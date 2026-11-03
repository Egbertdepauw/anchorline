import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('printerFaultMessage', () {
    test('has the exact user-facing copy for every fault', () {
      expect(
        printerFaultMessage(PrinterFault.noLabels),
        'Out of labels, or the cover is open',
      );
      expect(
        printerFaultMessage(PrinterFault.coverOpen),
        'Printer cover is open',
      );
      expect(
        printerFaultMessage(PrinterFault.overheated),
        'Printer is overheated. Let it cool down.',
      );
      expect(
        printerFaultMessage(PrinterFault.lowBattery),
        'Printer battery is low',
      );
    });
  });

  group('isFatalPrinterFault', () {
    test('everything except lowBattery is fatal', () {
      expect(isFatalPrinterFault(PrinterFault.noLabels), isTrue);
      expect(isFatalPrinterFault(PrinterFault.coverOpen), isTrue);
      expect(isFatalPrinterFault(PrinterFault.overheated), isTrue);
      expect(isFatalPrinterFault(PrinterFault.lowBattery), isFalse);
    });
  });

  group('LabelPrinterException', () {
    test('toString is the message', () {
      const e = LabelPrinterException('Printer not found');
      expect(e.toString(), 'Printer not found');
      expect(e.fault, isNull);
    });

    test('carries the fault', () {
      const e = LabelPrinterException(
        'Out of labels, or the cover is open',
        fault: PrinterFault.noLabels,
      );
      expect(e.fault, PrinterFault.noLabels);
      expect('$e', 'Out of labels, or the cover is open');
    });
  });

  test('FoundLabelPrinter carries id and name', () {
    const p = FoundLabelPrinter(id: 'AA:BB', name: 'Q199A1B2');
    expect(p.id, 'AA:BB');
    expect(p.name, 'Q199A1B2');
  });
}
