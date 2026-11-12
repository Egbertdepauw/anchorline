# Dive Plan Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a multilevel dive planner as a new top-level "Plan" tab — CC + Bailout end-to-end, OC stubbed in the data model only.

**Architecture:** Drift schema + PowerSync-backed storage for `dive_plans` (one draft + named saved plans per user). A new `lib/analysis/planner/` package walks the segments through the existing tissue model, returns trigger tissues + summary stats, then hands those to the existing `planDeco()` and `planBailout()` to build the outputs. UI is a single scrolling screen with collapsible settings, inline-editable segment/gas/bottle rows, and a reused stop-ladder table.

**Tech Stack:** Flutter 3.x, Drift (schema source) + PowerSync (storage + sync), Supabase (cloud + RLS), `shared_preferences` for global planner defaults, existing `lib/analysis/deco/` + `lib/analysis/bailout/`.

**Spec:** [docs/superpowers/specs/2026-05-20-dive-plan-tab-design.md](../specs/2026-05-20-dive-plan-tab-design.md)

---

## File structure

### New files
- `lib/data/models/dive_plan.dart` — DivePlanGas, DivePlanSegment, DivePlanBailoutBottle, DivePlanSettings, DivePlan + JSON codecs
- `lib/data/db/dive_plans_dao.dart` — PowerSync-backed CRUD + draft + watch
- `lib/analysis/planner/plan_result.dart` — PlanResult type
- `lib/analysis/planner/plan_simulator.dart` — segments → trigger tissues + summary stats
- `lib/analysis/planner/plan_runner.dart` — orchestrator
- `lib/ui/notifiers/dive_plan_notifier.dart` — editor state + compute + auto-save
- `lib/ui/screens/dive_plan_screen.dart` — top-level screen
- `lib/ui/widgets/plan_settings_panel.dart`
- `lib/ui/widgets/plan_gases_editor.dart`
- `lib/ui/widgets/plan_segments_editor.dart`
- `lib/ui/widgets/plan_bailout_bottles_editor.dart`
- `lib/ui/widgets/plan_output_section.dart`
- `lib/ui/widgets/saved_plans_sheet.dart`
- `lib/ui/widgets/stop_ladder_table.dart` — extracted from `bailout_section.dart`
- `supabase/migrations/0013_dive_plans.sql`
- `test/analysis/planner/plan_simulator_test.dart`
- `test/analysis/planner/plan_runner_test.dart`
- `test/data/db/dive_plans_dao_test.dart`
- `test/ui/notifiers/dive_plan_notifier_test.dart`
- `test/ui/screens/dive_plan_screen_test.dart`

### Modified files
- `lib/data/db/tables.dart` — add `DivePlans` table
- `lib/data/db/database.dart` — add table to `@DriftDatabase`, bump `schemaVersion` to 16, add migration step
- `lib/ui/notifiers/settings_notifier.dart` — add planner global defaults
- `lib/ui/widgets/bailout_section.dart` — switch to shared `StopLadderTable`
- `lib/ui/app_shell.dart` — add "Plan" bottom-nav destination + screen
- `infra/powersync-sync-rules.yaml` — add `dive_plans` to the `user_data` bucket

---

## Task 1: Drift schema + migration for `dive_plans`

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`
- Test: `test/data/db/dive_plans_schema_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/data/db/dive_plans_schema_test.dart`:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dive_plans table exists and round-trips a row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customInsert(
      "INSERT INTO dive_plans "
      "(id, name, mode, gases_json, segments_json, bailout_json, "
      "settings_json, notes, created_at, updated_at, deleted_at, "
      "owner_id, version, sync_status) "
      "VALUES ('p1', NULL, 'cc', '[]', '[]', '[]', NULL, NULL, "
      "1700000000000, 1700000000000, NULL, NULL, 1, 0)",
    );
    final rows = await db.customSelect(
      "SELECT id, mode FROM dive_plans WHERE id = 'p1'",
    ).get();
    expect(rows.length, 1);
    expect(rows.first.data['mode'], 'cc');
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/db/dive_plans_schema_test.dart`
Expected: FAIL — `no such table: dive_plans`

- [ ] **Step 3: Add the table definition**

Add to the end of `lib/data/db/tables.dart`:

```dart
/// Multilevel dive plans (CC + Bailout v1, OC future). One row per
/// plan: a single per-user "draft" row (name IS NULL) auto-saves on
/// edit; named rows are explicitly saved plans. Body is JSON-encoded
/// because gases/segments/bottles are always loaded as a unit.
class DivePlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get mode => text()(); // 'cc' or 'oc'
  TextColumn get gasesJson => text()();
  TextColumn get segmentsJson => text()();
  TextColumn get bailoutJson => text()();
  TextColumn get settingsJson => text().nullable()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: Register the table + bump schemaVersion**

In `lib/data/db/database.dart`:

1. Add `DivePlans` to the `tables: [...]` list in the `@DriftDatabase` annotation (alphabetised next to its peers).
2. Change `int get schemaVersion => 15;` to `int get schemaVersion => 16;`.
3. Add a migration step inside `onUpgrade`:

```dart
if (from < 16) {
  await m.createTable(divePlans);
  await customStatement(
    'CREATE UNIQUE INDEX idx_dive_plans_owner_draft '
    'ON dive_plans (owner_id) '
    'WHERE name IS NULL AND deleted_at IS NULL',
  );
  await customStatement(
    'CREATE INDEX idx_dive_plans_owner_updated '
    'ON dive_plans (owner_id, deleted_at, updated_at DESC)',
  );
}
```

- [ ] **Step 5: Run code generation**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: Regenerates `database.g.dart` with `DivePlan` row class + `$DivePlansTable` info.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/data/db/dive_plans_schema_test.dart`
Expected: PASS

- [ ] **Step 7: Run full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean. No regressions.

- [ ] **Step 8: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/db/dive_plans_schema_test.dart
git commit -m "feat(plan): add dive_plans Drift table + migration to schema v16"
```

---

## Task 2: Supabase migration + PowerSync sync rules

**Files:**
- Create: `supabase/migrations/0013_dive_plans.sql`
- Modify: `infra/powersync-sync-rules.yaml`

This is config-only and runs server-side; no unit test, but it must be deployed (Supabase migrations apply on push to your Supabase project; PowerSync rules are applied via the PowerSync dashboard).

- [ ] **Step 1: Write the Supabase migration**

Create `supabase/migrations/0013_dive_plans.sql`:

```sql
-- Multilevel dive plans. Single table; one "draft" row per user
-- (name IS NULL), unbounded named saved plans. Body is JSON-encoded
-- (gases / segments / bailout bottles / settings overrides) because
-- those subdocs are always loaded as a unit.
CREATE TABLE dive_plans (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text,                       -- NULL = draft, non-NULL = saved plan
  mode text NOT NULL,              -- 'cc' or 'oc' (v1 ships 'cc' only)
  gases_json text NOT NULL,
  segments_json text NOT NULL,
  bailout_json text NOT NULL,
  settings_json text,              -- per-plan overrides; NULL = use globals
  notes text,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

-- One draft per user — enforced server-side as well as locally.
CREATE UNIQUE INDEX idx_dive_plans_owner_draft
  ON dive_plans (owner_id)
  WHERE name IS NULL AND deleted_at IS NULL;

-- Saved-plans browser query: ORDER BY updated_at DESC for one user.
CREATE INDEX idx_dive_plans_owner_updated
  ON dive_plans (owner_id, deleted_at, updated_at DESC);

ALTER TABLE dive_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner can rw" ON dive_plans
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- PowerSync subscribes to logical replication via the `powersync`
-- publication. New tables must be added explicitly so changes start
-- flowing.
ALTER PUBLICATION powersync ADD TABLE "public"."dive_plans";

NOTIFY pgrst, 'reload schema';
```

- [ ] **Step 2: Append the sync-rule entry**

Edit `infra/powersync-sync-rules.yaml`, add one line under `data:` (alphabetically alongside the existing entries):

```yaml
      - SELECT * FROM dive_plans WHERE owner_id = bucket.user_id
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0013_dive_plans.sql infra/powersync-sync-rules.yaml
git commit -m "feat(plan): supabase migration + powersync rule for dive_plans"
```

After commit: deploy `supabase/migrations/0013_dive_plans.sql` to the Supabase project (Supabase CLI / dashboard) and paste the updated `powersync-sync-rules.yaml` content into the PowerSync dashboard. Both must land before client writes will sync — but the client code in subsequent tasks doesn't depend on this being live to compile or unit-test.

---

## Task 3: Dart models for plan body

**Files:**
- Create: `lib/data/models/dive_plan.dart`
- Test: `test/data/models/dive_plan_test.dart` (new)

- [ ] **Step 1: Write failing tests**

Create `test/data/models/dive_plan_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DivePlanGas JSON round-trip', () {
    const g = DivePlanGas(
        oxygenPercent: 21, heliumPercent: 35, isDiluent: true);
    final j = g.toJson();
    expect(DivePlanGas.fromJson(j), g);
  });

  test('DivePlanSegment JSON round-trip (CC with setpoint)', () {
    const s = DivePlanSegment(
      depthMeters: 50,
      durationMinutes: 20,
      gasMixIndex: 0,
      setpoint: 1.3,
    );
    expect(DivePlanSegment.fromJson(s.toJson()), s);
  });

  test('DivePlanSegment JSON round-trip (no setpoint)', () {
    const s = DivePlanSegment(
        depthMeters: 50, durationMinutes: 0, gasMixIndex: 1);
    expect(DivePlanSegment.fromJson(s.toJson()).setpoint, isNull);
  });

  test('DivePlanBailoutBottle JSON round-trip', () {
    const b = DivePlanBailoutBottle(
      gasMixIndex: 0,
      waterCapacityL: 5.7,
      fillPressureBar: 200,
    );
    expect(DivePlanBailoutBottle.fromJson(b.toJson()), b);
  });

  test('DivePlanSettings JSON round-trip with sparse fields', () {
    const s = DivePlanSettings(gfLow: 30, useVpmb: true);
    final json = s.toJson();
    final back = DivePlanSettings.fromJson(json);
    expect(back.gfLow, 30);
    expect(back.useVpmb, true);
    expect(back.gfHigh, isNull);
  });

  test('encodeGases / decodeGases handle empty + multi-mix lists', () {
    expect(decodeGases(encodeGases(const [])), isEmpty);
    const gases = [
      DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
    ];
    expect(decodeGases(encodeGases(gases)), gases);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/dive_plan_test.dart`
Expected: FAIL — `dive_plan.dart` doesn't exist.

- [ ] **Step 3: Implement the models**

Create `lib/data/models/dive_plan.dart`:

```dart
/// Data models for the Dive Plan tab. Plan bodies are JSON-encoded into
/// columns of the `dive_plans` table (see spec). Models are immutable
/// value classes with `==` / `hashCode` so notifier diffs are cheap.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class DivePlanGas {
  final int oxygenPercent;
  final int heliumPercent;
  final bool isDiluent;
  const DivePlanGas({
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.isDiluent,
  });

  Map<String, dynamic> toJson() => {
        'o2': oxygenPercent,
        'he': heliumPercent,
        'dil': isDiluent,
      };

  factory DivePlanGas.fromJson(Map<String, dynamic> j) => DivePlanGas(
        oxygenPercent: j['o2'] as int,
        heliumPercent: j['he'] as int,
        isDiluent: j['dil'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is DivePlanGas &&
      other.oxygenPercent == oxygenPercent &&
      other.heliumPercent == heliumPercent &&
      other.isDiluent == isDiluent;

  @override
  int get hashCode => Object.hash(oxygenPercent, heliumPercent, isDiluent);
}

@immutable
class DivePlanSegment {
  final double depthMeters;
  final int durationMinutes; // 0 = instant change (gas / setpoint)
  final int gasMixIndex;
  final double? setpoint; // CC only; null = phase default
  const DivePlanSegment({
    required this.depthMeters,
    required this.durationMinutes,
    required this.gasMixIndex,
    this.setpoint,
  });

  Map<String, dynamic> toJson() => {
        'd': depthMeters,
        't': durationMinutes,
        'g': gasMixIndex,
        if (setpoint != null) 'sp': setpoint,
      };

  factory DivePlanSegment.fromJson(Map<String, dynamic> j) => DivePlanSegment(
        depthMeters: (j['d'] as num).toDouble(),
        durationMinutes: j['t'] as int,
        gasMixIndex: j['g'] as int,
        setpoint: (j['sp'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is DivePlanSegment &&
      other.depthMeters == depthMeters &&
      other.durationMinutes == durationMinutes &&
      other.gasMixIndex == gasMixIndex &&
      other.setpoint == setpoint;

  @override
  int get hashCode =>
      Object.hash(depthMeters, durationMinutes, gasMixIndex, setpoint);
}

@immutable
class DivePlanBailoutBottle {
  final int gasMixIndex;
  final double waterCapacityL;
  final int fillPressureBar;
  const DivePlanBailoutBottle({
    required this.gasMixIndex,
    required this.waterCapacityL,
    required this.fillPressureBar,
  });

  Map<String, dynamic> toJson() => {
        'g': gasMixIndex,
        'wc': waterCapacityL,
        'fp': fillPressureBar,
      };

  factory DivePlanBailoutBottle.fromJson(Map<String, dynamic> j) =>
      DivePlanBailoutBottle(
        gasMixIndex: j['g'] as int,
        waterCapacityL: (j['wc'] as num).toDouble(),
        fillPressureBar: j['fp'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is DivePlanBailoutBottle &&
      other.gasMixIndex == gasMixIndex &&
      other.waterCapacityL == waterCapacityL &&
      other.fillPressureBar == fillPressureBar;

  @override
  int get hashCode =>
      Object.hash(gasMixIndex, waterCapacityL, fillPressureBar);
}

@immutable
class DivePlanSettings {
  final int? gfLow;
  final int? gfHigh;
  final int? vpmbConservatism;
  final bool? useVpmb;
  final int? ascentRateMpm;
  final int? descentRateMpm;
  final double? bottomSetpoint;
  final double? ascentSetpoint;
  final double? decoSetpoint;
  final double? lastStopDepthMeters;

  const DivePlanSettings({
    this.gfLow,
    this.gfHigh,
    this.vpmbConservatism,
    this.useVpmb,
    this.ascentRateMpm,
    this.descentRateMpm,
    this.bottomSetpoint,
    this.ascentSetpoint,
    this.decoSetpoint,
    this.lastStopDepthMeters,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (gfLow != null) m['gfLo'] = gfLow;
    if (gfHigh != null) m['gfHi'] = gfHigh;
    if (vpmbConservatism != null) m['vpmb'] = vpmbConservatism;
    if (useVpmb != null) m['useVpmb'] = useVpmb;
    if (ascentRateMpm != null) m['asc'] = ascentRateMpm;
    if (descentRateMpm != null) m['des'] = descentRateMpm;
    if (bottomSetpoint != null) m['spBot'] = bottomSetpoint;
    if (ascentSetpoint != null) m['spAsc'] = ascentSetpoint;
    if (decoSetpoint != null) m['spDec'] = decoSetpoint;
    if (lastStopDepthMeters != null) m['last'] = lastStopDepthMeters;
    return m;
  }

  factory DivePlanSettings.fromJson(Map<String, dynamic> j) =>
      DivePlanSettings(
        gfLow: j['gfLo'] as int?,
        gfHigh: j['gfHi'] as int?,
        vpmbConservatism: j['vpmb'] as int?,
        useVpmb: j['useVpmb'] as bool?,
        ascentRateMpm: j['asc'] as int?,
        descentRateMpm: j['des'] as int?,
        bottomSetpoint: (j['spBot'] as num?)?.toDouble(),
        ascentSetpoint: (j['spAsc'] as num?)?.toDouble(),
        decoSetpoint: (j['spDec'] as num?)?.toDouble(),
        lastStopDepthMeters: (j['last'] as num?)?.toDouble(),
      );

  DivePlanSettings copyWith({
    int? gfLow,
    int? gfHigh,
    int? vpmbConservatism,
    bool? useVpmb,
    int? ascentRateMpm,
    int? descentRateMpm,
    double? bottomSetpoint,
    double? ascentSetpoint,
    double? decoSetpoint,
    double? lastStopDepthMeters,
  }) =>
      DivePlanSettings(
        gfLow: gfLow ?? this.gfLow,
        gfHigh: gfHigh ?? this.gfHigh,
        vpmbConservatism: vpmbConservatism ?? this.vpmbConservatism,
        useVpmb: useVpmb ?? this.useVpmb,
        ascentRateMpm: ascentRateMpm ?? this.ascentRateMpm,
        descentRateMpm: descentRateMpm ?? this.descentRateMpm,
        bottomSetpoint: bottomSetpoint ?? this.bottomSetpoint,
        ascentSetpoint: ascentSetpoint ?? this.ascentSetpoint,
        decoSetpoint: decoSetpoint ?? this.decoSetpoint,
        lastStopDepthMeters:
            lastStopDepthMeters ?? this.lastStopDepthMeters,
      );
}

enum DivePlanMode { cc, oc }

/// Encoders / decoders for the JSON columns. Kept as top-level
/// functions so the DAO doesn't reach into instance state.
String encodeGases(List<DivePlanGas> gases) =>
    jsonEncode(gases.map((g) => g.toJson()).toList());

List<DivePlanGas> decodeGases(String s) =>
    (jsonDecode(s) as List).map((j) => DivePlanGas.fromJson(j)).toList();

String encodeSegments(List<DivePlanSegment> segs) =>
    jsonEncode(segs.map((s) => s.toJson()).toList());

List<DivePlanSegment> decodeSegments(String s) => (jsonDecode(s) as List)
    .map((j) => DivePlanSegment.fromJson(j))
    .toList();

String encodeBailout(List<DivePlanBailoutBottle> bs) =>
    jsonEncode(bs.map((b) => b.toJson()).toList());

List<DivePlanBailoutBottle> decodeBailout(String s) =>
    (jsonDecode(s) as List)
        .map((j) => DivePlanBailoutBottle.fromJson(j))
        .toList();

String? encodeSettings(DivePlanSettings? s) =>
    s == null ? null : jsonEncode(s.toJson());

DivePlanSettings? decodeSettings(String? s) =>
    s == null ? null : DivePlanSettings.fromJson(jsonDecode(s));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/dive_plan_test.dart`
Expected: PASS

- [ ] **Step 5: Run full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/dive_plan.dart test/data/models/dive_plan_test.dart
git commit -m "feat(plan): DivePlan data models with JSON round-trip"
```

---

## Task 4: Global planner settings on SettingsNotifier

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Modify: `test/ui/notifiers/settings_notifier_test.dart` (or create if missing)

- [ ] **Step 1: Write failing test**

Append to `test/ui/notifiers/settings_notifier_test.dart` (create the file with one test if it doesn't exist):

```dart
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('planner defaults exposed with sensible initial values', () async {
    final n = SettingsNotifier();
    await n.load();
    expect(n.plannerGfLow, 30);
    expect(n.plannerGfHigh, 85);
    expect(n.plannerUseVpmb, false);
    expect(n.plannerVpmbConservatism, 2);
    expect(n.plannerBottomSetpoint, closeTo(1.3, 0.001));
    expect(n.plannerAscentSetpoint, closeTo(0.7, 0.001));
    expect(n.plannerDecoSetpoint, closeTo(1.4, 0.001));
    expect(n.plannerLastStopDepthMeters, closeTo(6.0, 0.001));
  });

  test('plannerGfLow setter clamps + persists', () async {
    final n = SettingsNotifier();
    await n.load();
    n.setPlannerGfLow(120); // out of range, clamp to 100
    expect(n.plannerGfLow, 100);
    n.setPlannerGfLow(0);   // clamp to 1
    expect(n.plannerGfLow, 1);
    // Persisted across reload.
    final n2 = SettingsNotifier();
    await n2.load();
    expect(n2.plannerGfLow, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: FAIL — `plannerGfLow` getter not defined.

- [ ] **Step 3: Extend SettingsNotifier**

Add the storage keys near the top of `lib/ui/notifiers/settings_notifier.dart` (alongside `_kBailoutSacBottom` etc):

```dart
  static const _kPlannerGfLow = 'planner_gf_low';
  static const _kPlannerGfHigh = 'planner_gf_high';
  static const _kPlannerUseVpmb = 'planner_use_vpmb';
  static const _kPlannerVpmbConservatism = 'planner_vpmb_cons';
  static const _kPlannerBottomSp = 'planner_sp_bottom';
  static const _kPlannerAscentSp = 'planner_sp_ascent';
  static const _kPlannerDecoSp = 'planner_sp_deco';
  static const _kPlannerLastStop = 'planner_last_stop_m';
```

Add the fields with default values (alongside `_bailoutSacBottom`):

```dart
  int _plannerGfLow = 30;
  int _plannerGfHigh = 85;
  bool _plannerUseVpmb = false;
  int _plannerVpmbConservatism = 2;
  double _plannerBottomSetpoint = 1.3;
  double _plannerAscentSetpoint = 0.7;
  double _plannerDecoSetpoint = 1.4;
  double _plannerLastStopDepthMeters = 6.0;
```

Add the getters (next to the bailout getters):

```dart
  int get plannerGfLow => _plannerGfLow;
  int get plannerGfHigh => _plannerGfHigh;
  bool get plannerUseVpmb => _plannerUseVpmb;
  int get plannerVpmbConservatism => _plannerVpmbConservatism;
  double get plannerBottomSetpoint => _plannerBottomSetpoint;
  double get plannerAscentSetpoint => _plannerAscentSetpoint;
  double get plannerDecoSetpoint => _plannerDecoSetpoint;
  double get plannerLastStopDepthMeters => _plannerLastStopDepthMeters;
```

In `load()`, add (after the existing bailout loads):

```dart
    final pGfLow = prefs.getInt(_kPlannerGfLow);
    if (pGfLow != null) _plannerGfLow = pGfLow.clamp(1, 100);
    final pGfHigh = prefs.getInt(_kPlannerGfHigh);
    if (pGfHigh != null) _plannerGfHigh = pGfHigh.clamp(1, 100);
    _plannerUseVpmb = prefs.getBool(_kPlannerUseVpmb) ?? false;
    final pVpmb = prefs.getInt(_kPlannerVpmbConservatism);
    if (pVpmb != null) _plannerVpmbConservatism = pVpmb.clamp(0, 4);
    final pBottomSp = prefs.getDouble(_kPlannerBottomSp);
    if (pBottomSp != null) {
      _plannerBottomSetpoint = pBottomSp.clamp(0.4, 1.5);
    }
    final pAscentSp = prefs.getDouble(_kPlannerAscentSp);
    if (pAscentSp != null) {
      _plannerAscentSetpoint = pAscentSp.clamp(0.4, 1.5);
    }
    final pDecoSp = prefs.getDouble(_kPlannerDecoSp);
    if (pDecoSp != null) _plannerDecoSetpoint = pDecoSp.clamp(0.4, 1.6);
    final pLast = prefs.getDouble(_kPlannerLastStop);
    if (pLast != null) {
      _plannerLastStopDepthMeters = pLast.clamp(3.0, 9.0);
    }
```

Add the setters (next to existing setters):

```dart
  Future<void> setPlannerGfLow(int v) async {
    final clamped = v.clamp(1, 100);
    if (_plannerGfLow == clamped) return;
    _plannerGfLow = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerGfLow, clamped);
  }

  Future<void> setPlannerGfHigh(int v) async {
    final clamped = v.clamp(1, 100);
    if (_plannerGfHigh == clamped) return;
    _plannerGfHigh = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerGfHigh, clamped);
  }

  Future<void> setPlannerUseVpmb(bool v) async {
    if (_plannerUseVpmb == v) return;
    _plannerUseVpmb = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPlannerUseVpmb, v);
  }

  Future<void> setPlannerVpmbConservatism(int v) async {
    final clamped = v.clamp(0, 4);
    if (_plannerVpmbConservatism == clamped) return;
    _plannerVpmbConservatism = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlannerVpmbConservatism, clamped);
  }

  Future<void> setPlannerBottomSetpoint(double v) async {
    final clamped = v.clamp(0.4, 1.5);
    if (_plannerBottomSetpoint == clamped) return;
    _plannerBottomSetpoint = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerBottomSp, clamped);
  }

  Future<void> setPlannerAscentSetpoint(double v) async {
    final clamped = v.clamp(0.4, 1.5);
    if (_plannerAscentSetpoint == clamped) return;
    _plannerAscentSetpoint = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerAscentSp, clamped);
  }

  Future<void> setPlannerDecoSetpoint(double v) async {
    final clamped = v.clamp(0.4, 1.6);
    if (_plannerDecoSetpoint == clamped) return;
    _plannerDecoSetpoint = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerDecoSp, clamped);
  }

  Future<void> setPlannerLastStopDepthMeters(double v) async {
    final clamped = v.clamp(3.0, 9.0);
    if (_plannerLastStopDepthMeters == clamped) return;
    _plannerLastStopDepthMeters = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPlannerLastStop, clamped);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: PASS

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/notifiers/settings_notifier.dart test/ui/notifiers/settings_notifier_test.dart
git commit -m "feat(plan): global planner defaults (GF/setpoints/last-stop/VPM-B)"
```

---

## Task 5: DivePlansDao

**Files:**
- Create: `lib/data/db/dive_plans_dao.dart`
- Test: `test/data/db/dive_plans_dao_test.dart`

The DAO mirrors `EquipmentDao`'s pattern: PowerSync raw SQL, Drift row types as the public API, owner-id stamped at insert from the session.

- [ ] **Step 1: Write failing tests**

Create `test/data/db/dive_plans_dao_test.dart`:

```dart
import 'package:ccrlogger/data/db/dive_plans_dao.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart'
    show SessionSource;
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

class _FakeSession implements SessionSource {
  _FakeSession(this.userId);
  final String? userId;
  @override
  Session? get currentSession => userId == null
      ? null
      : Session(
          accessToken: 'a',
          tokenType: 't',
          user: _FakeUser(userId!),
        );
}

class _FakeUser {
  _FakeUser(this.id);
  final String id;
}

Future<PowerSyncDatabase> _openInMemoryPs() async {
  // Mirror equipment_dao_test's helper — set up a minimal PS DB with
  // just the dive_plans schema bootstrap.
  final db = PowerSyncDatabase(
    schema: Schema([
      Table('dive_plans', [
        Column.text('owner_id'),
        Column.text('name'),
        Column.text('mode'),
        Column.text('gases_json'),
        Column.text('segments_json'),
        Column.text('bailout_json'),
        Column.text('settings_json'),
        Column.text('notes'),
        Column.integer('created_at'),
        Column.integer('updated_at'),
        Column.integer('deleted_at'),
        Column.integer('version'),
        Column.integer('sync_status'),
      ]),
    ]),
    path: ':memory:',
  );
  await db.initialize();
  return db;
}

void main() {
  test('upsertDraft creates a draft row and replaces on second call',
      () async {
    final ps = await _openInMemoryPs();
    final dao = DivePlansDao(ps, _FakeSession('u1'));
    final draft = const DivePlanDraft(
      mode: DivePlanMode.cc,
      gases: [DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true)],
      segments: [DivePlanSegment(
          depthMeters: 50, durationMinutes: 20, gasMixIndex: 0, setpoint: 1.3)],
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
    final ps = await _openInMemoryPs();
    final dao = DivePlansDao(ps, _FakeSession('u1'));
    await dao.upsertDraft(const DivePlanDraft(
      mode: DivePlanMode.cc, gases: [], segments: [], bailout: [],
      settings: null,
    ));
    await dao.saveAs(name: 'Cave dive 60m');
    final saved = await dao.listSaved();
    expect(saved.length, 1);
    expect(saved.first.name, 'Cave dive 60m');
    expect(await dao.loadDraft(), isNull);
  });

  test('softDelete excludes from listSaved', () async {
    final ps = await _openInMemoryPs();
    final dao = DivePlansDao(ps, _FakeSession('u1'));
    await dao.upsertDraft(const DivePlanDraft(
      mode: DivePlanMode.cc, gases: [], segments: [], bailout: [],
      settings: null,
    ));
    final saved = await dao.saveAs(name: 'old');
    await dao.softDelete(saved.id);
    expect(await dao.listSaved(), isEmpty);
  });

  test('insert stamps owner_id from the session', () async {
    final ps = await _openInMemoryPs();
    final dao = DivePlansDao(ps, _FakeSession('u-7'));
    await dao.upsertDraft(const DivePlanDraft(
      mode: DivePlanMode.cc, gases: [], segments: [], bailout: [],
      settings: null,
    ));
    final row = await ps.getOptional(
        'SELECT owner_id FROM dive_plans WHERE name IS NULL');
    expect(row!['owner_id'], 'u-7');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/db/dive_plans_dao_test.dart`
Expected: FAIL — `dive_plans_dao.dart` doesn't exist.

- [ ] **Step 3: Implement the DAO**

Create `lib/data/db/dive_plans_dao.dart`:

```dart
/// Data Access Object for dive_plans.
///
/// PowerSync-backed table. One draft row per user (name IS NULL),
/// auto-saved on every edit. Saved plans are named rows. Soft-delete
/// via deleted_at. owner_id stamped from the Supabase session at
/// insert time, same pattern as DiveAttachmentsDao.
library;

import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/dive_plan.dart';

/// In-memory representation of an editable plan. The draft and saved
/// rows share this shape; the DAO maps it to/from the row data.
class DivePlanDraft {
  final DivePlanMode mode;
  final List<DivePlanGas> gases;
  final List<DivePlanSegment> segments;
  final List<DivePlanBailoutBottle> bailout;
  final DivePlanSettings? settings;
  final String? notes;
  const DivePlanDraft({
    required this.mode,
    required this.gases,
    required this.segments,
    required this.bailout,
    required this.settings,
    this.notes,
  });
}

/// A saved plan as it appears in the saved-plans browser.
class SavedDivePlan {
  final String id;
  final String name;
  final DateTime updatedAt;
  final DivePlanMode mode;
  const SavedDivePlan({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.mode,
  });
}

class DivePlansDao {
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  DivePlansDao(this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM dive_plans LIMIT 1').map((_) {});

  // ── Draft ──────────────────────────────────────────────────────────

  Future<DivePlanDraft?> loadDraft() async {
    final row = await _ps.getOptional(
      "SELECT mode, gases_json, segments_json, bailout_json, settings_json, "
      "notes FROM dive_plans "
      "WHERE name IS NULL AND deleted_at IS NULL "
      "${_ownerId == null ? '' : 'AND owner_id = ?'}",
      _ownerId == null ? [] : [_ownerId],
    );
    return row == null ? null : _toDraft(row);
  }

  Future<void> upsertDraft(DivePlanDraft draft) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.writeTransaction((tx) async {
      // Find the existing draft (if any).
      final existing = await tx.getOptional(
        "SELECT id FROM dive_plans "
        "WHERE name IS NULL AND deleted_at IS NULL "
        "${_ownerId == null ? '' : 'AND owner_id = ?'}",
        _ownerId == null ? [] : [_ownerId],
      );
      if (existing != null) {
        await tx.execute(
          "UPDATE dive_plans SET mode = ?, gases_json = ?, "
          "segments_json = ?, bailout_json = ?, settings_json = ?, "
          "notes = ?, updated_at = ? WHERE id = ?",
          [
            draft.mode.name,
            encodeGases(draft.gases),
            encodeSegments(draft.segments),
            encodeBailout(draft.bailout),
            encodeSettings(draft.settings),
            draft.notes,
            now,
            existing['id'],
          ],
        );
      } else {
        await tx.execute(
          "INSERT INTO dive_plans (id, owner_id, name, mode, gases_json, "
          "segments_json, bailout_json, settings_json, notes, created_at, "
          "updated_at, deleted_at, version, sync_status) "
          "VALUES (uuid(), ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 0)",
          [
            _ownerId,
            draft.mode.name,
            encodeGases(draft.gases),
            encodeSegments(draft.segments),
            encodeBailout(draft.bailout),
            encodeSettings(draft.settings),
            draft.notes,
            now,
            now,
          ],
        );
      }
    });
  }

  /// Promotes the current draft to a saved plan with [name] and clears
  /// the draft. Returns the new saved plan.
  Future<SavedDivePlan> saveAs({required String name}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _ps.writeTransaction<SavedDivePlan>((tx) async {
      final draft = await tx.getOptional(
        "SELECT id, mode, gases_json, segments_json, bailout_json, "
        "settings_json, notes FROM dive_plans "
        "WHERE name IS NULL AND deleted_at IS NULL "
        "${_ownerId == null ? '' : 'AND owner_id = ?'}",
        _ownerId == null ? [] : [_ownerId],
      );
      if (draft == null) {
        throw StateError('No draft to save.');
      }
      // Insert a new named row.
      final inserted = await tx.execute(
        "INSERT INTO dive_plans (id, owner_id, name, mode, gases_json, "
        "segments_json, bailout_json, settings_json, notes, created_at, "
        "updated_at, deleted_at, version, sync_status) "
        "VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 0) "
        "RETURNING id",
        [
          _ownerId,
          name,
          draft['mode'],
          draft['gases_json'],
          draft['segments_json'],
          draft['bailout_json'],
          draft['settings_json'],
          draft['notes'],
          now,
          now,
        ],
      );
      final newId = inserted.first['id'] as String;
      // Clear the draft row.
      await tx.execute(
        "DELETE FROM dive_plans WHERE id = ?",
        [draft['id']],
      );
      return SavedDivePlan(
        id: newId,
        name: name,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        mode: DivePlanMode.values.firstWhere(
            (m) => m.name == draft['mode']),
      );
    });
    return result;
  }

  // ── Saved plans ────────────────────────────────────────────────────

  Future<List<SavedDivePlan>> listSaved() async {
    final rows = await _ps.getAll(
      "SELECT id, name, mode, updated_at FROM dive_plans "
      "WHERE name IS NOT NULL AND deleted_at IS NULL "
      "${_ownerId == null ? '' : 'AND owner_id = ?'} "
      "ORDER BY updated_at DESC",
      _ownerId == null ? [] : [_ownerId],
    );
    return rows
        .map((r) => SavedDivePlan(
              id: r['id'] as String,
              name: r['name'] as String,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  r['updated_at'] as int),
              mode: DivePlanMode.values
                  .firstWhere((m) => m.name == r['mode']),
            ))
        .toList();
  }

  /// Loads a saved plan into a draft-shaped object. The caller can then
  /// pass it to [upsertDraft] to replace the active draft.
  Future<DivePlanDraft?> loadSaved(String id) async {
    final row = await _ps.getOptional(
      "SELECT mode, gases_json, segments_json, bailout_json, settings_json, "
      "notes FROM dive_plans WHERE id = ? AND deleted_at IS NULL",
      [id],
    );
    return row == null ? null : _toDraft(row);
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      "UPDATE dive_plans SET deleted_at = ?, updated_at = ? WHERE id = ?",
      [now, now, id],
    );
  }

  Future<void> renameSaved(String id, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      "UPDATE dive_plans SET name = ?, updated_at = ? WHERE id = ?",
      [name, now, id],
    );
  }

  /// Clears the current draft (without saving). Used by "New plan".
  Future<void> clearDraft() async {
    await _ps.execute(
      "DELETE FROM dive_plans "
      "WHERE name IS NULL AND deleted_at IS NULL "
      "${_ownerId == null ? '' : 'AND owner_id = ?'}",
      _ownerId == null ? [] : [_ownerId],
    );
  }

  // ── Mapping ────────────────────────────────────────────────────────

  DivePlanDraft _toDraft(Map<String, dynamic> row) => DivePlanDraft(
        mode: DivePlanMode.values
            .firstWhere((m) => m.name == row['mode']),
        gases: decodeGases(row['gases_json'] as String),
        segments: decodeSegments(row['segments_json'] as String),
        bailout: decodeBailout(row['bailout_json'] as String),
        settings: decodeSettings(row['settings_json'] as String?),
        notes: row['notes'] as String?,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/db/dive_plans_dao_test.dart`
Expected: PASS

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/dive_plans_dao.dart test/data/db/dive_plans_dao_test.dart
git commit -m "feat(plan): DivePlansDao — draft, save-as, list, soft-delete"
```

---

## Task 6: PlanResult model + PlanSimulator skeleton

**Files:**
- Create: `lib/analysis/planner/plan_result.dart`
- Create: `lib/analysis/planner/plan_simulator.dart`
- Test: `test/analysis/planner/plan_simulator_test.dart`

The simulator walks segments, advancing the existing tissue model. It returns trigger tissue state and summary stats. This task lands a minimal-but-correct simulator handling **square CC dives** (single bottom level, no time-0 changes). Later tasks add intermediate segments, time-0 switches, OTU/density.

- [ ] **Step 1: Write failing test**

Create `test/analysis/planner/plan_simulator_test.dart`:

```dart
import 'package:ccrlogger/analysis/planner/plan_result.dart';
import 'package:ccrlogger/analysis/planner/plan_simulator.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('square 30 m / 20 min on 21/35 dil at SP 1.3 loads compartments above '
      'surface', () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    // N2 in the fast compartments must have risen above 0.75 bar (surface).
    expect(out.triggerN2Bar[0], greaterThan(0.75));
    expect(out.triggerN2Bar[3], greaterThan(0.75));
    // He must have risen above 0 in the fast compartments.
    expect(out.triggerHeBar[0], greaterThan(0));
    // Trigger depth = the deepest segment with time > 0.
    expect(out.triggerDepthMeters, 30);
    // Bottom-time before trigger > 0.
    expect(out.totalRuntime.inMinutes, greaterThan(20));
  });

  test('empty segments returns surface-equivalent trigger state', () {
    final out = simulatePlan(
      gases: const [],
      segments: const [],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    expect(out.triggerDepthMeters, 0);
    expect(out.triggerN2Bar.every((n2) => (n2 - 0.745).abs() < 0.01), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/analysis/planner/plan_simulator_test.dart`
Expected: FAIL — `plan_simulator.dart` doesn't exist.

- [ ] **Step 3: Implement PlanResult**

Create `lib/analysis/planner/plan_result.dart`:

```dart
/// Result types for the dive-plan computation pipeline.
library;

import '../bailout/bailout_result.dart' show BailoutResult;
import '../deco/deco_step.dart' show DecoStep;

/// Output of the full plan run (simulator + planDeco + planBailout).
class PlanResult {
  /// Deco schedule from end-of-bottom to surface.
  final List<DecoStep> diveAscent;

  /// OC bailout plan computed from end-of-bottom tissue state.
  final BailoutResult bailout;

  /// CNS % at end of dive (after deco).
  final double cnsPercent;

  /// OTU accumulated over the dive.
  final double otuTotal;

  /// Maximum gas density at depth (g/L).
  final double maxDensityGramsPerLitre;

  /// Total runtime: descent + bottom + ascent + deco.
  final Duration totalRuntime;

  const PlanResult({
    required this.diveAscent,
    required this.bailout,
    required this.cnsPercent,
    required this.otuTotal,
    required this.maxDensityGramsPerLitre,
    required this.totalRuntime,
  });
}

/// Intermediate output of [simulatePlan] — feeds planDeco + planBailout.
class PlanSimulatorOutput {
  final List<double> triggerN2Bar; // 16-element
  final List<double> triggerHeBar; // 16-element
  final double triggerDepthMeters;
  final Duration totalRuntime; // descent + bottom phase
  final double cnsPercent;
  final double otuTotal;
  final double maxDensityGramsPerLitre;
  const PlanSimulatorOutput({
    required this.triggerN2Bar,
    required this.triggerHeBar,
    required this.triggerDepthMeters,
    required this.totalRuntime,
    required this.cnsPercent,
    required this.otuTotal,
    required this.maxDensityGramsPerLitre,
  });
}
```

- [ ] **Step 4: Implement PlanSimulator (square-dive minimum)**

Create `lib/analysis/planner/plan_simulator.dart`:

```dart
/// Forward-simulation of a dive plan: walks segments, advances the
/// existing tissue model minute-by-minute, returns trigger state +
/// summary stats. Feeds planDeco / planBailout downstream.
///
/// Scope of this file (Task 6): square CC dives — descent to first
/// segment, level at that depth for its duration. Time-0 segments
/// (gas / setpoint switches) and CNS/OTU/density accumulators land
/// in later tasks; their fields are present on the output type but
/// computed as zero here.
library;

import '../../data/models/dive_plan.dart';
import '../deco/schreiner.dart' show schreinerAdvance;
import '../deco/tissue_model.dart' show kTissues;
import '../loop_gas.dart' show loopGasAt;
import 'plan_result.dart';

const double _kSurfaceN2Bar = 0.7902 * (1.013 - 0.0627); // alveolar water-vapour-corrected
const double _kSurfaceAtmBar = 1.013;

PlanSimulatorOutput simulatePlan({
  required List<DivePlanGas> gases,
  required List<DivePlanSegment> segments,
  required DivePlanMode mode,
  required int descentRateMpm,
  required int ascentRateMpm,
  required double bottomSetpoint,
  required double ascentSetpoint,
  required double decoSetpoint,
}) {
  // Initialise tissues to surface equilibrium (N2 only).
  final pN2 = List<double>.filled(16, _kSurfaceN2Bar);
  final pHe = List<double>.filled(16, 0.0);
  if (segments.isEmpty) {
    return PlanSimulatorOutput(
      triggerN2Bar: pN2,
      triggerHeBar: pHe,
      triggerDepthMeters: 0,
      totalRuntime: Duration.zero,
      cnsPercent: 0,
      otuTotal: 0,
      maxDensityGramsPerLitre: 0,
    );
  }

  // Determine trigger depth: deepest segment with time > 0.
  double triggerDepth = 0;
  for (final s in segments) {
    if (s.durationMinutes > 0 && s.depthMeters > triggerDepth) {
      triggerDepth = s.depthMeters;
    }
  }

  // ── Descent transit: surface → segment 0 at descent rate ──
  final firstSeg = segments.first;
  final descentSeconds =
      (firstSeg.depthMeters / descentRateMpm * 60).round();
  _advanceTissuesOverInterval(
    pN2: pN2,
    pHe: pHe,
    seconds: descentSeconds,
    avgDepthMeters: firstSeg.depthMeters / 2.0,
    mode: mode,
    gas: gases[firstSeg.gasMixIndex],
    setpoint: firstSeg.setpoint ?? bottomSetpoint,
  );

  // ── Walk segments ──
  Duration totalTime = Duration(seconds: descentSeconds);
  double prevDepth = firstSeg.depthMeters;
  for (final seg in segments) {
    // Transit from prevDepth to seg.depth if they differ.
    if (seg.depthMeters != prevDepth && seg.durationMinutes > 0) {
      final delta = seg.depthMeters - prevDepth;
      final rate =
          delta > 0 ? descentRateMpm : ascentRateMpm;
      final transitSeconds =
          (delta.abs() / rate * 60).round();
      _advanceTissuesOverInterval(
        pN2: pN2,
        pHe: pHe,
        seconds: transitSeconds,
        avgDepthMeters: (seg.depthMeters + prevDepth) / 2.0,
        mode: mode,
        gas: gases[seg.gasMixIndex],
        setpoint: seg.setpoint ?? bottomSetpoint,
      );
      totalTime += Duration(seconds: transitSeconds);
    }
    // Level segment at constant depth.
    if (seg.durationMinutes > 0) {
      _advanceTissuesOverInterval(
        pN2: pN2,
        pHe: pHe,
        seconds: seg.durationMinutes * 60,
        avgDepthMeters: seg.depthMeters,
        mode: mode,
        gas: gases[seg.gasMixIndex],
        setpoint: seg.setpoint ?? bottomSetpoint,
      );
      totalTime += Duration(minutes: seg.durationMinutes);
      prevDepth = seg.depthMeters;
    }
  }

  return PlanSimulatorOutput(
    triggerN2Bar: pN2,
    triggerHeBar: pHe,
    triggerDepthMeters: triggerDepth,
    totalRuntime: totalTime,
    cnsPercent: 0,  // computed in Task 7
    otuTotal: 0,
    maxDensityGramsPerLitre: 0,
  );
}

/// Advances every compartment for [seconds] at constant ambient given
/// by [avgDepthMeters]. The inhaled inert-gas pp values come from
/// [gas] + [setpoint] (CC) or [gas] alone (OC).
void _advanceTissuesOverInterval({
  required List<double> pN2,
  required List<double> pHe,
  required int seconds,
  required double avgDepthMeters,
  required DivePlanMode mode,
  required DivePlanGas gas,
  required double setpoint,
}) {
  if (seconds <= 0) return;
  final ambient = _kSurfaceAtmBar + avgDepthMeters / 10.0;
  late final double inhaledN2;
  late final double inhaledHe;
  if (mode == DivePlanMode.cc) {
    final loop = loopGasAt(
      depthMeters: avgDepthMeters,
      ppo2Bar: setpoint,
      diluent: _toDiveGasMix(gas),
    );
    inhaledN2 = loop.n2Fraction * ambient;
    inhaledHe = loop.heFraction * ambient;
  } else {
    final fO2 = gas.oxygenPercent / 100.0;
    final fHe = gas.heliumPercent / 100.0;
    final fN2 = 1.0 - fO2 - fHe;
    inhaledN2 = fN2 * ambient;
    inhaledHe = fHe * ambient;
  }
  for (var c = 0; c < 16; c++) {
    pN2[c] = schreinerAdvance(
      initialPp: pN2[c],
      inhaledPp: inhaledN2,
      halfTimeMin: kTissues[c].halfTimeN2Min,
      intervalSeconds: seconds,
    );
    pHe[c] = schreinerAdvance(
      initialPp: pHe[c],
      inhaledPp: inhaledHe,
      halfTimeMin: kTissues[c].halfTimeHeMin,
      intervalSeconds: seconds,
    );
  }
}

/// Bridges DivePlanGas → DiveGasMix for the existing loopGasAt helper.
DiveGasMix _toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );
```

Add at the top of `plan_simulator.dart`:

```dart
import '../../data/models/dive.dart' show DiveGasMix;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/analysis/planner/plan_simulator_test.dart`
Expected: PASS

- [ ] **Step 6: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 7: Commit**

```bash
git add lib/analysis/planner/ test/analysis/planner/
git commit -m "feat(plan): PlanSimulator — square CC dive → trigger tissue state"
```

---

## Task 7: PlanSimulator — time-0 changes + multi-level + CNS/OTU/density

**Files:**
- Modify: `lib/analysis/planner/plan_simulator.dart`
- Modify: `test/analysis/planner/plan_simulator_test.dart`

- [ ] **Step 1: Add failing tests**

Append to `test/analysis/planner/plan_simulator_test.dart`:

```dart
  test('time-0 setpoint change updates active SP without advancing time', () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 0.7),
        DivePlanSegment(
            depthMeters: 50, durationMinutes: 0, gasMixIndex: 0, setpoint: 1.3),
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 10,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    // Total time = descent (50m / 18 = 2.78 min ≈ 167 s) + 20 min + 10 min.
    // Allow ±1 s rounding tolerance.
    expect(out.totalRuntime.inSeconds, closeTo(167 + 30 * 60, 2));
  });

  test('multi-level dive: deeper segment + shallower segment',
      () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 15,
            gasMixIndex: 0,
            setpoint: 1.3),
        DivePlanSegment(
            depthMeters: 30,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    expect(out.triggerDepthMeters, 50,
        reason: 'trigger = deepest segment, even if shallower segments '
            'are later in the dive');
  });

  test('CNS accumulates above zero at high PPO2 / depth', () {
    final out = simulatePlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 50,
            durationMinutes: 30,
            gasMixIndex: 0,
            setpoint: 1.4),
      ],
      mode: DivePlanMode.cc,
      descentRateMpm: 18,
      ascentRateMpm: 9,
      bottomSetpoint: 1.4,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
    );
    expect(out.cnsPercent, greaterThan(0));
    expect(out.otuTotal, greaterThan(0));
    expect(out.maxDensityGramsPerLitre, greaterThan(2.5));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/analysis/planner/plan_simulator_test.dart`
Expected: FAIL — multi-level case picks wrong trigger or CNS=0.

- [ ] **Step 3: Implement time-0 + CNS/OTU/density tracking**

Open `lib/analysis/planner/plan_simulator.dart` and replace the `simulatePlan` body with the version that handles time-0 segments + accumulators:

```dart
PlanSimulatorOutput simulatePlan({
  required List<DivePlanGas> gases,
  required List<DivePlanSegment> segments,
  required DivePlanMode mode,
  required int descentRateMpm,
  required int ascentRateMpm,
  required double bottomSetpoint,
  required double ascentSetpoint,
  required double decoSetpoint,
}) {
  final pN2 = List<double>.filled(16, _kSurfaceN2Bar);
  final pHe = List<double>.filled(16, 0.0);
  if (segments.isEmpty) {
    return PlanSimulatorOutput(
      triggerN2Bar: pN2,
      triggerHeBar: pHe,
      triggerDepthMeters: 0,
      totalRuntime: Duration.zero,
      cnsPercent: 0,
      otuTotal: 0,
      maxDensityGramsPerLitre: 0,
    );
  }

  double triggerDepth = 0;
  for (final s in segments) {
    if (s.durationMinutes > 0 && s.depthMeters > triggerDepth) {
      triggerDepth = s.depthMeters;
    }
  }

  // Accumulators.
  Duration totalTime = Duration.zero;
  double cnsAccum = 0;
  double otuAccum = 0;
  double maxDensity = 0;

  // Active state — updated by time-0 segments.
  int activeGasIdx = segments.first.gasMixIndex;
  double activeSetpoint = segments.first.setpoint ?? bottomSetpoint;

  // ── Descent transit (surface → first segment depth) ──
  final firstSeg = segments.first;
  final descentSeconds =
      (firstSeg.depthMeters / descentRateMpm * 60).round();
  _advanceAndAccumulate(
    pN2: pN2,
    pHe: pHe,
    seconds: descentSeconds,
    avgDepthMeters: firstSeg.depthMeters / 2.0,
    mode: mode,
    gas: gases[activeGasIdx],
    setpoint: activeSetpoint,
    cnsOut: (delta) => cnsAccum += delta,
    otuOut: (delta) => otuAccum += delta,
    maxDensityOut: (d) => maxDensity = d > maxDensity ? d : maxDensity,
  );
  totalTime += Duration(seconds: descentSeconds);

  double prevDepth = firstSeg.depthMeters;
  for (final seg in segments) {
    // Time-0 segments update active state without advancing time.
    if (seg.durationMinutes == 0) {
      activeGasIdx = seg.gasMixIndex;
      activeSetpoint = seg.setpoint ?? activeSetpoint;
      continue;
    }
    // Transit between depths (if needed) — uses descending or ascending
    // rate depending on direction.
    if (seg.depthMeters != prevDepth) {
      final delta = seg.depthMeters - prevDepth;
      final rate = delta > 0 ? descentRateMpm : ascentRateMpm;
      final transitSeconds = (delta.abs() / rate * 60).round();
      _advanceAndAccumulate(
        pN2: pN2,
        pHe: pHe,
        seconds: transitSeconds,
        avgDepthMeters: (seg.depthMeters + prevDepth) / 2.0,
        mode: mode,
        gas: gases[activeGasIdx],
        setpoint: activeSetpoint,
        cnsOut: (d) => cnsAccum += d,
        otuOut: (d) => otuAccum += d,
        maxDensityOut: (d) => maxDensity = d > maxDensity ? d : maxDensity,
      );
      totalTime += Duration(seconds: transitSeconds);
    }
    // Apply gas / setpoint of the new segment from this point on.
    activeGasIdx = seg.gasMixIndex;
    activeSetpoint = seg.setpoint ?? activeSetpoint;
    // Level phase.
    _advanceAndAccumulate(
      pN2: pN2,
      pHe: pHe,
      seconds: seg.durationMinutes * 60,
      avgDepthMeters: seg.depthMeters,
      mode: mode,
      gas: gases[activeGasIdx],
      setpoint: activeSetpoint,
      cnsOut: (d) => cnsAccum += d,
      otuOut: (d) => otuAccum += d,
      maxDensityOut: (d) => maxDensity = d > maxDensity ? d : maxDensity,
    );
    totalTime += Duration(minutes: seg.durationMinutes);
    prevDepth = seg.depthMeters;
  }

  return PlanSimulatorOutput(
    triggerN2Bar: pN2,
    triggerHeBar: pHe,
    triggerDepthMeters: triggerDepth,
    totalRuntime: totalTime,
    cnsPercent: cnsAccum,
    otuTotal: otuAccum,
    maxDensityGramsPerLitre: maxDensity,
  );
}
```

Replace `_advanceTissuesOverInterval` with `_advanceAndAccumulate`:

```dart
void _advanceAndAccumulate({
  required List<double> pN2,
  required List<double> pHe,
  required int seconds,
  required double avgDepthMeters,
  required DivePlanMode mode,
  required DivePlanGas gas,
  required double setpoint,
  required void Function(double) cnsOut,
  required void Function(double) otuOut,
  required void Function(double) maxDensityOut,
}) {
  if (seconds <= 0) return;
  final ambient = _kSurfaceAtmBar + avgDepthMeters / 10.0;

  // Compute inhaled inert pp values + ppO2 + density.
  late final double inhaledN2;
  late final double inhaledHe;
  late final double ppO2;
  late final double densityGl;
  if (mode == DivePlanMode.cc) {
    final loop = loopGasAt(
      depthMeters: avgDepthMeters,
      ppo2Bar: setpoint,
      diluent: _toDiveGasMix(gas),
    );
    inhaledN2 = loop.n2Fraction * ambient;
    inhaledHe = loop.heFraction * ambient;
    ppO2 = setpoint;
    densityGl = _density(loop.o2Fraction, loop.heFraction, ambient);
  } else {
    final fO2 = gas.oxygenPercent / 100.0;
    final fHe = gas.heliumPercent / 100.0;
    final fN2 = 1.0 - fO2 - fHe;
    inhaledN2 = fN2 * ambient;
    inhaledHe = fHe * ambient;
    ppO2 = fO2 * ambient;
    densityGl = _density(fO2, fHe, ambient);
  }
  if (densityGl > 0) maxDensityOut(densityGl);

  // Advance tissues.
  for (var c = 0; c < 16; c++) {
    pN2[c] = schreinerAdvance(
      initialPp: pN2[c],
      inhaledPp: inhaledN2,
      halfTimeMin: kTissues[c].halfTimeN2Min,
      intervalSeconds: seconds,
    );
    pHe[c] = schreinerAdvance(
      initialPp: pHe[c],
      inhaledPp: inhaledHe,
      halfTimeMin: kTissues[c].halfTimeHeMin,
      intervalSeconds: seconds,
    );
  }

  // NOAA CNS table (linear interpolation). Returns CNS-clock seconds per
  // breathing minute at ppO2. We approximate with a piecewise table.
  final cnsLimitMin = _noaaCnsLimitMinutes(ppO2);
  if (cnsLimitMin > 0) {
    final minutes = seconds / 60.0;
    cnsOut((minutes / cnsLimitMin) * 100.0);
  }

  // Hamilton OTU formula: OTU/min = ((ppO2 - 0.5) / 0.5)^(5/6) for ppO2 > 0.5.
  if (ppO2 > 0.5) {
    final minutes = seconds / 60.0;
    final otuRate = _hamiltonOtuPerMinute(ppO2);
    otuOut(otuRate * minutes);
  }
}

/// Gas density at ambient. ISA 15 °C: kO2=1.314, kN2=1.2013, kHe=0.166.
double _density(double fO2, double fHe, double ambientBar) {
  final fN2 = 1.0 - fO2 - fHe;
  final atOneAtm = fO2 * 1.314 + fN2 * 1.2013 + fHe * 0.166;
  return atOneAtm * ambientBar;
}

/// NOAA single-exposure CNS limit (minutes) at the given ppO2 (bar).
/// Linear interpolation between the published anchor points. Returns 0
/// when ppO2 < 0.5 (essentially no CNS clock).
double _noaaCnsLimitMinutes(double ppO2) {
  if (ppO2 < 0.5) return 0;
  // NOAA single-exposure 24-h limits.
  const points = <(double, double)>[
    (0.5, 720), (0.6, 720), (0.7, 570), (0.8, 450), (0.9, 360),
    (1.0, 300), (1.1, 240), (1.2, 210), (1.3, 180), (1.4, 150),
    (1.5, 120), (1.6, 45),
  ];
  if (ppO2 >= points.last.$1) return points.last.$2;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (ppO2 >= a.$1 && ppO2 < b.$1) {
      final f = (ppO2 - a.$1) / (b.$1 - a.$1);
      return a.$2 + (b.$2 - a.$2) * f;
    }
  }
  return points.first.$2;
}

double _hamiltonOtuPerMinute(double ppO2) {
  // OTU/min = ((ppO2 - 0.5) / 0.5)^(5/6) for ppO2 > 0.5.
  final base = (ppO2 - 0.5) / 0.5;
  if (base <= 0) return 0;
  return _pow(base, 5.0 / 6.0);
}

double _pow(double base, double exp) {
  return base == 0 ? 0 : (Math.pow(base, exp) as num).toDouble();
}
```

Add at the top of the file:

```dart
import 'dart:math' as Math;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/analysis/planner/plan_simulator_test.dart`
Expected: PASS — all 5 tests.

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/analysis/planner/plan_simulator.dart test/analysis/planner/plan_simulator_test.dart
git commit -m "feat(plan): PlanSimulator — multi-level + time-0 + CNS/OTU/density"
```

---

## Task 8: PlanRunner — orchestrator

**Files:**
- Create: `lib/analysis/planner/plan_runner.dart`
- Test: `test/analysis/planner/plan_runner_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/analysis/planner/plan_runner_test.dart`:

```dart
import 'package:ccrlogger/analysis/bailout/tank_recommender.dart'
    show kAl40, kAl80;
import 'package:ccrlogger/analysis/planner/plan_runner.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('40 m / 20 min CC dive on 21/35 produces a non-empty deco schedule '
      'and a non-trivial bailout plan', () {
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
        DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 40,
            durationMinutes: 20,
            gasMixIndex: 0,
            setpoint: 1.3),
      ],
      bailout: const [
        DivePlanBailoutBottle(
            gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
        DivePlanBailoutBottle(
            gasMixIndex: 1, waterCapacityL: 5.7, fillPressureBar: 232),
      ],
      mode: DivePlanMode.cc,
      gfLow: 30,
      gfHigh: 85,
      useVpmb: false,
      vpmbConservatism: 2,
      ascentRateMpm: 9,
      descentRateMpm: 18,
      bottomSetpoint: 1.3,
      ascentSetpoint: 0.7,
      decoSetpoint: 1.4,
      lastStopDepthMeters: 6,
      availableTanks: const [kAl40, kAl80],
    );
    expect(result.diveAscent, isNotEmpty);
    expect(result.bailout.perGas, isNotEmpty);
    expect(result.cnsPercent, greaterThan(0));
    expect(result.totalRuntime.inMinutes, greaterThanOrEqualTo(20));
  });

  test('NDL dive (no deco required) returns empty schedule but still '
      'computes a bailout plan', () {
    final result = runPlan(
      gases: const [
        DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ],
      segments: const [
        DivePlanSegment(
            depthMeters: 15,
            durationMinutes: 10,
            gasMixIndex: 0,
            setpoint: 1.0),
      ],
      bailout: const [
        DivePlanBailoutBottle(
            gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
      ],
      mode: DivePlanMode.cc,
      gfLow: 30, gfHigh: 85, useVpmb: false, vpmbConservatism: 2,
      ascentRateMpm: 9, descentRateMpm: 18,
      bottomSetpoint: 1.0, ascentSetpoint: 0.7, decoSetpoint: 1.4,
      lastStopDepthMeters: 6, availableTanks: const [kAl40, kAl80],
    );
    expect(result.diveAscent, isEmpty,
        reason: 'NDL → planDeco returns []');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/analysis/planner/plan_runner_test.dart`
Expected: FAIL — `plan_runner.dart` doesn't exist.

- [ ] **Step 3: Implement the orchestrator**

Create `lib/analysis/planner/plan_runner.dart`:

```dart
/// Orchestrates the full plan computation:
///   simulator → trigger tissues → planDeco → planBailout → PlanResult.
library;

import '../bailout/bailout_planner.dart' show planBailout;
import '../bailout/tank_recommender.dart' show TankSpec;
import '../deco/deco_planner.dart' show planDeco;
import '../../data/models/dive.dart' show DiveGasMix;
import '../../data/models/dive_plan.dart';
import 'plan_result.dart';
import 'plan_simulator.dart';

PlanResult runPlan({
  required List<DivePlanGas> gases,
  required List<DivePlanSegment> segments,
  required List<DivePlanBailoutBottle> bailout,
  required DivePlanMode mode,
  required int gfLow,
  required int gfHigh,
  required bool useVpmb,
  required int vpmbConservatism,
  required int ascentRateMpm,
  required int descentRateMpm,
  required double bottomSetpoint,
  required double ascentSetpoint,
  required double decoSetpoint,
  required double lastStopDepthMeters,
  required List<TankSpec> availableTanks,
}) {
  // Phase 1+2: walk the segments, get trigger tissues + summary stats.
  final sim = simulatePlan(
    gases: gases,
    segments: segments,
    mode: mode,
    descentRateMpm: descentRateMpm,
    ascentRateMpm: ascentRateMpm,
    bottomSetpoint: bottomSetpoint,
    ascentSetpoint: ascentSetpoint,
    decoSetpoint: decoSetpoint,
  );

  // Phase 3: deco schedule from end-of-bottom tissues.
  final diveGasMixes = gases.map(_toDiveGasMix).toList();
  final diveAscent = planDeco(
    initialN2Bar: sim.triggerN2Bar,
    initialHeBar: sim.triggerHeBar,
    triggerDepthMeters: sim.triggerDepthMeters,
    gases: diveGasMixes,
    gfLow: gfLow,
    gfHigh: gfHigh,
    ascentRateFastMPerMin: ascentRateMpm,
    ascentRateSlowMPerMin: ascentRateMpm,
    ppo2LimitBottom: 1.6,
    ppo2LimitDeco: 1.6,
  );

  // Phase 4: bailout plan (Scenario A — user-supplied tanks).
  final userBailoutTanks = <DiveGasMix>[];
  final userTankVolumesL = <DiveGasMix, double>{};
  for (final bottle in bailout) {
    final mix = _toDiveGasMix(gases[bottle.gasMixIndex]);
    userBailoutTanks.add(mix);
    userTankVolumesL[mix] =
        (userTankVolumesL[mix] ?? 0) +
            bottle.waterCapacityL * bottle.fillPressureBar;
  }
  final bailoutResult = planBailout(
    diveId: 'plan-${DateTime.now().microsecondsSinceEpoch}',
    maxDepthMeters: sim.triggerDepthMeters,
    triggerDepthMeters: sim.triggerDepthMeters,
    recordedDiluent: gases.isEmpty ? null : _toDiveGasMix(gases.first),
    tissueN2Bar: sim.triggerN2Bar,
    tissueHeBar: sim.triggerHeBar,
    userBailoutTanks: userBailoutTanks,
    userTankVolumesL: userTankVolumesL,
    bailoutCapableDiluent: false,
    gfLow: gfLow,
    gfHigh: gfHigh,
    sacBottom: 30,
    sacDeco: 20,
    ascentRateFast: ascentRateMpm,
    ascentRateSlow: ascentRateMpm,
    availableTanks: availableTanks,
  );

  // Phase 5: assemble.
  return PlanResult(
    diveAscent: diveAscent,
    bailout: bailoutResult,
    cnsPercent: sim.cnsPercent,
    otuTotal: sim.otuTotal,
    maxDensityGramsPerLitre: sim.maxDensityGramsPerLitre,
    totalRuntime: sim.totalRuntime,
  );
}

DiveGasMix _toDiveGasMix(DivePlanGas g) => DiveGasMix(
      oxygenPercent: g.oxygenPercent,
      heliumPercent: g.heliumPercent,
      isDiluent: g.isDiluent,
    );
```

NOTE: VPM-B forward-simulation is flagged as an open risk in the spec §9; this MVP runner ignores `useVpmb` and always uses ZHL-16C. The parameters stay in the signature so the caller doesn't have to change when VPM-B lands. Add a comment near the top of `runPlan`:

```dart
  // VPM-B forward-simulation is deferred (spec §9). The toggle is
  // accepted to keep the call-site stable; we always compute with
  // ZHL-16C until the existing vpmb.dart is verified to work outside
  // the replay engine.
  // ignore: unused_local_variable
  final _ = useVpmb; // suppress unused-parameter lint
  // ignore: unused_local_variable
  final __ = vpmbConservatism;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/analysis/planner/plan_runner_test.dart`
Expected: PASS

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/analysis/planner/plan_runner.dart test/analysis/planner/plan_runner_test.dart
git commit -m "feat(plan): PlanRunner — simulator + planDeco + planBailout orchestrator"
```

---

## Task 9: Extract `_StopTable` to shared widget

**Files:**
- Create: `lib/ui/widgets/stop_ladder_table.dart`
- Modify: `lib/ui/widgets/bailout_section.dart`

- [ ] **Step 1: Pull the `_StopTable` class into its own file**

Cut everything from `class _StopTable extends StatelessWidget` through the end of its private helpers (including `_ConsolidatedRow`) out of `lib/ui/widgets/bailout_section.dart` and paste it into a new file `lib/ui/widgets/stop_ladder_table.dart`.

Rename: drop the leading underscores so the class is `StopLadderTable`. Drop the underscore on `_ConsolidatedRow` → `ConsolidatedStopRow`. Keep `_mixLabel` / `_fmtMinutes` private to the file (they don't need to be exported).

Add the required imports at the top of the new file:

```dart
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../../analysis/bailout/icd.dart'
    show IcdSeverity, icdSeverityBetween;
import '../../analysis/gas_density.dart' show mixDensityAt1Atm;
import '../../data/models/dive.dart' show DiveGasMix;
import '../theme/tokens.dart';
```

Constructor:

```dart
class StopLadderTable extends StatelessWidget {
  const StopLadderTable({
    super.key,
    required this.stops,
    required this.scheme,
    this.startingRuntime = Duration.zero,
    this.icdRedAccent = const Color(0xFFE74C3C),
    this.icdAmberAccent = const Color(0xFFF39C12),
  });

  final List<AscentStop> stops;
  final ColorScheme scheme;
  final Duration startingRuntime;
  final Color icdRedAccent;
  final Color icdAmberAccent;
  // ... rest of build / consolidate methods, identical to the original.
}
```

Expose `StopLadderTable.mixLabel(DiveGasMix)` as a `static String` so other widgets can format gases consistently:

```dart
  static String mixLabel(DiveGasMix g) {
    if (g.heliumPercent > 0) return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }
```

- [ ] **Step 2: Update `bailout_section.dart` to use the shared widget**

In `lib/ui/widgets/bailout_section.dart`:

1. Add `import 'stop_ladder_table.dart';`
2. Delete the now-moved `_StopTable` + `_ConsolidatedRow` classes.
3. Replace every `_StopTable(...)` usage with `StopLadderTable(...)`.
4. Replace every `_StopTable._mixLabel(x)` usage with `StopLadderTable.mixLabel(x)`.
5. Replace `_StopTable._fmtMinutes` references with the same private helper relocated INSIDE `bailout_section.dart` if it's still used there (it's used by `_formatStage` and `_IcdBanner`). Or, simpler: copy `_fmtMinutes` as a private top-level function in both files.

- [ ] **Step 3: Run full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean. All 871 existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/stop_ladder_table.dart lib/ui/widgets/bailout_section.dart
git commit -m "refactor(ui): extract _StopTable to shared StopLadderTable widget"
```

---

## Task 10: DivePlanNotifier

**Files:**
- Create: `lib/ui/notifiers/dive_plan_notifier.dart`
- Test: `test/ui/notifiers/dive_plan_notifier_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/ui/notifiers/dive_plan_notifier_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/notifiers/dive_plan_notifier_test.dart`
Expected: FAIL — `dive_plan_notifier.dart` doesn't exist.

- [ ] **Step 3: Implement the notifier**

Create `lib/ui/notifiers/dive_plan_notifier.dart`:

```dart
/// Editor state for the Dive Plan tab.
///
/// Holds the editable plan, the resolved settings (defaults + overrides),
/// and the most recent [PlanResult]. Edits are debounced-written to the
/// `dive_plans` draft row and trigger a synchronous re-compute.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../analysis/bailout/tank_recommender.dart';
import '../../analysis/planner/plan_result.dart';
import '../../analysis/planner/plan_runner.dart';
import '../../data/db/dive_plans_dao.dart';
import '../../data/models/dive_plan.dart';
import 'settings_notifier.dart';

/// Minimal DAO interface used by the notifier — lets the test fake it.
abstract class DivePlansDaoLike {
  Future<DivePlanDraft?> loadDraft();
  Future<void> upsertDraft(DivePlanDraft draft);
  Future<void> clearDraft();
  Future<List<SavedDivePlan>> listSaved();
  Future<DivePlanDraft?> loadSaved(String id);
  Future<SavedDivePlan> saveAs({required String name});
  Future<void> softDelete(String id);
  Future<void> renameSaved(String id, String name);
  Stream<void> watchChanges();
}

// Make the real DAO satisfy the interface trivially.
// (DivePlansDao already has these methods; just add a declaration.)

class DivePlanNotifier extends ChangeNotifier {
  DivePlanNotifier({required this.dao, required this.settings});

  final DivePlansDaoLike dao;
  final SettingsNotifier settings;

  // ── Editable state ─────────────────────────────────────────────────
  DivePlanMode _mode = DivePlanMode.cc;
  List<DivePlanGas> _gases = [];
  List<DivePlanSegment> _segments = [];
  List<DivePlanBailoutBottle> _bailout = [];
  DivePlanSettings _overrides = const DivePlanSettings();
  String? _notes;

  DivePlanMode get mode => _mode;
  List<DivePlanGas> get gases => List.unmodifiable(_gases);
  List<DivePlanSegment> get segments => List.unmodifiable(_segments);
  List<DivePlanBailoutBottle> get bailout => List.unmodifiable(_bailout);
  DivePlanSettings get overrides => _overrides;
  String? get notes => _notes;

  // ── Compute output ─────────────────────────────────────────────────
  PlanResult? _result;
  PlanResult? get result => _result;

  // ── Debounce ───────────────────────────────────────────────────────
  Timer? _saveTimer;
  static const _saveDelay = Duration(milliseconds: 250);

  Future<void> load() async {
    final draft = await dao.loadDraft();
    if (draft != null) {
      _mode = draft.mode;
      _gases = List.from(draft.gases);
      _segments = List.from(draft.segments);
      _bailout = List.from(draft.bailout);
      _overrides = draft.settings ?? const DivePlanSettings();
      _notes = draft.notes;
    }
    _recompute();
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────
  void addGas(DivePlanGas g) {
    _gases = [..._gases, g];
    _markDirty();
  }

  void removeGas(int idx) {
    _gases = [..._gases]..removeAt(idx);
    _markDirty();
  }

  void replaceGas(int idx, DivePlanGas g) {
    _gases = [..._gases]..[idx] = g;
    _markDirty();
  }

  void addSegment(DivePlanSegment s) {
    _segments = [..._segments, s];
    _markDirty();
  }

  void removeSegment(int idx) {
    _segments = [..._segments]..removeAt(idx);
    _markDirty();
  }

  void replaceSegment(int idx, DivePlanSegment s) {
    _segments = [..._segments]..[idx] = s;
    _markDirty();
  }

  void reorderSegments(int oldIdx, int newIdx) {
    final list = [..._segments];
    final moving = list.removeAt(oldIdx);
    list.insert(newIdx, moving);
    _segments = list;
    _markDirty();
  }

  void addBailoutBottle(DivePlanBailoutBottle b) {
    _bailout = [..._bailout, b];
    _markDirty();
  }

  void removeBailoutBottle(int idx) {
    _bailout = [..._bailout]..removeAt(idx);
    _markDirty();
  }

  void setOverrides(DivePlanSettings s) {
    _overrides = s;
    _markDirty();
  }

  Future<void> saveAs(String name) async {
    await dao.saveAs(name: name);
    // Saved-as clears the draft on the DAO side; reflect that locally too.
    _clearAll();
    _recompute();
    notifyListeners();
  }

  Future<void> loadSaved(String id) async {
    final draft = await dao.loadSaved(id);
    if (draft == null) return;
    _mode = draft.mode;
    _gases = List.from(draft.gases);
    _segments = List.from(draft.segments);
    _bailout = List.from(draft.bailout);
    _overrides = draft.settings ?? const DivePlanSettings();
    _notes = draft.notes;
    // The loaded saved plan becomes the new draft on the next save tick.
    await dao.upsertDraft(_snapshot());
    _recompute();
    notifyListeners();
  }

  Future<void> newPlan() async {
    await dao.clearDraft();
    _clearAll();
    _recompute();
    notifyListeners();
  }

  // ── Internals ──────────────────────────────────────────────────────

  void _clearAll() {
    _mode = DivePlanMode.cc;
    _gases = [];
    _segments = [];
    _bailout = [];
    _overrides = const DivePlanSettings();
    _notes = null;
  }

  void _markDirty() {
    _recompute();
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _writeDraft);
  }

  Future<void> _writeDraft() async {
    await dao.upsertDraft(_snapshot());
  }

  DivePlanDraft _snapshot() => DivePlanDraft(
        mode: _mode,
        gases: _gases,
        segments: _segments,
        bailout: _bailout,
        settings: _overrides,
        notes: _notes,
      );

  void _recompute() {
    if (_segments.isEmpty || _gases.isEmpty) {
      _result = null;
      return;
    }
    final tankCatalogue = <TankSpec>[
      kAl40,
      kAl50,
      kAl80,
      if (settings.tank68L300Available) kTank68L300,
      if (settings.tank12L300Available) kTank12L300,
    ];
    _result = runPlan(
      gases: _gases,
      segments: _segments,
      bailout: _bailout,
      mode: _mode,
      gfLow: _overrides.gfLow ?? settings.plannerGfLow,
      gfHigh: _overrides.gfHigh ?? settings.plannerGfHigh,
      useVpmb: _overrides.useVpmb ?? settings.plannerUseVpmb,
      vpmbConservatism: _overrides.vpmbConservatism ??
          settings.plannerVpmbConservatism,
      ascentRateMpm: _overrides.ascentRateMpm ?? settings.bailoutAscentRateSlow,
      descentRateMpm: _overrides.descentRateMpm ?? 18,
      bottomSetpoint: _overrides.bottomSetpoint ?? settings.plannerBottomSetpoint,
      ascentSetpoint: _overrides.ascentSetpoint ?? settings.plannerAscentSetpoint,
      decoSetpoint: _overrides.decoSetpoint ?? settings.plannerDecoSetpoint,
      lastStopDepthMeters:
          _overrides.lastStopDepthMeters ?? settings.plannerLastStopDepthMeters,
      availableTanks: tankCatalogue,
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
```

**Important:** the abstract `DivePlansDaoLike` must live in `lib/data/db/dive_plans_dao_api.dart` — NOT inline in the notifier — to avoid a UI → DAO → UI import cycle. Move the `abstract class DivePlansDaoLike { ... }` declaration shown above out of `dive_plan_notifier.dart` and into the new file. Imports become:

```dart
// dive_plans_dao.dart
import 'dive_plans_dao_api.dart';
class DivePlansDao implements DivePlansDaoLike { ... }

// dive_plan_notifier.dart
import '../../data/db/dive_plans_dao_api.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/notifiers/dive_plan_notifier_test.dart`
Expected: PASS

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/notifiers/dive_plan_notifier.dart lib/data/db/dive_plans_dao.dart test/ui/notifiers/dive_plan_notifier_test.dart
git commit -m "feat(plan): DivePlanNotifier — editor state + debounced draft auto-save"
```

---

## Task 11: PlanSettingsPanel widget (collapsible)

**Files:**
- Create: `lib/ui/widgets/plan_settings_panel.dart`
- Test: `test/ui/widgets/plan_settings_panel_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/ui/widgets/plan_settings_panel_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/plan_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows resolved one-line summary collapsed by default',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    DivePlanSettings? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSettingsPanel(
          settings: settings,
          overrides: const DivePlanSettings(),
          onChange: (s) => captured = s,
        ),
      ),
    ));
    expect(find.text('30/85'), findsOneWidget,
        reason: 'shows resolved GF in the summary');
    expect(find.text('1.3 / 0.7 / 1.4'), findsOneWidget,
        reason: 'shows resolved bottom/ascent/deco setpoints');
    captured; // not asserted; just keep the closure alive.
  });

  testWidgets('tapping the summary expands the override controls',
      (tester) async {
    final settings = SettingsNotifier();
    await settings.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSettingsPanel(
          settings: settings,
          overrides: const DivePlanSettings(),
          onChange: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('plan-settings-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('GF Low'), findsOneWidget);
    expect(find.text('GF High'), findsOneWidget);
    expect(find.text('Last stop'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/plan_settings_panel_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement the panel**

Create `lib/ui/widgets/plan_settings_panel.dart`:

```dart
/// Collapsible plan-level settings panel. Shows resolved values
/// (defaults + overrides) in a one-line summary; expand to override
/// individual settings.
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';

class PlanSettingsPanel extends StatefulWidget {
  const PlanSettingsPanel({
    super.key,
    required this.settings,
    required this.overrides,
    required this.onChange,
  });

  final SettingsNotifier settings;
  final DivePlanSettings overrides;
  final ValueChanged<DivePlanSettings> onChange;

  @override
  State<PlanSettingsPanel> createState() => _PlanSettingsPanelState();
}

class _PlanSettingsPanelState extends State<PlanSettingsPanel> {
  bool _expanded = false;

  int get _gfLow =>
      widget.overrides.gfLow ?? widget.settings.plannerGfLow;
  int get _gfHigh =>
      widget.overrides.gfHigh ?? widget.settings.plannerGfHigh;
  double get _bottomSp =>
      widget.overrides.bottomSetpoint ?? widget.settings.plannerBottomSetpoint;
  double get _ascentSp =>
      widget.overrides.ascentSetpoint ?? widget.settings.plannerAscentSetpoint;
  double get _decoSp =>
      widget.overrides.decoSetpoint ?? widget.settings.plannerDecoSetpoint;
  double get _lastStop =>
      widget.overrides.lastStopDepthMeters ??
      widget.settings.plannerLastStopDepthMeters;

  String _summary() {
    final algo = widget.overrides.useVpmb ?? widget.settings.plannerUseVpmb
        ? 'VPM-B+${widget.overrides.vpmbConservatism ?? widget.settings.plannerVpmbConservatism}'
        : '$_gfLow/$_gfHigh';
    final sp = '${_bottomSp.toStringAsFixed(1)} / ${_ascentSp.toStringAsFixed(1)} / ${_decoSp.toStringAsFixed(1)}';
    final last = '${_lastStop.toStringAsFixed(0)} m';
    return '$algo · $sp · $last';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('plan-settings-toggle'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Row(
              children: [
                Text('SETTINGS', style: AppTypography.label),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(_summary(),
                      style: AppTypography.caption,
                      overflow: TextOverflow.ellipsis),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: Spacing.sm, bottom: Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const SizedBox(width: 100, child: Text('GF Low')),
                  Expanded(child: _intField(
                      value: _gfLow,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(gfLow: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('GF High')),
                  Expanded(child: _intField(
                      value: _gfHigh,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(gfHigh: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Bottom SP')),
                  Expanded(child: _doubleField(
                      value: _bottomSp,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(bottomSetpoint: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Ascent SP')),
                  Expanded(child: _doubleField(
                      value: _ascentSp,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(ascentSetpoint: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Deco SP')),
                  Expanded(child: _doubleField(
                      value: _decoSp,
                      onChanged: (v) => widget.onChange(
                          widget.overrides.copyWith(decoSetpoint: v)))),
                ]),
                Row(children: [
                  const SizedBox(width: 100, child: Text('Last stop')),
                  Expanded(child: _doubleField(
                      value: _lastStop,
                      onChanged: (v) => widget.onChange(widget.overrides
                          .copyWith(lastStopDepthMeters: v)))),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _intField(
          {required int value, required ValueChanged<int> onChanged}) =>
      TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) onChanged(v);
        },
      );

  Widget _doubleField(
          {required double value,
          required ValueChanged<double> onChanged}) =>
      TextFormField(
        initialValue: value.toStringAsFixed(1),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        onChanged: (s) {
          final v = double.tryParse(s);
          if (v != null) onChanged(v);
        },
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/plan_settings_panel_test.dart`
Expected: PASS

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/plan_settings_panel.dart test/ui/widgets/plan_settings_panel_test.dart
git commit -m "feat(plan): PlanSettingsPanel — collapsible override panel"
```

---

## Task 12: PlanGasesEditor widget

**Files:**
- Create: `lib/ui/widgets/plan_gases_editor.dart`
- Test: `test/ui/widgets/plan_gases_editor_test.dart`

The pattern repeats the row-editor approach used in `bailout_section.dart`'s table. Each row exposes: O₂ %, He %, is-diluent toggle, delete. An "add gas" button appends a new row defaulted to 21/0/dil.

- [ ] **Step 1: Write failing test**

Create `test/ui/widgets/plan_gases_editor_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_gases_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add gas → onAdd called with default 21/0 diluent',
      (tester) async {
    DivePlanGas? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [],
          onAdd: (g) => added = g,
          onRemove: (_) {},
          onReplace: (_, __) {},
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('add-gas')));
    expect(added,
        const DivePlanGas(oxygenPercent: 21, heliumPercent: 0, isDiluent: true));
  });

  testWidgets('rows render existing gases', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanGasesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
            DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, __) {},
        ),
      ),
    ));
    expect(find.text('Tx21/35'), findsOneWidget);
    expect(find.text('EAN50'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/plan_gases_editor_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/plan_gases_editor.dart`:

```dart
/// Editor for the plan's gas list. Each row exposes O2/He inputs +
/// diluent toggle. Reordering is intentionally absent: gas index
/// stability is critical (segments reference by index).
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import 'stop_ladder_table.dart' show StopLadderTable;
import '../theme/tokens.dart';

class PlanGasesEditor extends StatelessWidget {
  const PlanGasesEditor({
    super.key,
    required this.gases,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
  });

  final List<DivePlanGas> gases;
  final ValueChanged<DivePlanGas> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int idx, DivePlanGas g) onReplace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GASES', style: AppTypography.label),
        for (var i = 0; i < gases.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(_label(gases[i]),
                      style: AppTypography.readoutSm),
                ),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Diluent', style: AppTypography.caption),
                    value: gases[i].isDiluent,
                    onChanged: (v) => onReplace(
                        i,
                        DivePlanGas(
                            oxygenPercent: gases[i].oxygenPercent,
                            heliumPercent: gases[i].heliumPercent,
                            isDiluent: v)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-gas'),
            icon: const Icon(Icons.add),
            label: const Text('Add gas'),
            onPressed: () => onAdd(const DivePlanGas(
                oxygenPercent: 21, heliumPercent: 0, isDiluent: true)),
          ),
        ),
      ],
    );
  }

  static String _label(DivePlanGas g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }
}
```

Note: this skeleton only shows the gas label + diluent toggle + delete. Editing the O2/He values inline is deferred to Task 17 (the full-page wire-up) where a "tap to edit" dialog or expanded row is added. The TestProgressTracker covers the add + remove cases first.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/plan_gases_editor_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/plan_gases_editor.dart test/ui/widgets/plan_gases_editor_test.dart
git commit -m "feat(plan): PlanGasesEditor — add/remove gas rows"
```

---

## Task 13: PlanSegmentsEditor widget

**Files:**
- Create: `lib/ui/widgets/plan_segments_editor.dart`
- Test: `test/ui/widgets/plan_segments_editor_test.dart`

Row format: Depth (m, int input) — Time (min, int input — 0 = switch) — Gas dropdown — Setpoint dropdown — delete. Drag-handle for reorder.

- [ ] **Step 1: Write failing test**

Create `test/ui/widgets/plan_segments_editor_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_segments_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add segment defaults to deepest existing depth + 10 m / 10 min',
      (tester) async {
    DivePlanSegment? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 30,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (s) => added = s,
          onRemove: (_) {},
          onReplace: (_, __) {},
          onReorder: (_, __) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('add-segment')));
    expect(added!.depthMeters, 40);
    expect(added!.durationMinutes, 10);
  });

  testWidgets('segment row shows depth + time + gas label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 50,
                durationMinutes: 20,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, __) {},
          onReorder: (_, __) {},
          mode: DivePlanMode.cc,
        ),
      ),
    ));
    expect(find.text('50 m'), findsOneWidget);
    expect(find.text('20 min'), findsOneWidget);
    expect(find.text('Tx21/35'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/plan_segments_editor_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/plan_segments_editor.dart`:

```dart
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import 'plan_gases_editor.dart' show PlanGasesEditor;
import '../theme/tokens.dart';

class PlanSegmentsEditor extends StatelessWidget {
  const PlanSegmentsEditor({
    super.key,
    required this.gases,
    required this.segments,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
    required this.onReorder,
    required this.mode,
  });

  final List<DivePlanGas> gases;
  final List<DivePlanSegment> segments;
  final ValueChanged<DivePlanSegment> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int idx, DivePlanSegment s) onReplace;
  final void Function(int oldIdx, int newIdx) onReorder;
  final DivePlanMode mode;

  static String _gasLabel(DivePlanGas g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SEGMENTS', style: AppTypography.label),
        for (var i = 0; i < segments.length; i++)
          Padding(
            key: ValueKey('seg-$i'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 60,
                    child: Text('${segments[i].depthMeters.toStringAsFixed(0)} m')),
                SizedBox(
                    width: 70,
                    child: Text('${segments[i].durationMinutes} min')),
                Expanded(
                  child: Text(_gasLabel(gases[segments[i].gasMixIndex])),
                ),
                if (mode == DivePlanMode.cc)
                  SizedBox(
                      width: 50,
                      child: Text(segments[i].setpoint == null
                          ? '—'
                          : segments[i].setpoint!.toStringAsFixed(1))),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-segment'),
            icon: const Icon(Icons.add),
            label: const Text('Add segment'),
            onPressed: () {
              double depth = 10;
              if (segments.isNotEmpty) {
                final deepest = segments
                    .map((s) => s.depthMeters)
                    .reduce((a, b) => a > b ? a : b);
                depth = deepest + 10;
              }
              onAdd(DivePlanSegment(
                depthMeters: depth,
                durationMinutes: 10,
                gasMixIndex: 0,
                setpoint: mode == DivePlanMode.cc ? 1.3 : null,
              ));
            },
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/plan_segments_editor_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/plan_segments_editor.dart test/ui/widgets/plan_segments_editor_test.dart
git commit -m "feat(plan): PlanSegmentsEditor — display + add/remove rows"
```

---

## Task 14: PlanBailoutBottlesEditor widget

**Files:**
- Create: `lib/ui/widgets/plan_bailout_bottles_editor.dart`
- Test: `test/ui/widgets/plan_bailout_bottles_editor_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/ui/widgets/plan_bailout_bottles_editor_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_bailout_bottles_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders existing bottles + add adds an AL40 @ 200 bar by default',
      (tester) async {
    DivePlanBailoutBottle? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanBailoutBottlesEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
          ],
          bottles: const [
            DivePlanBailoutBottle(
                gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200),
          ],
          onAdd: (b) => added = b,
          onRemove: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('5.7'), findsWidgets);
    expect(find.textContaining('200'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('add-bottle')));
    expect(added!.waterCapacityL, 5.7);
    expect(added!.fillPressureBar, 200);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/plan_bailout_bottles_editor_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/plan_bailout_bottles_editor.dart`:

```dart
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_plan.dart';
import '../theme/tokens.dart';

class PlanBailoutBottlesEditor extends StatelessWidget {
  const PlanBailoutBottlesEditor({
    super.key,
    required this.gases,
    required this.bottles,
    required this.onAdd,
    required this.onRemove,
  });

  final List<DivePlanGas> gases;
  final List<DivePlanBailoutBottle> bottles;
  final ValueChanged<DivePlanBailoutBottle> onAdd;
  final ValueChanged<int> onRemove;

  static String _gasLabel(DivePlanGas g) {
    if (g.heliumPercent > 0) {
      return 'Tx${g.oxygenPercent}/${g.heliumPercent}';
    }
    if (g.oxygenPercent == 21) return 'Air';
    return 'EAN${g.oxygenPercent}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('BAILOUT BOTTLES', style: AppTypography.label),
        for (var i = 0; i < bottles.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                    child: Text(
                        '${_gasLabel(gases[bottles[i].gasMixIndex])} · '
                        '${bottles[i].waterCapacityL.toStringAsFixed(1)} L · '
                        '${bottles[i].fillPressureBar} bar')),
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onRemove(i)),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-bottle'),
            icon: const Icon(Icons.add),
            label: const Text('Add bailout bottle'),
            onPressed: () => onAdd(const DivePlanBailoutBottle(
                gasMixIndex: 0, waterCapacityL: 5.7, fillPressureBar: 200)),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/plan_bailout_bottles_editor_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/plan_bailout_bottles_editor.dart test/ui/widgets/plan_bailout_bottles_editor_test.dart
git commit -m "feat(plan): PlanBailoutBottlesEditor — list + add bottle"
```

---

## Task 15: PlanOutputSection widget

**Files:**
- Create: `lib/ui/widgets/plan_output_section.dart`
- Test: `test/ui/widgets/plan_output_section_test.dart`

Wraps the dive-plan output (stop ladder + summary stats) + the bailout output (reusing `BailoutSection`).

- [ ] **Step 1: Write failing test**

Create `test/ui/widgets/plan_output_section_test.dart`:

```dart
import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/analysis/planner/plan_result.dart';
import 'package:ccrlogger/data/models/dive.dart';
import 'package:ccrlogger/ui/widgets/plan_output_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows summary chips when result is non-null', (tester) async {
    const air = DiveGasMix(
        oxygenPercent: 21, heliumPercent: 0, isDiluent: true);
    final result = PlanResult(
      diveAscent: const [],
      bailout: BailoutResult(
        scenario: BailoutScenario.tanksDefined,
        totalTime: const Duration(minutes: 5),
        stops: const [
          AscentStop(
              depthStartMeters: 0,
              depthEndMeters: 0,
              duration: Duration(minutes: 5),
              gas: air,
              volumeLitresConsumed: 100),
        ],
        perGas: {},
        verdict: BailoutVerdict.sufficient,
        verdictDetails: const [],
      ),
      cnsPercent: 12.5,
      otuTotal: 80,
      maxDensityGramsPerLitre: 4.2,
      totalRuntime: const Duration(minutes: 30),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanOutputSection(result: result, scheme: ThemeData.dark().colorScheme),
      ),
    ));
    expect(find.textContaining('CNS'), findsOneWidget);
    expect(find.textContaining('12.5'), findsOneWidget);
    expect(find.textContaining('OTU'), findsOneWidget);
  });

  testWidgets('shows hint when result is null (empty plan)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanOutputSection(result: null, scheme: ThemeData.dark().colorScheme),
      ),
    ));
    expect(find.textContaining('Add gases and segments'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/plan_output_section_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/plan_output_section.dart`:

```dart
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../../analysis/planner/plan_result.dart';
import 'stop_ladder_table.dart' show StopLadderTable;
import '../theme/tokens.dart';

class PlanOutputSection extends StatelessWidget {
  const PlanOutputSection({
    super.key,
    required this.result,
    required this.scheme,
  });

  final PlanResult? result;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text('Add gases and segments to see the dive plan.',
            style: AppTypography.caption),
      );
    }
    final ascentStops = r.diveAscent
        .map((s) => AscentStop(
              depthStartMeters: s.depthMeters,
              depthEndMeters: s.depthMeters,
              duration: s.duration,
              gas: s.gas,
              volumeLitresConsumed: 0,
            ))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('OUTPUT — DIVE PLAN', style: AppTypography.label),
        if (ascentStops.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text('NDL — no decompression required.',
                style: AppTypography.caption),
          )
        else
          StopLadderTable(stops: ascentStops, scheme: scheme),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: 16,
          children: [
            Text('CNS ${r.cnsPercent.toStringAsFixed(1)} %',
                style: AppTypography.caption),
            Text('OTU ${r.otuTotal.toStringAsFixed(0)}',
                style: AppTypography.caption),
            Text('ρ max ${r.maxDensityGramsPerLitre.toStringAsFixed(1)} g/L',
                style: AppTypography.caption),
            Text('TTS ${r.totalRuntime.inMinutes} min',
                style: AppTypography.caption),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/plan_output_section_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/plan_output_section.dart test/ui/widgets/plan_output_section_test.dart
git commit -m "feat(plan): PlanOutputSection — dive-plan output + summary chips"
```

---

## Task 16: SavedPlansSheet widget

**Files:**
- Create: `lib/ui/widgets/saved_plans_sheet.dart`
- Test: `test/ui/widgets/saved_plans_sheet_test.dart`

Modal bottom sheet listing saved plans, ordered by `updated_at DESC`, tap to load, swipe to delete.

- [ ] **Step 1: Write failing test**

Create `test/ui/widgets/saved_plans_sheet_test.dart`:

```dart
import 'package:ccrlogger/data/db/dive_plans_dao.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/saved_plans_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders saved plans with name + last-modified', (tester) async {
    final plans = [
      SavedDivePlan(
        id: 'p1',
        name: 'Cave dive 60m',
        updatedAt: DateTime(2026, 5, 19, 14, 30),
        mode: DivePlanMode.cc,
      ),
      SavedDivePlan(
        id: 'p2',
        name: 'Reef 30m',
        updatedAt: DateTime(2026, 5, 18, 10),
        mode: DivePlanMode.cc,
      ),
    ];
    String? loaded;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SavedPlansSheet(
          plans: plans,
          onLoad: (id) => loaded = id,
          onDelete: (_) {},
        ),
      ),
    ));
    expect(find.text('Cave dive 60m'), findsOneWidget);
    expect(find.text('Reef 30m'), findsOneWidget);
    await tester.tap(find.text('Cave dive 60m'));
    expect(loaded, 'p1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/saved_plans_sheet_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/saved_plans_sheet.dart`:

```dart
library;

import 'package:flutter/material.dart';

import '../../data/db/dive_plans_dao.dart' show SavedDivePlan;

class SavedPlansSheet extends StatelessWidget {
  const SavedPlansSheet({
    super.key,
    required this.plans,
    required this.onLoad,
    required this.onDelete,
  });

  final List<SavedDivePlan> plans;
  final ValueChanged<String> onLoad;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('No saved plans yet.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: plans.length,
      itemBuilder: (_, i) {
        final p = plans[i];
        return Dismissible(
          key: ValueKey(p.id),
          background: Container(color: Colors.red),
          onDismissed: (_) => onDelete(p.id),
          child: ListTile(
            title: Text(p.name),
            subtitle: Text(
                '${p.updatedAt.day}/${p.updatedAt.month}/${p.updatedAt.year} '
                '${p.updatedAt.hour}:${p.updatedAt.minute.toString().padLeft(2, '0')}'),
            onTap: () => onLoad(p.id),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/saved_plans_sheet_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/saved_plans_sheet.dart test/ui/widgets/saved_plans_sheet_test.dart
git commit -m "feat(plan): SavedPlansSheet — tap-to-load, swipe-to-delete"
```

---

## Task 17: DivePlanScreen — assembly + name/save header

**Files:**
- Create: `lib/ui/screens/dive_plan_screen.dart`
- Test: `test/ui/screens/dive_plan_screen_test.dart`

Top-level screen that owns the `DivePlanNotifier` and stitches all the child widgets together: header with name + Save-as + Saved-plans + New-plan buttons; settings panel; gases; segments; bailout bottles; output; bailout-section.

- [ ] **Step 1: Write failing test**

Create `test/ui/screens/dive_plan_screen_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/dive_plan_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifiers/dive_plan_notifier_test.dart' show _FakeDao;

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
```

NOTE: The test imports `_FakeDao` from the notifier test file. Make sure `_FakeDao` is not declared as private if it needs to be reused across files — promote to `FakeDivePlansDao` in a `test/test_support/` helper if cross-file reuse is needed. Or duplicate the minimal fake in both test files (DRY exception for tests).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/screens/dive_plan_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the screen**

Create `lib/ui/screens/dive_plan_screen.dart`:

```dart
library;

import 'package:flutter/material.dart';

import '../notifiers/dive_plan_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../widgets/bailout_section.dart';
import '../widgets/plan_bailout_bottles_editor.dart';
import '../widgets/plan_gases_editor.dart';
import '../widgets/plan_output_section.dart';
import '../widgets/plan_segments_editor.dart';
import '../widgets/plan_settings_panel.dart';
import '../widgets/saved_plans_sheet.dart';
import '../theme/tokens.dart';

class DivePlanScreen extends StatefulWidget {
  const DivePlanScreen({
    super.key,
    required this.notifier,
    required this.settings,
  });

  final DivePlanNotifier notifier;
  final SettingsNotifier settings;

  @override
  State<DivePlanScreen> createState() => _DivePlanScreenState();
}

class _DivePlanScreenState extends State<DivePlanScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          IconButton(
            tooltip: 'Saved plans',
            icon: const Icon(Icons.folder_open),
            onPressed: _openSavedSheet,
          ),
          IconButton(
            key: const ValueKey('new-plan'),
            tooltip: 'New plan',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: () => widget.notifier.newPlan(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.notifier,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Cave dive…')),
                  FilledButton.icon(
                    key: const ValueKey('save-as'),
                    onPressed: _promptSaveAs,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save as'),
                  ),
                ],
              ),
              const Divider(),
              PlanSettingsPanel(
                settings: widget.settings,
                overrides: widget.notifier.overrides,
                onChange: widget.notifier.setOverrides,
              ),
              const Divider(),
              PlanGasesEditor(
                gases: widget.notifier.gases,
                onAdd: widget.notifier.addGas,
                onRemove: widget.notifier.removeGas,
                onReplace: widget.notifier.replaceGas,
              ),
              const Divider(),
              PlanSegmentsEditor(
                gases: widget.notifier.gases,
                segments: widget.notifier.segments,
                onAdd: widget.notifier.addSegment,
                onRemove: widget.notifier.removeSegment,
                onReplace: widget.notifier.replaceSegment,
                onReorder: widget.notifier.reorderSegments,
                mode: widget.notifier.mode,
              ),
              const Divider(),
              PlanBailoutBottlesEditor(
                gases: widget.notifier.gases,
                bottles: widget.notifier.bailout,
                onAdd: widget.notifier.addBailoutBottle,
                onRemove: widget.notifier.removeBailoutBottle,
              ),
              const Divider(thickness: 2),
              PlanOutputSection(
                  result: widget.notifier.result, scheme: scheme),
              const SizedBox(height: Spacing.md),
              if (widget.notifier.result != null)
                BailoutSection(
                  result: widget.notifier.result!.bailout,
                  triggerDepthMeters: widget.notifier.segments.isEmpty
                      ? 0
                      : widget.notifier.segments
                          .where((s) => s.durationMinutes > 0)
                          .map((s) => s.depthMeters)
                          .fold<double>(
                              0, (acc, d) => d > acc ? d : acc),
                  sacBottom: widget.settings.bailoutSacBottom,
                  sacDeco: widget.settings.bailoutSacDeco,
                  bailoutCapableDiluent: widget.settings.bailoutCapableDiluent,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptSaveAs() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save plan as'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Plan name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.notifier.saveAs(name);
    }
  }

  Future<void> _openSavedSheet() async {
    final plans = await widget.notifier.dao.listSaved();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SavedPlansSheet(
        plans: plans,
        onLoad: (id) async {
          Navigator.of(context).pop();
          await widget.notifier.loadSaved(id);
        },
        onDelete: (id) async {
          await widget.notifier.dao.softDelete(id);
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/screens/dive_plan_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/screens/dive_plan_screen.dart test/ui/screens/dive_plan_screen_test.dart
git commit -m "feat(plan): DivePlanScreen assembly + save-as / new-plan / saved-plans"
```

---

## Task 18: Wire `Plan` destination into AppShell

**Files:**
- Modify: `lib/ui/app_shell.dart`

- [ ] **Step 1: Locate the bottom-nav block**

Read [lib/ui/app_shell.dart](lib/ui/app_shell.dart) around line 411 (the `BottomNavigationBar` `items: const [...]`) and around line 366 (the `IndexedStack children: [...]`).

- [ ] **Step 2: Add the destination + screen**

Add a new bottom-nav item between Dives and Import:

```dart
        BottomNavigationBarItem(
          icon: Icon(Icons.event_note_outlined),
          label: 'Plan',
        ),
```

Add the screen instance to the `IndexedStack children` in the same position:

```dart
                DivePlanScreen(
                  notifier: _divePlanNotifier,
                  settings: widget.settingsNotifier,
                ),
```

In the `_AppShellState` class, instantiate `_divePlanNotifier` next to the other notifiers (search for `_diveListNotifier` initialisation):

```dart
  late final DivePlanNotifier _divePlanNotifier =
      DivePlanNotifier(dao: _divePlansDao, settings: widget.settingsNotifier);
```

And create `_divePlansDao`:

```dart
  late final DivePlansDao _divePlansDao =
      DivePlansDao(widget.powerSyncDb, _sessionSource);
```

(`_sessionSource` is the existing `SessionSource` instance already wired up for the other DAOs — search the file for `SessionSource` to find the variable name.)

Call `_divePlanNotifier.load()` inside `initState()`:

```dart
    super.initState();
    // ... existing ...
    _divePlanNotifier.load();
```

Add imports at the top:

```dart
import '../data/db/dive_plans_dao.dart';
import 'notifiers/dive_plan_notifier.dart';
import 'screens/dive_plan_screen.dart';
```

- [ ] **Step 3: Manually verify in dev**

Run: `flutter run` and confirm:
- The bottom-nav has 5 items now: Dives, Plan, Import, Equipment, Settings.
- Tapping Plan opens the new screen.
- Add a gas + segment; restart the app; data is still there (draft auto-save works).
- Save as "Test plan"; tap Saved plans; "Test plan" appears.

- [ ] **Step 4: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/app_shell.dart
git commit -m "feat(plan): wire Plan tab into AppShell bottom navigation"
```

---

## Task 19: End-to-end widget test

**Files:**
- Create: `test/ui/screens/dive_plan_e2e_test.dart`

- [ ] **Step 1: Write the test**

Create `test/ui/screens/dive_plan_e2e_test.dart`:

```dart
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/notifiers/dive_plan_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifiers/dive_plan_notifier_test.dart' show _FakeDao;

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
      home: DivePlanScreen(notifier: notifier, settings: settings),
    ));

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
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/ui/screens/dive_plan_e2e_test.dart`
Expected: PASS

- [ ] **Step 3: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: Clean. All tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/ui/screens/dive_plan_e2e_test.dart
git commit -m "test(plan): end-to-end widget test for add-gas → add-segment → result"
```

---

## Note on OwnerIdBackfiller

The spec §6 mentioned extending `OwnerIdBackfiller` for offline-create-then-sign-in flows. **This is not needed for `dive_plans`** — `OwnerIdBackfiller` exists to copy *legacy Drift rows* into PowerSync's local DB on first sign-in. `dive_plans` is PowerSync-resident from day one; rows live in PowerSync's database immediately, even when signed out (`owner_id` starts null). When the user signs in, PowerSync's own upload retry stamps `owner_id` via the same in-place UPDATE pattern that `_stampOwnerIdInPlace` uses for `dives` / `dive_samples` today. Add the table name to that call site only if we observe rows getting stranded with null `owner_id` in practice — until then, no backfiller change is needed.

## Cross-cutting verification (after all tasks complete)

- [ ] `flutter analyze` clean
- [ ] `flutter test` — all suites green, expect ~880+ total
- [ ] Run on a device: open Plan tab, add gas+segment, see dive plan output + summary chips + bailout section
- [ ] Restart app: draft survives (draft auto-save working)
- [ ] Save as "Foo", New plan, open Saved plans → "Foo" appears, tap it → plan reloads
- [ ] Sign in: confirm `dive_plans` rows show on the Supabase dashboard with the right `owner_id`
- [ ] Sign in on a second device: saved plans appear there too (PowerSync round-trip works)
