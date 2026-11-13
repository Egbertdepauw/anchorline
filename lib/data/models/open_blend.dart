/// An open blend (issue #112): a gas the diver has blended and not yet
/// analysed. An analysis that matches it closes it.
///
/// Pure Dart. Percentages are whole numbers ([DesiredMix]), pressures bar,
/// capacity litres.
library;

import 'gas_analysis.dart';

class OpenBlend {
  final String id;
  final DesiredMix target;
  final double targetPressureBar;
  final DesiredMix residual;
  final double residualPressureBar;
  final DesiredMix topoff;
  final double waterCapacityL;
  final GasRole role;
  final String? blendedBy;
  final DateTime blendedAt;

  const OpenBlend({
    required this.id,
    required this.target,
    required this.targetPressureBar,
    required this.residual,
    required this.residualPressureBar,
    required this.topoff,
    required this.waterCapacityL,
    required this.role,
    required this.blendedBy,
    required this.blendedAt,
  });
}

/// An [OpenBlend] before it has an id, as the DAO takes it.
class NewOpenBlend {
  final DesiredMix target;
  final double targetPressureBar;
  final DesiredMix residual;
  final double residualPressureBar;
  final DesiredMix topoff;
  final double waterCapacityL;
  final GasRole role;
  final String? blendedBy;
  final DateTime blendedAt;

  const NewOpenBlend({
    required this.target,
    required this.targetPressureBar,
    required this.residual,
    required this.residualPressureBar,
    required this.topoff,
    required this.waterCapacityL,
    required this.role,
    required this.blendedBy,
    required this.blendedAt,
  });
}
