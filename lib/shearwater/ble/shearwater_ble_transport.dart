/// High-level Shearwater BLE transport: scan, connect, import dives.
///
/// Orchestrates the full import flow using [ShearwaterProtocol] and
/// the Shearwater parser. This is the main entry point for the app
/// to interact with a dive computer.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_debug_logger.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../parser/byte_reader.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
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

/// Events emitted by [ShearwaterBleTransport.downloadDives] during an
/// import. A single bulk BLE transfer covers every dive in the manifest;
/// progress events stream live as bytes accumulate, dive events fire
/// once per demuxed dive after the transfer completes.
sealed class DownloadEvent {
  const DownloadEvent();
}

/// Periodic progress update during the bulk download.
///
/// The single-session download covers a flash range spanning [totalDives]
/// dives. As bytes accumulate, we attribute them to whichever manifest
/// entry the running compressed-byte count falls inside, expressed as
/// [diveIndex] (0-based) with [diveBytes] / [diveTotalBytes] for the
/// current dive's contribution.
class DownloadProgressEvent extends DownloadEvent {
  /// 0-based index into the manifest passed to `downloadDives`.
  final int diveIndex;

  /// Total number of dives in this import.
  final int totalDives;

  /// Compressed bytes attributed to the current dive so far. Capped to
  /// [diveTotalBytes] when the running cursor would otherwise exceed
  /// the manifest entry's flash range.
  final int diveBytes;

  /// Compressed allocation for the current dive — the dive's flash
  /// range size from the manifest (`endAddress - address`). This is an
  /// upper bound on what we'll receive for the dive, not the exact
  /// data length (the Petrel terminates each dive's actual data with
  /// an LRE end marker somewhere before the end of the allocation).
  final int diveTotalBytes;

  /// The manifest entry for the dive currently being downloaded — UI
  /// can surface dive number and start timestamp from this.
  final ManifestEntry currentEntry;

  const DownloadProgressEvent({
    required this.diveIndex,
    required this.totalDives,
    required this.diveBytes,
    required this.diveTotalBytes,
    required this.currentEntry,
  });
}

/// A downloaded dive blob with its manifest metadata.
class DownloadedDive extends DownloadEvent {
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
/// await for (final event in transport.downloadDives(manifest)) {
///   switch (event) {
///     case DownloadProgressEvent(): /* update UI */
///     case DownloadedDive(): /* parse + persist */
///   }
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

  /// Download dives from the manifest, yielding events as they happen.
  ///
  /// Issues a SINGLE [ShearwaterProtocol.download] call covering every
  /// dive in [manifest], then demuxes the resulting decompressed blob
  /// into per-dive records. Emits two kinds of [DownloadEvent]:
  ///
  /// * [DownloadProgressEvent] during the bulk transfer, throttled to
  ///   at most one update per 200 ms with an unthrottled extra event
  ///   each time the running byte count crosses into a new dive's flash
  ///   range — the boundary event is the most useful UX signal.
  /// * [DownloadedDive] once per dive after demux, in flash-address
  ///   order. Each is preceded by a final 100%-progress event for that
  ///   dive so the UI can briefly show a saturated bar.
  ///
  /// Why one big download instead of N small ones: the Petrel keeps UDS
  /// session state INDEPENDENTLY of the GATT link. After each per-dive
  /// download ends in a self-NAK 0x24 (the manifest's `endAddress` is a
  /// flash *allocation* boundary, not the data end, so the Petrel always
  /// runs off the actual dive bytes and rejects the next 0x36), the
  /// firmware's UDS state machine is wedged. On iOS this happened to
  /// recover by accident; on Android it didn't, and no combination of
  /// Quit / settle delay / RDBI ping / full GATT reconnect could
  /// unstick it. This matches libdivecomputer's Shearwater driver,
  /// which has always done one big download terminated cleanly by the
  /// LRE 0 end-marker at the very end of the on-flash log.
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> manifest) {
    late final StreamController<DownloadEvent> controller;
    controller = StreamController<DownloadEvent>(
      onListen: () {
        // Fire-and-forget — the controller takes care of bridging errors
        // and the close path. We can't `await` here because onListen
        // returns synchronously; the async body lives in _runDownload.
        unawaited(_runDownload(controller, manifest));
      },
    );
    return controller.stream;
  }

  Future<void> _runDownload(
    StreamController<DownloadEvent> controller,
    List<ManifestEntry> manifest,
  ) async {
    final p = _protocol!;
    final info = _deviceInfo!;

    // Filter + sort valid entries by flash address ascending. The Petrel
    // streams them out in address order in one continuous LRE stream.
    final entries = manifest.where((e) => e.isValid).toList()
      ..sort((a, b) => a.address.compareTo(b.address));
    if (entries.isEmpty) {
      await controller.close();
      return;
    }

    // Re-nudge the link to high priority before the bulk transfer starts.
    // Android often silently drops the request made at connect() time but
    // accepts it once the GATT link has done real work.
    //
    // Then keep nudging every 6 s for the duration of the download.
    // Android's `requestConnectionPriority(HIGH)` is NOT sticky — empirically
    // the Petrel link reverts to balanced (~177 ms inter-notification gap,
    // matching ~537 ms/block) about 5–10 s after the last priority request,
    // unless we keep asserting it. A multi-dive single-session download
    // can run for many minutes; without the refresher the link reverts
    // to balanced mid-transfer.
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
      // Per-dive downloads, libdc-style. Each Init carries size =
      // 0xFFFFFF (24-bit max) — the Petrel streams the dive's
      // actual compressed bytes and terminates cleanly via the
      // LRE 0 end-marker BEFORE running off the allocation
      // boundary. That avoids the self-NAK 0x24 path that wedged
      // the Petrel's UDS state machine on Android. Quit (0x37) is
      // then acked normally, the session retires, and the next
      // dive's Init lands cleanly. See libdc's
      // shearwater_petrel.c:334 + shearwater_common.c:420 for the
      // canonical reference (`DIVE_SIZE = 0xFFFFFF`).
      BleDebugLogger.instance.log(
          'per-dive downloads: ${entries.length} dive(s) at size=0xFFFFFF');

      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final address = info.baseAddress + entry.address;

        // Emit an "entered this dive" progress event so the UI
        // updates the header text immediately, even before the
        // first BLE block lands.
        if (!controller.isClosed) {
          controller.add(DownloadProgressEvent(
            diveIndex: i,
            totalDives: entries.length,
            diveBytes: 0,
            diveTotalBytes:
                entry.compressedSize > 0 ? entry.compressedSize : 1,
            currentEntry: entry,
          ));
        }

        BleDebugLogger.instance.log(
            'dive ${i + 1}/${entries.length}: '
            '#${entry.diveNumber} addr=0x${address.toRadixString(16)}');

        // ~5 Hz throttle on the streaming progress events. Boundary
        // events between dives are emitted unthrottled above (entry
        // event before, completion event after).
        var lastEmitMs = 0;
        final swatch = Stopwatch()..start();

        final Uint8List diveBytes;
        try {
          diveBytes = await p.download(
            address: address,
            size: 0xFFFFFF,
            compressed: true,
            // Force strict-sequential (window=1) for dive downloads.
            // With pipelining=2, the next-block request lands while
            // the Petrel is processing the LRE-end block, and the
            // overshoot reply is a NAK 0x24 that retires the session
            // on Petrel's side. Once that NAK is out, the Petrel
            // either drops the BLE link or ignores subsequent
            // Inits — both break multi-dive. libdc uses window=1 for
            // exactly this reason; we follow.
            pipelineWindow: 1,
            onProgress: (bytesRead, _) {
              if (controller.isClosed) return;
              final nowMs = swatch.elapsedMilliseconds;
              if (nowMs - lastEmitMs < 200) return;
              lastEmitMs = nowMs;
              final total =
                  entry.compressedSize > 0 ? entry.compressedSize : bytesRead;
              controller.add(DownloadProgressEvent(
                diveIndex: i,
                totalDives: entries.length,
                diveBytes: bytesRead > total ? total : bytesRead,
                diveTotalBytes: total,
                currentEntry: entry,
              ));
            },
          );
        } catch (e, st) {
          debugPrint('downloadDives: dive #${entry.diveNumber} '
              '(addr=0x${address.toRadixString(16)}) FAILED: $e\n$st');
          rethrow;
        }

        BleDebugLogger.instance.log(
            'dive ${i + 1}/${entries.length}: #${entry.diveNumber} done '
            '(${diveBytes.length} decompressed bytes)');

        if (!controller.isClosed) {
          // Saturated 100% event before the dive lands.
          controller.add(DownloadProgressEvent(
            diveIndex: i,
            totalDives: entries.length,
            diveBytes:
                entry.compressedSize > 0 ? entry.compressedSize : diveBytes.length,
            diveTotalBytes:
                entry.compressedSize > 0 ? entry.compressedSize : diveBytes.length,
            currentEntry: entry,
          ));
          controller.add(DownloadedDive(manifest: entry, data: diveBytes));
        }
      }
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      refresher?.cancel();
      if (!controller.isClosed) await controller.close();
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
