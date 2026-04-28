import 'package:flutter/foundation.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/models/annotation.dart' as dom;
import '../util/format.dart';

class DiveListNotifier extends ChangeNotifier {
  final DiveDao _dao;
  final DiveAnnotationsDao _annotationsDao;
  List<Dive> _dives = [];
  Map<String, dom.DiveAnnotation> _annotationsByDiveId = {};
  bool _loading = false;
  final _sparklineCache = _LruCache<String, Float32List>(50);

  DiveListNotifier(this._dao, this._annotationsDao);

  List<Dive> get dives => _dives;
  bool get loading => _loading;
  Map<String, dom.DiveAnnotation> get annotationsByDiveId =>
      Map.unmodifiable(_annotationsByDiveId);

  Map<String, List<Dive>> get groupedByMonth {
    final groups = <String, List<Dive>>{};
    for (final dive in _dives) {
      final key = formatMonthYear(dive.startTime);
      groups.putIfAbsent(key, () => []).add(dive);
    }
    return groups;
  }

  Future<void> loadDives() async {
    _loading = true;
    notifyListeners();
    _dives = await _dao.getAllDives();
    _annotationsByDiveId =
        await _annotationsDao.getAnnotationsForDives(_dives.map((d) => d.id));
    _loading = false;
    notifyListeners();
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
