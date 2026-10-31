/// Reading-stability detection for a live gas analyzer (Divesoft SOLO).
///
/// The SOLO emits O2/He readings several times per second (~5 Hz for the
/// trimix model). A galvanic O2 cell needs time to settle after gas starts
/// flowing, and the diver must not write the analysis on the cylinder until
/// the numbers have stopped moving. [StabilityDetector] watches a sliding
/// window of recent samples, measured in real time, and reports one of the
/// [ReadingStability] states.
///
/// Rule (v2, see docs/superpowers/specs/2026-10-27-gas-analyzer-solo-design.md
/// section 3, made time-based in #127): over the last
/// [StabilityDetector.defaultWindow] of real time (with at least
/// [StabilityDetector.defaultMinSamples] samples, and only once the data
/// actually spans the whole window), for BOTH O2 and He:
///
///  * spread (max − min) ≤ [StabilityDetector.defaultSpreadTolerance]
///    percentage points, AND
///  * |least-squares slope| ≤ [StabilityDetector.defaultMaxSlopePerSecond]
///    percentage points per second.
///
/// v1 (8 samples, spread ≤ 0.15, no slope term) flagged STABLE while the O2
/// cell was still drifting. The defaults below are still to be tuned against
/// real cylinders (air, EAN32, O2, hypoxic trimix), which is why every limit
/// can be overridden through the constructor.
///
/// Pure Dart: no Flutter, no I/O, so it can be unit-tested in isolation and
/// fed from any transport (USB serial, BLE bridge).
library;

/// What the UI shows in the stability pill.
enum ReadingStability {
  /// No sample received yet (or since the last [StabilityDetector.reset]).
  noData,

  /// Valid samples are arriving, but the window is not full yet or the
  /// readings are still moving.
  settling,

  /// The full window satisfies both the spread and the slope limits.
  stable,

  /// The latest sample has an unusable O2 or He value (the SOLO prints
  /// `***.*`, which the line parser maps to NaN).
  sensorError,
}

/// One analyzer reading as seen by the detector.
///
/// [seconds] is the sample time in seconds on an arbitrary but monotonic
/// time base; only differences between samples matter.
class StabilitySample {
  const StabilitySample({
    required this.seconds,
    required this.o2,
    required this.he,
  });

  final double seconds;

  /// O2 in percent.
  final double o2;

  /// He in percent (0 for an O2-only analyzer).
  final double he;
}

/// Sliding-window stability detector for O2/He readings.
///
/// The window is a span of real time, not a sample count, so the rule means
/// the same thing at any output rate (the SOLO trimix sends ~5 lines per
/// second, not the 1 Hz first assumed, see #127).
class StabilityDetector {
  /// Span of the window: the readings must have been steady for this long.
  static const Duration defaultWindow = Duration(seconds: 20);

  /// Minimum number of valid samples inside the window before it is judged.
  /// Guards against a window that spans 20 s but holds only a couple of
  /// samples (e.g. after a pause in the data stream).
  static const int defaultMinSamples = 10;

  /// Maximum allowed max − min within the window, in percentage points.
  static const double defaultSpreadTolerance = 0.2;

  /// Maximum allowed |least-squares slope| within the window, in percentage
  /// points per second of real time. This is the term that keeps a slowly
  /// drifting galvanic cell from being reported as stable.
  static const double defaultMaxSlopePerSecond = 0.01;

  StabilityDetector({
    this.window = defaultWindow,
    this.minSamples = defaultMinSamples,
    this.spreadTolerance = defaultSpreadTolerance,
    this.maxSlopePerSecond = defaultMaxSlopePerSecond,
  }) : assert(window > Duration.zero),
       assert(minSamples >= 2, 'a slope needs at least two samples'),
       assert(spreadTolerance >= 0),
       assert(maxSlopePerSecond >= 0);

  /// Span of real time the readings must be steady over.
  final Duration window;

  /// Minimum number of samples inside [window] before it can be stable.
  final int minSamples;
  final double spreadTolerance;
  final double maxSlopePerSecond;

  final List<StabilitySample> _samples = [];
  ReadingStability _state = ReadingStability.noData;

  /// Time of the most recent sample, used to synthesise 1 s spacing when the
  /// caller does not pass a time.
  double? _lastSeconds;

  /// Time of the first valid sample since the last reset or sensor error.
  /// The window only counts as full once the data reaches back a full
  /// [window] from the newest sample.
  double? _firstSeconds;

  double get _windowSeconds =>
      window.inMicroseconds / Duration.microsecondsPerSecond;

  /// The state after the most recent [add].
  ReadingStability get state => _state;

  /// Number of valid samples currently in the window.
  int get sampleCount => _samples.length;

  /// The samples currently in the window, oldest first.
  List<StabilitySample> get samples => List.unmodifiable(_samples);

  /// Feeds one reading and returns the resulting state.
  ///
  /// * [o2] null or NaN → [ReadingStability.sensorError]. A missing O2 value
  ///   is as unusable as `***.*`.
  /// * [he] NaN → [ReadingStability.sensorError].
  /// * [he] null means the analyzer has no He sensor (O2-only); He is then
  ///   treated as a constant 0, so only O2 decides stability. (The prototype
  ///   reports SENSOR ERROR here because `isFinite(undefined)` is false; that
  ///   would make an O2-only analyzer unusable.)
  ///
  /// A sensor error clears the window, so after recovery stability must be
  /// re-earned over a full fresh window. The prototype gets the same effect
  /// implicitly (a NaN in the window makes the spread NaN, failing the check
  /// until it scrolls out); clearing makes it explicit.
  ///
  /// The sample time is [elapsed] (time since an arbitrary monotonic
  /// origin, the preferred form) or [at]. When both are omitted the sample
  /// is assumed to be 1 s after the previous one. Slopes are computed in
  /// percentage points per second either way.
  ReadingStability add(
    double? o2,
    double? he, {
    Duration? elapsed,
    DateTime? at,
  }) {
    final seconds = elapsed != null
        ? elapsed.inMicroseconds / Duration.microsecondsPerSecond
        : at != null
        ? at.microsecondsSinceEpoch / Duration.microsecondsPerSecond
        : (_lastSeconds == null ? 0.0 : _lastSeconds! + 1.0);
    _lastSeconds = seconds;

    final heValue = he ?? 0.0;
    if (o2 == null || !o2.isFinite || !heValue.isFinite) {
      _samples.clear();
      _firstSeconds = null;
      return _state = ReadingStability.sensorError;
    }

    _firstSeconds ??= seconds;
    _samples.add(StabilitySample(seconds: seconds, o2: o2, he: heValue));
    final windowStart = seconds - _windowSeconds;
    while (_samples.first.seconds < windowStart) {
      _samples.removeAt(0);
    }

    // Small epsilon: microsecond timestamps converted to double seconds.
    final covered = seconds - _firstSeconds! >= _windowSeconds - 1e-6;
    if (!covered || _samples.length < minSamples) {
      return _state = ReadingStability.settling;
    }
    final stable =
        _channelStable(_samples.map((s) => s.o2).toList()) &&
        _channelStable(_samples.map((s) => s.he).toList());
    return _state = stable
        ? ReadingStability.stable
        : ReadingStability.settling;
  }

  /// Forgets all samples, e.g. when the cylinder changes or the analyzer
  /// reconnects.
  void reset() {
    _samples.clear();
    _lastSeconds = null;
    _firstSeconds = null;
    _state = ReadingStability.noData;
  }

  bool _channelStable(List<double> values) {
    var lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (hi - lo > spreadTolerance) return false;
    final times = _samples.map((s) => s.seconds).toList();
    return leastSquaresSlope(times, values).abs() <= maxSlopePerSecond;
  }

  /// Least-squares slope of [ys] against [xs] (units of y per unit of x).
  ///
  /// Returns 0 when the x values are degenerate (all equal), matching the
  /// prototype. x values are shifted to start at 0 to keep precision when
  /// they are large (epoch seconds).
  static double leastSquaresSlope(List<double> xs, List<double> ys) {
    assert(xs.length == ys.length);
    final n = xs.length;
    if (n < 2) return 0;
    final x0 = xs.first;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      final x = xs[i] - x0, y = ys[i];
      sx += x;
      sy += y;
      sxx += x * x;
      sxy += x * y;
    }
    final d = n * sxx - sx * sx;
    return d == 0 ? 0 : (n * sxy - sx * sy) / d;
  }
}
