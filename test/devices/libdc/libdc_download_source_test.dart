import 'dart:async';
import 'dart:io';

import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/fingerprint_store.dart';
import 'package:ccrlogger/devices/libdc/libdc_download_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:subsurface_core/subsurface_core.dart';

const _family = 0x130000;

const _descriptor = LibdcDescriptor(
  vendor: 'Divesoft',
  product: 'Liberty',
  family: _family,
  model: 10,
  transports: 0,
);

LibdcEnvelope _envelope(List<int> fingerprint, {int serial = 1234}) =>
    LibdcEnvelope(
      pinnedCommit: '0194f09',
      vendor: 'Divesoft',
      product: 'Liberty',
      family: _family,
      descriptorModel: 10,
      devinfoModel: 10,
      devinfoFirmware: 7,
      devinfoSerial: serial,
      fingerprint: Uint8List.fromList(fingerprint),
      data: Uint8List.fromList([1, 2, 3]),
    );

ConvertedDive _converted(LibdcEnvelope e) => mapLibdcDive(
  LibdcParsedDive(
    wallClock: DateTime.utc(2026, 6, 1, 9, 30),
    gasMixes: const [],
    tanks: const [],
    rows: const [],
  ),
  e,
  diveId: 'id-${e.fingerprint.join()}',
);

LibdcDiveDownloaded _dive(List<int> fingerprint) {
  final e = _envelope(fingerprint);
  return LibdcDiveDownloaded(
    envelope: e,
    diveId: 'id-${fingerprint.join()}',
    converted: _converted(e),
  );
}

LibdcDiveDownloaded _unparsable(List<int> fingerprint) => LibdcDiveDownloaded(
  envelope: _envelope(fingerprint),
  diveId: 'bad',
  parseError: LibdcStatus.dataFormat,
);

LibdcFinished _finished(LibdcStatus status) =>
    LibdcFinished(status: status, recording: LibdcRecording(log: ['a log']));

const _info = LibdcDeviceInfo(model: 10, firmware: 7, serial: 1234);

class _Store implements FingerprintStore {
  _Store(this.rows);
  final Map<String, Uint8List> rows;
  final prefixes = <String>[];

  @override
  Future<Map<String, Uint8List>> withPrefix(String prefix) async {
    prefixes.add(prefix);
    return {
      for (final e in rows.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }
}

class _GatedStore implements FingerprintStore {
  _GatedStore(this.gate);
  final Future<Map<String, Uint8List>> gate;
  @override
  Future<Map<String, Uint8List>> withPrefix(String prefix) => gate;
}

class _Harness {
  _Harness(List<LibdcDownloadEvent> script, {FingerprintStore? store}) {
    source = LibdcDownloadSource(
      descriptor: _descriptor,
      connection: _fakeConnection,
      closeConnection: () async => closes++,
      fingerprints: store,
      starter:
          ({
            required descriptor,
            required connection,
            required knownFingerprints,
            required record,
          }) {
            started++;
            passedKnown = knownFingerprints;
            return LibdcRun(
              events: Stream.fromIterable(script),
              cancel: () => cancels++,
            );
          },
    );
  }

  late final LibdcDownloadSource source;
  var started = 0;
  var closes = 0;
  var cancels = 0;
  Map<int, Uint8List>? passedKnown;
}

/// The starter never touches the link; the connection only has to exist.
class _NoLink implements LibdcBleLink {
  @override
  String get advertisedName => 'fake';
  @override
  Stream<Uint8List> get notifications => const Stream.empty();
  @override
  Future<void> write(Uint8List bytes) async {}
  @override
  Future<Uint8List> readCharacteristic(String uuid) async => Uint8List(0);
  @override
  Future<void> writeCharacteristic(String uuid, Uint8List bytes) async {}
  @override
  Future<void> get disconnected => Completer<void>().future;
}

final LibdcConnection _fakeConnection = LibdcBleConnection(_NoLink());

Future<(List<DiveSourceEvent>, Object?)> _collect(
  LibdcDownloadSource source,
) async {
  final events = <DiveSourceEvent>[];
  Object? error;
  try {
    await for (final e in source.download()) {
      events.add(e);
    }
  } catch (e) {
    error = e;
  }
  return (events, error);
}

void main() {
  test('the identity is the descriptor the computer reported, not the one '
      'opened', () async {
    const reported = LibdcDescriptor(
      vendor: 'Heinrichs Weikamp',
      product: 'OSTC 4',
      family: _family,
      model: 0x3B,
      transports: 0,
    );
    final h = _Harness([
      const LibdcDeviceInfo(
          model: 0x3B, firmware: 7, serial: 1234, descriptor: reported),
      _finished(LibdcStatus.done),
    ]);
    final (events, _) = await _collect(h.source);
    final id = (events.first as DiveSourceIdentified).identity;
    expect(id.vendor, 'Heinrichs Weikamp');
    expect(id.product, 'OSTC 4');
    expect(id.modelLabel, 'Heinrichs Weikamp OSTC 4');
    expect(id.family, _family);
    expect(id.modelCode, 0x3B);
    // The key's family is the opened one.
    expect(id.importStateKey, 'libdc:$_family:1234');
  });

  test(
    'device info gives DiveSourceIdentified with the libdc key and labels',
    () async {
      final h = _Harness([_info, _finished(LibdcStatus.done)]);
      final (events, error) = await _collect(h.source);
      expect(error, isNull);
      final id = (events.first as DiveSourceIdentified).identity;
      expect(id.vendor, 'Divesoft');
      expect(id.product, 'Liberty');
      expect(id.serial, 1234);
      expect(id.family, _family);
      expect(id.modelCode, 10);
      expect(id.firmware, 7);
      expect(id.dcModel, ShearwaterModel.unknown);
      expect(id.computerModel, 0);
      expect(id.importStateKey, 'libdc:$_family:1234');
      expect(id.modelLabel, 'Divesoft Liberty');
      expect(id.serialLabel, '1234');
      expect(id.firmwareLabel, '7');
      expect(h.source.identity, same(id));
    },
  );

  test('progress is passed with the dives so far', () async {
    final h = _Harness([
      _info,
      const LibdcProgress(current: 10, maximum: 100),
      _dive([1]),
      const LibdcProgress(current: 50, maximum: 100),
      _finished(LibdcStatus.done),
    ]);
    final (events, _) = await _collect(h.source);
    final progress = events.whereType<DiveSourceProgress>().toList();
    expect(progress[0].diveIndex, 0);
    expect(progress[0].diveBytes, 10);
    expect(progress[0].diveTotalBytes, 100);
    expect(progress[0].totalDives, isNull);
    expect(progress[1].diveIndex, 1);
  });

  test('a dive gives DiveSourceDive with the envelope as raw blob and '
      'kLibdcParserVersion', () async {
    final dive = _dive([0xaa, 0xbb]);
    final h = _Harness([_info, dive, _finished(LibdcStatus.done)]);
    final (events, _) = await _collect(h.source);
    final out = events.whereType<DiveSourceDive>().single;
    expect(out.listing, isNull);
    expect(out.rawBlob, dive.envelope.encode());
    expect(out.fingerprint, [0xaa, 0xbb]);
    expect(out.parserVersion, kLibdcParserVersion);
    expect(out.converted, same(dive.converted));
  });

  test('a parse error gives DiveSourceDiveFailed and the next dive still '
      'arrives', () async {
    final h = _Harness([
      _info,
      _unparsable([1]),
      _dive([2]),
      _finished(LibdcStatus.done),
    ]);
    final (events, error) = await _collect(h.source);
    expect(error, isNull);
    final failed = events.whereType<DiveSourceDiveFailed>().single;
    expect(failed.error, isA<LibdcDiveParseFailed>());
    expect((failed.error as LibdcDiveParseFailed).status, LibdcStatus.dataFormat);
    expect(events.whereType<DiveSourceDive>(), hasLength(1));
  });

  test("a clean finish keeps the newest dive's fingerprint; a cancel or IO "
      'keeps none', () async {
    for (final (status, keeps) in [
      (LibdcStatus.success, true),
      (LibdcStatus.done, true),
      (LibdcStatus.cancelled, false),
      (LibdcStatus.io, false),
    ]) {
      final h = _Harness([
        _info,
        _dive([9, 9]),
        _dive([8, 8]),
        _finished(status),
      ]);
      final (events, _) = await _collect(h.source);
      final fin = events.whereType<DiveSourceFinished>().single;
      expect(fin.importStateKey, 'libdc:$_family:1234', reason: '$status');
      expect(fin.fingerprintToKeep, keeps ? [9, 9] : isNull, reason: '$status');
      expect(fin.recordingText, contains('Anchorline download recording'));
    }
  });

  test('IO after two dives: two dives, Finished without fingerprint, then '
      'the stream fails', () async {
    final h = _Harness([
      _info,
      _dive([1]),
      _dive([2]),
      _finished(LibdcStatus.io),
    ]);
    final (events, error) = await _collect(h.source);
    expect(events.whereType<DiveSourceDive>(), hasLength(2));
    expect(events.last, isA<DiveSourceFinished>());
    expect((events.last as DiveSourceFinished).fingerprintToKeep, isNull);
    expect(error, isA<LibdcDownloadFailed>());
    expect((error as LibdcDownloadFailed).status, LibdcStatus.io);
  });

  test('a cancel ends the stream without an error', () async {
    final h = _Harness([_info, _finished(LibdcStatus.cancelled)]);
    final (_, error) = await _collect(h.source);
    expect(error, isNull);
  });

  test('saved fingerprints for the family are passed by serial', () async {
    final store = _Store({
      'libdc:$_family:1': Uint8List.fromList([1]),
      'libdc:$_family:2': Uint8List.fromList([2]),
      'libdc:${_family + 1}:3': Uint8List.fromList([3]),
      'B89641E4': Uint8List.fromList([4]),
      'libdc:$_family:oops': Uint8List.fromList([5]),
    });
    final h = _Harness([_finished(LibdcStatus.done)], store: store);
    await _collect(h.source);
    expect(store.prefixes, ['libdc:$_family:']);
    expect(h.passedKnown, {
      1: Uint8List.fromList([1]),
      2: Uint8List.fromList([2]),
    });
  });

  test('fingerprints: null passes none (download everything again)', () async {
    final h = _Harness([_finished(LibdcStatus.done)]);
    await _collect(h.source);
    expect(h.passedKnown, isEmpty);
  });

  test('a dive before device info uses serial 0', () async {
    final h = _Harness([_dive([1]), _finished(LibdcStatus.done)]);
    final (events, _) = await _collect(h.source);
    expect(
      (events.last as DiveSourceFinished).importStateKey,
      'libdc:$_family:0',
    );
  });

  test('canListDives is false and listDives throws UnsupportedError', () {
    final h = _Harness(const []);
    expect(h.source.canListDives, isFalse);
    expect(() => h.source.listDives(), throwsUnsupportedError);
  });

  test('close cancels once and closes the connection once, even when '
      'called twice', () async {
    final h = _Harness([_finished(LibdcStatus.done)]);
    await _collect(h.source);
    await h.source.close();
    await h.source.close();
    expect(h.cancels, 1);
    expect(h.closes, 1);
  });

  test('close returns within about 3 s when the connection never closes', () async {
    final logged = <String?>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logged.add(m);
    addTearDown(() => debugPrint = old);
    final source = LibdcDownloadSource(
      descriptor: _descriptor,
      connection: _fakeConnection,
      closeConnection: () => Completer<void>().future,
    );
    final watch = Stopwatch()..start();
    await source.close();
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(logged.single, contains('Disconnect timed out'));
  });

  test('a close during a running download cancels the run', () async {
    final controller = StreamController<LibdcDownloadEvent>();
    var cancels = 0;
    final source = LibdcDownloadSource(
      descriptor: _descriptor,
      connection: _fakeConnection,
      closeConnection: () async {},
      starter: ({required descriptor, required connection,
          required knownFingerprints, required record}) =>
          LibdcRun(events: controller.stream, cancel: () => cancels++),
    );
    final done = _collect(source);
    await Future<void>.delayed(Duration.zero);
    controller.add(_info);
    await Future<void>.delayed(Duration.zero);
    await source.close();
    expect(cancels, 1);
    await controller.close();
    await done;
  });

  test('close still cancels when closeConnection throws', () async {
    final h = _Harness(const []);
    final source = LibdcDownloadSource(
      descriptor: _descriptor,
      connection: _fakeConnection,
      closeConnection: () async => throw StateError('gone'),
      starter: ({required descriptor, required connection,
          required knownFingerprints, required record}) =>
          LibdcRun(events: const Stream.empty(), cancel: () => h.cancels++),
    );
    await _collect(source);
    await source.close();
    expect(h.cancels, 1);
  });

  test('a close while the fingerprints load starts nothing', () async {
    final gate = Completer<Map<String, Uint8List>>();
    final h = _Harness(
      [_info, _finished(LibdcStatus.done)],
      store: _GatedStore(gate.future),
    );
    final done = _collect(h.source);
    await Future<void>.delayed(Duration.zero);
    await h.source.close();
    gate.complete({});
    final (events, error) = await done;
    expect(h.started, 0);
    expect(error, isNull);
    expect(events.single, isA<DiveSourceFinished>());
    expect((events.single as DiveSourceFinished).fingerprintToKeep, isNull);
  });

  test('a cancel while the fingerprints load starts nothing', () async {
    final gate = Completer<Map<String, Uint8List>>();
    final h = _Harness(
      [_info, _finished(LibdcStatus.done)],
      store: _GatedStore(gate.future),
    );
    final done = _collect(h.source);
    await Future<void>.delayed(Duration.zero);
    h.source.cancel();
    gate.complete({});
    final (events, error) = await done;
    expect(h.started, 0);
    expect(error, isNull);
    expect(events.single, isA<DiveSourceFinished>());
    expect(h.closes, 0, reason: 'cancel leaves the connection to close()');
  });

  test('the real replay of the Petrel 3 trace: 8 dives, then PROTOCOL where '
      'the trace stops', () async {
    final trace = _petrelTrace();
    final descriptor = Libdc.descriptors().singleWhere(
      (d) => d.vendor == 'Shearwater' && d.product == 'Petrel 3',
    );
    final source = LibdcDownloadSource(
      descriptor: descriptor,
      connection: _fakeConnection,
      closeConnection: () async {},
      starter:
          ({
            required descriptor,
            required connection,
            required knownFingerprints,
            required record,
          }) {
            final d = LibdcDownload.replay(
              descriptor: descriptor,
              recording: trace,
              knownFingerprints: knownFingerprints,
            );
            return LibdcRun(events: d.events, cancel: d.cancel);
          },
    );
    final (events, error) = await _collect(source);

    final identity = events.whereType<DiveSourceIdentified>().single.identity;
    expect(identity.importStateKey, 'libdc:${descriptor.family}:3096855012');
    final dives = events.whereType<DiveSourceDive>().toList();
    expect(dives, hasLength(8));
    for (final d in dives) {
      expect(d.parserVersion, kLibdcParserVersion);
      expect(d.rawBlob, isNotEmpty);
    }
    final fin = events.last as DiveSourceFinished;
    expect(fin.fingerprintToKeep, isNull);
    expect(error, isA<LibdcDownloadFailed>());
    expect((error as LibdcDownloadFailed).status, LibdcStatus.protocol);
  });
}

/// The Petrel 3 trace (Subsurface's log of 8 dives), as the package's tests
/// use it: the third exchange is RDBI 0x8050 in Subsurface's fork, where
/// upstream at the pin reads 0x8060, so that one exchange is swapped.
LibdcRecording _petrelTrace() {
  final raw = LibdcRecording.parse(
    File('test/fixtures/raw/subsurface2.combined.txt').readAsStringSync(),
  );
  Uint8List hex(String s) => Uint8List.fromList([
    for (final t in s.split(' ')) int.parse(t, radix: 16),
  ]);
  final request = hex('01 00 ff 01 04 00 22 80 50 c0');
  final events = [...raw.events];
  final i = events.indexWhere(
    (e) => e.kind == 'W' && e.payload.join(',') == request.join(','),
  );
  if (i < 0 || i + 1 >= events.length || events[i + 1].kind != 'R') {
    throw StateError('the trace has no hardware id exchange to swap');
  }
  events[i] = LibdcIoEvent('W', hex('01 00 ff 01 04 00 22 80 60 c0'));
  events[i + 1] = LibdcIoEvent('R', hex('01 00 01 ff 05 00 62 80 60 0a c0'));
  return LibdcRecording(header: raw.header, events: events);
}
