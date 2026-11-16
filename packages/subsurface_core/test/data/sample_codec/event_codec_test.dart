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

  test('v1 golden bytes: wire codes, offsets and int32 sign handling', () {
    final blob = EventCodec.encode([
      DiveEvent(
        timeMs: 0x00012345,
        type: DiveEventType.bookmark,
        rawType: 0x0026,
        value: -2,
        bearing: 270,
      ),
      DiveEvent(
        timeMs: 0xFFFFFFFF,
        type: DiveEventType.ascentWarning,
        rawType: 0xFFFF,
        value: -0x80000000,
      ),
    ])!;
    final raw = ColumnPacker.unpackBytes(blob);
    expect(raw, [
      // version, count
      0x01, 0x00, 0x02,
      // event 1: timeMs, wire (bookmark), flags (value+bearing), rawType,
      // value -2, bearing 270
      0x00, 0x01, 0x23, 0x45, 0x01, 0x03, 0x00, 0x26,
      0xFF, 0xFF, 0xFF, 0xFE, 0x00, 0x00, 0x01, 0x0E,
      // event 2: timeMs, wire (ascentWarning), flags (value only), rawType,
      // value int32 min, bearing absent
      0xFF, 0xFF, 0xFF, 0xFF, 0x06, 0x01, 0xFF, 0xFF,
      0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]);
    final back = EventCodec.decode(blob);
    expect(back[0].value, -2);
    expect(back[1].value, -0x80000000);
    expect(back[1].bearing, isNull);
  });

  group('encode rejects values the format cannot hold', () {
    DiveEvent event({
      int timeMs = 0,
      int rawType = 0,
      int? value,
      int? bearing,
    }) =>
        DiveEvent(
          timeMs: timeMs,
          type: DiveEventType.other,
          rawType: rawType,
          value: value,
          bearing: bearing,
        );

    void rejects(String name, DiveEvent e) => test(name, () {
          expect(() => EventCodec.encode([e]), throwsArgumentError);
        });

    rejects('negative timeMs', event(timeMs: -1));
    rejects('timeMs above uint32', event(timeMs: 0x100000000));
    rejects('negative rawType', event(rawType: -1));
    rejects('rawType above uint16', event(rawType: 0x10000));
    rejects('value above int32', event(value: 0x80000000));
    rejects('value below int32', event(value: -0x80000001));
    rejects('bearing above int32', event(bearing: 0x80000000));
    rejects('bearing below int32', event(bearing: -0x80000001));

    test('more than 0xFFFF events', () {
      final many = List.generate(0x10000, (_) => event());
      expect(() => EventCodec.encode(many), throwsArgumentError);
    });

    test('the extremes of every range are accepted', () {
      final blob = EventCodec.encode([
        event(
            timeMs: 0xFFFFFFFF,
            rawType: 0xFFFF,
            value: -0x80000000,
            bearing: 0x7FFFFFFF),
      ]);
      expect(EventCodec.decode(blob).single.bearing, 0x7FFFFFFF);
      expect(EventCodec.encode(List.generate(0xFFFF, (_) => event())),
          isNotNull);
    });
  });
}
