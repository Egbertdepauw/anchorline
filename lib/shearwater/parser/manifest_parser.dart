/// Parser for the Shearwater dive manifest.
///
/// The manifest is downloaded from address 0xE0000000 and contains
/// 32-byte records, each describing one dive stored on the device.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';

/// A single entry in the dive manifest.
class ManifestEntry {
  /// 0xA5C4 = valid, 0x5A23 = deleted.
  final int header;

  /// Dive number on the device.
  final int diveNumber;

  /// 4-byte fingerprint for incremental sync (at offset 4).
  /// In practice this is the dive start timestamp.
  final Uint8List fingerprint;

  /// Start timestamp (Unix seconds UTC). Read from offset 4 (fingerprint).
  final int startTimestamp;

  /// End timestamp (Unix seconds UTC, at offset 8).
  final int endTimestamp;

  /// Address of the dive data in flash memory (relative to base address,
  /// at offset 20).
  final int address;

  /// An end address at offset 24, relative to the same base as [address].
  /// Its exact meaning is unknown.
  ///
  /// It is NOT the size of the dive's compressed data. For dive #718 in
  /// the recorded Petrel 3 trace (`test/fixtures/raw/`) it lies 78,176
  /// bytes past [address], while the Petrel sent 54,576 compressed bytes.
  /// Downloads don't need it: each dive is requested with size 0xFFFFFF,
  /// like libdivecomputer does, and the Petrel ends every dive's stream
  /// with its own LRE end marker. Asking for this range instead made the
  /// download run past the end of the dive (the NAK 0x24 path in
  /// `ShearwaterProtocol.download()`). See
  /// `docs/upstream/libdivecomputer-findings.md`, item 5.
  final int endAddress;

  /// [endAddress] - [address]. Despite the name this is not the dive's
  /// compressed size (see [endAddress]); it is only used as a rough total
  /// for download progress.
  int get compressedSize => endAddress - address;

  bool get isValid => header == manifestHeaderValid;
  bool get isDeleted => header == manifestHeaderDeleted;

  ManifestEntry({
    required this.header,
    required this.diveNumber,
    required this.fingerprint,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.address,
    required this.endAddress,
  });
}

/// Parses Shearwater dive manifest data.
class ManifestParser {
  /// Parse manifest [data] into a list of [ManifestEntry].
  ///
  /// Stops at the first record that is neither valid (0xA5C4)
  /// nor deleted (0x5A23).
  static List<ManifestEntry> parse(Uint8List data) {
    final entries = <ManifestEntry>[];
    var offset = 0;

    while (offset + manifestRecordSize <= data.length) {
      final header = uint16BE(data, offset);
      if (header != manifestHeaderValid && header != manifestHeaderDeleted) {
        break;
      }

      entries.add(ManifestEntry(
        header: header,
        diveNumber: uint16BE(data, offset + 2),
        fingerprint: data.sublist(offset + 4, offset + 8),
        startTimestamp: uint32BE(data, offset + 4), // fingerprint = start time
        endTimestamp: uint32BE(data, offset + 8),
        address: uint32BE(data, offset + 20),
        endAddress: uint32BE(data, offset + 24),
      ));

      offset += manifestRecordSize;
    }

    return entries;
  }
}
