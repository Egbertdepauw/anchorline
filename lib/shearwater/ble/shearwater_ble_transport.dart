/// High-level Shearwater BLE transport: scan, connect, import dives.
///
/// Orchestrates the full import flow using [ShearwaterProtocol] and
/// the Shearwater parser. This is the main entry point for the app
/// to interact with a dive computer.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../parser/byte_reader.dart';
import '../parser/constants.dart';
import '../parser/hardware.dart';
import '../parser/manifest_parser.dart';
import 'ble_io_impl.dart';
import 'protocol.dart';

/// Information about the connected dive computer.
class DeviceInfo {
  final String serial;
  final String firmware;
  final int hardwareId;
  final ShearwaterModel model;
  final int baseAddress;

  DeviceInfo({
    required this.serial,
    required this.firmware,
    required this.hardwareId,
    required this.model,
    required this.baseAddress,
  });
}

/// Progress updates during dive import.
class ImportProgress {
  final ImportPhase phase;
  final int current;
  final int total;
  final String? message;

  ImportProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.message,
  });
}

enum ImportPhase { connecting, readingManifest, downloadingDives, done }

/// A downloaded dive blob with its manifest metadata.
class DownloadedDive {
  final ManifestEntry manifest;
  final Uint8List data; // Decompressed dive blob, ready for parsing.

  DownloadedDive({required this.manifest, required this.data});
}

/// Shearwater BLE transport — the main import interface.
///
/// Usage:
/// ```dart
/// final transport = ShearwaterBleTransport();
/// final device = await transport.scan().first;
/// await transport.connect(device);
/// final info = await transport.readDeviceInfo();
/// final manifest = await transport.readManifest();
/// await for (final dive in transport.downloadDives(manifest)) {
///   // Process each dive
/// }
/// await transport.disconnect();
/// ```
class ShearwaterBleTransport {
  /// Number of `0x36` block requests kept in flight when downloading a
  /// dive. Default 2 = "send the next request while still receiving the
  /// current one", which roughly halves wall time on slow BLE links if
  /// the Petrel firmware queues commands (verified empirically against
  /// Shearwater's own app, which is much faster than the strict
  /// sequential libdc protocol would allow). Set to 1 in trace-replay
  /// tests, where the recorded fixtures only support sequential order.
  final int divePipelineWindow;

  ShearwaterBleTransport({this.divePipelineWindow = 2});

  FlutterBluePlusBleIo? _bleIo;
  ShearwaterProtocol? _protocol;
  DeviceInfo? _deviceInfo;

  /// Scan for Shearwater dive computers.
  ///
  /// Returns a stream of discovered BLE devices advertising the
  /// Shearwater service UUID.
  Stream<BluetoothDevice> scan({Duration timeout = const Duration(seconds: 10)}) {
    return FlutterBluePlus.scanResults
        .expand((results) => results)
        .where((result) => result.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toLowerCase() ==
                shearwaterServiceUuid.toLowerCase()))
        .map((result) => result.device)
        .timeout(timeout);
  }

  /// Connect to a Shearwater dive computer.
  Future<void> connect(BluetoothDevice device) async {
    _bleIo = FlutterBluePlusBleIo(device);
    await _bleIo!.connect();
    _protocol = ShearwaterProtocol(_bleIo!);
  }

  /// Connect using an existing [BleIo] (for testing).
  void connectWithIo(BleIo io) {
    _protocol = ShearwaterProtocol(io);
  }

  /// Read device identification info.
  Future<DeviceInfo> readDeviceInfo() async {
    final p = _protocol!;

    final serialData = await p.rdbi(idSerial);
    final serial = String.fromCharCodes(serialData);

    final firmwareData = await p.rdbi(idFirmware);
    final firmware = String.fromCharCodes(firmwareData);

    final hwData = await p.rdbi(idHardware);
    final hardwareId = uint16BE(Uint8List.fromList(hwData), 0);
    final model = modelFromHardware(hardwareId);

    final logUploadData = await p.rdbi(idLogUpload);
    final baseAddress = (logUploadData[1] << 24) |
        (logUploadData[2] << 16) |
        (logUploadData[3] << 8) |
        logUploadData[4];

    _deviceInfo = DeviceInfo(
      serial: serial,
      firmware: firmware,
      hardwareId: hardwareId,
      model: model,
      baseAddress: _normalizeBaseAddress(baseAddress),
    );

    return _deviceInfo!;
  }

  /// Read the dive manifest (may download multiple pages).
  ///
  /// Pass [lastFingerprint] for incremental sync — dives newer than
  /// the fingerprint are returned.
  Future<List<ManifestEntry>> readManifest({
    Uint8List? lastFingerprint,
  }) async {
    final p = _protocol!;
    final allEntries = <ManifestEntry>[];

    while (true) {
      final data = await p.download(
        address: manifestAddr,
        size: manifestSize,
        compressed: false,
      );

      final entries = ManifestParser.parse(data);
      var count = 0;
      var deleted = 0;

      for (final entry in entries) {
        if (entry.isDeleted) {
          deleted++;
          continue;
        }
        if (!entry.isValid) break;

        // Stop at fingerprint if provided.
        if (lastFingerprint != null &&
            _fingerprintMatch(entry.fingerprint, lastFingerprint)) {
          return allEntries;
        }

        allEntries.add(entry);
        count++;
      }

      // If the page wasn't full, no more pages.
      if (count + deleted != manifestRecordCount) break;
    }

    return allEntries;
  }

  /// Download dives from the manifest, yielding each as it completes.
  ///
  /// Each dive is downloaded compressed from the device, decompressed,
  /// and yielded as a [DownloadedDive] with the raw blob ready for parsing.
  Stream<DownloadedDive> downloadDives(List<ManifestEntry> manifest) async* {
    final p = _protocol!;
    final info = _deviceInfo!;

    // Re-nudge the link to high priority before the bulk transfer starts.
    // Android often silently drops the request made at connect() time but
    // accepts it once the GATT link has done real work.
    //
    // Then keep nudging every 6 s for the duration of the download.
    // Android's `requestConnectionPriority(HIGH)` is NOT sticky — empirically
    // the Petrel link reverts to balanced (~177 ms inter-notification gap,
    // matching ~537 ms/block) about 5–10 s after the last priority request,
    // unless we keep asserting it. Per-dive nudging isn't enough — a single
    // dive blob takes 30–60 s on a slow link, much longer than the timeout.
    //
    // Interval was 4 s; bumped to 6 s after the app was observed losing
    // connection mid-import. 6 s sits well under the ~8-10 s expiry but
    // halves the rate of LL parameter requests we put on the air.
    // We deliberately do NOT re-issue setPreferredPhy here — that produced
    // a fresh LL_PHY_REQ on every call and was the most likely culprit
    // for the mid-import disconnects.
    await _bleIo?.requestHighPerformanceLink();
    Timer? refresher;
    if (_bleIo != null) {
      refresher = Timer.periodic(const Duration(seconds: 6), (_) {
        // Fire-and-forget; the call itself shouldn't block the read loop.
        unawaited(_bleIo!.requestHighPerformanceLink());
      });
    }

    try {
      var firstDive = true;
      for (final entry in manifest) {
        if (!entry.isValid) continue;

        // Give the Petrel a beat between dives so its UDS state machine
        // can fully retire the previous session before we send a new
        // Init (0x35). Without this gap, on multi-dive imports the
        // second dive's Init occasionally lands while the Petrel is
        // still flushing latent NAK-side state, and the Petrel rejects
        // it with "ISO 14229: Trans Req. Seq." then drops the link.
        // 300 ms is empirically generous — Shearwater's own app pauses
        // about that long between dives in HCI snoops.
        if (!firstDive) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        firstDive = false;

        final address = info.baseAddress + entry.address;
        // The manifest records each dive's exact compressed size as the
        // gap between its start and end address. Pass that as the request
        // size — without it the Petrel happily streams the next-younger
        // dive's data right after this one because LRE end-markers only
        // fire at the very end of the on-flash log, not per dive.
        final size = entry.compressedSize > 0 && entry.compressedSize < 0xFFFFFF
            ? entry.compressedSize
            : 0xFFFFFF;
        debugPrint('download dive #${entry.diveNumber}: '
            'addr=0x${entry.address.toRadixString(16)} '
            'endAddr=0x${entry.endAddress.toRadixString(16)} '
            'compressedSize=${entry.compressedSize} '
            'requestSize=$size');
        try {
          final data = await p.download(
            address: address,
            size: size,
            compressed: true,
            pipelineWindow: divePipelineWindow,
          );
          yield DownloadedDive(manifest: entry, data: data);
        } catch (e, st) {
          // Surface the failure visibly. Without this the exception
          // unwinds through the stream consumer and the only sign of
          // trouble is the eventual BLE disconnect timeout — useless
          // for diagnosing which dive / which block / why.
          debugPrint('downloadDives: dive #${entry.diveNumber} '
              '(addr=0x${entry.address.toRadixString(16)}) FAILED: $e\n$st');
          rethrow;
        }
      }
    } finally {
      refresher?.cancel();
    }
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    // Send shutdown WDBI if connected.
    try {
      await _protocol?.wdbi(0x9020, Uint8List.fromList([0x00]));
    } catch (_) {
      // Best-effort shutdown.
    }
    await _bleIo?.disconnect();
    _bleIo = null;
    _protocol = null;
    _deviceInfo = null;
  }

  /// Normalize the base address per libdc logic.
  static int _normalizeBaseAddress(int addr) {
    return switch (addr) {
      0xDD000000 || 0xC0000000 || 0x90000000 => 0xC0000000,
      0x80000000 => 0x80000000,
      _ => addr, // Unknown — use as-is.
    };
  }

  static bool _fingerprintMatch(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
