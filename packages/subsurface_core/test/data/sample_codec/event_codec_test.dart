import 'dart:typed_data';

import 'package:subsurface_core/data/models/dive_event.dart';
import 'package:subsurface_core/data/sample_codec/column_packer.dart';
import 'package:subsurface_core/data/sample_codec/event_codec.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips every field, value and bearing optional', () {
    final events = [
      DiveEvent(
        timeMs: 125000,
        type: DiveEventType.bookmark,
        value: 7,
        bearing: 270,
      ),
      DiveEvent(
        timeMs: 600000,
        type: DiveEventType.setpointChange,
        rawType: 0x0D,
      ),
    ];
    final decoded = EventCodec.decode(EventCodec.encode(events));
    expect(decoded, hasLength(2));
    for (var i = 0; i < events.length; i++) {
      expect(decoded[i].timeMs, events[i].timeMs);
      expect(decoded[i].type, events[i].type);
      expect(decoded[i].rawType, events[i].rawType);
      expect(decoded[i].value, events[i].value);
      expect(decoded[i].bearing, events[i].bearing);
    }
  });

  test('no events encodes to null and null decodes to empty', () {
    expect(EventCodec.encode(const []), isNull);
    expect(EventCodec.decode(null), isEmpty);
  });

  test('an unknown type code decodes as other and keeps rawType', () {
    final raw = Uint8List(3 + 16);
    final view = ByteData.sublistView(raw);
    raw[0] = 1;
    view.setUint16(1, 1, Endian.big);
    view.setUint32(3, 1000, Endian.big);
    raw[7] = 42;
    raw[8] = 0;
    view.setUint16(9, 0x1234, Endian.big);
    final events = EventCodec.decode(ColumnPacker.packBytes(raw));
    expect(events, hasLength(1));
    expect(events.single.type, DiveEventType.other);
    expect(events.single.rawType, 0x1234);
    expect(events.single.timeMs, 1000);
  });

  test('a newer format version decodes as no events, without throwing', () {
    final raw = Uint8List(3 + 16);
    raw[0] = 2;
    ByteData.sublistView(raw).setUint16(1, 1, Endian.big);
    expect(EventCodec.decode(ColumnPacker.packBytes(raw)), isEmpty);
  });

  test('a truncated blob decodes as no events, without throwing', () {
    final raw = Uint8List(3 + 8);
    raw[0] = 1;
    ByteData.sublistView(raw).setUint16(1, 1, Endian.big);
    expect(EventCodec.decode(ColumnPacker.packBytes(raw)), isEmpty);
    // Not even valid zlib.
    expect(EventCodec.decode(Uint8List.fromList([1, 2, 3])), isEmpty);
  });
}
