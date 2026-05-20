import 'package:ccrlogger/data/db/dive_plans_dao.dart' show DivePlanDraft, SavedDivePlan;
import 'package:ccrlogger/data/db/dive_plans_dao_api.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/dive_plan_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDao implements DivePlansDaoLike {
  DivePlanDraft? draft;
  @override
  Future<DivePlanDraft?> loadDraft() async => draft;
  @override
  Future<void> upsertDraft(DivePlanDraft d) async {
    draft = d;
  }
  @override
  Stream<void> watchChanges() => const Stream.empty();
  @override
  Future<List<SavedDivePlan>> listSaved() async => const [];
  @override
  Future<DivePlanDraft?> loadSaved(String id) async => null;
  @override
  Future<SavedDivePlan> saveAs({required String name}) async => SavedDivePlan(
        id: 'x',
        name: name,
        updatedAt: DateTime.now(),
        mode: DivePlanMode.cc,
      );
  @override
  Future<void> softDelete(String id) async {}
  @override
  Future<void> renameSaved(String id, String name) async {}
  @override
  Future<void> clearDraft() async {
    draft = null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders SETTINGS, GASES, SEGMENTS, BAILOUT BOTTLES sections',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final notifier = DivePlanNotifier(dao: dao, settings: settings);
    await notifier.load();
    await tester.pumpWidget(MaterialApp(
      home: DivePlanScreen(notifier: notifier, settings: settings),
    ));
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('GASES'), findsOneWidget);
    expect(find.text('SEGMENTS'), findsOneWidget);
    expect(find.text('BAILOUT BOTTLES'), findsOneWidget);
  });

  testWidgets('Save-as button opens a name dialog, calls saveAs on confirm',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final notifier = DivePlanNotifier(dao: dao, settings: settings);
    await notifier.load();
    // Seed an editable draft so the plan isn't trivially empty.
    notifier.addGas(const DivePlanGas(
        oxygenPercent: 21, heliumPercent: 35, isDiluent: true));
    notifier.addSegment(const DivePlanSegment(
        depthMeters: 40, durationMinutes: 15, gasMixIndex: 0, setpoint: 1.3));
    await tester.pumpWidget(MaterialApp(
      home: DivePlanScreen(notifier: notifier, settings: settings),
    ));
    await tester.tap(find.byKey(const ValueKey('save-as')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Test plan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // After save the draft is cleared on the notifier side.
    expect(notifier.gases, isEmpty);
  });
}
