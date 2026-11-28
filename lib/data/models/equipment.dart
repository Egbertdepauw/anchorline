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
  static const backgas = 'backgas';
  static const travel = 'travel';
  static const stage = 'stage';
  static const offboard = 'offboard';

  /// Grouping and dropdown order.
  static const all = <String>[
    oxygen,
    diluent,
    bailout,
    backgas,
    travel,
    stage,
    offboard,
  ];

  /// Roles whose cylinders are numbered (stored in `bailout_order`).
  static bool isNumbered(String? role) => role == bailout || role == stage;
}

/// Diver-facing name of a stored role; an unknown string (another device
/// running a newer build) is shown as it is.
String cylinderRoleLabel(String role) => switch (role) {
      CylinderRole.oxygen => 'Oxygen',
      CylinderRole.diluent => 'Diluent',
      CylinderRole.bailout => 'Bailout',
      CylinderRole.backgas => 'Backgas',
      CylinderRole.travel => 'Travel',
      CylinderRole.stage => 'Stage',
      CylinderRole.offboard => 'Offboard',
      _ => role,
    };

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
