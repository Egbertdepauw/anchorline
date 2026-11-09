# Bailout Gas Scenarios — Design Spec

**Date:** 2026-05-13
**Track:** D of the four-track 2026-05-13 wishlist.
**Depends on:** Track C (tissue replay) — uses
`DecoReplayEngine.tissueStateAt(diveId, sampleIndex)` to forward-simulate
the OC ascent.

## Goal

Add a new "Bailout" section to the dive detail screen below Notes,
showing the OC gas requirement for a worst-case loop failure at the end
of bottom time. Two scenarios:

- **A** — user has defined BO tanks on the dive: compute volumes,
  compare against available, surplus/shortfall verdict
- **B** — no BO tanks defined: assume standard gases,
  recommend tank sizes + minimum fill pressures

The user gets a concrete answer to "did I carry enough gas?" or "what
should I carry on a dive like this?"

## Why

Every tech CCR diver builds bailout scenarios by hand for big dives.
The math is well-defined: ascent profile + deco schedule × SAC × gas
volume. Doing it post-dive against the actual recorded profile gives
direct feedback on whether the bailout plan was adequate, AND for
casual dives where the diver didn't pre-plan, shows what they should
have been carrying. It's a uniquely-CCR feature that no other mobile
log does.

## Decisions locked during brainstorming

- **Trigger point:** last sample at max depth (end of bottom phase).
  Less conservative than first sample at max depth, more realistic for
  the "failure on the way up" scenario most divers worry about.
- **SAC rates (two-tier, both Settings-configurable):**
  - `bailoutSacBottom` default **30 L/min** — initial ascent
  - `bailoutSacDeco` default **20 L/min** — deco stops (diver has
    settled)
- **Ascent rates (two-tier, both Settings-configurable):**
  - `bailoutAscentRateFast` default **18 m/min** — trigger → slowdown
    point
  - `bailoutAscentRateSlow` default **9 m/min** — slowdown point →
    surface
  - **Slowdown point:** the deeper of `{first gas switch depth,
    half-max-pressure depth}` where half-pressure depth = `(maxDepth −
    10) / 2`
- **Gas switch logic:** at the deepest stop where PPO2 ≤ 1.6 for the
  gas being switched to (MOD-based)
- **Stop intervals:** 3 m increments
- **Deco schedule:** pulled from Track C's replay engine using the
  algorithm + parameters the dive is configured with
- **Bottom-mix gas selection:**
  1. If DC reports the dive's diluent mix → use it
  2. Otherwise, compute optimal `(O₂, He)` using config-specific target
     (1.6 PPO2 full table, 1.0 PPO2 bailout-capable diluent) + END ≤ 39 m, then snap to the
     closest standard mix from the table
- **Bailout-capable diluent toggle** (Settings, default OFF): when ON, Scenario
  B drops the bottom-mix BO stage and uses diluent for the initial leg
- **Standard mix tables:**
  - Full bottom-mix table: `{21/35, 18/45, 15/55, 12/65, 10/70}`
  - Bailout-capable diluent bottom mixes: `{21/35, 18/45, 15/55}`
  - Deco mixes (both): `{EAN 32, EAN 50, O₂ 100%}`
- **Tank size catalogue (Settings):** `AL40` (5.7 L) and `AL80`
  (11.1 L) always available at 207 bar. `6.8 L/300 bar` and
  `12 L/300 bar` toggleable, default off.
- **Display:** scenario banner + 3-tile summary + per-stop table +
  verdict banner. Per-gas line in the verdict shows surplus/shortfall
  in both litres AND bar (bar phrasing reads better for divers).

## Scope

### In scope

1. **Bailout planner module** — pure Dart, leans on Track C:
   - `lib/analysis/bailout/standard_mixes.dart` — constant tables for
     `kBottomMixes`, `kBailoutDiluentBottomMixes`, `kDecoMixes`.
   - `lib/analysis/bailout/mix_resolver.dart` — `resolveBottomMix(dive,
     gasMixes, bailoutCapableDiluent) -> GasMix`. Uses DC-recorded diluent first;
     falls back to compute-then-snap.
   - `lib/analysis/bailout/ascent_simulator.dart` — given a trigger
     point, tissue state, list of available OC gases, and the
     settings (SAC rates + ascent rates), produce an `AscentPlan`:
     stops, durations, gas at each stop, volumes consumed.
   - `lib/analysis/bailout/tank_recommender.dart` — given the required
     volume per gas and the configured tank catalogue, recommend the
     smallest tank that fits and compute the minimum fill pressure.
   - `lib/analysis/bailout/bailout_planner.dart` — orchestrator. Reads
     dive context + settings, dispatches to Scenario A or B, returns
     `BailoutResult`.
   - `lib/analysis/bailout/bailout_result.dart` — value object:
     ```dart
     class BailoutResult {
       final BailoutScenario scenario;       // A or B
       final Duration totalTime;
       final List<AscentStop> stops;         // depth, duration, gas, volume
       final Map<GasMix, GasUsage> perGas;   // required, available (A),
                                             // recommended tank + min fill (B)
       final BailoutVerdict verdict;         // ok / partial / fail
       final List<String> verdictDetails;    // human-readable lines
     }
     ```

2. **SettingsNotifier extensions:**
   - `int get bailoutSacBottom` (default 30), `int get bailoutSacDeco`
     (default 20), `int get bailoutAscentRateFast` (default 18),
     `int get bailoutAscentRateSlow` (default 9), `bool get
     bailoutCapableDiluent` (default false), `bool get tankAl40Available`
     (always true; no setter), `bool get tankAl80Available` (always
     true; no setter), `bool get tank68L300Available` (default false,
     user toggle), `bool get tank12L300Available` (default false, user
     toggle).
   - SharedPreferences keys: `bailout_sac_bottom`, `bailout_sac_deco`,
     `bailout_ascent_fast`, `bailout_ascent_slow`, `bailout_capable_diluent`,
     `tank_6_8l_300_available`, `tank_12l_300_available`.

3. **Settings UI** — new "Bailout planning" subsection on the Settings
   screen:
   - Number inputs for the four rate values (with sensible min/max
     clamps: SAC 10–60 L/min, ascent rates 3–30 m/min)
   - Switch: "Diluent is bailout-capable (bailout-capable diluent)"
   - Switches: "6.8 L / 300 bar stage available", "12 L / 300 bar stage
     available"

4. **Dive detail UI** — new "Bailout" section below the Notes section
   on the Details tab:
   - `lib/ui/widgets/bailout_section.dart` — section header + scenario
     banner + 3-tile summary row + ascent table + verdict banner.
     Re-runs the planner via `ListenableBuilder` on whatever inputs
     change (algorithm dropdown, settings, annotations dirty flag for
     BO tank changes).

5. **Tank inference for Scenario A:**
   - The dive's `tanks` already carries `volumeLiters` and pressure
     readings per tank (existing parser output). Classify each tank
     by use:
     - `TankUsage.diluent` → ignore for bailout (already on loop)
     - `TankUsage.oxygen` → O₂ deco tank
     - Other → bailout tank, mix from the tank's gas-mix link
   - For each, compute `available_volume = (start_bar − end_bar) × waterCapacity_L`
     where `end_bar` is the recorded end pressure (or 0 if the dive
     used the full tank). Compare against `required_volume` from the
     ascent plan.

6. **Tests:**
   - `test/analysis/bailout/mix_resolver_test.dart` — verify the
     "best gas" math gives the expected snapped mixes (60 m full table →
     21/35; 60 m bailout-capable diluent → 15/55; 40 m full table → 32/0 if no helium needed;
     edge cases like dive depth < 20 m).
   - `test/analysis/bailout/ascent_simulator_test.dart` — fixture
     dives: known trigger point + tissue state → expected stops, gas
     usage, total time. Compare against hand-computed values.
   - `test/analysis/bailout/tank_recommender_test.dart` — given
     `volume = 1465 L` + AL40+AL80 catalogue, expect "AL80 @ 132 bar".
     Edge cases: volume needs > AL80 capacity → recommend 12L/300 (if
     enabled) or "no tank fits" verdict.
   - `test/analysis/bailout/bailout_planner_test.dart` — end-to-end:
     known dive + settings → BailoutResult with expected verdict
     (Scenario A "sufficient", Scenario A "O₂ short by 25 L", Scenario
     B with 3 recommended stages).
   - `test/ui/widgets/bailout_section_test.dart` — widget renders both
     scenarios; verdict colour reflects sufficiency; ascent table has
     expected rows.
   - Extend `test/ui/notifiers/settings_notifier_test.dart` with all
     new bailout-config round-trips.

### Out of scope for v1

- **Bailout-from-any-point interactive view** — tap on the chart, see
  bailout from that moment. Powerful but expensive (re-runs the deco
  engine + planner on every crosshair move). Defer.
- **Personal SAC derivation from the actual dive data** — `bailoutSac*`
  use the configured defaults. Could compute "your actual SAC during
  this dive × 1.5 stress factor" later. Edge case: dives without tank
  pressure data wouldn't support this.
- **Custom standard-mix tables** — the two standard-mix tables are
  hardcoded.
- **Tank reserve handling** — calculation assumes full usable capacity
  (`pressure × waterCap`). No "leave 500 psi at the surface" reserve.
  Most planners include this — could add a Settings entry later.
- **Multiple-failure scenarios** — single failure at trigger point
  only. No "what if your O₂ also fails on the 6 m stop" cascading
  analysis.
- **Non-standard tank sizes** — AL40, AL80, 6.8L/300, 12L/300 only. If
  user has S40, S80, S100, etc., the AL40/AL80 entries cover the
  equivalent capacity ranges close enough.

## Architecture

### Component flow

```
DiveDetailScreen.build (Details tab)
  ↓ inside _buildDetailsTab, below _buildAnnotationsSection
BailoutSection widget
  ↓ ListenableBuilder on [settingsNotifier, annotationsNotifier]
BailoutPlanner.plan(dive, samples, gasMixes, annotation, settings, replayEngine)
  ↓
1. Resolve scenario: A if any dive.tanks classifies as bailout, else B
2. Resolve bottom-mix gas:
   - DC has recorded diluent? → use it
   - Else → MixResolver.computeBestGas(maxDepth, isGue) → snap to standard
3. Pull tissue state at end-of-bottom-time index from replayEngine
4. AscentSimulator.run(triggerDepth, tissueState, availableOcGases, settings)
   → list of AscentStop {depth, duration, gas, volumeConsumed}
5. For Scenario A: per gas, compare volume_required vs volume_available
6. For Scenario B: per gas, TankRecommender.recommend(volume, catalogue)
7. Build BailoutResult with verdict
  ↓
BailoutSection renders: banner, summary tiles, ascent table, verdict.
```

### Helper data types

- `class GasMix { double o2; double he; double get n2 => 1 - o2 - he; }`
  (already exists in the codebase for parsed gas mixes)
- `class AscentStop { double depthMeters; Duration duration; GasMix gas; double volumeL; }`
- `enum BailoutScenario { tanksDefined, standardGases }` (A or B)
- `enum BailoutVerdict { sufficient, partialShortfall, insufficient }`
- `class TankSpec { String name; double waterCapacityL; int ratedPressureBar; }`
- `class GasUsage { double requiredL; double? availableL; TankSpec? recommendedTank; int? minFillPressureBar; }`

### Edge cases

- **No-deco dive:** ascent profile is `(triggerDepth → 0 m)` at the
  fast rate only — slowdown point doesn't apply because there's no
  first switch and half-pressure may be above 0 m. Treat as a
  straight ascent at `bailoutAscentRateFast` if maxDepth < 20 m, else
  apply the slowdown logic anyway.
- **Trigger depth < gas-switch depth:** if max depth was 18 m and
  first switch would be at 21 m, the ascent never has a switch — just
  goes from trigger to surface on the bottom mix. The slow-rate kicks
  in at half-pressure depth `(18-10)/2 = 4 m`.
- **No suitable standard mix:** the user dives a 100 m extreme that
  exceeds even 10/70's PPO2 limit at trigger depth. Verdict reports
  "no standard bottom mix viable" — caller would need a custom mix.
  Rare; flag clearly.
- **Tank pressure data missing on Scenario A:** dive carries tanks but
  no end-pressure recorded. Fall back to "full tank assumed" with a
  warning row in the verdict.

## Risks

- **Ascent simulator accuracy depends on Track C's replay engine
  fidelity.** If Track C's tissue model is 5 % off, every bailout
  calc is 5 % off. Fixture tests in Track C are the safety net.
- **Computing the ascent plan dynamically on every settings change**
  could feel laggy. Mitigation: the planner output is small;
  re-computing on a ListenableBuilder is sub-100 ms. The replay engine
  itself is cached (Track C), so the expensive part doesn't repeat.
- **Gas-switching logic is opinionated.** "Switch at deepest stop
  where PPO2 ≤ 1.6 for the new gas" is one convention; some divers
  use PPO2 ≤ 1.4 for deco gases. We hardcode 1.6 — Settings entry
  could come later if pushback.
- **Verdict copy is opinionated.** Phrasing like "Recommend carrying
  3 stages" is friendly but assumes the diver agrees with our
  protocol. Keep verdict text neutral and factual.

## Testing strategy

- Unit tests on every module (mix resolver, ascent simulator, tank
  recommender, planner orchestrator)
- Widget test on the section renderer with mock BailoutResult inputs
- Fixture-driven end-to-end: 3 dives × scenario A + B = 6 test cases.
  Inputs: dive file + tank config + settings. Outputs: verdict + per-gas
  volume. Hand-computed expected values.
- `flutter analyze` clean, full suite green

## Definition of done

1. Five analysis modules with unit tests
2. SettingsNotifier extensions + UI subsection
3. BailoutSection widget + test
4. Wired into DiveDetailScreen below the annotations section
5. `flutter analyze` clean, full test suite green
6. Manual smoke against a real dive: open a CCR trimix dive with BO
   tanks defined → see Scenario A with realistic volumes + verdict.
   Open a similar dive without BO tanks → see Scenario B with 3
   recommended stages + min fill pressures. Toggle the bailout-capable diluent in
   Settings → Scenario B drops to 2 stages. Bump bailoutSacBottom from
   30 to 40 in Settings → volumes recompute upward.
