import 'package:ccrlogger/label_printer/phomemo/phomemo_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePhomemoNotification', () {
    test('1A 0F 0C is jobDone', () {
      expect(
        parsePhomemoNotification([0x1A, 0x0F, 0x0C]),
        PhomemoEvent.jobDone,
      );
    });

    test('1A 06 88 is noLabels', () {
      expect(
        parsePhomemoNotification([0x1A, 0x06, 0x88]),
        PhomemoEvent.noLabels,
      );
    });

    test('1A 05 98 is coverOpen', () {
      expect(
        parsePhomemoNotification([0x1A, 0x05, 0x98]),
        PhomemoEvent.coverOpen,
      );
    });

    test('1A 04 A4 is lowBattery', () {
      expect(
        parsePhomemoNotification([0x1A, 0x04, 0xA4]),
        PhomemoEvent.lowBattery,
      );
    });

    test('1A 05 99 (cover closed) is ignored', () {
      expect(parsePhomemoNotification([0x1A, 0x05, 0x99]), isNull);
    });

    test('other battery levels are ignored', () {
      expect(parsePhomemoNotification([0x1A, 0x04, 0x5A]), isNull);
    });

    test('the hot status 1A 03 xx is ignored until its value is known', () {
      expect(parsePhomemoNotification([0x1A, 0x03, 0xA9]), isNull);
    });

    test('the per-chunk ack 01 xx is ignored', () {
      expect(parsePhomemoNotification([0x01, 0x01]), isNull);
    });

    test('empty and unknown notifications are ignored', () {
      expect(parsePhomemoNotification([]), isNull);
      expect(parsePhomemoNotification([0x1A]), isNull);
      expect(parsePhomemoNotification([0xFF, 0xFF, 0xFF]), isNull);
    });

    test('a known status followed by extra bytes still matches', () {
      // SpoolmanScale and phomymo both read the status from the first bytes.
      expect(
        parsePhomemoNotification([0x1A, 0x0F, 0x0C, 0x00]),
        PhomemoEvent.jobDone,
      );
    });

    test('a known status cut short is ignored', () {
      expect(parsePhomemoNotification([0x1A, 0x0F]), isNull);
    });
  });
}
