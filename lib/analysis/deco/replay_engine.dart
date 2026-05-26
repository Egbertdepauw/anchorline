/// Orchestrator that dispatches to the appropriate replay engine
/// based on the algorithm parameter, and caches the result keyed by
/// (diveId, algorithm, vpmbConservatism, gfLow, gfHigh). LRU eviction
/// when more than 16 entries are cached.
library;

import 'dart:collection';

import '../../data/models/dive.dart' show DiveGasMix;
import 'replay_result.dart';
import 'vpmb.dart';
import 'zhl16c.dart';

class DecoReplayEngine {
  static const int _maxCacheEntries = 16;
  final LinkedHashMap<_CacheKey, DecoReplayResult> _cache = LinkedHashMap();

  DecoReplayResult replay({
    required String diveId,
    required SampleStream samples,
    required List<DiveGasMix> gasMixes,
    required DecoAlgorithm algorithm,
    int? vpmbConservatism,
    int? gfLow,
    int? gfHigh,
    int? triggerSampleIdx,
    double surfacePressureBar = 1.013,
  }) {
    final key = _CacheKey(diveId, algorithm, vpmbConservatism, gfLow, gfHigh,
        triggerSampleIdx, surfacePressureBar);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // re-insert at end (LRU)
      return cached;
    }
    final result = switch (algorithm) {
      DecoAlgorithm.zhl16c => Zhl16cReplay().run(
          samples: samples,
          gasMixes: gasMixes,
          gfLow: gfLow ?? 30,
          gfHigh: gfHigh ?? 85,
          triggerSampleIdx: triggerSampleIdx,
          surfacePressureBar: surfacePressureBar,
        ),
      DecoAlgorithm.vpmb => VpmbReplay().run(
          samples: samples,
          gasMixes: gasMixes,
          conservatism: vpmbConservatism ?? 2,
          triggerSampleIdx: triggerSampleIdx,
          surfacePressureBar: surfacePressureBar,
        ),
    };
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
    return result;
  }

  int get cacheSize => _cache.length;
  void clearCache() => _cache.clear();
}

class _CacheKey {
  final String diveId;
  final DecoAlgorithm algorithm;
  final int? vpmbConservatism;
  final int? gfLow;
  final int? gfHigh;
  final int? triggerSampleIdx;
  final double surfacePressureBar;

  const _CacheKey(
    this.diveId,
    this.algorithm,
    this.vpmbConservatism,
    this.gfLow,
    this.gfHigh,
    this.triggerSampleIdx,
    this.surfacePressureBar,
  );

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.diveId == diveId &&
      other.algorithm == algorithm &&
      other.vpmbConservatism == vpmbConservatism &&
      other.gfLow == gfLow &&
      other.gfHigh == gfHigh &&
      other.triggerSampleIdx == triggerSampleIdx &&
      other.surfacePressureBar == surfacePressureBar;

  @override
  int get hashCode => Object.hash(diveId, algorithm, vpmbConservatism, gfLow,
      gfHigh, triggerSampleIdx, surfacePressureBar);
}
