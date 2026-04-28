/// Equipment-related constants shared by UI and DAO layers.
///
/// Drift-generated row classes for equipment tables (`DiveComputer`,
/// `OxygenCell`, `ScrubberSession`, `Cylinder`, `PressureMapping`) live
/// in `database.dart` / `database.g.dart`. This file holds non-row
/// helper types that don't belong in the schema layer.
library;

class CylinderRole {
  static const oxygen = 'oxygen';
  static const diluent = 'diluent';
  static const bailout = 'bailout';
  static const offboard = 'offboard';
  static const all = <String>[oxygen, diluent, bailout, offboard];
}

class SlotInUseException implements Exception {
  final int slot;
  final String otherCellId;
  final String? otherLabel;

  SlotInUseException({
    required this.slot,
    required this.otherCellId,
    required this.otherLabel,
  });

  @override
  String toString() =>
      'SlotInUseException(slot=$slot, otherCellId=$otherCellId, otherLabel=$otherLabel)';
}
