import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
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

  test('each manifest entry describes the blob it is answered with', () async {
    final mock = MockBleTransport(perDiveDelay: Duration.zero);
    await mock.readDeviceInfo();
    final manifest = await mock.readManifest();
    final dives = (await mock.downloadDives(manifest).toList())
        .whereType<DownloadedDive>()
        .toList();
    expect(dives, hasLength(8));
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    for (final d in dives) {
      final header = parser.parse(d.data).header;
      expect(header.diveNumber, d.manifest.diveNumber);
      expect(header.startTimestamp, d.manifest.startTimestamp,
          reason: 'dive ${d.manifest.diveNumber}');
    }
  });

  test('downloadDives yields one blob per manifest entry', () async {
    final mock = MockBleTransport(perDiveDelay: Duration.zero);
    await mock.connectMock();
    await mock.readDeviceInfo();
    final manifest = await mock.readManifest();
    final events = await mock.downloadDives(manifest).toList();
    final dives = events.whereType<DownloadedDive>().toList();
    expect(dives.length, equals(8));
    for (final dive in dives) {
      expect(dive.data.length, greaterThan(0));
    }
    // Every dive event is preceded by a saturated progress event.
    final progress = events.whereType<DownloadProgressEvent>().toList();
    expect(progress.length, equals(8));
    expect(progress.first.totalDives, equals(8));
  });
}
