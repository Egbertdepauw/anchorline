// Pure data types for the Statistics screen. No Flutter/Drift imports so the
// aggregator and its tests stay dependency-free.

/// Minimal per-dive input the aggregator needs (mapped from the Drift Dive row
/// by the notifier, keeping this layer Drift-free).
class StatsDiveInput {
  final String id;
  final int startTime; // epoch seconds (DC wall clock)
  final int durationSeconds;
  final int maxDepthMm;
  final int diveMode; // DiveMode.value
  const StatsDiveInput({
    required this.id,
    required this.startTime,
    required this.durationSeconds,
    required this.maxDepthMm,
    required this.diveMode,
  });
}

/// Per-dive values decoded from the sample blob (cached).
class DerivedStats {
  final double? minWaterTempC;
  final double? maxWaterTempC;
  final int timeInDecoSeconds;
  const DerivedStats({
    this.minWaterTempC,
    this.maxWaterTempC,
    this.timeInDecoSeconds = 0,
  });
}

/// A single headline record (raw value + source for the hint; UI formats it).
class RecordStat {
  final num value; // depthMm (int) | seconds (int) | tempC (double)
  final String? diveId;
  final int? startTime;
  final String? siteName;
  const RecordStat({
    required this.value,
    this.diveId,
    this.startTime,
    this.siteName,
  });
}

/// Total for one dive-mode bucket.
class ModeTotal {
  final String label; // "Closed circuit"
  final int representativeModeValue; // for diveModeColor(...)
  final int count;
  final int totalSeconds;
  const ModeTotal({
    required this.label,
    required this.representativeModeValue,
    required this.count,
    required this.totalSeconds,
  });
}

/// Stats for one period (a year, or a month within a year).
class PeriodStat {
  final int year;
  final int? month; // null for a year row; 1-12 for a month row
  final int diveCount;
  final int totalSeconds;
  final int maxDepthMm;
  final double? minWaterTempC;
  final List<PeriodStat> months; // child months for a year row; else const []
  const PeriodStat({
    required this.year,
    this.month,
    required this.diveCount,
    required this.totalSeconds,
    required this.maxDepthMm,
    this.minWaterTempC,
    this.months = const [],
  });
}

/// Everything the screen renders.
class StatsResult {
  final int totalDives;
  final int totalSeconds;
  final RecordStat? deepest;
  final RecordStat? longestDive;
  final RecordStat? longestDeco;
  final RecordStat? coldest;
  final RecordStat? warmest;
  final List<ModeTotal> modeTotals; // present buckets, count desc
  final List<PeriodStat> years; // newest first, each with months (newest first)
  const StatsResult({
    required this.totalDives,
    required this.totalSeconds,
    this.deepest,
    this.longestDive,
    this.longestDeco,
    this.coldest,
    this.warmest,
    this.modeTotals = const [],
    this.years = const [],
  });

  bool get isEmpty => totalDives == 0;
}
