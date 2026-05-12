import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/annotation.dart';

class DiveAnnotationsNotifier extends ChangeNotifier {
  final DiveAnnotationsDao _annotationsDao;
  final EquipmentDao _equipmentDao;

  DiveAnnotationsNotifier(this._annotationsDao, this._equipmentDao);

  String? _diveId;
  DiveAnnotation? _annotation;
  Map<int, String?> _cylinderByMix = {};
  bool _dirty = false;

  // ── Read accessors ────────────────────────────────────────────────────

  String? get siteName => _annotation?.siteName;
  double? get siteLatitude => _annotation?.siteLatitude;
  double? get siteLongitude => _annotation?.siteLongitude;
  String? get notes => _annotation?.notes;
  List<String> get buddies => _annotation?.buddies ?? const [];
  List<String> get tags => _annotation?.tags ?? const [];
  int? get rating => _annotation?.rating;
  String? get conditions => _annotation?.conditions;
  String? get divemaster => _annotation?.divemaster;
  String? get suit => _annotation?.suit;
  String? get undersuit => _annotation?.undersuit;
  String? get weightSystem => _annotation?.weightSystem;
  String? get dpv => _annotation?.dpv;
  String? get camera => _annotation?.camera;
  int? get visibility => _annotation?.visibility;
  int? get wavesize => _annotation?.wavesize;
  int? get current => _annotation?.current;
  int? get surge => _annotation?.surge;
  int? get chill => _annotation?.chill;
  double? get airTempC => _annotation?.airTempC;
  double? get waterTempC => _annotation?.waterTempC;
  List<Weight> get weights => _annotation?.weights ?? const [];
  Map<int, String?> get cylinderByMix => Map.unmodifiable(_cylinderByMix);
  bool get dirty => _dirty;
  bool get loaded => _annotation != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<void> load(String diveId) async {
    _diveId = diveId;
    final existing = await _annotationsDao.get(diveId);
    if (existing != null) {
      _annotation = existing;
    } else {
      final now = DateTime.now();
      _annotation = DiveAnnotation(
        diveId: diveId,
        createdAt: now,
        updatedAt: now,
      );
    }
    final cylinders = await _equipmentDao.listCylindersForDive(diveId);
    _cylinderByMix = {for (final c in cylinders) c.gasMixIndex: c.cylinderId};
    _dirty = false;
    notifyListeners();
  }

  // ── Setters ───────────────────────────────────────────────────────────

  void setSiteName(String? v) {
    _annotation = _annotation?.copyWith(siteName: Value(v));
    _markDirty();
  }

  void setLatLon(double? lat, double? lon) {
    _annotation = _annotation?.copyWith(
      siteLatitude: Value(lat),
      siteLongitude: Value(lon),
    );
    _markDirty();
  }

  void setNotes(String? v) {
    _annotation = _annotation?.copyWith(notes: Value(v));
    _markDirty();
  }

  void setBuddies(List<String> v) {
    _annotation = _annotation?.copyWith(buddies: v);
    _markDirty();
  }

  void setTags(List<String> v) {
    _annotation = _annotation?.copyWith(tags: v);
    _markDirty();
  }

  void setRating(int? v) {
    _annotation = _annotation?.copyWith(rating: Value(v));
    _markDirty();
  }

  void setConditions(String? v) {
    _annotation = _annotation?.copyWith(conditions: Value(v));
    _markDirty();
  }

  void setDivemaster(String? v) {
    _annotation = _annotation?.copyWith(divemaster: Value(v));
    _markDirty();
  }

  void setSuit(String? v) {
    _annotation = _annotation?.copyWith(suit: Value(v));
    _markDirty();
  }

  void setUndersuit(String? v) {
    _annotation = _annotation?.copyWith(undersuit: Value(v));
    _markDirty();
  }

  void setWeightSystem(String? v) {
    _annotation = _annotation?.copyWith(weightSystem: Value(v));
    _markDirty();
  }

  void setDpv(String? v) {
    _annotation = _annotation?.copyWith(dpv: Value(v));
    _markDirty();
  }

  void setCamera(String? v) {
    _annotation = _annotation?.copyWith(camera: Value(v));
    _markDirty();
  }

  void setVisibility(int? v) {
    _annotation = _annotation?.copyWith(visibility: Value(v));
    _markDirty();
  }

  void setWavesize(int? v) {
    _annotation = _annotation?.copyWith(wavesize: Value(v));
    _markDirty();
  }

  void setCurrent(int? v) {
    _annotation = _annotation?.copyWith(current: Value(v));
    _markDirty();
  }

  void setSurge(int? v) {
    _annotation = _annotation?.copyWith(surge: Value(v));
    _markDirty();
  }

  void setChill(int? v) {
    _annotation = _annotation?.copyWith(chill: Value(v));
    _markDirty();
  }

  void setAirTempC(double? v) {
    _annotation = _annotation?.copyWith(airTempC: Value(v));
    _markDirty();
  }

  void setWaterTempC(double? v) {
    _annotation = _annotation?.copyWith(waterTempC: Value(v));
    _markDirty();
  }

  void setWeights(List<Weight> v) {
    _annotation = _annotation?.copyWith(weights: v);
    _markDirty();
  }

  void setCylinderForMix(int gasMixIndex, String? cylinderId) {
    _cylinderByMix = {..._cylinderByMix, gasMixIndex: cylinderId};
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    notifyListeners();
  }

  // ── Save ──────────────────────────────────────────────────────────────

  /// Saves the annotation (PowerSync) and the per-mix cylinder mappings
  /// (Drift) sequentially. The two DBs can't share a transaction, so a
  /// crash between them leaves the annotation written and the mappings
  /// not — fine for now because mappings are user-recoverable, and the
  /// dive_cylinders table moves to PowerSync in Phase 2.3 anyway.
  Future<void> save() async {
    if (_annotation == null || _diveId == null) return;
    await _annotationsDao.upsert(_annotation!);
    final mappings = _cylinderByMix.entries
        .map((e) => (gasMixIndex: e.key, cylinderId: e.value))
        .toList();
    await _equipmentDao.setDiveCylinders(_annotation!.diveId, mappings);
    _dirty = false;
    notifyListeners();
  }
}
