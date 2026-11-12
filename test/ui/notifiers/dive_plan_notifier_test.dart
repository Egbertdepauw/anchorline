import 'package:ccrlogger/data/db/dive_plans_dao_api.dart';
import 'package:ccrlogger/data/db/dive_plans_dao.dart' show DivePlanDraft, SavedDivePlan;
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/dive_plan_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDao implements DivePlansDaoLike {
  DivePlanDraft? draft;
  final Map<String, DivePlanDraft> saved = {};
  int upsertCalls = 0;
  int saveAsCalls = 0;
  int updateSavedCalls = 0;
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
  Future<List<SavedDivePlan>> listSaved() async => [
        for (final e in saved.entries)
          SavedDivePlan(
            id: e.key,
            name: e.value.planName ?? '(unnamed)',
            updatedAt: DateTime.now(),
            mode: e.value.mode,
          ),
      ];
  @override
  Future<DivePlanDraft?> loadSaved(String id) async => saved[id];
  @override
  Future<SavedDivePlan> saveAs({required String name}) async {
    saveAsCalls++;
    final id = 'saved-${saved.length + 1}';
    saved[id] = DivePlanDraft(
      mode: draft?.mode ?? DivePlanMode.cc,
      gases: draft?.gases ?? const [],
      segments: draft?.segments ?? const [],
      bailout: draft?.bailout ?? const [],
      settings: draft?.settings,
      notes: draft?.notes,
      planName: name,
    );
    // Mirror real DAO behaviour: saveAs deletes the draft row.
    draft = null;
    return SavedDivePlan(
      id: id,
      name: name,
      updatedAt: DateTime.now(),
      mode: DivePlanMode.cc,
    );
  }

  @override
  Future<void> updateSaved(
      {required String id,
      required DivePlanDraft draft,
      required String name}) async {
    updateSavedCalls++;
    saved[id] = DivePlanDraft(
      mode: draft.mode,
      gases: draft.gases,
      segments: draft.segments,
      bailout: draft.bailout,
      settings: draft.settings,
      notes: draft.notes,
      planName: name,
    );
  }

  @override
  Future<void> softDelete(String id) async {
    saved.remove(id);
  }

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

  test('isDirty: false on empty plan, true after edit, false after save',
      () async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final n = DivePlanNotifier(dao: dao, settings: settings);
    await n.load();
    expect(n.isDirty, isFalse, reason: 'empty plan is clean');
    n.addGas(const DivePlanGas(
        oxygenPercent: 21, heliumPercent: 0, isDiluent: true));
    expect(n.isDirty, isTrue, reason: 'edit dirties the plan');
    n.setPlanName('Test');
    await n.save();
    expect(n.isDirty, isFalse, reason: 'save clears the dirty flag');
  });

  test('save overwrites when a loaded plan\'s name is unchanged', () async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final n = DivePlanNotifier(dao: dao, settings: settings);
    await n.load();
    n.addGas(const DivePlanGas(
        oxygenPercent: 21, heliumPercent: 0, isDiluent: true));
    n.setPlanName('My plan');
    await n.save();
    expect(dao.saveAsCalls, equals(1));
    expect(dao.updateSavedCalls, equals(0));

    // Edit + save again with the same name → overwrite.
    n.addSegment(const DivePlanSegment(
        depthMeters: 30, durationMinutes: 15, gasMixIndex: 0, setpoint: 1.3));
    final result = await n.save();
    expect(result.wasOverwrite, isTrue);
    expect(dao.saveAsCalls, equals(1), reason: 'no new saved row was created');
    expect(dao.updateSavedCalls, equals(1));
  });

  test('save creates a new row when the name is changed after load', () async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = _FakeDao();
    final n = DivePlanNotifier(dao: dao, settings: settings);
    await n.load();
    n.addGas(const DivePlanGas(
        oxygenPercent: 21, heliumPercent: 0, isDiluent: true));
    n.setPlanName('Original');
    await n.save();

    // Rename + save → new saved row, not overwrite.
    n.setPlanName('Renamed copy');
    final result = await n.save();
    expect(result.wasOverwrite, isFalse);
    expect(dao.saveAsCalls, equals(2));
    expect(dao.updateSavedCalls, equals(0));
  });

  group('removeGas remaps segment + bailout gas indices', () {
    Future<DivePlanNotifier> seededPlan() async {
      final settings = SettingsNotifier();
      await settings.load();
      final n = DivePlanNotifier(dao: _FakeDao(), settings: settings);
      await n.load();
      // 4 gases (indices 0..3).
      n.addGas(const DivePlanGas(
          oxygenPercent: 18, heliumPercent: 45, isDiluent: true)); // 0 dil
      n.addGas(const DivePlanGas(
          oxygenPercent: 21, heliumPercent: 0, isDiluent: false)); // 1
      n.addGas(const DivePlanGas(
          oxygenPercent: 50, heliumPercent: 0, isDiluent: false)); // 2
      n.addGas(const DivePlanGas(
          oxygenPercent: 100, heliumPercent: 0, isDiluent: false)); // 3
      return n;
    }

    test(
        'reference above the removed gas shifts down (regression: '
        'RangeError on recompute after delete)', () async {
      final n = await seededPlan();
      // Segment uses gas 3 (the 100% O2). Deleting gas 1 should shift
      // that reference to 2 — NOT leave it at 3 (which would crash the
      // recompute with RangeError: Not in inclusive range 0..2: 3).
      n.addSegment(const DivePlanSegment(
          depthMeters: 6, durationMinutes: 10, gasMixIndex: 3));

      n.removeGas(1);

      expect(n.gases, hasLength(3));
      expect(n.segments.single.gasMixIndex, 2,
          reason: 'gas index above the removed one shifts down by one');
      // The whole point: a recompute must not throw.
      await Future.delayed(const Duration(milliseconds: 350));
    });

    test('reference to the removed gas falls back to gas 0', () async {
      final n = await seededPlan();
      n.addSegment(const DivePlanSegment(
          depthMeters: 21, durationMinutes: 5, gasMixIndex: 2));

      n.removeGas(2); // delete the exact gas the segment used

      expect(n.gases, hasLength(3));
      expect(n.segments.single.gasMixIndex, 0,
          reason: 'orphaned reference falls back to the first gas');
    });

    test('reference below the removed gas is unchanged', () async {
      final n = await seededPlan();
      n.addSegment(const DivePlanSegment(
          depthMeters: 40, durationMinutes: 20, gasMixIndex: 0));

      n.removeGas(2);

      expect(n.segments.single.gasMixIndex, 0,
          reason: 'index below the removed one is untouched');
    });

    test('bailout bottle indices are remapped the same way', () async {
      final n = await seededPlan();
      n.addBailoutBottle(const DivePlanBailoutBottle(
          gasMixIndex: 3, waterCapacityL: 11.1, fillPressureBar: 232));

      n.removeGas(1);

      expect(n.bailout.single.gasMixIndex, 2,
          reason: 'bailout index above the removed gas shifts down');
    });
  });

  group('depth limit and view state (#183)', () {
    Future<DivePlanNotifier> loaded() async {
      final settings = SettingsNotifier();
      await settings.load();
      final n = DivePlanNotifier(dao: _FakeDao(), settings: settings);
      await n.load();
      n.addGas(const DivePlanGas(
          oxygenPercent: 18, heliumPercent: 45, isDiluent: true));
      return n;
    }

    test('a segment deeper than the max is not computed', () async {
      final n = await loaded();
      n.addSegment(const DivePlanSegment(
          depthMeters: 4030, durationMinutes: 30, gasMixIndex: 0));
      expect(n.exceedsMaxDepth, isTrue);
      expect(n.result, isNull);

      n.replaceSegment(0, const DivePlanSegment(
          depthMeters: kMaxPlanDepthMeters, durationMinutes: 30,
          gasMixIndex: 0));
      expect(n.exceedsMaxDepth, isFalse);
      expect(n.result, isNotNull, reason: 'the limit itself is allowed');
    });

    test('settingsExpanded notifies on change only', () async {
      final n = await loaded();
      var notified = 0;
      n.addListener(() => notified++);
      expect(n.settingsExpanded, isFalse);
      n.setSettingsExpanded(true);
      n.setSettingsExpanded(true);
      expect(n.settingsExpanded, isTrue);
      expect(notified, 1);
    });
  });
}
