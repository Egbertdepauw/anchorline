/// The part of a Shearwater connection that [ShearwaterDownloadSource] needs.
///
/// Implemented by the real BLE transport and by the mock transport, so the
/// download source never touches Bluetooth directly.
library;

import 'dart:typed_data';

import '../parser/manifest_parser.dart';
import 'shearwater_ble_transport.dart';

abstract interface class ShearwaterLink {
  Future<DeviceInfo> readDeviceInfo();

  /// Pass [lastFingerprint] for incremental sync; implementations that cannot
  /// filter (the mock) ignore it.
  Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint});

  Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries);

  Future<void> disconnect();
}
