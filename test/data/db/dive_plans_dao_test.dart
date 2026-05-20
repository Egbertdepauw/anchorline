import 'package:ccrlogger/data/db/dive_plans_dao.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upsertDraft creates a draft row and replaces on second call', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u1');
    final dao = DivePlansDao(ps, session);

    const draft = DivePlanDraft(
      mode: DivePlanMode.cc,
      gases: [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true)
      ],
      segments: [
        DivePlanSegment(
            depthMeters: 50, durationMinutes: 20, gasMixIndex: 0, setpoint: 1.3)
      ],
      bailout: [],
      settings: null,
    );
    await dao.upsertDraft(draft);
    final loaded = await dao.loadDraft();
    expect(loaded, isNotNull);
    expect(loaded!.gases, draft.gases);
    expect(loaded.segments, draft.segments);

    // Second upsert replaces, doesn't create a 2nd draft row.
    await dao.upsertDraft(draft);
    final rows = await ps.getAll(
      'SELECT id FROM dive_plans WHERE name IS NULL',
    );
    expect(rows.length, 1);
  });

  test('saveAs creates a named plan and clears the draft', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u1');
    final dao = DivePlansDao(ps, session);

    await dao.upsertDraft(const DivePlanDraft(
      mode: DivePlanMode.cc,
      gases: [],
      segments: [],
      bailout: [],
      settings: null,
    ));
    await dao.saveAs(name: 'Cave dive 60m');
    final saved = await dao.listSaved();
    expect(saved.length, 1);
    expect(saved.first.name, 'Cave dive 60m');
    expect(await dao.loadDraft(), isNull);
  });

  test('softDelete excludes from listSaved', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u1');
    final dao = DivePlansDao(ps, session);

    await dao.upsertDraft(const DivePlanDraft(
      mode: DivePlanMode.cc,
      gases: [],
      segments: [],
      bailout: [],
      settings: null,
    ));
    final saved = await dao.saveAs(name: 'old');
    await dao.softDelete(saved.id);
    expect(await dao.listSaved(), isEmpty);
  });

  test('insert stamps owner_id from the session', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u-7');
    final dao = DivePlansDao(ps, session);

    await dao.upsertDraft(const DivePlanDraft(
      mode: DivePlanMode.cc,
      gases: [],
      segments: [],
      bailout: [],
      settings: null,
    ));
    final row = await ps.getOptional(
        'SELECT owner_id FROM dive_plans WHERE name IS NULL');
    expect(row!['owner_id'], 'u-7');
  });
}
