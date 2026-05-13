/// User-editable dive annotation — layered on top of immutable dive data.
///
/// Has sync metadata for future cloud sync (Phase 2).
library;

import 'package:drift/drift.dart' show Value;

enum SyncStatus { synced, pending, conflict }

/// One entry in a dive's weight system. Mirrors a Subsurface
/// `weightsystem weight=X.Ykg description="..."` line, of which there
/// can be multiple per dive (e.g. "backplate" + "p-weight" + "trim").
///
/// Plain Dart, no package dependencies — `toJson`/`fromJson` use the
/// same shape we persist as `weights_json` in the DB.
class Weight {
  const Weight({required this.weightKg, required this.description});

  /// Kilograms. Always metric (CLAUDE.md principle 4).
  final double weightKg;

  /// Free-text label as the diver chose to describe it ("backplate",
  /// "p-weight", "ankle weights", etc.). Empty string when Subsurface
  /// emitted a `weightsystem` line without a `description=` field.
  final String description;

  Map<String, dynamic> toJson() => {
        'weight_kg': weightKg,
        'description': description,
      };

  factory Weight.fromJson(Map<String, dynamic> json) => Weight(
        weightKg: (json['weight_kg'] as num).toDouble(),
        description: (json['description'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Weight &&
          other.weightKg == weightKg &&
          other.description == description;

  @override
  int get hashCode => Object.hash(weightKg, description);

  @override
  String toString() => 'Weight(${weightKg}kg, "$description")';
}

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
  final String? divemaster;

  /// Per-dive override of which deco algorithm to display.
  /// 'zhl16c' or 'vpmb'. NULL = use app default (ZHL-16C).
  final String? displayDecoAlgorithm;

  // Equipment used on this dive (Phase 3). All freeform single-string
  // values; the UI surfaces each as a buddies-style autocomplete.
  final String? suit;
  final String? undersuit;
  final String? weightSystem;
  final String? dpv;
  final String? camera;

  // Subsurface "Information" tab parity. Five environmental ratings
  // 1..5 (null = unrated, matching existing `rating` convention) +
  // measured air/water temperature in °C + a list of weights worn.
  final int? visibility;
  final int? wavesize;
  final int? current;
  final int? surge;
  final int? chill;
  final double? airTempC;
  final double? waterTempC;
  final List<Weight> weights;

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
    this.divemaster,
    this.displayDecoAlgorithm,
    this.suit,
    this.undersuit,
    this.weightSystem,
    this.dpv,
    this.camera,
    this.visibility,
    this.wavesize,
    this.current,
    this.surge,
    this.chill,
    this.airTempC,
    this.waterTempC,
    this.weights = const [],
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
    Value<String?>? divemaster,
    Value<String?>? displayDecoAlgorithm,
    Value<String?>? suit,
    Value<String?>? undersuit,
    Value<String?>? weightSystem,
    Value<String?>? dpv,
    Value<String?>? camera,
    Value<int?>? visibility,
    Value<int?>? wavesize,
    Value<int?>? current,
    Value<int?>? surge,
    Value<int?>? chill,
    Value<double?>? airTempC,
    Value<double?>? waterTempC,
    List<Weight>? weights,
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
        divemaster: divemaster == null ? this.divemaster : divemaster.value,
        displayDecoAlgorithm: displayDecoAlgorithm == null
            ? this.displayDecoAlgorithm
            : displayDecoAlgorithm.value,
        suit: suit == null ? this.suit : suit.value,
        undersuit: undersuit == null ? this.undersuit : undersuit.value,
        weightSystem:
            weightSystem == null ? this.weightSystem : weightSystem.value,
        dpv: dpv == null ? this.dpv : dpv.value,
        camera: camera == null ? this.camera : camera.value,
        visibility: visibility == null ? this.visibility : visibility.value,
        wavesize: wavesize == null ? this.wavesize : wavesize.value,
        current: current == null ? this.current : current.value,
        surge: surge == null ? this.surge : surge.value,
        chill: chill == null ? this.chill : chill.value,
        airTempC: airTempC == null ? this.airTempC : airTempC.value,
        waterTempC: waterTempC == null ? this.waterTempC : waterTempC.value,
        weights: weights ?? this.weights,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt == null ? this.deletedAt : deletedAt.value,
        version: version ?? this.version,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
