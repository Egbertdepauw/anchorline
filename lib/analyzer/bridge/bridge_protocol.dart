/// Wire protocol between the app and the ESP32 SOLO bridge (protocol v1).
///
/// Pure Dart: no Flutter, no I/O. The BLE link splits the Nordic UART stream
/// into lines and feeds each one to [parseBridgeMessage]; everything the app
/// sends goes through the `format*` functions. The message tables are in
/// `docs/superpowers/specs/2026-11-03-background-gas-logging-design.md`,
/// section 3.
///
/// The protocol is ASCII, one message per line. Parsing never throws:
/// anything that is not a well-formed v1 message becomes [BridgeUnknown].
///
/// Versioning: the builder may add messages and `key=value` fields, and the
/// parser ignores keys it does not know. Anything incompatible (a changed
/// meaning, a removed key, a new framing) must bump [kBridgeProtocolVersion]
/// and the `proto=` field of HELLO.
library;

/// The protocol version this file speaks (`proto=` in HELLO).
const int kBridgeProtocolVersion = 1;

/// The longest feedback text the bridge screen can show.
const int kFeedbackTextMax = 24;

// ---------------------------------------------------------------------------
// Bridge -> app
// ---------------------------------------------------------------------------

/// One parsed line from the bridge.
sealed class BridgeMessage {
  const BridgeMessage();
}

/// `HELLO proto= fw= bridge= epoch= boot= up= solo= rec= vbus= batt= pending=`
/// Sent on every connection.
class BridgeHello extends BridgeMessage {
  final int proto;
  final String fw;
  final String bridgeId;
  final String epoch;
  final int boot;
  final int upMs;
  final bool soloAttached;
  final bool recording;
  final bool vbusOn;
  final int batteryMv;
  final int pending;

  const BridgeHello({
    required this.proto,
    required this.fw,
    required this.bridgeId,
    required this.epoch,
    required this.boot,
    required this.upMs,
    required this.soloAttached,
    required this.recording,
    required this.vbusOn,
    required this.batteryMv,
    required this.pending,
  });
}

/// `ST solo= data= pending= batt= up=` Every 5 s and on change.
class BridgeStatus extends BridgeMessage {
  final bool soloAttached;
  final bool dataFlowing;
  final int pending;
  final int batteryMv;
  final int upMs;

  const BridgeStatus({
    required this.soloAttached,
    required this.dataFlowing,
    required this.pending,
    required this.batteryMv,
    required this.upMs,
  });
}

/// `L <raw SOLO line>` A live SOLO line, only while `LIVE ON`.
class BridgeLiveLine extends BridgeMessage {
  final String line;

  const BridgeLiveLine(this.line);
}

/// `REC <rid> boot= up= wall= live=` A record starts.
class BridgeRecordStart extends BridgeMessage {
  final String rid;
  final int boot;
  final int upMs;

  /// Wall time of the hold in epoch milliseconds, or 0 when the bridge had
  /// no wall time.
  final int wallMs;

  /// A phone was connected and subscribed at the moment of the hold.
  final bool live;

  const BridgeRecordStart({
    required this.rid,
    required this.boot,
    required this.upMs,
    required this.wallMs,
    required this.live,
  });
}

/// `W <offset-ms> <raw SOLO line>` One line of a record's window, oldest
/// first. Offsets are zero or negative, relative to the hold.
class BridgeWindowLine extends BridgeMessage {
  final int offsetMs;
  final String line;

  const BridgeWindowLine(this.offsetMs, this.line);
}

/// `H <raw SOLO line>` The held reading.
class BridgeHeldLine extends BridgeMessage {
  final String line;

  const BridgeHeldLine(this.line);
}

/// `END <rid>` The record is complete.
class BridgeRecordEnd extends BridgeMessage {
  final String rid;

  const BridgeRecordEnd(this.rid);
}

/// Anything else: unknown type, missing key, bad number or bad boolean.
class BridgeUnknown extends BridgeMessage {
  final String raw;

  const BridgeUnknown(this.raw);
}

/// Matches the line terminator the link may leave on a line.
final RegExp _trailingTerminators = RegExp(r'[\r\n]+$');

/// A plain unsigned decimal number. Stricter than [int.tryParse], which also
/// takes `0x10` and a leading `+`.
final RegExp _unsigned = RegExp(r'^\d+$');
final RegExp _signed = RegExp(r'^-?\d+$');

/// Parses one line from the bridge.
///
/// Never throws: unknown types, missing keys and bad numbers give
/// [BridgeUnknown]. A trailing CR or LF is dropped first. The first
/// space-separated token is the type and types are case-sensitive.
///
/// The payload of `L` and `H` is everything after the first space, and of
/// `W` everything after the second space, both verbatim (a SOLO line has
/// runs of spaces that must survive). Elsewhere, tokens split on single
/// spaces and `key=value` tokens split on the first `=`; keys the parser
/// does not know are ignored.
BridgeMessage parseBridgeMessage(String line) {
  final text = line.replaceAll(_trailingTerminators, '');
  final firstSpace = text.indexOf(' ');
  final type = firstSpace < 0 ? text : text.substring(0, firstSpace);
  final rest = firstSpace < 0 ? null : text.substring(firstSpace + 1);

  final BridgeMessage? parsed = switch (type) {
    'HELLO' => _parseHello(_keyValues(_tokens(rest))),
    'ST' => _parseStatus(_keyValues(_tokens(rest))),
    'L' => rest == null ? null : BridgeLiveLine(rest),
    'H' => rest == null ? null : BridgeHeldLine(rest),
    'W' => _parseWindowLine(rest),
    'REC' => _parseRecordStart(rest),
    'END' => _parseRecordEnd(rest),
    _ => null,
  };
  return parsed ?? BridgeUnknown(line);
}

BridgeHello? _parseHello(Map<String, String> kv) {
  final proto = _uint(kv['proto']);
  final fw = _text(kv['fw']);
  final bridgeId = _text(kv['bridge']);
  final epoch = _text(kv['epoch']);
  final boot = _uint(kv['boot']);
  final upMs = _uint(kv['up']);
  final solo = _flag(kv['solo']);
  final rec = _onOff(kv['rec']);
  final vbus = _onOff(kv['vbus']);
  final batt = _uint(kv['batt']);
  final pending = _uint(kv['pending']);
  if (proto == null ||
      fw == null ||
      bridgeId == null ||
      epoch == null ||
      boot == null ||
      upMs == null ||
      solo == null ||
      rec == null ||
      vbus == null ||
      batt == null ||
      pending == null) {
    return null;
  }
  return BridgeHello(
    proto: proto,
    fw: fw,
    bridgeId: bridgeId,
    epoch: epoch,
    boot: boot,
    upMs: upMs,
    soloAttached: solo,
    recording: rec,
    vbusOn: vbus,
    batteryMv: batt,
    pending: pending,
  );
}

BridgeStatus? _parseStatus(Map<String, String> kv) {
  final solo = _flag(kv['solo']);
  final data = _flag(kv['data']);
  final pending = _uint(kv['pending']);
  final batt = _uint(kv['batt']);
  final upMs = _uint(kv['up']);
  if (solo == null ||
      data == null ||
      pending == null ||
      batt == null ||
      upMs == null) {
    return null;
  }
  return BridgeStatus(
    soloAttached: solo,
    dataFlowing: data,
    pending: pending,
    batteryMv: batt,
    upMs: upMs,
  );
}

BridgeWindowLine? _parseWindowLine(String? rest) {
  if (rest == null) return null;
  final space = rest.indexOf(' ');
  if (space < 0) return null;
  final offset = _int(rest.substring(0, space));
  if (offset == null) return null;
  return BridgeWindowLine(offset, rest.substring(space + 1));
}

BridgeRecordStart? _parseRecordStart(String? rest) {
  if (rest == null) return null;
  final tokens = _tokens(rest);
  final rid = _rid(tokens.first);
  if (rid == null) return null;
  final kv = _keyValues(tokens.skip(1));
  final boot = _uint(kv['boot']);
  final upMs = _uint(kv['up']);
  final wallMs = _uint(kv['wall']);
  final live = _flag(kv['live']);
  if (boot == null || upMs == null || wallMs == null || live == null) {
    return null;
  }
  return BridgeRecordStart(
    rid: rid,
    boot: boot,
    upMs: upMs,
    wallMs: wallMs,
    live: live,
  );
}

BridgeRecordEnd? _parseRecordEnd(String? rest) {
  if (rest == null) return null;
  final rid = _rid(_tokens(rest).first);
  return rid == null ? null : BridgeRecordEnd(rid);
}

/// Splits the part of a line after the type on single spaces.
List<String> _tokens(String? rest) => rest == null ? const [] : rest.split(' ');

/// Splits `key=value` tokens on the first `=`. Tokens without a key or
/// without `=` are skipped. A repeated key keeps its first value.
Map<String, String> _keyValues(Iterable<String> tokens) {
  final result = <String, String>{};
  for (final token in tokens) {
    final eq = token.indexOf('=');
    if (eq <= 0) continue;
    result.putIfAbsent(token.substring(0, eq), () => token.substring(eq + 1));
  }
  return result;
}

/// A record id: a non-empty token that is not a `key=value` pair.
String? _rid(String token) =>
    token.isEmpty || token.contains('=') ? null : token;

String? _text(String? v) => v == null || v.isEmpty ? null : v;

int? _uint(String? v) =>
    v != null && _unsigned.hasMatch(v) ? int.tryParse(v) : null;

int? _int(String v) => _signed.hasMatch(v) ? int.tryParse(v) : null;

/// `0` / `1`.
bool? _flag(String? v) => switch (v) {
  '1' => true,
  '0' => false,
  _ => null,
};

/// `on` / `off`.
bool? _onOff(String? v) => switch (v) {
  'on' => true,
  'off' => false,
  _ => null,
};

// ---------------------------------------------------------------------------
// App -> bridge
// ---------------------------------------------------------------------------

/// The live state shown on the bridge screen. Wire: `settling`, `stable`,
/// `sensor_error`, `air`.
enum BridgeLiveState {
  settling('settling'),
  stable('stable'),
  sensorError('sensor_error'),
  air('air');

  const BridgeLiveState(this.wire);

  final String wire;
}

/// The result shown on the bridge screen after a record. Wire: the
/// lowercase enum name.
enum FeedbackCode { printed, saved, check, skipped, error }

final RegExp _lineBreaks = RegExp(r'\r\n|\r|\n');

/// Free text on the wire must not contain a line break, or the bridge would
/// read it as two messages.
String _oneLine(String s) => s.replaceAll(_lineBreaks, ' ');

// The format functions each return one line WITHOUT the trailing '\n'; the
// link adds it.

/// `TIME <epoch-ms>`. Sent first on every connection.
String formatTime(DateTime now) => 'TIME ${now.millisecondsSinceEpoch}';

/// `LIVE ON` / `LIVE OFF`.
String formatLive(bool on) => on ? 'LIVE ON' : 'LIVE OFF';

/// `STATE <code> [<mix>]`. A null or empty [mix] is left out.
String formatState(BridgeLiveState s, {String? mix}) {
  if (mix == null || mix.isEmpty) return 'STATE ${s.wire}';
  return 'STATE ${s.wire} ${_oneLine(mix)}';
}

/// `ACK <rid>`.
String formatAck(String rid) => 'ACK $rid';

/// `FB <rid> <code> <text>`. Line breaks in [text] become spaces and the
/// text is cut to [kFeedbackTextMax] characters (the bridge LCD is ASCII).
String formatFeedback(String rid, FeedbackCode c, String text) {
  var t = _oneLine(text);
  if (t.length > kFeedbackTextMax) t = t.substring(0, kFeedbackTextMax);
  return 'FB $rid ${c.name} $t';
}

/// `CFG rec=<on|off> vbus=<on|off>`.
String formatConfig({required bool recording, required bool vbusOn}) =>
    'CFG rec=${recording ? 'on' : 'off'} vbus=${vbusOn ? 'on' : 'off'}';

// ---------------------------------------------------------------------------
// Record assembly
// ---------------------------------------------------------------------------

/// One complete record: the start line, its window and the held line.
class BridgeRecord {
  final String rid;
  final int boot;
  final int upMs;
  final int wallMs;
  final bool live;

  /// Oldest first, offsets zero or negative.
  final List<BridgeWindowLine> window;

  /// The raw SOLO line of the held reading. Empty when the bridge sent `END`
  /// without an `H` line; the reader treats that as "no reading".
  final String heldLine;

  const BridgeRecord({
    required this.rid,
    required this.boot,
    required this.upMs,
    required this.wallMs,
    required this.live,
    required this.window,
    required this.heldLine,
  });
}

/// A record that has started but not ended.
class _OpenRecord {
  final BridgeRecordStart start;
  final List<BridgeWindowLine> window = [];

  /// Stays empty until an `H` line arrives.
  String heldLine = '';

  _OpenRecord(this.start);
}

/// Feeds parsed messages and returns a complete record on its `END`.
///
/// A record is `REC`, any number of `W` lines, one `H` line and `END`. The
/// assembler keeps one open record at a time and drops it when
///
///  * a new `REC` arrives (the bridge started over, so the old one is
///    partial), or
///  * an `END` carries another rid.
///
/// An `END` for the open record without an `H` line still returns the
/// record, with an empty `heldLine`. The bridge sends pending records one at
/// a time and the next only after the `ACK` for this one, so a record that
/// is never returned would never be confirmed and would block every later
/// record. The reader parses the empty line as "no reading", answers `ACK`
/// and `FB <rid> error NO READING`, and the queue moves on.
///
/// Live lines, status and other messages are ignored, also in the middle of
/// a record. `W` and `H` outside a record are ignored.
class BridgeRecordAssembler {
  _OpenRecord? _open;

  /// Returns the finished record when [m] is the matching `END`, else null.
  BridgeRecord? add(BridgeMessage m) {
    switch (m) {
      case BridgeRecordStart():
        _open = _OpenRecord(m);
        return null;
      case BridgeWindowLine():
        _open?.window.add(m);
        return null;
      case BridgeHeldLine():
        _open?.heldLine = m.line;
        return null;
      case BridgeRecordEnd():
        final open = _open;
        _open = null;
        if (open == null || open.start.rid != m.rid) return null;
        final s = open.start;
        return BridgeRecord(
          rid: s.rid,
          boot: s.boot,
          upMs: s.upMs,
          wallMs: s.wallMs,
          live: s.live,
          window: List.unmodifiable(open.window),
          heldLine: open.heldLine,
        );
      case BridgeHello() ||
          BridgeStatus() ||
          BridgeLiveLine() ||
          BridgeUnknown():
        return null;
    }
  }
}
