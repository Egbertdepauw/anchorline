/// One leg of a deco plan: a flat stop (depthStart == depthEnd) or a moving
/// ascent segment. Gas is what the diver breathes during this leg.
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

class DecoStep {
  final double depthStartMeters;
  final double depthEndMeters;
  final Duration duration;
  final DiveGasMix gas;

  const DecoStep({
    required this.depthStartMeters,
    required this.depthEndMeters,
    required this.duration,
    required this.gas,
  });

  bool get isStop => depthStartMeters == depthEndMeters;
}
