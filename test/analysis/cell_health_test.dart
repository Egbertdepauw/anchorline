import 'package:ccrlogger/analysis/cell_health.dart';
import 'package:flutter_test/flutter_test.dart';

({DateTime start, double peakMv}) p(DateTime t, double mv) =>
    (start: t, peakMv: mv);

void main() {
  final now = DateTime(2026, 4, 28);

  group('evaluateCellHealth', () {
    test('insufficientData when fewer than 5 dives', () {
      final h = evaluateCellHealth(
        now: now,
        installedDate: DateTime(2025, 10, 1),
        divePeaks: [
          p(DateTime(2025, 11, 1), 50.0),
          p(DateTime(2025, 12, 1), 50.0),
          p(DateTime(2026, 1, 1), 50.0),
          p(DateTime(2026, 2, 1), 50.0),
        ],
      );
      expect(h.diveCount, 4);
      expect(h.mvStatus, CellMvStatus.insufficientData);
      expect(h.baselinePeakMv, isNull);
      expect(h.recentPeakMv, isNull);
      expect(h.ageMonths, isNotNull);
    });

    test('healthy when recent peak >= 85% of baseline peak', () {
      final h = evaluateCellHealth(
        now: now,
        installedDate: DateTime(2025, 10, 1),
        divePeaks: [
          for (var i = 0; i < 5; i++) p(DateTime(2025, 11, 1 + i), 50.0),
          for (var i = 0; i < 5; i++) p(DateTime(2026, 2, 1 + i), 47.0),
        ],
      );
      expect(h.mvStatus, CellMvStatus.healthy);
      expect(h.baselinePeakMv, 50.0);
      expect(h.recentPeakMv, 47.0);
    });

    test('watch when 70% <= ratio < 85%', () {
      final h = evaluateCellHealth(
        now: now,
        installedDate: DateTime(2025, 10, 1),
        divePeaks: [
          for (var i = 0; i < 5; i++) p(DateTime(2025, 11, 1 + i), 50.0),
          for (var i = 0; i < 5; i++) p(DateTime(2026, 2, 1 + i), 38.0),
        ],
      );
      expect(h.mvStatus, CellMvStatus.watch);
      // 38 / 50 = 0.76
    });

    test('replace when ratio < 70%', () {
      final h = evaluateCellHealth(
        now: now,
        installedDate: DateTime(2025, 10, 1),
        divePeaks: [
          for (var i = 0; i < 5; i++) p(DateTime(2025, 11, 1 + i), 50.0),
          for (var i = 0; i < 5; i++) p(DateTime(2026, 2, 1 + i), 30.0),
        ],
      );
      expect(h.mvStatus, CellMvStatus.replace);
    });

    test('ageMonths null when installedDate is null', () {
      final h = evaluateCellHealth(
        now: now,
        installedDate: null,
        divePeaks: const [],
      );
      expect(h.ageMonths, isNull);
      expect(h.diveCount, 0);
      expect(h.mvStatus, CellMvStatus.insufficientData);
    });

    test('uses max-of-window for both ends, not the strict last entry', () {
      // Recent window has one outlier high reading mixed in; that should
      // raise the recent peak even if the very last reading is low.
      final h = evaluateCellHealth(
        now: now,
        installedDate: DateTime(2025, 10, 1),
        divePeaks: [
          for (var i = 0; i < 5; i++) p(DateTime(2025, 11, 1 + i), 50.0),
          // Last 5: low/low/low/low + one strong recovery reading
          p(DateTime(2026, 1, 1), 30.0),
          p(DateTime(2026, 1, 5), 30.0),
          p(DateTime(2026, 1, 10), 30.0),
          p(DateTime(2026, 1, 15), 48.0),
          p(DateTime(2026, 1, 20), 30.0),
        ],
      );
      expect(h.recentPeakMv, 48.0);
      expect(h.mvStatus, CellMvStatus.healthy);
    });

    test('ageMonths is real-valued from days / 30.44', () {
      final h = evaluateCellHealth(
        now: DateTime(2026, 4, 28),
        installedDate: DateTime(2025, 7, 14),
        divePeaks: const [],
      );
      // 288 days ≈ 9.46 months
      expect(h.ageMonths, closeTo(9.46, 0.05));
    });
  });
}
