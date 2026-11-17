import 'package:ccrlogger/ble/ble_central.dart' show BleScanResult;
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
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _EquipDao implements EquipmentDao {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

const _ostc = LibdcDescriptor(
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
