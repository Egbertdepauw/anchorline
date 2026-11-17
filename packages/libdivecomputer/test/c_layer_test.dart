// Tests of Anchorline's C layer (native/anchorline_io.c) against the
// hook-built library.
//
// The blocking side runs on a helper isolate that calls dc_iostream_* on the
// iostream from al_link_iostream, passed across as an address, exactly as the
// download isolate will. This isolate plays the main isolate: it answers the
// link's requests through a NativeCallable.listener and pushes packets.
//
// Nothing here sleeps to synchronise. Where a test needs the blocking thread
// to have got somewhere, the helper sends a message first (Signal) and this
// isolate waits for it.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:libdivecomputer/src/bindings.g.dart';
import 'package:test/test.dart';

const _success = dc_status_t.DC_STATUS_SUCCESS;
const _unsupported = dc_status_t.DC_STATUS_UNSUPPORTED;
const _invalidArgs = dc_status_t.DC_STATUS_INVALIDARGS;
const _io = dc_status_t.DC_STATUS_IO;
const _timeout = dc_status_t.DC_STATUS_TIMEOUT;
const _protocol = dc_status_t.DC_STATUS_PROTOCOL;
const _cancelled = dc_status_t.DC_STATUS_CANCELLED;

// ---------------------------------------------------------------------------
// The blocking thread: a list of iostream calls run on a helper isolate.

/// One call the blocking thread makes on the iostream.
sealed class Op {
  const Op();
}

final class SetTimeout extends Op {
  const SetTimeout(this.ms);
  final int ms;
}

final class Read extends Op {
  const Read(this.size);
  final int size;
}

final class Write extends Op {
  const Write(this.bytes);
  final List<int> bytes;
}

final class Poll extends Op {
  const Poll(this.ms);
  final int ms;
}

final class Available extends Op {
  const Available();
}

final class Purge extends Op {
  const Purge(this.direction);
  final int direction;
}

final class Flush extends Op {
  const Flush();
}

final class Sleep extends Op {
  const Sleep(this.ms);
  final int ms;
}

/// An ioctl on a buffer that starts as [data] and is as long.
final class Ioctl extends Op {
  const Ioctl(this.request, this.data);
  final int request;
  final List<int> data;
}

/// `configure(115200, 8, none, 1, none)`.
final class Configure extends Op {
  const Configure();
}

final class SetDtr extends Op {
  const SetDtr(this.value);
  final int value;
}

final class SetRts extends Op {
  const SetRts(this.value);
  final int value;
}

final class SetBreak extends Op {
  const SetBreak(this.value);
  final int value;
}

final class GetLines extends Op {
  const GetLines();
}

/// Tells the test isolate that the blocking thread got here.
final class Signal extends Op {
  const Signal(this.port);
  final SendPort port;
}

/// What one [Op] returned.
final class Res {
  const Res(
    this.status, {
    this.data = const [],
    this.value = 0,
    this.elapsed = Duration.zero,
  });

  final int status;

  /// Read: the bytes read. Ioctl: the whole buffer afterwards.
  final List<int> data;

  /// Write: `actual`. Available: the count. GetLines: the lines.
  final int value;
  final Duration elapsed;

  @override
  String toString() =>
      'Res(status $status, data $data, value $value, ${elapsed.inMilliseconds} ms)';
}

List<Res> _execute(int iostreamAddress, List<Op> ops) {
  final io = Pointer<dc_iostream_t>.fromAddress(iostreamAddress);
  return [
    for (final op in ops)
      using((arena) {
        final watch = Stopwatch()..start();
        Res done(int status, {List<int> data = const [], int value = 0}) =>
            Res(status, data: data, value: value, elapsed: watch.elapsed);
        switch (op) {
          case SetTimeout(:final ms):
            return done(dc_iostream_set_timeout(io, ms));
          case Read(:final size):
            final buffer = arena<Uint8>(size + 1);
            final actual = arena<Size>();
            final status = dc_iostream_read(io, buffer.cast(), size, actual);
            return done(
              status,
              data: List.of(buffer.asTypedList(actual.value)),
              value: actual.value,
            );
          case Write(:final bytes):
            final buffer = arena<Uint8>(bytes.length + 1);
            buffer.asTypedList(bytes.length).setAll(0, bytes);
            final actual = arena<Size>();
            final status = dc_iostream_write(
              io,
              buffer.cast(),
              bytes.length,
              actual,
            );
            return done(status, value: actual.value);
          case Poll(:final ms):
            return done(dc_iostream_poll(io, ms));
          case Available():
            final value = arena<Size>();
            final status = dc_iostream_get_available(io, value);
            return done(status, value: value.value);
          case Purge(:final direction):
            return done(dc_iostream_purge(io, direction));
          case Flush():
            return done(dc_iostream_flush(io));
          case Sleep(:final ms):
            return done(dc_iostream_sleep(io, ms));
          case Ioctl(:final request, :final data):
            final buffer = arena<Uint8>(data.length + 1);
            buffer.asTypedList(data.length).setAll(0, data);
            final status = dc_iostream_ioctl(
              io,
              request,
              buffer.cast(),
              data.length,
            );
            return done(status, data: List.of(buffer.asTypedList(data.length)));
          case Configure():
            return done(
              dc_iostream_configure(
                io,
                115200,
                8,
                dc_parity_t.DC_PARITY_NONE,
                dc_stopbits_t.DC_STOPBITS_ONE,
                dc_flowcontrol_t.DC_FLOWCONTROL_NONE,
              ),
            );
          case SetDtr(:final value):
            return done(dc_iostream_set_dtr(io, value));
          case SetRts(:final value):
            return done(dc_iostream_set_rts(io, value));
          case SetBreak(:final value):
            return done(dc_iostream_set_break(io, value));
          case GetLines():
            final value = arena<UnsignedInt>();
            final status = dc_iostream_get_lines(io, value);
            return done(status, value: value.value);
          case Signal(:final port):
            port.send(null);
            return done(_success);
        }
      }),
  ];
}

/// Runs [ops] on a helper isolate. Only the two arguments are captured, so
/// the closure is sendable.
Future<List<Res>> _onBlockingThread(int iostreamAddress, List<Op> ops) =>
    Isolate.run(() => _execute(iostreamAddress, ops));

// ---------------------------------------------------------------------------
// The main isolate's side of a link.

/// A request as al_link_pending handed it out.
final class Request {
  Request(this.kind, this.data, this.uuid);

  /// The kind the request callback gave.
  final int kind;
  final List<int> data;

  /// Empty for a plain write.
  final String uuid;

  @override
  String toString() => 'Request($kind, $data, "$uuid")';
}

typedef OnRequest = void Function(TestLink link, int kind);

class TestLink {
  TestLink.live({String? name = 'Liberty 1234', OnRequest? onRequest})
    : _onRequest = onRequest ?? _answerSuccess {
    final callable = NativeCallable<al_request_fnFunction>.listener(_handle);
    _callable = callable;
    link = using(
      (arena) => al_link_new_live(
        name == null ? nullptr : name.toNativeUtf8(allocator: arena).cast(),
        callable.nativeFunction,
      ),
    );
    expect(link, isNot(nullptr));
    _open();
  }

  TestLink.replay(List<int> events, {String? name = 'Liberty 1234'})
    : _onRequest = _answerSuccess {
    link = using((arena) {
      final buffer = arena<Uint8>(events.length + 1);
      buffer.asTypedList(events.length).setAll(0, events);
      return al_link_new_replay(
        name == null ? nullptr : name.toNativeUtf8(allocator: arena).cast(),
        buffer,
        events.length,
      );
    });
    expect(link, isNot(nullptr));
    _open();
  }

  late final Pointer<al_link_t> link;
  late final Pointer<dc_context_t> context;
  late final Pointer<dc_iostream_t> iostream;
  NativeCallable<al_request_fnFunction>? _callable;
  final OnRequest _onRequest;

  /// Every request this side took, in order.
  final requests = <Request>[];

  final _runs = <Future<void>>[];
  var _running = 0;
  var _disposed = false;

  static void _answerSuccess(TestLink link, int kind) {
    if (link.take(kind) != null) link.complete(_success);
  }

  void _open() {
    using((arena) {
      final ctx = arena<Pointer<dc_context_t>>();
      expect(dc_context_new(ctx), _success);
      context = ctx.value;
      final out = arena<Pointer<dc_iostream_t>>();
      expect(al_link_iostream(link, context, out), _success);
      iostream = out.value;
    });
  }

  void _handle(int address, int kind) {
    if (_disposed) return;
    expect(address, link.address);
    _onRequest(this, kind);
  }

  /// al_link_pending, first with no room so the size-needed path runs on
  /// every request that has bytes. Null when nothing is waiting.
  Request? take(int kind) => using((arena) {
    final uuid = arena<Char>(DC_BLE_UUID_SIZE);
    var capacity = 0;
    var data = arena<Uint8>(1);
    while (true) {
      final n = al_link_pending(link, data, capacity, uuid, DC_BLE_UUID_SIZE);
      if (n > capacity) {
        capacity = n;
        data = arena<Uint8>(n);
        continue;
      }
      final uuidText = uuid.cast<Utf8>().toDartString();
      if (n == 0 && uuidText.isEmpty) return null;
      final request = Request(kind, List.of(data.asTypedList(n)), uuidText);
      requests.add(request);
      return request;
    }
  });

  void complete(int status, [List<int> data = const []]) => using((arena) {
    final buffer = arena<Uint8>(data.length + 1);
    buffer.asTypedList(data.length).setAll(0, data);
    al_link_complete(
      link,
      status,
      data.isEmpty ? nullptr : buffer,
      data.length,
    );
  });

  void push(List<int> bytes) => using((arena) {
    final buffer = arena<Uint8>(bytes.length + 1);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    al_link_push(link, buffer, bytes.length);
  });

  Future<List<Res>> run(List<Op> ops) {
    _running++;
    final future = _onBlockingThread(iostream.address, ops);
    _runs.add(future.then((_) => _running--, onError: (_) => _running--));
    return future;
  }

  /// The packed recording, read the way the app will: size first, then the
  /// bytes.
  Uint8List recording() => using((arena) {
    final size = al_link_recording(link, nullptr, 0);
    if (size == 0) return Uint8List(0);
    final buffer = arena<Uint8>(size);
    expect(al_link_recording(link, buffer, size), size);
    return Uint8List.fromList(buffer.asTypedList(size));
  });

  Future<void> dispose() async {
    // A failed test can leave the blocking thread waiting; a cancel and a
    // disconnect make every call return at once.
    if (_running > 0) {
      al_link_cancel(link);
      al_link_disconnected(link);
    }
    await Future.wait(_runs);
    _disposed = true;
    expect(dc_iostream_close(iostream), _success);
    _callable?.close();
    al_link_free(link);
    dc_context_free(context);
  }
}

TestLink _live({String? name = 'Liberty 1234', OnRequest? onRequest}) {
  final link = TestLink.live(name: name, onRequest: onRequest);
  addTearDown(link.dispose);
  return link;
}

TestLink _replay(List<int> events, {String? name = 'Liberty 1234'}) {
  final link = TestLink.replay(events, name: name);
  addTearDown(link.dispose);
  return link;
}

/// A port whose first message says the blocking thread got to a [Signal].
(SendPort, Future<void>) _signal() {
  final port = ReceivePort();
  return (port.sendPort, port.first);
}

// ---------------------------------------------------------------------------
// The recording layout: u8 kind, u64 microseconds, u32 length, the payload.

final class Event {
  Event(this.kind, this.micros, this.payload);
  final String kind;
  final int micros;
  final Uint8List payload;

  @override
  String toString() => 'Event($kind, $micros, $payload)';
}

List<Event> _parse(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final events = <Event>[];
  var offset = 0;
  while (offset < bytes.length) {
    final length = view.getUint32(offset + 9);
    events.add(
      Event(
        String.fromCharCode(bytes[offset]),
        view.getUint64(offset + 1),
        Uint8List.sublistView(bytes, offset + 13, offset + 13 + length),
      ),
    );
    offset += 13 + length;
  }
  expect(offset, bytes.length, reason: 'the last event runs past the end');
  return events;
}

Uint8List _encode(List<(String, List<int>)> events) {
  final out = BytesBuilder();
  var micros = 0;
  for (final (kind, payload) in events) {
    micros += 10;
    final header = ByteData(13)
      ..setUint8(0, kind.codeUnitAt(0))
      ..setUint64(1, micros)
      ..setUint32(9, payload.length);
    out
      ..add(header.buffer.asUint8List())
      ..add(payload);
  }
  return out.toBytes();
}

List<int> _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

int _readU32(List<int> bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0);

int _readI32(List<int> bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes)).getInt32(0);

/// `DC_IOCTL_IOR(type, nr, size)` from ioctl.h.
int _ior(int type, int nr, int size) =>
    (DC_IOCTL_DIR_READ << 30) | (size << 16) | (type << 8) | nr;

const _uuidText = '6e400003-b5a3-f393-e0a9-e50e24dc10b8';
const _uuidBytes = [
  0x6E, 0x40, 0x00, 0x03, 0xB5, 0xA3, 0xF3, 0x93, //
  0xE0, 0xA9, 0xE5, 0x0E, 0x24, 0xDC, 0x10, 0xB8,
];

Matcher _within(int lowMs, int highMs) => allOf(
  greaterThanOrEqualTo(Duration(milliseconds: lowMs)),
  lessThan(Duration(milliseconds: highMs)),
);

void main() {
  test('read returns one packet per call and keeps the rest of a longer '
      'packet', () async {
    final l = _live();
    l.push([1, 2, 3]);
    l.push([4, 5, 6, 7, 8]);
    final r = await l.run(const [
      Available(),
      Read(16),
      Read(2),
      Available(),
      Read(16),
      Read(0),
    ]);
    expect(r[0].value, 8);
    expect(r[1].status, _success);
    expect(r[1].data, [1, 2, 3]);
    expect(r[2].status, _success);
    expect(r[2].data, [4, 5]);
    expect(r[3].value, 3);
    expect(r[4].data, [6, 7, 8]);
    expect(r[5].status, _success);
    expect(r[5].value, 0);
  });

  test('read waits for a packet pushed later', () async {
    final l = _live();
    for (final timeout in [3000, -1]) {
      final (port, reached) = _signal();
      final run = l.run([SetTimeout(timeout), Signal(port), const Read(16)]);
      await reached;
      l.push([9, 8]);
      final r = await run;
      expect(r[2].status, _success, reason: 'timeout $timeout');
      expect(r[2].data, [9, 8]);
      expect(r[2].elapsed, lessThan(const Duration(milliseconds: 2500)));
    }
  });

  test('read times out after the timeout libdivecomputer set', () async {
    final l = _live();
    final r = await l.run(const [
      SetTimeout(100),
      Read(16),
      SetTimeout(0),
      Read(16),
    ]);
    expect(r[0].status, _success);
    expect(r[1].status, _timeout);
    expect(r[1].value, 0);
    expect(r[1].elapsed, _within(100, 600));
    expect(r[3].status, _timeout);
    expect(r[3].elapsed, lessThan(const Duration(milliseconds: 100)));
  });

  test('a write waits for completion and returns the status given', () async {
    final answers = [_success, _io];
    final l = _live(
      onRequest: (l, kind) {
        expect(kind, AL_REQ_WRITE);
        // Not taken yet, so not this request's completion: ignored.
        al_link_complete(l.link, dc_status_t.DC_STATUS_NOACCESS, nullptr, 0);
        expect(l.take(kind), isNotNull);
        expect(l.take(kind), isNull, reason: 'a request is taken once');
        l.complete(answers.removeAt(0));
        // A second completion of the same request: ignored.
        al_link_complete(l.link, dc_status_t.DC_STATUS_NOACCESS, nullptr, 0);
      },
    );
    // Nothing pending: ignored, and the next write still waits.
    al_link_complete(l.link, dc_status_t.DC_STATUS_NOACCESS, nullptr, 0);
    final r = await l.run(const [
      Write([0xAA, 0xBB]),
      Write([0xCC]),
      Write([]),
    ]);
    expect(r[0].status, _success);
    expect(r[0].value, 2);
    expect(r[1].status, _io);
    expect(r[1].value, 0);
    // A write of nothing has nothing to send and asks nobody.
    expect(r[2].status, _success);
    expect(r[2].value, 0);
    expect(l.requests.map((q) => q.data), [
      [0xAA, 0xBB],
      [0xCC],
    ]);
    expect(l.requests.map((q) => q.uuid), ['', '']);
  });

  test('a write nobody completes times out', () async {
    var seen = 0;
    final l = _live(
      onRequest: (l, kind) {
        seen++;
        // The first request is never even taken.
        if (seen == 1) return;
        if (seen == 2) {
          l.take(kind); // taken, never completed
          return;
        }
        // The second write's completion, arriving late, before this request
        // is taken: ignored.
        al_link_complete(l.link, _success, nullptr, 0);
        l.take(kind);
        l.complete(dc_status_t.DC_STATUS_DATAFORMAT);
      },
    );
    al_link_set_write_timeout(l.link, 200);
    final untaken = await l.run(const [
      Write([1]),
    ]);
    expect(untaken[0].status, _timeout);
    expect(untaken[0].value, 0);
    expect(untaken[0].elapsed, _within(200, 1500));
    // A notification handled only now finds nothing to do: nobody waits
    // for that write any more.
    expect(l.take(AL_REQ_WRITE), isNull);

    final taken = await l.run(const [
      Write([2]),
    ]);
    expect(taken[0].status, _timeout);
    expect(taken[0].elapsed, _within(200, 1500));
    // Its completion after the timeout: ignored.
    al_link_complete(l.link, _success, nullptr, 0);

    final next = await l.run(const [
      Write([3]),
    ]);
    expect(next[0].status, dc_status_t.DC_STATUS_DATAFORMAT);
    expect(seen, 3);
    expect(l.requests.map((q) => q.data), [
      [2],
      [3],
    ]);
  });

  test(
    'cancel wakes a waiting read with CANCELLED and al_link_cancelled turns 1',
    () async {
      final l = _live(onRequest: (_, _) => fail('nothing asks after a cancel'));
      expect(al_link_cancelled(l.link.cast()), 0);
      final (port, reached) = _signal();
      final run = l.run([const SetTimeout(-1), Signal(port), const Read(16)]);
      await reached;
      al_link_cancel(l.link);
      final r = await run;
      expect(r[2].status, _cancelled);
      expect(r[2].data, isEmpty);
      expect(al_link_cancelled(l.link.cast()), 1);
      // After a cancel nothing waits any more.
      l.push([1]);
      final after = await l.run(const [
        Read(16),
        Write([1]),
        Sleep(3000),
        Poll(-1),
      ]);
      for (final a in after) {
        expect(a.status, _cancelled, reason: '$a');
        expect(a.elapsed, lessThan(const Duration(milliseconds: 1000)));
      }
    },
  );

  test('sleep waits, and a cancel cuts it short', () async {
    final l = _live();
    final r = await l.run(const [Sleep(120)]);
    expect(r[0].status, _success);
    expect(r[0].elapsed, _within(120, 1000));
    final (port, reached) = _signal();
    final run = l.run([Signal(port), const Sleep(3000)]);
    await reached;
    al_link_cancel(l.link);
    final cut = await run;
    expect(cut[1].status, _cancelled);
    expect(cut[1].elapsed, lessThan(const Duration(milliseconds: 1500)));
  });

  test(
    'a disconnect wakes a waiting read and a waiting write with IO',
    () async {
      final reader = _live();
      final (port, reached) = _signal();
      final run = reader.run([
        const SetTimeout(-1),
        Signal(port),
        const Read(16),
      ]);
      await reached;
      al_link_disconnected(reader.link);
      final r = await run;
      expect(r[2].status, _io);
      expect(r[2].data, isEmpty);
      // A packet after the disconnect is dropped.
      reader.push([7]);
      final after = await reader.run(const [Read(16), Poll(0)]);
      expect(after.map((a) => a.status), [_io, _io]);

      final writer = _live(
        onRequest: (l, kind) {
          l.take(kind);
          al_link_disconnected(l.link);
        },
      );
      al_link_set_write_timeout(writer.link, 3000);
      final w = await writer.run(const [
        Write([1, 2]),
      ]);
      expect(w[0].status, _io);
      expect(w[0].value, 0);
      expect(w[0].elapsed, lessThan(const Duration(milliseconds: 2000)));

      // What arrived before the disconnect is still read, then IO.
      final drainer = _live();
      drainer.push([5, 6]);
      al_link_disconnected(drainer.link);
      final drained = await drainer.run(const [Read(16), Read(16)]);
      expect(drained[0].data, [5, 6]);
      expect(drained[1].status, _io);
    },
  );

  test('purge input drops what is queued; poll sees a queued packet and '
      'times out otherwise', () async {
    final l = _live();
    al_link_set_recording(l.link, 1);
    l.push([1, 2]);
    l.push([3]);
    final (port, reached) = _signal();
    final run = l.run([
      const Poll(0),
      const Available(),
      const Purge(dc_direction_t.DC_DIRECTION_OUTPUT),
      const Available(),
      const Purge(dc_direction_t.DC_DIRECTION_INPUT),
      const Available(),
      const Poll(0),
      const Poll(100),
      const Flush(),
      Signal(port),
      const Poll(3000),
      const Read(16),
    ]);
    await reached;
    l.push([4]);
    final r = await run;
    expect(r[0].status, _success);
    expect(r[1].value, 3);
    expect(r[2].status, _success);
    expect(r[3].value, 3, reason: 'purging output leaves the input queue');
    expect(r[4].status, _success);
    expect(r[5].value, 0);
    expect(r[6].status, _timeout);
    expect(r[7].status, _timeout);
    expect(r[7].elapsed, _within(100, 600));
    expect(r[8].status, _success);
    expect(r[10].status, _success);
    expect(r[10].elapsed, lessThan(const Duration(milliseconds: 2500)));
    expect(r[11].data, [4]);
    final purges = _parse(l.recording()).where((e) => e.kind == 'P').toList();
    expect(purges, hasLength(1));
    expect(_readU32(purges.single.payload), 3);
  });

  test('configure, set_dtr, set_rts and set_break succeed; get_lines is '
      'unsupported', () async {
    for (final l in [_live(), _replay(const [])]) {
      al_link_set_recording(l.link, 1);
      final r = await l.run(const [
        Configure(),
        SetDtr(1),
        SetRts(0),
        SetBreak(0),
        GetLines(),
      ]);
      expect(r.map((x) => x.status), [
        _success,
        _success,
        _success,
        _success,
        _unsupported,
      ]);
      final events = _parse(l.recording());
      expect(events.map((e) => e.kind), everyElement('X'));
      expect(events.map((e) => ascii.decode(e.payload)), [
        'configure 115200 8N1',
        'set_dtr 1',
        'set_rts 0',
        'set_break 0',
      ]);
    }
  });

  test('GET_NAME copies the advertised name; a buffer too small is '
      'INVALIDARGS', () async {
    final name = [...ascii.encode('Liberty 1234'), 0];
    for (final l in [_live(), _replay(const [])]) {
      final r = await l.run([
        Ioctl(DC_IOCTL_BLE_GET_NAME, List.filled(13, 0xFF)),
        Ioctl(DC_IOCTL_BLE_GET_NAME, List.filled(64, 0xFF)),
        Ioctl(DC_IOCTL_BLE_GET_NAME, List.filled(12, 0xFF)),
      ]);
      expect(r[0].status, _success);
      expect(r[0].data, name);
      expect(r[1].status, _success);
      expect(r[1].data.sublist(0, 13), name);
      expect(r[2].status, _invalidArgs);
    }
    final anonymous = _live(name: null);
    final r = await anonymous.run([
      Ioctl(DC_IOCTL_BLE_GET_NAME, List.filled(16, 0)),
    ]);
    expect(r[0].status, _unsupported);
  });

  test('PIN code, access code and an unknown ioctl are unsupported', () async {
    final unknown = _ior(0x78, 9, 4);
    final requests = [
      DC_IOCTL_BLE_GET_PINCODE,
      DC_IOCTL_BLE_GET_ACCESSCODE,
      DC_IOCTL_BLE_SET_ACCESSCODE,
      unknown,
    ];
    for (final l in [_live(), _replay(const [])]) {
      al_link_set_recording(l.link, 1);
      final r = await l.run([
        Ioctl(DC_IOCTL_BLE_GET_PINCODE, List.filled(7, 0)),
        Ioctl(DC_IOCTL_BLE_GET_ACCESSCODE, List.filled(16, 0)),
        Ioctl(DC_IOCTL_BLE_SET_ACCESSCODE, List.filled(16, 1)),
        Ioctl(unknown, const [0, 0, 0, 0]),
      ]);
      expect(r.map((x) => x.status), everyElement(_unsupported));
      expect(r[0].data, List.filled(7, 0), reason: 'the buffer is untouched');
      final events = _parse(l.recording());
      expect(events.map((e) => e.kind), everyElement('I'));
      expect(events.map((e) => _readU32(e.payload)), requests);
    }
  });

  test('a characteristic read and write go to the main isolate with the '
      'UUID', () async {
    final l = _live(
      onRequest: (l, kind) {
        final request = l.take(kind)!;
        expect(request.uuid, _uuidText);
        if (kind == AL_REQ_CHAR_READ) {
          // The second read returns one byte more than fits.
          l.complete(
            _success,
            l.requests.length == 1 ? [1, 2, 3, 4, 5] : [1, 2, 3, 4, 5, 6],
          );
        } else {
          l.complete(_success);
        }
      },
    );
    al_link_set_recording(l.link, 1);
    final r = await l.run(const [
      Ioctl(DC_IOCTL_BLE_CHARACTERISTIC_READ, [..._uuidBytes, 0, 0, 0, 0, 0]),
      Ioctl(DC_IOCTL_BLE_CHARACTERISTIC_READ, [..._uuidBytes, 0, 0, 0, 0, 0]),
      Ioctl(DC_IOCTL_BLE_CHARACTERISTIC_WRITE, [..._uuidBytes, 7, 8]),
      Ioctl(DC_IOCTL_BLE_CHARACTERISTIC_READ, [1, 2, 3]),
    ]);
    expect(r[0].status, _success);
    expect(r[0].data, [..._uuidBytes, 1, 2, 3, 4, 5]);
    expect(r[1].status, _invalidArgs);
    expect(r[2].status, _success);
    expect(r[3].status, _invalidArgs, reason: 'shorter than a UUID');
    expect(l.requests.map((q) => q.kind), [
      AL_REQ_CHAR_READ,
      AL_REQ_CHAR_READ,
      AL_REQ_CHAR_WRITE,
    ]);
    expect(l.requests.map((q) => q.data), [
      <int>[],
      <int>[],
      [7, 8],
    ]);
    // C: u8 direction, u8 UUID length, the UUID, the value. The read that
    // failed is not in it.
    final events = _parse(l.recording());
    expect(events.map((e) => e.kind), ['C', 'C']);
    final uuid = ascii.encode(_uuidText);
    expect(events[0].payload, [DC_IOCTL_DIR_READ, 36, ...uuid, 1, 2, 3, 4, 5]);
    expect(events[1].payload, [DC_IOCTL_DIR_WRITE, 36, ...uuid, 7, 8]);
  });

  test(
    'the recording lists W, R and P in order with rising timestamps',
    () async {
      final l = _live();
      await l.run(const [
        Write([0x01]),
      ]);
      expect(l.recording(), isEmpty, reason: 'nothing is kept while off');
      al_link_set_recording(l.link, 1);
      l.push([1, 2, 3]);
      l.push([4, 5]);
      await l.run(const [
        SetTimeout(250),
        Write([0x10, 0x11]),
        Read(16),
        Purge(dc_direction_t.DC_DIRECTION_INPUT),
        Sleep(5),
      ]);
      final bytes = l.recording();
      final events = _parse(bytes);
      expect(events.map((e) => e.kind), ['T', 'W', 'R', 'P', 'S']);
      expect(_readI32(events[0].payload), 250);
      expect(events[1].payload, [0x10, 0x11]);
      expect(events[2].payload, [1, 2, 3]);
      expect(_readU32(events[3].payload), 2);
      expect(_readU32(events[4].payload), 5);
      for (var i = 1; i < events.length; i++) {
        expect(events[i].micros, greaterThanOrEqualTo(events[i - 1].micros));
      }
      expect(events.last.micros, greaterThan(events.first.micros));
      // Too little room: the size needed, and nothing copied.
      using((arena) {
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).fillRange(0, bytes.length, 0xEE);
        expect(
          al_link_recording(l.link, buffer, bytes.length - 1),
          bytes.length,
        );
        expect(buffer.asTypedList(bytes.length), everyElement(0xEE));
      });
      // Turned off, it keeps what it has and adds nothing.
      al_link_set_recording(l.link, 0);
      await l.run(const [Sleep(1)]);
      expect(l.recording(), bytes);
    },
  );

  test('replay serves recorded reads on demand and reports a diverging write '
      'as PROTOCOL', () async {
    final events = _encode([
      ('T', _u32(3000)), // 0, skipped
      ('W', [1, 2]), // 1
      ('R', [3, 4, 5]), // 2
      ('S', _u32(10)), // 3, skipped
      ('R', [6]), // 4
      ('W', [7]), // 5
      ('R', [8]), // 6
    ]);
    final l = _replay(events, name: 'Perdix');
    expect(al_link_replay_position(l.link), 0);
    final r = await l.run([
      const Read(4), // a W is next
      const Write([1, 2]),
      const Read(2),
      const Available(),
      const Read(16),
      const Poll(0),
      const Read(16),
      const Poll(0), // a W is next
      const Available(),
      const Write([9]), // the recording has [7]
      Ioctl(DC_IOCTL_BLE_GET_NAME, List.filled(7, 0)),
    ]);
    expect(r[0].status, _protocol);
    expect(r[1].status, _success);
    expect(r[1].value, 2);
    expect(r[2].data, [3, 4]);
    expect(r[3].value, 1);
    expect(r[4].data, [5]);
    expect(r[5].status, _success);
    expect(r[6].data, [6]);
    expect(r[7].status, _timeout);
    expect(r[8].value, 0);
    expect(r[9].status, _protocol);
    expect(r[9].value, 0);
    expect(r[10].data, [...ascii.encode('Perdix'), 0]);
    expect(al_link_replay_position(l.link), 5, reason: 'the diverging W');
    final rest = await l.run(const [
      Write([7]),
      Read(16),
      Read(16), // the end of the recording
      Write([1]),
    ]);
    expect(rest.map((x) => x.status), [
      _success,
      _success,
      _timeout,
      _protocol,
    ]);
    expect(rest[1].data, [8]);
    expect(al_link_replay_position(l.link), 7);

    // A layout that runs past its end is refused.
    using((arena) {
      final cut = arena<Uint8>(events.length);
      cut.asTypedList(events.length).setAll(0, events);
      expect(al_link_new_replay(nullptr, cut, events.length - 1), nullptr);
      expect(al_link_new_replay(nullptr, cut, 5), nullptr);
    });
  });

  test('a live recording replays to the same reads and writes', () async {
    const ops = [
      SetTimeout(0),
      Write([0x01]),
      Read(2),
      Read(16),
      Write([0x02, 0x03]),
      Read(16),
      Ioctl(DC_IOCTL_BLE_CHARACTERISTIC_READ, [..._uuidBytes, 0, 0]),
      Sleep(1),
      Write([0x04]),
    ];
    final live = _live(
      onRequest: (l, kind) {
        if (l.take(kind) == null) return;
        if (kind == AL_REQ_CHAR_READ) {
          l.complete(_success, [0x51, 0x52]);
          return;
        }
        // The computer answers the second write.
        if (l.requests.length == 2) l.push([0xB1]);
        l.complete(_success);
      },
    );
    al_link_set_recording(live.link, 1);
    live.push([0xA1, 0xA2, 0xA3]);
    final first = await live.run(ops);
    final recorded = live.recording();
    final replay = _replay(recorded);
    final second = await replay.run(ops);
    String describe(Res x) => '${x.status} ${x.data}';
    expect(second.map(describe), first.map(describe));
    expect(first[2].data, [0xA1, 0xA2]);
    expect(first[5].data, [0xB1]);
    expect(first[6].data, [..._uuidBytes, 0x51, 0x52]);
  });

  test('overflowing the queue turns into IO, not a crash', () async {
    final l = _live();
    al_link_set_recording(l.link, 1);
    using((arena) {
      const mib = 1 << 20;
      final chunk = arena<Uint8>(mib);
      for (var i = 0; i < AL_LINK_QUEUE_LIMIT ~/ mib; i++) {
        al_link_push(l.link, chunk, mib);
      }
    });
    final full = await l.run(const [Available()]);
    expect(full[0].value, AL_LINK_QUEUE_LIMIT, reason: 'the limit itself fits');
    l.push([1]);
    l.push([2]);
    final r = await l.run(const [Read(16), Read(16), Available(), Poll(0)]);
    expect(r[0].status, _io);
    expect(r[1].status, _io);
    expect(r[2].value, 0);
    expect(r[3].status, _io);
    final overflow = _parse(l.recording()).where((e) => e.kind == 'X');
    expect(overflow.map((e) => ascii.decode(e.payload)), ['overflow']);
  });
}
