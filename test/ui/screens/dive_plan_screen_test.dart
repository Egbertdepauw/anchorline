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
  String? lastSaveName;
  int saveAsCalls = 0;
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
  Future<SavedDivePlan> saveAs({required String name}) async {
    saveAsCalls++;
    lastSaveName = name;
    // Mirror the real DAO: saveAs deletes the draft as part of promotion.
    draft = null;
    return SavedDivePlan(
      id: 'x',
      name: name,
      updatedAt: DateTime.now(),
      mode: DivePlanMode.cc,
    );
  }

  int updateSavedCalls = 0;
  String? lastUpdateId;
  @override
  Future<void> updateSaved(
      {required String id,
      required DivePlanDraft draft,
      required String name}) async {
    updateSavedCalls++;
    lastUpdateId = id;
    lastSaveName = name;
  }

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

  testWidgets('renders SETTINGS, GASES, SEGMENTS on Plan tab and BAILOUT BOTTLES on Bailout tab',
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
    // Bailout tab — switch and verify the bailout-bottles editor surfaces.
    await tester.tap(find.text('Bailout'));
    await tester.pumpAndSettle();
    expect(find.text('BAILOUT BOTTLES'), findsOneWidget);
  });

  testWidgets('inline name + Save button persists the plan and keeps editor state',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final notifier = DivePlanNotifier(dao: dao, settings: settings);
    await notifier.load();
    notifier.addGas(const DivePlanGas(
        oxygenPercent: 21, heliumPercent: 35, isDiluent: true));
    notifier.addSegment(const DivePlanSegment(
        depthMeters: 40, durationMinutes: 15, gasMixIndex: 0, setpoint: 1.3));
    await tester.pumpWidget(MaterialApp(
      home: DivePlanScreen(notifier: notifier, settings: settings),
    ));
    // Type into the app-bar name field. It's the first TextField in the tree.
    await tester.enterText(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      ),
      'Test plan',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-as')));
    await tester.pumpAndSettle();
    expect(dao.saveAsCalls, equals(1));
    expect(dao.lastSaveName, equals('Test plan'));
    // Editor state survives the save — that was the bug we fixed.
    expect(notifier.gases, isNotEmpty);
    expect(notifier.segments, isNotEmpty);
    expect(notifier.planName, equals('Test plan'));
  });

  Future<DivePlanNotifier> seededNotifier() async {
    final settings = SettingsNotifier();
    await settings.load();
    final notifier = DivePlanNotifier(dao: _FakeDao(), settings: settings);
    await notifier.load();
    notifier.addGas(const DivePlanGas(
        oxygenPercent: 18, heliumPercent: 45, isDiluent: true));
    notifier.addSegment(const DivePlanSegment(
        depthMeters: 40, durationMinutes: 15, gasMixIndex: 0, setpoint: 1.3));
    return notifier;
  }

  testWidgets(
      'settings panel stays open when the screen is rebuilt from scratch, '
      'and a GF edit reaches the notifier (#183)', (tester) async {
    final notifier = await seededNotifier();
    Widget screen() => MaterialApp(
          home: DivePlanScreen(
              notifier: notifier, settings: notifier.settings),
        );
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('plan-settings-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('GF Low'), findsOneWidget);

    // Throw the whole tree away, as a tab switch in the app shell can.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('GF Low'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('gf-low')), '40');
    await tester.pump();
    expect(notifier.overrides.gfLow, 40);
    expect(find.text('GF Low'), findsOneWidget);
    // Let the debounced draft write fire.
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a segment depth over the max is rejected with a message (#183)',
      (tester) async {
    final notifier = await seededNotifier();
    await tester.pumpWidget(MaterialApp(
      home: DivePlanScreen(notifier: notifier, settings: notifier.settings),
    ));
    final depthField = find
        .descendant(
            of: find.byKey(const ValueKey('seg-0')),
            matching: find.byType(TextField))
        .first;
    await tester.enterText(depthField, '4030');
    await tester.pump();
    expect(notifier.segments.single.depthMeters, 40,
        reason: 'the plan keeps the last accepted depth');
    expect(notifier.result, isNotNull);
    expect(find.text('Max depth 300 m. The plan still uses 40 m.'),
        findsOneWidget);

    await tester.enterText(depthField, '45');
    await tester.pump();
    expect(notifier.segments.single.depthMeters, 45);
    expect(find.byKey(const ValueKey('segment-depth-limit')), findsNothing);
    // Let the debounced draft write fire.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
