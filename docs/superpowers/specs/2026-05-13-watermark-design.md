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

- **Source:** user generated externally via an AI image tool. Image
  composition matches the original t-shirt reference: surfacing CCR
  diver, front view, white line art with halftone shading, water
  ripples + reflection.
- **Format:** PNG, **solid black background** (NOT transparent — the
  AI tool returned it black-on-black-bg, which is fine; the render
  layer compensates).
- **Resolution:** ~1024×1024 px, scales cleanly on retina displays.
- **Path:** `assets/images/watermark.png` (user adds the file manually
  before this track's first implementation task runs — drag from
  Finder into the project).

## Rendering — black background, blend-mode compositing

The image's black background can't be pre-masked (we want a single
asset, no manual remove.bg step). At render time we composite the
image using `BlendMode.screen` against its parent layer — screen blend
formula `result = 1 − (1 − dst) × (1 − src)` makes black pixels
transparent (src=0 → result=dst) and lifts white pixels onto the
background unchanged.

Flutter's `Image.asset` widget doesn't expose a blend-mode-against-parent
parameter (only `colorBlendMode` which blends image with the `color`
property), so we need a small custom `BlendMask` widget that drops into
its own `saveLayer` with the chosen blend mode.

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

### New files

**`lib/ui/widgets/blend_mask.dart`** — generic helper that composites a
child with a chosen `BlendMode` against its parent layer (Flutter
standard recipe for "blend my child against the background"):

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Composites [child] using [blendMode] against its parent's pixels,
/// at the chosen alpha. Use to apply blend modes (e.g. screen, plus)
/// that Flutter's stock `Image.asset(colorBlendMode:)` can't reach —
/// those blend the image with a colour, not with what's behind it.
class BlendMask extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  final double opacity;

  const BlendMask({
    super.key,
    required this.blendMode,
    required this.opacity,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlendMask(blendMode, opacity);

  @override
  void updateRenderObject(BuildContext context, _RenderBlendMask r) {
    r.blendMode = blendMode;
    r.opacity = opacity;
  }
}

class _RenderBlendMask extends RenderProxyBox {
  BlendMode blendMode;
  double opacity;
  _RenderBlendMask(this.blendMode, this.opacity);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.saveLayer(
      offset & size,
      Paint()
        ..blendMode = blendMode
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    super.paint(context, offset);
    context.canvas.restore();
  }
}
```

**`lib/ui/widgets/background_watermark.dart`** — composes
`BlendMask` + `Image.asset`:

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
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.6,
                heightFactor: 0.6,
                child: BlendMask(
                  blendMode: BlendMode.screen,
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
      ],
    );
  }
}
```

Note the Stack child order has flipped vs. the v1 spec: with `Opacity`
the watermark went behind because we wanted it under the content; with
`BlendMode.screen` it goes **on top** of the content so it composites
*against* the rendered content as the destination. Screen blend keeps
the brighter pixel — for the watermark's white lines that's the white;
for the watermark's black background that's whatever the app rendered
underneath. Net: line art glows faintly over the content, black
background is fully transparent. `IgnorePointer` ensures taps still
reach the content layer underneath.

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

- `test/ui/widgets/blend_mask_test.dart`:
  - Builds with a `BlendMode.screen` + opacity 0.5 and a coloured child
  - Asserts the render tree contains a `_RenderBlendMask` with the
    expected `blendMode` and `opacity` properties
  - Updates: changing the props on the widget propagates to the
    render object
- `test/ui/widgets/background_watermark_test.dart`:
  - Renders nothing extra when `opacity == 0` (no image in the tree)
  - When `opacity > 0`, the tree contains a `BlendMask` with
    `blendMode == BlendMode.screen` wrapping an `Image`
  - `IgnorePointer` wraps the watermark so taps fall through to the
    child layer
- `test/ui/notifiers/settings_notifier_test.dart` — extend with
  watermark-opacity round-trip test (defaults to 0.06, persists
  across reload, no-ops on identical value, clamps to 0..0.20 range)

## Risks

- **Asset missing in tests** — the PNG must be present at
  `assets/images/watermark.png` for any widget test that triggers the
  watermark. Test fix: tests that don't care construct the
  `SettingsNotifier` with `watermarkOpacity = 0` so the image-load path
  is skipped entirely (no asset bundle lookup).
- **`saveLayer` cost per build.** `BlendMask` calls `saveLayer` once
  per paint. For a static asset on a screen that rebuilds rarely this
  is negligible (<1 ms on modern devices). If watermark ever becomes
  animated or appears on a heavily-rebuilding screen, profile first.
- **Future light theme.** `BlendMode.screen` blends the image's
  whites onto whatever's underneath. On a light theme background the
  watermark's white lines would become invisible (1 ∨ 1 = 1, no
  contrast). When a light theme lands, either:
  (a) switch the watermark image to a black-line-art version + use
  `BlendMode.multiply` on light theme, or
  (b) keep the white image but use `BlendMode.darken` on light theme
  (less ideal — line art renders as the line art's white over the
  light bg, which is still invisible). Out of scope for v1; flagged
  here so the next visual-redesign session knows what to do.

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
