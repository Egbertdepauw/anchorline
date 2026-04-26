import 'package:ccrlogger/ui/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDepth', () {
    test('formats depth in meters from mm', () {
      expect(formatDepth(28400), equals('28.4m'));
    });
    test('formats shallow depth', () {
      expect(formatDepth(1200), equals('1.2m'));
    });
    test('formats zero depth', () {
      expect(formatDepth(0), equals('0.0m'));
    });
  });

  group('formatDuration', () {
    test('formats minutes only', () {
      expect(formatDuration(3428), equals('57min'));
    });
    test('formats hours and minutes', () {
      expect(formatDuration(7200), equals('2h 0min'));
    });
    test('formats hours and minutes mixed', () {
      expect(formatDuration(5520), equals('1h 32min'));
    });
  });

  group('formatDate', () {
    test('formats unix timestamp to short date', () {
      expect(formatDateShort(1776591525), equals('19 Apr'));
    });
  });

  group('formatMonthYear', () {
    test('formats unix timestamp to month year', () {
      expect(formatMonthYear(1776591525), equals('April 2026'));
    });
  });

  group('formatGf', () {
    test('formats GF low/high', () {
      expect(formatGf(35, 75), equals('GF 35/75'));
    });
    test('returns empty for null values', () {
      expect(formatGf(null, null), equals(''));
    });
  });
}
