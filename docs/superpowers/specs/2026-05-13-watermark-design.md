# Background Watermark — Design Spec

**Date:** 2026-05-13
**Track:** A of the four-track 2026-05-13 wishlist.
**Source request:** User wants a subtle watermark behind every view to encapsulate the "technical CCR diver" intent.

## Goal

Render a single white, low-opacity illustration behind every Scaffold body
in the app, anchored centrally, so the app's CCR-diving identity is
constant background context without competing with content.

## Why

The app currently has no visual identity beyond the colour palette
("Wreck") and the instrument aesthetic. The brand is implicit. A
watermark gives a constant visible cue: "this is a tech CCR diving tool,
not a generalist log."

## Asset

- **Source:** user generates externally via an AI image tool
  (Bing Image Creator / Google ImageFX / Krea / etc.) using a prompt
  matching the t-shirt reference style (surfacing CCR diver, front view,
  white line art on transparent background, illustrator quality).
- **Format:** single PNG with transparent background (preferred) or SVG
  if the AI tool exports vector
- **Resolution:** at least 1200×1200 px so it stays crisp on retina
  displays. Larger is fine — Flutter scales down cleanly
- **Colour:** pure white line art on transparent; opacity controlled at
  render time via the theme

## Placement + opacity

- **Where:** behind the `Scaffold.body` of every top-level screen
  (DiveListScreen body, DiveDetailPager body, EquipmentLandingScreen,
  SettingsScreen, SitesMapScreen body, ImportScreen body)
- **Anchor:** centred, fixed (not scrolling with content)
- **Size:** scales to fit ~60% of the shorter screen dimension (so it's
  always centred and never overlaps the AppBar or BottomNavigationBar)
- **Opacity:** **6%** as the default. Below 5% it disappears on AMOLED
  + brightness-reduced phones; above 10% it competes with text. Single
  Settings entry `watermarkOpacity` (range 0–20%, default 6%) so the
  user can tune.
- **Off mode:** opacity = 0 hides it. No separate boolean flag needed —
  the slider going to zero is the "off."

## Implementation surface

### New file

`lib/ui/widgets/background_watermark.dart` — a small `StatelessWidget`:

```dart
class BackgroundWatermark extends StatelessWidget {
  final Widget child;
  final double opacity;

  const BackgroundWatermark({
    super.key,
    required this.child,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.6,
                heightFactor: 0.6,
                child: Opacity(
                  opacity: opacity,
                  child: Image.asset(
                    'assets/images/watermark.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
```

### Files modified

- `pubspec.yaml` — add `assets/images/watermark.png` to the assets block
- `assets/images/watermark.png` — new asset file (user-provided)
- `lib/ui/notifiers/settings_notifier.dart` — add `double get watermarkOpacity` + `Future<void> setWatermarkOpacity(double v)`, SharedPreferences key `watermark_opacity`, default `0.06`
- `lib/ui/app_shell.dart` — wrap the IndexedStack body in `BackgroundWatermark` reading opacity from `widget.settingsNotifier`. ListenableBuilder so opacity changes rebuild
- `lib/ui/screens/settings_screen.dart` — add a slider row "Watermark opacity" (0–20%) writing to the notifier
- `lib/ui/screens/dive_detail_pager.dart` — same wrap on its Scaffold body (since the pager has its own Scaffold, not under AppShell's IndexedStack)
- `lib/ui/screens/sites_map_screen.dart` — same
- `lib/ui/screens/settings_screen.dart` — same
- `lib/ui/screens/import_screen.dart` — same

### Tests

- `test/ui/widgets/background_watermark_test.dart`:
  - Renders nothing extra when `opacity == 0` (image not in the tree)
  - Renders the image inside an `Opacity` widget when `opacity > 0`
  - `IgnorePointer` wraps the image so taps fall through
- `test/ui/notifiers/settings_notifier_test.dart` — extend with watermark round-trip test (defaults to 0.06, persists across reload, no-ops on identical value)

## Risks

- **Asset missing in tests** — the PNG would need to be present for any
  widget test that triggers the watermark. Test fix: tests that don't
  care construct the SettingsNotifier with `watermarkOpacity = 0` so the
  image-load path is skipped.
- **Performance on Android** — `Opacity` widget forces a saveLayer. For
  a single static image this is negligible, but worth noting if we ever
  add motion to the watermark (we won't in v1).

## Out of scope for v1

- Per-screen watermark variants (one static image, used everywhere)
- Light/dark theme variants (single white-on-transparent works for both
  since the app is currently dark-only)
- Animation, parallax, scale-with-scroll
- Multiple watermark images selectable in Settings

## Definition of done

1. `assets/images/watermark.png` committed (user provides)
2. `BackgroundWatermark` widget + test
3. SettingsNotifier `watermarkOpacity` field + Settings slider
4. Six screen-body wraps in production code
5. `flutter analyze` clean + full test suite passes
6. Manual smoke: open every tab, verify the watermark is visible at the
   centre of each body, doesn't interfere with taps, and disappears
   when the Settings slider goes to 0
