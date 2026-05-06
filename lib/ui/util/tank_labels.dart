import '../../data/db/database.dart';
import '../../data/models/dive.dart' show DiveTank;
import '../../shearwater/parser/parsed_dive.dart' show TankUsage;

String tankTraceLabelFor(DiveTank tank) {
  switch (tank.usage) {
    case TankUsage.diluent:
      return 'DIL';
    case TankUsage.oxygen:
      return 'O2';
    case TankUsage.sidemount:
      return 'BO';
    case TankUsage.none:
      return 'T${tank.slot}';
  }
}

String labelForTank(DiveTank tank, Map<int, Cylinder>? mapped) {
  final c = mapped?[tank.slot];
  if (c != null && c.label.trim().isNotEmpty) return c.label;
  return tankTraceLabelFor(tank);
}
