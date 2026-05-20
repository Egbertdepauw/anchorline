import 'package:ccrlogger/data/db/dive_plans_dao_api.dart';
import 'package:ccrlogger/data/db/dive_plans_dao.dart' show DivePlanDraft, SavedDivePlan;
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/dive_plan_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDao implements DivePlansDaoLike {
  DivePlanDraft? draft;
  int upsertCalls = 0;
  @override
  Future<DivePlanDraft?> loadDraft() async => draft;
  @override
  Future<void> upsertDraft(DivePlanDraft d) async {
    draft = d;
    upsertCalls++;
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

  test('initial load surfaces empty draft when DAO returns null', () async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final n = DivePlanNotifier(dao: dao, settings: settings);
    await n.load();
    expect(n.gases, isEmpty);
    expect(n.segments, isEmpty);
  });

  test('addGas + result re-computes', () async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final n = DivePlanNotifier(dao: dao, settings: settings);
    await n.load();
    n.addGas(const DivePlanGas(
        oxygenPercent: 21, heliumPercent: 35, isDiluent: true));
    n.addSegment(const DivePlanSegment(
        depthMeters: 30,
        durationMinutes: 15,
        gasMixIndex: 0,
        setpoint: 1.3));
    // Wait for debounce + auto-compute.
    await Future.delayed(const Duration(milliseconds: 350));
    expect(n.result, isNotNull);
    expect(dao.upsertCalls, greaterThan(0));
  });
}
