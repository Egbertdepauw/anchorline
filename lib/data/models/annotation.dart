/// User-editable dive annotation — layered on top of immutable dive data.
///
/// Has sync metadata for future cloud sync (Phase 2).
library;

import 'package:drift/drift.dart' show Value;

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

  DiveAnnotation copyWith({
    String? diveId,
    Value<String?>? siteName,
    Value<double?>? siteLatitude,
    Value<double?>? siteLongitude,
    Value<String?>? notes,
    List<String>? buddies,
    List<String>? tags,
    Value<int?>? rating,
    Value<String?>? conditions,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?>? deletedAt,
    int? version,
    SyncStatus? syncStatus,
  }) =>
      DiveAnnotation(
        diveId: diveId ?? this.diveId,
        siteName: siteName == null ? this.siteName : siteName.value,
        siteLatitude:
            siteLatitude == null ? this.siteLatitude : siteLatitude.value,
        siteLongitude:
            siteLongitude == null ? this.siteLongitude : siteLongitude.value,
        notes: notes == null ? this.notes : notes.value,
        buddies: buddies ?? this.buddies,
        tags: tags ?? this.tags,
        rating: rating == null ? this.rating : rating.value,
        conditions: conditions == null ? this.conditions : conditions.value,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt == null ? this.deletedAt : deletedAt.value,
        version: version ?? this.version,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
