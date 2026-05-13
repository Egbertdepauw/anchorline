/// Standard mix tables for the bailout planner. Per Track D spec.
library;

import '../../data/models/dive.dart' show DiveGasMix;

const List<DiveGasMix> kNonGueBottomMixes = [
  DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
  DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
  DiveGasMix(oxygenPercent: 15, heliumPercent: 55, isDiluent: true),
  DiveGasMix(oxygenPercent: 12, heliumPercent: 65, isDiluent: true),
  DiveGasMix(oxygenPercent: 10, heliumPercent: 70, isDiluent: true),
];

const List<DiveGasMix> kGueBottomMixes = [
  DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
  DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
  DiveGasMix(oxygenPercent: 15, heliumPercent: 55, isDiluent: true),
];

const List<DiveGasMix> kDecoMixes = [
  DiveGasMix(oxygenPercent: 32, heliumPercent: 0, isDiluent: false),
  DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
  DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
];

const double kPpo2MaxNonGue = 1.6;
const double kPpo2MaxGue = 1.0;
const double kEndMaxMetres = 39.0;
