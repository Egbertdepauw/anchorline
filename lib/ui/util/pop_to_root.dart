import 'package:flutter/widgets.dart';

/// Pops [navigator] back to its first route through each route's own pop
/// guards (`PopScope`), unlike `popUntil`, which skips them. Stops as soon as
/// a pop is refused, so a guard that asks the user ("Unsaved changes") keeps
/// the user on that screen until they decide.
Future<void> popToRootRespectingGuards(NavigatorState navigator) async {
  Route<dynamic>? topRoute() {
    Route<dynamic>? top;
    navigator.popUntil((r) {
      top = r;
      return true;
    });
    return top;
  }

  while (navigator.mounted && navigator.canPop()) {
    final before = topRoute();
    await navigator.maybePop();
    if (!navigator.mounted || identical(topRoute(), before)) return;
  }
}
