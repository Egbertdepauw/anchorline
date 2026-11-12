/// Renders a subtle CCR-diver watermark behind a screen's content. The
/// asset is a transparent-background PNG so a plain Opacity composite is
/// all that's needed.
///
/// Because the watermark composites ON TOP of its child, surfaces that
/// render bright full-bleed content (photos, PDF pages) pick up a
/// visible tint. [WatermarkSuppressionScope] + [SuppressWatermark] let
/// such descendants ask the watermark owner to drop to zero opacity
/// while they are mounted, without the owner having to know about every
/// route the nested navigators can push.
library;

import 'package:flutter/material.dart';

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
    // Always a Stack, with the overlay left out at zero opacity. Returning
    // the bare child instead changed the tree shape above it, so every
    // switch (e.g. to the Settings tab, which hides the watermark) threw
    // away the state of everything below: open panels, text fields, the
    // Dives tab's navigation stack (#183).
    return Stack(
      children: [
        child,
        if (opacity > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.9,
                  heightFactor: 0.9,
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
      ],
    );
  }
}

/// Inherited handle to the watermark owner's suppression counter.
///
/// The owner (app shell) creates one long-lived `ValueNotifier<int>`,
/// listens to it, and zeroes the watermark while the count is > 0.
/// Descendants never read the value through this scope — they only
/// increment/decrement it via [SuppressWatermark] — so the notifier
/// identity never changes and [updateShouldNotify] is always false.
class WatermarkSuppressionScope extends InheritedWidget {
  /// Count of currently mounted [SuppressWatermark] descendants.
  final ValueNotifier<int> suppressors;

  const WatermarkSuppressionScope({
    super.key,
    required this.suppressors,
    required super.child,
  });

  static WatermarkSuppressionScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WatermarkSuppressionScope>();

  @override
  bool updateShouldNotify(WatermarkSuppressionScope oldWidget) => false;
}

/// Pass-through wrapper that suppresses the brand watermark while it is
/// mounted under a [WatermarkSuppressionScope]. With no scope above it
/// (e.g. a widget under test, or a route hosted outside the shell) it is
/// a silent no-op.
///
/// Both the increment and the decrement are deferred to a post-frame
/// callback: the counter is watched by a ListenableBuilder ABOVE this
/// widget, and mutating it synchronously from initState/dispose would
/// mean notifying an ancestor mid-build / mid-teardown.
class SuppressWatermark extends StatefulWidget {
  final Widget child;

  const SuppressWatermark({super.key, required this.child});

  @override
  State<SuppressWatermark> createState() => _SuppressWatermarkState();
}

class _SuppressWatermarkState extends State<SuppressWatermark> {
  /// The scope's notifier, captured when we incremented it, so dispose
  /// can decrement without touching [context] after unmount.
  ValueNotifier<int>? _suppressors;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = WatermarkSuppressionScope.maybeOf(context);
      if (scope == null) return;
      _suppressors = scope.suppressors;
      _suppressors!.value += 1;
      _counted = true;
    });
  }

  @override
  void dispose() {
    if (_counted) {
      _counted = false;
      final suppressors = _suppressors!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        suppressors.value -= 1;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
