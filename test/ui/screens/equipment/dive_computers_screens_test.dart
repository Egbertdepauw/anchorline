import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/ui/screens/equipment/dive_computer_detail_screen.dart';
import 'package:ccrlogger/ui/screens/equipment/dive_computers_list_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../../_helpers/libdc_fixture_dives.dart';
import '../../../_helpers/powersync_test_helper.dart';

/// The Dive Computers screens show what the computer reported: a Shearwater
/// by its hardware ID and hex serial as always, another brand by the
/// identity descriptor stored at import and its decimal serial.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shearwaterSerial = 0xB89641E4;
  const petrel3HardwareId = 0xB407;
  const divesoftSerial = 1234567; // divesoftCcrDive()'s serial.

  Future<({EquipmentDao dao, DiveDao diveDao, EquipmentDaoTestRig rig})>
      openRig(WidgetTester tester, AppDatabase db) async {
    late final EquipmentDaoTestRig rig;
    await tester.runAsync(() async {
      rig = await openEquipmentDaoForTest(db);
    });
    return (
      dao: rig.dao,
      diveDao: DiveDao(db, rig.ps, rig.session),
      rig: rig,
    );
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: screen));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  String startText(Dive d) =>
      DateTime.fromMillisecondsSinceEpoch(d.startTime * 1000)
          .toLocal()
          .toString();

  group('list', () {
    testWidgets('a Shearwater row keeps its model and hex serial ending',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = await openRig(tester, db);
      await tester.runAsync(() async {
        await r.dao.upsertDiveComputer(
          vendor: kShearwaterVendor,
          product: 'Petrel 3',
          serial: shearwaterSerial,
          model: petrel3HardwareId,
          firmwareVersion: 103,
        );
        // A row from a build before libdivecomputer: no vendor at all.
        await r.rig.ps.execute(
          'INSERT INTO dive_computers '
          '(id, owner_id, serial, model, firmware_version, '
          'created_at, updated_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          ['dc_1234abcd', 'test-user', 0x1234ABCD, petrel3HardwareId, 98,
            0, 0, 1, 0],
        );
      });

      await pumpScreen(tester, DiveComputersListScreen(dao: r.dao));

      expect(find.text('Petrel 3 · …41e4'), findsOneWidget);
      expect(find.text('Petrel 3 · …abcd'), findsOneWidget);
      expect(find.textContaining('FW 103 · '), findsOneWidget);
      expect(find.textContaining('Unknown'), findsNothing);
    });

    testWidgets(
        'another brand shows the stored brand and model and its decimal '
        'serial ending', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = await openRig(tester, db);
      await tester.runAsync(() async {
        await r.dao.upsertDiveComputer(
          vendor: 'Divesoft',
          product: 'Liberty',
          serial: divesoftSerial,
          model: 0,
          firmwareVersion: 7,
          family: kFixtureFamilyDivesoft,
          modelCode: 1,
        );
        // A serial shorter than the ending shows whole.
        await r.dao.upsertDiveComputer(
          vendor: 'Ratio',
          product: 'iX3M 2021 Tech+',
          serial: 42,
          model: 0,
          family: kFixtureFamilyRatio,
        );
      });

      await pumpScreen(tester, DiveComputersListScreen(dao: r.dao));

      expect(find.text('Divesoft Liberty · …4567'), findsOneWidget);
      expect(find.text('Ratio iX3M 2021 Tech+ · 42'), findsOneWidget);
      expect(find.textContaining('FW 7 · '), findsOneWidget);
      expect(find.textContaining('Unknown'), findsNothing);
      // The hex reading of the decimal serial must not show.
      expect(find.textContaining('d687'), findsNothing);
    });
  });

  group('detail', () {
    testWidgets(
        'a Shearwater keeps its hex serial, raw model and dive numbers',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = await openRig(tester, db);
      late final String id;
      late final Dive dive;
      await tester.runAsync(() async {
        final data =
            File('test/fixtures/dives/dive_716.bin').readAsBytesSync();
        final parsed =
            ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
        await r.diveDao.importDive(
          converted: DiveConverter.convert(
            parsed: parsed,
            dcSerial: shearwaterSerial,
            dcDiveNumber: 716,
            dcModel: ShearwaterModel.petrel3,
          ),
          rawBlob: data,
          parserVersion: 1,
        );
        dive = (await r.diveDao.getAllDives()).single;
        id = await r.dao.upsertDiveComputer(
          vendor: kShearwaterVendor,
          product: 'Petrel 3',
          serial: shearwaterSerial,
          model: petrel3HardwareId,
          firmwareVersion: 103,
        );
      });

      await pumpScreen(tester, DiveComputerDetailScreen(dao: r.dao, id: id));

      expect(find.text('Serial: B89641E4'), findsOneWidget);
      expect(find.text('Model: $petrel3HardwareId'), findsOneWidget);
      expect(find.text('Firmware: 103'), findsOneWidget);
      expect(find.text('Dive #716'), findsOneWidget);
      expect(find.text(startText(dive)), findsOneWidget);
    });

    testWidgets(
        'another brand shows its decimal serial, brand and model, and dates '
        'without a dive number', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = await openRig(tester, db);
      late final String id;
      late final Dive dive;
      await tester.runAsync(() async {
        await r.diveDao.importDive(
          converted: divesoftCcrDive(),
          rawBlob: Uint8List(0),
          parserVersion: 1,
        );
        dive = (await r.diveDao.getAllDives()).single;
        id = await r.dao.upsertDiveComputer(
          vendor: 'Divesoft',
          product: 'Liberty',
          serial: divesoftSerial,
          model: 0,
          firmwareVersion: 7,
          family: kFixtureFamilyDivesoft,
          modelCode: 1,
        );
      });

      await pumpScreen(tester, DiveComputerDetailScreen(dao: r.dao, id: id));

      expect(find.text('Serial: 1234567'), findsOneWidget);
      expect(find.text('Model: Divesoft Liberty'), findsOneWidget);
      expect(find.text('Model: 0'), findsNothing);
      expect(find.text('Firmware: 7'), findsOneWidget);
      // The dive is listed by its start alone, never as "Dive #0".
      expect(dive.dcDiveNumber, 0);
      expect(find.text(startText(dive)), findsOneWidget);
      expect(find.textContaining('Dive #'), findsNothing);
      expect(find.text('No imports yet'), findsNothing);
    });
  });
}
