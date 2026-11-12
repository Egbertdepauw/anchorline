import 'dart:typed_data';
import 'package:ccrlogger/analysis/deco/replay_engine.dart';
import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/analysis/deco/zhl16c.dart' show SampleStub;
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

SampleStub _flat(double depthM, int durationSec, int intervalMs) {
  final n = (durationSec * 1000 / intervalMs).round();
  return SampleStub(
    depthMeters: Float32List(n)..fillRange(0, n, depthM),
    gasMixIndex: Uint8List(n),
    sampleIntervalMs: intervalMs,
  );
}

void main() {
  final samples = _flat(30, 600, 10000);
  final gasMixes = [DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true)];

  test('dispatches ZHL-16C when algorithm == zhl16c', () {
    final engine = DecoReplayEngine();
    final result = engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.zhl16c, gfLow: 30, gfHigh: 85,
    );
    expect(result.algorithm, DecoAlgorithm.zhl16c);
  });

  test('dispatches VPM-B when algorithm == vpmb', () {
    final engine = DecoReplayEngine();
    final result = engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.vpmb, vpmbConservatism: 2,
    );
    expect(result.algorithm, DecoAlgorithm.vpmb);
  });

  test('cache hit returns same instance for same key', () {
    final engine = DecoReplayEngine();
    final r1 = engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.zhl16c, gfLow: 30, gfHigh: 85,
    );
    final r2 = engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.zhl16c, gfLow: 30, gfHigh: 85,
    );
    expect(identical(r1, r2), isTrue);
    expect(engine.cacheSize, 1);
  });

  test('different algorithm → cache miss', () {
    final engine = DecoReplayEngine();
    engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.zhl16c, gfLow: 30, gfHigh: 85,
    );
    engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.vpmb, vpmbConservatism: 2,
    );
    expect(engine.cacheSize, 2);
  });

  test('different VPM-B conservatism → cache miss', () {
    final engine = DecoReplayEngine();
    engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.vpmb, vpmbConservatism: 0,
    );
    engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.vpmb, vpmbConservatism: 4,
    );
    expect(engine.cacheSize, 2);
  });

  test('LRU eviction when cache exceeds 16 entries', () {
    final engine = DecoReplayEngine();
    // 17 distinct dive IDs
    for (var i = 0; i < 17; i++) {
      engine.replay(
        diveId: 'dive_$i', samples: samples, gasMixes: gasMixes,
        algorithm: DecoAlgorithm.zhl16c, gfLow: 30, gfHigh: 85,
      );
    }
    expect(engine.cacheSize, 16);
  });

  test('clearCache empties it', () {
    final engine = DecoReplayEngine();
    engine.replay(
      diveId: 'd1', samples: samples, gasMixes: gasMixes,
      algorithm: DecoAlgorithm.zhl16c, gfLow: 30, gfHigh: 85,
    );
    expect(engine.cacheSize, 1);
    engine.clearCache();
    expect(engine.cacheSize, 0);
  });
}
