/// User-editable dive annotation — layered on top of immutable dive data.
///
/// Has sync metadata for future cloud sync (Phase 2).
library;

enum SyncStatus { synced, pending, conflict }

class DiveAnnotation {
  final String diveId;
  final String? siteName;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? notes;
  final List<String> buddies;
  final List<String> tags;
  final int? rating; // 1-5
  final String? conditions;

  // Sync metadata (designed in from day one per CLAUDE.md).
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final SyncStatus syncStatus;

  DiveAnnotation({
    required this.diveId,
    this.siteName,
    this.siteLatitude,
    this.siteLongitude,
    this.notes,
    this.buddies = const [],
    this.tags = const [],
    this.rating,
    this.conditions,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
  });
}
