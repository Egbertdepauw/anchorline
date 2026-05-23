/// Mock BLE transport for testing and UI development.
///
/// Provides the same high-level methods as [ShearwaterBleTransport] without
/// real BLE hardware. Loads fixture dive blobs from bundled assets.
library;

import 'package:flutter/services.dart';

import '../parser/hardware.dart';
import '../parser/manifest_parser.dart';
import 'shearwater_ble_transport.dart';

/// Mock transport that simulates a Petrel 3 with 8 fixture dives.
///
/// Used by [ImportNotifier] when `useMock: true`, and directly in
/// `mock_ble_transport_test.dart`.
class MockBleTransport {
  DeviceInfo? _deviceInfo;

  /// Simulated delay per downloaded dive.
  final Duration perDiveDelay;

  MockBleTransport({this.perDiveDelay = const Duration(milliseconds: 500)});

  /// Simulate connecting to the device.
  Future<void> connectMock() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  /// Return a hard-coded [DeviceInfo] representing a Petrel 3.
  Future<DeviceInfo> readDeviceInfo() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _deviceInfo = DeviceInfo(
      serial: 'B89641E4',
      firmware: 'V103 DiveCAN',
      hardwareId: 0xB407,
      model: ShearwaterModel.petrel3,
      baseAddress: 0x80000000,
    );
    return _deviceInfo!;
  }

  /// Return a synthetic manifest for the 8 bundled fixture dives.
  ///
  /// Dive numbers match the fixture filenames (dive_711.bin … dive_718.bin).
  /// The entries are returned newest-first (highest dive number first),
  /// matching real device behavior.
  Future<List<ManifestEntry>> readManifest() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    const diveNumbers = [711, 712, 713, 714, 715, 716, 717, 718];
    // Build entries and reverse so newest (718) comes first.
    return diveNumbers.map((n) => ManifestEntry(
          header: 0xA5C4,
          diveNumber: n,
          fingerprint: Uint8List.fromList([0, 0, 0, n & 0xFF]),
          startTimestamp: 1776591525 + (n - 711) * 86400,
          endTimestamp: 1776591525 + (n - 711) * 86400 + 3600,
          address: n * 0x10000,
          endAddress: n * 0x10000 + 0x10000,
        )).toList().reversed.toList();
  }

  /// Yield events for each entry by loading the corresponding fixture
  /// asset. Each entry produces one [DownloadProgressEvent] (saturated
  /// at 100% — the mock has nothing to throttle and tests don't care
  /// about mid-transfer progress) followed by one [DownloadedDive].
  /// Entries without a matching asset file are silently skipped.
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> manifest) async* {
    final valid = manifest.where((e) => e.isValid).toList();
    for (var i = 0; i < valid.length; i++) {
      final entry = valid[i];
      await Future<void>.delayed(perDiveDelay);
      try {
        final byteData = await rootBundle
            .load('test/fixtures/dives/dive_${entry.diveNumber}.bin');
        final total = entry.compressedSize;
        yield DownloadProgressEvent(
          diveIndex: i,
          totalDives: valid.length,
          diveBytes: total,
          diveTotalBytes: total,
          currentEntry: entry,
        );
        yield DownloadedDive(
          manifest: entry,
          data: byteData.buffer.asUint8List(),
        );
      } catch (_) {
        // Skip dives without fixture files.
      }
    }
  }

  /// No-op disconnect.
  Future<void> disconnect() async {}
}
