import 'package:ccrlogger/data/db/dive_plans_dao.dart' show DivePlanDraft, SavedDivePlan;
import 'package:ccrlogger/data/db/dive_plans_dao_api.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/dive_plan_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_user_acknowledgements_dao.dart';

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
  Future<void> updateSaved(
      {required String id,
      required DivePlanDraft draft,
      required String name}) async {}
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

  testWidgets(
      'editing gases + segments triggers a recompute that produces a '
      'non-null result with summary chips visible', (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final notifier = DivePlanNotifier(dao: dao, settings: settings);
    await notifier.load();
    await tester.pumpWidget(MaterialApp(
      home: DivePlanScreen(
        notifier: notifier,
        settings: settings,
        acknowledgements:
            FakeUserAcknowledgementsDao(plannerWarningAccepted: true),
      ),
    ));
    // Let the warning acceptance load.
    await tester.pump();

    // Add a gas.
    await tester.tap(find.byKey(const ValueKey('add-gas')));
    await tester.pumpAndSettle();
    // Add a segment.
    await tester.tap(find.byKey(const ValueKey('add-segment')));
    await tester.pumpAndSettle();
    // Wait for debounced re-compute.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('CNS'), findsOneWidget,
        reason: 'summary chips appear once result is non-null');
    expect(find.textContaining('TTS'), findsOneWidget);
  });
}
