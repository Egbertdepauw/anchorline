# Selectable Themes — Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove every loose colour from UI code so the whole app follows the selected theme, add a guard that keeps it that way, and switch theming on for release builds.

**Architecture:** Every colour in `lib/` outside `lib/ui/theme/` becomes one of four things: a `ThemePalette` token read through `context.palette` (chrome), a `SafetyColors` constant (meaning: fixed in every theme), a `DataColors` constant (data encoding: fixed in every theme), or a `MediaColors` constant (neutral surfaces around photos and documents). A guard test then forbids colour literals and named Material colours outside the theme folder.

**Tech Stack:** Flutter 3.44 / Dart ^3.11.5, `flutter_test`. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-06-theming-design.md` (section "Stage 2"), plus the carry-over list in GitHub issue #96.

## Global Constraints

- Four kinds, and only four: **chrome** → `context.palette.<token>`; **safety** → `SafetyColors`; **data encoding** → `DataColors`; **neutral media surfaces** → `MediaColors`. `Colors.transparent` is the one named colour allowed outside `lib/ui/theme/`.
- Safety colours keep their exact values: success `#4ADE80`, warning `#F39C12`, danger `#E74C3C`, info `#60A5FA`, GF bands `#4ADE80` / `#F59E0B` / `#DC2626`.
- Data-encoding colours keep their exact current values. Moving one into `DataColors` must not change it.
- Never a global or static "current palette". Widgets use `context.palette`; painters and helpers without a `BuildContext` receive the palette (or the specific colours) from their caller, and a painter repaints when they change.
- No file under `lib/` outside `lib/ui/theme/` may name `AppColors.wreck` (existing guard test).
- Wreck may shift only where this plan's "Accepted changes to Wreck" list says so. Anything else that changes how Wreck looks is a defect.
- A theme changes colours only. Do not touch typography, spacing, radii or motion.
- No new dependencies.
- Do not run `dart format` on existing files: `main` is not format-clean. Match the surrounding style by hand. New files may be formatted.
- Edit by hand, file by file. No `sed` or scripted replacement across files: the same literal means different things in different places.
- Every task ends with `flutter analyze` clean and the full `flutter test` suite passing.
- Commit messages end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Accepted changes to Wreck

Stage 2 unifies stray literals with the colour they were meant to be. These small shifts in the default theme are intended:

| Where | Before | After |
|---|---|---|
| Cell health strip status colours | Material green / amber / red-accent / grey | `SafetyColors.success` / `warning` / `danger`, `palette.textMuted` |
| Swipe-to-delete backgrounds (dive list, saved plans) | Material red 700, Material red | `SafetyColors.danger` |
| Subsurface sync section warning and error text | `#E65100`, `#E53935` | `SafetyColors.warning`, `SafetyColors.danger` |
| Subsurface sync section secondary text, dive information captions | `#B0BEC5`, `#78909C` | `palette.textSecondary`, `palette.textMuted` |
| Profile chart axis labels | `#90A4AE` | `palette.textSecondary` |
| Chart legend and crosshair tooltip boxes | `#152238` at 75% / 88% | `palette.surfaceCard` at the same opacity |
| Crosshair tooltip label and sub-label text | `#778899`, `#9FB0C0` | `palette.textMuted`, `palette.textSecondary` |
| White text in chart legends and tooltips | `Colors.white` | `palette.textPrimary` |
| Density and END legend swatches | `#E3E6EB` | `palette.textPrimary` |
| Map pins in the map picker and the site mini map | Material red, Material red-accent | one `DataColors.mapPin` |

## Review Focus

1. **A legend that disagrees with its chart.** In every theme, each trace toggle's swatch is the colour the chart draws that trace in. → Task 2.
2. **A warning that stops looking like a warning.** After the sweep, every status, band and alert colour is identical in all six themes. → Task 1 (values), Task 5 (cross-theme test).
3. **A fixed colour that disappears on some theme.** Data-encoding colours are fixed, so each must stay readable on every theme's card. → Task 1.
4. **Speed-coloured depth trace on cream themes.** The calm-segment colour must not drift toward the gradient's amber and orange. → Task 2.
5. **A colour captured once.** A legend map or top-level constant built from a colour at load time does not follow a theme switch. → Tasks 2 and 3.

## File Structure

| File | Responsibility |
|---|---|
| `lib/ui/theme/data_colors.dart` (new) | Fixed data-encoding colours: dive modes, tissue ramp, speed gradient, tanks, water temperature, GF99, ceiling, map pins |
| `lib/ui/theme/media_colors.dart` (new) | Neutral surfaces around media: viewer background and foreground, scrims over photos |
| `lib/ui/theme/safety_colors.dart` (modify) | Adds limit bands, alert surfaces and the on-alert colour |
| `lib/ui/theme/tokens.dart`, `omarchy/omarchy_mapping.dart` (modify) | Drop the unused `chartTraceGf99` token |
| `lib/ui/theme/app_themes.dart` (modify) | `kThemingEnabled` becomes `true` (Task 5) |
| `test/ui/theme/no_loose_colors_test.dart` (new) | The guard |
| Group A, B, C files | Listed in Tasks 2, 3 and 4 |

## Execution order

Task 1 first. Tasks 2, 3 and 4 touch disjoint files and can run in parallel, each in its own worktree branched from Task 1's commit, then merged. Task 5 last.

## Before Task 1

- [ ] `git switch main && git pull --ff-only && git switch -c feat/96-theming-stage-2`
- [ ] Commit this plan:

```bash
git add docs/superpowers/plans/2026-10-08-theming-stage-2.md
git commit -m "docs(theme): stage 2 plan — sweep loose colours (#96)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: Fixed colour classes and the unused token

**Files:**
- Create: `lib/ui/theme/data_colors.dart`, `lib/ui/theme/media_colors.dart`
- Modify: `lib/ui/theme/safety_colors.dart`, `lib/ui/theme/tokens.dart`, `lib/ui/theme/omarchy/omarchy_mapping.dart`
- Test: create `test/ui/theme/fixed_colors_test.dart`; modify `test/ui/theme/safety_colors_test.dart`, `test/ui/theme/theme_palette_test.dart`, `test/ui/theme/omarchy_mapping_test.dart`, `test/ui/theme/app_themes_test.dart`

**Interfaces:**
- Consumes: `contrastRatio` (`color_math.dart`), `AppThemes.all`, `ThemePalette`.
- Produces: `DataColors`, `MediaColors`, and the `SafetyColors` additions below. `ThemePalette` loses `chartTraceGf99` (17 fields remain).

- [ ] **Step 1: Write the failing tests**

`test/ui/theme/fixed_colors_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:ccrlogger/ui/theme/data_colors.dart';
import 'package:ccrlogger/ui/theme/media_colors.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Data colours known to fall short of 3:1 on a theme's card.
/// Keys are '<themeId>/<name>'. Each is an existing colour whose value
/// stage 2 must not change; the entry records the shortfall so no new
/// one can slip in. Filled in from the first run of this test (Step 4).
const _knownCardShortfalls = <String>{};

void main() {
  test('data colours keep their established values', () {
    expect(DataColors.modeClosedCircuit, const Color(0xFF4FC3F7));
    expect(DataColors.modeOpenCircuit, const Color(0xFFFF9800));
    expect(DataColors.modeSemiClosed, const Color(0xFFAB47BC));
    expect(DataColors.modeGauge, const Color(0xFF78909C));
    expect(DataColors.modeFreedive, const Color(0xFF26A69A));
    expect(DataColors.waterTemp, const Color(0xFF4DD0E1));
    expect(DataColors.gf99, const Color(0xFF9333EA));
    expect(DataColors.ceiling, const Color(0xFFEAB308));
    expect(DataColors.speedCalm, const Color(0xFFE0E8EC));
    expect(DataColors.speedSlow, const Color(0xFFA8D957));
    expect(DataColors.speedModerate, const Color(0xFFE5C73F));
    expect(DataColors.speedFast, const Color(0xFFEC8A3D));
    expect(DataColors.speedExtreme, const Color(0xFFE65656));
    expect(DataColors.tanks, const [
      Color(0xFF80DEEA),
      Color(0xFFFFAB91),
      Color(0xFFCE93D8),
      Color(0xFFB0BEC5),
      Color(0xFFA5D6A7),
      Color(0xFFFFE082),
    ]);
    expect(DataColors.tissueRamp, const [
      (0.0, Color(0xFF1E3A8A)),
      (40.0, Color(0xFF3B82F6)),
      (70.0, Color(0xFF06B6D4)),
      (85.0, Color(0xFF22C55E)),
      (95.0, Color(0xFFFACC15)),
      (100.0, Color(0xFFF97316)),
      (115.0, Color(0xFFDC2626)),
    ]);
    expect(DataColors.mapPin, const Color(0xFFF44336));
    expect(DataColors.mapPinMuted, const Color(0xFF8B3A3A));
  });

  test('safety additions', () {
    expect(SafetyColors.bandSafe, SafetyColors.gfWithinLimits);
    expect(SafetyColors.bandCaution, SafetyColors.gfOverHigh);
    expect(SafetyColors.bandOver, SafetyColors.gfOverLimit);
    expect(SafetyColors.alertCriticalSurface, const Color(0xFFB71C1C));
    expect(SafetyColors.alertWarningSurface, const Color(0xFFE65100));
    expect(SafetyColors.onAlert, const Color(0xFFFFFFFF));
  });

  test('on-alert text is readable on every alert surface', () {
    for (final surface in [
      SafetyColors.alertCriticalSurface,
      SafetyColors.alertWarningSurface,
      SafetyColors.danger,
    ]) {
      expect(contrastRatio(SafetyColors.onAlert, surface),
          greaterThanOrEqualTo(3.0),
          reason: '$surface');
    }
  });

  test('media colours', () {
    expect(MediaColors.viewerBackground, const Color(0xFF000000));
    expect(MediaColors.viewerForeground, const Color(0xFFFFFFFF));
    expect(MediaColors.onScrim, const Color(0xFFFFFFFF));
    expect(MediaColors.scrim(0.35), const Color(0xFF000000).withValues(alpha: 0.35));
  });

  test('line-drawing data colours are readable on every theme card', () {
    final offenders = <String>[];
    for (final t in AppThemes.all) {
      DataColors.lineColors.forEach((name, color) {
        final ratio = contrastRatio(color, t.palette.surfaceCard);
        final key = '${t.id}/$name';
        if (_knownCardShortfalls.contains(key)) {
          expect(ratio, lessThan(3.0),
              reason: '$key no longer falls short: remove it from '
                  '_knownCardShortfalls');
        } else if (ratio < 3.0) {
          offenders.add('$key ${ratio.toStringAsFixed(2)}');
        }
      });
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('accent is readable as a label in every theme', () {
    for (final t in AppThemes.all) {
      for (final bg in [t.palette.surfaceBg, t.palette.surfaceCard]) {
        expect(contrastRatio(t.palette.accentPrimary, bg),
            greaterThanOrEqualTo(3.0),
            reason: '${t.id} accent');
      }
    }
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/theme/fixed_colors_test.dart`
Expected: FAIL to compile — `data_colors.dart` and `media_colors.dart` do not exist.

- [ ] **Step 3: Implement**

`lib/ui/theme/data_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Colours that encode data. They are identical in every theme: a
/// closed-circuit dive, a fast ascent or a saturated tissue must look
/// the same whatever palette the diver picked. Never derive these from
/// the active theme.
class DataColors {
  DataColors._();

  // Dive modes (dive list, dive detail, statistics).
  static const Color modeClosedCircuit = Color(0xFF4FC3F7);
  static const Color modeOpenCircuit = Color(0xFFFF9800);
  static const Color modeSemiClosed = Color(0xFFAB47BC);
  static const Color modeGauge = Color(0xFF78909C);
  static const Color modeFreedive = Color(0xFF26A69A);

  // Profile chart traces that are not theme tokens.
  static const Color waterTemp = Color(0xFF4DD0E1);
  static const Color gf99 = Color(0xFF9333EA);
  static const Color ceiling = Color(0xFFEAB308);

  /// Tank pressure traces, by tank index (wraps).
  static const List<Color> tanks = [
    Color(0xFF80DEEA), // cyan-ish
    Color(0xFFFFAB91), // peach
    Color(0xFFCE93D8), // lilac
    Color(0xFFB0BEC5), // blue grey
    Color(0xFFA5D6A7), // pale green
    Color(0xFFFFE082), // pale amber
  ];

  // Vertical-speed gradient for the speed-coloured depth trace. The calm
  // colour is fixed too, so the gradient reads the same on every theme.
  static const Color speedCalm = Color(0xFFE0E8EC);
  static const Color speedSlow = Color(0xFFA8D957);
  static const Color speedModerate = Color(0xFFE5C73F);
  static const Color speedFast = Color(0xFFEC8A3D);
  static const Color speedExtreme = Color(0xFFE65656);

  /// Tissue saturation ramp: (percent of M-value, colour), ascending.
  static const List<(double, Color)> tissueRamp = [
    (0.0, Color(0xFF1E3A8A)), // deep blue
    (40.0, Color(0xFF3B82F6)), // blue
    (70.0, Color(0xFF06B6D4)), // cyan
    (85.0, Color(0xFF22C55E)), // green
    (95.0, Color(0xFFFACC15)), // yellow
    (100.0, Color(0xFFF97316)), // orange
    (115.0, Color(0xFFDC2626)), // red
  ];

  // Pins drawn on map tiles, which do not follow the theme.
  static const Color mapPin = Color(0xFFF44336);
  static const Color mapPinMuted = Color(0xFF8B3A3A);

  /// The data colours drawn as thin lines on a chart card, by name. Used
  /// by tests to check each stays readable on every theme's card.
  static const Map<String, Color> lineColors = {
    'waterTemp': waterTemp,
    'gf99': gf99,
    'ceiling': ceiling,
    'speedCalm': speedCalm,
    'speedSlow': speedSlow,
    'speedModerate': speedModerate,
    'speedFast': speedFast,
    'speedExtreme': speedExtreme,
    'tank0': Color(0xFF80DEEA),
    'tank1': Color(0xFFFFAB91),
    'tank2': Color(0xFFCE93D8),
    'tank3': Color(0xFFB0BEC5),
    'tank4': Color(0xFFA5D6A7),
    'tank5': Color(0xFFFFE082),
  };
}
```

`lib/ui/theme/media_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Neutral colours around photos and documents. A photo or PDF viewer is
/// black whatever the theme, and controls drawn over a photo sit on a
/// dark scrim. These do not follow the theme.
class MediaColors {
  MediaColors._();

  static const Color viewerBackground = Color(0xFF000000);
  static const Color viewerForeground = Color(0xFFFFFFFF);

  /// Icons and text drawn on a [scrim].
  static const Color onScrim = Color(0xFFFFFFFF);

  /// A black scrim over media at [opacity] (0 to 1).
  static Color scrim(double opacity) =>
      const Color(0xFF000000).withValues(alpha: opacity);
}
```

In `lib/ui/theme/safety_colors.dart`, add inside the class, before `all`:

```dart
  /// Limit bands for gas density and END readouts. Same colours as the
  /// GF bands: within limits, approaching, over.
  static const Color bandSafe = gfWithinLimits;
  static const Color bandCaution = gfOverHigh;
  static const Color bandOver = gfOverLimit;

  /// Background of a full-width alert banner, and of a destructive
  /// swipe action when drawn with [danger].
  static const Color alertCriticalSurface = Color(0xFFB71C1C);
  static const Color alertWarningSurface = Color(0xFFE65100);

  /// Text and icons on an alert surface or on [danger].
  static const Color onAlert = Color(0xFFFFFFFF);
```

Leave `SafetyColors.all` as it is (the seven named colours used as text and readouts).

Remove the unused `chartTraceGf99` token: in `lib/ui/theme/tokens.dart` delete it from the `ThemePalette` constructor, the field list, `copyWith`, `lerp` and `AppColors.wreck`; in `lib/ui/theme/omarchy/omarchy_mapping.dart` delete the `chartTraceGf99: cell3,` line and update the doc comment that mentions GF99 if any. The profile chart never read this token: it draws GF99 in the purple that is now `DataColors.gf99`.

- [ ] **Step 4: Update the affected tests and settle the shortfall list**

- `test/ui/theme/theme_palette_test.dart`: remove the `chartTraceGf99` line from the 18-colour palette and its `expect`.
- `test/ui/theme/omarchy_mapping_test.dart`: remove the two `chartTraceGf99` expectations.
- `test/ui/theme/app_themes_test.dart`: remove the `chartTraceGf99` expectation in "Wreck is unchanged".
- Run `flutter test test/ui/theme/fixed_colors_test.dart`. If "line-drawing data colours are readable on every theme card" lists offenders, each is an existing colour whose value this stage must not change: add each listed key to `_knownCardShortfalls`, run again, and record the full list with its ratios in your report. Do not change any colour value or the 3.0 threshold.
- If "accent is readable as a label" fails, stop and report: that needs a decision.

- [ ] **Step 5: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui/theme test/ui/theme
git commit -m "feat(theme): fixed data, media and alert colours; drop the unused GF99 token (#96)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Group A — charts

**Files:**
- Modify: `lib/ui/widgets/profile_chart.dart`, `lib/ui/widgets/crosshair_tooltip.dart`, `lib/ui/widgets/trace_segmented_bar.dart`, `lib/ui/widgets/dive_profile_chart.dart`, `lib/ui/widgets/tissue_saturation_heatmap.dart`, `lib/ui/widgets/cell_health_strip.dart`
- Test: modify `test/ui/widgets/profile_chart_test.dart`, `test/ui/widgets/trace_segmented_bar_test.dart` (create if absent), `test/ui/widgets/cell_health_strip_test.dart` (create if absent)

**Interfaces:**
- Consumes: `DataColors`, `SafetyColors` additions (Task 1); `context.palette`; `ProfileChartPainter.palette`.
- Produces: `Color traceLegendColor(TraceType type, ThemePalette palette)` in `trace_segmented_bar.dart`, replacing the colours in the constant legend map.

- [ ] **Step 1: Write the failing tests**

Add to the trace bar's test file:

```dart
  test('each legend swatch is the colour the chart draws that trace in', () {
    for (final t in AppThemes.all) {
      final p = t.palette;
      expect(traceLegendColor(TraceType.ppo2, p), p.chartTracePpo2,
          reason: t.id);
      expect(traceLegendColor(TraceType.setpoint, p), p.chartTraceSetpoint,
          reason: t.id);
      expect(traceLegendColor(TraceType.cells, p), p.cell1, reason: t.id);
      expect(traceLegendColor(TraceType.deco, p), SafetyColors.warning);
      expect(traceLegendColor(TraceType.gasChanges, p), SafetyColors.info);
      expect(traceLegendColor(TraceType.tanks, p), DataColors.tanks.first);
      expect(traceLegendColor(TraceType.gf99, p), DataColors.gf99);
      expect(traceLegendColor(TraceType.ceiling, p), DataColors.ceiling);
      expect(traceLegendColor(TraceType.waterTemp, p), DataColors.waterTemp);
      expect(traceLegendColor(TraceType.density, p), p.textPrimary,
          reason: t.id);
      expect(traceLegendColor(TraceType.end, p), p.textPrimary, reason: t.id);
    }
  });

  test('every trace type has a legend colour', () {
    for (final type in TraceType.values) {
      expect(() => traceLegendColor(type, AppColors.wreck), returnsNormally);
    }
  });
```

Add to the cell health strip's test file a test that pumps the strip (reuse the construction from the existing tests in `test/ui/widgets/`, or from the widget's call site in `lib/`) with one healthy, one watch and one replace cell under `AppThemes.byId('catppuccin').themeData`, and asserts the three status colours it renders are `SafetyColors.success`, `SafetyColors.warning` and `SafetyColors.danger`.

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/widgets/trace_segmented_bar_test.dart`
Expected: FAIL to compile — `traceLegendColor` is undefined.

- [ ] **Step 3: Migrate, file by file**

`trace_segmented_bar.dart`

| Line (content) | Becomes |
|---|---|
| The constant legend map with `(label:, color:)` records | Keep the labels in the constant map; move colour to a new top-level `Color traceLegendColor(TraceType type, ThemePalette palette)` implemented as an exhaustive `switch`, with the values from the test above. Tanks: `DataColors.tanks.first`. |
| Every read of `.color` from the map | `traceLegendColor(type, context.palette)` |
| `Colors.transparent` | stays |

`profile_chart.dart`

| Line (content) | Becomes |
|---|---|
| `_crosshairColor = Color(0x80FFFFFF)` | delete; use `palette.textPrimary.withValues(alpha: 0.5)` at its use in the painter |
| `_waterTempColor` | delete; `DataColors.waterTemp` |
| `_tankColors` list | delete; `DataColors.tanks` |
| `_vSpeedSlowColor` … `_vSpeedCrazyColor` | delete; `DataColors.speedSlow` / `speedModerate` / `speedFast` / `speedExtreme` |
| `_vSpeedAnchorsFor(Color stable)` and its one call | drop the parameter: the 0 m/min anchor is `DataColors.speedCalm`. The list becomes a top-level `const`/`final` again and `_colorForRate` reads it directly; its fallback `return` is `DataColors.speedCalm` |
| `_bandGreen` / `_bandOrange` / `_bandRed` | delete; `SafetyColors.bandSafe` / `bandCaution` / `bandOver` |
| `Color(0xC0152238)` (two legend boxes) | `context.palette.surfaceCard.withValues(alpha: 0.75)` |
| `Colors.white` in the two legends | `context.palette.textPrimary` |
| `Color(0xFF9333EA)` | `DataColors.gf99` |
| `Color(0xFFEAB308)` | `DataColors.ceiling` |
| `Colors.white` in the painter (two text styles near the gas-change / marker labels) | `palette.textPrimary` |
| `Color(0xFF90A4AE)` (three axis-label styles) | `palette.textSecondary`; the enclosing `const TextStyle` loses `const` |

The speed-off depth trace keeps using `palette.chartTraceDepth`. Only the speed-coloured mode's calm colour becomes fixed.

`crosshair_tooltip.dart`

| Line (content) | Becomes |
|---|---|
| `_labelColor = Color(0xFF778899)` | `context.palette.textMuted` |
| `_subColor = Color(0xFF9FB0C0)` | `context.palette.textSecondary` |
| `_boxColor = Color(0xE0152238)` | `context.palette.surfaceCard.withValues(alpha: 0.88)` |
| `row.valueColor ?? Colors.white`, `valueColor ?? Colors.white`, other `Colors.white` | `… ?? context.palette.textPrimary`, `context.palette.textPrimary` |

The three `static const` colours cannot stay static. Read the palette once at the top of `build` and pass it to the private helpers that need it.

`dive_profile_chart.dart` (the small chart; its painter has five static colours)

| Static colour | Becomes |
|---|---|
| `_gridColor` `#1A2832` | `palette.chartGrid` |
| `_axisLabel` `#A0AEB6` | `palette.textSecondary` |
| `_profileLine` `#E0E8EC` | `palette.chartTraceDepth` |
| `_profileFill` `#1F2E38` at 20% | `palette.surfaceRaised.withValues(alpha: 0.2)` |
| `_switchMarker` `#60A5FA` | `SafetyColors.info` |

Give the painter a required `ThemePalette palette` field, passed `context.palette` by the widget that builds it, and add `!identical(old.palette, palette)` to its `shouldRepaint`.

`tissue_saturation_heatmap.dart`: replace the seven-entry ramp literal with `DataColors.tissueRamp`. If the local list has a different record shape than `(double, Color)`, adapt the reader, not `DataColors`.

`cell_health_strip.dart`

| Before | After |
|---|---|
| `Colors.green` | `SafetyColors.success` |
| `Colors.amber` | `SafetyColors.warning` |
| `Colors.redAccent` | `SafetyColors.danger` |
| `Colors.grey` | `context.palette.textMuted` (pass the palette in if the place has no `BuildContext`) |

- [ ] **Step 4: Update the existing speed-anchor expectations**

`test/ui/widgets/profile_chart_test.dart` has a test "an open ProfileChart repaints in the new palette on a theme switch" and others that construct `ProfileChartPainter`. They keep passing unchanged. If any test referred to `_vSpeedAnchorsFor`, there is none to update: it is private.

- [ ] **Step 5: Verify this group is clean**

Run:
```bash
grep -nE 'Color\(0x|\bColors\.[a-zA-Z]' lib/ui/widgets/profile_chart.dart lib/ui/widgets/crosshair_tooltip.dart lib/ui/widgets/trace_segmented_bar.dart lib/ui/widgets/dive_profile_chart.dart lib/ui/widgets/tissue_saturation_heatmap.dart lib/ui/widgets/cell_health_strip.dart | grep -v 'Colors.transparent'
```
Expected: no output.

- [ ] **Step 6: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui/widgets test/ui/widgets
git commit -m "feat(theme): charts, legends and tooltips follow the theme (#96)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Group B — dive detail and planner

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart`, `lib/ui/screens/dive_plan_screen.dart`, `lib/ui/widgets/dive_information_section.dart`, `lib/ui/widgets/bailout_section.dart`, `lib/ui/widgets/gas_safety_readout.dart`, `lib/ui/widgets/stop_ladder_table.dart`, `lib/ui/widgets/plan_settings_panel.dart`, `lib/ui/widgets/plan_segments_editor.dart`, `lib/ui/widgets/saved_plans_sheet.dart`
- Test: modify `test/ui/widgets/gas_safety_readout_test.dart` (create if absent)

**Interfaces:**
- Consumes: `SafetyColors` (including Task 1's bands and `onAlert`), `context.palette`.
- Produces: nothing other tasks consume.

- [ ] **Step 1: Write the failing test**

In the gas safety readout's test file, add a test that pumps the readout (reuse the construction from its existing tests or its call site) under `AppThemes.byId('miasma').themeData` in a state that shows secondary text, and asserts that text's colour is `AppThemes.byId('miasma').palette.textSecondary`. Today it is the literal `#A0AEB6`, so the test fails.

- [ ] **Step 2: Run and confirm failure**

Run the new test. Expected: FAIL, colour is `Color(0xFFA0AEB6)`.

- [ ] **Step 3: Migrate, file by file**

| File | Line (content) | Becomes |
|---|---|---|
| `dive_detail_screen.dart` | `DensityBand.green/orange/red => const Color(…)` | `SafetyColors.bandSafe` / `bandCaution` / `bandOver` |
| | `EndBand.green/orange/red => const Color(…)` | the same three |
| | `Colors.transparent` | stays |
| | `Icon(Icons.fullscreen, color: Colors.white70)` (button over the chart) | `context.palette.textSecondary`; the `const` on the `Icon` is removed |
| `dive_plan_screen.dart` | `Color(0xFF2A3A45)` (two) | `context.palette.surfaceBezel`; an enclosing `const Divider` loses `const` |
| `dive_information_section.dart` | `Color(0xFF78909C)` caption style | `context.palette.textMuted`; `const captionStyle` becomes `final` |
| | `Color(0xFFB0BEC5)` | `context.palette.textSecondary` |
| `bailout_section.dart` | `_blue` / `_amber` / `_green` / `_red` static constants | delete; `SafetyColors.info` / `warning` / `success` / `danger` at each use |
| `gas_safety_readout.dart` | `_statusSuccess` / `_statusWarning` / `_statusDanger` | delete; `SafetyColors.success` / `warning` / `danger` |
| | `_textSecondary` | delete; `context.palette.textSecondary`, passed into any helper that has no `BuildContext` |
| `stop_ladder_table.dart` | constructor defaults `icdRedAccent`, `icdAmberAccent`, `gasSwitchAccent` | `SafetyColors.danger`, `SafetyColors.warning`, `SafetyColors.info` (still `const` defaults) |
| | `Divider(… color: Color(0xFF2A3A45))` | `context.palette.surfaceBezel` |
| | `Color(0xFF1A2832)` | `context.palette.chartGrid` |
| | `Colors.transparent` | stays |
| `plan_settings_panel.dart` | `Color(0xFFA0AEB6)` | `context.palette.textSecondary` |
| `plan_segments_editor.dart` | `isSafe ? null : const Color(0xFFE74C3C)` | `isSafe ? null : SafetyColors.danger` |
| `saved_plans_sheet.dart` | `Container(color: Colors.red)` (swipe-to-delete background) | `SafetyColors.danger` |

Where a replaced literal sat in a `const` expression, remove `const` from the nearest enclosing constructor that contains the palette read, and restore `const` on children the analyzer flags with `prefer_const_constructors`.

- [ ] **Step 4: Verify this group is clean**

Run:
```bash
grep -nE 'Color\(0x|\bColors\.[a-zA-Z]' lib/ui/screens/dive_detail_screen.dart lib/ui/screens/dive_plan_screen.dart lib/ui/widgets/dive_information_section.dart lib/ui/widgets/bailout_section.dart lib/ui/widgets/gas_safety_readout.dart lib/ui/widgets/stop_ladder_table.dart lib/ui/widgets/plan_settings_panel.dart lib/ui/widgets/plan_segments_editor.dart lib/ui/widgets/saved_plans_sheet.dart | grep -v 'Colors.transparent'
```
Expected: no output.

- [ ] **Step 5: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui test/ui
git commit -m "feat(theme): dive detail and planner follow the theme (#96)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Group C — lists, maps, media and sync

**Files:**
- Modify: `lib/ui/util/dive_mode_color.dart`, `lib/ui/screens/dive_list_screen.dart`, `lib/ui/screens/map_picker_screen.dart`, `lib/ui/screens/sites_map_screen.dart`, `lib/ui/screens/pdf_viewer_screen.dart`, `lib/ui/screens/image_viewer_screen.dart`, `lib/ui/widgets/site_mini_map.dart`, `lib/ui/widgets/dive_media_tab.dart`, `lib/ui/widgets/subsurface_sync_section.dart`, `lib/ui/widgets/sync_health_banner.dart`
- Test: modify `test/ui/widgets/sync_health_banner_test.dart` (create if absent)

**Interfaces:**
- Consumes: `DataColors`, `MediaColors`, `SafetyColors` additions (Task 1), `context.palette`.
- Produces: nothing other tasks consume.

- [ ] **Step 1: Write the failing test**

In the sync health banner's test file, add a test that pumps the banner in its critical and its warning state (reuse the construction from its existing tests or its call site) and asserts the background colours are `SafetyColors.alertCriticalSurface` and `SafetyColors.alertWarningSurface`, and that its icon colour is `SafetyColors.onAlert`. Then add a second test for `diveModeColor`: for each dive-mode value the function handles, the result equals the matching `DataColors.mode…` constant (read `lib/ui/util/dive_mode_color.dart` for the value-to-mode mapping).

- [ ] **Step 2: Run them**

The colour values are unchanged by this task, so these tests may already pass against the literals. That is expected: they pin the values before the refactor. Run them and confirm they pass before and after Step 3.

- [ ] **Step 3: Migrate, file by file**

| File | Line (content) | Becomes |
|---|---|---|
| `dive_mode_color.dart` | the five private constants | delete; `DataColors.modeClosedCircuit` / `modeOpenCircuit` / `modeSemiClosed` / `modeGauge` / `modeFreedive` |
| `dive_list_screen.dart` | `Colors.red.shade700` (swipe-to-delete background) | `SafetyColors.danger` |
| | `Icon(Icons.delete_outline, color: Colors.white)` | `SafetyColors.onAlert` |
| `map_picker_screen.dart` | `Colors.red` (pin) | `DataColors.mapPin` |
| `site_mini_map.dart` | `Colors.redAccent` (pin) | `DataColors.mapPin` |
| `sites_map_screen.dart` | `Color(0xFF8B3A3A)` (pin) | `DataColors.mapPinMuted` |
| `pdf_viewer_screen.dart`, `image_viewer_screen.dart` | `Colors.black` background | `MediaColors.viewerBackground` |
| | `Colors.black.withValues(alpha: 0.6)` | `MediaColors.scrim(0.6)` |
| | `Colors.white` foreground | `MediaColors.viewerForeground` |
| `dive_media_tab.dart` | `Colors.black.withValues(alpha: 0.35)` / `0.45` | `MediaColors.scrim(0.35)` / `MediaColors.scrim(0.45)` |
| | `Icon(… color: Colors.white)` over a photo | `MediaColors.onScrim` |
| | `Colors.transparent` | stays |
| `subsurface_sync_section.dart` | `Color(0xFFE65100)` text | `SafetyColors.warning` |
| | `Color(0xFFE53935)` text | `SafetyColors.danger` |
| | `Color(0xFFB0BEC5)` | `context.palette.textSecondary`; the enclosing `const` is removed |
| `sync_health_banner.dart` | `Color(0xFFB71C1C)` / `Color(0xFFE65100)` | `SafetyColors.alertCriticalSurface` / `alertWarningSurface` |
| | `Colors.white` | `SafetyColors.onAlert` |
| | `Colors.white70` | `SafetyColors.onAlert.withValues(alpha: 0.7)`; an enclosing `const` is removed |

`lib/ui/widgets/chip_input.dart` only uses `Colors.transparent` and is not touched.

- [ ] **Step 4: Verify this group is clean**

Run:
```bash
grep -nE 'Color\(0x|\bColors\.[a-zA-Z]' lib/ui/util/dive_mode_color.dart lib/ui/screens/dive_list_screen.dart lib/ui/screens/map_picker_screen.dart lib/ui/screens/sites_map_screen.dart lib/ui/screens/pdf_viewer_screen.dart lib/ui/screens/image_viewer_screen.dart lib/ui/widgets/site_mini_map.dart lib/ui/widgets/dive_media_tab.dart lib/ui/widgets/subsurface_sync_section.dart lib/ui/widgets/sync_health_banner.dart | grep -v 'Colors.transparent'
```
Expected: no output.

- [ ] **Step 5: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui test/ui
git commit -m "feat(theme): lists, maps, media and sync screens use named colours (#96)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Guard, switch theming on, verify

**Files:**
- Create: `test/ui/theme/no_loose_colors_test.dart`, `test/ui/theme/safety_everywhere_test.dart`
- Modify: `lib/ui/theme/app_themes.dart`

**Interfaces:**
- Consumes: the merged result of Tasks 1 to 4.

- [ ] **Step 1: Write the guard**

`test/ui/theme/no_loose_colors_test.dart`:

```dart
// Guards the theme system: colours in UI code come from the active theme
// (context.palette) or from the fixed classes in lib/ui/theme/
// (SafetyColors, DataColors, MediaColors). A colour literal or a named
// Material colour anywhere else will not follow the user's theme.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _allowed(String path) => path.startsWith('lib/ui/theme/');

final _literal = RegExp(r'\bColor\(0x|\bColor\.from(ARGB|RGBO)\(|\bHSLColor\b|\bHSVColor\b');
final _named = RegExp(r'\bColors\.([a-zA-Z0-9]+)');

void main() {
  test('no colour literals or named Material colours outside lib/ui/theme',
      () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowed(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.contains('//') ? line.substring(0, line.indexOf('//')) : line;
        final named = _named
            .allMatches(code)
            .where((m) => m.group(1) != 'transparent')
            .isNotEmpty;
        if (_literal.hasMatch(code) || named) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.palette, SafetyColors, DataColors or '
            'MediaColors instead:\n${offenders.join('\n')}');
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/ui/theme/no_loose_colors_test.dart`
Expected: PASS. If it lists offenders, Tasks 2 to 4 missed them: fix each by the rules of the task that owns the file, and say so in the report.

- [ ] **Step 3: A cross-theme safety test**

`test/ui/theme/safety_everywhere_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/gf_color.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('safety colours are the same under every theme',
      (tester) async {
    for (final t in AppThemes.all) {
      late Color error;
      await tester.pumpWidget(MaterialApp(
        theme: t.themeData,
        home: Builder(builder: (context) {
          error = Theme.of(context).colorScheme.error;
          return const SizedBox();
        }),
      ));
      expect(error, SafetyColors.danger, reason: t.id);
      expect(gfBandColor(50), SafetyColors.gfWithinLimits, reason: t.id);
      expect(gfBandColor(90), SafetyColors.gfOverHigh, reason: t.id);
      expect(gfBandColor(120), SafetyColors.gfOverLimit, reason: t.id);
    }
  });
}
```

Run: `flutter test test/ui/theme/safety_everywhere_test.dart` — expected PASS.

- [ ] **Step 4: Switch theming on**

In `lib/ui/theme/app_themes.dart`, replace the `kThemingEnabled` declaration and its doc comment with:

```dart
/// Whether the user can pick a theme, and whether a stored choice is
/// applied. On for every build since stage 2 swept the loose colours.
const bool kThemingEnabled = true;
```

Remove the `package:flutter/foundation.dart` import from that file if `flutter analyze` then reports it unused.

- [ ] **Step 5: Final automated checks**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.
Run: `git diff main --stat -- pubspec.yaml pubspec.lock` — expected: no output.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/theme/app_themes.dart test/ui/theme/no_loose_colors_test.dart test/ui/theme/safety_everywhere_test.dart
git commit -m "feat(theme): guard against loose colours and enable theming in release builds (#96)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Manual look-through (the owner)**

Build with `flutter build macos --release` and open `build/macos/Build/Products/Release/Anchorline.app`: Settings must now show "Appearance" in a release build. For each of the six themes look at the dive list, a CCR dive detail with every trace toggled on (legend swatches against the chart), the cell health strip, the planner with its stop ladder, the blend screen, the sync banner if it can be provoked, and a photo attachment. In Wreck, compare against the "Accepted changes to Wreck" list: nothing outside it should look different from before.

- [ ] **Step 8: Push and open the PR**

```bash
git push -u origin feat/96-theming-stage-2
gh pr create --title "feat(theme): selectable themes, stage 2 — sweep loose colours, theming on for everyone (#96)" --body "Closes #96. See docs/superpowers/plans/2026-10-08-theming-stage-2.md, including the list of accepted changes to Wreck.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
