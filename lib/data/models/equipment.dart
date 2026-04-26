/// Equipment entities: dive computers, O2 cells, scrubber sessions, cylinders.
///
/// All user-editable entities have sync metadata.
library;

import 'annotation.dart';

class DiveComputer {
  final String id;
  final int serial;
  final int modelCode;
  final int? firmwareVersion;
  final String? nickname;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final SyncStatus syncStatus;

  DiveComputer({
    required this.id,
    required this.serial,
    required this.modelCode,
    this.firmwareVersion,
    this.nickname,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
  });
}

class OxygenCell {
  final String id;
  final int slot; // 1, 2, or 3
  final DateTime? installedDate;
  final DateTime? retiredDate;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final SyncStatus syncStatus;

  OxygenCell({
    required this.id,
    required this.slot,
    this.installedDate,
    this.retiredDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
  });
}

class ScrubberSession {
  final String id;
  final DateTime? startedDate;
  final int? totalMinutes;
  final String? mediaType; // e.g. "Sofnolime 797"
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final SyncStatus syncStatus;

  ScrubberSession({
    required this.id,
    this.startedDate,
    this.totalMinutes,
    this.mediaType,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
  });
}
