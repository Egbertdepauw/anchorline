// The Petrel 3 trace, and TraceLink: a LibdcBleLink that plays a dive
// computer from a recording.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';

/// The only real download we hold: Subsurface's log of 8 dives from a
/// Petrel 3, read in place (`test/fixtures/raw/` at the repository root).
const petrelTracePath = '../../test/fixtures/raw/subsurface2.combined.txt';

LibdcRecording rawPetrelTrace() =>
    LibdcRecording.parse(File(petrelTracePath).readAsStringSync());

/// The serial number the Petrel 3 in the trace reports.
const petrelSerial = 3096855012;

/// Bytes of a hex string like `01 00 ff`.
Uint8List hexBytes(String hex) => Uint8List.fromList([
  for (final t in hex.trim().split(' ')) int.parse(t, radix: 16),
]);

/// The trace's third exchange is RDBI 0x8050 (hardware id), which
/// Subsurface's libdivecomputer fork reads. Upstream at the pin reads RDBI
/// 0x8060 (model) there instead, so a strict replay of the raw trace stops at
/// write 2. This swaps that one exchange for the model request and a model
/// answer of 10 (Petrel 3, `PETREL3` in shearwater_common.h). Everything else
/// is the trace as recorded.
final rdbiHardwareRequest = hexBytes('01 00 ff 01 04 00 22 80 50 c0');
final rdbiModelRequest = hexBytes('01 00 ff 01 04 00 22 80 60 c0');
final rdbiModelAnswer = hexBytes('01 00 01 ff 05 00 62 80 60 0a c0');

LibdcRecording petrelTrace() {
  final raw = rawPetrelTrace();
  final events = [...raw.events];
  final i = events.indexWhere(
    (e) => e.kind == 'W' && _equal(e.payload, rdbiHardwareRequest),
  );
  if (i < 0 || events[i + 1].kind != 'R') {
    throw StateError('the trace has no hardware id exchange to swap');
  }
  events[i] = LibdcIoEvent('W', rdbiModelRequest);
  events[i + 1] = LibdcIoEvent('R', rdbiModelAnswer);
  return LibdcRecording(header: raw.header, events: events);
}

/// libdivecomputer's own Petrel 3 descriptor. Test-only: matchBle never
/// offers a Shearwater.
LibdcDescriptor petrel3() => Libdc.descriptors().singleWhere(
  (d) => d.vendor == 'Shearwater' && d.product == 'Petrel 3',
);

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Answers each write with the `R` packets recorded after the matching `W`,
/// one notification per packet. A write that is not the next `W` of the
/// trace throws, as a link whose computer never answers would.
///
/// With [skipAhead], a write that is not the next `W` is answered from the
/// next identical `W` further on, the way the computer answers a request by
/// what it asks for. For a download that asks for less than the trace holds
/// (a fingerprint skips the trace's later manifest pages). The C layer's
/// replay never does this.
class TraceLink implements LibdcBleLink {
  TraceLink(
    LibdcRecording trace, {
    this.advertisedName = 'Petrel 3',
    this.onWrite,
    this.skipAhead = false,
  }) : _events = [
         for (final e in trace.events)
           if (e.kind == 'W' || e.kind == 'R') e,
       ];

  @override
  final String advertisedName;

  /// Runs before write [index] of the trace is answered; the answer waits
  /// for what it returns. [index] counts the trace's writes from 0.
  final FutureOr<void> Function(int index, Uint8List bytes)? onWrite;

  final bool skipAhead;

  final List<LibdcIoEvent> _events;
  final _notifications = StreamController<Uint8List>();
  final _disconnected = Completer<void>();
  var _position = 0;
  var _writeIndex = 0;

  /// Every write that reached the link, in order, matching or not.
  final received = <Uint8List>[];

  /// How many of the trace's writes were matched.
  int get matchedWrites => _writeIndex;

  /// Whether the download still listens to the notifications.
  bool get hasListener => _notifications.hasListener;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Future<void> get disconnected => _disconnected.future;

  bool get isDropped => _disconnected.isCompleted;

  /// The connection drops.
  void drop() {
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  /// A notification out of turn.
  void push(Uint8List packet) => _notifications.add(packet);

  @override
  Future<void> write(Uint8List bytes) async {
    received.add(Uint8List.fromList(bytes));
    if (isDropped) throw StateError('the link is down');
    bool matches(int i) =>
        _events[i].kind == 'W' && _equal(_events[i].payload, bytes);
    if (_position >= _events.length || !matches(_position)) {
      var next = -1;
      if (skipAhead) {
        for (var i = _position; i < _events.length; i++) {
          if (matches(i)) {
            next = i;
            break;
          }
        }
      }
      if (next < 0) throw StateError('write $_writeIndex is not in the trace');
      _writeIndex += _events
          .sublist(_position, next)
          .where((e) => e.kind == 'W')
          .length;
      _position = next;
    }
    final index = _writeIndex++;
    _position++;
    final answers = <Uint8List>[];
    while (_position < _events.length && _events[_position].kind == 'R') {
      answers.add(_events[_position++].payload);
    }
    await onWrite?.call(index, bytes);
    if (isDropped) return;
    for (final a in answers) {
      _notifications.add(a);
    }
  }

  @override
  Future<Uint8List> readCharacteristic(String uuid) =>
      Future.error(UnsupportedError('no characteristics in the trace'));

  @override
  Future<void> writeCharacteristic(String uuid, Uint8List bytes) =>
      Future.error(UnsupportedError('no characteristics in the trace'));
}

/// Every event of [download], with a deadline so a hang fails the test.
Future<List<LibdcDownloadEvent>> collect(
  LibdcDownload download, {
  Duration timeout = const Duration(seconds: 60),
}) => download.events.toList().timeout(timeout);

List<LibdcDiveDownloaded> divesOf(List<LibdcDownloadEvent> events) =>
    events.whereType<LibdcDiveDownloaded>().toList();

LibdcFinished finishedOf(List<LibdcDownloadEvent> events) =>
    events.last as LibdcFinished;
