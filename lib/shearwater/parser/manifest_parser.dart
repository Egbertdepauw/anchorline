/// Parser for the Shearwater dive manifest.
///
/// The manifest is downloaded from address 0xE0000000 and contains
/// 32-byte records, each describing one dive stored on the device.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:subsurface_core/shearwater/parser/parsed_dive.dart';

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

  /// End address of the dive data in flash memory (exclusive, relative to
  /// the same base, at offset 24). [endAddress] - [address] is the exact
  /// number of compressed bytes the Petrel will return when we download
  /// this dive. Without this, we'd request a generic upper bound (16 MB)
  /// and the Petrel happily streams the next-younger dive's data right
  /// after this one — the LRE end-marker convention only fires at the
  /// very end of the on-flash log, not between dives.
  final int endAddress;

  /// Compressed dive size in bytes, derived from [endAddress] - [address].
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

  /// Throws [ManifestMismatchException] unless [blobHeader], parsed from the
  /// blob downloaded for this entry, is the dive this entry describes: the
  /// same start time and, when the header carries one, the same dive number.
  ///
  /// libdivecomputer relies on the same identity. Its fingerprint is this
  /// entry's bytes 4-7 when it reads the manifest, and the blob's bytes 12-15
  /// (the opening start time) when it hands a dive over (shearwater_petrel.c),
  /// so the two must be equal for incremental downloads to stop where they
  /// should.
  void checkBlobHeader(DiveHeader blobHeader) {
    final number = blobHeader.diveNumber;
    if (blobHeader.startTimestamp != startTimestamp ||
        (number != null && number != diveNumber)) {
      throw ManifestMismatchException(
        entry: this,
        blobDiveNumber: number,
        blobStartTimestamp: blobHeader.startTimestamp,
      );
    }
  }
}

/// A downloaded blob that is not the dive its manifest entry describes, as
/// happens when the manifest went stale between reading it and downloading
/// (a dive overwritten or removed in between).
class ManifestMismatchException implements Exception {
  final ManifestEntry entry;

  /// The blob's own dive number, null when its header carries none.
  final int? blobDiveNumber;
  final int blobStartTimestamp;

  const ManifestMismatchException({
    required this.entry,
    required this.blobDiveNumber,
    required this.blobStartTimestamp,
  });

  @override
  String toString() => 'ManifestMismatchException: the manifest lists dive '
      '#${entry.diveNumber} starting at ${entry.startTimestamp}, but the '
      'downloaded blob is dive #${blobDiveNumber ?? '?'} starting at '
      '$blobStartTimestamp';
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
