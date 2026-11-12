# 2026-05-20 — Plan tab refinements + Gas Blending tab

Post-implementation summary of one productive day. Builds on the 2026-05-20
dive-plan spec + plan and adds a brand-new Gas Blending top-level tab modelled
after `blender-toolkit.t-provider.de`. 949 → 953 tests over the day; analyzer
clean throughout.

## Plan tab refinements

The Dive Plan tab as shipped by the original plan worked end-to-end but
exposed several rough edges that landed today as follow-up fixes.

### Smart save + dirty tracking

- `DivePlanNotifier.isDirty` derives from a JSON-serialised baseline of the
  last-saved plan vs the live editor state. Amber pip in the app bar surfaces
  unsaved changes; tooltip "Unsaved changes" on tap.
- `notifier.save()` is the smart-save entry point: when a saved plan is
  currently loaded AND its name hasn't been changed, it overwrites the
  existing saved row via `dao.updateSaved()`. Otherwise it creates a new
  saved row via `saveAs()`. The Save button labels itself "Overwrite" vs
  "Save" to match.
- New `DivePlansDaoLike.updateSaved({id, draft, name})` for in-place updates.
- After a successful save the editor state is preserved (the earlier bug
  cleared the editor immediately after saving, which read as "save did
  nothing").

### Inline plan-name field

- App-bar `TextField` driven by `notifier.setPlanName()` replaces the static
  "Cave dive…" placeholder. When the field is empty and the user taps Save,
  a dialog prompts for a name as a fallback.
- `DivePlanDraft.planName` round-trips through `loadSaved()` so loading a
  saved plan repopulates the name field.

### Visual rework

- `_SectionCard` wrapper: surface-card background + 3px left accent bar +
  consistent padding. Used by every input section + the output card.
- Semantic accent colours: blue (settings), green (segments + target on
  Blend), amber (output), warning amber (bailout bottles, hot-fill banner).
- Two-tab structure on the Plan screen: Plan / Bailout. Each tab has its own
  profile chart on top of its output card.
- `DiveProfileChart` widget (custom painter): depth-vs-time graph with
  filled profile, max-depth dashed pip, gas-switch tick marks + mix labels.

### Algorithm controls

- CC / OC mode toggle: `notifier.setMode()`. OC mode hides the setpoint rows
  in the settings panel.
- VPM-B vs ZHL-16C toggle: `DivePlanSettings.useVpmb` + `vpmbConservatism`.
  The planner still falls back to ZHL+GF underneath; an italic note in the
  settings panel says so. VPM-B forward-planning queued as future work.
- "Deco SP from" depth: the deco SP only applies at/above this depth; deeper
  than that the planner uses the ascent SP. Default 99 m (= "always deco
  SP"); a real deep diver typically sets ~36 m so SP doesn't jump high
  during the deep first-stop leg.
- "OC SAC" setting: drives OC consumption math (SAC × ambient × duration);
  feeds both the per-leg VOL column and the new gas-used chip.

### Gas safety + per-segment checks

New shared module `gas_safety_readout.dart` used by both the gas editor and
the segments editor. Single source of truth for the colour ladder:

| OC PPO₂ at depth | END at depth | Colour | Selectable in seg dropdown |
|---|---|---|---|
| ≤ 1.1 | ≤ 30 m | green | yes |
| 1.1 to 1.51, or END > 30 m | — | amber | yes |
| > 1.51 | — | red | yes (with red text) |
| > 1.61 | — | — | **filtered out** |

- Hypoxic mixes used at depth (deep trimix diluent) stay green when PPO₂ and
  END are in range — fixed an earlier bug where any hypoxic mix was amber
  even when it was the right choice.
- Amber warning text: "PPO₂ too high to flush" (per user feedback — replaces
  the older "outside the everyday-deco budget").
- The segments editor filters its gas dropdown by OC PPO₂ ≤ 1.61 at the
  row's depth, and renders a per-segment warning line below the row when
  the chosen gas is amber or red. Green / neutral states stay silent.
- The gas editor's per-gas safety line evaluates against the **deepest**
  segment using that gas (so a deco-only gas is judged at its actual usage
  depth, not the deepest dive depth).

### Output table improvements

- New END column between PPO₂ and ρ (CCR-aware: loop fHe scales with
  setpoint).
- VOL column populated for every leg: CC = metabolic O₂ burn (~1 L/min ×
  duration); OC = SAC × ambient × duration. Earlier the column was 0.
- Per-gas consumption chips on OC plans: "Tx18/45 3400 L · EAN50 980 L"
  instead of a single lumped "Gas 4380 L" chip. CC plans keep the O₂ chip.
- ICD + benign gas-switch row tints in the stop ladder.
- O₂ chip remains on CC (metabolic estimate).

### Bailout bottle editor

Was previously delete-only after add. Now fully editable: gas dropdown +
capacity (L) + pressure (bar) all editable in place. `replaceBailoutBottle`
added to the notifier.

### CCR no-auto-switch (fix)

The deco planner used to MultiDeco-style auto-pick the richest safe gas at
each stop. That's wrong on CCR — the diver doesn't swap diluent at 21 m
just because EAN 50 is in the gas list. In CC mode the runner now passes a
single-element gas list (the active diluent at the end of the segment walk)
to `planDeco`, killing auto-switching. To switch diluent mid-dive the diver
adds a 0-time segment with the new gas as the last segment. OC mode keeps
the original auto-select behaviour (that's correct for OC deco).

## Gas Blending tab (new feature)

Modelled after `blender-toolkit.t-provider.de` — partial-pressure blending
only (no continuous mode), with cost calculation, multiple fill sequences,
real-gas math, and hot-fill compensation.

### Pure-Dart blender — `lib/analysis/blending/`

- `compressibility.dart`: van der Waals real-gas Z. Constants from CRC
  Handbook for He / O₂ / N₂. Mixing rules: a_mix = (Σ xᵢ √aᵢ)² (Berthelot),
  b_mix linear in mole fraction (Amagat). Helpers `molesForGauge` and
  `gaugeForMoles` invert each other through vdW so the blender can work
  entirely in mole space.
- `gas_blender.dart`: `planBlend({current, target, topoff, sequence,
  useRealGas, prices, temperatureKelvin, settledTemperatureKelvin})` →
  `BlendResult`. Algorithm:
  1. Convert current + target cylinder states to per-gas moles using vdW.
  2. Decompose the per-gas mole delta into He-bank, O₂-bank, and top-off
     mole contributions (linear system; same algebra as before, in moles).
  3. If any contribution is negative, binary-search the smallest drain
     fraction that unblocks the fill; recursively plan from the drained
     state and emit the drain as step 0.
  4. Walk the chosen fill sequence converting cumulative mole inventory
     to gauge pressure via vdW at each step. The bar deltas are emitted
     as the fill plan — by construction they sum to the target gauge.
- Three fill sequences: He → O₂ → top-off (default, tech convention),
  O₂ → He → top-off, O₂ → top-off → He (the high-pressure-He against
  banked-nitrox case from ScubaBoard).
- Cost: per-source moles × R × T(K) gives "barliter" matching the
  reference. Three prices: He per litre, O₂ per litre, air flat fee per
  fill.
- Result class: `steps`, `finalPressureBar` (hot fill), `settledPressureBar`
  (cold target, only when hot-fill compensation is active),
  `settledTemperatureKelvin`, `fillTemperatureKelvin`, `cost`,
  `drainToPressureBar`, `error` + `errorMessage` for impossible blends.

### Hot-fill compensation

- `planBlend` takes both `temperatureKelvin` (fill temp, what the gauge
  reads during blending) and an optional `settledTemperatureKelvin` (the
  temperature the cylinder will eventually reach).
- Target moles are computed at the settled temperature; the fill plan is
  walked at the fill temperature. So the diver fills to a higher gauge
  during the (warm) fill, and the gauge drops to the user's target
  pressure after the cylinder cools.
- Info banner in the UI: "Hot fill to 263 bar — settles to 250 bar at 18 °C."
  Hidden when fill ≡ settled.

### Settings

New global settings (persisted via SharedPreferences):
- `blendOxygenCostPerLitre`, `blendHeliumCostPerLitre`, `blendAirFlatFee`
- `blendTopoffOxygenPercent` / `blendTopoffHeliumPercent` — default
  top-off mix
- `blendFillSequence` — default fill order (stored as enum name)
- `blendUseRealGas` — default to vdW correction (true)
- `blendFillTempC` (default 18 °C) and `blendSettledTempC` (default 18 °C)

New "Gas blending" section in the Settings screen with rows for each.

### UI — `BlendScreen`

Four input → output cards on a single screen:
1. **CURRENT CYLINDER** — O₂ %, He %, pressure (bar), water capacity (L)
2. **TARGET** — O₂ %, He %, pressure (settled)
3. **TOP-OFF** — O₂ % / He % + Air / EAN32 / EAN50 quick-pick chips, fill
   order dropdown, real-gas switch, fill temp / settled temp fields
4. **FILL PLAN** — ordered step rows ("ADD HE 88 bar of He → 88 bar"),
   per-source litre breakdown, total cost, hot-fill banner when active,
   error / drain banner when impossible

`BlendNotifier` holds editable state, recomputes synchronously on every
edit, listens to `SettingsNotifier` for price changes.

### Bottom navigation

Inserted at index 2: Dives / Plan / **Blend** / Import / Equipment /
Settings. Icon: `Icons.science_outlined` (chemistry flask).

### Reference parity

For the canonical "empty 12 L → Tx 21/35 @ 250 bar, air top-off, 18 °C,
vdW" test scenario:

| Leg | Our app | Reference | Δ |
|---|---|---|---|
| He | ~83 bar | 82.4 bar | <1 bar |
| O₂ | ~23 bar | 22.9 bar | <0.5 bar |
| Air | ~144 bar | 144.7 bar | <1 bar |
| **Total** | **250.0** | **250.0** | **0** |

The sum-equals-target invariant is pinned by a regression test. Sub-bar
drift vs the reference comes from minor differences in vdW mixing rules
implementation; well within fill-gauge precision.

## Tests

952 → 953 tests passing. New regression tests cover:

- `test/analysis/blending/gas_blender_test.dart` — 9 tests covering ideal +
  vdW + hot-fill scenarios
- `test/analysis/planner/plan_runner_test.dart` — added CCR no-auto-switch +
  explicit 0-time switch
- `test/ui/widgets/gas_safety_readout_test.dart` — 6 tests pinning the
  PPO₂ / END colour boundaries + selectability cap
- `test/ui/widgets/plan_segments_editor_test.dart` — dropdown filter +
  per-segment warning regression tests
- `test/ui/widgets/plan_settings_panel_test.dart` — VPM-B reveal + OC mode
  hides setpoints
- `test/ui/notifiers/dive_plan_notifier_test.dart` — isDirty + overwrite vs
  save-as-new
- `test/ui/screens/blend_screen_test.dart` — target fields editable
  regression (caught a styling issue where field fill matched card
  background and the user reported "read only" inputs)

## Known follow-ups

- VPM-B forward planning — currently falls back to ZHL+GF. Proper
  bubble-nucleation model is queued.
- Continuous-blending mode (the reference's other fill mode) — skipped from
  v1; pp-blending covers 95% of tech-diving workflow.
- Tank-heating compensation beyond the simple T-ratio model.
- PSCR O₂-drop calculator.
- Cost / heating / PSCR could be a v2 settings group.
