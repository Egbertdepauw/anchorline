# Deco-based Bailout Planner — Design

## Goal

Replace the current fixed-time-step bailout simulator with a proper Bühlmann-with-GF deco engine. Bailout = deco plan + gas math. The plan must produce 3m stop increments starting from a GF-Low-derived first stop, with stop durations driven by tissue off-gassing under linearly-interpolated GF — i.e., something a tech diver would actually breathe to.

## Motivation

User feedback (2026-05-14):

> "The bailout is only useable combined with a deco plan. You cannot ascend without a deco plan, also not on bailout. The target of a bailout is 'not dying' so we need A) enough gas and B) a deco plan."

The current [`ascent_simulator.dart`](lib/analysis/bailout/ascent_simulator.dart) takes 1-minute steps at a fixed ascent rate. For a 40m bailout that produces stops at e.g. 22m, 13m, 4m — which is neither at 3m increments nor at a GF-Low first stop. The user with GF 50/95 from 40m expects a first stop around 15m or 12m, then 3m increments down to the surface.

## Architecture

Replace `ascent_simulator.simulateAscent` with `deco_planner.planDeco`. The planner runs a Bühlmann ZH-L16C engine with Erik-Baker GF on the initial tissue state, producing a list of `DecoStep` rows representing every leg of the ascent. The bailout planner consumes those rows + SAC rates to compute volumes.

The replay engine already does per-sample tissue evolution; we share the tissue model (`tissue_model.dart`) and Schreiner equation (`schreiner.dart`) with it. No new physics — just a different walk shape.

### Components

1. **`lib/analysis/deco/deco_planner.dart`** *(new)* — generic ZHL-16C+GF deco planner. Pure function: given tissue state + ambient conditions + gas list + GF settings, returns a list of `DecoStep`. No knowledge of SAC or bailout — that lives a layer up.

2. **`lib/analysis/bailout/ascent_simulator.dart`** *(rewrite)* — thin wrapper that calls `planDeco`, then walks the returned `DecoStep` rows and adds `volumeLitresConsumed` to each using `sacBottom` / `sacDeco` × ambient pressure × duration. Same public type `AscentPlan` so the bailout planner doesn't need a rewrite.

3. **`lib/analysis/bailout/bailout_planner.dart`** *(unchanged)* — keeps Scenario A/B detection, gas-list building, verdict logic. The safeguard that prepends a bottom mix stays.

### Algorithm: planDeco

```
input:
  initialN2Bar, initialHeBar : List<double> length 16 — tissue state at trigger
  triggerDepthMeters : double
  gases : List<DiveGasMix> — sorted by O2 ascending (bottom mix first)
  gfLow, gfHigh : int (1..100)
  ascentRateFastMPerMin, ascentRateSlowMPerMin : int

state:
  pN2, pHe : List<double> length 16, initialised from input
  currentDepth = triggerDepthMeters
  steps : List<DecoStep>

phase 1 — find first stop depth:
  Walk pN2/pHe up at the FAST ascent rate in 1m increments.
  At each depth, compute the ceiling using GF_Low (linear M-line):
    for each compartment c:
      totalLoad = pN2[c] + pHe[c]
      a, b = mix Bühlmann coefficients weighted by N2/He
      ceilingBar = (totalLoad - a × gfLow/100) × b ÷ (1 - gfLow/100 + gfLow/100 × b)
        — Erik-Baker formulation
    worstCeiling = max over compartments
  Stop at the deepest 1m point where worstCeiling > 0 — that's the
  ceiling-breach depth.
  Round UP to next multiple of 3 → firstStopDepthMeters.
  If no ceiling breach all the way to 0m, return [] (NDL dive).

phase 2 — stop ladder:
  ascentRate = ascentRateSlowMPerMin
  currentDepth = triggerDepthMeters
  // Ascent leg from trigger to first stop, at fast rate.
  walk up at FAST rate to firstStopDepthMeters, advancing tissues
    minute by minute, breathing the deepest-safe gas at each step.
  Record one DecoStep per minute (depthStart, depthEnd, duration=1min, gas).

  // At each stop, hold and check whether next-3m-up is allowed.
  loop:
    nextStopDepth = max(0, currentStopDepth - 3)
    // GF at this depth, linear between (firstStop, gfLow) and (surface, gfHigh):
    gfHere = lerp(currentStopDepth, firstStopDepth, gfLow, 0, gfHigh)
    minutesAtStop = 0
    while ceilingAt(nextStopDepth, gfHere) > nextStopDepth:
      advance tissues 1 minute at currentStopDepth
      minutesAtStop += 1
      record DecoStep(stop, duration=1min)
    // Ascend one 3m increment at slow rate.
    walk up to nextStopDepth at SLOW rate, record ascent DecoStep.
    currentStopDepth = nextStopDepth
    if currentStopDepth == 0: break

output:
  List<DecoStep> covering every minute from trigger to surface.
```

### DecoStep type

Same shape as the existing `AscentStop`, kept so the rest of the system doesn't churn:

```dart
class DecoStep {
  final double depthStartMeters;
  final double depthEndMeters;
  final Duration duration;
  final DiveGasMix gas;
}
```

`AscentStop` keeps `volumeLitresConsumed` since the gas-math layer fills it. We can either reuse `AscentStop` outright (drop `DecoStep`) or alias one to the other — implementation detail.

### Gas selection at each depth

Already in `_bestGasForDepth` (richest gas with PPO2 ≤ 1.6) — keep verbatim. The list order is bottom-mix-first per the existing safeguard in `bailout_planner.dart`.

### GF linear interpolation

Erik Baker convention:

```
gfAtDepth = gfLow + (gfHigh - gfLow) × (firstStopDepth - currentDepth) / firstStopDepth
```

i.e., at firstStopDepth → gfLow, at surface (0m) → gfHigh, linear in between.

### Ceiling formula (single compartment)

```
fN2 = pN2 / (pN2 + pHe)           // tissue N2 fraction
fHe = 1 - fN2
a = aN2 × fN2 + aHe × fHe
b = bN2 × fN2 + bHe × fHe
gf = gfFraction (0..1)
// Erik Baker: M-value reduced by GF
P_amb_tol = (P_tissue - a × gf) × b / (1 - gf + gf × b)
// or equivalently in depth-units:
ceilingMeters = max(0, (P_amb_tol - 1.013) × 10)
```

The replay engine's existing ceiling math (`zhl16c.dart:115-120`) uses the un-GF'd version `(totalLoad - a) × b` — we add the GF reduction here.

## Output mapping for the existing BailoutSection UI

A 40m dive on 21/0 air with GF 50/95 should produce (rough sketch):

```
40 → 15 m   |  ~2 min  |  21/0  |  ascent at fast rate (or slow)
15 m hold   |  ~2 min  |  21/0
15 → 12 m   |  ~20 s   |  21/0
12 m hold   |  ~2 min  |  21/0
12 → 9 m    |  ~20 s   |  21/0
9 m hold    |  ~3 min  |  21/0
9 → 6 m     |  ~20 s   |  21/0  (or switch to 50% if PPO2 OK)
6 m hold    |  ~4 min  |  EAN50 (after switch)
6 → 3 m     |  ~20 s   |  100% (after second switch)
3 m hold    |  ~6 min  |  100%
3 → 0 m     |  ~20 s   |  100%
```

`_StopTable._consolidate` already merges adjacent same-gas same-depth-range rows, so the displayed plan will compact this to one row per stop depth.

## What's NOT changing

- The Drift / Supabase / PowerSync schema for `dive_bailout_carry` (stable).
- The Scenario A/B detection in `bailout_planner.dart`.
- The safeguard prepending a bottom mix when user's lowest-O2 tank is unsafe at trigger depth.
- The `peakDepthN2Bar`/`peakDepthHeBar` plumbing from the replay engine.
- The `BailoutSection` widget (the new deco-driven stops just feed in via the existing `AscentStop` list).

## Tests

The new `deco_planner_test.dart` covers:

1. **NDL dive returns empty steps.** Surface-equilibrated tissues at 20m for 5 min → no deco.
2. **First-stop depth rounds up to 3m increment.** Heavily-loaded tissues from a deep dive produce a first stop at a multiple of 3m, not somewhere in between.
3. **GF Low is honored at first stop.** Diver at GF 30/85 has a deeper first stop than GF 70/85 on the same dive.
4. **Stops are at 3m increments.** Every `depthEndMeters` of a non-zero-duration stop is divisible by 3.
5. **Stop time grows with tissue load.** A heavier loading produces longer total stop time than a lighter loading on the same trigger depth.
6. **Gas switches at MOD.** EAN50 in the gas list starts being used at the deepest stop where its PPO2 ≤ 1.6 (≈22m).
7. **Plan reaches the surface.** Final step's `depthEndMeters` is 0.

`bailout_planner_test.dart` regressions stay green; only the **values** change (the existing tests assert structure: `stops.isNotEmpty`, `volumeByGas` non-empty, verdict logic).

## Out of scope

- VPM-B deco (the user's existing VPM-B replay is a linearised approximation; the bailout planner uses ZHL-16C+GF only for now).
- Air break protocol (5 min off-O2 every 20 min at 6/3m). Future enhancement.
- Backwards-deco ("would I have needed deco at X depth instead?") — separate feature.
- Reverse-profile / saw-tooth handling beyond the single trigger point.

## Acceptance

- A 40m dive on air with GF 50/95 produces a first stop at 15m or 12m, then stops at 9, 6, 3, 0.
- A no-deco-required dive produces an empty stop list (single-leg straight ascent).
- The existing `dive_bailout_carry` UI continues to work — adding a carry row changes the gas at each leg of the new deco-driven plan.
- The Scenario B plan picks a depth-safe bottom mix (Air or 21/35) at the trigger depth, not EAN 50 — same regression test passes.
