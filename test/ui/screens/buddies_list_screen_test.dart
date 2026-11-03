import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:ccrlogger/ui/screens/buddies_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

Future<void> _insertDive(
  PowerSyncDatabase db,
  String id,
  int startTimeSeconds,
) async {
  await db.execute(
    'INSERT INTO dives '
    '(id, dc_serial, dc_dive_number, start_time, end_time, '
    'duration_seconds, max_depth_mm, dive_mode, deco_model, '
    'atmospheric_pressure_mbar, water_density, log_version, dc_model, '
    'sample_interval_ms, gas_mixes_json, parser_version, imported_at, '
    'deleted_at, version, sync_status) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id, 1, 1, startTimeSeconds, startTimeSeconds + 3600,
      3600, 30000, 0, 0, 1013, 1030, 1, 0, 10000, '[]', 1,
      startTimeSeconds, null, 1, 0,
    ],
  );
}

Future<void> _putAnnotation(
  DiveAnnotationsDao dao,
  String diveId,
  List<String> buddies,
) async {
  final now = DateTime.now();
  await dao.upsert(DiveAnnotation(
    diveId: diveId,
    buddies: buddies,
    createdAt: now,
    updatedAt: now,
  ));
}

// NoSplash avoids the macOS `ink_sparkle.frag` shader flake when InkWell
// taps run in widget tests (same workaround the rest of the suite uses).
Widget _wrap(DiveAnnotationsDao dao) => MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: BuddiesListScreen(dao: dao),
    );

void main() {
  testWidgets('renders buddy names + a stats subtitle with the dive count',
      (tester) async {
    late final DiveAnnotationsDao dao;
    await tester.runAsync(() async {
      final db = await openPowerSyncForTest();
      dao = DiveAnnotationsDao(db, FakeSessionSource());
      await _insertDive(db, 'd1', 1000000);
      await _insertDive(db, 'd2', 2000000);
      await _putAnnotation(dao, 'd1', ['Alex', 'Sam']);
      await _putAnnotation(dao, 'd2', ['Alex']);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(dao));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('Buddies'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    // Alex is on two dives; the subtitle shows the count.
    expect(find.textContaining('2 dives'), findsOneWidget);
    expect(find.textContaining('1 dive'), findsOneWidget);
  });

  testWidgets('tapping Rename opens a dialog with a prefilled TextField',
      (tester) async {
    late final DiveAnnotationsDao dao;
    await tester.runAsync(() async {
      final db = await openPowerSyncForTest();
      dao = DiveAnnotationsDao(db, FakeSessionSource());
      await _insertDive(db, 'd1', 1000000);
      await _putAnnotation(dao, 'd1', ['Alex']);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(dao));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();

    // Open the row's popup menu, then pick Rename.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Alex'), findsOneWidget);
  });

  testWidgets('shows the empty-state message when there are no buddies',
      (tester) async {
    late final DiveAnnotationsDao dao;
    await tester.runAsync(() async {
      final db = await openPowerSyncForTest();
      dao = DiveAnnotationsDao(db, FakeSessionSource());
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(dao));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('No buddies recorded yet'), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
  });
}
