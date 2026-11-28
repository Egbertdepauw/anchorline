import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart'
    show AscentStop;
import 'package:ccrlogger/ui/widgets/dive_profile_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

// A fresh instance per leg, as the planner produces them; not const, so
// the compiler can't fold them into one object.
AscentStop _leg(int o2, int he) => AscentStop(
      depthStartMeters: 30,
      depthEndMeters: 30,
      duration: const Duration(minutes: 5),
      gas: DiveGasMix(oxygenPercent: o2, heliumPercent: he, isDiluent: false),
      volumeLitresConsumed: 0,
    );

void main() {
  // #274: an Air-only plan drew "Air" switch markers between legs.
  test('legs on separate instances of one mix are no gas switch', () {
    expect(gasSwitchLegIndices([_leg(21, 0), _leg(21, 0), _leg(21, 0)]),
        isEmpty);
  });

  test('a real change of mix is a gas switch', () {
    expect(
        gasSwitchLegIndices(
            [_leg(21, 0), _leg(21, 0), _leg(50, 0), _leg(100, 0)]),
        [2, 3]);
  });
}
