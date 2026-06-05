import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../analysis/merge/merge_validator.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/dive_merge_dao.dart';
import '../../data/models/annotation.dart' as dom;
import '../models/dive_list_item.dart';
import '../util/format.dart';
import 'dive_renumber.dart';

class DiveListNotifier extends ChangeNotifier {
  final DiveDao _dao;
  final DiveAnnotationsDao _annotationsDao;
  final DiveMergeDao _mergeDao;
  StreamSubscription<void>? _annotationsWatchSub;
  StreamSubscription<void>? _mergeWatchSub;
  List<Dive> _dives = [];
  Map<String, dom.DiveAnnotation> _annotationsByDiveId = {};
  List<MergeLink> _links = [];
  bool _loading = false;
  final _sparklineCache = _LruCache<String, Float32List>(50);

  bool _disposed = false;

  // Selection mode (for creating merges).
  bool _selectionMode = false;
  final Set<String> _selectedDiveIds = {};

  DiveListNotifier(this._dao, this._annotationsDao, this._mergeDao) {
    // Refresh whenever annotations change locally or arrive from the cloud.
    // Drift dives don't need a watch — they only mutate via local imports,
    // and the import flow already calls loadDives().
    _annotationsWatchSub = _annotationsDao.watchChanges().listen(
      (_) {
        if (_disposed) return;
        loadDives();
      },
      // Subscription can outlive the underlying psDb during test teardown;
      // swallow the resulting "connection closed" errors instead of
      // surfacing them as unhandled stream errors.
      onError: (_) {},
    );
    _mergeWatchSub = _mergeDao.watchChanges().listen(
      (_) {
        if (_disposed) return;
        loadDives();
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _annotationsWatchSub?.cancel();
    _mergeWatchSub?.cancel();
    super.dispose();
  }

  List<Dive> get dives => _dives;
  bool get loading => _loading;
  Map<String, dom.DiveAnnotation> get annotationsByDiveId =>
      Map.unmodifiable(_annotationsByDiveId);

  List<MergeLink> get links => List.unmodifiable(_links);
  List<DiveListItem> get listItems => buildListItems(_dives, _links);

  bool get selectionMode => _selectionMode;
  Set<String> get selectedDiveIds => Set.unmodifiable(_selectedDiveIds);
  bool isSelected(String diveId) => _selectedDiveIds.contains(diveId);

  void enterSelectionMode(String firstDiveId) {
    _selectionMode = true;
    _selectedDiveIds
      ..clear()
      ..add(firstDiveId);
    notifyListeners();
  }

  void exitSelectionMode() {
    _selectionMode = false;
    _selectedDiveIds.clear();
    notifyListeners();
  }

  void toggleSelected(String diveId) {
    if (!_selectedDiveIds.remove(diveId)) {
      _selectedDiveIds.add(diveId);
    }
    if (_selectedDiveIds.isEmpty) {
      _selectionMode = false;
    }
    notifyListeners();
  }

  /// Eligibility of the current selection (drives the Merge button state).
  MergeEligibility get mergeEligibility {
    final selected =
        _dives.where((d) => _selectedDiveIds.contains(d.id)).toList();
    return validateMerge(selected: selected, allDives: _dives);
  }

  /// Merges the current selection (assumes [mergeEligibility].canMerge).
  Future<void> mergeSelected() async {
    final ids = _selectedDiveIds.toList();
    await _mergeDao.mergeDives(ids);
    exitSelectionMode();
    await loadDives();
  }

  /// Unmerges a group and refreshes.
  Future<void> unmergeGroup(String groupId) async {
    await _mergeDao.unmerge(groupId);
    await loadDives();
  }

  /// Representative dive id for a list item (a merged group → its earliest
  /// member, which carries the group's annotation/number).
  String _representativeId(DiveListItem item) => switch (item) {
        SingleDive(:final dive) => dive.id,
        MergedGroupItem(:final group) => group.earliest.id,
      };

  /// Select every visible list item (merged groups via their representative id).
  void selectAll() {
    _selectionMode = true;
    _selectedDiveIds
      ..clear()
      ..addAll(listItems.map(_representativeId));
    notifyListeners();
  }

  /// Renumber the current selection from [start] in date order, persisting
  /// `user_dive_number`. No-op when nothing is selected.
  ///
  /// Selection holds one representative id per visible item (a merged group's
  /// earliest member), so a group is numbered once with no gaps. Non-
  /// representative members of a merged group are not written — harmless while
  /// the group displays via its representative; they fall back to the auto
  /// sequence if ever shown individually (e.g. after unmerge).
  Future<void> renumberSelected(int start) async {
    if (_selectedDiveIds.isEmpty) return;
    final byId = {for (final d in _dives) d.id: d};
    final targets = _selectedDiveIds
        .where(byId.containsKey)
        .map((id) => (diveId: id, startTime: byId[id]!.startTime))
        .toList();
    await _annotationsDao.setUserDiveNumbers(computeRenumber(targets, start));
    exitSelectionMode();
    await loadDives();
  }

  /// Clear custom numbers for the current selection (back to auto sequence).
  Future<void> resetNumberingSelected() async {
    if (_selectedDiveIds.isEmpty) return;
    await _annotationsDao
        .setUserDiveNumbers({for (final id in _selectedDiveIds) id: null});
    exitSelectionMode();
    await loadDives();
  }

  /// CCRLog-internal sequential dive number, keyed by dive id. Computed
  /// over all non-deleted dives sorted by `start_time` ascending — the
  /// chronologically-oldest dive is `#1`, newest is `#N`. Stable across
  /// filter changes (filtering hides rows; it doesn't renumber).
  ///
  /// Deliberately NOT the dive computer's own counter. dc_dive_number
  /// can have gaps (factory-reset DCs, deleted-on-device dives) and
  /// can collide across multiple dive computers — neither is what the
  /// user wants to see in the dive list. The user explicitly prefers
  /// a continuous 1..N sequence even if it disagrees with what the
  /// Petrel and Subsurface display per-dive.
  Map<String, int> get sequenceByDiveId {
    final n = _dives.length;
    return {
      for (var i = 0; i < n; i++)
        _dives[i].id:
            _annotationsByDiveId[_dives[i].id]?.userDiveNumber ?? (n - i),
    };
  }

  Map<String, List<Dive>> get groupedByMonth {
    final groups = <String, List<Dive>>{};
    for (final dive in _dives) {
      final key = formatMonthYear(dive.startTime);
      groups.putIfAbsent(key, () => []).add(dive);
    }
    return groups;
  }

  Future<void> loadDives() async {
    if (_disposed) return;
    _loading = true;
    notifyListeners();
    final dives = await _dao.getAllDives();
    if (_disposed) return;
    final annotations =
        await _annotationsDao.getAnnotationsForDives(dives.map((d) => d.id));
    if (_disposed) return;
    final links = await _mergeDao.getActiveLinks();
    if (_disposed) return;
    _dives = dives;
    _annotationsByDiveId = annotations;
    _links = links;
    _loading = false;
    notifyListeners();
  }

  /// Soft-deletes a dive and refreshes the list. Pair with [restoreDive]
  /// behind a SnackBar UNDO button.
  Future<void> softDeleteDive(String id) async {
    await _dao.softDeleteDive(id);
    await loadDives();
  }

  /// Undoes a [softDeleteDive] — restores the row and refreshes.
  Future<void> restoreDive(String id) async {
    await _dao.restoreDive(id);
    await loadDives();
  }

  Future<Float32List?> getSparklineData(String diveId) async {
    final cached = _sparklineCache.get(diveId);
    if (cached != null) return cached;
    final samples = await _dao.getSamples(diveId);
    if (samples == null) return null;
    _sparklineCache.put(diveId, samples.depthMeters);
    return samples.depthMeters;
  }

  /// Combined depth sparkline for a merge group: each member's depth track
  /// concatenated (no gap — the thumbnail is tiny) so the merged tile shows
  /// both dives' shapes. Reuses the per-dive [getSparklineData] cache.
  Future<Float32List?> getMergedSparklineData(List<String> diveIds) async {
    final parts = <Float32List>[];
    for (final id in diveIds) {
      final part = await getSparklineData(id);
      if (part != null && part.isNotEmpty) parts.add(part);
    }
    if (parts.isEmpty) return null;
    final total = parts.fold<int>(0, (sum, p) => sum + p.length);
    final out = Float32List(total);
    var w = 0;
    for (final p in parts) {
      out.setAll(w, p);
      w += p.length;
    }
    return out;
  }
}

class _LruCache<K, V> {
  final int _maxSize;
  final _map = <K, V>{};

  _LruCache(this._maxSize);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > _maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}
