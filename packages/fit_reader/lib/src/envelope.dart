import 'dart:convert';
import 'dart:typed_data';

/// Where a stored FIT file came from.
enum FitSource {
  file(0),
  connectExport(1),
  accountExport(2),
  folder(3);

  final int wire;
  const FitSource(this.wire);
}

/// A FIT file with the little we keep beside it, as stored in the raw blob
/// column. Layout, big-endian: `'ALFT'`, u8 version (1), u8 source,
/// u16 file-name length + UTF-8 name, u32 FIT length + FIT bytes.
class FitEnvelope {
  final FitSource source;
  final String fileName;
  final Uint8List fit;

  const FitEnvelope({
    required this.source,
    required this.fileName,
    required this.fit,
  });

  static const _magic = [0x41, 0x4C, 0x46, 0x54]; // ALFT
  static const _version = 1;

  Uint8List encode() {
    final name = utf8.encode(fileName);
    if (name.length > 0xFFFF) {
      throw ArgumentError('file name too long');
    }
    final out = Uint8List(4 + 1 + 1 + 2 + name.length + 4 + fit.length);
    final d = ByteData.sublistView(out);
    out.setRange(0, 4, _magic);
    d.setUint8(4, _version);
    d.setUint8(5, source.wire);
    d.setUint16(6, name.length);
    out.setRange(8, 8 + name.length, name);
    var p = 8 + name.length;
    d.setUint32(p, fit.length);
    p += 4;
    out.setRange(p, p + fit.length, fit);
    return out;
  }

  /// Throws [FormatException] on a bad magic, a newer version or truncation.
  static FitEnvelope decode(Uint8List bytes) {
    if (bytes.length < 8) throw const FormatException('FIT envelope too short');
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('not a FIT envelope');
      }
    }
    final d = ByteData.sublistView(bytes);
    final version = d.getUint8(4);
    if (version == 0 || version > _version) {
      throw FormatException('unsupported FIT envelope version $version');
    }
    final sourceWire = d.getUint8(5);
    final source = FitSource.values.firstWhere(
      (s) => s.wire == sourceWire,
      orElse: () => FitSource.file,
    );
    final nameLen = d.getUint16(6);
    var p = 8;
    if (bytes.length < p + nameLen + 4) {
      throw const FormatException('FIT envelope truncated');
    }
    final fileName = utf8.decode(
      Uint8List.sublistView(bytes, p, p + nameLen),
      allowMalformed: true,
    );
    p += nameLen;
    final fitLen = d.getUint32(p);
    p += 4;
    if (bytes.length < p + fitLen) {
      throw const FormatException('FIT envelope truncated');
    }
    return FitEnvelope(
      source: source,
      fileName: fileName,
      fit: Uint8List.fromList(Uint8List.sublistView(bytes, p, p + fitLen)),
    );
  }
}
