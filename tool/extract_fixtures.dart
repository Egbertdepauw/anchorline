/// CLI tool to extract test fixtures from a Shearwater protocol trace.
///
/// Parses a combined.txt transcript (produced by extract_libdc_log.py),
/// replays the Shearwater protocol, and extracts:
///   - Device info (serial, firmware, hardware, base address)
///   - Raw manifest data
///   - Individual decompressed dive blobs
///
/// Usage:
///   dart run tool/extract_fixtures.dart [path/to/combined.txt]
///
/// Default input: ../subsurface2.combined.txt (relative to project root)
/// Output goes to test/fixtures/
library;

import 'dart:io';
import 'dart:typed_data';

// We use the project's own SLIP decoder and decompressor.
import 'package:ccrlogger/shearwater/parser/slip_decoder.dart';
import 'package:ccrlogger/shearwater/parser/decompressor.dart';

// ── Trace parsing ──────────────────────────────────────────────

class TraceEntry {
  final String direction; // 'W' or 'R'
  final Uint8List bytes;

  TraceEntry(this.direction, this.bytes);
}

List<TraceEntry> parseTrace(String text) {
  final entries = <TraceEntry>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final match = RegExp(r'^([WR]) \(\d+ bytes\): (.+)$').firstMatch(trimmed);
    if (match == null) {
      stderr.writeln('Warning: skipping unparseable line: $trimmed');
      continue;
    }

    final direction = match.group(1)!;
    final hexStr = match.group(2)!;
    final bytes = Uint8List.fromList(
      hexStr.split(' ').map((h) => int.parse(h, radix: 16)).toList(),
    );
    entries.add(TraceEntry(direction, bytes));
  }
  return entries;
}

// ── BLE frame reassembly + SLIP decode ─────────────────────────

/// Given a list of BLE frames (consecutive R entries forming one SLIP packet),
/// strip BLE headers, concatenate, and SLIP decode.
Uint8List decodeBleFrames(List<Uint8List> frames) {
  final builder = BytesBuilder(copy: false);
  for (final frame in frames) {
    // Strip 2-byte BLE header [nframes, frame_index]
    if (frame.length > 2) {
      builder.add(frame.sublist(2));
    }
  }
  return slipDecode(builder.toBytes());
}

/// Extract the transfer payload from a decoded SLIP packet.
/// Request:  [0xFF, 0x01, length, 0x00, ...payload]
/// Response: [0x01, 0xFF, length, 0x00, ...payload]
Uint8List stripTransferHeader(Uint8List packet) {
  if (packet.length < 4) return Uint8List(0);
  return packet.sublist(4);
}

// ── Protocol state machine ────────────────────────────────────

class DeviceInfo {
  String serial = '';
  String firmware = '';
  int hardware = 0;
  int baseAddress = 0;
}

class ManifestRecord {
  final int header; // 0xA5C4 = valid, 0x5A23 = deleted
  final int diveNumber;
  final Uint8List fingerprint; // 4 bytes at offset 4
  final int startTimestamp;
  final int endTimestamp;
  final int address; // offset 20, 4 bytes BE

  bool get isValid => header == 0xA5C4;
  bool get isDeleted => header == 0x5A23;

  ManifestRecord({
    required this.header,
    required this.diveNumber,
    required this.fingerprint,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.address,
  });

  factory ManifestRecord.fromBytes(Uint8List data, int offset) {
    return ManifestRecord(
      header: (data[offset] << 8) | data[offset + 1],
      diveNumber: (data[offset + 2] << 8) | data[offset + 3],
      fingerprint: data.sublist(offset + 4, offset + 8),
      startTimestamp: (data[offset + 8] << 24) |
          (data[offset + 9] << 16) |
          (data[offset + 10] << 8) |
          data[offset + 11],
      endTimestamp: (data[offset + 12] << 24) |
          (data[offset + 13] << 16) |
          (data[offset + 14] << 8) |
          data[offset + 15],
      address: (data[offset + 20] << 24) |
          (data[offset + 21] << 16) |
          (data[offset + 22] << 8) |
          data[offset + 23],
    );
  }
}

void main(List<String> args) {
  final projectDir = Directory.current.path;
  final defaultTrace = '$projectDir/../subsurface2.combined.txt';
  final tracePath = args.isNotEmpty ? args[0] : defaultTrace;

  final traceFile = File(tracePath);
  if (!traceFile.existsSync()) {
    stderr.writeln('Error: trace file not found: $tracePath');
    exit(1);
  }

  stdout.writeln('Parsing trace: $tracePath');
  final entries = parseTrace(traceFile.readAsStringSync());
  stdout.writeln('Found ${entries.length} trace entries');

  // ── Walk through entries, pair W/R transactions ──

  final deviceInfo = DeviceInfo();
  final manifestData = BytesBuilder(copy: false);
  final diveBlobs = <int, Uint8List>{}; // diveNumber → decompressed blob

  // Collect download state
  var inDownload = false;
  var downloadCompressed = false;
  var downloadAddress = 0;
  final downloadBlockData = BytesBuilder(copy: false);
  var downloadLreBuffer = BytesBuilder(copy: false);
  var downloadLreDone = false;

  var i = 0;
  while (i < entries.length) {
    final entry = entries[i];

    if (entry.direction == 'W') {
      // Decode the write to understand what command was sent
      final writePacket = decodeBleFrames([entry.bytes]);
      final writePayload = stripTransferHeader(writePacket);

      if (writePayload.isEmpty) {
        i++;
        continue;
      }

      final cmd = writePayload[0];

      // Collect the response(s) — consecutive R entries
      i++;
      final responseFrames = <Uint8List>[];
      while (i < entries.length && entries[i].direction == 'R') {
        responseFrames.add(entries[i].bytes);
        i++;
      }

      if (responseFrames.isEmpty) continue;

      final responsePacket = decodeBleFrames(responseFrames);
      final responsePayload = stripTransferHeader(responsePacket);

      if (responsePayload.isEmpty) continue;

      final rspCmd = responsePayload[0];

      // ── RDBI response ──
      if (cmd == 0x22 && rspCmd == 0x62 && responsePayload.length >= 3) {
        final id = (writePayload[1] << 8) | writePayload[2];
        final data = responsePayload.sublist(3);

        switch (id) {
          case 0x8010: // Serial
            deviceInfo.serial = String.fromCharCodes(data);
            stdout.writeln('  Serial: ${deviceInfo.serial}');
          case 0x8011: // Firmware
            deviceInfo.firmware = String.fromCharCodes(data);
            stdout.writeln('  Firmware: ${deviceInfo.firmware}');
          case 0x8050: // Hardware
            if (data.length >= 2) {
              deviceInfo.hardware = (data[0] << 8) | data[1];
              stdout.writeln(
                  '  Hardware: 0x${deviceInfo.hardware.toRadixString(16).toUpperCase().padLeft(4, '0')}');
            }
          case 0x8021: // Logupload config
            if (data.length >= 5) {
              deviceInfo.baseAddress =
                  (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
              stdout.writeln(
                  '  Base address: 0x${deviceInfo.baseAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}');
            }
        }
      }

      // ── Download init (0x35) ──
      else if (cmd == 0x35 && rspCmd == 0x75) {
        inDownload = true;
        downloadCompressed = writePayload[1] == 0x10;
        downloadAddress = (writePayload[3] << 24) |
            (writePayload[4] << 16) |
            (writePayload[5] << 8) |
            writePayload[6];
        downloadBlockData.clear();
        downloadLreBuffer = BytesBuilder(copy: false);
        downloadLreDone = false;

        final addrHex =
            downloadAddress.toRadixString(16).toUpperCase().padLeft(8, '0');
        final compStr = downloadCompressed ? 'compressed' : 'uncompressed';
        stdout.writeln('  Download init: 0x$addrHex ($compStr)');
      }

      // ── Download block (0x36) ──
      else if (cmd == 0x36 && rspCmd == 0x76 && inDownload) {
        // Block data starts after [0x76, block_num]
        final blockData = responsePayload.sublist(2);

        if (downloadCompressed) {
          // LRE decode each block, accumulate into buffer
          if (!downloadLreDone) {
            try {
              final lreResult = lreDecode(Uint8List.fromList(blockData));
              downloadLreBuffer.add(lreResult.data);
              if (lreResult.isFinal) {
                downloadLreDone = true;
              }
            } catch (e) {
              stderr.writeln(
                  '  Warning: LRE decode error on block ${responsePayload[1]}: $e');
              // Try partial — append raw
              downloadBlockData.add(blockData);
            }
          }
        } else {
          // Uncompressed: just accumulate
          downloadBlockData.add(blockData);
        }
      }

      // ── Download quit (0x37) ──
      else if (cmd == 0x37 && rspCmd == 0x77 && inDownload) {
        inDownload = false;

        if (downloadCompressed) {
          // XOR decode the accumulated LRE output
          final data = downloadLreBuffer.toBytes();
          xorDecode(data);
          _handleDownloadComplete(
              downloadAddress, data, deviceInfo, manifestData, diveBlobs);
        } else {
          // Uncompressed data is ready
          final data = downloadBlockData.toBytes();
          _handleDownloadComplete(
              downloadAddress, data, deviceInfo, manifestData, diveBlobs);
        }
      }

      // ── WDBI (0x2E) — shutdown etc, ignore ──
      // else: unknown command, skip
    } else {
      // Stray R without a preceding W — skip
      i++;
    }
  }

  // ── Parse manifest ──
  final rawManifest = manifestData.toBytes();
  stdout.writeln('\nManifest: ${rawManifest.length} bytes');

  final records = <ManifestRecord>[];
  var offset = 0;
  while (offset + 32 <= rawManifest.length) {
    final header = (rawManifest[offset] << 8) | rawManifest[offset + 1];
    if (header != 0xA5C4 && header != 0x5A23) break;
    records.add(ManifestRecord.fromBytes(rawManifest, offset));
    offset += 32;
  }

  final validRecords = records.where((r) => r.isValid).toList();
  final deletedRecords = records.where((r) => r.isDeleted).toList();
  stdout.writeln(
      'Manifest records: ${validRecords.length} valid, ${deletedRecords.length} deleted');

  // Build address → dive number lookup from manifest
  final addressToDiveNumber = <int, int>{};
  for (final r in validRecords) {
    addressToDiveNumber[r.address] = r.diveNumber;
  }

  for (final r in validRecords) {
    final ts = DateTime.fromMillisecondsSinceEpoch(r.startTimestamp * 1000,
        isUtc: true);
    final addrHex = r.address.toRadixString(16).padLeft(8, '0');
    final hasDive = diveBlobs.containsKey(r.address);
    stdout.writeln(
        '  Dive #${r.diveNumber}: $ts addr=0x$addrHex ${hasDive ? '✓' : '✗'}');
  }

  // ── Save fixtures ──
  final fixtureDir = '$projectDir/test/fixtures';

  // Save device info
  final infoFile = File('$fixtureDir/device_info.txt');
  infoFile.writeAsStringSync(
    'serial=${deviceInfo.serial}\n'
    'firmware=${deviceInfo.firmware}\n'
    'hardware=0x${deviceInfo.hardware.toRadixString(16).padLeft(4, '0')}\n'
    'base_address=0x${deviceInfo.baseAddress.toRadixString(16).padLeft(8, '0')}\n',
  );
  stdout.writeln('\nSaved: ${infoFile.path}');

  // Save raw manifest
  final manifestFile = File('$fixtureDir/manifest.bin');
  manifestFile.writeAsBytesSync(rawManifest);
  stdout.writeln('Saved: ${manifestFile.path} (${rawManifest.length} bytes)');

  // Save individual dive blobs, named by dive number
  var savedCount = 0;
  for (final entry in diveBlobs.entries) {
    final diveNumber = addressToDiveNumber[entry.key];
    final name = diveNumber != null ? 'dive_$diveNumber' : 'dive_addr_${entry.key.toRadixString(16)}';
    final diveFile = File('$fixtureDir/dives/$name.bin');
    diveFile.writeAsBytesSync(entry.value);
    stdout.writeln(
        'Saved: ${diveFile.path} (${entry.value.length} bytes)');
    savedCount++;
  }

  stdout.writeln(
      '\nDone: $savedCount dive fixtures extracted from ${validRecords.length} manifest entries.');
}

void _handleDownloadComplete(
  int address,
  Uint8List data,
  DeviceInfo deviceInfo,
  BytesBuilder manifestData,
  Map<int, Uint8List> diveBlobs,
) {
  if (address == 0xE0000000) {
    // Manifest page
    manifestData.add(data);
    stdout.writeln('  Manifest page: ${data.length} bytes');
  } else {
    // Dive blob — store by the relative address (matching manifest record)
    final relativeAddress = address - deviceInfo.baseAddress;
    diveBlobs[relativeAddress] = Uint8List.fromList(data);
    stdout.writeln(
        '  Dive blob at offset 0x${relativeAddress.toRadixString(16)}: ${data.length} bytes');
  }
}
