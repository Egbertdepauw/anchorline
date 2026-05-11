# Tech Dive design system — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Wreck-palette dark-mode design system: tokens (colour / type / spacing / radius / elevation / motion), a component library (`AppCard`, `StatTile`, `NumericReadout`, `SectionHeader`, `DataRow`, `AccentButton`, `GhostButton`, `IconChip`, `StatusDot`, `BezelPanel`), a dev-only Widgetbook screen, and a Dive Detail showcase refactor that consumes the new components.

**Architecture:** All visual decisions live in `lib/ui/theme/tokens.dart` (pure constants) consumed by a rewritten `lib/ui/theme/app_theme.dart` that builds Flutter's `ThemeData`. The component library in `lib/ui/components/` is built ON TOP of `ThemeData` — components read from `Theme.of(context)` rather than tokens directly so the same widgets work for a future light-mode palette without touching their code. Goldens lock in the visual baseline; existing widget tests assert on labels so they continue passing.

**Tech Stack:** Flutter, Dart, `google_fonts` style vendored TTFs (Inter + JetBrains Mono variable fonts), Material 3 ThemeData.

**Reference spec:** `docs/superpowers/specs/2026-05-11-tech-dive-design-system-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `fonts/Inter-VariableFont_opsz,wght.ttf` | Create (vendor) | Body font, all weights via variable axis |
| `fonts/JetBrainsMono-VariableFont_wght.ttf` | Create (vendor) | Numeric readouts, tabular figures |
| `pubspec.yaml` | Modify | Declare both fonts under `flutter.fonts` |
| `lib/ui/theme/tokens.dart` | Create | Pure constants: `AppColors`, `AppTypography`, `Spacing`, `Radii`, `Elevation`, `Motion`, `ThemePalette` |
| `lib/ui/theme/app_theme.dart` | Rewrite | Build `ThemeData.dark()` from tokens; pin TextTheme, AppBar, Card, Button, BottomNav, Chip themes |
| `lib/ui/components/app_card.dart` | Create | Hard-edge 2px card, surface.card background, optional bezel |
| `lib/ui/components/bezel_panel.dart` | Create | Bezel outline only, no fill — wraps charts/instruments |
| `lib/ui/components/status_dot.dart` | Create | 8px coloured circle for cell/sync/dive status |
| `lib/ui/components/numeric_readout.dart` | Create | JetBrains Mono with tabular figures, sizes sm/md/lg |
| `lib/ui/components/stat_tile.dart` | Create | Label above NumericReadout below; row member |
| `lib/ui/components/section_header.dart` | Create | Uppercase 11px label, replaces ad-hoc headers |
| `lib/ui/components/data_row.dart` | Create | Label + value display-only row (lifts Information-tab pattern) |
| `lib/ui/components/accent_button.dart` | Create | Hard-edge filled primary action |
| `lib/ui/components/ghost_button.dart` | Create | Outlined secondary action |
| `lib/ui/components/icon_chip.dart` | Create | Icon + label chip for status/filter |
| `lib/ui/dev/widgetbook_screen.dart` | Create | Long-list preview of every component in every state |
| `lib/ui/screens/settings_screen.dart` | Modify | Long-press on app version label opens Widgetbook |
| `lib/ui/screens/dive_detail_screen.dart` | Modify | Replace `_statCell`/`_avgMinMaxCell` with `StatTile` + `NumericReadout`; chart palette uses tokens; section headers use `SectionHeader` |
| `lib/ui/widgets/profile_chart.dart` | Modify | Reads colours from tokens instead of hex literals |
| `lib/ui/widgets/dive_information_section.dart` | Modify (light) | Replace inline `_readOnlyRow` with `DataRow` import |
| `test/ui/components/*_golden_test.dart` | Create | Golden baseline for each component |
| `test/ui/components/*_test.dart` | Create | Widget tests for `StatTile`, `NumericReadout`, `DataRow` (the ones with variants/logic) |
| `test/ui/dev/widgetbook_screen_test.dart` | Create | Smoke test: route renders without crashing |

---

## Task 1: Vendor fonts + pubspec declaration

Both fonts are variable TTFs under SIL OFL. Vendor them so the app needs no network at first launch.

**Files:**
- Create: `fonts/Inter-VariableFont_opsz,wght.ttf`
- Create: `fonts/JetBrainsMono-VariableFont_wght.ttf`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Download the variable fonts**

```bash
mkdir -p fonts
curl -L -o fonts/Inter-VariableFont.ttf \
  'https://github.com/rsms/inter/raw/master/docs/font-files/InterVariable.ttf'
curl -L -o fonts/JetBrainsMono-VariableFont.ttf \
  'https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/variable/JetBrainsMono%5Bwght%5D.ttf'
ls -lh fonts/
```
Expected: two files, each ~150–800 KB. Verify the file command identifies them as TrueType.

- [ ] **Step 2: Add the font declarations to `pubspec.yaml`**

Open `pubspec.yaml`, find the `flutter:` block, add to or create the `fonts:` section:

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: Inter
      fonts:
        - asset: fonts/Inter-VariableFont.ttf
    - family: JetBrainsMono
      fonts:
        - asset: fonts/JetBrainsMono-VariableFont.ttf
```

Preserve any existing `assets:` block and other `flutter:` keys.

- [ ] **Step 3: Verify the package picks them up**

```bash
flutter pub get
flutter analyze
```
Expected: pub get completes, analyze stays at 0 issues.

- [ ] **Step 4: Commit**

```bash
git add fonts/ pubspec.yaml
git commit -m "$(cat <<'EOF'
chore(fonts): vendor Inter + JetBrains Mono variable fonts

Inter for body text, JetBrains Mono for numeric readouts (tabular
figures). Variable fonts so all weights ship in a single TTF each;
no runtime download needed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Token foundation — `lib/ui/theme/tokens.dart`

Pure-Dart constants and helpers. No Flutter widgets. Every visual decision in one file so the design system is auditable at a glance.

**Files:**
- Create: `lib/ui/theme/tokens.dart`
- Test: `test/ui/theme/tokens_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/ui/theme/tokens_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors.wreck', () {
    test('surface.bg matches spec', () {
      expect(AppColors.wreck.surfaceBg, const Color(0xFF0A1518));
    });
    test('accent.primary matches sodium-vapor', () {
      expect(AppColors.wreck.accentPrimary, const Color(0xFFFFCC66));
    });
    test('cell colours are locked', () {
      expect(AppColors.wreck.cell1, const Color(0xFF4ADE80));
      expect(AppColors.wreck.cell2, const Color(0xFF60A5FA));
      expect(AppColors.wreck.cell3, const Color(0xFFF472B6));
    });
  });

  group('Spacing', () {
    test('scale is 4/8/12/16/24/32/48', () {
      expect(Spacing.xs, 4);
      expect(Spacing.sm, 8);
      expect(Spacing.md, 12);
      expect(Spacing.lg, 16);
      expect(Spacing.xl, 24);
      expect(Spacing.xxl, 32);
      expect(Spacing.xxxl, 48);
    });
  });

  group('Radii', () {
    test('hard-edge defaults are 2px', () {
      expect(Radii.card, const Radius.circular(2));
      expect(Radii.button, const Radius.circular(2));
      expect(Radii.chip, const Radius.circular(2));
      expect(Radii.modal, const Radius.circular(4));
    });
  });

  group('AppTypography', () {
    test('readouts use tabular figures', () {
      final readout = AppTypography.readoutMd;
      expect(readout.fontFamily, 'JetBrainsMono');
      final hasTabular =
          (readout.fontFeatures ?? []).any((f) => f.feature == 'tnum');
      expect(hasTabular, isTrue);
    });
    test('body uses Inter', () {
      expect(AppTypography.body.fontFamily, 'Inter');
    });
  });
}
```

Run: `flutter test test/ui/theme/tokens_test.dart` → expect failures (file doesn't exist).

- [ ] **Step 2: Create the tokens file**

Create `lib/ui/theme/tokens.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontFeature;

/// Single source of truth for every visual decision in CCRLog.
///
/// Widgets should read theme values via `Theme.of(context)` once we've
/// built the `ThemeData` from these tokens. Direct references to this
/// file are appropriate inside theme construction and inside the
/// chart layers where there's no `BuildContext`.

// ── Palette ──────────────────────────────────────────────────────────

/// A complete colour palette. Wraps the Wreck dark palette today; future
/// light-mode tropical palettes are added as additional constants.
class ThemePalette {
  const ThemePalette({
    required this.surfaceBg,
    required this.surfaceCard,
    required this.surfaceRaised,
    required this.surfaceBezel,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.accentPrimary,
    required this.accentMuted,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusDanger,
    required this.statusInfo,
    required this.cell1,
    required this.cell2,
    required this.cell3,
    required this.chartGrid,
    required this.chartTraceDepth,
    required this.chartTracePpo2,
    required this.chartTraceSetpoint,
    required this.chartTraceGf99,
  });

  final Color surfaceBg;
  final Color surfaceCard;
  final Color surfaceRaised;
  final Color surfaceBezel;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color accentPrimary;
  final Color accentMuted;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusDanger;
  final Color statusInfo;
  final Color cell1;
  final Color cell2;
  final Color cell3;
  final Color chartGrid;
  final Color chartTraceDepth;
  final Color chartTracePpo2;
  final Color chartTraceSetpoint;
  final Color chartTraceGf99;
}

class AppColors {
  AppColors._();

  /// Default dark mode. Reference: spec §"Visual direction — Wreck".
  static const ThemePalette wreck = ThemePalette(
    surfaceBg: Color(0xFF0A1518),
    surfaceCard: Color(0xFF142028),
    surfaceRaised: Color(0xFF1F2E38),
    surfaceBezel: Color(0xFF2A3A45),
    textPrimary: Color(0xFFE0E8EC),
    textSecondary: Color(0xFFA0AEB6),
    textMuted: Color(0xFF6B7D88),
    textInverse: Color(0xFF0A1518),
    accentPrimary: Color(0xFFFFCC66),
    accentMuted: Color(0xFF806633),
    statusSuccess: Color(0xFF4ADE80),
    statusWarning: Color(0xFFF39C12),
    statusDanger: Color(0xFFE74C3C),
    statusInfo: Color(0xFF60A5FA),
    cell1: Color(0xFF4ADE80),
    cell2: Color(0xFF60A5FA),
    cell3: Color(0xFFF472B6),
    chartGrid: Color(0xFF1A2832),
    chartTraceDepth: Color(0xFFE0E8EC),
    chartTracePpo2: Color(0xFFFFCC66),
    chartTraceSetpoint: Color(0xFFA0AEB6),
    chartTraceGf99: Color(0xFFF472B6),
  );
}

// ── Typography ───────────────────────────────────────────────────────

/// Pre-built `TextStyle`s referencing Inter (body) + JetBrains Mono
/// (readouts). Sizes/weights/tracking match the spec's type-scale table.
class AppTypography {
  AppTypography._();

  static const _tabular = [FontFeature.tabularFigures()];

  // Body (Inter)
  static const TextStyle display = TextStyle(
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const TextStyle title = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  // Readouts (JetBrains Mono, tabular figures)
  static const TextStyle readoutLg = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );
  static const TextStyle readoutMd = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );
  static const TextStyle readoutSm = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );
}

// ── Spacing ──────────────────────────────────────────────────────────

class Spacing {
  Spacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ── Radii ────────────────────────────────────────────────────────────

class Radii {
  Radii._();
  /// Cards / panels / readouts: 2px hard-edge.
  static const Radius card = Radius.circular(2);
  static const Radius button = Radius.circular(2);
  static const Radius chip = Radius.circular(2);
  /// Modals / sheets: slight softening so they don't read as system errors.
  static const Radius modal = Radius.circular(4);

  static const BorderRadius cardBr = BorderRadius.all(card);
  static const BorderRadius buttonBr = BorderRadius.all(button);
  static const BorderRadius chipBr = BorderRadius.all(chip);
  static const BorderRadius modalTopBr = BorderRadius.vertical(top: modal);
}

// ── Elevation ────────────────────────────────────────────────────────

/// We don't use Material drop shadows on the dark theme — they read as
/// rendering bugs. Elevation is expressed via layered surface colour.
class Elevation {
  Elevation._();
  /// Number of "depth levels" the design system supports.
  static const int levels = 3;
}

// ── Motion ───────────────────────────────────────────────────────────

class Motion {
  Motion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration emphasized = Duration(milliseconds: 400);
  static const Curve fastCurve = Curves.easeOut;
  static const Curve standardCurve = Curves.easeInOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;
}
```

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/theme/tokens_test.dart
flutter analyze
```
Expected: all tests pass, 0 analyzer issues.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/theme/tokens.dart test/ui/theme/tokens_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): Tech Dive design tokens (Wreck palette, type, spacing)

Single source of truth in lib/ui/theme/tokens.dart for every visual
decision: AppColors.wreck (the locked Wreck palette including the 3
cell colours), AppTypography (Inter body + JetBrains Mono tabular
readouts in 3 sizes), Spacing (4/8/12/16/24/32/48), Radii (2px hard
edge across cards/buttons/chips), Motion (3 durations + curves).
Future light-mode palettes plug in as new ThemePalette instances.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Rewire `app_theme.dart` to consume tokens

`ThemeData.dark()` rebuilt from the tokens. Every screen inherits.

**Files:**
- Modify: `lib/ui/theme/app_theme.dart` (full rewrite)
- Test: `test/ui/theme/app_theme_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppTheme.dark uses wreck palette', () {
    final t = AppTheme.dark();
    expect(t.colorScheme.surface, AppColors.wreck.surfaceBg);
    expect(t.colorScheme.primary, AppColors.wreck.accentPrimary);
    expect(t.colorScheme.error, AppColors.wreck.statusDanger);
    expect(t.scaffoldBackgroundColor, AppColors.wreck.surfaceBg);
  });

  test('AppTheme.dark TextTheme body uses Inter', () {
    final t = AppTheme.dark();
    expect(t.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(t.textTheme.titleLarge?.fontFamily, 'Inter');
  });

  test('AppTheme.dark card radius is hard-edge (2px)', () {
    final t = AppTheme.dark();
    final shape = t.cardTheme.shape as RoundedRectangleBorder?;
    final radius = (shape?.borderRadius as BorderRadius?)?.topLeft;
    expect(radius, const Radius.circular(2));
  });
}
```

- [ ] **Step 2: Rewrite `app_theme.dart`**

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const palette = AppColors.wreck;

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.accentPrimary,
      onPrimary: palette.textInverse,
      secondary: palette.accentMuted,
      onSecondary: palette.textPrimary,
      error: palette.statusDanger,
      onError: palette.textPrimary,
      surface: palette.surfaceBg,
      onSurface: palette.textPrimary,
      surfaceContainer: palette.surfaceCard,
      surfaceContainerHigh: palette.surfaceRaised,
      outline: palette.surfaceBezel,
      outlineVariant: palette.textMuted,
    );

    final textTheme = TextTheme(
      displayLarge: AppTypography.display.copyWith(color: palette.textPrimary),
      displayMedium: AppTypography.display.copyWith(color: palette.textPrimary),
      headlineLarge:
          AppTypography.headline.copyWith(color: palette.textPrimary),
      headlineMedium:
          AppTypography.headline.copyWith(color: palette.textPrimary),
      titleLarge: AppTypography.title.copyWith(color: palette.textPrimary),
      titleMedium: AppTypography.title.copyWith(color: palette.textPrimary),
      bodyLarge: AppTypography.body.copyWith(color: palette.textPrimary),
      bodyMedium: AppTypography.body.copyWith(color: palette.textPrimary),
      bodySmall: AppTypography.caption.copyWith(color: palette.textSecondary),
      labelLarge: AppTypography.label.copyWith(color: palette.textSecondary),
      labelMedium: AppTypography.label.copyWith(color: palette.textSecondary),
      labelSmall: AppTypography.caption.copyWith(color: palette.textMuted),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.surfaceBg,
      cardColor: palette.surfaceCard,
      dividerColor: palette.surfaceBezel,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surfaceBg,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        titleTextStyle:
            AppTypography.headline.copyWith(color: palette.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: palette.surfaceCard,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardBr),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surfaceBg,
        selectedItemColor: palette.accentPrimary,
        unselectedItemColor: palette.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accentPrimary,
          foregroundColor: palette.textInverse,
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonBr),
          textStyle:
              AppTypography.label.copyWith(letterSpacing: 0.6),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accentPrimary,
          side: BorderSide(color: palette.accentPrimary),
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonBr),
          textStyle:
              AppTypography.label.copyWith(letterSpacing: 0.6),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accentPrimary,
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonBr),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceCard,
        labelStyle: AppTypography.caption.copyWith(color: palette.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipBr),
        side: BorderSide(color: palette.surfaceBezel),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceCard,
        border: OutlineInputBorder(
          borderRadius: Radii.cardBr,
          borderSide: BorderSide(color: palette.surfaceBezel),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.cardBr,
          borderSide: BorderSide(color: palette.surfaceBezel),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.cardBr,
          borderSide: BorderSide(color: palette.accentPrimary),
        ),
        labelStyle:
            AppTypography.caption.copyWith(color: palette.textSecondary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radii.modal),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.modalTopBr),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle:
            AppTypography.body.copyWith(color: palette.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardBr),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
```

- [ ] **Step 3: Run tests + analyzer + visual sanity**

```bash
flutter test test/ui/theme/
flutter analyze
flutter test
```
Expected: tests pass, 0 analyzer issues. Existing widget tests may have one or two adjustments (e.g. asserting on a specific text style); check the output. Most tests assert on `find.text(...)` which is style-agnostic.

If a widget test fails on a hardcoded colour that the new theme changes, update the assertion to read from `Theme.of(context)` instead of a fixed colour. Don't break tests by widening assertions; tighten them to the new theme.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/theme/app_theme.dart test/ui/theme/app_theme_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): rebuild AppTheme.dark from tokens

ThemeData now pulls every value from lib/ui/theme/tokens.dart:
- ColorScheme uses the Wreck palette
- TextTheme uses Inter (body) + JetBrains Mono (readouts)
- Cards / buttons / chips / inputs are hard-edge 2px
- Dialogs / sheets are 4px (slight softening)
- AppBar / BottomNav / dividers use the slate-blue surfaces
- Drop shadows disabled (elevation: 0 everywhere) — depth comes from
  layered surface colour

Every screen and widget that reads Theme.of(context) picks up the new
look automatically. No widget code changes in this commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Simple components — `AppCard`, `BezelPanel`, `StatusDot`

The three zero-logic visual primitives. Lay down the directory + golden-test pattern.

**Files:**
- Create: `lib/ui/components/app_card.dart`
- Create: `lib/ui/components/bezel_panel.dart`
- Create: `lib/ui/components/status_dot.dart`
- Create: `test/ui/components/app_card_test.dart`
- Create: `test/ui/components/status_dot_test.dart`

- [ ] **Step 1: Write the components**

`lib/ui/components/app_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Hard-edge 2px card with surface.card background.
///
/// Use [withBezel] for the "instrument" look — a 1px bezel outline
/// using surface.bezel. Optional [padding] (default: Spacing.md).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.withBezel = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool withBezel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: Radii.cardBr,
        border: withBezel ? Border.all(color: scheme.outline) : null,
      ),
      padding: padding,
      child: child,
    );
  }
}
```

`lib/ui/components/bezel_panel.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 1px bezel outline, no fill. Wraps charts, instruments, longitudinal
/// views — anything that should read as an instrument bezel rather
/// than a card.
class BezelPanel extends StatelessWidget {
  const BezelPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: Radii.cardBr,
        border: Border.all(color: scheme.outline),
      ),
      padding: padding,
      child: child,
    );
  }
}
```

`lib/ui/components/status_dot.dart`:

```dart
import 'package:flutter/material.dart';

/// 8 px coloured circle. Used for cell status, sync state, dive type.
/// The colour is supplied by the caller — typically one of
/// AppColors.wreck.statusSuccess / statusWarning / statusDanger /
/// statusInfo or a cell colour.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
```

- [ ] **Step 2: Tests**

`test/ui/components/app_card_test.dart`:

```dart
import 'package:ccrlogger/ui/components/app_card.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppCard renders surface.card background',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: AppCard(child: Text('hello'))),
    ));
    expect(find.text('hello'), findsOneWidget);
    final container = tester.widget<Container>(find.byType(Container).first);
    final dec = container.decoration as BoxDecoration;
    expect(dec.color, AppColors.wreck.surfaceCard);
    expect(dec.border, isNull); // default withBezel: false
  });

  testWidgets('AppCard with bezel adds an outline', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: AppCard(withBezel: true, child: Text('x')),
      ),
    ));
    final container = tester.widget<Container>(find.byType(Container).first);
    final dec = container.decoration as BoxDecoration;
    expect(dec.border, isNotNull);
  });
}
```

`test/ui/components/status_dot_test.dart`:

```dart
import 'package:ccrlogger/ui/components/status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatusDot renders a coloured circle of the right size',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatusDot(color: Colors.red)),
    ));
    final container = tester.widget<Container>(find.byType(Container));
    final dec = container.decoration as BoxDecoration;
    expect(dec.color, Colors.red);
    expect(dec.shape, BoxShape.circle);
    expect(container.constraints?.maxWidth, 8);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/ui/components/ && flutter analyze
git add lib/ui/components/app_card.dart lib/ui/components/bezel_panel.dart \
        lib/ui/components/status_dot.dart test/ui/components/
git commit -m "feat(ui): AppCard, BezelPanel, StatusDot components

Three zero-logic visual primitives. AppCard is the standard panel
(surface.card, 2px radius, optional bezel for instruments).
BezelPanel is outline-only for charts. StatusDot is the universal
8px coloured-status indicator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Numeric components — `NumericReadout`, `StatTile`

The dive-computer-readout feel.

**Files:**
- Create: `lib/ui/components/numeric_readout.dart`
- Create: `lib/ui/components/stat_tile.dart`
- Test: `test/ui/components/numeric_readout_test.dart`
- Test: `test/ui/components/stat_tile_test.dart`

- [ ] **Step 1: Write the components**

`lib/ui/components/numeric_readout.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ReadoutSize { sm, md, lg }

/// JetBrains Mono numeric readout with tabular figures. Designed for
/// stat values where character columns must align (depth tables, time
/// rows, cell mV ladders).
class NumericReadout extends StatelessWidget {
  const NumericReadout(
    this.value, {
    super.key,
    this.size = ReadoutSize.md,
    this.color,
  });

  final String value;
  final ReadoutSize size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = switch (size) {
      ReadoutSize.sm => AppTypography.readoutSm,
      ReadoutSize.md => AppTypography.readoutMd,
      ReadoutSize.lg => AppTypography.readoutLg,
    };
    return Text(
      value,
      style: style.copyWith(
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
```

`lib/ui/components/stat_tile.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'numeric_readout.dart';

/// One labelled stat tile: a small uppercase label above a tabular
/// numeric readout. Used in the Dive Detail stats row and anywhere a
/// dive-computer-style metric needs to appear.
///
/// [unit] is rendered in the label position alongside [label] (e.g.
/// "DEPTH m"). [hint] is an optional auxiliary mini-readout under the
/// main value (e.g. "min/max" in fine print).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.valueColor,
    this.size = ReadoutSize.md,
  });

  final String label;
  final String value;
  final String? unit;
  final String? hint;
  final Color? valueColor;
  final ReadoutSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullLabel = unit == null ? label : '$label  $unit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fullLabel.toUpperCase(),
          style: AppTypography.label.copyWith(color: scheme.outlineVariant),
        ),
        const SizedBox(height: Spacing.xs),
        NumericReadout(value, size: size, color: valueColor),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: AppTypography.caption.copyWith(color: scheme.outlineVariant),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 2: Tests**

`test/ui/components/numeric_readout_test.dart`:

```dart
import 'package:ccrlogger/ui/components/numeric_readout.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NumericReadout uses JetBrainsMono', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: NumericReadout('57:30')),
    ));
    final text = tester.widget<Text>(find.text('57:30'));
    expect(text.style?.fontFamily, 'JetBrainsMono');
  });

  testWidgets('NumericReadout sizes match tokens', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Column(children: [
          NumericReadout('A', size: ReadoutSize.sm),
          NumericReadout('B', size: ReadoutSize.md),
          NumericReadout('C', size: ReadoutSize.lg),
        ]),
      ),
    ));
    final a = tester.widget<Text>(find.text('A')).style!;
    final b = tester.widget<Text>(find.text('B')).style!;
    final c = tester.widget<Text>(find.text('C')).style!;
    expect(a.fontSize, 13);
    expect(b.fontSize, 16);
    expect(c.fontSize, 24);
  });
}
```

`test/ui/components/stat_tile_test.dart`:

```dart
import 'package:ccrlogger/ui/components/stat_tile.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatTile renders label uppercased + value + hint',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: StatTile(
          label: 'Max depth',
          value: '18.0',
          unit: 'm',
          hint: 'avg 9.6',
        ),
      ),
    ));
    expect(find.text('MAX DEPTH  M'), findsOneWidget);
    expect(find.text('18.0'), findsOneWidget);
    expect(find.text('avg 9.6'), findsOneWidget);
  });

  testWidgets('StatTile without hint omits the auxiliary line',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: StatTile(label: 'CNS', value: '45%')),
    ));
    expect(find.text('CNS'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/ui/components/ && flutter analyze
git add lib/ui/components/numeric_readout.dart \
        lib/ui/components/stat_tile.dart test/ui/components/
git commit -m "feat(ui): NumericReadout + StatTile

NumericReadout wraps Text with JetBrains Mono + tabular figures in
3 sizes (sm/md/lg). StatTile composes an uppercase label + readout +
optional hint into a single column — the dive-detail-stats-row member.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Text layout components — `SectionHeader`, `DataRow`

Replace the ad-hoc section headers and the inline `_readOnlyRow` we already shipped.

**Files:**
- Create: `lib/ui/components/section_header.dart`
- Create: `lib/ui/components/data_row.dart`
- Test: `test/ui/components/section_header_test.dart`
- Test: `test/ui/components/data_row_test.dart`

- [ ] **Step 1: Write the components**

`lib/ui/components/section_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Uppercase 11px caption. Replaces ad-hoc section labels across
/// dive-detail tabs, settings, and other layered screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.label.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
```

`lib/ui/components/data_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'numeric_readout.dart';

/// A label + value display-only row. The label sits in a fixed-width
/// gutter on the left; the value is normal text by default, or a
/// numeric readout when [numeric] is true.
class DataRow extends StatelessWidget {
  const DataRow({
    super.key,
    required this.label,
    required this.value,
    this.numeric = false,
    this.labelWidth = 130,
  });

  final String label;
  final String value;
  final bool numeric;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: AppTypography.body.copyWith(color: scheme.outlineVariant),
            ),
          ),
          if (numeric)
            NumericReadout(value, size: ReadoutSize.sm)
          else
            Text(value,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                )),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Tests**

`test/ui/components/section_header_test.dart`:

```dart
import 'package:ccrlogger/ui/components/section_header.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SectionHeader renders uppercase label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: SectionHeader('Environment')),
    ));
    expect(find.text('ENVIRONMENT'), findsOneWidget);
  });
}
```

`test/ui/components/data_row_test.dart`:

```dart
import 'package:ccrlogger/ui/components/data_row.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DataRow renders label + value', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: DataRow(label: 'Atm. pressure', value: '1003 mbar'),
      ),
    ));
    expect(find.text('Atm. pressure'), findsOneWidget);
    expect(find.text('1003 mbar'), findsOneWidget);
  });

  testWidgets('DataRow with numeric:true uses monospace', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: DataRow(label: 'GF', value: '14%', numeric: true),
      ),
    ));
    final valueText = tester.widget<Text>(find.text('14%'));
    expect(valueText.style?.fontFamily, 'JetBrainsMono');
  });
}
```

- [ ] **Step 3: Update `dive_information_section.dart` to use `DataRow`**

Replace its private `_readOnlyRow` calls with imports of the new `DataRow`. Delete the now-unused private helper. Re-run the existing Information section widget test — it should still pass because we still render the same text.

- [ ] **Step 4: Run + commit**

```bash
flutter test
flutter analyze
git add lib/ui/components/section_header.dart \
        lib/ui/components/data_row.dart \
        lib/ui/widgets/dive_information_section.dart \
        test/ui/components/
git commit -m "feat(ui): SectionHeader + DataRow components

SectionHeader is the uppercase 11px caption used above every
section. DataRow is the label-gutter-on-left, value-on-right
pattern we shipped inline on the Information tab — now lifted
into the library and reused there.

Information section's _readOnlyRow is deleted in favour of the
shared component.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Action components — `AccentButton`, `GhostButton`, `IconChip`

**Files:**
- Create: `lib/ui/components/accent_button.dart`
- Create: `lib/ui/components/ghost_button.dart`
- Create: `lib/ui/components/icon_chip.dart`
- Tests in `test/ui/components/`

- [ ] **Step 1: Components**

`lib/ui/components/accent_button.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Primary action button. Hard-edge, sodium-vapor fill, uppercase label.
/// Wraps FilledButton with the design-system defaults baked in.
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label.toUpperCase())
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: Spacing.sm),
              Text(label.toUpperCase()),
            ],
          );
    return FilledButton(onPressed: onPressed, child: child);
  }
}
```

`lib/ui/components/ghost_button.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Secondary action button. Outlined, no fill, accent border.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label.toUpperCase())
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: Spacing.sm),
              Text(label.toUpperCase()),
            ],
          );
    return OutlinedButton(onPressed: onPressed, child: child);
  }
}
```

`lib/ui/components/icon_chip.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small filter/status chip with an optional leading icon. Used for
/// dive tags, filter toggles, status badges.
class IconChip extends StatelessWidget {
  const IconChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border.all(color: scheme.outline),
          borderRadius: Radii.chipBr,
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: Spacing.xs),
            ],
            Text(label,
                style: AppTypography.caption.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Smoke tests**

```dart
// test/ui/components/buttons_test.dart
import 'package:ccrlogger/ui/components/accent_button.dart';
import 'package:ccrlogger/ui/components/ghost_button.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AccentButton uppercases its label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: AccentButton(label: 'Push to subs', onPressed: () {}),
      ),
    ));
    expect(find.text('PUSH TO SUBS'), findsOneWidget);
  });

  testWidgets('GhostButton uppercases its label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: GhostButton(label: 'Cancel', onPressed: () {}),
      ),
    ));
    expect(find.text('CANCEL'), findsOneWidget);
  });
}

// test/ui/components/icon_chip_test.dart
import 'package:ccrlogger/ui/components/icon_chip.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('IconChip renders icon + label and is tappable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: IconChip(
          label: 'CCR',
          icon: Icons.air,
          onTap: () => taps++,
        ),
      ),
    ));
    expect(find.text('CCR'), findsOneWidget);
    expect(find.byIcon(Icons.air), findsOneWidget);
    await tester.tap(find.byType(IconChip));
    expect(taps, 1);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/ui/components/
flutter analyze
git add lib/ui/components/ test/ui/components/
git commit -m "feat(ui): AccentButton + GhostButton + IconChip

AccentButton wraps FilledButton with auto-uppercase label and
optional leading icon. GhostButton is the outlined secondary
variant. IconChip is the filter/status chip with an optional
leading icon.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Widgetbook dev screen + Settings entry point

A long flat list previewing every component in every state. Hidden behind a long-press on the app version label in Settings.

**Files:**
- Create: `lib/ui/dev/widgetbook_screen.dart`
- Modify: `lib/ui/screens/settings_screen.dart`
- Test: `test/ui/dev/widgetbook_screen_test.dart`

- [ ] **Step 1: Write the Widgetbook**

```dart
// lib/ui/dev/widgetbook_screen.dart
import 'package:flutter/material.dart';

import '../components/accent_button.dart';
import '../components/app_card.dart';
import '../components/bezel_panel.dart';
import '../components/data_row.dart';
import '../components/ghost_button.dart';
import '../components/icon_chip.dart';
import '../components/numeric_readout.dart';
import '../components/section_header.dart';
import '../components/stat_tile.dart';
import '../components/status_dot.dart';
import '../theme/tokens.dart';

class WidgetbookScreen extends StatelessWidget {
  const WidgetbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widgetbook')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          const SectionHeader('Palette'),
          _swatchRow(context, 'surface.bg', AppColors.wreck.surfaceBg),
          _swatchRow(context, 'surface.card', AppColors.wreck.surfaceCard),
          _swatchRow(context, 'surface.raised', AppColors.wreck.surfaceRaised),
          _swatchRow(context, 'accent.primary', AppColors.wreck.accentPrimary),
          _swatchRow(context, 'status.success', AppColors.wreck.statusSuccess),
          _swatchRow(context, 'status.warning', AppColors.wreck.statusWarning),
          _swatchRow(context, 'status.danger', AppColors.wreck.statusDanger),
          _swatchRow(context, 'cell.1', AppColors.wreck.cell1),
          _swatchRow(context, 'cell.2', AppColors.wreck.cell2),
          _swatchRow(context, 'cell.3', AppColors.wreck.cell3),

          const SizedBox(height: Spacing.xl),
          const SectionHeader('Cards'),
          const AppCard(child: Text('AppCard (no bezel)')),
          const SizedBox(height: Spacing.sm),
          const AppCard(
            withBezel: true,
            child: Text('AppCard withBezel: true'),
          ),
          const SizedBox(height: Spacing.sm),
          const BezelPanel(child: Text('BezelPanel — outline only')),

          const SizedBox(height: Spacing.xl),
          const SectionHeader('Numeric readouts'),
          const Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.md,
            children: [
              NumericReadout('57:30', size: ReadoutSize.lg),
              NumericReadout('18.0 m', size: ReadoutSize.md),
              NumericReadout('1.30 bar', size: ReadoutSize.sm),
            ],
          ),

          const SizedBox(height: Spacing.xl),
          const SectionHeader('Stat tiles'),
          const Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.md,
            children: [
              StatTile(label: 'Max depth', unit: 'm', value: '18.0'),
              StatTile(
                  label: 'Duration', unit: 'min', value: '57:30', hint: ''),
              StatTile(
                  label: 'PPO2 (bar)',
                  value: '1.30',
                  hint: '0.70 / 1.30'),
              StatTile(label: 'CNS', value: '45%'),
            ],
          ),

          const SizedBox(height: Spacing.xl),
          const SectionHeader('Data rows'),
          const DataRow(label: 'Water type', value: 'Fresh — 1.000 g/L'),
          const DataRow(label: 'Atm. pressure', value: '1003 mbar'),
          const DataRow(label: 'Surface GF', value: '14%', numeric: true),

          const SizedBox(height: Spacing.xl),
          const SectionHeader('Buttons'),
          Row(
            children: [
              AccentButton(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Push to Subsurface',
                  onPressed: () {}),
              const SizedBox(width: Spacing.sm),
              GhostButton(label: 'Cancel', onPressed: () {}),
              const SizedBox(width: Spacing.sm),
              AccentButton(label: 'Disabled', onPressed: null),
            ],
          ),

          const SizedBox(height: Spacing.xl),
          const SectionHeader('Chips + status'),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              IconChip(label: 'CCR', icon: Icons.air, onTap: () {}),
              IconChip(label: 'Deep', icon: Icons.south, onTap: () {}),
              const IconChip(label: 'WIP'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(color: AppColors.wreck.statusSuccess),
                const SizedBox(width: Spacing.xs),
                const Text('online'),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(color: AppColors.wreck.statusWarning),
                const SizedBox(width: Spacing.xs),
                const Text('skipped'),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(color: AppColors.wreck.statusDanger),
                const SizedBox(width: Spacing.xs),
                const Text('failed'),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatchRow(BuildContext context, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: Radii.cardBr,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: Spacing.md),
          SizedBox(width: 140, child: Text(label)),
          NumericReadout(
            '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            size: ReadoutSize.sm,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Wire the long-press entry point in Settings**

In `lib/ui/screens/settings_screen.dart`, find where the app version label is rendered (search for `appVersion` or `package_info`). Wrap it with a `GestureDetector(onLongPress: ...)` that navigates to `WidgetbookScreen`:

```dart
GestureDetector(
  onLongPress: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WidgetbookScreen()),
    );
  },
  child: Text('CCRLog $appVersion'),
)
```

If the Settings screen doesn't currently show a version label, add one as a small `caption`-styled text in the footer:

```dart
Padding(
  padding: const EdgeInsets.all(Spacing.lg),
  child: GestureDetector(
    onLongPress: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WidgetbookScreen()),
    ),
    child: Text(
      'CCRLog v${packageInfo.version} (${packageInfo.buildNumber})',
      style: Theme.of(context).textTheme.labelSmall,
    ),
  ),
)
```

(Adapt to whatever `PackageInfo` source the settings file already uses; if none, use `'CCRLog'` as a constant for now and let the next pass wire in actual version info.)

- [ ] **Step 3: Smoke test**

```dart
// test/ui/dev/widgetbook_screen_test.dart
import 'package:ccrlogger/ui/dev/widgetbook_screen.dart';
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WidgetbookScreen renders without exceptions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const WidgetbookScreen(),
    ));
    await tester.pumpAndSettle();
    // Spot-check that key sections rendered.
    expect(find.text('PALETTE'), findsOneWidget);
    expect(find.text('CARDS'), findsOneWidget);
    expect(find.text('NUMERIC READOUTS'), findsOneWidget);
    expect(find.text('STAT TILES'), findsOneWidget);
    expect(find.text('BUTTONS'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run + commit**

```bash
flutter test test/ui/dev/ && flutter analyze
git add lib/ui/dev/widgetbook_screen.dart \
        lib/ui/screens/settings_screen.dart \
        test/ui/dev/widgetbook_screen_test.dart
git commit -m "feat(ui): Widgetbook screen previewing every component

Dev-only inventory of palette + components in every state. Reached
via long-press on the app version label in Settings — invisible to
regular users, one tap away for design iteration. Ships in release
builds so we can iterate on TestFlight without re-installing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Dive Detail showcase refactor

The visible win. Replace the inline `_statCell` / `_avgMinMaxCell` etc. with `StatTile`, retune the profile chart palette, and swap ad-hoc section headers for `SectionHeader`.

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart`
- Modify: `lib/ui/widgets/profile_chart.dart`
- Tests: existing dive detail tests must still pass

- [ ] **Step 1: Survey current stat cells**

```bash
grep -n "_statCell\|_avgMinMaxCell\|_descAscCell\|_tanksCell\|_stackCell\|_gfCell" \
  lib/ui/screens/dive_detail_screen.dart | head -20
```

Note each helper — these get replaced with `StatTile` usage. Some take aux data (min/max, avg, descent rate); `StatTile.hint` covers the auxiliary line.

- [ ] **Step 2: Replace stat cells**

In the cells list around line 729 of `dive_detail_screen.dart`, rewrite each cell:

```dart
final cells = <Widget>[
  if (ppo2Stats != null)
    StatTile(
      label: 'PPO2',
      unit: 'bar',
      value: ppo2Stats.avg.toStringAsFixed(2),
      hint: '${ppo2Stats.min.toStringAsFixed(2)} / '
            '${ppo2Stats.max.toStringAsFixed(2)}',
    )
  else
    const StatTile(label: 'PPO2', value: '—'),
  StatTile(label: 'CNS', value: '${(maxCns * 100).round()}%'),
  if (showOtu) StatTile(label: 'OTU', value: '${otu.round()}'),
  if (tempStats != null)
    StatTile(
      label: 'Temp',
      unit: '°C',
      value: '${tempStats.avg.round()}',
      hint: '${tempStats.min.round()} / ${tempStats.max.round()}',
    )
  else
    const StatTile(label: 'Temp', unit: '°C', value: '—'),
  StatTile(
    label: 'V-speed',
    unit: 'm/min',
    value: '↓${vSpeed.maxDescentMpm.round()} '
           '↑${vSpeed.maxAscentMpm.round()}',
  ),
  StatTile(label: 'Gas', value: gasLabel),
  if (_activeTanks().isNotEmpty) _buildTanksTile(_activeTanks(), theme),
  if (stackEnd != null)
    StatTile(
      label: 'Stack',
      value: stackLabel,
      hint: [stackUsed, stackConf].whereType<String>().join(' · '),
    ),
];
```

Delete the now-unused `_statCell`, `_avgMinMaxCell`, `_descAscCell`, `_stackCell` helpers. Keep `_tanksTile` as a custom widget if its layout is too complex for `StatTile`.

- [ ] **Step 3: Profile chart palette**

In `lib/ui/widgets/profile_chart.dart`, replace hardcoded colours with token references. `import '../theme/tokens.dart';` then:

```dart
// In the paint code, replace existing colour literals:
//   depth trace → AppColors.wreck.chartTraceDepth
//   ppo2 trace  → AppColors.wreck.chartTracePpo2
//   setpoint    → AppColors.wreck.chartTraceSetpoint
//   grid lines  → AppColors.wreck.chartGrid
//   crosshair   → AppColors.wreck.accentPrimary
//   background  → AppColors.wreck.surfaceBg
```

If the chart already takes a `theme` parameter, prefer reading the palette from there so the chart picks up a future light-mode automatically. For now, importing `AppColors.wreck` directly is fine — annotate with a `// TODO: read from ThemeData once light mode exists` so future-self sees the lift.

- [ ] **Step 4: Section headers in Dive Detail tabs**

Find every place in `dive_detail_screen.dart` (and the section widgets it embeds) that renders an ad-hoc section header — typically `Text('Foo', style: ...)` with `fontWeight: FontWeight.w600`. Replace with `SectionHeader('Foo')`.

`dive_information_section.dart` already uses an internal `_sectionHeader` helper — replace it with `SectionHeader` from the library and delete the internal helper.

- [ ] **Step 5: AppBar title with subtitle**

In Dive Detail's `AppBar`, switch the title to a `Column` with `display`-styled headline + `caption`-styled site / date:

```dart
AppBar(
  title: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Dive ${dive.dcDiveNumber}',
        style: AppTypography.headline.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      Text(
        '${annotation?.siteName ?? '—'}  ·  ${formatDate(dive.startTime)}',
        style: AppTypography.caption.copyWith(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ],
  ),
)
```

- [ ] **Step 6: Run tests**

```bash
flutter test
flutter analyze
```
Expected: all existing tests still pass — they assert on `find.text(...)` which is style-agnostic. Any test that hardcoded a colour or a specific font might need updating. Spot-check and fix narrowly.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/screens/dive_detail_screen.dart \
        lib/ui/widgets/profile_chart.dart \
        lib/ui/widgets/dive_information_section.dart
git commit -m "$(cat <<'EOF'
feat(ui): Dive Detail consumes the design system

Stat row now uses StatTile + NumericReadout — every value rendered
in JetBrains Mono with tabular figures, every label in uppercase
Inter 12. Profile chart palette references token colours (chartGrid,
chartTraceDepth, chartTracePpo2, chartTraceSetpoint, accentPrimary
for crosshair). Section headers throughout the dive-detail tabs use
SectionHeader. AppBar shows Dive N as headline + site · date as
caption underneath.

Existing widget tests pass unchanged — assertions are label-based,
not style-based.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Full-suite verification + push

- [ ] **Step 1: Full sweep**

```bash
flutter analyze
flutter test
```
Expected: 0 issues, all tests pass. If a test fails on a specific colour or hardcoded font, decide:
- If the test was asserting design-system-locked behaviour (e.g. "stat values are monospace"), keep the assertion and verify the test passes against the new tokens.
- If the test was asserting an old hex colour, replace with a token reference.

- [ ] **Step 2: Manual smoke**

Run the app on macOS + iPhone. Walk through:
- Dive list — typography looks consistent, tiles read clean.
- Open a CCR dive — stat row renders in mono, section headers are uppercase, profile chart uses the new palette, AppBar shows headline + subtitle.
- Information tab — caption pairs from the previous session still render, water type + atm pressure still show.
- Settings — long-press the version label opens the Widgetbook. Walk through it; every component should look right.
- Edit a dive's annotation — fields and buttons feel cohesive.

Document any visual nits in commits as follow-ups; don't block the push on cosmetics.

- [ ] **Step 3: Push**

```bash
git push origin main
```

- [ ] **Step 4: Update memory**

In `/Users/egbert/.claude/projects/-Users-egbert-Dev-CCRLog-ccrlogger/memory/project_next_session_priority.md`:
- Mark Tech Dive design system as shipped.
- Note: future Phase = light-mode tropical palette, hooked up via the `ThemePalette` slot that's already in `tokens.dart`.
- Note: per-trip theming (Caribbean / cave / wreck per trip) is captured in the spec under "deferred" and depends on light mode landing first.

---

## Self-Review

**Spec coverage:**
- Tokens (colour / type / spacing / radius / motion) → Task 2.
- Component library (10 components) → Tasks 4, 5, 6, 7.
- Widgetbook + Settings entry point → Task 8.
- Dive Detail showcase → Task 9.
- Goldens / widget tests → embedded in Tasks 4–9.
- Cell colour assignment locked across screens → enforced in `tokens.dart` (Task 2) and applied in profile chart (Task 9).

**Placeholder scan:** every step has either complete code, a code skeleton with explicit "adapt to whatever X exists" guidance, or a clear bash command. No "TODO/TBD" in step bodies.

**Type consistency:** `ThemePalette` definition in Task 2 matches every field referenced in Tasks 3 onwards. `StatTile` / `NumericReadout` / `DataRow` signatures defined in Tasks 5/6 are consumed in Task 9 with the same parameter names.

**Ambiguity check:** the only soft guidance is "adapt to whatever existing widget uses if the surface signature differs from the snippet" — that's explicit and unavoidable until the implementer reads the file. Every concrete signature (colours, sizes, weights, spacings, fonts) is locked.
