import 'dart:convert';
import 'dart:typed_data';

/// What Anchorline stores as the raw blob of a libdivecomputer dive: the
/// dive's bytes plus everything needed to parse them again the same way
/// (spec section 7).
///
/// Layout, big-endian: `'ALDC'`, `u8 1` (version), then `pinnedCommit`,
/// `vendor` and `product` (each `u8 length` + UTF-8), `u32 family`,
/// `u32 descriptorModel`, `u8 flags` (bit 0: device info present, bit 1:
/// clock present), `u32 devinfoModel`, `u32 devinfoFirmware`,
/// `u32 devinfoSerial`, `u32 devtime`, `i64 systime`, `u16 length` + the
/// fingerprint and `u32 length` + the data. Absent values are written as 0
/// with their flag clear.
///
/// The three device-info values travel together (one flag), and so do the
/// two clock values. A group with at least one value set is written as
/// present and reads back with all of its values non-null.
class LibdcEnvelope {
  LibdcEnvelope({
    required this.pinnedCommit,
    required this.vendor,
    required this.product,
    required this.family,
    required this.descriptorModel,
    this.devinfoModel,
    this.devinfoFirmware,
    this.devinfoSerial,
    this.devtime,
    this.systime,
    required this.fingerprint,
    required this.data,
  });

  /// The upstream commit the dive was downloaded with.
  final String pinnedCommit;
  final String vendor;
  final String product;

  /// A `dc_family_t` value.
  final int family;
  final int descriptorModel;

  /// From the `DC_EVENT_DEVINFO` event, when the computer sent one.
  final int? devinfoModel;
  final int? devinfoFirmware;
  final int? devinfoSerial;

  /// From the `DC_EVENT_CLOCK` event: the computer's tick counter and the
  /// phone's Unix time when it was read.
  final int? devtime;
  final int? systime;

  final Uint8List fingerprint;
  final Uint8List data;

  static const _magic = [0x41, 0x4c, 0x44, 0x43]; // 'ALDC'
  static const _version = 1;

  bool get _hasDevinfo =>
      devinfoModel != null || devinfoFirmware != null || devinfoSerial != null;
  bool get _hasClock => devtime != null || systime != null;

  Uint8List encode() {
    final out = BytesBuilder(copy: false);
    void u8(int v) => out.addByte(v);
    void u16(int v) =>
        out.add((ByteData(2)..setUint16(0, v)).buffer.asUint8List());
    void u32(int v) =>
        out.add((ByteData(4)..setUint32(0, v)).buffer.asUint8List());
    void i64(int v) =>
        out.add((ByteData(8)..setInt64(0, v)).buffer.asUint8List());
    void str(String s) {
      final bytes = utf8.encode(s);
      if (bytes.length > 255) {
        throw ArgumentError.value(s, 'string', 'longer than 255 bytes');
      }
      u8(bytes.length);
      out.add(bytes);
    }

    out.add(_magic);
    u8(_version);
    str(pinnedCommit);
    str(vendor);
    str(product);
    u32(family);
    u32(descriptorModel);
    u8((_hasDevinfo ? 1 : 0) | (_hasClock ? 2 : 0));
    u32(devinfoModel ?? 0);
    u32(devinfoFirmware ?? 0);
    u32(devinfoSerial ?? 0);
    u32(devtime ?? 0);
    i64(systime ?? 0);
    if (fingerprint.length > 0xffff) {
      throw ArgumentError.value(fingerprint.length, 'fingerprint', 'too long');
    }
    u16(fingerprint.length);
    out.add(fingerprint);
    u32(data.length);
    out.add(data);
    return out.toBytes();
  }

  /// Throws [FormatException] on a bad magic, version 0, a newer version or
  /// truncated input. Bytes after the data are accepted and ignored.
  static LibdcEnvelope decode(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    var pos = 0;
    void need(int n) {
      if (n < 0 || pos + n > bytes.length) {
        throw const FormatException('Truncated libdivecomputer envelope');
      }
    }

    int u8() {
      need(1);
      return bytes[pos++];
    }

    int u16() {
      need(2);
      final v = view.getUint16(pos);
      pos += 2;
      return v;
    }

    int u32() {
      need(4);
      final v = view.getUint32(pos);
      pos += 4;
      return v;
    }

    int i64() {
      need(8);
      final v = view.getInt64(pos);
      pos += 8;
      return v;
    }

    Uint8List blob(int n) {
      need(n);
      final v = Uint8List.fromList(bytes.sublist(pos, pos + n));
      pos += n;
      return v;
    }

    String str() => utf8.decode(blob(u8()));

    need(_magic.length);
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('Not a libdivecomputer envelope');
      }
    }
    pos = _magic.length;
    final version = u8();
    if (version < 1 || version > _version) {
      throw FormatException('Unsupported envelope version $version');
    }
    final pinnedCommit = str();
    final vendor = str();
    final product = str();
    final family = u32();
    final descriptorModel = u32();
    final flags = u8();
    final model = u32();
    final firmware = u32();
    final serial = u32();
    final devtime = u32();
    final systime = i64();
    final fingerprint = blob(u16());
    final data = blob(u32());
    final devinfo = flags & 1 != 0;
    final clock = flags & 2 != 0;
    return LibdcEnvelope(
      pinnedCommit: pinnedCommit,
      vendor: vendor,
      product: product,
      family: family,
      descriptorModel: descriptorModel,
      devinfoModel: devinfo ? model : null,
      devinfoFirmware: devinfo ? firmware : null,
      devinfoSerial: devinfo ? serial : null,
      devtime: clock ? devtime : null,
      systime: clock ? systime : null,
      fingerprint: fingerprint,
      data: data,
    );
  }
}
