import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('readDeviceInfo returns Petrel 3 info', () async {
    final mock = MockBleTransport();
    await mock.connectMock();
    final info = await mock.readDeviceInfo();
    expect(info.serial, equals('B89641E4'));
    expect(info.model, equals(ShearwaterModel.petrel3));
    expect(info.firmware, contains('V103'));
  });

  test('readManifest returns 8 fixture entries', () async {
    final mock = MockBleTransport();
    await mock.connectMock();
    await mock.readDeviceInfo();
    final manifest = await mock.readManifest();
    expect(manifest.length, equals(8));
    expect(manifest.first.diveNumber, greaterThan(0));
  });

  test('downloadDives yields one blob per manifest entry', () async {
    final mock = MockBleTransport(perDiveDelay: Duration.zero);
    await mock.connectMock();
    await mock.readDeviceInfo();
    final manifest = await mock.readManifest();
    final dives = await mock.downloadDives(manifest).toList();
    expect(dives.length, equals(8));
    for (final dive in dives) {
      expect(dive.data.length, greaterThan(0));
    }
  });
}
