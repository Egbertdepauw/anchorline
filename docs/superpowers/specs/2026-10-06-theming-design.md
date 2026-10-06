# Selectable themes — design

Date: 2026-10-06
Status: approved 2026-10-06; amended the same day after computing the
palettes (cells/PPO2 rule, GF-red contrast exception, painter scope)

## Goal

Let the user pick the app's colour theme in Settings. The first version
ships six dark themes: the current look (**Wreck**, stays the default) plus
five themes taken from Omarchy Linux: **Ethereal**, **Retro 82**,
**Catppuccin**, **Hackerman**, **Miasma**.

Success means:

- Picking a theme recolours the whole app immediately, charts included.
- The app starts in the chosen theme with no flash of Wreck.
- Wreck looks exactly as it does today.
- Colours that carry safety meaning look the same in every theme.
- Adding another theme later is one palette definition plus one registry
  entry.

## Decisions

| Question | Decision |
|---|---|
| Do meaning-carrying colours follow the theme? | No. Status colours and GF bands are fixed across themes. Cell and trace colours follow the theme only where they stay distinguishable. |
| Which themes ship first? | Wreck + Ethereal, Retro 82, Catppuccin, Hackerman, Miasma. |
| Does the choice sync across devices? | No. Stored per device in local preferences, like every other setting today. |
| How do widgets read the active palette? | From the Flutter theme (a `ThemeExtension`), not from a global. |
| What does a theme change? | Colours only. Typography, spacing, radii and motion are untouched. |

## Out of scope

- The rest of Omarchy's themes, and any light theme. Planned as a later
  stage; this design must not block it (see "Later stage").
- Syncing settings across devices. If done, it should cover all settings
  as its own project.
- Fonts, spacing, shape, wallpapers, icons.
- A custom-theme editor.

## Current state

- One palette, `AppColors.wreck`, in `lib/ui/theme/tokens.dart`.
  `MaterialApp` is fixed to `AppTheme.dark()` (`lib/main.dart`).
- No theme setting exists. `SettingsNotifier` stores settings in
  `SharedPreferences`; `main()` awaits `settings.load()` before `runApp`.
- 95 call sites read `AppColors.wreck.<token>` directly.
- Outside `lib/ui/theme/` there are about 90 `Color(0x…)` literals in 18
  files and 137 `Colors.*` uses in 26 files. `profile_chart.dart` is the
  heaviest.
- Six files define a `CustomPainter`.

## Design

### 1. Theme system

**`ThemePalette`** (`lib/ui/theme/tokens.dart`) remains the app's colour
token set and becomes a `ThemeExtension<ThemePalette>` (with `copyWith` and
`lerp`) so it travels inside `ThemeData`. The four `status*` tokens leave
it (section 2). All other existing tokens stay.

**Theme registry** (new, `lib/ui/theme/app_themes.dart`): the list of
available themes. Each entry has

- a stable id used for persistence: `wreck`, `ethereal`, `retro82`,
  `catppuccin`, `hackerman`, `miasma`;
- a display name;
- its `ThemePalette`.

It exposes lookup by id that returns Wreck for an unknown or missing id.

**Omarchy source colours** (new, `lib/ui/theme/omarchy/`): one small file
per Omarchy theme holding the values from that theme's `colors.toml`
unchanged, as a const `OmarchyColors` value. One shared mapping function
turns an `OmarchyColors` into a `ThemePalette` (section 2). Wreck is not
expressed this way; it keeps its hand-written palette.

**`AppTheme.build(ThemePalette)`** replaces `AppTheme.dark()`. It builds
`ThemeData` exactly as today (colour scheme, text theme, app bar, and the
rest) from the palette it is given, and attaches the palette as an
extension. All six themes use `Brightness.dark`.

**`context.palette`**: a `BuildContext` extension returning the active
`ThemePalette`.

**Data flow**

1. `SettingsNotifier` gains a theme id, persisted under a new preference
   key. Unknown or missing values resolve to Wreck.
2. `main()` already loads settings before the first frame, so the first
   frame uses the chosen theme.
3. `MaterialApp` is rebuilt from the settings notifier, so a change of id
   swaps `ThemeData`. Flutter animates between the two themes via `lerp`.
4. Widgets read `context.palette`. `CustomPainter`s have no context: the
   owning widget passes the palette in, and `shouldRepaint` returns true
   when it changes.

**Picker**: a new "Appearance" section in `settings_screen.dart` with one
row per registered theme: display name plus a swatch strip (background,
card, primary text, accent). The active theme is marked. Tapping a row
applies it immediately.

### 2. Palette mapping and safety colours

**Fixed safety colours** (new, `lib/ui/theme/safety_colors.dart`): shared
by every theme, values unchanged from today.

| Colour | Value today | Source today |
|---|---|---|
| Status success | `#4ADE80` | `ThemePalette.statusSuccess` |
| Status warning | `#F39C12` | `ThemePalette.statusWarning` |
| Status danger | `#E74C3C` | `ThemePalette.statusDanger` |
| Status info | `#60A5FA` | `ThemePalette.statusInfo` |
| GF within limits | `#4ADE80` | `gf_color.dart` |
| GF over GF-high | `#F59E0B` | `gf_color.dart` |
| GF over 100 | `#DC2626` | `gf_color.dart` |

The two ambers and two reds differ slightly today. They are kept as they
are; unifying them is not part of this work.

**Known contrast shortfall.** Every safety colour is at least 3:1 against
every theme's `surfaceBg`. Against `surfaceCard`, all pass except "GF over
100" red (`#DC2626`) on Catppuccin (2.6:1) and Miasma (2.9:1), whose cards
are lighter than Wreck's (3.4:1 there). The values stay unchanged; the
test records these two as named exceptions with a 2.5:1 floor so no other
shortfall can slip in.

**Mapping an Omarchy theme onto the tokens**

| `ThemePalette` token | Omarchy colour |
|---|---|
| `surfaceBg` | `background` |
| `surfaceCard` | `lighter_background` |
| `surfaceRaised` | `selection` |
| `surfaceBezel` | `muted` |
| `textPrimary`, `chartTraceDepth` | `foreground` |
| `textSecondary`, `chartTraceSetpoint` | `light_foreground` |
| `textMuted` | `dark_foreground` |
| `textInverse` | `background` |
| `accentPrimary` | `accent` |
| `accentMuted` | `accent` blended 50% toward `background` |
| `chartGrid` | midpoint of `surfaceCard` and `surfaceRaised` |
| `cell1`, `cell2`, `cell3` | `green`, `blue`, `magenta`, or Wreck defaults (below) |
| `chartTraceGf99` | same as `cell3` |
| `chartTracePpo2` | `yellow`, or Wreck default (below) |

**Readability floor.** Some Omarchy values are meant for terminal
decoration, not body text (Miasma's `dark_foreground` `#555555` on
`#222222` is roughly 2:1). After mapping, each text token is checked
against both `surfaceBg` and `surfaceCard` using the WCAG contrast ratio:

- `textPrimary`, `textSecondary`: at least 4.5:1
- `textMuted`: at least 3:1

A token that fails is blended toward `foreground` in small steps until it
passes. The adjustment happens in the mapping function, so the stored
Omarchy values stay untouched.

**Cells and the PPO2 / GF99 traces.** Two groups, each decided
independently per theme:

- **Cells group** (`cell1`, `cell2`, `cell3`, and `chartTraceGf99`, which
  shares `cell3`'s colour as it does in Wreck). The theme uses its own
  `green`, `blue`, `magenta` only if each is at least 3:1 against
  `surfaceCard` and the three are pairwise distinguishable: a CIEDE2000
  difference of at least 20. Otherwise it takes Wreck's (`#4ADE80`,
  `#60A5FA`, `#F472B6`).
- **PPO2** (`chartTracePpo2`). The theme uses its own `yellow` only if it
  is at least 3:1 against `surfaceCard` and has a CIEDE2000 difference of
  at least 15 from both `chartTraceDepth` and `chartTraceSetpoint`, and
  from each of the theme's three final cell colours (they share the PPO2
  axis). Otherwise it takes Wreck's `#FFCC66`.

Each theme's source file states both choices explicitly, and a test
verifies that the stated choices satisfy the rules and that whatever a
theme ends up with (own or default) also passes them. Computed outcome
(2026-10-06):

| Theme | Cells group | PPO2 |
|---|---|---|
| Ethereal | own (closest pair 21.4) | own (17.4 / 18.8 from depth / setpoint) |
| Retro 82 | default (blue = magenta) | own (27.6 / 38.9) |
| Catppuccin | own (closest pair 28.0) | own (30.7 / 31.1) |
| Hackerman | default (blue vs magenta 3.2) | default (own is 14.7 from cell 1) |
| Miasma | default (green vs blue 9.5) | own (30.6 / 23.0) |

The cell check was added after the stage 1 code review: Hackerman's own
PPO2 teal passed the depth/setpoint check but sat too close to cell 1.

Why two groups and a lower PPO2 threshold: Ethereal and Retro 82 have
cream foregrounds, so Wreck's default PPO2 yellow sits too close to their
depth trace (15.3 and 10.8) to serve as a fallback, and no warm colour in
Ethereal reaches 20 from its depth trace. Wreck itself is at 28.9.

**Accepted trade-off.** A theme's accent may resemble a safety colour
(Hackerman's accent `#82FB9C` vs success green; Retro 82's `#faa968` vs
warning amber). Wreck already has an orange accent beside amber warnings.
Theme accents are not altered.

**Omarchy source values** (from `basecamp/omarchy`,
`themes/<name>/colors.toml`, read 2026-10-06; all five are `mode = "dark"`):

| | Ethereal | Retro 82 | Catppuccin | Hackerman | Miasma |
|---|---|---|---|---|---|
| `accent` | `#7d82d9` | `#faa968` | `#89b4fa` | `#82FB9C` | `#78824b` |
| `selection` | `#252e56` | `#134e5a` | `#45475a` | `#1f253a` | `#383838` |
| `muted` | `#6d7db6` | `#2a6b78` | `#585b70` | `#2d3450` | `#666666` |
| `background` | `#060B1E` | `#05182e` | `#1e1e2e` | `#0B0C16` | `#222222` |
| `lighter_background` | `#131a3a` | `#0a2540` | `#313244` | `#151828` | `#2c2c2c` |
| `foreground` | `#ffcead` | `#f6dcac` | `#cdd6f4` | `#ddf7ff` | `#c2c2b0` |
| `light_foreground` | `#c9b8a6` | `#a7c9c6` | `#bac2de` | `#b5c5db` | `#8a8a7e` |
| `dark_foreground` | `#6d7db6` | `#3f8f8a` | `#6c7086` | `#6a6e95` | `#555555` |
| `green` | `#92a593` | `#028391` | `#a6e3a1` | `#4fe88f` | `#5f875f` |
| `blue` | `#7d82d9` | `#3f8f8a` | `#89b4fa` | `#829dd4` | `#78824b` |
| `magenta` | `#c89dc1` | `#3f8f8a` | `#f5c2e7` | `#86a7df` | `#bb7744` |
| `yellow` | `#E9BB4F` | `#e97b3c` | `#f9e2af` | `#50f7d4` | `#b36d43` |

The remaining `colors.toml` fields (`dark_background`, `darker_background`,
`bright_*`, `red`, `orange`, `cyan`, `brown`) are stored in the source
files for completeness but not used by the mapping.

### 3. Migration and staging

Two stages, each its own issue, branch and PR.

**Stage 1 — theme system and tokenised colours**

- Everything in sections 1 and 2.
- The 95 `AppColors.wreck.<token>` call sites move to
  `context.palette.<token>`; `status*` reads move to the fixed safety set.
  Call sites inside `const` expressions lose `const`.
- Of the six `CustomPainter` files, only `profile_chart.dart` and
  `cell_data_chart.dart` read tokens today; their painters take the
  palette colours as constructor arguments. `cell_mv_chart.dart` holds
  six literals commented as copies of tokens; those move to the palette
  in this stage too. The other three painters have only loose literals
  and belong to stage 2.
- `AppColors.wreck` remains only as the registry's Wreck entry.
- The picker is shown only in debug builds (`kDebugMode`).

After stage 1, switching themes recolours everything that uses tokens.
Loose literals still show Wreck-like colours, which is why the picker is
not yet visible in release builds.

**Stage 2 — sweep the loose colours**

Each `Color(0x…)` literal and `Colors.*` use outside `lib/ui/theme/` is
sorted into one of four kinds:

| Kind | Example | Action |
|---|---|---|
| Safety | red/amber in gas safety readouts | use the fixed safety set |
| Chrome | a border or label colour written as a literal | use a palette token |
| Data encoding | dive-mode colours, tissue heatmap gradient, speed-coloured graph | stays fixed, as named constants under `lib/ui/theme/` |
| Neutral | `Colors.transparent`, shadow and overlay blacks | left as is |

- A new palette token is added only where a chrome colour has no existing
  token to map to; it then needs a value in the mapping and in Wreck.
- The files split into three non-overlapping groups — chart widgets, dive
  detail, remaining screens and widgets — suitable for three parallel
  build agents.
- A guard test fails on colour literals outside `lib/ui/theme/`, with a
  short allowlist for the neutral cases.
- Last step: remove the `kDebugMode` gate so the picker is visible to all.

### 4. Testing

**Unit tests (pure colour logic)**

- Mapping: each Omarchy theme's palette has the expected background,
  card, text and accent values.
- Readability floor: every registered theme meets the contrast minimums
  on both `surfaceBg` and `surfaceCard`.
- Safety colours: each is at least 3:1 against every theme's `surfaceBg`
  and `surfaceCard`, except the two named GF-red exceptions in section 2
  (floor 2.5:1).
- Cells and traces: every theme's stated choices satisfy the rules in
  section 2, and so do the colours it ends up with.
- Registry: ids are unique; unknown id resolves to Wreck; Wreck's palette
  is value-for-value identical to today's.

**Settings tests**

- The theme id is saved and restored.
- A missing or unknown stored id yields Wreck without throwing.

**Widget tests**

- `AppTheme.build` attaches the palette and `context.palette` returns it.
- Changing the setting swaps the app's theme.
- The picker lists all registered themes, marks the active one, and
  applies a tap.
- One chart painter repaints when the palette changes.

**Guard test** (end of stage 2), as in section 3.

**Manual check.** At the end of each stage: a macOS run through the dive
list, a CCR dive detail (profile chart and cell chart), the planner and
Settings, in all six themes.

### 5. Failure handling

The only runtime failure point is reading the stored theme id; it falls
back to Wreck. Palettes are compile-time constants, so nothing is loaded
or parsed at runtime.

## Later stage (not part of this work)

Remaining Omarchy themes, including light ones. What this design leaves
ready for it:

- Adding a dark theme is one `OmarchyColors` file and one registry entry;
  the tests in section 4 cover it automatically.
- Light themes additionally need: brightness taken from the theme's
  `mode` instead of fixed dark, safety and data-encoding colours checked
  (and possibly given light variants) against light backgrounds, and a
  review of the neutral shadow/overlay colours.
