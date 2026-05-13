# Watermark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a subtle CCR-diver watermark behind every top-level screen at user-adjustable opacity (default 6%). The watermark image has a solid black background, composited via `BlendMode.screen` so black pixels become transparent and white line art lifts onto the dark theme as a faint glow.

**Architecture:** A small reusable `BlendMask` widget wraps a child in a `saveLayer` with a chosen blend mode. `BackgroundWatermark` composes `BlendMask(screen)` + `Image.asset` and wraps screen bodies via `Stack`. `SettingsNotifier` gains a `watermarkOpacity` field (SharedPreferences-persisted) so the user can tune visibility from a Settings slider.

**Tech Stack:** Flutter, flutter_test, shared_preferences

**Spec:** [docs/superpowers/specs/2026-05-13-watermark-design.md](../specs/2026-05-13-watermark-design.md)

---

## Task 1: Add the asset + register in pubspec

**Files:**
- Already present: `assets/images/watermark.png` (user added)
- Modify: `pubspec.yaml` (assets block)

- [ ] **Step 1: Verify the asset file exists**

```bash
ls -la assets/images/watermark.png
```
Expected: file shown, size ≥ 100 KB.

- [ ] **Step 2: Register the asset in `pubspec.yaml`**

Find the `flutter:` section. If it has an `assets:` list already, add the new line. If not, add the whole block.

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/watermark.png
```

- [ ] **Step 3: Run pub get + verify asset bundle**

Run: `flutter pub get`
Expected: completes cleanly.

Run: `flutter analyze --no-pub`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml assets/images/watermark.png
git commit -m "$(cat <<'EOF'
chore(assets): add watermark.png + register in pubspec

CCR-diver background watermark. Used in Track A by the BackgroundWatermark
widget, composited via BlendMode.screen so the black background renders
as transparent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Build the `BlendMask` widget + tests

**Files:**
- Create: `lib/ui/widgets/blend_mask.dart`
- Create: `test/ui/widgets/blend_mask_test.dart`

- [ ] **Step 1: Write the failing test first**

Create `test/ui/widgets/blend_mask_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/blend_mask.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BlendMask wraps its child in a render object with the given blendMode + opacity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BlendMask(
        blendMode: BlendMode.screen,
        opacity: 0.5,
        child: SizedBox(width: 40, height: 40),
      ),
    ));
    final renderObject =
        tester.renderObject(find.byType(BlendMask));
    // We don't expose the private render-object class; we assert the
    // widget rendered without throwing and the SizedBox child is present.
    expect(renderObject, isNotNull);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('BlendMask updates its render object when blendMode changes',
      (tester) async {
    Widget build(BlendMode mode) => MaterialApp(
          home: BlendMask(
            blendMode: mode,
            opacity: 0.5,
            child: const SizedBox(width: 40, height: 40),
          ),
        );
    await tester.pumpWidget(build(BlendMode.screen));
    await tester.pumpWidget(build(BlendMode.multiply));
    // Reaching here without exceptions means the updateRenderObject path
    // worked. We can't assert the private render object's properties
    // directly without exposing them.
    expect(find.byType(BlendMask), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to confirm failure**

Run: `flutter test test/ui/widgets/blend_mask_test.dart`
Expected: FAIL — compile error `The class 'BlendMask' isn't defined`.

- [ ] **Step 3: Implement `BlendMask`**

Create `lib/ui/widgets/blend_mask.dart`:

```dart
/// Composites a child using a chosen [BlendMode] against its parent's
/// pixels, at the chosen alpha. Use to apply blend modes (e.g. screen,
/// plus) that Flutter's stock `Image.asset(colorBlendMode:)` can't
/// reach — those blend the image with a colour, not with what's behind
/// it.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/widgets/blend_mask_test.dart`
Expected: 2/2 pass.

- [ ] **Step 5: Run full suite + analyze**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes (no other test affected).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/blend_mask.dart test/ui/widgets/blend_mask_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): BlendMask widget for parent-blend-mode compositing

Standard Flutter recipe — RenderProxyBox subclass that calls saveLayer
with a chosen BlendMode. Lets us composite a child against the parent's
pixels using modes (screen, plus, multiply) that Image.asset's
colorBlendMode can't reach (that one blends with a colour, not with the
backdrop). Used by the watermark in Task 3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Build the `BackgroundWatermark` widget + tests

**Files:**
- Create: `lib/ui/widgets/background_watermark.dart`
- Create: `test/ui/widgets/background_watermark_test.dart`

- [ ] **Step 1: Write the failing test first**

Create `test/ui/widgets/background_watermark_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/background_watermark.dart';
import 'package:ccrlogger/ui/widgets/blend_mask.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BackgroundWatermark with opacity 0 renders only the child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(BlendMask), findsNothing);
  });

  testWidgets('BackgroundWatermark with opacity > 0 renders a BlendMask + Image alongside the child',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    expect(find.text('content'), findsOneWidget);
    final blendMask = tester.widget<BlendMask>(find.byType(BlendMask));
    expect(blendMask.blendMode, BlendMode.screen);
    expect(blendMask.opacity, closeTo(0.1, 0.001));
  });

  testWidgets('BackgroundWatermark wraps the watermark in IgnorePointer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BackgroundWatermark(
        opacity: 0.1,
        child: Text('content'),
      ),
    ));
    expect(
      find.ancestor(
        of: find.byType(BlendMask),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/widgets/background_watermark_test.dart`
Expected: FAIL — `BackgroundWatermark` undefined.

- [ ] **Step 3: Implement `BackgroundWatermark`**

Create `lib/ui/widgets/background_watermark.dart`:

```dart
/// Renders a subtle CCR-diver watermark behind a screen's content,
/// composited via BlendMode.screen so the asset's black background is
/// transparent and the white line art lifts onto the dark surface.
library;

import 'package:flutter/material.dart';

import 'blend_mask.dart';

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

- [ ] **Step 4: Run tests**

Run: `flutter test test/ui/widgets/background_watermark_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Run full suite + analyze**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/background_watermark.dart test/ui/widgets/background_watermark_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): BackgroundWatermark widget composes BlendMask + asset

Stack wraps the child with the watermark image on top, blended via
BlendMode.screen so black bg disappears and the line art glows onto
the dark surface. IgnorePointer keeps taps falling through to the
child. opacity == 0 short-circuits to just the child.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extend `SettingsNotifier` with `watermarkOpacity`

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Modify: `test/ui/notifiers/settings_notifier_test.dart`

- [ ] **Step 1: Write the failing tests**

Open `test/ui/notifiers/settings_notifier_test.dart`. Add a new group at the end of `main()`:

```dart
  group('watermarkOpacity', () {
    test('defaults to 0.06 when prefs empty', () async {
      final n = SettingsNotifier();
      await n.load();
      expect(n.watermarkOpacity, closeTo(0.06, 0.001));
    });

    test('setWatermarkOpacity persists and notifies', () async {
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setWatermarkOpacity(0.12);
      expect(n.watermarkOpacity, closeTo(0.12, 0.001));
      expect(notifyCount, 1);
    });

    test('setWatermarkOpacity clamps to 0..0.20', () async {
      final n = SettingsNotifier();
      await n.load();
      await n.setWatermarkOpacity(-0.5);
      expect(n.watermarkOpacity, 0.0);
      await n.setWatermarkOpacity(0.99);
      expect(n.watermarkOpacity, closeTo(0.20, 0.001));
    });

    test('setWatermarkOpacity no-ops when value unchanged', () async {
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setWatermarkOpacity(0.06);
      expect(notifyCount, 0);
    });

    test('watermarkOpacity persists across reload', () async {
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setWatermarkOpacity(0.09);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.watermarkOpacity, closeTo(0.09, 0.001));
    });
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart --plain-name watermarkOpacity`
Expected: FAIL — `watermarkOpacity` getter undefined.

- [ ] **Step 3: Extend `SettingsNotifier`**

Open `lib/ui/notifiers/settings_notifier.dart`. Add the field, getter, setter, hydration:

Add to the static-key block:
```dart
static const _kWatermarkOpacity = 'watermark_opacity';
```

Add to the field block:
```dart
double _watermarkOpacity = 0.06;
```

Add to the getter block:
```dart
double get watermarkOpacity => _watermarkOpacity;
```

Add to `load()`, before `notifyListeners()`:
```dart
final wm = prefs.getDouble(_kWatermarkOpacity);
if (wm != null) {
  _watermarkOpacity = wm.clamp(0.0, 0.20);
}
```

Add a new setter method:
```dart
Future<void> setWatermarkOpacity(double v) async {
  final clamped = v.clamp(0.0, 0.20);
  if (_watermarkOpacity == clamped) return;
  _watermarkOpacity = clamped;
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_kWatermarkOpacity, clamped);
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: All previous tests + 5 new tests pass.

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/ui/notifiers/settings_notifier.dart test/ui/notifiers/settings_notifier_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): persist watermarkOpacity (default 0.06)

Double on SettingsNotifier, range 0..0.20, SharedPreferences key
watermark_opacity. Drives the watermark visibility from the Settings
slider. Clamped to range; no-ops on identical-value setter; persists
across reload.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire `BackgroundWatermark` into all screen bodies

**Files:**
- Modify: `lib/ui/app_shell.dart` (wrap the IndexedStack body)
- Modify: `lib/ui/screens/dive_detail_pager.dart` (wrap Scaffold body — the pager has its own Scaffold)
- Modify: `lib/ui/screens/sites_map_screen.dart` (wrap Scaffold body)
- Modify: `lib/ui/screens/settings_screen.dart` (wrap Scaffold body)
- Modify: `lib/ui/screens/import_screen.dart` (wrap Scaffold body if it has one)
- Modify: `lib/ui/screens/equipment/equipment_landing_screen.dart` (if it has its own Scaffold)

- [ ] **Step 1: Identify which screens have their own Scaffold**

Run:
```bash
grep -l "Scaffold" lib/ui/screens/*.dart lib/ui/screens/equipment/*.dart lib/ui/*.dart
```

Each file in the output is a candidate for the wrap. The Stack-vs-Scaffold-body distinction matters: we want the watermark to sit BEHIND the screen's primary body content, but ABOVE the Scaffold's background colour. Wrapping the `Scaffold.body:` value with `BackgroundWatermark` is correct.

- [ ] **Step 2: Wrap each screen body**

For each candidate file, find the `Scaffold(...)` constructor. The pattern is the same everywhere: change `body: <expr>` to `body: BackgroundWatermark(opacity: widget.settingsNotifier.watermarkOpacity, child: <expr>)`. Wrap in `ListenableBuilder(listenable: widget.settingsNotifier, ...)` so opacity changes rebuild.

For `app_shell.dart` specifically, the body is an `IndexedStack` inside a `Column` (with the sync-health banner above). Wrap the IndexedStack (not the Column) — the banner sits above the watermark naturally.

Concrete pattern (example for sites_map_screen.dart):

```dart
// Before:
return Scaffold(
  appBar: AppBar(title: const Text('Dive sites')),
  body: _sites == null
      ? const Center(child: CircularProgressIndicator())
      : ListenableBuilder(/* ... existing builder ... */),
);

// After:
return Scaffold(
  appBar: AppBar(title: const Text('Dive sites')),
  body: ListenableBuilder(
    listenable: widget.settingsNotifier,
    builder: (context, _) {
      return BackgroundWatermark(
        opacity: widget.settingsNotifier.watermarkOpacity,
        child: _sites == null
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(/* ... existing builder ... */),
      );
    },
  ),
);
```

Add `import '../widgets/background_watermark.dart';` at the top of each file.

- [ ] **Step 3: Run analyze + test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes (no test changes needed — widget tests still work because at default opacity 0.06 the watermark renders but doesn't change any text the tests look for).

- [ ] **Step 4: Manual smoke test on macOS**

Run: `flutter run -d macos`

Verify:
1. Watermark is visible (faint white line art) on the Dive list screen
2. Switch to the Equipment tab — watermark also visible
3. Open a dive — watermark visible behind the chart + stats
4. Open Settings — watermark visible (we'll add the slider in Task 6)
5. Open the sites map (AppBar action) — watermark visible behind the map
6. Tap anywhere on the dive list — taps still register (IgnorePointer working)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): wrap every screen body in BackgroundWatermark

AppShell (IndexedStack), DiveDetailPager, SitesMapScreen,
SettingsScreen, ImportScreen, EquipmentLandingScreen all get the
watermark behind their Scaffold body. ListenableBuilder on
settingsNotifier so opacity tweaks rebuild only the watermark layer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add the Settings slider for watermark opacity

**Files:**
- Modify: `lib/ui/screens/settings_screen.dart`

- [ ] **Step 1: Add the slider row**

Open `lib/ui/screens/settings_screen.dart`. Find an appropriate place in the settings list — under the "Appearance" or "Graph" section if one exists; otherwise add a new "Appearance" section near the top.

Add a `ListTile` (or similar) with a `Slider`:

```dart
ListenableBuilder(
  listenable: widget.notifier,
  builder: (context, _) {
    final value = widget.notifier.watermarkOpacity;
    return ListTile(
      title: const Text('Watermark opacity'),
      subtitle: Text(value == 0
          ? 'Hidden'
          : '${(value * 100).toStringAsFixed(0)}%'),
      trailing: SizedBox(
        width: 180,
        child: Slider(
          value: value,
          min: 0,
          max: 0.20,
          divisions: 20,
          onChanged: (v) => widget.notifier.setWatermarkOpacity(v),
        ),
      ),
    );
  },
),
```

- [ ] **Step 2: Run analyze + smoke test**

Run: `flutter analyze`
Expected: clean.

Run the app, open Settings, drag the slider:
- Slider at 0 → watermark disappears
- Slider at max (20%) → watermark very visible (might be too strong; fine for tuning)
- Slider at 6% (default) → faint as desired
- Setting persists when you close + relaunch

- [ ] **Step 3: Commit**

```bash
git add lib/ui/screens/settings_screen.dart
git commit -m "$(cat <<'EOF'
feat(settings): add watermark-opacity slider

Drag-to-tune in Settings (0-20% range, 20 divisions). Subtitle shows
current value as percent or 'Hidden' at zero. Reads/writes to
SettingsNotifier.watermarkOpacity.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Definition of done

After Task 6 commits:
1. `flutter analyze` reports zero issues
2. `flutter test` passes the full suite (target: existing + 10 new = ~715)
3. Manual smoke (Task 5 Step 4 + Task 6 Step 2) passes on macOS
4. Six commits land on `main`:
   - chore(assets): add watermark.png + register in pubspec
   - feat(ui): BlendMask widget for parent-blend-mode compositing
   - feat(ui): BackgroundWatermark widget composes BlendMask + asset
   - feat(settings): persist watermarkOpacity (default 0.06)
   - feat(ui): wrap every screen body in BackgroundWatermark
   - feat(settings): add watermark-opacity slider
