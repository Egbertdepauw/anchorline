# Selectable Themes — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a theme system with six dark themes (Wreck plus Omarchy's Ethereal, Retro 82, Catppuccin, Hackerman, Miasma), a debug-only picker in Settings, and move every palette-token read onto the active theme.

**Architecture:** `ThemePalette` becomes a `ThemeExtension` carried inside `ThemeData`; widgets read it through `context.palette`. Each Omarchy theme is stored as its raw `colors.toml` values and turned into a `ThemePalette` by one mapping function that enforces contrast floors. Safety colours (status, GF bands) move to one fixed class shared by all themes. The chosen theme id lives in `SettingsNotifier` (local preferences) and drives `MaterialApp.theme`.

**Tech Stack:** Flutter 3.44 / Dart ^3.11.5, `shared_preferences` (already a dependency), `flutter_test`. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-06-theming-design.md`

## Global Constraints

- Six themes with these exact ids: `wreck`, `ethereal`, `retro82`, `catppuccin`, `hackerman`, `miasma`. Wreck is the default.
- Wreck's palette must stay value-for-value identical to today's.
- Safety colours keep today's exact values: success `#4ADE80`, warning `#F39C12`, danger `#E74C3C`, info `#60A5FA`, GF within limits `#4ADE80`, GF over GF-high `#F59E0B`, GF over 100 `#DC2626`.
- Contrast floors (WCAG ratio) against both `surfaceBg` and `surfaceCard`: `textPrimary` and `textSecondary` ≥ 4.5, `textMuted` ≥ 3.0.
- Cells: each ≥ 3.0 against `surfaceCard`, pairwise CIEDE2000 ≥ 20. PPO2 trace: ≥ 3.0 against `surfaceCard`, CIEDE2000 ≥ 15 from depth and setpoint traces.
- A theme changes colours only. Do not touch typography, spacing, radii or motion.
- The theme choice is per device (`SharedPreferences`). No Supabase table, no PowerSync rule.
- The picker is visible only when `kDebugMode` is true in this stage.
- Loose `Color(0x…)` literals and `Colors.*` uses are stage 2. Do not sweep them here, except the six token-mirroring literals in `cell_mv_chart.dart` (Task 8).
- No new dependencies.
- Do not run `dart format` on existing files: `main` is not format-clean and it churns hundreds of lines. Match the surrounding style by hand. New files may be formatted.
- Every task ends with `flutter analyze` clean and the listed tests passing.
- Commit messages end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

Conditions the spec implies but that are easy to leave untested. Each has a test in the task named.

1. **Stored theme value has the wrong type** (an `int` or `bool` under the key from a bad write): the app starts in Wreck; it must not throw during `settings.load()`, which runs before the first frame. → Task 6.
2. **A widget is built without the app theme** (the many existing widget tests that pump a bare `MaterialApp`, or a subtree under a different `Theme`): `context.palette` returns Wreck; it must not null-crash. → Task 3.
3. **The theme changes while a dive detail is open**: the profile and cell charts repaint in the new colours without needing a scroll or tap. → Task 8.
4. **Mid-transition theme lerp**: Flutter calls `ThemePalette.lerp` with `t` between 0 and 1 and may pass `null` or another extension type as `other`; it must return a valid palette. → Task 3.
5. **`setThemeId` is called with an id that is not registered** (stale UI after a theme is renamed): the setting resolves to Wreck and what gets persisted is a valid id. → Task 6.

## File Structure

| File | Responsibility |
|---|---|
| `lib/ui/theme/color_math.dart` (new) | Pure colour maths: WCAG contrast, CIE Lab, CIEDE2000. No widgets. |
| `lib/ui/theme/safety_colors.dart` (new) | The fixed safety colours. |
| `lib/ui/theme/tokens.dart` (modify) | `ThemePalette` as a `ThemeExtension`; `context.palette`; `AppColors.wreck`. |
| `lib/ui/theme/gf_color.dart` (modify) | Reads the GF band colours from `SafetyColors`. |
| `lib/ui/theme/app_theme.dart` (modify) | `AppTheme.build(palette)`. |
| `lib/ui/theme/omarchy/omarchy_colors.dart` (new) | `OmarchyColors`: one theme's raw `colors.toml` values. |
| `lib/ui/theme/omarchy/{ethereal,retro_82,catppuccin,hackerman,miasma}.dart` (new) | One const `OmarchyColors` each. |
| `lib/ui/theme/omarchy/omarchy_mapping.dart` (new) | `paletteFromOmarchy` and the rule predicates. |
| `lib/ui/theme/app_themes.dart` (new) | The registry: ids, names, palettes, `ThemeData`. |
| `lib/ui/theme/active_theme_builder.dart` (new) | Rebuilds with the settings' current `ThemeData`. |
| `lib/ui/notifiers/settings_notifier.dart` (modify) | Persists the theme id. |
| `lib/ui/widgets/theme_picker.dart` (new) | The picker rows with swatches. |
| `lib/ui/screens/settings_screen.dart` (modify) | "Appearance" section, debug-gated. |
| `lib/main.dart` (modify) | Wires `ActiveThemeBuilder` around `MaterialApp`. |
| Call-site files (modify) | Listed in Tasks 2, 7 and 8. |

## Before Task 1

- [ ] Create the GitHub issue: `gh issue create --title "feat(theme): selectable themes, stage 1 — theme system, Omarchy palettes, debug-only picker" --label enhancement --body "Spec: docs/superpowers/specs/2026-10-06-theming-design.md. Plan: docs/superpowers/plans/2026-10-06-theming-stage-1.md. Stage 2 (sweep of loose colour literals, picker made visible) is a separate issue."` Note the issue number as `93`.
- [ ] Branch from up-to-date `main` (never `git reset --hard`; the tree has long-lived untracked files): `git switch main && git pull --ff-only && git switch -c feat/93-theming-stage-1`
- [ ] Commit the two documents:

```bash
git add docs/superpowers/specs/2026-10-06-theming-design.md docs/superpowers/plans/2026-10-06-theming-stage-1.md
git commit -m "docs(theme): spec and stage 1 plan for selectable themes (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: Colour maths

**Files:**
- Create: `lib/ui/theme/color_math.dart`
- Test: `test/ui/theme/color_math_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `double relativeLuminance(Color c)`
  - `double contrastRatio(Color a, Color b)` — WCAG ratio, 1.0 to 21.0, symmetric.
  - `typedef Lab = ({double l, double a, double b});`
  - `Lab labOf(Color c)` — sRGB (D65) to CIE L\*a\*b\*.
  - `double deltaE2000Lab(Lab p, Lab q)`
  - `double deltaE2000(Color a, Color b)`

- [ ] **Step 1: Write the failing test**

`test/ui/theme/color_math_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contrastRatio', () {
    test('black on white is 21', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.001));
    });
    test('a colour against itself is 1', () {
      expect(contrastRatio(const Color(0xFF4ADE80), const Color(0xFF4ADE80)),
          closeTo(1.0, 0.0001));
    });
    test('is symmetric', () {
      const a = Color(0xFFE0E8EC), b = Color(0xFF0A1518);
      expect(contrastRatio(a, b), contrastRatio(b, a));
    });
    test('Wreck primary text on Wreck background is about 14.9', () {
      expect(contrastRatio(const Color(0xFFE0E8EC), const Color(0xFF0A1518)),
          closeTo(14.93, 0.05));
    });
  });

  group('deltaE2000Lab', () {
    // Reference pairs from Sharma, Wu & Dalal (2005), CIEDE2000 test data.
    test('matches published reference pairs', () {
      expect(
          deltaE2000Lab((l: 50, a: 2.6772, b: -79.7751),
              (l: 50, a: 0, b: -82.7485)),
          closeTo(2.0425, 0.0001));
      expect(
          deltaE2000Lab((l: 50, a: 3.1571, b: -77.2803),
              (l: 50, a: 0, b: -82.7485)),
          closeTo(2.8615, 0.0001));
      expect(
          deltaE2000Lab((l: 50, a: 2.8361, b: -74.0200),
              (l: 50, a: 0, b: -82.7485)),
          closeTo(3.4412, 0.0001));
      expect(deltaE2000Lab((l: 50, a: 2.5, b: 0), (l: 50, a: 0, b: -2.5)),
          closeTo(4.3065, 0.0001));
    });
  });

  group('deltaE2000', () {
    test('identical colours are 0', () {
      expect(deltaE2000(const Color(0xFF60A5FA), const Color(0xFF60A5FA)),
          closeTo(0, 0.0001));
    });
    test('black to white is 100', () {
      expect(deltaE2000(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(100, 0.01));
    });
    test('Wreck cell 1 and cell 2 are far apart (about 50)', () {
      expect(deltaE2000(const Color(0xFF4ADE80), const Color(0xFF60A5FA)),
          closeTo(50.0, 0.5));
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/ui/theme/color_math_test.dart`
Expected: FAIL to compile — `color_math.dart` does not exist.

- [ ] **Step 3: Implement**

`lib/ui/theme/color_math.dart`:

```dart
// Pure colour maths used to check theme palettes: WCAG contrast and the
// CIEDE2000 colour difference. No widgets, no theme state.

import 'dart:math' as math;
import 'dart:ui' show Color;

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.x relative luminance of an opaque sRGB colour (0 black, 1 white).
double relativeLuminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// WCAG 2.x contrast ratio between two opaque colours, 1.0 to 21.0.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A CIE L*a*b* colour (D65 white point).
typedef Lab = ({double l, double a, double b});

Lab labOf(Color c) {
  final r = _linear(c.r);
  final g = _linear(c.g);
  final b = _linear(c.b);
  final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
  final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
  final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
  double f(double t) => t > 216 / 24389
      ? math.pow(t, 1 / 3).toDouble()
      : (24389 / 27 * t + 16) / 116;
  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _rad(double deg) => deg * math.pi / 180;

double _hueDeg(double b, double a) {
  if (a == 0 && b == 0) return 0;
  final h = math.atan2(b, a) * 180 / math.pi;
  return h < 0 ? h + 360 : h;
}

/// CIEDE2000 colour difference. Around 1 is a just-noticeable difference.
double deltaE2000Lab(Lab p, Lab q) {
  const pow25to7 = 6103515625.0; // 25^7
  final c1 = math.sqrt(p.a * p.a + p.b * p.b);
  final c2 = math.sqrt(q.a * q.a + q.b * q.b);
  final cBar7 = math.pow((c1 + c2) / 2, 7).toDouble();
  final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + pow25to7)));
  final a1 = (1 + g) * p.a;
  final a2 = (1 + g) * q.a;
  final c1p = math.sqrt(a1 * a1 + p.b * p.b);
  final c2p = math.sqrt(a2 * a2 + q.b * q.b);
  final h1 = _hueDeg(p.b, a1);
  final h2 = _hueDeg(q.b, a2);

  final dL = q.l - p.l;
  final dC = c2p - c1p;
  var dh = 0.0;
  if (c1p * c2p != 0) {
    dh = h2 - h1;
    if (dh > 180) {
      dh -= 360;
    } else if (dh < -180) {
      dh += 360;
    }
  }
  final dH = 2 * math.sqrt(c1p * c2p) * math.sin(_rad(dh / 2));

  final lBar = (p.l + q.l) / 2;
  final cBarP = (c1p + c2p) / 2;
  double hBar;
  if (c1p * c2p == 0) {
    hBar = h1 + h2;
  } else if ((h1 - h2).abs() <= 180) {
    hBar = (h1 + h2) / 2;
  } else if (h1 + h2 < 360) {
    hBar = (h1 + h2 + 360) / 2;
  } else {
    hBar = (h1 + h2 - 360) / 2;
  }

  final t = 1 -
      0.17 * math.cos(_rad(hBar - 30)) +
      0.24 * math.cos(_rad(2 * hBar)) +
      0.32 * math.cos(_rad(3 * hBar + 6)) -
      0.20 * math.cos(_rad(4 * hBar - 63));
  final dTheta = 30 * math.exp(-math.pow((hBar - 275) / 25, 2));
  final cBarP7 = math.pow(cBarP, 7).toDouble();
  final rC = 2 * math.sqrt(cBarP7 / (cBarP7 + pow25to7));
  final lTerm = (lBar - 50) * (lBar - 50);
  final sL = 1 + 0.015 * lTerm / math.sqrt(20 + lTerm);
  final sC = 1 + 0.045 * cBarP;
  final sH = 1 + 0.015 * cBarP * t;
  final rT = -math.sin(_rad(2 * dTheta)) * rC;

  final xL = dL / sL;
  final xC = dC / sC;
  final xH = dH / sH;
  return math.sqrt(xL * xL + xC * xC + xH * xH + rT * xC * xH);
}

double deltaE2000(Color a, Color b) => deltaE2000Lab(labOf(a), labOf(b));
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/theme/color_math_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze` — expected `No issues found!`

```bash
git add lib/ui/theme/color_math.dart test/ui/theme/color_math_test.dart
git commit -m "feat(theme): colour maths — WCAG contrast and CIEDE2000 (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Fixed safety colours

Moves the four status tokens out of `ThemePalette` into a fixed class and points every reader at it. After this task `ThemePalette` has 18 fields.

**Files:**
- Create: `lib/ui/theme/safety_colors.dart`
- Modify: `lib/ui/theme/tokens.dart` (remove the four `status*` fields from `ThemePalette` and from `AppColors.wreck`)
- Modify: `lib/ui/theme/gf_color.dart`
- Modify: `lib/ui/theme/app_theme.dart` (`error:` line)
- Modify (status call sites): `lib/ui/screens/blend_screen.dart`, `lib/ui/screens/dive_plan_screen.dart`, `lib/ui/dev/widgetbook_screen.dart`, `lib/ui/widgets/dive_annotations_section.dart`, `lib/ui/widgets/dive_tile.dart`, `lib/ui/widgets/profile_chart.dart`, `lib/ui/components/status_dot.dart` (comment only)
- Test: `test/ui/theme/safety_colors_test.dart`; modify `test/ui/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `SafetyColors.success`, `.warning`, `.danger`, `.info`, `.gfWithinLimits`, `.gfOverHigh`, `.gfOverLimit` (all `static const Color`), and `SafetyColors.all` (`static const Map<String, Color>` keyed by those seven names).

- [ ] **Step 1: Write the failing test**

`test/ui/theme/safety_colors_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safety colours keep their established values', () {
    expect(SafetyColors.success, const Color(0xFF4ADE80));
    expect(SafetyColors.warning, const Color(0xFFF39C12));
    expect(SafetyColors.danger, const Color(0xFFE74C3C));
    expect(SafetyColors.info, const Color(0xFF60A5FA));
    expect(SafetyColors.gfWithinLimits, const Color(0xFF4ADE80));
    expect(SafetyColors.gfOverHigh, const Color(0xFFF59E0B));
    expect(SafetyColors.gfOverLimit, const Color(0xFFDC2626));
  });

  test('all lists every safety colour by name', () {
    expect(SafetyColors.all.keys, [
      'success',
      'warning',
      'danger',
      'info',
      'gfWithinLimits',
      'gfOverHigh',
      'gfOverLimit',
    ]);
    expect(SafetyColors.all['danger'], SafetyColors.danger);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/ui/theme/safety_colors_test.dart`
Expected: FAIL to compile — `safety_colors.dart` does not exist.

- [ ] **Step 3: Create `SafetyColors`**

`lib/ui/theme/safety_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Colours that carry safety meaning. They are identical in every theme:
/// a warning must look like a warning whatever palette the diver picked.
/// Never derive these from the active theme.
class SafetyColors {
  SafetyColors._();

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFF39C12);
  static const Color danger = Color(0xFFE74C3C);
  static const Color info = Color(0xFF60A5FA);

  /// Gradient-factor bands, see `gfBandColor`.
  static const Color gfWithinLimits = Color(0xFF4ADE80);
  static const Color gfOverHigh = Color(0xFFF59E0B);
  static const Color gfOverLimit = Color(0xFFDC2626);

  /// Every safety colour by name, for tests that check them against each
  /// theme's surfaces.
  static const Map<String, Color> all = {
    'success': success,
    'warning': warning,
    'danger': danger,
    'info': info,
    'gfWithinLimits': gfWithinLimits,
    'gfOverHigh': gfOverHigh,
    'gfOverLimit': gfOverLimit,
  };
}
```

- [ ] **Step 4: Point `gf_color.dart` at it**

In `lib/ui/theme/gf_color.dart`, add `import 'safety_colors.dart';` and replace the function body with:

```dart
Color gfBandColor(double gf, {double gfHigh = 85}) {
  if (gf > 100) return SafetyColors.gfOverLimit; // red — supersaturated
  if (gf > gfHigh) return SafetyColors.gfOverHigh; // amber — over GF-high
  return SafetyColors.gfWithinLimits; // green — within limits
}
```

- [ ] **Step 5: Remove the status tokens from `ThemePalette`**

In `lib/ui/theme/tokens.dart`, delete from `ThemePalette` the four constructor parameters `required this.statusSuccess`, `required this.statusWarning`, `required this.statusDanger`, `required this.statusInfo`, and the four matching `final Color status…;` fields. In `AppColors.wreck`, delete the four `status…:` arguments.

- [ ] **Step 6: Fix every reader**

Run `flutter analyze`; it now reports each read of a removed field, in `lib/` and in `test/`. Replace by this table, adding `import '../theme/safety_colors.dart';` (adjust the relative path) to each file touched:

| Old | New |
|---|---|
| `AppColors.wreck.statusSuccess` | `SafetyColors.success` |
| `AppColors.wreck.statusWarning` | `SafetyColors.warning` |
| `AppColors.wreck.statusDanger` | `SafetyColors.danger` |
| `AppColors.wreck.statusInfo` | `SafetyColors.info` |
| `palette.statusDanger` (in `app_theme.dart`, the `error:` line) | `SafetyColors.danger` |

In `lib/ui/widgets/profile_chart.dart` the three affected top-level declarations become constants:

```dart
const Color _decoColor = SafetyColors.warning;
const Color _gasChangeColor = SafetyColors.info;
const Color _bailoutColor = SafetyColors.danger;
```

In `lib/ui/components/status_dot.dart`, update the doc comment to name `SafetyColors.success / warning / danger / info` in place of the `AppColors.wreck.status…` names.

If a file no longer uses `AppColors` after the change, remove its now-unused `tokens.dart` import only if the analyzer flags it.

- [ ] **Step 7: Update the existing theme test**

In `test/ui/theme/app_theme_test.dart`, add `import 'package:ccrlogger/ui/theme/safety_colors.dart';` and change the error assertion to:

```dart
    expect(t.colorScheme.error, SafetyColors.danger);
```

- [ ] **Step 8: Run tests and analyze**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test test/ui/theme` — expected PASS, including the unchanged `gf_color_test.dart`.
Run: `grep -rnE "(wreck|palette)\.status(Success|Warning|Danger|Info)" lib test --include='*.dart'` — expected: no output.

- [ ] **Step 9: Full suite and commit**

Run: `flutter test` — expected: all pass.

```bash
git add lib test
git commit -m "refactor(theme): move status and GF colours to fixed SafetyColors (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `ThemePalette` as a theme extension

**Files:**
- Modify: `lib/ui/theme/tokens.dart`
- Modify: `lib/ui/theme/app_theme.dart`
- Test: `test/ui/theme/theme_palette_test.dart`; modify `test/ui/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: `ThemePalette` with 18 `Color` fields (after Task 2): `surfaceBg`, `surfaceCard`, `surfaceRaised`, `surfaceBezel`, `textPrimary`, `textSecondary`, `textMuted`, `textInverse`, `accentPrimary`, `accentMuted`, `cell1`, `cell2`, `cell3`, `chartGrid`, `chartTraceDepth`, `chartTracePpo2`, `chartTraceSetpoint`, `chartTraceGf99`.
- Produces:
  - `class ThemePalette extends ThemeExtension<ThemePalette>` with a `const` constructor, `copyWith({...})` (every field optional) and `lerp(ThemePalette? other, double t)`.
  - `extension PaletteContext on BuildContext { ThemePalette get palette; }` — the active palette, or `AppColors.wreck` when the theme carries none.
  - `static ThemeData AppTheme.build(ThemePalette palette)`; `AppTheme.dark()` stays and returns `build(AppColors.wreck)`.

- [ ] **Step 1: Write the failing tests**

`test/ui/theme/theme_palette_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final other = AppColors.wreck.copyWith(
    surfaceBg: const Color(0xFF1E1E2E),
    accentPrimary: const Color(0xFF89B4FA),
  );

  group('ThemePalette', () {
    test('copyWith replaces only the named fields', () {
      expect(other.surfaceBg, const Color(0xFF1E1E2E));
      expect(other.accentPrimary, const Color(0xFF89B4FA));
      expect(other.surfaceCard, AppColors.wreck.surfaceCard);
      expect(other.cell3, AppColors.wreck.cell3);
    });

    test('lerp returns the endpoints at t=0 and t=1', () {
      expect(AppColors.wreck.lerp(other, 0).surfaceBg,
          AppColors.wreck.surfaceBg);
      expect(AppColors.wreck.lerp(other, 1).surfaceBg, other.surfaceBg);
      expect(AppColors.wreck.lerp(other, 1).accentPrimary,
          other.accentPrimary);
    });

    test('lerp at t=0.5 is between the endpoints', () {
      final mid = AppColors.wreck.lerp(other, 0.5).surfaceBg;
      expect(mid, isNot(AppColors.wreck.surfaceBg));
      expect(mid, isNot(other.surfaceBg));
    });

    test('lerp with null returns this palette', () {
      expect(AppColors.wreck.lerp(null, 0.5), same(AppColors.wreck));
    });
  });

  group('context.palette', () {
    testWidgets('returns the palette of the active theme', (tester) async {
      late ThemePalette seen;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(other),
        home: Builder(builder: (context) {
          seen = context.palette;
          return const SizedBox();
        }),
      ));
      expect(seen.surfaceBg, const Color(0xFF1E1E2E));
    });

    testWidgets('falls back to Wreck when the theme carries no palette',
        (tester) async {
      late ThemePalette seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = context.palette;
          return const SizedBox();
        }),
      ));
      expect(seen, same(AppColors.wreck));
    });
  });

  group('AppTheme.build', () {
    test('wires the palette into ThemeData', () {
      final t = AppTheme.build(other);
      expect(t.extension<ThemePalette>(), same(other));
      expect(t.colorScheme.surface, other.surfaceBg);
      expect(t.colorScheme.primary, other.accentPrimary);
      expect(t.scaffoldBackgroundColor, other.surfaceBg);
      expect(t.brightness, Brightness.dark);
    });

    test('dark() is build(wreck)', () {
      expect(AppTheme.dark().extension<ThemePalette>(),
          same(AppColors.wreck));
    });
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/theme/theme_palette_test.dart`
Expected: FAIL to compile — `copyWith`, `lerp`, `context.palette`, `AppTheme.build` are undefined.

- [ ] **Step 3: Make `ThemePalette` a `ThemeExtension`**

In `lib/ui/theme/tokens.dart`, change the class header to

```dart
class ThemePalette extends ThemeExtension<ThemePalette> {
```

and add these two methods inside the class, after the fields:

```dart
  @override
  ThemePalette copyWith({
    Color? surfaceBg,
    Color? surfaceCard,
    Color? surfaceRaised,
    Color? surfaceBezel,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textInverse,
    Color? accentPrimary,
    Color? accentMuted,
    Color? cell1,
    Color? cell2,
    Color? cell3,
    Color? chartGrid,
    Color? chartTraceDepth,
    Color? chartTracePpo2,
    Color? chartTraceSetpoint,
    Color? chartTraceGf99,
  }) {
    return ThemePalette(
      surfaceBg: surfaceBg ?? this.surfaceBg,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceBezel: surfaceBezel ?? this.surfaceBezel,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textInverse: textInverse ?? this.textInverse,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentMuted: accentMuted ?? this.accentMuted,
      cell1: cell1 ?? this.cell1,
      cell2: cell2 ?? this.cell2,
      cell3: cell3 ?? this.cell3,
      chartGrid: chartGrid ?? this.chartGrid,
      chartTraceDepth: chartTraceDepth ?? this.chartTraceDepth,
      chartTracePpo2: chartTracePpo2 ?? this.chartTracePpo2,
      chartTraceSetpoint: chartTraceSetpoint ?? this.chartTraceSetpoint,
      chartTraceGf99: chartTraceGf99 ?? this.chartTraceGf99,
    );
  }

  /// Used by Flutter to cross-fade between two themes.
  @override
  ThemePalette lerp(covariant ThemeExtension<ThemePalette>? other, double t) {
    if (other is! ThemePalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ThemePalette(
      surfaceBg: mix(surfaceBg, other.surfaceBg),
      surfaceCard: mix(surfaceCard, other.surfaceCard),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceBezel: mix(surfaceBezel, other.surfaceBezel),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textInverse: mix(textInverse, other.textInverse),
      accentPrimary: mix(accentPrimary, other.accentPrimary),
      accentMuted: mix(accentMuted, other.accentMuted),
      cell1: mix(cell1, other.cell1),
      cell2: mix(cell2, other.cell2),
      cell3: mix(cell3, other.cell3),
      chartGrid: mix(chartGrid, other.chartGrid),
      chartTraceDepth: mix(chartTraceDepth, other.chartTraceDepth),
      chartTracePpo2: mix(chartTracePpo2, other.chartTracePpo2),
      chartTraceSetpoint: mix(chartTraceSetpoint, other.chartTraceSetpoint),
      chartTraceGf99: mix(chartTraceGf99, other.chartTraceGf99),
    );
  }
```

Update the class doc comment to: `/// A complete colour palette, carried in ThemeData as a theme extension. Read it in widgets with context.palette.`

At the end of the Palette section (after the `AppColors` class), add:

```dart
/// The active [ThemePalette]. Falls back to Wreck when the surrounding
/// theme carries none, so a widget built outside the app theme (a test
/// harness, a nested Theme) still gets a complete palette.
extension PaletteContext on BuildContext {
  ThemePalette get palette =>
      Theme.of(this).extension<ThemePalette>() ?? AppColors.wreck;
}
```

- [ ] **Step 4: Add `AppTheme.build`**

In `lib/ui/theme/app_theme.dart`, replace

```dart
  static ThemeData dark() {
    const palette = AppColors.wreck;
```

with

```dart
  /// The default theme (Wreck).
  static ThemeData dark() => build(AppColors.wreck);

  /// Builds the app's ThemeData from [palette]. Every theme is dark.
  static ThemeData build(ThemePalette palette) {
```

and in the `return ThemeData(` call add, directly after `useMaterial3: true,`:

```dart
      extensions: [palette],
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/ui/theme`
Expected: PASS.

- [ ] **Step 6: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui/theme test/ui/theme
git commit -m "feat(theme): carry ThemePalette in ThemeData as a theme extension (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Omarchy source colours and mapping

**Files:**
- Create: `lib/ui/theme/omarchy/omarchy_colors.dart`
- Create: `lib/ui/theme/omarchy/ethereal.dart`, `retro_82.dart`, `catppuccin.dart`, `hackerman.dart`, `miasma.dart`
- Create: `lib/ui/theme/omarchy/omarchy_mapping.dart`
- Test: `test/ui/theme/omarchy_mapping_test.dart`

**Interfaces:**
- Consumes: `contrastRatio`, `deltaE2000` (Task 1); `ThemePalette`, `AppColors.wreck` (Task 3).
- Produces:
  - `class OmarchyColors` (const; fields below).
  - `const OmarchyColors etherealColors`, `retro82Colors`, `catppuccinColors`, `hackermanColors`, `miasmaColors`.
  - `const double kMinTextContrast = 4.5`, `kMinMutedTextContrast = 3.0`, `kMinTraceContrast = 3.0`, `kMinCellDeltaE = 20`, `kMinPpo2DeltaE = 15`.
  - `Color liftToContrast(Color color, Color toward, List<Color> backgrounds, double minRatio)`
  - `bool cellColorsPass(Color c1, Color c2, Color c3, Color card)`
  - `bool ppo2ColorPasses(Color ppo2, Color depth, Color setpoint, Color card)`
  - `ThemePalette paletteFromOmarchy(OmarchyColors o)`

- [ ] **Step 1: Write the failing test**

`test/ui/theme/omarchy_mapping_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:ccrlogger/ui/theme/omarchy/catppuccin.dart';
import 'package:ccrlogger/ui/theme/omarchy/ethereal.dart';
import 'package:ccrlogger/ui/theme/omarchy/hackerman.dart';
import 'package:ccrlogger/ui/theme/omarchy/miasma.dart';
import 'package:ccrlogger/ui/theme/omarchy/omarchy_colors.dart';
import 'package:ccrlogger/ui/theme/omarchy/omarchy_mapping.dart';
import 'package:ccrlogger/ui/theme/omarchy/retro_82.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sources = <String, OmarchyColors>{
  'ethereal': etherealColors,
  'retro82': retro82Colors,
  'catppuccin': catppuccinColors,
  'hackerman': hackermanColors,
  'miasma': miasmaColors,
};

void main() {
  group('direct mappings', () {
    test('Catppuccin surfaces, text and accent come straight from the source',
        () {
      final p = paletteFromOmarchy(catppuccinColors);
      expect(p.surfaceBg, const Color(0xFF1E1E2E));
      expect(p.surfaceCard, const Color(0xFF313244));
      expect(p.surfaceRaised, const Color(0xFF45475A));
      expect(p.surfaceBezel, const Color(0xFF585B70));
      expect(p.textPrimary, const Color(0xFFCDD6F4));
      expect(p.textSecondary, const Color(0xFFBAC2DE));
      expect(p.textInverse, const Color(0xFF1E1E2E));
      expect(p.accentPrimary, const Color(0xFF89B4FA));
      expect(p.chartTraceDepth, p.textPrimary);
      expect(p.chartTraceSetpoint, p.textSecondary);
    });

    test('every theme maps background, card and accent from its source', () {
      _sources.forEach((name, o) {
        final p = paletteFromOmarchy(o);
        expect(p.surfaceBg, o.background, reason: name);
        expect(p.surfaceCard, o.lighterBackground, reason: name);
        expect(p.accentPrimary, o.accent, reason: name);
        expect(p.textPrimary, o.foreground, reason: name);
      });
    });

    test('derived tokens lie between their endpoints', () {
      final p = paletteFromOmarchy(etherealColors);
      expect(p.accentMuted,
          Color.lerp(etherealColors.accent, etherealColors.background, 0.5));
      expect(
          p.chartGrid,
          Color.lerp(etherealColors.lighterBackground,
              etherealColors.selection, 0.5));
    });
  });

  group('readability floor', () {
    test('liftToContrast leaves a passing colour untouched', () {
      const c = Color(0xFFCDD6F4);
      expect(
          liftToContrast(c, const Color(0xFFFFFFFF),
              const [Color(0xFF1E1E2E)], 4.5),
          c);
    });

    test('liftToContrast raises a failing colour until it passes', () {
      const dim = Color(0xFF555555);
      const bgs = [Color(0xFF222222), Color(0xFF2C2C2C)];
      final lifted = liftToContrast(dim, const Color(0xFFC2C2B0), bgs, 3.0);
      expect(lifted, isNot(dim));
      for (final bg in bgs) {
        expect(contrastRatio(lifted, bg), greaterThanOrEqualTo(3.0));
      }
    });

    test('Miasma muted and secondary text are lifted, primary is not', () {
      final p = paletteFromOmarchy(miasmaColors);
      expect(p.textPrimary, miasmaColors.foreground);
      expect(p.textSecondary, isNot(miasmaColors.lightForeground));
      expect(p.textMuted, isNot(miasmaColors.darkForeground));
    });

    test('Ethereal text needs no lifting', () {
      final p = paletteFromOmarchy(etherealColors);
      expect(p.textSecondary, etherealColors.lightForeground);
      expect(p.textMuted, etherealColors.darkForeground);
    });

    test('every theme meets the text contrast floors', () {
      _sources.forEach((name, o) {
        final p = paletteFromOmarchy(o);
        for (final bg in [p.surfaceBg, p.surfaceCard]) {
          expect(contrastRatio(p.textPrimary, bg),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '$name textPrimary');
          expect(contrastRatio(p.textSecondary, bg),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '$name textSecondary');
          expect(contrastRatio(p.textMuted, bg),
              greaterThanOrEqualTo(kMinMutedTextContrast),
              reason: '$name textMuted');
        }
      });
    });
  });

  group('cells and PPO2', () {
    test('stated choices are the ones the rules allow', () {
      _sources.forEach((name, o) {
        final card = o.lighterBackground;
        expect(o.useOwnCellColors,
            cellColorsPass(o.green, o.blue, o.magenta, card),
            reason: '$name useOwnCellColors');
        final p = paletteFromOmarchy(o);
        expect(
            o.useOwnPpo2Color,
            ppo2ColorPasses(
                o.yellow, p.chartTraceDepth, p.chartTraceSetpoint, card),
            reason: '$name useOwnPpo2Color');
      });
    });

    test('expected outcome per theme', () {
      expect(etherealColors.useOwnCellColors, isTrue);
      expect(catppuccinColors.useOwnCellColors, isTrue);
      expect(retro82Colors.useOwnCellColors, isFalse);
      expect(hackermanColors.useOwnCellColors, isFalse);
      expect(miasmaColors.useOwnCellColors, isFalse);
      for (final o in _sources.values) {
        expect(o.useOwnPpo2Color, isTrue);
      }
    });

    test('own cell colours are used when stated, Wreck defaults otherwise',
        () {
      final cat = paletteFromOmarchy(catppuccinColors);
      expect(cat.cell1, catppuccinColors.green);
      expect(cat.cell2, catppuccinColors.blue);
      expect(cat.cell3, catppuccinColors.magenta);
      expect(cat.chartTraceGf99, cat.cell3);

      final hack = paletteFromOmarchy(hackermanColors);
      expect(hack.cell1, AppColors.wreck.cell1);
      expect(hack.cell2, AppColors.wreck.cell2);
      expect(hack.cell3, AppColors.wreck.cell3);
      expect(hack.chartTraceGf99, AppColors.wreck.chartTraceGf99);
      expect(hack.chartTracePpo2, hackermanColors.yellow);
    });
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/theme/omarchy_mapping_test.dart`
Expected: FAIL to compile — the `omarchy/` files do not exist.

- [ ] **Step 3: Create `OmarchyColors`**

`lib/ui/theme/omarchy/omarchy_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// One Omarchy theme's colours, copied unchanged from
/// `themes/<name>/colors.toml` in github.com/basecamp/omarchy. Field names
/// are the toml keys in camelCase. Do not adjust values here: the mapping
/// in omarchy_mapping.dart does any readability correction.
class OmarchyColors {
  const OmarchyColors({
    required this.accent,
    required this.selection,
    required this.muted,
    required this.background,
    required this.darkBackground,
    required this.darkerBackground,
    required this.lighterBackground,
    required this.foreground,
    required this.darkForeground,
    required this.lightForeground,
    required this.brightForeground,
    required this.red,
    required this.yellow,
    required this.orange,
    required this.green,
    required this.cyan,
    required this.blue,
    required this.magenta,
    required this.brown,
    required this.brightRed,
    required this.brightYellow,
    required this.brightGreen,
    required this.brightCyan,
    required this.brightBlue,
    required this.brightMagenta,
    required this.useOwnCellColors,
    required this.useOwnPpo2Color,
  });

  final Color accent;
  final Color selection;
  final Color muted;
  final Color background;
  final Color darkBackground;
  final Color darkerBackground;
  final Color lighterBackground;
  final Color foreground;
  final Color darkForeground;
  final Color lightForeground;
  final Color brightForeground;
  final Color red;
  final Color yellow;
  final Color orange;
  final Color green;
  final Color cyan;
  final Color blue;
  final Color magenta;
  final Color brown;
  final Color brightRed;
  final Color brightYellow;
  final Color brightGreen;
  final Color brightCyan;
  final Color brightBlue;
  final Color brightMagenta;

  /// Not from colors.toml. True when this theme's green/blue/magenta are
  /// distinct and readable enough to colour cells 1/2/3; false to keep the
  /// Wreck cell colours. A test checks this matches the rule.
  final bool useOwnCellColors;

  /// Not from colors.toml. True when this theme's yellow is distinct enough
  /// from its depth and setpoint traces to colour the PPO2 trace.
  final bool useOwnPpo2Color;
}
```

- [ ] **Step 4: Create the five source files**

`lib/ui/theme/omarchy/ethereal.dart`:

```dart
import 'package:flutter/material.dart';

import 'omarchy_colors.dart';

/// Omarchy "Ethereal" — themes/ethereal/colors.toml, read 2026-10-06.
const OmarchyColors etherealColors = OmarchyColors(
  accent: Color(0xFF7D82D9),
  selection: Color(0xFF252E56),
  muted: Color(0xFF6D7DB6),
  background: Color(0xFF060B1E),
  darkBackground: Color(0xFF040816),
  darkerBackground: Color(0xFF030610),
  lighterBackground: Color(0xFF131A3A),
  foreground: Color(0xFFFFCEAD),
  darkForeground: Color(0xFF6D7DB6),
  lightForeground: Color(0xFFC9B8A6),
  brightForeground: Color(0xFFFFCEAD),
  red: Color(0xFFED5B5A),
  yellow: Color(0xFFE9BB4F),
  orange: Color(0xFFEB8B54),
  green: Color(0xFF92A593),
  cyan: Color(0xFFA3BFD1),
  blue: Color(0xFF7D82D9),
  magenta: Color(0xFFC89DC1),
  brown: Color(0xFF75452A),
  brightRed: Color(0xFFFAAAA9),
  brightYellow: Color(0xFFF7DC9C),
  brightGreen: Color(0xFFC4CFC4),
  brightCyan: Color(0xFFDFEAF0),
  brightBlue: Color(0xFFC2C4F0),
  brightMagenta: Color(0xFFEAD7E7),
  useOwnCellColors: true,
  useOwnPpo2Color: true,
);
```

`lib/ui/theme/omarchy/retro_82.dart`:

```dart
import 'package:flutter/material.dart';

import 'omarchy_colors.dart';

/// Omarchy "Retro 82" — themes/retro-82/colors.toml, read 2026-10-06.
/// Blue and magenta are the same teal, so cells keep the Wreck colours.
const OmarchyColors retro82Colors = OmarchyColors(
  accent: Color(0xFFFAA968),
  selection: Color(0xFF134E5A),
  muted: Color(0xFF2A6B78),
  background: Color(0xFF05182E),
  darkBackground: Color(0xFF031222),
  darkerBackground: Color(0xFF020C17),
  lighterBackground: Color(0xFF0A2540),
  foreground: Color(0xFFF6DCAC),
  darkForeground: Color(0xFF3F8F8A),
  lightForeground: Color(0xFFA7C9C6),
  brightForeground: Color(0xFFF6DCAC),
  red: Color(0xFFF85525),
  yellow: Color(0xFFE97B3C),
  orange: Color(0xFFFAA968),
  green: Color(0xFF028391),
  cyan: Color(0xFF8CBFB8),
  blue: Color(0xFF3F8F8A),
  magenta: Color(0xFF3F8F8A),
  brown: Color(0xFF743D1E),
  brightRed: Color(0xFFF85525),
  brightYellow: Color(0xFFE97B3C),
  brightGreen: Color(0xFF028391),
  brightCyan: Color(0xFF8CBFB8),
  brightBlue: Color(0xFFFAA968),
  brightMagenta: Color(0xFF3F8F8A),
  useOwnCellColors: false,
  useOwnPpo2Color: true,
);
```

`lib/ui/theme/omarchy/catppuccin.dart`:

```dart
import 'package:flutter/material.dart';

import 'omarchy_colors.dart';

/// Omarchy "Catppuccin" — themes/catppuccin/colors.toml, read 2026-10-06.
const OmarchyColors catppuccinColors = OmarchyColors(
  accent: Color(0xFF89B4FA),
  selection: Color(0xFF45475A),
  muted: Color(0xFF585B70),
  background: Color(0xFF1E1E2E),
  darkBackground: Color(0xFF161622),
  darkerBackground: Color(0xFF101019),
  lighterBackground: Color(0xFF313244),
  foreground: Color(0xFFCDD6F4),
  darkForeground: Color(0xFF6C7086),
  lightForeground: Color(0xFFBAC2DE),
  brightForeground: Color(0xFFCDD6F4),
  red: Color(0xFFF38BA8),
  yellow: Color(0xFFF9E2AF),
  orange: Color(0xFFF6B6AB),
  green: Color(0xFFA6E3A1),
  cyan: Color(0xFF94E2D5),
  blue: Color(0xFF89B4FA),
  magenta: Color(0xFFF5C2E7),
  brown: Color(0xFF7B5B55),
  brightRed: Color(0xFFF38BA8),
  brightYellow: Color(0xFFF9E2AF),
  brightGreen: Color(0xFFA6E3A1),
  brightCyan: Color(0xFF94E2D5),
  brightBlue: Color(0xFF89B4FA),
  brightMagenta: Color(0xFFF5C2E7),
  useOwnCellColors: true,
  useOwnPpo2Color: true,
);
```

`lib/ui/theme/omarchy/hackerman.dart`:

```dart
import 'package:flutter/material.dart';

import 'omarchy_colors.dart';

/// Omarchy "Hackerman" — themes/hackerman/colors.toml, read 2026-10-06.
/// Its "red", "yellow" and "orange" are all greens, and blue and magenta
/// are nearly identical, so cells keep the Wreck colours.
const OmarchyColors hackermanColors = OmarchyColors(
  accent: Color(0xFF82FB9C),
  selection: Color(0xFF1F253A),
  muted: Color(0xFF2D3450),
  background: Color(0xFF0B0C16),
  darkBackground: Color(0xFF080910),
  darkerBackground: Color(0xFF06060C),
  lighterBackground: Color(0xFF151828),
  foreground: Color(0xFFDDF7FF),
  darkForeground: Color(0xFF6A6E95),
  lightForeground: Color(0xFFB5C5DB),
  brightForeground: Color(0xFFDDF7FF),
  red: Color(0xFF50F872),
  yellow: Color(0xFF50F7D4),
  orange: Color(0xFF50F7A3),
  green: Color(0xFF4FE88F),
  cyan: Color(0xFF7CF8F7),
  blue: Color(0xFF829DD4),
  magenta: Color(0xFF86A7DF),
  brown: Color(0xFF287B51),
  brightRed: Color(0xFF85FF9D),
  brightYellow: Color(0xFFA4FFEC),
  brightGreen: Color(0xFF9CF7C2),
  brightCyan: Color(0xFFD1FFFE),
  brightBlue: Color(0xFFC4D2ED),
  brightMagenta: Color(0xFFCDDBF4),
  useOwnCellColors: false,
  useOwnPpo2Color: true,
);
```

`lib/ui/theme/omarchy/miasma.dart`:

```dart
import 'package:flutter/material.dart';

import 'omarchy_colors.dart';

/// Omarchy "Miasma" — themes/miasma/colors.toml, read 2026-10-06.
/// Green and blue (an olive) are too close, so cells keep the Wreck
/// colours. Its dark and light foregrounds are too dim for body text; the
/// mapping lifts them.
const OmarchyColors miasmaColors = OmarchyColors(
  accent: Color(0xFF78824B),
  selection: Color(0xFF383838),
  muted: Color(0xFF666666),
  background: Color(0xFF222222),
  darkBackground: Color(0xFF191919),
  darkerBackground: Color(0xFF121212),
  lighterBackground: Color(0xFF2C2C2C),
  foreground: Color(0xFFC2C2B0),
  darkForeground: Color(0xFF555555),
  lightForeground: Color(0xFF8A8A7E),
  brightForeground: Color(0xFFC2C2B0),
  red: Color(0xFF685742),
  yellow: Color(0xFFB36D43),
  orange: Color(0xFF8D6242),
  green: Color(0xFF5F875F),
  cyan: Color(0xFFC9A554),
  blue: Color(0xFF78824B),
  magenta: Color(0xFFBB7744),
  brown: Color(0xFF463121),
  brightRed: Color(0xFF685742),
  brightYellow: Color(0xFFB36D43),
  brightGreen: Color(0xFF5F875F),
  brightCyan: Color(0xFFC9A554),
  brightBlue: Color(0xFF78824B),
  brightMagenta: Color(0xFFBB7744),
  useOwnCellColors: false,
  useOwnPpo2Color: true,
);
```

- [ ] **Step 5: Create the mapping**

`lib/ui/theme/omarchy/omarchy_mapping.dart`:

```dart
// Turns an Omarchy theme's raw colours into the app's ThemePalette.
//
// Omarchy palettes are designed for terminals and window chrome, so two
// corrections happen here and nowhere else: text colours are lifted until
// they meet a contrast floor, and cell / PPO2 colours fall back to the
// Wreck values when the theme's own are not distinct enough.

import 'package:flutter/material.dart';

import '../color_math.dart';
import '../tokens.dart';
import 'omarchy_colors.dart';

/// Minimum WCAG contrast for primary and secondary text.
const double kMinTextContrast = 4.5;

/// Minimum WCAG contrast for muted text.
const double kMinMutedTextContrast = 3.0;

/// Minimum WCAG contrast for a cell or trace colour on a card.
const double kMinTraceContrast = 3.0;

/// Minimum CIEDE2000 difference between any two cell colours.
const double kMinCellDeltaE = 20;

/// Minimum CIEDE2000 difference between the PPO2 trace and the depth and
/// setpoint traces.
const double kMinPpo2DeltaE = 15;

/// Returns [color] if it has at least [minRatio] contrast against every
/// one of [backgrounds]; otherwise blends it toward [toward] in 5% steps
/// and returns the first blend that does. Returns [toward] if none does.
Color liftToContrast(
  Color color,
  Color toward,
  List<Color> backgrounds,
  double minRatio,
) {
  bool passes(Color c) =>
      backgrounds.every((bg) => contrastRatio(c, bg) >= minRatio);
  if (passes(color)) return color;
  for (var step = 1; step <= 20; step++) {
    final candidate = Color.lerp(color, toward, step * 0.05)!;
    if (passes(candidate)) return candidate;
  }
  return toward;
}

/// Whether three colours can serve as cell 1/2/3 on [card]: each readable
/// on the card, and each clearly different from the other two.
bool cellColorsPass(Color c1, Color c2, Color c3, Color card) {
  final cells = [c1, c2, c3];
  if (cells.any((c) => contrastRatio(c, card) < kMinTraceContrast)) {
    return false;
  }
  return deltaE2000(c1, c2) >= kMinCellDeltaE &&
      deltaE2000(c1, c3) >= kMinCellDeltaE &&
      deltaE2000(c2, c3) >= kMinCellDeltaE;
}

/// Whether [ppo2] can serve as the PPO2 trace on [card] next to the
/// [depth] and [setpoint] traces.
bool ppo2ColorPasses(Color ppo2, Color depth, Color setpoint, Color card) =>
    contrastRatio(ppo2, card) >= kMinTraceContrast &&
    deltaE2000(ppo2, depth) >= kMinPpo2DeltaE &&
    deltaE2000(ppo2, setpoint) >= kMinPpo2DeltaE;

ThemePalette paletteFromOmarchy(OmarchyColors o) {
  const wreck = AppColors.wreck;
  final surfaces = [o.background, o.lighterBackground];
  final textPrimary = o.foreground;
  final textSecondary = liftToContrast(
      o.lightForeground, o.foreground, surfaces, kMinTextContrast);
  final textMuted = liftToContrast(
      o.darkForeground, o.foreground, surfaces, kMinMutedTextContrast);
  final cell3 = o.useOwnCellColors ? o.magenta : wreck.cell3;

  return ThemePalette(
    surfaceBg: o.background,
    surfaceCard: o.lighterBackground,
    surfaceRaised: o.selection,
    surfaceBezel: o.muted,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    textInverse: o.background,
    accentPrimary: o.accent,
    accentMuted: Color.lerp(o.accent, o.background, 0.5)!,
    cell1: o.useOwnCellColors ? o.green : wreck.cell1,
    cell2: o.useOwnCellColors ? o.blue : wreck.cell2,
    cell3: cell3,
    chartGrid: Color.lerp(o.lighterBackground, o.selection, 0.5)!,
    chartTraceDepth: textPrimary,
    chartTracePpo2: o.useOwnPpo2Color ? o.yellow : wreck.chartTracePpo2,
    chartTraceSetpoint: textSecondary,
    chartTraceGf99: cell3,
  );
}
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/ui/theme/omarchy_mapping_test.dart`
Expected: PASS. If "stated choices are the ones the rules allow" fails for a theme, the flag in that theme's source file is wrong: fix the flag to match the rule, then update "expected outcome per theme" and the outcome table in the spec to match, and mention it in the commit message. Do not change a threshold to make a flag pass.

- [ ] **Step 7: Analyze and commit**

Run: `flutter analyze` — expected `No issues found!`

```bash
git add lib/ui/theme/omarchy test/ui/theme/omarchy_mapping_test.dart
git commit -m "feat(theme): Omarchy source palettes and mapping onto app tokens (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Theme registry

**Files:**
- Create: `lib/ui/theme/app_themes.dart`
- Test: `test/ui/theme/app_themes_test.dart`

**Interfaces:**
- Consumes: `paletteFromOmarchy`, the five `…Colors` constants, `cellColorsPass`, `ppo2ColorPasses`, the `kMin…` constants (Task 4); `AppTheme.build` (Task 3); `SafetyColors.all` (Task 2); `contrastRatio` (Task 1).
- Produces:
  - `class AppThemeDef { final String id; final String name; final ThemePalette palette; late final ThemeData themeData; }`
  - `AppThemes.defaultId` (`'wreck'`), `AppThemes.all` (`List<AppThemeDef>`, Wreck first), `AppThemes.byId(String? id)` (returns the Wreck entry for null or unknown).

- [ ] **Step 1: Write the failing test**

`test/ui/theme/app_themes_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:ccrlogger/ui/theme/omarchy/omarchy_mapping.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Safety colours known to fall short of 3:1 on a theme's card. See the
/// spec, "Known contrast shortfall". Keys are '<themeId>/<safetyName>'.
const _knownCardShortfalls = {
  'catppuccin/gfOverLimit',
  'miasma/gfOverLimit',
};

void main() {
  group('registry', () {
    test('lists the six themes, Wreck first', () {
      expect(AppThemes.all.map((t) => t.id), [
        'wreck',
        'ethereal',
        'retro82',
        'catppuccin',
        'hackerman',
        'miasma',
      ]);
      expect(AppThemes.all.map((t) => t.name), [
        'Wreck',
        'Ethereal',
        'Retro 82',
        'Catppuccin',
        'Hackerman',
        'Miasma',
      ]);
    });

    test('ids are unique', () {
      final ids = AppThemes.all.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('byId finds a theme and falls back to Wreck', () {
      expect(AppThemes.byId('miasma').name, 'Miasma');
      expect(AppThemes.byId(null).id, 'wreck');
      expect(AppThemes.byId('no-such-theme').id, 'wreck');
      expect(AppThemes.byId('').id, 'wreck');
      expect(AppThemes.defaultId, 'wreck');
    });

    test('Wreck is unchanged', () {
      final w = AppThemes.byId('wreck').palette;
      expect(w, same(AppColors.wreck));
      expect(w.surfaceBg, const Color(0xFF0A1518));
      expect(w.surfaceCard, const Color(0xFF142028));
      expect(w.surfaceRaised, const Color(0xFF1F2E38));
      expect(w.surfaceBezel, const Color(0xFF2A3A45));
      expect(w.textPrimary, const Color(0xFFE0E8EC));
      expect(w.textSecondary, const Color(0xFFA0AEB6));
      expect(w.textMuted, const Color(0xFF6B7D88));
      expect(w.textInverse, const Color(0xFF0A1518));
      expect(w.accentPrimary, const Color(0xFFC97B3A));
      expect(w.accentMuted, const Color(0xFF806633));
      expect(w.cell1, const Color(0xFF4ADE80));
      expect(w.cell2, const Color(0xFF60A5FA));
      expect(w.cell3, const Color(0xFFF472B6));
      expect(w.chartGrid, const Color(0xFF1A2832));
      expect(w.chartTraceDepth, const Color(0xFFE0E8EC));
      expect(w.chartTracePpo2, const Color(0xFFFFCC66));
      expect(w.chartTraceSetpoint, const Color(0xFFA0AEB6));
      expect(w.chartTraceGf99, const Color(0xFFF472B6));
    });

    test('themeData carries the palette and is built once', () {
      final t = AppThemes.byId('catppuccin');
      expect(t.themeData.extension<ThemePalette>(), same(t.palette));
      expect(t.themeData, same(t.themeData));
      expect(t.themeData.brightness, Brightness.dark);
    });
  });

  group('every registered theme', () {
    test('meets the text contrast floors', () {
      for (final t in AppThemes.all) {
        final p = t.palette;
        for (final bg in [p.surfaceBg, p.surfaceCard]) {
          expect(contrastRatio(p.textPrimary, bg),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${t.id} textPrimary');
          expect(contrastRatio(p.textSecondary, bg),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${t.id} textSecondary');
          expect(contrastRatio(p.textMuted, bg),
              greaterThanOrEqualTo(kMinMutedTextContrast),
              reason: '${t.id} textMuted');
        }
      }
    });

    test('ends up with cell and PPO2 colours that pass the rules', () {
      for (final t in AppThemes.all) {
        final p = t.palette;
        expect(cellColorsPass(p.cell1, p.cell2, p.cell3, p.surfaceCard),
            isTrue,
            reason: '${t.id} cells');
        expect(
            ppo2ColorPasses(p.chartTracePpo2, p.chartTraceDepth,
                p.chartTraceSetpoint, p.surfaceCard),
            isTrue,
            reason: '${t.id} ppo2');
      }
    });

    test('shows every safety colour readably on its background', () {
      for (final t in AppThemes.all) {
        SafetyColors.all.forEach((name, color) {
          expect(contrastRatio(color, t.palette.surfaceBg),
              greaterThanOrEqualTo(3.0),
              reason: '${t.id}/$name on background');
        });
      }
    });

    test('shows every safety colour readably on its card, bar known cases',
        () {
      for (final t in AppThemes.all) {
        SafetyColors.all.forEach((name, color) {
          final ratio = contrastRatio(color, t.palette.surfaceCard);
          final key = '${t.id}/$name';
          if (_knownCardShortfalls.contains(key)) {
            expect(ratio, greaterThanOrEqualTo(2.5), reason: '$key floor');
            expect(ratio, lessThan(3.0),
                reason: '$key no longer falls short: remove it from '
                    '_knownCardShortfalls');
          } else {
            expect(ratio, greaterThanOrEqualTo(3.0), reason: '$key on card');
          }
        });
      }
    });
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/theme/app_themes_test.dart`
Expected: FAIL to compile — `app_themes.dart` does not exist.

- [ ] **Step 3: Implement the registry**

`lib/ui/theme/app_themes.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'omarchy/catppuccin.dart';
import 'omarchy/ethereal.dart';
import 'omarchy/hackerman.dart';
import 'omarchy/miasma.dart';
import 'omarchy/omarchy_mapping.dart';
import 'omarchy/retro_82.dart';
import 'tokens.dart';

/// One selectable theme.
class AppThemeDef {
  AppThemeDef({required this.id, required this.name, required this.palette});

  /// Stable identifier, persisted in the user's settings. Never rename one
  /// without a migration: an unknown id silently resolves to Wreck.
  final String id;

  /// Name shown in the picker.
  final String name;

  final ThemePalette palette;

  /// Built on first use and reused, so re-selecting a theme hands
  /// MaterialApp the identical ThemeData.
  late final ThemeData themeData = AppTheme.build(palette);
}

/// The themes the user can pick. To add one: add its OmarchyColors file
/// under omarchy/ and one entry here. The tests in app_themes_test.dart
/// then check it automatically.
class AppThemes {
  AppThemes._();

  static const String defaultId = 'wreck';

  static final List<AppThemeDef> all = List.unmodifiable([
    AppThemeDef(id: defaultId, name: 'Wreck', palette: AppColors.wreck),
    AppThemeDef(
        id: 'ethereal',
        name: 'Ethereal',
        palette: paletteFromOmarchy(etherealColors)),
    AppThemeDef(
        id: 'retro82',
        name: 'Retro 82',
        palette: paletteFromOmarchy(retro82Colors)),
    AppThemeDef(
        id: 'catppuccin',
        name: 'Catppuccin',
        palette: paletteFromOmarchy(catppuccinColors)),
    AppThemeDef(
        id: 'hackerman',
        name: 'Hackerman',
        palette: paletteFromOmarchy(hackermanColors)),
    AppThemeDef(
        id: 'miasma',
        name: 'Miasma',
        palette: paletteFromOmarchy(miasmaColors)),
  ]);

  /// The theme with [id], or Wreck when [id] is null or not registered.
  static AppThemeDef byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/theme/app_themes_test.dart`
Expected: PASS. Two results need care if they fail:
- A safety colour below 3.0 on a card that is not in `_knownCardShortfalls`: stop and report it. Do not add it to the set; that needs a decision.
- A known shortfall now reports ≥ 3.0: remove it from the set, as the failure message says.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze` — expected `No issues found!`

```bash
git add lib/ui/theme/app_themes.dart test/ui/theme/app_themes_test.dart
git commit -m "feat(theme): theme registry with six themes and palette checks (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Theme setting and app wiring

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Create: `lib/ui/theme/active_theme_builder.dart`
- Modify: `lib/main.dart` (`CCRLogApp.build`, around line 186)
- Test: modify `test/ui/notifiers/settings_notifier_test.dart`; create `test/ui/theme/active_theme_builder_test.dart`

**Interfaces:**
- Consumes: `AppThemes.byId`, `AppThemes.defaultId`, `AppThemeDef.themeData` (Task 5).
- Produces:
  - `String SettingsNotifier.themeId` — always a registered id.
  - `Future<void> SettingsNotifier.setThemeId(String id)` — resolves unknown ids to Wreck, notifies listeners, persists under the key `app_theme`.
  - `ActiveThemeBuilder({required SettingsNotifier settings, required Widget Function(BuildContext, ThemeData, Widget?) builder, Widget? child})`.

- [ ] **Step 1: Write the failing settings tests**

Append inside `main()` of `test/ui/notifiers/settings_notifier_test.dart`:

```dart
  group('theme id', () {
    test('defaults to wreck when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.load();
      expect(n.themeId, 'wreck');
    });

    test('reads a stored id on load', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'catppuccin'});
      final n = SettingsNotifier();
      await n.load();
      expect(n.themeId, 'catppuccin');
    });

    test('an unknown stored id resolves to wreck', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'solarized'});
      final n = SettingsNotifier();
      await n.load();
      expect(n.themeId, 'wreck');
    });

    test('a stored value of the wrong type resolves to wreck, no throw',
        () async {
      SharedPreferences.setMockInitialValues({'app_theme': 42});
      final n = SettingsNotifier();
      await n.load();
      expect(n.themeId, 'wreck');
    });

    test('setThemeId persists across a reload and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final n1 = SettingsNotifier();
      await n1.load();
      var notified = 0;
      n1.addListener(() => notified++);
      await n1.setThemeId('hackerman');
      expect(n1.themeId, 'hackerman');
      expect(notified, 1);

      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.themeId, 'hackerman');
    });

    test('setThemeId with the current id does not notify', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'miasma'});
      final n = SettingsNotifier();
      await n.load();
      var notified = 0;
      n.addListener(() => notified++);
      await n.setThemeId('miasma');
      expect(notified, 0);
    });

    test('setThemeId with an unknown id stores wreck', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'ethereal'});
      final n = SettingsNotifier();
      await n.load();
      await n.setThemeId('no-such-theme');
      expect(n.themeId, 'wreck');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme'), 'wreck');
    });
  });
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: FAIL to compile — `themeId` and `setThemeId` are undefined.

- [ ] **Step 3: Add the setting**

In `lib/ui/notifiers/settings_notifier.dart`:

Add the import `import '../theme/app_themes.dart';` with the other relative imports.

Add with the other keys at the top of the class:

```dart
  static const _kThemeId = 'app_theme';
```

Add with the other private fields:

```dart
  String _themeId = AppThemes.defaultId;
```

Add with the other getters:

```dart
  /// Id of the selected theme. Always a registered id.
  String get themeId => _themeId;
```

Add at the end of `load()`, before its closing brace:

```dart
    // `get` rather than `getString`: a value of the wrong type must fall
    // back to the default, not throw before the first frame.
    final storedTheme = prefs.get(_kThemeId);
    _themeId = AppThemes.byId(storedTheme is String ? storedTheme : null).id;
```

Add next to the other setters:

```dart
  Future<void> setThemeId(String id) async {
    final resolved = AppThemes.byId(id).id;
    if (_themeId == resolved) return;
    _themeId = resolved;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeId, resolved);
  }
```

- [ ] **Step 4: Run the settings tests**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing `ActiveThemeBuilder` test**

`test/ui/theme/active_theme_builder_test.dart`:

```dart
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/theme/active_theme_builder.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(SettingsNotifier settings, void Function(ThemePalette) onSeen) {
    return ActiveThemeBuilder(
      settings: settings,
      child: Builder(builder: (context) {
        onSeen(context.palette);
        return const SizedBox();
      }),
      builder: (context, theme, child) =>
          MaterialApp(theme: theme, home: child),
    );
  }

  testWidgets('starts in the stored theme', (tester) async {
    SharedPreferences.setMockInitialValues({'app_theme': 'ethereal'});
    final settings = SettingsNotifier();
    await settings.load();
    late ThemePalette seen;
    await tester.pumpWidget(app(settings, (p) => seen = p));
    expect(seen, same(AppThemes.byId('ethereal').palette));
  });

  testWidgets('switches when the setting changes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsNotifier();
    await settings.load();
    late ThemePalette seen;
    await tester.pumpWidget(app(settings, (p) => seen = p));
    expect(seen, same(AppColors.wreck));

    await settings.setThemeId('catppuccin');
    await tester.pumpAndSettle();
    expect(seen.surfaceBg, AppThemes.byId('catppuccin').palette.surfaceBg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hands MaterialApp the registry ThemeData', (tester) async {
    SharedPreferences.setMockInitialValues({'app_theme': 'miasma'});
    final settings = SettingsNotifier();
    await settings.load();
    await tester.pumpWidget(app(settings, (_) {}));
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme, same(AppThemes.byId('miasma').themeData));
  });
}
```

- [ ] **Step 6: Run and confirm failure**

Run: `flutter test test/ui/theme/active_theme_builder_test.dart`
Expected: FAIL to compile — `active_theme_builder.dart` does not exist.

- [ ] **Step 7: Implement `ActiveThemeBuilder`**

`lib/ui/theme/active_theme_builder.dart`:

```dart
import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';
import 'app_themes.dart';

/// Rebuilds with the ThemeData of the theme selected in [settings].
///
/// Wrap MaterialApp in this and pass the result as its `theme`. Put the
/// app's home in [child] so it is not rebuilt each time a setting changes.
class ActiveThemeBuilder extends StatelessWidget {
  const ActiveThemeBuilder({
    super.key,
    required this.settings,
    required this.builder,
    this.child,
  });

  final SettingsNotifier settings;
  final Widget Function(BuildContext context, ThemeData theme, Widget? child)
      builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      child: child,
      builder: (context, child) => builder(
        context,
        AppThemes.byId(settings.themeId).themeData,
        child,
      ),
    );
  }
}
```

- [ ] **Step 8: Run the test**

Run: `flutter test test/ui/theme/active_theme_builder_test.dart`
Expected: PASS.

- [ ] **Step 9: Wire it into the app**

In `lib/main.dart`, in `CCRLogApp.build`, the method currently returns `MaterialApp(title: 'Anchorline', theme: AppTheme.dark(), home: AppShell(…), debugShowCheckedModeBanner: false)`. Change it so the existing `AppShell(…)` expression, with all its arguments unchanged, becomes the `child`:

```dart
  @override
  Widget build(BuildContext context) {
    return ActiveThemeBuilder(
      settings: settings,
      child: AppShell(
        // ← the existing AppShell arguments, unchanged
      ),
      builder: (context, theme, home) => MaterialApp(
        title: 'Anchorline',
        theme: theme,
        home: home,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
```

Replace the import `import 'ui/theme/app_theme.dart';` with `import 'ui/theme/active_theme_builder.dart';` (keeping the import list's alphabetical position).

- [ ] **Step 10: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui/notifiers/settings_notifier.dart lib/ui/theme/active_theme_builder.dart lib/main.dart test/ui
git commit -m "feat(theme): persist the theme choice and drive MaterialApp from it (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Move widget call sites onto the active palette

Every remaining `AppColors.wreck` read in screens and plain widgets. Charts are Task 8.

**Files:**
- Modify: `lib/ui/screens/blend_screen.dart`, `lib/ui/screens/dive_plan_screen.dart`, `lib/ui/screens/dive_detail_screen.dart`, `lib/ui/screens/sites_map_screen.dart`, `lib/ui/dev/widgetbook_screen.dart`, `lib/ui/widgets/bailout_section.dart`, `lib/ui/widgets/dive_information_section.dart`, `lib/ui/widgets/dive_annotations_section.dart`, `lib/ui/widgets/stop_ladder_table.dart`, `lib/ui/widgets/dive_tile.dart`
- Test: create `test/ui/theme/no_direct_palette_test.dart`

**Interfaces:**
- Consumes: `context.palette` (Task 3).
- Produces: no direct `AppColors.wreck` reads in the files above.

- [ ] **Step 1: Write the failing guard test**

`test/ui/theme/no_direct_palette_test.dart`:

```dart
// Guards the theme system: UI code must read colours from the active
// theme (context.palette), never from the Wreck palette directly, or it
// will not follow the user's theme choice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to name AppColors.wreck: the theme layer itself.
bool _allowed(String path) => path.startsWith('lib/ui/theme/');

/// Chart files, migrated in a later step of this work. Emptied in Task 8.
const _pendingCharts = <String>{
  'lib/ui/widgets/profile_chart.dart',
  'lib/ui/widgets/cell_data_chart.dart',
  'lib/ui/widgets/cell_mv_chart.dart',
};

void main() {
  test('no UI code reads AppColors.wreck directly', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowed(path) || _pendingCharts.contains(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('AppColors.wreck')) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.palette instead:\n${offenders.join('\n')}');
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/theme/no_direct_palette_test.dart`
Expected: FAIL, listing every remaining `AppColors.wreck` line outside the theme folder and the three chart files. This list is the work list for the next step.

- [ ] **Step 3: Migrate each listed line**

Apply these rules, file by file. Run `flutter analyze` after each file.

1. **A `BuildContext` is in scope** (inside `build`, a `Builder`, or a method that takes `context`): replace `AppColors.wreck.<token>` with `context.palette.<token>`.
2. **A local alias** `const palette = AppColors.wreck;` (three places in `dive_detail_screen.dart`): replace with `final palette = context.palette;`. Uses of `palette.<token>` below it stay as they are.
3. **Inside a `const` expression** (the analyzer reports "Invalid constant value" or "Arguments of a constant creation must be constant expressions"): remove `const` from the nearest enclosing constructor call that contains the palette read. If the analyzer then hints `prefer_const_constructors` on sibling or child widgets that are still constant, add `const` to those.
4. **No `BuildContext` in scope** (a private helper method, a top-level function, a field initialiser, a default parameter value): do not reach for a global. Add a `ThemePalette palette` parameter to the helper and pass `context.palette` from the caller in `build`. For a field initialiser or default parameter value, make the value nullable and resolve it in `build` with `?? context.palette.<token>`.
5. **A comment or doc comment** that names `AppColors.wreck.<token>`: reword to "the theme's `<token>`".
6. After editing a file, if `AppColors` is no longer referenced but `context.palette` is, the `tokens.dart` import stays (the extension lives there).

Do not change any `Color(0x…)` literal or `Colors.*` use in these files. That is stage 2.

- [ ] **Step 4: Run the guard test**

Run: `flutter test test/ui/theme/no_direct_palette_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass. Existing widget tests pump a bare `MaterialApp` or `AppTheme.dark()`; both resolve `context.palette` to Wreck, so their expectations hold.

```bash
git add lib test/ui/theme/no_direct_palette_test.dart
git commit -m "refactor(theme): screens and widgets read the active palette (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Charts follow the theme

**Files:**
- Modify: `lib/ui/widgets/profile_chart.dart`
- Modify: `lib/ui/widgets/cell_data_chart.dart`
- Modify: `lib/ui/widgets/cell_mv_chart.dart`
- Modify: `test/ui/theme/no_direct_palette_test.dart` (empty `_pendingCharts`)
- Test: modify `test/ui/widgets/profile_chart_test.dart`

**Interfaces:**
- Consumes: `ThemePalette`, `context.palette`, `AppColors.wreck` (Task 3); `SafetyColors` (Task 2); `AppThemes` (Task 5).
- Produces: `ProfileChartPainter` gains `final ThemePalette palette` (constructor parameter `this.palette = AppColors.wreck`, so existing callers compile) and repaints when it changes.

- [ ] **Step 1: Write the failing tests**

In `test/ui/widgets/profile_chart_test.dart`, add the imports

```dart
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
```

and add these two tests directly after the existing `test('shouldRepaint detects changes', …)`:

```dart
  test('shouldRepaint detects a palette change', () {
    final samples = _loadSamples();
    final wreck = ProfileChartPainter(
        samples: samples,
        visibleTraces: {TraceType.ppo2},
        crosshairIndex: null);
    final catppuccin = ProfileChartPainter(
        samples: samples,
        visibleTraces: {TraceType.ppo2},
        crosshairIndex: null,
        palette: AppThemes.byId('catppuccin').palette);
    expect(wreck.palette, same(AppColors.wreck));
    expect(wreck.shouldRepaint(catppuccin), isTrue);
    expect(catppuccin.shouldRepaint(catppuccin), isFalse);
  });

  testWidgets('ProfileChart hands the active palette to its painter',
      (tester) async {
    final samples = _loadSamples();
    final theme = AppThemes.byId('ethereal');
    await tester.pumpWidget(MaterialApp(
        theme: theme.themeData,
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 300,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {TraceType.ppo2},
                    crosshairIndex: null)))));

    final painters = tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byType(ProfileChart), matching: find.byType(CustomPaint)))
        .map((c) => c.painter)
        .whereType<ProfileChartPainter>()
        .toList();
    expect(painters, hasLength(1));
    expect(painters.single.palette, same(theme.palette));
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/widgets/profile_chart_test.dart`
Expected: FAIL to compile — `ProfileChartPainter` has no `palette`.

- [ ] **Step 3: `profile_chart.dart` — painter takes the palette**

1. Delete these seven top-level declarations and the comment block above them that says the colours are sourced from `AppColors.wreck`:

```dart
final Color _depthColor = AppColors.wreck.chartTraceDepth;
final Color _ppo2Color = AppColors.wreck.chartTracePpo2;
final Color _setpointColor = AppColors.wreck.chartTraceSetpoint;
final Color _cell0Color = AppColors.wreck.cell1;
final Color _cell1Color = AppColors.wreck.cell2;
final Color _cell2Color = AppColors.wreck.cell3;
final Color _gridColor = AppColors.wreck.chartGrid;
```

   Keep `_decoColor`, `_gasChangeColor`, `_bailoutColor` (constants since Task 2), `_crosshairColor` and every other literal.

2. Delete `final Color _vSpeedStableColor = _depthColor;` and replace the top-level `_vSpeedAnchors` list with a function that takes the stable colour:

```dart
// Anchor table sorted by speed ascending. _colorForRate finds the bracket
// containing the segment's signed rate and lerps between the two anchors.
// [stable] is the theme's depth-trace colour, so a calm dive looks like a
// plain depth trace.
List<({double speed, Color color})> _vSpeedAnchorsFor(Color stable) => [
      (speed: -30.0, color: _vSpeedCrazyColor),
      (speed: -18.2, color: _vSpeedCrazyColor),
      (speed: -9.1, color: _vSpeedFastColor),
      (speed: -4.6, color: _vSpeedModerateColor),
      (speed: -1.5, color: _vSpeedSlowColor),
      (speed: 0.0, color: stable),
      (speed: 1.5, color: _vSpeedSlowColor),
      (speed: 9.1, color: _vSpeedModerateColor),
      (speed: 18.2, color: _vSpeedFastColor),
      (speed: 30.4, color: _vSpeedCrazyColor),
      (speed: 60.0, color: _vSpeedCrazyColor),
    ];
```

3. In `ProfileChartPainter`, add the field and constructor parameter:

```dart
  /// Colours for the themed traces and grid.
  final ThemePalette palette;
```

   and in the constructor's parameter list, after `this.viewEnd = 1.0,`:

```dart
    this.palette = AppColors.wreck,
```

4. In `shouldRepaint`, add as the first condition:

```dart
    return !identical(old.palette, palette) ||
        old.crosshairIndex != crosshairIndex ||
```

5. Inside the painter, replace each use of a deleted name:

| Deleted name | Replacement inside `ProfileChartPainter` |
|---|---|
| `_depthColor` | `palette.chartTraceDepth` |
| `_ppo2Color` | `palette.chartTracePpo2` |
| `_setpointColor` | `palette.chartTraceSetpoint` |
| `_cell0Color` | `palette.cell1` |
| `_cell1Color` | `palette.cell2` |
| `_cell2Color` | `palette.cell3` |
| `_gridColor` | `palette.chartGrid` |
| `_vSpeedStableColor` | `palette.chartTraceDepth` |

6. In `_colorForRate`, add as its first line `final anchors = _vSpeedAnchorsFor(palette.chartTraceDepth);` and replace every `_vSpeedAnchors` in that method with `anchors`.

7. In `ProfileChart.build`, pass the palette where the painter is constructed (around line 296): add `palette: context.palette,` to the `ProfileChartPainter(` arguments.

8. In `_CellLegend.build`, replace `final colors = [_cell0Color, _cell1Color, _cell2Color];` with:

```dart
    final palette = context.palette;
    final colors = [palette.cell1, palette.cell2, palette.cell3];
```

9. Update the doc comment on `useSpeedColoredGraph` that mentions `[_depthColor]` to say "the theme's depth-trace colour".

- [ ] **Step 4: Run the profile chart tests**

Run: `flutter test test/ui/widgets/profile_chart_test.dart`
Expected: PASS (new and existing).

- [ ] **Step 5: `cell_data_chart.dart`**

In the widget's `build`, replace the block of direct reads with:

```dart
    final palette = context.palette;
    final cell0 = palette.cell1;
    final cell1 = palette.cell2;
    final cell2 = palette.cell3;
    final ppo2Color = palette.chartTracePpo2;
    final setpointColor = palette.chartTraceSetpoint;
```

and where `_CellDataPainter(` is constructed, change `gridColor: AppColors.wreck.chartGrid,` to `gridColor: palette.chartGrid,`.

The painter already receives its colours as fields but ignores them in `shouldRepaint`. Replace that method with:

```dart
  @override
  bool shouldRepaint(covariant _CellDataPainter old) =>
      !identical(old.samples, samples) ||
      old.cal0 != cal0 ||
      old.cal1 != cal1 ||
      old.cal2 != cal2 ||
      old.cell0Color != cell0Color ||
      old.cell1Color != cell1Color ||
      old.cell2Color != cell2Color ||
      old.ppo2Color != ppo2Color ||
      old.setpointColor != setpointColor ||
      old.gridColor != gridColor;
```

- [ ] **Step 6: `cell_mv_chart.dart`**

`_ChartPainter` already receives `theme` and repaints when it changes. Replace its six static colour constants

```dart
  static const _gridColor = Color(0xFF1A2832); // AppColors.wreck.chartGrid
  static const _axisLabel = Color(0xFFA0AEB6); // AppColors.wreck.textSecondary
  static const _healthyColor = Color(0xFF4ADE80); // AppColors.wreck.statusSuccess
  static const _watchColor = Color(0xFFF39C12); // AppColors.wreck.statusWarning
  static const _replaceColor = Color(0xFFE74C3C); // AppColors.wreck.statusDanger
  static const _pillBg = Color(0xCC0A1518); // AppColors.wreck.surfaceBg @ ~80%
```

with

```dart
  ThemePalette get _palette =>
      theme.extension<ThemePalette>() ?? AppColors.wreck;
  Color get _gridColor => _palette.chartGrid;
  Color get _axisLabel => _palette.textSecondary;
  Color get _pillBg => _palette.surfaceBg.withValues(alpha: 0.8);
  static const _healthyColor = SafetyColors.success;
  static const _watchColor = SafetyColors.warning;
  static const _replaceColor = SafetyColors.danger;
```

Add `import '../theme/safety_colors.dart';` and, if not already imported, `import '../theme/tokens.dart';`. If the analyzer reports a `const` expression that used `_gridColor`, `_axisLabel` or `_pillBg` (for example a `const TextStyle(color: _axisLabel, …)`), remove that `const`. If a `static` field is built from one of them, turn that field into an instance getter (`TextStyle get _labelStyle => TextStyle(color: _axisLabel, …);`), since the colours now depend on the painter's theme.

- [ ] **Step 7: Close the guard**

In `test/ui/theme/no_direct_palette_test.dart`, delete the `_pendingCharts` constant and its doc comment, and change the skip line to:

```dart
      if (_allowed(path)) continue;
```

- [ ] **Step 8: Run chart and guard tests**

Run: `flutter test test/ui/widgets/profile_chart_test.dart test/ui/widgets/cell_data_chart_test.dart test/ui/widgets/cell_mv_chart_test.dart test/ui/theme/no_direct_palette_test.dart`
Expected: PASS.

- [ ] **Step 9: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui/widgets test/ui
git commit -m "feat(theme): profile and cell charts follow the active palette (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Theme picker (debug builds only)

**Files:**
- Create: `lib/ui/widgets/theme_picker.dart`
- Modify: `lib/ui/screens/settings_screen.dart`
- Test: create `test/ui/widgets/theme_picker_test.dart`; modify `test/ui/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: `AppThemes.all`, `AppThemeDef` (Task 5); `SettingsNotifier.themeId`, `setThemeId` (Task 6).
- Produces:
  - `ThemePicker({required SettingsNotifier notifier})` — one row per theme with key `ValueKey('theme-<id>')`; the active row shows `Icons.check`.
  - `SettingsScreen` gains `final bool showThemePicker` (constructor parameter `this.showThemePicker = kDebugMode`).

- [ ] **Step 1: Write the failing picker test**

`test/ui/widgets/theme_picker_test.dart`:

```dart
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/widgets/theme_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsNotifier> pump(WidgetTester tester,
      {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final settings = SettingsNotifier();
    await settings.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ThemePicker(notifier: settings)),
      ),
    ));
    return settings;
  }

  Finder checkIn(String id) => find.descendant(
      of: find.byKey(ValueKey('theme-$id')), matching: find.byIcon(Icons.check));

  testWidgets('lists every registered theme by name', (tester) async {
    await pump(tester);
    for (final t in AppThemes.all) {
      expect(find.byKey(ValueKey('theme-${t.id}')), findsOneWidget);
      expect(find.text(t.name), findsOneWidget);
    }
  });

  testWidgets('marks only the active theme', (tester) async {
    await pump(tester, prefs: {'app_theme': 'retro82'});
    expect(checkIn('retro82'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tapping a row selects that theme and moves the mark',
      (tester) async {
    final settings = await pump(tester);
    expect(checkIn('wreck'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme-hackerman')));
    await tester.pumpAndSettle();

    expect(settings.themeId, 'hackerman');
    expect(checkIn('hackerman'), findsOneWidget);
    expect(checkIn('wreck'), findsNothing);
  });

  testWidgets('each row shows four swatches from its own palette',
      (tester) async {
    await pump(tester);
    final palette = AppThemes.byId('catppuccin').palette;
    final swatchColors = tester
        .widgetList<Container>(find.descendant(
            of: find.byKey(const ValueKey('theme-catppuccin')),
            matching: find.byKey(const ValueKey('theme-swatch'))))
        .map((c) => (c.decoration! as BoxDecoration).color)
        .toList();
    expect(swatchColors, [
      palette.surfaceBg,
      palette.surfaceCard,
      palette.textPrimary,
      palette.accentPrimary,
    ]);
  });
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/ui/widgets/theme_picker_test.dart`
Expected: FAIL to compile — `theme_picker.dart` does not exist.

- [ ] **Step 3: Implement the picker**

`lib/ui/widgets/theme_picker.dart`:

```dart
import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';
import '../theme/app_themes.dart';
import '../theme/tokens.dart';

/// One row per available theme: name, a strip of four swatches from that
/// theme, and a check mark on the active one. Tapping a row applies it.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.notifier});

  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final theme in AppThemes.all)
            ListTile(
              key: ValueKey('theme-${theme.id}'),
              title: Text(theme.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: _SwatchStrip(palette: theme.palette),
              ),
              trailing: theme.id == notifier.themeId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => notifier.setThemeId(theme.id),
            ),
        ],
      ),
    );
  }
}

class _SwatchStrip extends StatelessWidget {
  const _SwatchStrip({required this.palette});

  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = [
      palette.surfaceBg,
      palette.surfaceCard,
      palette.textPrimary,
      palette.accentPrimary,
    ];
    return Row(
      children: [
        for (final color in colors)
          Padding(
            padding: const EdgeInsets.only(right: Spacing.xs),
            child: Container(
              key: const ValueKey('theme-swatch'),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: Radii.chipBr,
                // Outline in the ambient theme so a swatch matching the
                // current background is still visible.
                border: Border.all(color: context.palette.surfaceBezel),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the picker test**

Run: `flutter test test/ui/widgets/theme_picker_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing settings-screen tests**

In `test/ui/screens/settings_screen_test.dart`, add the import `import 'package:ccrlogger/ui/widgets/theme_picker.dart';` and append inside `main()`:

```dart
  testWidgets('shows the Appearance section when showThemePicker is true',
      (tester) async {
    final h = await _build(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          notifier: h.settings, authService: h.auth, showThemePicker: true),
    ));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(ThemePicker), findsOneWidget);
  });

  testWidgets('hides the Appearance section when showThemePicker is false',
      (tester) async {
    final h = await _build(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          notifier: h.settings, authService: h.auth, showThemePicker: false),
    ));
    expect(find.text('Appearance'), findsNothing);
    expect(find.byType(ThemePicker), findsNothing);
  });
```

- [ ] **Step 6: Run and confirm failure**

Run: `flutter test test/ui/screens/settings_screen_test.dart`
Expected: FAIL to compile — `showThemePicker` is not a parameter.

- [ ] **Step 7: Add the section to Settings**

In `lib/ui/screens/settings_screen.dart`:

Add the imports `import 'package:flutter/foundation.dart';` (with the other `package:flutter` imports; it provides `kDebugMode`) and `import '../widgets/theme_picker.dart';` (after `'../widgets/subsurface_sync_section.dart'`).

Add to the `SettingsScreen` fields, after `subsurfaceBootstrapImporter`:

```dart
  /// Whether to show the theme picker. Debug builds only for now: until
  /// the loose colour literals are swept (stage 2), non-default themes
  /// look half-applied.
  final bool showThemePicker;
```

and to the constructor, after `this.subsurfaceBootstrapImporter,`:

```dart
    this.showThemePicker = kDebugMode,
```

In the `ListView` children in `_SettingsScreenState.build`, insert directly before the `SwitchListTile` titled `'Use speed coloured graph'`:

```dart
          if (widget.showThemePicker) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ThemePicker(notifier: widget.notifier),
            const Divider(height: 32),
          ],
```

- [ ] **Step 8: Run settings tests**

Run: `flutter test test/ui/screens/settings_screen_test.dart test/ui/screens/settings_screen_sync_status_test.dart`
Expected: PASS. If an existing test now fails because a widget it taps has scrolled off-screen (the picker adds six rows above it in debug-mode test runs), fix that test by pumping `SettingsScreen(…, showThemePicker: false)` in its helper; do not change the production default.

- [ ] **Step 9: Analyze, full suite, commit**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.

```bash
git add lib/ui/widgets/theme_picker.dart lib/ui/screens/settings_screen.dart test/ui
git commit -m "feat(theme): theme picker in Settings, debug builds only (#93)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Verify and open the PR

**Files:** none (verification only).

- [ ] **Step 1: Final automated checks**

Run: `flutter analyze` — expected `No issues found!`
Run: `flutter test` — expected: all pass.
Run: `grep -rn "AppColors\.wreck" lib --include='*.dart' | grep -v "lib/ui/theme/"` — expected: no output.
Run: `git diff main --stat -- pubspec.yaml pubspec.lock` — expected: no output (no dependency changes).

- [ ] **Step 2: Debug build for the manual check**

Run: `flutter run -d macos` (debug, so the picker is visible).

Hand over to the user for the look-through. For each of the six themes, picked in Settings → Appearance:
- the dive list;
- a CCR dive detail: profile chart with PPO2, setpoint and cells visible, and the cell data chart;
- the planner and the blend screen;
- Settings itself.

What to look for: the theme switches immediately without a restart; charts recolour without needing a tap; warnings and GF readouts look the same in every theme; restarting the app keeps the chosen theme. Areas that still look like Wreck are expected where colours are loose literals (stage 2); note them for the stage 2 issue.

- [ ] **Step 3: Release build hides the picker**

Run: `flutter build macos --release`, open `build/macos/Build/Products/Release/Anchorline.app`, and confirm Settings has no "Appearance" section. The theme chosen in the debug run stays applied, since the stored setting is shared; set it back to Wreck in a debug run afterwards if wanted.

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin feat/93-theming-stage-1
gh pr create --title "feat(theme): selectable themes, stage 1 — theme system, Omarchy palettes, debug-only picker (#93)" --body "Closes #93.

Implements stage 1 of docs/superpowers/specs/2026-10-06-theming-design.md.

- ThemePalette is a ThemeExtension; widgets read context.palette.
- Six themes: Wreck (default, unchanged) plus Omarchy's Ethereal, Retro 82, Catppuccin, Hackerman, Miasma.
- Status and GF colours are fixed across themes (SafetyColors).
- The theme choice is stored per device.
- The picker is visible in debug builds only until stage 2 sweeps the loose colour literals.

Known and accepted: GF-over-100 red is below 3:1 on the Catppuccin (2.6) and Miasma (2.9) card colours; recorded as named exceptions in app_themes_test.dart.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 5: File the stage 2 issue**

```bash
gh issue create --title "feat(theme): selectable themes, stage 2 — sweep loose colour literals, make the picker visible" --label enhancement --body "Follow-up to #93. See 'Stage 2' in docs/superpowers/specs/2026-10-06-theming-design.md: sort every Color(0x…) literal and Colors.* use outside lib/ui/theme/ into safety / chrome / data-encoding / neutral, add the guard test, then remove the kDebugMode gate on the theme picker."
```
