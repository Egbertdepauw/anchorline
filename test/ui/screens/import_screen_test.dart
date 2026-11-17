import 'dart:async';
import 'dart:typed_data';

import 'package:ccrlogger/ble/ble_central.dart' show BleScanResult;
import 'package:ccrlogger/devices/libdc/libdc_download_source.dart'
    show LibdcRun;
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:ccrlogger/ui/screens/import_screen.dart';
import 'package:ccrlogger/ui/widgets/libdc_model_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer/libdivecomputer.dart';

import '../../_helpers/fake_ble_central.dart';

// The screen tests only scan; the daos are never touched.
class _Dao implements DiveDao {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _StateDao implements ImportStateDao {
  @override
  Future<Map<String, Uint8List>> withPrefix(String prefix) async => {};

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _EquipDao implements EquipmentDao {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

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

const _ostc =LibdcDescriptor(
    vendor: 'Heinrichs Weikamp',
    product: 'OSTC 4',
    family: 11,
    model: 0x3B,
    transports: 32);
const _famA = LibdcDescriptor(
    vendor: 'Acme', product: 'Alpha', family: 3, model: 1, transports: 32);
const _famB = LibdcDescriptor(
    vendor: 'Bolt', product: 'Beta', family: 4, model: 2, transports: 32);
const _shear = LibdcDescriptor(
    vendor: 'Shearwater',
    product: 'Petrel 3',
    family: 5,
    model: 9,
    transports: 32);

void main() {
  late FakeBleCentral central;

  ImportNotifier notifierWith(
          List<LibdcDescriptor> Function(String name) match) =>
      ImportNotifier(
        dao: _Dao(),
        importStateDao: _StateDao(),
        equipmentDao: _EquipDao(),
        central: central,
        matchBle: match,
      );

  Future<void> show(WidgetTester tester, ImportNotifier n) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ImportScreen(notifier: n, onViewDives: () {})),
    ));
    n.startScan();
    await tester.pump();
    await tester.pump();
  }

  setUp(() => central = FakeBleCentral());

  testWidgets('an unchecked family shows "Not yet tested by us"',
      (tester) async {
    final n = notifierWith((_) => [_ostc]);
    addTearDown(n.dispose);
    await show(tester, n);

    central.advertise(const BleScanResult(id: 'BB:02', name: 'OSTC 4-1234'));
    await tester.pump();

    expect(find.text('Heinrichs Weikamp OSTC 4'), findsOneWidget);
    expect(find.text('OSTC 4-1234'), findsOneWidget);
    expect(find.text('Not yet tested by us'), findsOneWidget);
    expect(find.text('Record this download'), findsOneWidget);
  });

  testWidgets('a name matching two families asks which one', (tester) async {
    final n = notifierWith((_) => [_famA, _famB]);
    addTearDown(n.dispose);
    await show(tester, n);

    central.advertise(const BleScanResult(id: 'CC:03', name: 'Twin 77'));
    await tester.pump();
    await tester.tap(find.text('Acme Alpha and others'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Which of these is your computer?'), findsOneWidget);
    expect(find.text('Acme Alpha'), findsOneWidget);
    expect(find.text('Bolt Beta'), findsOneWidget);
  });

  testWidgets('the model picker lists brands and models without Shearwater',
      (tester) async {
    final n = notifierWith((_) => const []);
    addTearDown(n.dispose);
    await show(tester, n);
    central.advertise(const BleScanResult(id: 'DD:04', name: 'Mystery X'));
    await tester.pump();

    await tester.tap(find.text("My computer isn't listed"));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LibdcModelPicker), findsOneWidget);
    // The list scrolls; Shearwater would sit among the brands if it were
    // Every BLE brand but Shearwater, sorted; the first is on screen.
    final vendors = ({
      for (final d in Libdc.descriptors())
        if (d.supportsBle && !d.isShearwater) d.vendor
    }.toList()
      ..sort());
    expect(vendors, isNotEmpty);
    expect(find.text(vendors.first), findsOneWidget);
    expect(find.text('Shearwater'), findsNothing);
    await tester.tap(find.text(vendors.first));
    await tester.pump(const Duration(milliseconds: 500));
    final firstModel = Libdc.descriptors()
        .firstWhere((d) =>
            d.supportsBle && !d.isShearwater && d.vendor == vendors.first)
        .product;
    expect(find.text(firstModel), findsOneWidget);

    await tester.tap(find.text(firstModel));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // Last step: the named devices seen in the scan.
    expect(find.text('Mystery X'), findsOneWidget);
  });

  Future<
      ({
        String recordingText,
        List<String> extraHeader,
        Rect? origin
      })?> runShareFlow(WidgetTester tester, LibdcStatus status) async {
    final n = ImportNotifier(
      dao: _Dao(),
      importStateDao: _StateDao(),
      equipmentDao: _EquipDao(),
      central: central,
      libdcOpener: (c, r, d) async => LibdcOpened(
        connection: LibdcBleConnection(_NoLink()),
        close: () async {},
        gattSummary: const ['service A', 'char B'],
      ),
      libdcStarter: ({
        required descriptor,
        required connection,
        required knownFingerprints,
        required record,
      }) =>
          LibdcRun(
            events: Stream.fromIterable([
              const LibdcDeviceInfo(model: 1, firmware: 2, serial: 3),
              LibdcFinished(
                  status: status,
                  recording: LibdcRecording(log: ['recorded log'])),
            ]),
            cancel: () {},
          ),
    );
    addTearDown(n.dispose);
    ({String recordingText, List<String> extraHeader, Rect? origin})? shared;
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ImportScreen(
          notifier: n,
          onViewDives: () {},
          shareDownloadFn: ({
            required recordingText,
            required extraHeader,
            origin,
          }) async =>
              shared = (
                recordingText: recordingText,
                extraHeader: extraHeader,
                origin: origin
              ),
        ),
      ),
    ));
    n.recordNextDownload = true;
    await tester.runAsync(() => n.selectLibdcDevice(
        const ImportScanResult(
            id: 'AA', name: 'Twin', kind: ImportDeviceKind.libdc,
            candidates: [_famA]),
        _famA));
    await tester.pump();
    expect(find.text('Share this download'), findsOneWidget);
    await tester.tap(find.text('Share this download'));
    await tester.pump();
    return shared;
  }

  testWidgets('Share this download appears after a recorded download',
      (tester) async {
    final shared = await runShareFlow(tester, LibdcStatus.done);
    expect(shared!.recordingText, contains('recorded log'));
    expect(shared.extraHeader.join('\n'), contains('service A'));
    expect(shared.extraHeader.join('\n'), contains('char B'));
    expect(shared.origin, isNotNull);
  });

  testWidgets('Share this download appears after a failure', (tester) async {
    final shared = await runShareFlow(tester, LibdcStatus.io);
    expect(find.text('Download stopped (the connection dropped). 0 dives saved.'),
        findsOneWidget);
    expect(shared!.recordingText, contains('recorded log'));
  });

  testWidgets('a libdc download shows its progress and a Cancel button',
      (tester) async {
    final gate = StreamController<LibdcDownloadEvent>();
    var cancelled = false;
    final n = ImportNotifier(
      dao: _Dao(),
      importStateDao: _StateDao(),
      equipmentDao: _EquipDao(),
      central: central,
      libdcOpener: (c, r, d) async => LibdcOpened(
        connection: LibdcBleConnection(_NoLink()),
        close: () async {},
        gattSummary: const [],
      ),
      libdcStarter: ({
        required descriptor,
        required connection,
        required knownFingerprints,
        required record,
      }) =>
          LibdcRun(events: gate.stream, cancel: () => cancelled = true),
    );
    addTearDown(n.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ImportScreen(notifier: n, onViewDives: () {})),
    ));
    late Future<void> flow;
    await tester.runAsync(() async {
      flow = n.selectLibdcDevice(
          const ImportScanResult(
              id: 'AA',
              name: 'Twin',
              kind: ImportDeviceKind.libdc,
              candidates: [_famA]),
          _famA);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.add(const LibdcDeviceInfo(model: 1, firmware: 2, serial: 3));
      gate.add(const LibdcProgress(current: 50, maximum: 100));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    expect(find.text('0 dives saved'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.5);
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
    await tester.runAsync(() async {
      gate.add(LibdcFinished(
          status: LibdcStatus.cancelled, recording: LibdcRecording(log: [])));
      await gate.close();
      await flow;
    });
  });

  testWidgets('the picker leaves out a Shearwater descriptor it is given',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibdcModelPicker(
          devices: const [],
          descriptors: const [_shear, _famA],
        ),
      ),
    ));
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Shearwater'), findsNothing);
  });
}
