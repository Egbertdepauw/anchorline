# Tech Dive design system — design

**Status:** draft 2026-05-11, awaiting user approval.

**Owner:** CCRLog UI.

**Context:** Current theme is 32 lines: dark navy surface + cyan seed, generic Material 3. The audience is technical and CCR divers — people who spend hours staring at dive computer screens and post-dive analysis software. The app's character per CLAUDE.md is "CCR-first, OC-second" and "tech divers dive in dark places and surface in dark cars." The visual language should match: a deliberate dark-mode-first design system that reads as serious technical software, not a generic consumer app. A future light mode for tropical diving is captured as a non-goal-this-session breadcrumb.

## Goals (this session)

1. **Design token system** — a single source of truth in `lib/ui/theme/` for colour, typography, spacing, radius, elevation, and motion. Every existing widget inherits the new look via `AppTheme` without per-widget changes.
2. **Component library** — a small set of opinionated, reusable widgets (`StatTile`, `NumericReadout`, `AppCard`, `SectionHeader`, `DataRow`, etc.) with consistent shape/typography/colour rules. Documented inline. Used wherever the pattern fits.
3. **Widgetbook screen** — a dev-mode-only `/dev/widgetbook` route that previews every component in every state (default, focused, disabled, error, dense), so future-self can see at a glance what's available and what it looks like.
4. **Dive Detail showcase** — refactor the highest-impact screen to use the new tokens + components so we ship a visible win, not just plumbing.

## Non-goals (deferred)

- **Light mode (tropical).** The token system is built with the right structure to add a second `ColorScheme` later, but we don't ship one yet. The token file will note where the light-mode definitions go.
- **Per-trip theming.** A future direction is letting the user pick a "Caribbean / cave / wreck" theme per trip. Not in this pass.
- **Animations / motion system.** We define motion tokens (durations, easings) but don't audit every existing animation. New components use them; existing ones get touched lazily.
- **Custom dive-domain icons.** Material icons are fine for v1. Custom icons (cylinder shapes, depth gauges, CCR-loop glyphs) are a future polish task.

## Visual direction — Wreck

| Token | Hex | Role |
|---|---|---|
| `surface.bg` | `#0A1518` | Scaffold background (cold slate) |
| `surface.card` | `#142028` | Card / panel (silt-on-steel) |
| `surface.raised` | `#1F2E38` | Raised card, modal, sheet (steel) |
| `surface.bezel` | `#2A3A45` | 1px outline around readouts, instruments |
| `text.primary` | `#E0E8EC` | Body text (cold white) |
| `text.secondary` | `#A0AEB6` | Labels, captions |
| `text.muted` | `#6B7D88` | De-emphasised, rust-green |
| `text.inverse` | `#0A1518` | Text on accent surfaces |
| `accent.primary` | `#FFCC66` | Primary actions, focus rings (sodium-vapor) |
| `accent.muted` | `#806633` | Hover/pressed accent |
| `status.success` | `#4ADE80` | OK indicators (cell green) |
| `status.warning` | `#F39C12` | Caution, skipped, near-limit |
| `status.danger` | `#E74C3C` | MOD exceeded, cell failed, error |
| `status.info` | `#60A5FA` | Neutral info, sync indicators |
| `cell.1` | `#4ADE80` | Cell 1 trace / chart |
| `cell.2` | `#60A5FA` | Cell 2 trace |
| `cell.3` | `#F472B6` | Cell 3 trace |
| `chart.grid` | `#1A2832` | Grid lines on profile chart |
| `chart.trace.depth` | `#E0E8EC` | Depth trace (cold white) |
| `chart.trace.ppo2` | `#FFCC66` | PPO2 voted trace (sodium) |
| `chart.trace.setpoint` | `#A0AEB6` | Setpoint reference line |
| `chart.trace.gf99` | `#F472B6` | GF99 (when Phase 3 ships) |

Polarity convention for cell colours is locked: **Cell 1 green, Cell 2 blue, Cell 3 pink.** This applies to per-dive cell traces, longitudinal cell health charts, and per-cell mV indicators. Consistency across screens lets a diver glance at any chart and know which cell is which without a legend.

## Typography

- **Font family — body:** Inter (variable font, weights 400/500/600/700).
- **Font family — numerals:** JetBrains Mono (variable font, weights 400/500/600). Tabular numerals enabled (`fontFeatures: [FontFeature.tabularFigures()]`).
- **Why both:** Inter is the de-facto neutral UI sans. JetBrains Mono on stat readouts gives the dive-computer-display feel — narrow zero, distinct `1` vs `l` vs `I`, equal column widths.

Type scale (`TextTheme`):

| Token | Family | Size / Weight / Tracking | Used for |
|---|---|---|---|
| `display` | Inter | 28 SemiBold, -0.5 | Screen titles in hero spots |
| `headline` | Inter | 20 SemiBold, -0.3 | AppBar titles, section heroes |
| `title` | Inter | 16 SemiBold, 0 | Card titles |
| `body` | Inter | 14 Regular, 0 | Body text, dialogs |
| `label` | Inter | 12 Medium, 0.6 (uppercase) | Section headers, captions |
| `caption` | Inter | 11 Regular, 0 | Hints, helper text |
| `readout.lg` | JetBrains Mono | 24 SemiBold, tabular | Hero stat values |
| `readout.md` | JetBrains Mono | 16 Medium, tabular | Stat row values |
| `readout.sm` | JetBrains Mono | 13 Regular, tabular | Inline values inside dense rows |

Fonts get pinned in `pubspec.yaml` with explicit asset paths under `fonts/`. We vendor the `.ttf` files (variable fonts) so the app doesn't need network at first launch. Both fonts are open-source (Inter under SIL OFL, JetBrains Mono under SIL OFL).

## Shape language — hard-edge

- **Card / panel radius:** `2 px` (almost-square, bezel-like).
- **Button radius:** `2 px` (matches the card aesthetic).
- **Chip radius:** `2 px`.
- **Readout panel radius:** `2 px` with a 1px `surface.bezel` outline — the "instrument bezel" treatment.
- **Modal / sheet radius:** `4 px` top corners (slight softening so it doesn't look like a system error dialog).
- **Avatar / circular elements:** stay circular.

Buttons render labels in `Inter Medium UPPERCASE` with `letterSpacing: 0.6` to reinforce the industrial feel. (Soft mode = sentence case; we chose hard-edge.)

## Spacing scale

Single source of truth in `Spacing` class:

| Token | px |
|---|---|
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `lg` | 16 |
| `xl` | 24 |
| `xxl` | 32 |
| `xxxl` | 48 |

All padding / gap values reference these. No magic numbers in widgets.

## Elevation

Material's shadow elevation reads wrong on near-black surfaces. We use **layered surface colour** instead:

- Level 0: `surface.bg` (scaffold)
- Level 1: `surface.card` (cards on scaffold)
- Level 2: `surface.raised` (raised cards, modals, sheets)

Plus an optional 1px `surface.bezel` outline on stat readouts and chart panels. No drop shadows on dark theme — they look like rendering bugs.

## Motion

| Token | Duration | Easing |
|---|---|---|
| `motion.fast` | 120 ms | `Curves.easeOut` |
| `motion.standard` | 240 ms | `Curves.easeInOutCubic` |
| `motion.emphasized` | 400 ms | `Curves.easeInOutCubicEmphasized` |

Used for tab switches, sheet entry, hover/press states. Existing animations stay as-is for now; new components use these tokens.

## Component library (v1)

Each component lives in `lib/ui/components/` (new directory), gets a dartdoc explaining its purpose, and is showcased in the Widgetbook.

| Component | Purpose | Notes |
|---|---|---|
| `AppCard` | Standard panel container | 2 px radius, `surface.card`, optional 1px bezel for "instrument" look |
| `StatTile` | One labelled stat in a row of stats | Used in the Dive Detail stat row — label above, big readout below |
| `NumericReadout` | Tabular-numeral stat value | Wraps a Text with JetBrains Mono + tabular figures; sizes `sm`/`md`/`lg` |
| `SectionHeader` | Uppercase 11 px label preceding a block | Replaces the inconsistent ad-hoc headers across screens |
| `DataRow` | Label + value display-only row | The pattern we just shipped on the Information tab; lifts it into the library |
| `AccentButton` | Primary action | Hard-edge, sodium-vapor accent, uppercase label |
| `GhostButton` | Secondary action | Outlined, no fill, accent border |
| `IconChip` | Status/filter chip with leading icon | Used for tags, sync state, filter toggles |
| `StatusDot` | 8 px coloured circle | Cell status, dive type, sync state |
| `BezelPanel` | A panel with bezel outline, no background | Used to wrap charts, longitudinal views |

`StarRating` already exists; we re-theme it but don't move it.

## Widgetbook (dev-only)

A new route `/dev/widgetbook` rendered by `lib/ui/dev/widgetbook_screen.dart`. Lists every component in `lib/ui/components/` with:

- All its states (default, hover, focused, disabled, error).
- A side-by-side "specimen" — actual usage with realistic dive data so we can see how it reads in context.
- Hidden behind a long-press on the app version label in Settings (so it's not in the regular nav). Compiles unconditionally — the cost is trivial and having it in release builds means we can iterate on a TestFlight build without re-installing.

## Dive Detail showcase

After the tokens and library land, we refactor `lib/ui/screens/dive_detail_screen.dart` to consume them. Concretely:

1. **Stat row** uses `StatTile` + `NumericReadout.md` for each value. The current ad-hoc `_statCell` / `_avgMinMaxCell` / `_descAscCell` etc. get rewritten in terms of `StatTile` so the spacing and typography are consistent.
2. **Profile chart** background switches to `surface.bg` with `chart.grid` lines; depth trace uses `chart.trace.depth`, PPO2 uses `chart.trace.ppo2`, etc. The crosshair overlay uses `accent.primary`.
3. **AppBar title** uses `display` style with a small `caption` subtitle showing the dive's site / date.
4. **Section headers** (PPO2, Cells, Deco, Tank, etc.) use `SectionHeader`.
5. **Tab bar** at the bottom gets `accent.primary` for the active tab indicator with the sodium-vapor colour instead of cyan.

The Information tab we just shipped already uses a similar pattern; the new `DataRow` lifts the inline `_readOnlyRow` into the library and the section headers + star rows get re-themed automatically.

## Files (anticipated)

- **Theme + tokens:**
  - `lib/ui/theme/app_theme.dart` — rewritten, exports `AppTheme.dark()` + tokens.
  - `lib/ui/theme/tokens.dart` — new, `AppColors`, `AppTypography`, `Spacing`, `Radii`, `Elevation`, `Motion` (pure constants + helpers).
- **Components:**
  - `lib/ui/components/app_card.dart`
  - `lib/ui/components/stat_tile.dart`
  - `lib/ui/components/numeric_readout.dart`
  - `lib/ui/components/section_header.dart`
  - `lib/ui/components/data_row.dart`
  - `lib/ui/components/accent_button.dart`
  - `lib/ui/components/ghost_button.dart`
  - `lib/ui/components/icon_chip.dart`
  - `lib/ui/components/status_dot.dart`
  - `lib/ui/components/bezel_panel.dart`
- **Fonts:**
  - `fonts/Inter-VariableFont.ttf`
  - `fonts/JetBrainsMono-VariableFont.ttf`
  - `pubspec.yaml` font declarations
- **Widgetbook:**
  - `lib/ui/dev/widgetbook_screen.dart`
  - Settings screen edit: long-press handler on the app version label.
- **Showcase refactor:**
  - `lib/ui/screens/dive_detail_screen.dart` — adopt the new components.

Total: ~12 new files, ~3 edited.

## Tests

- **Golden tests** for each new component (`test/ui/components/*_golden_test.dart`). Default state only — captures the visual baseline; future changes show up as diffs in the goldens.
- **Widget tests** for `StatTile`, `DataRow`, `NumericReadout` (the ones with logic / variants).
- **Existing widget tests** — must still pass after the Dive Detail refactor. The information section test already covers the labels-and-rows behaviour; we should not need new tests if we're careful.

Existing `test/ui/widgets/*` tests assert on `find.text('Max')` and similar — those will continue to pass because we're changing typography, not labels. If a test asserts on a specific colour or pixel layout it'll need updating; spot-check during implementation.

## Light mode breadcrumb (deferred)

The token file structures the palette as a `ThemePalette` object so adding a second instance (`ThemePalette.tropical()` etc.) is mechanical. The `ColorScheme` is derived from the palette via a single helper. When we want light mode, we add a new palette + a `themeMode` setting + a system listener. No rework of components — they read tokens, not hex codes directly.

## Open questions for review

None blocking — every decision is locked above. Worth confirming before implementation:

1. Pinning the **cell colour assignment** (green/blue/pink in that order, applied across all cell visualisations). If you prefer a different colour per cell, say so before goldens get generated.
2. The **app version label long-press to access Widgetbook** — happy with that as the hidden entry point? Alternatives: a debug flag in `--dart-define`, or always-visible in Settings → Developer.
