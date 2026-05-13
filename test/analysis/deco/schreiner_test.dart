import 'package:ccrlogger/analysis/deco/schreiner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flat-depth equilibration follows exponential load curve', () {
    final result = loadCompartment(
      currentLoadBar: 0.0,
      inertGasPartialPressureBar: 0.79,
      halfTimeMin: 10.0,
      intervalSeconds: 600,
    );
    expect(result, closeTo(0.395, 0.005));
  });

  test('two half-times → 75% equilibration', () {
    final result = loadCompartment(
      currentLoadBar: 0.0,
      inertGasPartialPressureBar: 1.0,
      halfTimeMin: 10.0,
      intervalSeconds: 1200,
    );
    expect(result, closeTo(0.75, 0.01));
  });

  test('zero interval returns current load unchanged', () {
    final result = loadCompartment(
      currentLoadBar: 1.5,
      inertGasPartialPressureBar: 2.0,
      halfTimeMin: 10.0,
      intervalSeconds: 0,
    );
    expect(result, closeTo(1.5, 0.001));
  });

  test('descending pressure (off-gas) reduces load toward new equilibrium', () {
    final result = loadCompartment(
      currentLoadBar: 2.0,
      inertGasPartialPressureBar: 0.79,
      halfTimeMin: 10.0,
      intervalSeconds: 600,
    );
    expect(result, closeTo(1.395, 0.005));
  });
}
