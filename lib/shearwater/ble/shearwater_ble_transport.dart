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
import '../parser/constants.dart';
import '../parser/dive_parser.dart';
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
      // Build the single-session request covering every dive's range.
      // The manifest is on-flash so addresses are contiguous (or nearly
      // so — small flash-allocation gaps between dives are fine, the
      // Petrel just streams zero/junk for those bytes and the LRE
      // decoder skips them).
      final firstAddr = info.baseAddress + entries.first.address;
      final lastEndAddr = info.baseAddress + entries.last.endAddress;
      var totalSize = lastEndAddr - firstAddr;
      // The download Init opcode encodes size in 24 bits. Clamp and
      // rely on the LRE end-marker (which fires at the very end of the
      // on-flash log) to terminate the transfer.
      if (totalSize <= 0 || totalSize >= 0xFFFFFF) {
        totalSize = 0xFFFFFF;
      }

      BleDebugLogger.instance.log(
          'single-session download: ${entries.length} dive(s), '
          'addr=0x${firstAddr.toRadixString(16)} '
          'size=$totalSize bytes');

      // Per-dive compressed allocation, computed from the manifest's
      // flash ranges. Used to attribute the running compressed-byte
      // count to a specific dive during the bulk transfer.
      //
      // We deliberately key on `compressedSize` (endAddress - address)
      // rather than walking absolute flash addresses, because the
      // entries' `address` fields are relative to baseAddress and the
      // first dive's flash offset within the download is 0.
      final diveAllocations = [
        for (final e in entries) e.compressedSize,
      ];
      final totalAllocation =
          diveAllocations.fold<int>(0, (sum, n) => sum + n);
      // Cumulative byte offset where each dive's allocation ends. Used
      // to bucket the running compressed-byte count into a diveIndex.
      final cumulativeEnds = <int>[];
      var running = 0;
      for (final alloc in diveAllocations) {
        running += alloc;
        cumulativeEnds.add(running);
      }

      // Progress throttle: cap UI updates to ~5 Hz; always emit an
      // extra event when the running cursor crosses into a new dive.
      var lastEmitMs = 0;
      var lastDiveIndex = -1;
      final swatch = Stopwatch()..start();

      void emitProgress(int bytesRead, int reportedTotal) {
        if (controller.isClosed) return;
        // Find which dive the running cursor falls into. We compare
        // against the per-dive flash allocation, NOT the reportedTotal
        // (which is the clamped 0xFFFFFF or actual size requested at
        // Init). If bytesRead overflows the planned allocation total
        // — possible when totalSize was clamped to 0xFFFFFF and the
        // Petrel streamed past the last dive's endAddress — we cap to
        // the last dive at 100%.
        var diveIndex = lastDiveIndex < 0 ? 0 : lastDiveIndex;
        while (diveIndex < cumulativeEnds.length - 1 &&
            bytesRead >= cumulativeEnds[diveIndex]) {
          diveIndex++;
        }
        if (diveIndex >= entries.length) diveIndex = entries.length - 1;

        final crossedBoundary = diveIndex != lastDiveIndex;
        final nowMs = swatch.elapsedMilliseconds;
        if (!crossedBoundary && nowMs - lastEmitMs < 200) return;
        lastDiveIndex = diveIndex;
        lastEmitMs = nowMs;

        final entry = entries[diveIndex];
        final diveTotal = diveAllocations[diveIndex];
        final diveStart =
            diveIndex == 0 ? 0 : cumulativeEnds[diveIndex - 1];
        var diveBytes = bytesRead - diveStart;
        if (diveBytes < 0) diveBytes = 0;
        if (diveBytes > diveTotal) diveBytes = diveTotal;

        controller.add(DownloadProgressEvent(
          diveIndex: diveIndex,
          totalDives: entries.length,
          diveBytes: diveBytes,
          diveTotalBytes: diveTotal,
          currentEntry: entry,
        ));
      }

      final Uint8List blob;
      try {
        blob = await p.download(
          address: firstAddr,
          size: totalSize,
          compressed: true,
          pipelineWindow: divePipelineWindow,
          onProgress: (bytesRead, total) {
            // `total` is the size requested at Init (often clamped
            // to 0xFFFFFF). We map progress against the manifest's
            // per-dive flash allocations instead, falling back to
            // `totalAllocation` for the overall denominator.
            emitProgress(bytesRead, totalAllocation);
          },
        );
      } catch (e, st) {
        // Surface the failure visibly. Without this the exception
        // unwinds through the stream consumer and the only sign of
        // trouble is the eventual BLE disconnect timeout — useless
        // for diagnosing what blew up.
        debugPrint('downloadDives: single-session download FAILED: $e\n$st');
        rethrow;
      }

      BleDebugLogger.instance.log(
          'single-session download: decompressed to ${blob.length} bytes; '
          'demuxing into ${entries.length} dive(s)');

      // Demux the blob into individual dives. parseOne returns
      // bytesConsumed so we can advance the cursor; the parser walks
      // 32-byte records to the dive's [logRecordFinal] (0xFF) marker
      // and on past the on-flash 128-byte alignment pad — i.e. the
      // exact byte count one dive occupies on flash. Entries were
      // address-sorted above; parse order matches address order.
      final parser = ShearwaterDiveParser(model: info.model);
      var offset = 0;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (offset >= blob.length) {
          BleDebugLogger.instance.log(
              'demux: ran out of bytes at dive #${entry.diveNumber} '
              '(offset=$offset, blob=${blob.length}) — '
              '${entries.length - i} dive(s) skipped');
          break;
        }
        try {
          final result = parser.parseOne(blob, offset: offset);
          final endOffset = offset + result.bytesConsumed;
          final diveBytes = Uint8List.sublistView(blob, offset, endOffset);
          BleDebugLogger.instance.log(
              'demux: yielded dive #${entry.diveNumber} '
              'at offset=$offset, bytes=${result.bytesConsumed}');
          // Emit a saturated progress event for this dive so the UI
          // briefly shows 100% before flipping to "Saving…" for the
          // next index. Cheap; the UI throttles its own redraw.
          if (!controller.isClosed) {
            controller.add(DownloadProgressEvent(
              diveIndex: i,
              totalDives: entries.length,
              diveBytes: diveAllocations[i],
              diveTotalBytes: diveAllocations[i],
              currentEntry: entry,
            ));
            controller.add(DownloadedDive(manifest: entry, data: diveBytes));
          }
          offset = endOffset;
        } catch (e, st) {
          debugPrint('downloadDives: demux of dive #${entry.diveNumber} '
              '(offset=$offset) FAILED: $e\n$st');
          rethrow;
        }
      }
      BleDebugLogger.instance.log(
          'single-session download: done. final offset=$offset, '
          'blob.length=${blob.length}');
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
