/// Stored form of a dive's events: one zlib-compressed blob per dive.
///
/// Layout before compression, big-endian:
///   uint8  formatVersion
///   uint16 count
///   per event, 16 bytes:
///     uint32 timeMs
///     uint8  type.wire
///     uint8  flags (bit 0 value present, bit 1 bearing present)
///     uint16 rawType
///     int32  value   (0 when absent)
///     int32  bearing (0 when absent)
///
/// Decoding never throws: an unknown format version or a damaged blob reads
/// as "no events", and an unknown type code reads as [DiveEventType.other].
library;

import 'dart:typed_data';

import '../models/dive_event.dart';
import 'column_packer.dart';

class EventCodec {
  static const int formatVersion = 1;

  static const int _headerBytes = 3;
  static const int _eventBytes = 16;
  static const int _flagValue = 1;
  static const int _flagBearing = 2;

  /// Encodes [events]; null when there are none.
  static Uint8List? encode(List<DiveEvent> events) {
    if (events.isEmpty) return null;
    final raw = Uint8List(_headerBytes + events.length * _eventBytes);
    final view = ByteData.sublistView(raw);
    raw[0] = formatVersion;
    view.setUint16(1, events.length, Endian.big);
    var o = _headerBytes;
    for (final e in events) {
      view.setUint32(o, e.timeMs, Endian.big);
      raw[o + 4] = e.type.wire;
      raw[o + 5] = (e.value != null ? _flagValue : 0) |
          (e.bearing != null ? _flagBearing : 0);
      view.setUint16(o + 6, e.rawType, Endian.big);
      view.setInt32(o + 8, e.value ?? 0, Endian.big);
      view.setInt32(o + 12, e.bearing ?? 0, Endian.big);
      o += _eventBytes;
    }
    return ColumnPacker.packBytes(raw);
  }

  /// Decodes a blob written by [encode]; empty for null or unreadable input.
  static List<DiveEvent> decode(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return const [];
    try {
      final raw = ColumnPacker.unpackBytes(blob);
      if (raw.length < _headerBytes || raw[0] != formatVersion) {
        return const [];
      }
      final view = ByteData.sublistView(raw);
      final count = view.getUint16(1, Endian.big);
      if (raw.length < _headerBytes + count * _eventBytes) return const [];
      final out = <DiveEvent>[];
      var o = _headerBytes;
      for (var i = 0; i < count; i++) {
        final flags = raw[o + 5];
        out.add(DiveEvent(
          timeMs: view.getUint32(o, Endian.big),
          type: DiveEventType.fromWire(raw[o + 4]),
          rawType: view.getUint16(o + 6, Endian.big),
          value: flags & _flagValue != 0
              ? view.getInt32(o + 8, Endian.big)
              : null,
          bearing: flags & _flagBearing != 0
              ? view.getInt32(o + 12, Endian.big)
              : null,
        ));
        o += _eventBytes;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
