# Dive Bailout Carry — Design

## Goal

Model the per-dive list of OC bailout cylinders so the bailout planner runs against the gases the diver actually carried that day, not a guess from global equipment state.

## Motivation

The current Bailout panel either runs Scenario B (GUE standards) or reads `cylinders.gasMix` globally and treats every `role='bailout'` cylinder as carried on every dive. Both are wrong:

- A cylinder is a physical vessel — volume, working pressure, hydro, serial. What's *in* it varies per fill.
- Bailout carry varies per dive: a 50m trimix dive might carry trimix + 50% + O2; a 20m rec dive might carry a single AL40 of EAN 50.

## Architecture

Two-part model, separating physical from per-dive:

1. **`cylinders`** (general Equipment) becomes strictly physical. The `gas_mix` column is dropped.
2. **`dive_bailout_carry`** (new) records "for dive X, I carried cylinder C with gas G at fill pressure P, in breathing order N".

The bailout planner reads `dive_bailout_carry` for the current dive and produces `userBailoutTanks` + `userTankVolumesL` from it. When the table is empty for a dive, Scenario B continues to apply.

## Schema

### Drift

```dart
class DiveBailoutCarry extends Table {
  TextColumn get id => text()();                                      // composite of (diveId, cylinderId) hashed
  TextColumn get diveId => text().references(Dives, #id)();
  TextColumn get cylinderId => text().references(Cylinders, #id)();
  TextColumn get gasMix => text()();                                  // "21/35", "100", "32"
  IntColumn get fillPressureBar => integer().nullable()();            // null → use cylinder.workingPressureBar
  IntColumn get bailoutOrder => integer()();                          // 1, 2, 3 … bottom-first

  // standard sync columns
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

### Supabase migration

```sql
-- 0011_dive_bailout_carry.sql
ALTER TABLE cylinders DROP COLUMN gas_mix;

CREATE TABLE dive_bailout_carry (
  id text PRIMARY KEY,
  dive_id text NOT NULL REFERENCES dives(id),
  cylinder_id text NOT NULL REFERENCES cylinders(id),
  gas_mix text NOT NULL,
  fill_pressure_bar integer,
  bailout_order integer NOT NULL,
  owner_id text REFERENCES auth.users(id),
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_dive_bailout_carry_owner_dive
  ON dive_bailout_carry (owner_id, dive_id);

ALTER TABLE dive_bailout_carry ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner can rw" ON dive_bailout_carry
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

NOTIFY pgrst, 'reload schema';
```

### PowerSync sync rules

Add a line to [infra/powersync-sync-rules.yaml](infra/powersync-sync-rules.yaml):

```yaml
- SELECT * FROM dive_bailout_carry WHERE owner_id = bucket.user_id
```

## DAO API

In `EquipmentDao`:

```dart
Stream<void> watchDiveBailoutCarry(String diveId);

Future<List<DiveBailoutCarry>> listBailoutCarry(String diveId);

Future<void> addBailoutCarry({
  required String diveId,
  required String cylinderId,
  required String gasMix,
  int? fillPressureBar,
  required int bailoutOrder,
});

Future<void> updateBailoutCarry(
  String id, {
  String? gasMix,
  int? fillPressureBar,
  int? bailoutOrder,
});

Future<void> deleteBailoutCarry(String id);
```

## UI

Dive Detail → Equipment tab gets a new section below the existing dive_cylinders mapping table:

```
─── Bailout carry ───────────────────────
Order   Cylinder         Gas      Fill
1       AL40 stage       21/35    200 bar [edit] [×]
2       AL40 stage       50       200 bar [edit] [×]
3       AL40 stage       100      200 bar [edit] [×]
[+ Add cylinder]
```

- "+ Add cylinder" opens a bottom-sheet picker showing global Cylinders. Picking one creates a `dive_bailout_carry` row with fill pressure defaulted to the cylinder's `workingPressureBar`.
- Each row inline-edits gas + fill pressure. Order can be reordered by drag handle.
- Cylinders already in `dive_cylinders` (loop diluent / O2 etc.) are still selectable for bailout — they're the same physical vessels.

## Planner wiring

In `_buildBailoutSection`:

```dart
return StreamBuilder<void>(
  stream: widget.equipmentDao.watchDiveBailoutCarry(widget.dive.id),
  builder: (context, _) => FutureBuilder<List<({DiveBailoutCarry row, Cylinder cyl})>>(
    future: widget.equipmentDao.listBailoutCarryWithCylinders(widget.dive.id),
    builder: (context, snap) {
      final carry = snap.data ?? const [];
      // userBailoutTanks = [for c in carry parseGas(c.row.gasMix)]
      // userTankVolumesL[mix] += cyl.volumeLiters * (c.row.fillPressureBar ?? cyl.workingPressureBar)
      ...
    },
  ),
);
```

The planner safeguard from earlier (prepend bottom mix when first user gas is unsafe at depth) stays — covers the case where the diver only carries deco tanks.

## Migration of existing data

There is no production data to migrate — gasMix has only been used by my recent broken wiring. The Drift migration drops the column; the Supabase migration drops it too. Local cleanup: the previous attempt may have left `role='bailout'` flags on cylinders the user didn't intend. The user can resolve this manually by editing those cylinders' roles back; no automated migration step.

## Out of scope

- Auto-suggesting bailout mixes from depth / END (Scenario B already does this; carry is an explicit override).
- Reusing dive_cylinders for the loop-gas mapping; that stays as-is.
- Tracking what was actually breathed mid-dive as bailout (would need correlation against samples; a separate feature).

## Acceptance

- A dive with no `dive_bailout_carry` rows produces a Scenario B plan.
- A dive with `dive_bailout_carry` rows produces a Scenario A plan using exactly those gases and volumes.
- Editing a cylinder in global Equipment (e.g. volume) reflects immediately in any dive's bailout plan that uses it.
- The PostgREST upload error on `display_deco_algorithm` stays fixed (no related changes here).
