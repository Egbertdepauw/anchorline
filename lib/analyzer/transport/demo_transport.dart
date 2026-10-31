/// Simulated Divesoft SOLO trimix analyzer, for UI work and widget tests.
///
/// Mirrors `startDemo()` in `docs/prototypes/solo-live.html`: the analyzer
/// first reads air, gas starts flowing after [DemoAnalyzerTransport.
/// gasArrivesAfter], and the readings then settle exponentially onto the
/// target mix (18.2 % O2 / 45.1 % He by default) with a little sensor
/// noise. One line per [DemoAnalyzerTransport.sampleInterval] (200 ms by
/// default: the real trimix SOLO sends ~5 lines per second, #127), in the
/// real SOLO trimix line format, so every line goes through
/// `parseSoloLine` exactly like hardware output. The settling curve is
/// defined per second of simulated time, so it looks the same at any
/// interval.
///
/// Pure Dart. Timing runs on a [Timer], so inside `testWidgets` the
/// simulation is driven deterministically with `tester.pump(duration)`.
/// [DemoAnalyzerTransport.emitSample] advances it by hand without timers.
library;

import 'dart:async';
import 'dart:math';

import 'analyzer_transport.dart';

class DemoAnalyzerTransport implements AnalyzerTransport {
  DemoAnalyzerTransport({
    this.targetO2 = 18.2,
    this.targetHe = 45.1,
    this.gasArrivesAfter = const Duration(seconds: 3),
    this.sampleInterval = defaultSampleInterval,
    this.noiseAmplitude = 0.04,
    this.temperatureC = 21.4,
    this.pressureHpa = 1013.2,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random(),
        _clock = clock ?? DateTime.now;

  /// O2 % the readings settle on.
  final double targetO2;

  /// He % the readings settle on.
  final double targetHe;

  /// The real trimix SOLO's output rate: ~5 lines per second.
  static const Duration defaultSampleInterval = Duration(milliseconds: 200);

  /// Simulated time of plain air before the gas reaches the sensor.
  final Duration gasArrivesAfter;

  /// Time between lines.
  final Duration sampleInterval;

  /// Maximum noise added to each value, in percentage points (±).
  final double noiseAmplitude;

  final double temperatureC;
  final double pressureHpa;

  final Random _random;
  final DateTime Function() _clock;

  /// Approach factors per second of simulated time, as in the prototype
  /// (settles over ~10 s for O2, a little slower for He). Scaled to
  /// [sampleInterval] in [emitSample].
  static const double _o2ApproachPerSecond = 0.25;
  static const double _heApproachPerSecond = 0.22;

  double get _intervalSeconds =>
      sampleInterval.inMicroseconds / Duration.microsecondsPerSecond;

  /// Fraction of the remaining distance covered in one [sampleInterval],
  /// for a per-second approach factor [perSecond].
  double _approach(double perSecond) =>
      1 - pow(1 - perSecond, _intervalSeconds).toDouble();

  final StreamController<String> _lines = StreamController.broadcast();
  final StreamController<AnalyzerConnectionStatus> _status =
      StreamController.broadcast();

  AnalyzerConnectionStatus _current = AnalyzerConnectionStatus.disconnected;
  Timer? _timer;
  int _sample = 0;
  double _o2 = 20.9;
  double _he = 0;

  @override
  String get name => 'Demo';

  @override
  Stream<String> get lines => _lines.stream;

  @override
  AnalyzerConnectionStatus get status => _current;

  @override
  Stream<AnalyzerConnectionStatus> get statusChanges => _status.stream;

  @override
  String? get errorMessage => null;

  @override
  Future<void> connect() async {
    if (_current == AnalyzerConnectionStatus.connected) return;
    _setStatus(AnalyzerConnectionStatus.connecting);
    _sample = 0;
    _o2 = 20.9;
    _he = 0;
    _setStatus(AnalyzerConnectionStatus.connected);
    _timer = Timer.periodic(sampleInterval, (_) => emitSample());
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    if (_current != AnalyzerConnectionStatus.disconnected) {
      _setStatus(AnalyzerConnectionStatus.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    // Not awaited: a broadcast controller's done future only completes
    // once the done event is delivered, which callers need not wait for.
    unawaited(_lines.close());
    unawaited(_status.close());
  }

  /// Advances the simulation by one sample and emits its line. Called by
  /// the timer while connected; tests may call it directly.
  String emitSample() {
    _sample++;
    // Simulated time of this sample; the first one is at one interval.
    final elapsed = sampleInterval * _sample;
    if (elapsed > gasArrivesAfter) {
      _o2 += (targetO2 - _o2) * _approach(_o2ApproachPerSecond);
      _he += (targetHe - _he) * _approach(_heApproachPerSecond);
    }
    final line = formatLine(
      o2: _o2 + _noise(),
      he: max(0, _he + _noise()),
      tempC: temperatureC,
      baroHpa: pressureHpa,
      time: _clock(),
    );
    if (!_lines.isClosed) _lines.add(line);
    return line;
  }

  /// Formats one line exactly like a trimix SOLO:
  /// `He 45.1 O2 18.2 % Ti 21.4 ~C 1013.2 hPa 2026/10/27 20:30:00`.
  static String formatLine({
    required double o2,
    required double he,
    required double tempC,
    required double baroHpa,
    required DateTime time,
  }) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${time.year}/${two(time.month)}/${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return 'He ${he.toStringAsFixed(1)} O2 ${o2.toStringAsFixed(1)} % '
        'Ti ${tempC.toStringAsFixed(1)} ~C '
        '${baroHpa.toStringAsFixed(1)} hPa $stamp';
  }

  double _noise() => (_random.nextDouble() - 0.5) * 2 * noiseAmplitude;

  void _setStatus(AnalyzerConnectionStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }
}
