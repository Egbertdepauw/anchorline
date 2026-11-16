/// Mock BLE transport for testing and UI development.
///
/// Provides the same high-level methods as [ShearwaterBleTransport] without
/// real BLE hardware. Loads fixture dive blobs from bundled assets.
library;

import 'package:flutter/services.dart';

import 'package:subsurface_core/shearwater/parser/hardware.dart';
import '../parser/manifest_parser.dart';
import 'shearwater_ble_transport.dart';
import 'shearwater_link.dart';

/// Mock transport that simulates a Petrel 3 with 8 fixture dives.
///
/// Used by [ImportNotifier] when `useMock: true`, and directly in
/// `mock_ble_transport_test.dart`.
class MockBleTransport implements ShearwaterLink {
  DeviceInfo? _deviceInfo;

  /// Simulated delay per downloaded dive.
  final Duration perDiveDelay;

  MockBleTransport({this.perDiveDelay = const Duration(milliseconds: 500)});

  /// Simulate connecting to the device.
  Future<void> connectMock() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  /// Return a hard-coded [DeviceInfo] representing a Petrel 3.
  @override
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

  /// Start and end time of each bundled fixture dive, as the device's own
  /// manifest (test/fixtures/manifest.bin) lists them. They must match the
  /// blobs: the download source refuses a blob whose header disagrees with
  /// its manifest entry.
  static const _fixtureTimes = {
    711: (0x69BBE64F, 0x69BBF1BE),
    712: (0x69BD2F70, 0x69BD4012),
    713: (0x69BE9030, 0x69BE9C77),
    714: (0x69C8E8D6, 0x69C8F799),
    715: (0x69D11267, 0x69D11FD6),
    716: (0x69D22DA9, 0x69D23BC8),
    717: (0x69DB7DA4, 0x69DB82F6),
    718: (0x69E4A356, 0x69E4B0B5),
  };

  /// Return a manifest for the 8 bundled fixture dives.
  ///
  /// Dive numbers match the fixture filenames (dive_711.bin … dive_718.bin)
  /// and the times come from the real manifest; the fingerprints and flash
  /// addresses are synthetic. The entries are returned newest-first
  /// (highest dive number first), matching real device behavior.
  @override
  Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Build entries and reverse so newest (718) comes first.
    return _fixtureTimes.entries.map((t) {
      final n = t.key;
      final (start, end) = t.value;
      return ManifestEntry(
        header: 0xA5C4,
        diveNumber: n,
        fingerprint: Uint8List.fromList([0, 0, 0, n & 0xFF]),
        startTimestamp: start,
        endTimestamp: end,
        address: n * 0x10000,
        endAddress: n * 0x10000 + 0x10000,
      );
    }).toList().reversed.toList();
  }

  /// Yield events for each entry by loading the corresponding fixture
  /// asset. Each entry produces one [DownloadProgressEvent] (saturated
  /// at 100% — the mock has nothing to throttle and tests don't care
  /// about mid-transfer progress) followed by one [DownloadedDive].
  /// Entries without a matching asset file are silently skipped.
  @override
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
  @override
  Future<void> disconnect() async {}
}
