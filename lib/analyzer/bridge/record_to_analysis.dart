/// Turns one record from the SOLO bridge into a gas analysis (issue #113).
///
/// When the diver presses OK on the SOLO, the bridge sends the held line and
/// the last 30 s of lines. [recordToAnalysis] decides everything about that
/// record: save or skip, stable or not, which of the diver's setup fields
/// apply, whether a label may print from the diver's pocket, and the text
/// the bridge screen shows. It is the safety core of Log on OK: a wrong
/// "print" decision puts a wrong label on a cylinder, so the rules are
/// deliberately boring and each one has a test.
///
/// The OK press is the diver's confirmation (decision 18): the reading does
/// not have to be stable, and a desired mix is optional. Stability is still
/// worked out and stored on the analysis, it just does not gate anything.
///
/// Pure Dart: no Flutter, no I/O. The decision order is spec section 5,
/// `docs/superpowers/specs/2026-11-03-background-gas-logging-design.md`.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';

import '../../analysis/gas_naming.dart';
import '../../analysis/mix_match.dart';
import '../../analysis/open_blend_match.dart';
import '../../analysis/standard_mix_pick.dart';
import '../../data/models/gas_analysis.dart';
import '../../data/models/open_blend.dart';
import '../protocol/solo_line_parser.dart';
import '../stability.dart';
import 'bridge_protocol.dart';

/// How old a record may be, by the bridge's own clock, and still count as
/// live: the diver is still standing at the analyzer, so what they set up
/// belongs to this cylinder.
const Duration kLiveRecordMaxAge = Duration(seconds: 30);

/// The diver's O2 reading is room air: O2 within the air band and no helium
/// (below the helium noise floor; a negative reading is noise too). Room air
/// is a calibration check, not a fill, so it is not logged.
bool isRoomAir(double o2Percent, double hePercent) =>
    o2Percent >= kAirO2MinPercent &&
    o2Percent <= kAirO2MaxPercent &&
    hePercent < kHeliumNoiseFloorPercent;

/// What the diver set up before pressing OK (the setup card). Used only for
/// a live record; see [recordToAnalysis].
class LogOnOkSetup {
  const LogOnOkSetup({
    this.analysedBy,
    this.desiredMix,
    this.tappedRole,
    this.cylinderRole,
    this.autoPickMix = false,
    this.openBlends = const [],
    this.blendChoice = const AutoBlend(),
    this.residual = false,
    this.analysedFor,
    this.printOnOk = false,
    this.printerConfigured = false,
    this.cylinderId,
    this.fillPressureBar,
    this.notes,
    this.modPpo2s = const [],
  });

  final String? analysedBy;
  final DesiredMix? desiredMix;

  /// The role the diver tapped; it beats the blend's and the cylinder's.
  final GasRole? tappedRole;

  /// The picked cylinder's known role. Null means follow the blend, else
  /// the mix: see [gasRoleForMix].
  final GasRole? cylinderRole;

  /// True while the diver has not picked or cleared a mix: each press then
  /// gets the nearest standard mix of its own held reading ([pickDesiredMix]).
  final bool autoPickMix;

  /// The open blends a press may close (issue #112), oldest first. Matched
  /// with [blendForAnalysis], like every other save path.
  final List<OpenBlend> openBlends;

  /// What the diver chose for the blend a press closes.
  final BlendChoice blendChoice;

  /// "Residual analysis" is on: the press saves a residual, with no desired
  /// mix, no label and no blend closed.
  final bool residual;
  final String? analysedFor;

  /// The diver wants a label printed on OK.
  final bool printOnOk;

  /// A label printer is set up and can be used.
  final bool printerConfigured;
  final String? cylinderId;
  final double? fillPressureBar;
  final String? notes;

  /// The ppO2s the MOD depths are worked out at. Always applied, also to a
  /// late record: they are a preference, not a statement about a cylinder.
  final List<double> modPpo2s;
}

/// The bridge's boot counter and uptime from its latest HELLO or ST. With a
/// record's own `boot` and `upMs` it dates the record and tells whether it is
/// still live.
class BridgeClock {
  const BridgeClock({required this.boot, required this.upMs});

  final int boot;
  final int upMs;
}

/// What to do with one record.
sealed class RecordOutcome {
  const RecordOutcome(this.rid, this.feedback, this.feedbackText);

  /// The record id; the app answers `ACK <rid>` and `FB <rid> ...`.
  final String rid;

  /// The result shown on the bridge screen. [feedbackText] is ASCII and at
  /// most [kFeedbackTextMax] characters (the bridge LCD font is ASCII).
  final FeedbackCode feedback;
  final String feedbackText;
}

/// Nothing to save: there is no reading, or it is room air. The record is
/// still acknowledged, then the feedback is sent.
class SkipRecord extends RecordOutcome {
  const SkipRecord(super.rid, super.feedback, super.feedbackText);
}

/// Save [analysis] under [rowId].
class SaveRecord extends RecordOutcome {
  const SaveRecord({
    required String rid,
    required this.rowId,
    required this.analysis,
    required this.printLabel,
    required this.live,
    this.blendToClose,
    required FeedbackCode feedback,
    required String feedbackText,
  }) : super(rid, feedback, feedbackText);

  /// The row id, [bridgeRowId] of the bridge and the record: saving the same
  /// record twice (the bridge resends until it is acknowledged) writes the
  /// same row.
  final String rowId;

  /// [NewGasAnalysis.needsSignoff] is already decided: true while a print is
  /// pending, so a failed print leaves the entry flagged.
  final NewGasAnalysis analysis;

  /// Try to print the label after the save, and clear the sign-off flag
  /// when it succeeds.
  final bool printLabel;

  /// The record was live, so the setup was used, the per-cylinder values
  /// (cylinder, fill pressure, notes) among it. Only a save that is complete
  /// (not [NewGasAnalysis.needsSignoff]) uses them up: the caller clears them
  /// then, and not for an entry that still needs sign-off, because OK on the
  /// same cylinder again needs them.
  final bool live;

  /// The open blend this save closes once it is complete, or null (issue
  /// #112). Never set for a late record or a residual.
  final OpenBlend? blendToClose;
}

/// Decides what to do with [record], in this order (spec section 5):
///
///  1. No usable reading at the hold (no O2, a sensor error, O2 of zero):
///     skip with `NO READING`.
///  2. Room air: skip with `AIR - NOT LOGGED`. A negative He is read as 0.
///  3. Stable: the 30 s window and the held line, fed to a fresh
///     [StabilityDetector] with their real spacing.
///  4. `analysedAt`: the moment of the OK, from the bridge's uptime when its
///     boot is [clock]'s, else the bridge's wall time, else the SOLO's own
///     clock, else [now] with a note.
///  5. Live: the bridge had a phone, the boot is the same, the record is at
///     most [kLiveRecordMaxAge] old, and the analyzer screen is open or a
///     session runs ([active]).
///  6. The setup applies only to a live record. A late record is saved as
///     bailout with no name, mix, cylinder, pressure or notes; only
///     [LogOnOkSetup.modPpo2s] always applies. The desired mix is the
///     diver's pick, else (with [LogOnOkSetup.autoPickMix]) the nearest
///     standard mix of this record's own held reading, only ever a match or
///     orange. A live record also matches an open blend
///     ([blendForAnalysis]); its target is then the desired mix and it is
///     the [SaveRecord.blendToClose]. A diver who cleared the mix on
///     purpose (no pick, no mix) gets no blend by reading. A residual has
///     no desired mix, no print and no blend. The role is the tapped one,
///     else the blend's, else the cylinder's, else follows the mix (or the
///     reading when there is none).
///  7. The desired mix is graded against the measured gas.
///  8. Print only if live, the diver asked for it, a printer exists, there
///     is a name, and either there is no desired mix (the label then shows
///     the analysed mix) or the grade against it is a match or orange.
///     Stability is not part of it.
///  9. The entry needs sign-off if a print is pending (until it succeeds),
///     or it is late, has no name, or is a red or hard mismatch against a
///     desired mix. No desired mix and an unstable reading do not flag it.
/// 10. The feedback, the first that fits: printed, mismatch, late, no name,
///     else saved with the analysed mix.
/// 11. The analysis itself, carrying [source] as its capture source
///     ([CaptureSource.bridgeOk] for the ESP32 bridge, [CaptureSource.usbOk]
///     for the app's own hold detector on a USB cable).
RecordOutcome recordToAnalysis({
  required BridgeRecord record,
  required String bridgeId,
  required LogOnOkSetup setup,
  required BridgeClock clock,
  required DateTime now,
  required bool active,
  CaptureSource source = CaptureSource.bridgeOk,
}) {
  final rid = record.rid;

  // 1. The reading at the hold.
  final reading = parseSoloLine(record.heldLine);
  final o2 = reading?.o2;
  final heRaw = reading?.he ?? 0.0;
  if (reading == null ||
      o2 == null ||
      !o2.isFinite ||
      o2 <= 0 ||
      !heRaw.isFinite) {
    return SkipRecord(rid, FeedbackCode.error, 'NO READING');
  }

  // 2. Room air.
  final he = math.max(heRaw, 0.0);
  if (isRoomAir(o2, he)) {
    return SkipRecord(rid, FeedbackCode.skipped, 'AIR - NOT LOGGED');
  }

  // 3. Stability, on the real spacing of the lines. The window's first line
  // is time zero; the held line comes last, at offset 0.
  final detector = StabilityDetector();
  final firstOffset = record.window.isEmpty ? 0 : record.window.first.offsetMs;
  for (final w in record.window) {
    final r = parseSoloLine(w.line);
    if (r == null) continue;
    detector.add(
      r.o2,
      r.he,
      elapsed: Duration(milliseconds: w.offsetMs - firstOffset),
    );
  }
  final stable =
      detector.add(
        o2,
        heRaw,
        elapsed: Duration(milliseconds: 0 - firstOffset),
      ) ==
      ReadingStability.stable;

  // 4. When the OK was pressed. A record that arrives after the bridge's
  // latest ST (clock behind the record) is not older than zero.
  final sameBoot = record.boot == clock.boot;
  final ageMs = clock.upMs - record.upMs;
  final DateTime analysedAt;
  String? timeNote;
  if (sameBoot) {
    analysedAt = now.subtract(Duration(milliseconds: math.max(0, ageMs)));
  } else if (record.wallMs != 0) {
    analysedAt = DateTime.fromMillisecondsSinceEpoch(record.wallMs);
  } else if (reading.deviceTime != null) {
    analysedAt = reading.deviceTime!;
  } else {
    analysedAt = now;
    timeNote =
        'Time of OK unknown; delivered '
        '${DateFormat('yyyy-MM-dd HH:mm', 'en_US').format(now)}';
  }

  // 5. Live.
  final live =
      record.live &&
      sameBoot &&
      ageMs <= kLiveRecordMaxAge.inMilliseconds &&
      active;

  // 6. The setup, for a live record only.
  final analysedBy = live ? _blankToNull(setup.analysedBy) : null;
  final residual = live && setup.residual;
  final OpenBlend? blend;
  if (!live || residual) {
    blend = null;
  } else if (setup.desiredMix == null &&
      !setup.autoPickMix &&
      setup.blendChoice is AutoBlend) {
    // The diver cleared the mix on purpose: no match by reading.
    blend = null;
  } else {
    blend = blendForAnalysis(
      o2Percent: o2,
      hePercent: he,
      choice: setup.blendChoice,
      chosenMix: setup.desiredMix,
      residual: false,
      open: setup.openBlends,
    );
  }
  // Without a blend the pick is the nearest standard mix, which is also what
  // "None" asks for.
  final desiredMix = !live || residual
      ? null
      : (blend?.target ??
            setup.desiredMix ??
            (setup.autoPickMix
                ? pickDesiredMix(o2Percent: o2, hePercent: he)?.mix
                : null));
  final gasRole = live
      ? (setup.tappedRole ??
            blend?.role ??
            setup.cylinderRole ??
            gasRoleForMix(desiredMix?.o2Percent.toDouble() ?? o2))
      : GasRole.bailout;
  final analysedFor = live ? setup.analysedFor : null;
  final cylinderId = live ? setup.cylinderId : null;
  final fillPressureBar = live ? setup.fillPressureBar : null;
  final setupNotes = live ? _blankToNull(setup.notes) : null;

  // 7. The grade.
  final level = desiredMix == null
      ? null
      : gradeMix(
          o2Percent: o2,
          hePercent: he,
          targetO2Percent: desiredMix.o2Percent,
          targetHePercent: desiredMix.hePercent,
        ).level;
  final matches = level == MixMatchLevel.match || level == MixMatchLevel.orange;
  final mismatch = level == MixMatchLevel.red || level == MixMatchLevel.hard;
  final named = analysedBy != null;

  // 8. A label from the diver's pocket. The OK press is the confirmation, so
  // stability is not asked for; a desired mix is checked only when there is
  // one (red and hard mean no print, nobody sees the colour in a pocket).
  final printLabel =
      live &&
      !residual &&
      setup.printOnOk &&
      setup.printerConfigured &&
      named &&
      (desiredMix == null || matches);

  // 9. Sign-off.
  final needsSignoff = printLabel || !live || !named || mismatch;

  // 10. Feedback.
  final mix = gasMixName(o2, he);
  final (FeedbackCode, String) feedback = printLabel
      ? (FeedbackCode.printed, mix)
      : mismatch
      ? (FeedbackCode.check, 'MISMATCH')
      : !live
      ? (FeedbackCode.saved, 'SIGN OFF LATER')
      : !named
      ? (FeedbackCode.saved, 'NO NAME SET')
      : (FeedbackCode.saved, mix);

  // 11. The analysis.
  final notes = [?setupNotes, ?timeNote].join('\n');
  final temp = reading.tempC;
  final baro = reading.baroHpa;
  return SaveRecord(
    rid: rid,
    rowId: bridgeRowId(bridgeId, rid),
    analysis: NewGasAnalysis(
      cylinderId: cylinderId,
      analysedBy: analysedBy,
      analysedAt: analysedAt,
      o2Percent: o2,
      hePercent: he,
      fillPressureBar: fillPressureBar,
      tempC: temp != null && temp.isFinite ? temp : null,
      baroHpa: baro != null && baro.isFinite ? baro : null,
      modPpo2s: setup.modPpo2s,
      stable: stable,
      notes: notes.isEmpty ? null : notes,
      desiredMix: desiredMix,
      gasRole: gasRole,
      needsSignoff: needsSignoff,
      captureSource: source,
      bridgeRecordId: '$bridgeId/$rid',
      analysedFor: analysedFor,
      isResidual: residual,
    ),
    printLabel: printLabel,
    live: live,
    blendToClose: blend,
    feedback: feedback.$1,
    feedbackText: feedback.$2,
  );
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s;

/// RFC 4122 URL namespace, `6ba7b811-9dad-11d1-80b4-00c04fd430c8`.
const List<int> _namespaceUrl = [
  0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, //
  0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
];

/// The row id for the analysis of one bridge record: a UUID v5 (SHA-1) in the
/// URL namespace of the name `anchorline-bridge:<bridgeId>/<rid>`, lowercase
/// and hyphenated. Deterministic, so a record that is delivered twice (the
/// bridge resends until it is acknowledged, and a phone may save it and die
/// before the ACK) lands on the same row instead of a second one.
String bridgeRowId(String bridgeId, String rid) {
  final digest = sha1.convert([
    ..._namespaceUrl,
    ...utf8.encode('anchorline-bridge:$bridgeId/$rid'),
  ]);
  final bytes = List<int>.of(digest.bytes.take(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) b.write('-');
    b.write(hex(i));
  }
  return b.toString();
}
