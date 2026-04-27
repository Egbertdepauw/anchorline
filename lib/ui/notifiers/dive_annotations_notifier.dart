import 'package:flutter/foundation.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../../data/models/annotation.dart';

class DiveAnnotationsNotifier extends ChangeNotifier {
  final DiveAnnotationsDao _dao;

  DiveAnnotationsNotifier(this._dao);

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
  Map<int, String?> get cylinderByMix => Map.unmodifiable(_cylinderByMix);
  bool get dirty => _dirty;
  bool get loaded => _annotation != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<void> load(String diveId) async {
    _diveId = diveId;
    final existing = await _dao.get(diveId);
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
    final cylinders = await _dao.listCylindersForDive(diveId);
    _cylinderByMix = {for (final c in cylinders) c.gasMixIndex: c.cylinderId};
    _dirty = false;
    notifyListeners();
  }

  // ── Setters ───────────────────────────────────────────────────────────

  void setSiteName(String? v) {
    _annotation = _annotation?.copyWith(siteName: v);
    _markDirty();
  }

  void setLatLon(double? lat, double? lon) {
    _annotation = _annotation?.copyWith(siteLatitude: lat, siteLongitude: lon);
    _markDirty();
  }

  void setNotes(String? v) {
    _annotation = _annotation?.copyWith(notes: v);
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
    _annotation = _annotation?.copyWith(rating: v);
    _markDirty();
  }

  void setConditions(String? v) {
    _annotation = _annotation?.copyWith(conditions: v);
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

  Future<void> save() async {
    if (_annotation == null || _diveId == null) return;
    final mappings = _cylinderByMix.entries
        .map((e) => (gasMixIndex: e.key, cylinderId: e.value))
        .toList();
    await _dao.saveAll(_annotation!, mappings);
    _dirty = false;
    notifyListeners();
  }
}
