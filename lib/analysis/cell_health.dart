/// Pure-Dart cell health heuristics.
///
/// No Flutter, no DB. Callers feed `(diveStartTime, peakMvForSlot)` tuples;
/// the equipment DAO has a thin adapter that wires real data into this.
library;

enum CellMvStatus { insufficientData, healthy, watch, replace }

class CellHealth {
  final double? ageMonths;
  final int diveCount;
  final CellMvStatus mvStatus;
  final double? baselinePeakMv;
  final double? recentPeakMv;

  const CellHealth({
    required this.ageMonths,
    required this.diveCount,
    required this.mvStatus,
    required this.baselinePeakMv,
    required this.recentPeakMv,
  });
}

/// Computes [CellHealth] from a chronologically-sorted list of
/// `(diveStartTime, peakMvForSlot)` tuples within the cell's
/// install/retire window.
///
/// Pass [installedDate] separately so the age component degrades
/// gracefully when the user hasn't recorded an install date.
CellHealth evaluateCellHealth({
  required DateTime now,
  required DateTime? installedDate,
  required List<({DateTime start, double peakMv})> divePeaks,
}) {
  final sorted = [...divePeaks]..sort((a, b) => a.start.compareTo(b.start));
  final n = sorted.length;

  double? ageMonths;
  if (installedDate != null) {
    ageMonths = now.difference(installedDate).inDays / 30.44;
  }

  if (n < 5) {
    return CellHealth(
      ageMonths: ageMonths,
      diveCount: n,
      mvStatus: CellMvStatus.insufficientData,
      baselinePeakMv: null,
      recentPeakMv: null,
    );
  }

  double maxOf(Iterable<({DateTime start, double peakMv})> xs) =>
      xs.map((p) => p.peakMv).reduce((a, b) => a > b ? a : b);

  final baselinePeak = maxOf(sorted.take(5));
  final recentPeak = maxOf(sorted.skip(n - 5));

  final CellMvStatus status;
  if (baselinePeak <= 0) {
    status = CellMvStatus.insufficientData;
  } else {
    final ratio = recentPeak / baselinePeak;
    if (ratio >= 0.85) {
      status = CellMvStatus.healthy;
    } else if (ratio >= 0.7) {
      status = CellMvStatus.watch;
    } else {
      status = CellMvStatus.replace;
    }
  }

  return CellHealth(
    ageMonths: ageMonths,
    diveCount: n,
    mvStatus: status,
    baselinePeakMv: baselinePeak,
    recentPeakMv: recentPeak,
  );
}
