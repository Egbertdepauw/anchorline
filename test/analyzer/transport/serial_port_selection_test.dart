import 'package:ccrlogger/analyzer/transport/serial_port_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rankSerialPorts', () {
    test('macOS: only cu.* callout ports, usbmodem first, consoles hidden',
        () {
      final ranked = rankSerialPorts([
        '/dev/tty.usbmodem101',
        '/dev/cu.Bluetooth-Incoming-Port',
        '/dev/cu.debug-console',
        '/dev/cu.usbserial-A10',
        '/dev/cu.usbmodem101',
        '/dev/null',
        '/dev/disk0',
      ]);
      expect(ranked, ['/dev/cu.usbmodem101', '/dev/cu.usbserial-A10']);
    });

    test('Linux: ttyACM before ttyUSB, plain ttys hidden', () {
      final ranked = rankSerialPorts([
        '/dev/tty0',
        '/dev/ttyS0',
        '/dev/ttyUSB0',
        '/dev/ttyACM1',
        '/dev/ttyACM0',
      ]);
      expect(ranked, ['/dev/ttyACM0', '/dev/ttyACM1', '/dev/ttyUSB0']);
    });

    test('Windows: COM ports sorted numerically, duplicates removed', () {
      expect(rankSerialPorts(['COM10', 'COM3', 'COM9', 'COM3']),
          ['COM3', 'COM9', 'COM10']);
    });
  });

  group('preselectSerialPort', () {
    test('prefers the previously used port when still present', () {
      expect(
        preselectSerialPort(['/dev/cu.usbmodem101', '/dev/cu.usbmodem201'],
            previous: '/dev/cu.usbmodem201'),
        '/dev/cu.usbmodem201',
      );
    });

    test('falls back to the first likely analyzer port', () {
      expect(
        preselectSerialPort(['/dev/cu.usbmodem101', '/dev/cu.usbserial-A'],
            previous: '/dev/cu.gone'),
        '/dev/cu.usbmodem101',
      );
      expect(preselectSerialPort(['/dev/ttyACM0', '/dev/ttyUSB0']),
          '/dev/ttyACM0');
    });

    test('picks the only port, otherwise nothing', () {
      expect(preselectSerialPort(['COM4']), 'COM4');
      expect(preselectSerialPort(['COM3', 'COM4']), isNull);
      expect(preselectSerialPort([]), isNull);
    });
  });
}
