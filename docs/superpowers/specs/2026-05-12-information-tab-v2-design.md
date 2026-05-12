# Information Tab v2 — design

**Status:** approved 2026-05-12.

**Owner:** CCRLog UI / data.

**Context:** The Dive Detail screen has 4 tabs (Details, Information, Media, Equipment). After the design-system pass, the Information tab carries star ratings + temps + water type + atm pressure, but lacks two things divers want from Subsurface parity:

1. Dive Computer metadata (model, serial, firmware, deco params, sensor calibration, scrubber, etc.) — currently only visible piecemeal in stat row labels.
2. The Divemaster field — present in Subsurface and emitted by our Subsurface sync as a hardcoded empty string, but never stored or editable in CCRLog.

Item 11 of today's plan separately restructures the Details-tab site form into a 2-tab group (Form / Map) that defaults to Map when GPS coords exist — keeping the site information present but giving it visual weight that matches its frequency-of-use.

This spec covers all three items (1, 2, 11) as a single coherent "Information Tab v2" track because they ship together as a user-perceptible parity-with-Subsurface upgrade.

## Goals (this session)

1. Add a **Dive Computer** read-only section to the Information tab, mirroring Subsurface's parity fields plus Shearwater-specific extras (calibration, scrubber, log version).
2. Add a **Divemaster** field — new schema column, new editable input on the Details-tab annotations section, plumbed through the Subsurface mapper so future pushes carry the real value instead of the empty placeholder.
3. Replace the Details-tab **site form block** with a conditional 2-tab group (Form / Map). Hide the tab strip entirely when coords are missing — the form stands alone in that state.

## Non-goals (deferred)

- **Map polish** — zoom-to-dive, satellite toggle, provider choice (OSM vs Google). All Track 2.
- **Restructuring tab content** — buddies / tags / rating / notes / suit / weights stay exactly where they currently live. No moves between tabs.
- **Surface GF / Max GF / tissue traces** — Phase 3.
- **Dive Computer section being editable** — DC-derived fields are read-only; the data comes from the Shearwater binary parse. Subsurface-equivalent "edit" actions don't apply.
- **Sample-derived water-temp pre-fill** — already shipped (Information section receives `defaultWaterTempC` from sample stats).

## Architecture

### Item 1 — Divemaster field

Net-new schema + plumbing.

```
table dive_annotations
  + divemaster TEXT  (nullable, default null)

migration N
  ALTER TABLE dive_annotations ADD COLUMN divemaster TEXT;

DiveAnnotation
  + final String? divemaster;
  + copyWith(divemaster: Value<String?>)

DiveAnnotationsNotifier
  + String? get divemaster
  + setDivemaster(String?)

UI (Details tab → annotations section)
  + text input "Divemaster" placed near Buddies

Mapper (CcrlogToSubsurfaceMapper)
  - replace hardcoded `QuotedLine(key: 'divemaster', value: '')`
  + read annotation.divemaster ?? '' on emit
  + Subsurface push round-trips the real value

Bootstrap importer (SubsurfaceToCcrlogMapper)
  + extract divemaster value from existing Dive-NNN, store into annotation
```

PowerSync sync rules need a refresh too — `divemaster` is a new column on a synced table.

### Item 2 — Dive Computer section

Pure UI, read-only. No schema change. The data already exists on the `Dive` entity (model, firmware, gfLow, gfHigh, sampleIntervalMs, logVersion, units, sensorCalibration, calibratedSensorMask, aiMode, configuredStackSeconds, stackRemainingAtStartSeconds, stackRemainingAtEndSeconds) — we just expose it.

Layout (under the existing Information-tab content):

```
SectionHeader("Dive computer")
  DataRow  Model           = ShearwaterModel + display name
  DataRow  Serial          = hex
  DataRow  Firmware        = 0xN-prefixed hex
  DataRow  Deco model      = "Bühlmann ZHL-16 · GF L/H" / "VPM-B" / "VPM-B/GFS"
  DataRow  Sample interval = "N s" (intervalMs / 1000)
  DataRow  Log version     = "N (PNF)" if isPnf else "N"
  DataRow  Units           = "Metric" / "Imperial"

SectionHeader("Sensors")
  Custom row  Cell calibration  = three StatusDots (cell1/2/3 palette) + 4-decimal calibration value next to each
  DataRow     Calibrated mask   = "Cell 1, 2, 3" / "Cell 1, 3" / "None" (decoded from bitmask)
  DataRow     Air-integration   = "Off" / "Standard (2 tanks)" / "HP-CCR (4 tanks)" — decoded from aiMode

SectionHeader("Scrubber")  — only when configuredStackSeconds != null
  DataRow  Configured       = formatStackHm(configuredStackSeconds)
  DataRow  Remaining (start)= formatStackHm(stackRemainingAtStartSeconds)
  DataRow  Remaining (end)  = formatStackHm(stackRemainingAtEndSeconds)
  DataRow  Used this dive   = formatStackUsedMs(start - end)
```

The Scrubber sub-block is hidden when the diver hasn't enabled stack tracking (configured == null). Sensor calibration row uses a custom inline `Row` of `[StatusDot(cell.1 colour), NumericReadout(cal1), gap, StatusDot(cell.2), NumericReadout(cal2), gap, StatusDot(cell.3), NumericReadout(cal3)]` — no new component class needed, just composition.

`DiveInformationSection`'s constructor already receives the `Dive` object, so no plumbing changes.

### Item 11 — Site tab-group

The current Details-tab site block is a fixed `Column` containing site-name autocomplete + lat/long fields + action buttons. Replace with a conditional structure:

```
if siteLatitude == null || siteLongitude == null:
    render <SiteFormView>            // current widget, no tab strip
else:
    render
      DefaultTabController(length: 2, initialIndex: 1)   // default = Map
        TabBar([Form, Map])
        TabBarView([
          SiteFormView(),
          SiteMapView(lat, lon, siteName, onTap: openSitesMapScreen),
        ])
```

`SiteFormView` is just the current widget extracted as-is.

`SiteMapView` is a new small widget: renders an existing `SiteMiniMap` scaled wider, with a label strip overlay showing site name + lat/lon, and a tap target that opens the existing `SitesMapScreen`. No new map plumbing — the polish (zoom-to-dive, satellite toggle, provider) belongs to Track 2 and arrives in `SitesMapScreen` / `SiteMiniMap` separately.

The tab controller is created/disposed only when coords are present — when the user enters coords for the first time, the form re-renders into the tab-group automatically because `siteLatitude`/`siteLongitude` are watched via the notifier.

## Tests

- **Annotation schema** — golden test that the migration applies cleanly to an empty DB and to a DB seeded at the prior schema version.
- **DiveAnnotation model** — round-trip JSON / copyWith handles `divemaster`.
- **Mapper** — `mapDive` emits `divemaster "Wendy De Joode"` when annotation carries it; emits `divemaster ""` when null/empty (current behaviour).
- **Bootstrap import** — when source Dive-NNN has `divemaster "Bob"`, the imported annotation has `divemaster == 'Bob'`.
- **Information section widget test** — DC section renders all expected rows for a CCR Petrel 3 dive; Scrubber sub-block is hidden when configured stack is null; sensor calibration row shows three coloured dots.
- **Site tab-group widget test** — coords absent → no tab strip, form visible. Coords present → tab strip visible, Map tab is the initial tab, Form tab still reachable.

## Code-touch list

- `supabase/migrations/00NN_divemaster.sql` (or local Drift migration) — add column.
- `lib/data/db/tables.dart` + `database.g.dart` (regen) — schema update.
- `lib/data/models/annotation.dart` — `divemaster` field on `DiveAnnotation`.
- `lib/data/db/dive_annotations_dao.dart` — read/write the column.
- `lib/ui/notifiers/dive_annotations_notifier.dart` — getter/setter + dirty tracking.
- `lib/ui/widgets/dive_annotations_section.dart` — Divemaster text field.
- `lib/ui/widgets/dive_information_section.dart` — DC section appended.
- `lib/sync/subsurface_git/mapper.dart` — emit real divemaster value.
- `lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart` — read divemaster from imported Dive-NNN.
- `infra/powersync-sync-rules.yaml` — include `divemaster` in `dive_annotations` rules.
- `lib/ui/screens/dive_detail_screen.dart` — site block → conditional tab-group.
- `lib/ui/widgets/site_form_view.dart` (extracted from screen, new file) — the existing form.
- `lib/ui/widgets/site_map_view.dart` (new) — the Map-tab content.
- Tests in the same dirs.

## Risk & rollback

- The schema change is additive (new nullable column) — safe under PowerSync's local-first reconciliation.
- The mapper change reads a value that was empty before, so the Subsurface git history will show `divemaster ""` → `divemaster "Name"` for any dive where the user fills the new field. That's the expected user-visible change.
- If the new DC section reads `aiMode` / `calibratedSensorMask` decoding wrong (the bit-decoding logic is new UI code), the worst case is a misleading display string — no data loss. Covered by widget tests against known fixture values.
- The site tab-group is purely a presentational rearrangement; if the implementation has any bug, the rollback is to render the existing form unconditionally — no data implications.

## Open questions for review

None blocking — every shape is locked. Worth confirming once before implementation:

1. **Divemaster placement on the annotations section** — alongside Buddies (same row, two fields) or stacked beneath? I'll propose alongside; tell me before plan-writing if you'd rather stack.
2. **Migration target** — Drift local + Supabase migration both need to be updated. Plan task will cover both; flag here if Hetzner timing changes that decision.
