/// What the save card binds to for Log on OK (issue #113): a source of OK
/// presses that were handled, whichever way they arrived.
///
/// Over a USB cable that is `UsbOkLogger`, which finds the presses itself in
/// the SOLO's stream. Over the ESP32 bridge it is `BridgeOkHandler`, which
/// gets them as records the bridge made. Both ask [OkLogger.setupProvider]
/// for the card's setup once per press and report each press on
/// [OkLogger.results].
///
/// Pure Dart.
library;

import 'bridge/bridge_protocol.dart';
import 'bridge/record_to_analysis.dart';

/// What the diver set up for the next OK, and how many labels to print.
typedef OkSetup = ({LogOnOkSetup setup, int copies});

/// The setup used when the screen has none to give: [LogOnOkSetup] with its
/// defaults and one copy. The reading is still saved, flagged for sign-off,
/// and nothing prints.
const OkSetup kNoOkSetup = (setup: LogOnOkSetup(), copies: 1);

/// How one OK press went, for the screen and the save card.
class OkLogResult {
  const OkLogResult({
    required this.code,
    required this.text,
    required this.analysisId,
    required this.complete,
    this.setupUsed,
    this.alreadySaved = false,
  });

  /// The feedback: printed, saved, check, skipped or error.
  final FeedbackCode code;

  /// The feedback text, ASCII and at most [kFeedbackTextMax] characters
  /// (`EAN32`, `MISMATCH`, `NO NAME SET`, `PRINT FAILED`, ...).
  final String text;

  /// The id of the saved row; null when nothing was saved.
  final String? analysisId;

  /// The row was saved with `needs_signoff = 0`: nothing is left for the
  /// diver to do (and the label printed, if a print was wanted).
  final bool complete;

  /// The setup this press used: what the setup provider gave when the press
  /// was handled. Presses are handled one after the other, so a result can
  /// arrive after the provider was asked again for the next press; the card
  /// goes by this, not by what the provider gives now, to see which of its
  /// fields this press took. Null when the press never got as far as the
  /// setup (a failed timer tick).
  final OkSetup? setupUsed;

  /// A row with this press's id was there already, so nothing was written
  /// and nothing printed. Over the bridge that is a record delivered again
  /// after its ACK was lost; it is ACKed again.
  final bool alreadySaved;

  @override
  String toString() =>
      'OkLogResult($code, "$text", id: $analysisId, complete: $complete'
      '${alreadySaved ? ', already saved' : ''})';
}

/// A source of handled OK presses; see the library comment.
abstract class OkLogger {
  /// One event per OK press that was handled, also when it failed.
  /// Broadcast.
  Stream<OkLogResult> get results;

  /// The setup of the save card, asked for when a press is handled. Null, or
  /// a provider that throws, means [kNoOkSetup].
  OkSetup Function()? setupProvider;
}
