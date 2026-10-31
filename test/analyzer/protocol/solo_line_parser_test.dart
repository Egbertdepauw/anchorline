import 'package:ccrlogger/analyzer/protocol/solo_line_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// The trimix lines below are synthetic, modelled on the prototype's demo
// generator (docs/prototypes/solo-live.html, startDemo). Real captures
// from a trimix SOLO are tested in solo_fixture_test.dart.

void main() {
  group('parseSoloLine', () {
    test('documented SOLO O2 line', () {
      final r = parseSoloLine(
        'O2 21.1 % Ti 23.9 ~C 1004.1 hPa 2021/12/20 12:03:00',
      );
      expect(r, isNotNull);
      expect(r!.o2, 21.1);
      expect(r.he, 0, reason: 'O2-only SOLO has no He key');
      expect(r.tempC, 23.9);
      expect(r.baroHpa, 1004.1);
      expect(r.deviceTime, DateTime(2021, 12, 20, 12, 3, 0));
      expect(r.deviceTime!.isUtc, isFalse);
      expect(r.raw, 'O2 21.1 % Ti 23.9 ~C 1004.1 hPa 2021/12/20 12:03:00');
    });

    test('trimix SOLO line (synthetic, prototype shape)', () {
      final r = parseSoloLine(
        'He 45.1 O2 18.2 % Ti 21.4 ~C 1013.2 hPa 2026/10/27 20:30:05',
      );
      expect(r, isNotNull);
      expect(r!.o2, 18.2);
      expect(r.he, 45.1);
      expect(r.tempC, 21.4);
      expect(r.baroHpa, 1013.2);
      expect(r.deviceTime, DateTime(2026, 10, 27, 20, 30, 5));
    });

    test('asterisk field becomes NaN, others still parse', () {
      final r = parseSoloLine(
        'He ***.* O2 20.9 % Ti 22.0 ~C 1010.0 hPa 2026/10/27 20:30:00',
      );
      expect(r, isNotNull);
      expect(r!.he!.isNaN, isTrue);
      expect(r.o2, 20.9);
      expect(r.tempC, 22.0);
    });

    test('all measurement fields as asterisks', () {
      final r = parseSoloLine(
        'He ***.* O2 ***.* % Ti **.* ~C ****.* hPa 2026/10/27 20:30:00',
      );
      expect(r, isNotNull);
      expect(r!.o2!.isNaN, isTrue);
      expect(r.he!.isNaN, isTrue);
      expect(r.tempC!.isNaN, isTrue);
      expect(r.baroHpa!.isNaN, isTrue);
      expect(r.deviceTime, DateTime(2026, 10, 27, 20, 30, 0));
    });

    test('garbage line returns null', () {
      expect(parseSoloLine('Divesoft SOLO v1.2 ready'), isNull);
      expect(parseSoloLine(r'@#$%^&*()'), isNull);
      expect(
        parseSoloLine('O2 abc %'),
        isNull,
        reason: 'O2 key without a number is not a reading',
      );
    });

    test('empty and whitespace-only lines return null', () {
      expect(parseSoloLine(''), isNull);
      expect(parseSoloLine('   '), isNull);
      expect(parseSoloLine('\r\n'), isNull);
    });

    test('partial line without CRLF', () {
      final r = parseSoloLine('He 35.0 O2 20.9 % Ti 23');
      expect(r, isNotNull);
      expect(r!.o2, 20.9);
      expect(r.he, 35.0);
      expect(r.tempC, 23);
      expect(r.baroHpa, isNull);
      expect(r.deviceTime, isNull);
    });

    test('CRLF-terminated line strips terminators from raw', () {
      const body = 'O2 21.1 % Ti 23.9 ~C 1004.1 hPa 2021/12/20 12:03:00';
      for (final line in ['$body\r\n', '$body\r', '$body\n']) {
        final r = parseSoloLine(line);
        expect(r, isNotNull);
        expect(r!.raw, body);
        expect(r.o2, 21.1);
        expect(r.deviceTime, DateTime(2021, 12, 20, 12, 3, 0));
      }
    });

    test('extra whitespace is tolerated', () {
      final r = parseSoloLine(
        '  He   35.0\tO2  20.9 %  Ti 23.9 ~C   1004.1  hPa  2026/10/27  20:30:00  ',
      );
      expect(r, isNotNull);
      expect(r!.he, 35.0);
      expect(r.o2, 20.9);
      expect(r.baroHpa, 1004.1);
      expect(r.deviceTime, DateTime(2026, 10, 27, 20, 30, 0));
    });

    test('older He/O2 analyzer format', () {
      final r = parseSoloLine('He 035.0 O2 020.9\r\n');
      expect(r, isNotNull);
      expect(r!.he, 35.0);
      expect(r.o2, 20.9);
      expect(r.tempC, isNull);
      expect(r.baroHpa, isNull);
      expect(r.deviceTime, isNull);
    });

    test('He field without O2 is not a reading', () {
      expect(parseSoloLine('He 35.0'), isNull);
    });

    test('O2-only line reports he = 0', () {
      final r = parseSoloLine('O2 99.5 %');
      expect(r, isNotNull);
      expect(r!.o2, 99.5);
      expect(r.he, 0);
    });

    test('malformed timestamp yields null deviceTime', () {
      final r = parseSoloLine(
        'O2 21.1 % Ti 23.9 ~C 1004.1 hPa 2021/13/40 25:03:00',
      );
      expect(r, isNotNull);
      expect(r!.o2, 21.1);
      expect(r.deviceTime, isNull);
    });
  });
}
