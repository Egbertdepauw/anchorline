# Statistics tab — design

**Date:** 2026-06-05
**Status:** Approved design (mockup + decisions), ready for implementation plan
**Source:** Wendy's wishlist, item "Dive statistics" (second of three; deco shipped on PR #60, renumbering still queued)

> Note: the project roadmap lists generalized cross-dive stats as Phase 3. This is being pulled forward at the user's explicit request, kept deliberately focused (the per-cell longitudinal view remains separate and out of scope here).

## Goal

A read-only **Statistics** screen summarizing the whole logbook: all-time records, dive-mode totals, a dives-per-year trend, and a year/month breakdown — Subsurface-style aggregates, but mobile-first and in CCRLog's dark instrument aesthetic. The approved mockup lives at `.superpowers/brainstorm/49555-1780661763/content/statistics.html`.

## Non-goals (v1)

- No charts beyond the single dives-per-year bar chart (depth histograms, SAC trends, etc. are later).
- No per-cell / longitudinal cell-health stats (that's a separate Phase-1 feature, not this screen).
- No unit preference — the app is metric-only today; stats render metric via the existing `format.dart` helpers.
- No CSV/stat export.
- No new synced data — the derived cache is device-local and re-derivable.

## Data approach: persistent derived-stats cache

Most stats come straight from the **dive rows** (PowerSync `dives`), which `DiveDao.getAllDives()` returns in one cheap query: count, `durationSeconds`, `maxDepthMm`, `diveMode`, `startTime`. These render with no sample decoding.

Two stat families need **per-sample** data: water temperature (coldest/warmest) and time-in-deco (longest deco). Decoding every dive's sample blob on each open doesn't scale, so we cache the derived per-dive values.

**Cache table (local Drift, NOT synced — re-derivable from raw):** `dive_derived_stats`
- `dive_id TEXT` (primary key)
- `parser_version INTEGER` — the sample-parser version that produced this row
- `min_water_temp_c REAL?` — null when the dive has no valid temperature samples
- `max_water_temp_c REAL?`
- `time_in_deco_seconds INTEGER` (default 0)

Stored in Drift (alongside `dive_raw_blobs`), keyed by `dive_id`. Device-local and re-derivable, so it does **not** sync (consistent with principle 7's "caches that exist purely to avoid recompute"). On a fresh device the cache is empty and repopulates lazily.

**Population — lazy, parser-version-invalidated:** when the Statistics screen opens, the notifier:
1. Loads all dive rows (`getAllDives()`).
2. Reads existing cache rows.
3. For any dive **missing a row** or whose `parser_version` ≠ the current parser version, loads its `SampleSet` (`DiveDao.getSamples`), computes the derived values, and upserts the cache row.
4. Aggregates and renders.

First-ever open (or after importing new dives) pays a one-time decode for the uncached dives, behind a progress indicator; every subsequent open is instant. (Eager population inside `importDive` is a possible later optimization, explicitly out of scope for v1.)

**Derived value computation** (reuse `lib/data/sample_codec/dive_stats.dart`):
- `min/max_water_temp_c`: from `minAvgMax(samples.temperatureCelsius, sampleCount)` (already NaN-safe for merged-dive gaps). Both null if no finite samples.
- `time_in_deco_seconds`: `totalTimeInDecoSeconds(...)` (the helper shipped with the deco feature).

The parser-version constant: reuse the existing sample-parser version used for raw-blob reparse tagging; if none is exposed as a constant, introduce one in the parser and reference it here.

## Information architecture (screen)

One vertically scrolling screen (`StatisticsScreen`), pushed as a route — **reached via a stats icon (`Icons.bar_chart`/`Icons.insights`) in the Dives screen's app bar**, not a bottom-nav tab. Sections top→bottom:

1. **Records** — all-time highlight cards (2-column grid), each reusing the existing `StatTile` (label + mono value + unit + optional hint):
   - Total dives · Total time · Deepest (m, + site·year hint) · Longest deco (min, + site·year) · Coldest (°C, + site·month) · Warmest (°C, + site·month).
   - Deepest/longest/coldest/warmest hints name the dive (site + date) they came from.
2. **By dive mode** — one row per present mode bucket (count desc), each with a mini bar + "N dives · Hh". Buckets: **CCR** (`DiveMode.isCcr`: cc, cc2, sc), **Open circuit** (ocTec, ocRec), **Gauge** (gauge), **Freedive**, **Other** (ppo2, avelo). Rows with zero count are hidden.
3. **Dives per year** — a compact bar chart, one bar per calendar year (height ∝ dive count), year label under each.
4. **Breakdown** — a segmented control **[By year | By month]**:
   - **By year:** one row per year (newest first) showing `dives · total time · deepest · coldest`; tapping a year expands to that year's months.
   - **By month:** a flat list of months (newest first), same per-row stats.

(This refines the mockup's three-segment control: the all-time summary is the top three sections, so the breakdown toggle is just year-vs-month grouping.)

Empty state: with zero dives, show a friendly "No dives yet — import some to see your stats" placeholder.

## Components / units

| Unit | File | Responsibility |
|---|---|---|
| Cache table | `lib/data/db/tables.dart` (+ `database.dart` migration) | `DiveDerivedStats` Drift table |
| Cache DAO | `lib/data/db/dive_derived_stats_dao.dart` | upsert / read-all / read-by-id of derived rows |
| Result models | `lib/analysis/stats/stats_result.dart` | `StatsResult`, `RecordStat`, `ModeTotal`, `PeriodStat` (pure data) |
| Aggregator | `lib/analysis/stats/dive_stats_aggregator.dart` | **pure** `aggregate(List<Dive>, Map<String, DerivedStats>, Map<String, String?> siteByDiveId) → StatsResult` |
| Notifier | `lib/ui/notifiers/statistics_notifier.dart` | load dives, load site names (annotations DAO) for record hints, ensure cache fresh (lazy populate), aggregate, expose result + loading/empty state |
| Screen | `lib/ui/screens/statistics_screen.dart` | scaffold + sections; composes the widgets below |
| Records grid | (reuse `lib/ui/components/stat_tile.dart`) | records cards |
| Mode breakdown | `lib/ui/widgets/stats_mode_breakdown.dart` | mode rows + bars |
| Year chart | `lib/ui/widgets/stats_year_chart.dart` | dives-per-year bars |
| Period list | `lib/ui/widgets/stats_period_list.dart` | year (expandable) / month list |
| Wiring | `lib/ui/screens/dive_list_screen.dart` | app-bar stats button → `Navigator.push(StatisticsScreen)` |

The **aggregator is pure and the unit-test centerpiece**: it takes plain dives + a derived-stats map and returns the fully-computed `StatsResult`. No I/O, no Flutter — fast and exhaustively testable.

## Stat definitions (exact)

- **Total dives** = count of live dives. **Total time** = Σ `durationSeconds`, shown `Hh Mm`.
- **Deepest** = max `maxDepthMm` (→ m, 1 dp); hint = that dive's site + year.
- **Longest deco** = max `time_in_deco_seconds`; shown whole minutes; hint = site + year. (Reuses the deco feature's definition — consistent with the dive summary's `Deco` tile.)
- **Coldest** = min over non-null `min_water_temp_c`; **Warmest** = max over non-null `max_water_temp_c`; both °C 1 dp; hint = site + month-year. Hidden/"—" if no dive has temperature.
- **Per-period (year/month) row:** dives = count; time = Σ duration; deepest = max maxDepth; coldest = min of non-null minTemp in the period.
- **Year bucketing** uses local-time year/month derived from `startTime` (epoch seconds) — the same local-time rendering `format.dart` already uses for dive dates.
- **Record hints** use the dive's annotated **site name** (omitted gracefully if the dive has no site) plus the date. Site names are loaded once by the notifier (cheap annotations query) and passed into the pure aggregator as `siteByDiveId`, so the aggregator stays I/O-free.

## Formatting

Reuse `lib/ui/util/format.dart`: `formatDepth` (mm→m), `formatDuration` (s→"Hh Mm"), `formatDateTime`/date helpers for hints. Temperature: render °C with 1 dp (add a tiny `formatTempC` helper if not present). All numeric values use the app's tabular `NumericReadout` (via `StatTile`) for steadiness.

## Edge cases

- **No dives:** empty-state placeholder; no crash, no cache work.
- **Dive with no valid temp** (e.g. some imports, merged-dive gaps): `min/max_water_temp_c` null; excluded from coldest/warmest and from period min-temp.
- **No deco dives at all:** "Longest deco" shows "—" (or 0); time-in-deco is 0 for NDL dives by definition.
- **Merged dives:** temperature via `minAvgMax` skips NaN; time-in-deco via `totalTimeInDecoSeconds` skips NaN — both already handled by the shipped helpers.
- **Large logbooks:** only uncached/stale dives decode samples; progress indicator during the one-time backfill; UI renders row-derived sections immediately where practical.

## Testing

- **Aggregator (primary, pure unit tests):** synthetic dives + derived map →
  - records (deepest/longest/coldest/warmest pick the right dive; ties; all-NDL → no longest deco; no-temp → no coldest/warmest),
  - mode bucketing (CCR groups cc/cc2/sc; zero buckets hidden),
  - per-year / per-month grouping and per-period min-temp/deepest,
  - empty input → empty result.
- **Cache DAO:** upsert + read round-trip; parser-version staleness detection (stale row recomputed).
- **Notifier:** lazy-populate path computes only for missing/stale dives (with a fake DAO).
- **Verify:** `flutter analyze` clean, `flutter test` green. Manual: open Stats from the Dives app bar on a real logbook; sanity-check records vs known dives; verify year/month expand.

## Files touched

**Create:** `dive_derived_stats_dao.dart`, `analysis/stats/stats_result.dart`, `analysis/stats/dive_stats_aggregator.dart`, `ui/notifiers/statistics_notifier.dart`, `ui/screens/statistics_screen.dart`, `ui/widgets/stats_mode_breakdown.dart`, `ui/widgets/stats_year_chart.dart`, `ui/widgets/stats_period_list.dart`, plus tests for the aggregator, cache DAO, and notifier.
**Modify:** `data/db/tables.dart` + `data/db/database.dart` (new table + migration), `ui/screens/dive_list_screen.dart` (app-bar entry), and `dive_stats.dart` only if a `formatTempC`-style helper lands there (else `format.dart`).

## Resolved decisions

- **Data:** persistent, device-local, parser-version-tagged derived-stats cache; lazy population on stats open; reuse `dive_stats.dart` helpers.
- **Nav:** stats icon in the Dives app bar → pushed `StatisticsScreen` (bottom nav stays at 6).
- **Content/structure:** the approved mockup — Records cards, By-mode, dives-per-year chart, and a By-year (expandable) / By-month breakdown.
- **Records set (v1):** total dives, total time, deepest, longest deco, coldest, warmest. Extensible later.
