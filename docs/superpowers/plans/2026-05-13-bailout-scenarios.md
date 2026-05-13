# Bailout Scenarios Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Depends on:** Track C must be merged first — this plan uses `DecoReplayEngine.tissueStateAt()` for the ascent simulation. Do not start Task 4 of this plan until Track C is shipped.

**Goal:** Add a "Bailout" section below Notes on the dive detail screen that computes the OC gas requirement for a worst-case loop failure at end-of-bottom-time. Scenario A when the user has BO tanks; Scenario B (GUE standards) otherwise.

**Architecture:** Five pure-Dart analysis modules build the planner (`standard_mixes.dart` constants, `mix_resolver.dart` picks bottom mix, `ascent_simulator.dart` walks the planned ascent, `tank_recommender.dart` matches volumes to tank catalogue, `bailout_planner.dart` orchestrates). A new `BailoutSection` widget renders the result. Settings extension adds 5 new fields (two SAC rates, two ascent rates, GUE-config toggle) plus tank-catalogue toggles.

**Tech Stack:** Flutter, flutter_test, dart:typed_data

**Spec:** [docs/superpowers/specs/2026-05-13-bailout-scenarios-design.md](../specs/2026-05-13-bailout-scenarios-design.md)

---

## Task 1: Standard mix tables + mix resolver

**Files:**
- Create: `lib/analysis/bailout/standard_mixes.dart`
- Create: `lib/analysis/bailout/mix_resolver.dart`
- Create: `test/analysis/bailout/mix_resolver_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/analysis/bailout/mix_resolver_test.dart`:

```dart
import 'package:ccrlogger/analysis/bailout/mix_resolver.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBottomMix — DC-recorded diluent', () {
    test('returns the dive\'s recorded diluent verbatim', () {
      final mix = resolveBottomMix(
        recordedDiluent: DiveGasMix(o2: 18, he: 45, diluent: true),
        maxDepthMeters: 60,
        isGueConfig: false,
      );
      expect(mix.o2, 18);
      expect(mix.he, 45);
    });
  });

  group('resolveBottomMix — non-GUE compute-and-snap', () {
    test('60 m max depth → snaps to 21/35', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 60,
        isGueConfig: false,
      );
      expect(mix.o2, 21);
      expect(mix.he, 35);
    });

    test('40 m max depth → snaps to 21/35 (helium needed for END < 39m)', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 40,
        isGueConfig: false,
      );
      // (40+10)(1-He) ≤ 49 → He ≥ 0.02. Snap to 21/35 closest standard
      // since 21/35 satisfies both PPO2 1.6 and END 39 constraints.
      expect(mix.o2, 21);
      expect(mix.he, 35);
    });

    test('80 m max depth → snaps to 12/65 (deeper than 21/35 PPO2-1.6 MOD)', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 80,
        isGueConfig: false,
      );
      expect(mix.o2, 12);
      expect(mix.he, 65);
    });
  });

  group('resolveBottomMix — GUE compute-and-snap', () {
    test('60 m max depth → snaps to 15/55', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 60,
        isGueConfig: true,
      );
      expect(mix.o2, 15);
      expect(mix.he, 55);
    });

    test('40 m max depth → snaps to 21/35', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 40,
        isGueConfig: true,
      );
      expect(mix.o2, 21);
      expect(mix.he, 35);
    });
  });
}
```

- [ ] **Step 2: Implement `standard_mixes.dart`**

```dart
/// Standard mix tables for the bailout planner. Per Track D spec.
library;

import '../../data/models/dive.dart' show DiveGasMix;

const List<DiveGasMix> kNonGueBottomMixes = [
  DiveGasMix(o2: 21, he: 35, diluent: true),
  DiveGasMix(o2: 18, he: 45, diluent: true),
  DiveGasMix(o2: 15, he: 55, diluent: true),
  DiveGasMix(o2: 12, he: 65, diluent: true),
  DiveGasMix(o2: 10, he: 70, diluent: true),
];

const List<DiveGasMix> kGueBottomMixes = [
  DiveGasMix(o2: 21, he: 35, diluent: true),
  DiveGasMix(o2: 18, he: 45, diluent: true),
  DiveGasMix(o2: 15, he: 55, diluent: true),
];

const List<DiveGasMix> kDecoMixes = [
  DiveGasMix(o2: 32, he: 0, diluent: false),
  DiveGasMix(o2: 50, he: 0, diluent: false),
  DiveGasMix(o2: 100, he: 0, diluent: false),
];

const double kPpo2MaxNonGue = 1.6;
const double kPpo2MaxGue = 1.0;
const double kEndMaxMetres = 39.0;
```

- [ ] **Step 3: Implement `mix_resolver.dart`**

```dart
import '../../data/models/dive.dart' show DiveGasMix;
import 'standard_mixes.dart';

DiveGasMix resolveBottomMix({
  required DiveGasMix? recordedDiluent,
  required double maxDepthMeters,
  required bool isGueConfig,
}) {
  if (recordedDiluent != null) return recordedDiluent;

  // Compute the optimal mix for the config's PPO2 target.
  final ppo2Target = isGueConfig ? kPpo2MaxGue : kPpo2MaxNonGue;
  final ambientBar = (maxDepthMeters + 10.0) / 10.0;
  final optO2 = ppo2Target / ambientBar;
  // END constraint: (D+10)(1-He) ≤ 39 → He ≥ 1 - 49/(D+10)
  final optHe = (1.0 - 49.0 / (maxDepthMeters + 10.0)).clamp(0.0, 1.0);

  // Pick from the config-specific standard table — closest O2 to
  // optimal, both safety constraints honoured (PPO2 ≤ 1.6 absolute,
  // END ≤ 39 absolute).
  final candidates = isGueConfig ? kGueBottomMixes : kNonGueBottomMixes;
  DiveGasMix? best;
  double bestDelta = double.infinity;
  for (final mix in candidates) {
    final f02 = mix.o2 / 100.0;
    final fHe = mix.he / 100.0;
    final ppo2 = f02 * ambientBar;
    final end = (maxDepthMeters + 10.0) * (1.0 - fHe) - 10.0;
    if (ppo2 > 1.6 || end > kEndMaxMetres) continue;
    final delta = (f02 - optO2).abs();
    if (delta < bestDelta) {
      best = mix;
      bestDelta = delta;
    }
  }
  // Fallback to deepest mix if nothing satisfies (extreme depth)
  best ??= candidates.last;
  return best;
}
```

- [ ] **Step 4: Run tests + analyze + commit**

```bash
flutter test test/analysis/bailout/mix_resolver_test.dart  # 6/6 pass
flutter analyze  # clean
git add lib/analysis/bailout/standard_mixes.dart lib/analysis/bailout/mix_resolver.dart test/analysis/bailout/
git commit -m "$(cat <<'EOF'
feat(analysis): bailout standard mix tables + resolver

Tables per Track D spec: non-GUE {21/35, 18/45, 15/55, 12/65, 10/70},
GUE {21/35, 18/45, 15/55}, deco {EAN 32, EAN 50, O2 100}. resolveBottomMix
uses DC-recorded diluent verbatim when present; otherwise computes optimal
(O2, He) for the config's PPO2 target + END ≤ 39m and snaps to the
nearest standard mix that satisfies both constraints.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: SettingsNotifier extensions for bailout config

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Modify: `test/ui/notifiers/settings_notifier_test.dart`

- [ ] **Step 1: Write failing tests + implement**

Add five new fields with the same pattern used for `vpmbConservatism`:

| Field | Type | Default | Range/clamp | SharedPrefs key |
|---|---|---|---|---|
| `bailoutSacBottom` | int (L/min) | 30 | clamp(10, 60) | `bailout_sac_bottom` |
| `bailoutSacDeco` | int | 20 | clamp(10, 60) | `bailout_sac_deco` |
| `bailoutAscentRateFast` | int (m/min) | 18 | clamp(3, 30) | `bailout_ascent_fast` |
| `bailoutAscentRateSlow` | int | 9 | clamp(3, 30) | `bailout_ascent_slow` |
| `gueDiluentConfig` | bool | false | n/a | `gue_diluent_config` |
| `tank68L300Available` | bool | false | n/a | `tank_6_8l_300_available` |
| `tank12L300Available` | bool | false | n/a | `tank_12l_300_available` |

(AL40 and AL80 are always available — no Settings field.)

Add 7 round-trip tests covering default value + persistence + clamp where applicable.

- [ ] **Step 2: Run + commit**

```bash
flutter test test/ui/notifiers/settings_notifier_test.dart  # all pass
git add lib/ui/notifiers/settings_notifier.dart test/ui/notifiers/settings_notifier_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): bailout-config fields on SettingsNotifier

Five new persisted fields (two SAC rates, two ascent rates, GUE config
toggle) plus two tank-availability flags (6.8L/300, 12L/300). SAC + rate
fields clamp to sensible ranges. Defaults per Track D spec: SAC 30/20,
rates 18/9, GUE off, extra tanks off.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Settings UI for bailout config

**Files:**
- Modify: `lib/ui/screens/settings_screen.dart`

Add a new "Bailout planning" subsection with:
- 4 `ListTile` rows for the rates, each with a TextField for the value (or stepper)
- 1 `SwitchListTile` for GUE config (with subtitle describing the effect)
- 2 `SwitchListTile`s for the 6.8L/300 + 12L/300 tank availability

Each binds to its `SettingsNotifier` getter/setter via `ListenableBuilder`.

Commit:
```
feat(settings): Bailout planning subsection in Settings UI
```

---

## Task 4: Ascent simulator

**Files:**
- Create: `lib/analysis/bailout/ascent_simulator.dart`
- Create: `test/analysis/bailout/ascent_simulator_test.dart`

(Depends on Track C — `DecoReplayEngine.tissueStateAt()` API)

- [ ] **Step 1: Define data shapes**

```dart
class AscentStop {
  final double depthMeters;
  final Duration duration;
  final DiveGasMix gas;
  final double volumeLitres;
  const AscentStop({...});
}

class AscentPlan {
  final List<AscentStop> stops;
  final Duration totalTime;
  final Map<DiveGasMix, double> volumeByGas;
  const AscentPlan({...});
}
```

- [ ] **Step 2: Write failing tests** — fixture dives with known expected outputs (hand-computed).

- [ ] **Step 3: Implement ascent simulation**

Pseudocode:
```
function run(triggerDepth, tissueState, availableGases, settings) {
  // 1. Determine slowdown point: max(first gas switch depth, halfPressureDepth)
  //    halfPressureDepth = (triggerDepth - 10) / 2
  //    first gas switch depth = deepest stop where a non-bottom gas is MOD-appropriate
  // 2. Initial leg (trigger → slowdown point) at bailoutAscentRateFast on bottom mix
  //    Compute volume = SAC_bottom × (avg_depth_bar) × duration_min
  // 3. From slowdown point downward, query deco ceiling at each candidate stop
  //    (via Track C's tissueStateAt + an ascent extrapolation). Generate stops
  //    at 3m increments based on the deco schedule.
  // 4. Switch gas at deepest MOD-1m for each available deco gas.
  // 5. For each stop: duration = deco obligation at that depth; volume = SAC_deco × avg_depth_bar × duration_min
  // 6. Surface at bailoutAscentRateSlow from final stop or shallowest gas's bottom
}
```

(Detailed implementation is non-trivial — budget ~200 lines + careful testing. Use Track C's replay engine to advance the tissue state forward through the ascent.)

- [ ] **Step 4: Run tests + commit**

Commit:
```
feat(analysis): ascent simulator for bailout planning
```

---

## Task 5: Tank recommender

**Files:**
- Create: `lib/analysis/bailout/tank_recommender.dart`
- Create: `test/analysis/bailout/tank_recommender_test.dart`

```dart
class TankSpec {
  final String name;
  final double waterCapacityL;
  final int ratedPressureBar;
  const TankSpec({...});
}

const kAl40 = TankSpec(name: 'AL40', waterCapacityL: 5.7, ratedPressureBar: 207);
const kAl80 = TankSpec(name: 'AL80', waterCapacityL: 11.1, ratedPressureBar: 207);
const kTank68L300 = TankSpec(name: '6.8L/300', waterCapacityL: 6.8, ratedPressureBar: 300);
const kTank12L300 = TankSpec(name: '12L/300', waterCapacityL: 12.0, ratedPressureBar: 300);

class TankRecommendation {
  final TankSpec tank;
  final int minFillPressureBar;
}

TankRecommendation? recommend({
  required double volumeLitres,
  required List<TankSpec> availableTanks,
}) {
  // Walk smallest to largest. For each, min_fill = volume / waterCap.
  // If min_fill <= ratedPressure, pick this tank.
  // Return null if no tank fits.
}
```

Tests: 1465L → AL80 @ 132 bar; 500L → AL40 @ 88 bar; 4000L without 12L/300 in catalogue → null.

Commit:
```
feat(analysis): tank recommender (smallest viable + min fill pressure)
```

---

## Task 6: Bailout planner orchestrator + result type

**Files:**
- Create: `lib/analysis/bailout/bailout_result.dart`
- Create: `lib/analysis/bailout/bailout_planner.dart`
- Create: `test/analysis/bailout/bailout_planner_test.dart`

Compose the previous modules. The orchestrator's job:
1. Detect scenario (A if any tank classifies as bailout BO; B otherwise)
2. Resolve bottom mix via `mix_resolver`
3. Pull tissue state at end-of-bottom from `DecoReplayEngine`
4. Simulate ascent via `ascent_simulator`
5. For A: compute surplus/shortfall per gas
6. For B: call `tank_recommender` per gas to recommend tanks

Output type `BailoutResult` per the spec.

Commit:
```
feat(analysis): bailout planner orchestrator
```

---

## Task 7: BailoutSection widget

**Files:**
- Create: `lib/ui/widgets/bailout_section.dart`
- Create: `test/ui/widgets/bailout_section_test.dart`

Render the section per the brainstorm mockup:
- Scenario banner (blue for A, amber for B)
- 3-tile summary row (Total time / Required vol / Available-or-Stages)
- Per-stop table (depth, time, gas, runtime, vol)
- Verdict banner (green/orange/red)

Test with mock `BailoutResult` inputs covering all three verdict colours.

Commit:
```
feat(ui): BailoutSection widget renders scenario + table + verdict
```

---

## Task 8: Wire BailoutSection into dive detail screen

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart`

Add the section below the Notes section in `_buildDetailsTab`. Wrap in `ListenableBuilder(listenable: widget.settingsNotifier, ...)` (settings drive the SAC/ascent rates) AND `ListenableBuilder(listenable: _annotationsNotifier, ...)` (annotations drive the algorithm selection from Track C). Inside the builder, run the planner.

Manual smoke:
- Open a CCR trimix dive with BO tanks → Scenario A renders
- Open a similar dive without BO tanks → Scenario B renders with 3 recommended stages
- Toggle "GUE diluent config" in Settings → Scenario B drops to 2 stages
- Bump `bailoutSacBottom` from 30 to 40 → volumes recompute upward

Commit:
```
feat(ui): bailout section wired into dive detail below Notes
```

---

## Definition of done

After Task 8 commits:
1. `flutter analyze` reports zero issues
2. `flutter test` passes the full suite (target: existing + ~25 new tests)
3. Manual smoke against the user's own dives covers Scenarios A + B + all relevant Settings toggles
4. Eight commits land on `main`
5. Track C must have been merged BEFORE Task 4 onward — bailout planner directly imports from `lib/analysis/deco/`
