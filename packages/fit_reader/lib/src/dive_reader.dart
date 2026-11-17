import 'dart:typed_data';

import 'container.dart';
import 'messages.dart';

enum FitFileKind { dive, apnea, otherActivity, notActivity }

bool _isDiveSport(int? sport) => sport == FitSportKind.diving;

bool _isApnea(int? sub) =>
    sub == FitSportKind.apnea || sub == FitSportKind.apneaHunting;

/// Decides what a FIT file holds by decoding only up to its first sport
/// message, or failing that its first session. The file CRC is therefore
/// not checked here. Throws [FitFormatException] for an unreadable file.
FitFileKind classifyFit(Uint8List bytes) {
  int? fileType;
  FitMessage? marker;
  decodeFit(
    bytes,
    stopAfter: (m) {
      if (m.global == FitMesg.fileId) {
        fileType = m.intField(FitFileIdField.type);
        return fileType != fitFileTypeActivity;
      }
      if (m.global == FitMesg.sport || m.global == FitMesg.session) {
        marker = m;
        return true;
      }
      return false;
    },
  );
  if (fileType != fitFileTypeActivity) return FitFileKind.notActivity;
  final m = marker;
  if (m == null) return FitFileKind.otherActivity;
  final isSport = m.global == FitMesg.sport;
  final sport = m.intField(isSport ? FitSport.sport : FitSession.sport);
  final sub = m.intField(isSport ? FitSport.subSport : FitSession.subSport);
  if (!_isDiveSport(sport)) return FitFileKind.otherActivity;
  return _isApnea(sub) ? FitFileKind.apnea : FitFileKind.dive;
}

class FitFileId {
  final int manufacturer;
  final int? product;

  /// 0 when the file has none.
  final int serial;

  /// FIT seconds; 0 when absent.
  final int timeCreated;
  final String? productName;

  const FitFileId({
    required this.manufacturer,
    required this.product,
    required this.serial,
    required this.timeCreated,
    required this.productName,
  });
}

/// One dive session with the messages that belong to it.
class FitDiveSession {
  /// 0-based position of this session's message among all session messages
  /// in the file, apnea and other sports included. Depends only on the file.
  final int fileSessionIndex;

  /// FIT seconds.
  final int start;
  final int end;

  /// Local time minus UTC, minutes, when the file says.
  final int? offsetMinutes;
  final int? subSport;

  /// The summary message that references the session, if any.
  final FitMessage? summary;
  final FitMessage? diveSettings;

  /// Main device software version, hundredths.
  final int? firmware;
  final List<FitMessage> records;
  final List<FitMessage> events;
  final List<FitMessage> tankUpdates;
  final List<FitMessage> diveGases;
  final List<FitMessage> sensorProfiles;
  final List<FitMessage> tankSummaries;

  const FitDiveSession({
    required this.fileSessionIndex,
    required this.start,
    required this.end,
    required this.offsetMinutes,
    required this.subSport,
    required this.summary,
    required this.diveSettings,
    required this.firmware,
    required this.records,
    required this.events,
    required this.tankUpdates,
    required this.diveGases,
    required this.sensorProfiles,
    required this.tankSummaries,
  });

  int? get diveNumber => summary?.intField(FitDiveSummary.diveNumber);

  /// Millimetres.
  int? get maxDepthMm => summary?.intField(FitDiveSummary.maxDepth);
}

class FitDiveFile {
  final FitFileId id;
  final List<FitDiveSession> sessions;
  const FitDiveFile({required this.id, required this.sessions});
}

class _Span {
  final int index; // position in the session list
  final int messagePos;
  final int start;
  final int end;
  final int? subSport;
  const _Span(this.index, this.messagePos, this.start, this.end, this.subSport);
}

class _Bucket {
  final records = <FitMessage>[];
  final events = <FitMessage>[];
  final tankUpdates = <FitMessage>[];
  final diveGases = <FitMessage>[];
  final sensorProfiles = <FitMessage>[];
  final tankSummaries = <FitMessage>[];
  final summaries = <FitMessage>[];
  final settings = <FitMessage>[];
}

int? _signed32(int? v) =>
    v == null ? null : (v >= 0x80000000 ? v - (1 << 32) : v);

/// Reads the dive sessions out of a FIT file. The file CRC is checked.
/// Apnea sessions and sessions of other sports are left out.
///
/// Timestamped messages go to the dive session whose time span holds them.
/// Messages without a timestamp (gases, settings, sensor profiles) go to the
/// session that follows them in the file, or to the last one when they come
/// after every session. A session that gets no gases, settings or sensor
/// profiles that way inherits the latest earlier ones.
FitDiveFile readFitDives(Uint8List bytes) {
  final file = decodeFit(bytes);
  final msgs = file.messages;

  FitMessage? first(int global) {
    for (final m in msgs) {
      if (m.global == global) return m;
    }
    return null;
  }

  final idMsg = first(FitMesg.fileId);
  final id = FitFileId(
    manufacturer: idMsg?.intField(FitFileIdField.manufacturer) ?? 0,
    product: idMsg?.intField(FitFileIdField.product),
    serial: idMsg?.intField(FitFileIdField.serial) ?? 0,
    timeCreated: idMsg?.intField(FitFileIdField.timeCreated) ?? 0,
    productName: idMsg?.stringField(FitFileIdField.productName),
  );

  // The file-level sport stands in for a session that does not say.
  final sportMsg = first(FitMesg.sport);

  // The activity gives the offset exactly; device settings only roughly.
  int? offsetSeconds;
  final activity = first(FitMesg.activity);
  final local = activity?.intField(FitActivity.localTimestamp);
  final activityTs = activity?.timestamp;
  if (local != null && activityTs != null) {
    offsetSeconds = local - activityTs;
  } else {
    // A zero here is not trusted: such files carry the real value elsewhere.
    final t = _signed32(
      first(FitMesg.deviceSettings)?.intField(FitDeviceSettings.timeOffset),
    );
    if (t != null && t != 0) offsetSeconds = t;
  }
  final offsetMinutes = offsetSeconds == null
      ? null
      : (offsetSeconds / 60).round();

  int? firmware;
  for (final m in msgs) {
    if (m.global == FitMesg.deviceInfo &&
        m.intField(FitDeviceInfo.deviceIndex) == 0) {
      firmware = m.intField(FitDeviceInfo.softwareVersion);
      break;
    }
  }

  // Every session message, in raw order; only the dive ones get a span.
  final spans = <_Span>[];
  final sessionPos = <int>[];
  var fileSessionIndex = 0;
  final indexOfSpan = <int>[];
  for (var p = 0; p < msgs.length; p++) {
    final m = msgs[p];
    if (m.global != FitMesg.session) continue;
    sessionPos.add(p);
    final myIndex = fileSessionIndex++;
    final sport =
        m.intField(FitSession.sport) ?? sportMsg?.intField(FitSport.sport);
    final sub =
        m.intField(FitSession.subSport) ??
        sportMsg?.intField(FitSport.subSport);
    if (!_isDiveSport(sport) || _isApnea(sub)) continue;
    final elapsedMs = m.intField(FitSession.totalElapsedTime);
    final ts = m.timestamp;
    final start =
        m.intField(FitSession.startTime) ??
        (ts != null && elapsedMs != null ? ts - elapsedMs ~/ 1000 : null);
    final end =
        ts ??
        (start != null && elapsedMs != null ? start + elapsedMs ~/ 1000 : null);
    if (start == null || end == null) continue;
    spans.add(_Span(spans.length, p, start, end, sub));
    indexOfSpan.add(myIndex);
  }

  final buckets = [for (var _ in spans) _Bucket()];

  /// The span index (into [spans]) a message belongs to, or null.
  int? ownerOf(int pos, FitMessage m) {
    final ts = m.timestamp;
    if (ts != null) {
      for (final s in spans) {
        if (ts >= s.start && ts <= s.end) return s.index;
      }
      return null;
    }
    // Position: the first session message after it, else the last one,
    // among ALL sessions; a message owned by a non-dive session is dropped.
    if (sessionPos.isEmpty) return null;
    var owner = sessionPos.length - 1;
    for (var k = 0; k < sessionPos.length; k++) {
      if (sessionPos[k] > pos) {
        owner = k;
        break;
      }
    }
    final at = indexOfSpan.indexOf(owner);
    return at < 0 ? null : at;
  }

  for (var p = 0; p < msgs.length; p++) {
    final m = msgs[p];
    final List<FitMessage> Function(_Bucket)? pick = switch (m.global) {
      FitMesg.record => (b) => b.records,
      FitMesg.event => (b) => b.events,
      FitMesg.tankUpdate => (b) => b.tankUpdates,
      FitMesg.diveGas => (b) => b.diveGases,
      FitMesg.sensorProfile => (b) => b.sensorProfiles,
      FitMesg.tankSummary => (b) => b.tankSummaries,
      FitMesg.diveSettings => (b) => b.settings,
      FitMesg.diveSummary
          when m.intField(FitDiveSummary.referenceMessage) == FitMesg.session =>
        (b) => b.summaries,
      _ => null,
    };
    if (pick == null) continue;
    final owner = ownerOf(p, m);
    if (owner != null) pick(buckets[owner]).add(m);
  }

  final sessions = <FitDiveSession>[];
  for (var i = 0; i < spans.length; i++) {
    final b = buckets[i];
    List<FitMessage> inherited(List<FitMessage> Function(_Bucket) pick) {
      for (var j = i; j >= 0; j--) {
        final l = pick(buckets[j]);
        if (l.isNotEmpty) return l;
      }
      return const [];
    }

    final settings = inherited((b) => b.settings);
    sessions.add(
      FitDiveSession(
        fileSessionIndex: indexOfSpan[i],
        start: spans[i].start,
        end: spans[i].end,
        offsetMinutes: offsetMinutes,
        subSport: spans[i].subSport,
        summary: b.summaries.isEmpty ? null : b.summaries.first,
        diveSettings: settings.isEmpty ? null : settings.first,
        firmware: firmware,
        records: b.records,
        events: b.events,
        tankUpdates: b.tankUpdates,
        diveGases: inherited((b) => b.diveGases),
        sensorProfiles: inherited((b) => b.sensorProfiles),
        tankSummaries: b.tankSummaries,
      ),
    );
  }
  return FitDiveFile(id: id, sessions: sessions);
}
