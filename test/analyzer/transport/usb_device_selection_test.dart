import 'package:ccrlogger/analyzer/transport/usb_device_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keyboard = UsbDeviceInfo(
    deviceName: '/dev/bus/usb/001/002',
    vendorId: 0x046d,
    productId: 0xc31c,
    interfaceClasses: [3], // HID
  );
  const flashDrive = UsbDeviceInfo(
    deviceName: '/dev/bus/usb/001/003',
    vendorId: 0x0781,
    productId: 0x5567,
    interfaceClasses: [8], // mass storage
  );
  const cdcComposite = UsbDeviceInfo(
    deviceName: '/dev/bus/usb/001/004',
    vendorId: 0x1234,
    productId: 0x0001,
    deviceClass: 0xEF, // misc / IAD
    interfaceClasses: [kUsbClassCdcComm, kUsbClassCdcData],
  );
  const cdcDeviceClass = UsbDeviceInfo(
    deviceName: '/dev/bus/usb/001/005',
    vendorId: 0x2345,
    productId: 0x0002,
    deviceClass: kUsbClassCdcComm,
  );

  test('isCdcSerial recognises CDC by device or interface class', () {
    expect(cdcComposite.isCdcSerial, isTrue);
    expect(cdcDeviceClass.isCdcSerial, isTrue);
    expect(keyboard.isCdcSerial, isFalse);
    expect(flashDrive.isCdcSerial, isFalse);
  });

  test('picks the first CDC serial device, ignoring others', () {
    expect(
      selectAnalyzerDevice([keyboard, flashDrive, cdcComposite, cdcDeviceClass]),
      same(cdcComposite),
    );
  });

  test('returns null when no CDC device is attached', () {
    expect(selectAnalyzerDevice([keyboard, flashDrive]), isNull);
    expect(selectAnalyzerDevice(const []), isNull);
  });

  test('an exact VID/PID match wins over earlier CDC devices', () {
    expect(
      selectAnalyzerDevice([cdcComposite, cdcDeviceClass],
          vendorId: 0x2345, productId: 0x0002),
      same(cdcDeviceClass),
    );
  });

  test('falls back to CDC when the known VID/PID is absent', () {
    expect(
      selectAnalyzerDevice([keyboard, cdcComposite],
          vendorId: 0x9999, productId: 0x9999),
      same(cdcComposite),
    );
  });

  test('VID-only match when no product ID is configured', () {
    expect(
      selectAnalyzerDevice([cdcComposite, cdcDeviceClass], vendorId: 0x2345),
      same(cdcDeviceClass),
    );
  });

  test('fromMap decodes the platform channel payload', () {
    final d = UsbDeviceInfo.fromMap(<Object?, Object?>{
      'deviceName': '/dev/bus/usb/002/007',
      'vendorId': 4660,
      'productId': 22136,
      'deviceClass': 0,
      'interfaceClasses': <Object?>[2, 10],
      'productName': 'SOLO',
      'manufacturerName': 'Divesoft',
      'hasPermission': true,
    });
    expect(d.deviceName, '/dev/bus/usb/002/007');
    expect(d.vendorId, 0x1234);
    expect(d.productId, 0x5678);
    expect(d.interfaceClasses, [2, 10]);
    expect(d.isCdcSerial, isTrue);
    expect(d.hasPermission, isTrue);
    expect(d.displayName, 'Divesoft SOLO');
  });

  test('displayName falls back to VID:PID', () {
    expect(cdcComposite.displayName, 'USB device 1234:0001');
  });
}
