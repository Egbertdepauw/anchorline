import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/models/annotation.dart' as dom;
import '../util/format.dart';

class DiveListNotifier extends ChangeNotifier {
  final DiveDao _dao;
  final DiveAnnotationsDao _annotationsDao;
  StreamSubscription<void>? _annotationsWatchSub;
  List<Dive> _dives = [];
  Map<String, dom.DiveAnnotation> _annotationsByDiveId = {};
  bool _loading = false;
  final _sparklineCache = _LruCache<String, Float32List>(50);

  bool _disposed = false;

  DiveListNotifier(this._dao, this._annotationsDao) {
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
  }

  @override
  void dispose() {
    _disposed = true;
    _annotationsWatchSub?.cancel();
    super.dispose();
  }

  List<Dive> get dives => _dives;
  bool get loading => _loading;
  Map<String, dom.DiveAnnotation> get annotationsByDiveId =>
      Map.unmodifiable(_annotationsByDiveId);

  /// Display dive number keyed by dive id.
  ///
  /// Returns the dive computer's own counter (`dcDiveNumber`). This
  /// matches what the Petrel itself shows AND what Subsurface displays,
  /// so users who cross-check between the three systems don't see
  /// confusing off-by-N mismatches.
  ///
  /// Previously this returned a CCRLog-internal chronological sequence
  /// (1..N over all imported dives). That worked cleanly when every
  /// single dive lived in CCRLog — but as soon as the user had dives in
  /// Subsurface or on the DC that hadn't been imported into CCRLog yet,
  /// CCRLog's numbering lagged the others and confused anyone trying
  /// to find "dive #692" across all three UIs.
  ///
  /// Trade-off: for users who switch dive computers (or factory-reset
  /// one), `dcDiveNumber` can collide across DCs — two different dives
  /// can both display as e.g. "#147". A future revision could namespace
  /// the display by serial when collisions are detected. Manual entries
  /// with `dcDiveNumber == 0` currently display as "#0"; revisit when
  /// manual-dive entry is a real feature.
  Map<String, int> get sequenceByDiveId {
    return {
      for (final d in _dives) d.id: d.dcDiveNumber,
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
    _dives = dives;
    _annotationsByDiveId = annotations;
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
