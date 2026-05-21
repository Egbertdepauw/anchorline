# Claude Code brief — wire Anchorline branding into the CCRLog Flutter app

## Context
This is a Dart/Flutter project (the app is being branded "Anchorline" — a dive-logging app
for CCR / deep-wreck divers). I have a set of brand assets (SVGs + PNGs) to integrate. Please
wire them in idiomatically for Flutter, covering: (1) SVG marks rendered in-app, (2) the
brand color palette as a Dart theme, and (3) platform launcher icons (iOS + Android, and web
if the project has a web target).

Work in Plan Mode first: inspect the project, propose the changes, and let me approve before
editing. Do NOT change app logic or unrelated files.

## Assets I will place
These are the **final, refined vector marks** (produced in Recraft from the approved design
spec — solid weighted flukes, ring-and-dot buoy, curved stock). I will copy them into
`assets/brand/` (create it if absent):
- `anchorline-mark-full.svg`     — full mark (buoy + descent line + anchor) on dark tile. Splash/large.
- `anchorline-mark-icon.svg`     — simplified anchor only, on dark tile. Small/compact UI.
- `anchorline-mark-inline.svg`   — transparent background, all-orange anchor. In-app UI on any bg.
- `anchorline-wordmark-dark.svg` — horizontal lockup for DARK backgrounds (white anchor body + text).
- `anchorline-wordmark-light.svg`— horizontal lockup for LIGHT backgrounds (dark anchor body + text).
- `launcher-1024.png`            — 1024×1024 master, full mark on dark tile (for app icon).
- `adaptive-foreground-1024.png` — 1024×1024 transparent foreground (Android adaptive icon).

NOTE on the inline/wordmark SVGs: unlike the earlier hand-drawn drafts, these refined marks have
their colors baked in as filled paths (the anchor body is NOT `currentColor`). See task 4.

(If any are missing when you run, list what's missing and proceed with what's present.)

## Brand palette (exact)
- Hull black:        `#0A1419`  (primary dark surface / icon background)
- Reel orange:       `#C97B3A`  (primary accent — buoy, line, flukes)
- Surface white:     `#E4E9E6`  (anchor body / light foreground)
- Slack-water steel: `#3A6477`  (secondary accent)

## Tasks

### 1. Dependencies
Add to `pubspec.yaml` and run `flutter pub get`:
- `flutter_svg` (latest stable) — runtime SVG rendering.
- `flutter_launcher_icons` (latest stable, dev_dependency) — generates platform app icons.
Check for version conflicts with the existing Dart SDK constraint before adding; if a conflict
exists, pick the highest compatible versions and tell me.

### 2. Register assets
In `pubspec.yaml` under `flutter:`, register the brand asset directory:
```yaml
  assets:
    - assets/brand/
```
Preserve any existing `assets:` entries — append, don't overwrite.

### 3. Brand palette as Dart
Create `lib/theme/anchorline_colors.dart` with an abstract/const class exposing the four
colors above as `Color(0xFF…)` constants (e.g. `AnchorlineColors.hullBlack`, `.reelOrange`,
`.surfaceWhite`, `.slackSteel`). Then wire these into the app's existing theme:
- Find where `ThemeData` / `ColorScheme` is defined.
- Use `reelOrange` as the seed/primary accent and `hullBlack` as the dark scaffold/surface,
  WITHOUT discarding existing typography or component themes. Show me a diff; don't silently
  restructure the theme. If the app already has a strong theme, propose minimal wiring only.

### 4. Reusable logo widget
Create `lib/widgets/anchorline_logo.dart` exposing a small widget API, e.g.:
```dart
enum AnchorlineMark { full, icon, inline, wordmarkDark, wordmarkLight }
class AnchorlineLogo extends StatelessWidget {
  final AnchorlineMark mark;
  final double? size;      // height in logical px
  ...
}
```
- Render via `flutter_svg`'s `SvgPicture.asset`, mapping each enum value to its asset path
  (`wordmarkDark` → `anchorline-wordmark-dark.svg`, `wordmarkLight` → the light one, etc.).
- IMPORTANT: these refined SVGs have colors baked into their paths, so do NOT apply a global
  `colorFilter` (it would flatten the multi-color mark to one color). Render them as-is.
  Pick `wordmarkDark` vs `wordmarkLight` based on the surface the logo sits on. The `inline`
  mark is all-orange on transparent and works on either background.
- Handle null `size` sensibly (intrinsic). Add a doc comment with usage examples.

### 5. Launcher icons
Configure `flutter_launcher_icons` (in `pubspec.yaml` or `flutter_launcher_icons.yaml`):
```yaml
flutter_launcher_icons:
  image_path: "assets/brand/launcher-1024.png"
  android: true
  ios: true
  remove_alpha_ios: true
  adaptive_icon_background: "#0A1419"
  adaptive_icon_foreground: "assets/brand/adaptive-foreground-1024.png"
  # web/windows/macos: enable ONLY if those targets exist in this project
```
Then run the generator (`dart run flutter_launcher_icons`) and report what it produced.
Detect which platform folders actually exist (`android/`, `ios/`, `web/`, etc.) and only enable
those targets. Do not create new platform targets.

NOTE: the supplied `adaptive-foreground-1024.png` is the all-orange anchor on transparent, which
sits on the `#0A1419` adaptive background → orange anchor on near-black. This is intentional and
looks clean under Android's icon masking. (The iOS/legacy icon from `launcher-1024.png` uses the
white-body + orange-flukes mark on the tile.) If I later ask for the adaptive icon to match the
launcher's white-body look instead, that's a foreground swap only.

### 6. (Web target only — skip if no `web/` folder)
If `web/` exists: update `web/manifest.json` `theme_color`/`background_color` to `#0A1419`,
and replace the favicon with a 32×32 PNG derived from `anchorline-mark-icon.svg` if convenient.
This is optional and lowest priority.

## Verification
- Run `flutter pub get` and `flutter analyze`; report and fix any new analyzer issues YOU
  introduced (don't touch pre-existing unrelated warnings).
- Confirm the app still builds (`flutter build` for an available platform, or at least
  `flutter analyze` clean) — don't leave the project broken.
- Show me: the pubspec diff, the new files, the theme wiring diff, and the launcher-icon output.

## Constraints
- Plan first, edit after approval.
- Minimal, reversible changes; no refactors beyond what's listed.
- Don't commit anything; leave that to me.
- If anything is ambiguous (e.g. theme is already heavily customized), ask rather than guess.
