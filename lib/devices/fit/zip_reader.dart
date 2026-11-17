import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown for a zip archive this reader cannot or will not read: corrupt
/// structure, an unsupported method, encryption, a size or CRC mismatch.
class ZipFormatException implements Exception {
  ZipFormatException(this.message);
  final String message;

  @override
  String toString() => 'ZipFormatException: $message';
}

/// One central-directory record.
class ZipEntryInfo {
  ZipEntryInfo({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.size,
    required this.localHeaderOffset,
    this.crc32 = 0,
    this.flags = 0,
  });

  final String name;
  final int method;
  final int compressedSize;
  final int size;

  /// Relative to the start of the archive (the reader's `base`).
  final int localHeaderOffset;
  final int crc32;
  final int flags;

  bool get isStored => method == 0;
  bool get isDirectory => name.endsWith('/');
  bool get isEncrypted => (flags & 1) != 0;
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crcUpdate(int crc, List<int> data) {
  var c = crc;
  for (var i = 0; i < data.length; i++) {
    c = _crcTable[(c ^ data[i]) & 0xFF] ^ (c >> 8);
  }
  return c;
}

/// A small streaming zip reader on `dart:io`. It reads the central directory
/// into memory and entry data in chunks of at most 1 MB; it never holds a
/// whole archive. Methods 0 (stored) and 8 (deflate) are supported, plus
/// Zip64 and data descriptors (sizes always come from the central directory).
///
/// The reader moves the file's position, so don't use one [ZipReader] (or
/// the same [RandomAccessFile]) from concurrent calls.
class ZipReader {
  ZipReader._(this._file, this._base, this._length, this.entries,
      this._dataStart);

  static const int _chunk = 1 << 20;
  static const int _maxCentralDirectory = 256 << 20;

  final RandomAccessFile _file;
  final int _base;
  final int _length;

  /// Entries in central-directory order.
  final List<ZipEntryInfo> entries;
  final Map<ZipEntryInfo, int> _dataStart;

  /// Opens the archive found at [base] in [file], [length] bytes long
  /// (default: to the end of the file). A stored inner zip is opened in
  /// place by passing its [storedSpan].
  static Future<ZipReader> open(RandomAccessFile file,
      {int base = 0, int? length}) async {
    final total = length ?? (await file.length()) - base;
    if (base < 0 || total < 22) {
      throw ZipFormatException('Not a zip archive (too short)');
    }

    // End of central directory: scan the tail (22 bytes plus a comment of
    // up to 64 KB).
    final tailLen = total < 22 + 65535 ? total : 22 + 65535;
    final tail = await _readAt(file, base + total - tailLen, tailLen);
    var eocd = -1;
    for (var i = tailLen - 22; i >= 0; i--) {
      if (_u32(tail, i) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw ZipFormatException('No end of central directory');
    var count = _u16(tail, eocd + 10);
    var cdSize = _u32(tail, eocd + 12);
    var cdOffset = _u32(tail, eocd + 16);

    if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      // Zip64: the locator sits right before the EOCD record.
      final locAt = eocd - 20;
      if (locAt < 0 || _u32(tail, locAt) != 0x07064b50) {
        throw ZipFormatException('Missing Zip64 locator');
      }
      final z64 = _u64(tail, locAt + 8);
      if (z64 < 0 || z64 + 56 > total) {
        throw ZipFormatException('Bad Zip64 record offset');
      }
      final rec = await _readAt(file, base + z64, 56);
      if (_u32(rec, 0) != 0x06064b50) {
        throw ZipFormatException('Bad Zip64 end record');
      }
      count = _u64(rec, 32);
      cdSize = _u64(rec, 40);
      cdOffset = _u64(rec, 48);
    }
    if (count < 0 ||
        cdSize < 0 ||
        cdOffset < 0 ||
        cdSize > _maxCentralDirectory ||
        cdOffset + cdSize > total) {
      throw ZipFormatException('Corrupt central directory bounds');
    }

    final cd = await _readAt(file, base + cdOffset, cdSize);
    final entries = <ZipEntryInfo>[];
    var p = 0;
    for (var n = 0; n < count; n++) {
      if (p + 46 > cd.length || _u32(cd, p) != 0x02014b50) {
        throw ZipFormatException('Corrupt central directory record');
      }
      final flags = _u16(cd, p + 8);
      final method = _u16(cd, p + 10);
      final crc = _u32(cd, p + 16);
      var csize = _u32(cd, p + 20);
      var size = _u32(cd, p + 24);
      final nameLen = _u16(cd, p + 28);
      final extraLen = _u16(cd, p + 30);
      final commentLen = _u16(cd, p + 32);
      var offset = _u32(cd, p + 42);
      final end = p + 46 + nameLen + extraLen + commentLen;
      if (end > cd.length) {
        throw ZipFormatException('Corrupt central directory record');
      }
      final name = utf8.decode(cd.sublist(p + 46, p + 46 + nameLen),
          allowMalformed: true);

      // Zip64 extra field: only the values whose 32-bit field is saturated,
      // in the order size, compressed size, offset.
      var x = p + 46 + nameLen;
      final xEnd = x + extraLen;
      while (x + 4 <= xEnd) {
        final id = _u16(cd, x);
        final len = _u16(cd, x + 2);
        if (x + 4 + len > xEnd) break;
        if (id == 1) {
          var q = x + 4;
          final qEnd = q + len;
          int next() {
            if (q + 8 > qEnd) {
              throw ZipFormatException('Truncated Zip64 extra field');
            }
            final v = _u64(cd, q);
            q += 8;
            return v;
          }

          if (size == 0xFFFFFFFF) size = next();
          if (csize == 0xFFFFFFFF) csize = next();
          if (offset == 0xFFFFFFFF) offset = next();
        }
        x += 4 + len;
      }
      if (size < 0 || csize < 0 || offset < 0 || offset + 30 > total) {
        throw ZipFormatException('Corrupt entry "$name"');
      }
      entries.add(ZipEntryInfo(
        name: name,
        method: method,
        compressedSize: csize,
        size: size,
        localHeaderOffset: offset,
        crc32: crc,
        flags: flags,
      ));
      p = end;
    }

    final reader = ZipReader._(file, base, total, entries, {});
    // Stored entries get their data offset now so [storedSpan] can stay
    // synchronous; deflated ones are resolved when first read.
    for (final e in entries) {
      if (e.isStored && !e.isDirectory) {
        try {
          await reader._resolve(e);
        } on ZipFormatException {
          // Leave it unresolved: storedSpan, read and extractTo throw for
          // this one entry, the rest of the archive stays readable.
        }
      }
    }
    return reader;
  }

  /// Where inside the underlying file a stored entry's bytes live, so an
  /// inner zip can be opened in place with [ZipReader.open].
  ({int base, int length}) storedSpan(ZipEntryInfo e) {
    final start = _dataStart[e];
    if (!e.isStored) {
      throw ZipFormatException('Entry "${e.name}" is not stored');
    }
    if (start == null) {
      throw ZipFormatException('Entry "${e.name}" has a bad local header');
    }
    return (base: _base + start, length: e.compressedSize);
  }

  /// Inflates the whole entry into memory. Throws [ZipFormatException] when
  /// it is larger than [maxSize], encrypted, not stored/deflated, or its
  /// size or CRC-32 do not match the central directory.
  Future<Uint8List> read(ZipEntryInfo e, {int maxSize = 64 << 20}) async {
    _checkReadable(e);
    if (e.size > maxSize) {
      throw ZipFormatException(
          'Entry "${e.name}" is ${e.size} bytes, above the limit of $maxSize');
    }
    final out = Uint8List(e.size);
    var written = 0;
    var crc = 0xFFFFFFFF;
    await _pump(e, (chunk) {
      if (written + chunk.length > e.size) {
        throw ZipFormatException('Entry "${e.name}" is larger than declared');
      }
      out.setRange(written, written + chunk.length, chunk);
      written += chunk.length;
      crc = _crcUpdate(crc, chunk);
    });
    _verify(e, written, crc);
    return out;
  }

  /// Streams the entry into [target] in chunks of at most 1 MB. A failed
  /// extraction deletes the partial file.
  Future<void> extractTo(ZipEntryInfo e, File target) async {
    _checkReadable(e);
    final sink = await target.open(mode: FileMode.write);
    var written = 0;
    var crc = 0xFFFFFFFF;
    try {
      await _pump(e, (chunk) {
        written += chunk.length;
        if (written > e.size) {
          throw ZipFormatException(
              'Entry "${e.name}" is larger than declared');
        }
        crc = _crcUpdate(crc, chunk);
        // Synchronous so chunks stay ordered inside the converter sink.
        sink.writeFromSync(chunk);
      });
      _verify(e, written, crc);
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  void _checkReadable(ZipEntryInfo e) {
    if (e.isEncrypted) {
      throw ZipFormatException('Entry "${e.name}" is encrypted');
    }
    if (e.method != 0 && e.method != 8) {
      throw ZipFormatException(
          'Entry "${e.name}" uses unsupported method ${e.method}');
    }
    if (e.isStored && e.compressedSize != e.size) {
      throw ZipFormatException('Entry "${e.name}" has inconsistent sizes');
    }
  }

  void _verify(ZipEntryInfo e, int written, int crc) {
    if (written != e.size) {
      throw ZipFormatException(
          'Entry "${e.name}" is $written bytes, expected ${e.size}');
    }
    if (((crc ^ 0xFFFFFFFF) & 0xFFFFFFFF) != e.crc32) {
      throw ZipFormatException('Entry "${e.name}" fails its CRC-32 check');
    }
  }

  Future<int> _resolve(ZipEntryInfo e) async {
    final cached = _dataStart[e];
    if (cached != null) return cached;
    final h = await _readAt(_file, _base + e.localHeaderOffset, 30);
    if (_u32(h, 0) != 0x04034b50) {
      throw ZipFormatException('Bad local header for "${e.name}"');
    }
    final start = e.localHeaderOffset + 30 + _u16(h, 26) + _u16(h, 28);
    if (start + e.compressedSize > _length) {
      throw ZipFormatException('Entry "${e.name}" runs past the archive');
    }
    return _dataStart[e] = start;
  }

  /// Feeds the entry's decompressed bytes to [onChunk], reading at most
  /// 1 MB of the archive at a time.
  Future<void> _pump(ZipEntryInfo e, void Function(Uint8List) onChunk) async {
    final start = await _resolve(e);
    ByteConversionSink? inflater;
    if (!e.isStored) {
      inflater = ZLibDecoder(raw: true).startChunkedConversion(
          _CallbackSink((c) => onChunk(Uint8List.fromList(c))));
    }
    try {
      var done = 0;
      while (done < e.compressedSize) {
        final n = e.compressedSize - done < _chunk
            ? e.compressedSize - done
            : _chunk;
        final data = await _readAt(_file, _base + start + done, n);
        done += n;
        if (inflater == null) {
          onChunk(data);
        } else {
          inflater.add(data);
        }
      }
      inflater?.close();
    } on ZipFormatException {
      rethrow;
    } on FormatException catch (err) {
      throw ZipFormatException('Entry "${e.name}" is corrupt: ${err.message}');
    } on ArgumentError catch (err) {
      throw ZipFormatException('Entry "${e.name}" is corrupt: $err');
    }
  }

  static Future<Uint8List> _readAt(
      RandomAccessFile f, int position, int count) async {
    await f.setPosition(position);
    final data = await f.read(count);
    if (data.length != count) {
      throw ZipFormatException('Unexpected end of file');
    }
    return data;
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  static int _u64(Uint8List b, int o) => _u32(b, o) + (_u32(b, o + 4) << 32);
}

class _CallbackSink extends ByteConversionSinkBase {
  _CallbackSink(this._on);
  final void Function(List<int>) _on;

  @override
  void add(List<int> chunk) => _on(chunk);

  @override
  void close() {}
}
