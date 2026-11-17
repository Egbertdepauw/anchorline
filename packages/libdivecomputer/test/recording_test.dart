import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:test/test.dart';

import 'support/trace_link.dart';

List<int> _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

List<int> _i32(int v) => (ByteData(4)..setInt32(0, v)).buffer.asUint8List();

const _uuid = '00002a29-0000-1000-8000-00805f9b34fb';

LibdcEnvelope _envelope(int n) => LibdcEnvelope(
  pinnedCommit: Libdc.pinnedCommit,
  vendor: 'Divesoft',
  product: 'Liberty',
  family: 0x1234,
  descriptorModel: 7,
  devinfoModel: 1,
  devinfoFirmware: 2,
  devinfoSerial: 3,
  fingerprint: Uint8List.fromList([n, 2, 3, 4]),
  data: Uint8List.fromList(List.generate(40, (i) => (i * n) & 0xff)),
);

void main() {
  test('parse reads the .combined.txt trace into W and R events in order', () {
    final lines = File(petrelTracePath).readAsLinesSync();
    final trace = rawPetrelTrace();
    expect(trace.events.where((e) => e.kind == 'W'), hasLength(3101));
    expect(trace.events.where((e) => e.kind == 'R'), hasLength(9178));
    expect(
      trace.events.map((e) => e.kind).join(),
      [
        for (final l in lines)
          if (l.isNotEmpty) l[0],
      ].join(),
    );
    expect(
      trace.events.first,
      LibdcIoEvent('W', hexBytes('01 00 ff 01 04 00 22 80 10 c0')),
    );
    expect(trace.events[1].payload, hasLength(18));
    expect(trace.events.every((e) => e.micros == null), isTrue);
    expect(trace.header, isEmpty);
    expect(trace.log, isEmpty);
    expect(trace.envelopes, isEmpty);
    // Every line reads back as itself.
    expect(trace.events.map((e) => e.toLine()), [
      for (final l in lines)
        if (l.isNotEmpty) l,
    ]);
  });

  test(
    'toText then parse gives the same events, header, log and envelopes',
    () {
      final events = [
        LibdcIoEvent('T', _i32(3000), micros: 1),
        LibdcIoEvent('T', _i32(-1), micros: 2),
        LibdcIoEvent('X', ascii.encode('configure 115200 8N1'), micros: 3),
        LibdcIoEvent('S', _u32(300), micros: 12345678),
        LibdcIoEvent('P', _u32(40), micros: 13000000),
        LibdcIoEvent('W', [0x01, 0x00, 0xff], micros: 13000001),
        LibdcIoEvent('R', [0xc0], micros: 13000002),
        LibdcIoEvent('W', const [], micros: 13000003),
        LibdcIoEvent('C', [
          1,
          36,
          ...ascii.encode(_uuid),
          9,
          8,
        ], micros: 13100000),
        LibdcIoEvent('C', [2, 36, ...ascii.encode(_uuid)], micros: 13100001),
        LibdcIoEvent('I', _u32(0x40047801), micros: 13200000),
        LibdcIoEvent('X', ascii.encode('overflow'), micros: 13200001),
        // A read that timed out: nothing read, then its status.
        LibdcIoEvent('R', const [], micros: 13300000),
        LibdcIoEvent('E', _i32(-7), micros: 13300001),
        // Not a kind the C layer writes today: kept as raw bytes.
        LibdcIoEvent('Q', [5, 6], micros: 13200002),
      ];
      final recording = LibdcRecording(
        header: [
          'descriptor Divesoft|Liberty|4660|7',
          'advertised Liberty 1234',
          'libdivecomputer ${Libdc.pinnedCommit}',
        ],
        events: events,
        log: [
          'ERROR: Failed to send the packet. [in hdlc.c:120 (hdlc_write)]',
          '',
          'INFO: Read: size=2, data=0102',
        ],
        envelopes: [_envelope(1), _envelope(2)],
      );
      final text = recording.toText();
      final lines = text.split('\n');
      expect(lines.first, '# Anchorline download recording 1');
      expect(
        lines,
        containsAllInOrder([
          '# descriptor Divesoft|Liberty|4660|7',
          '# advertised Liberty 1234',
          '[0.000001] T 3000',
          '[0.000002] T -1',
          '[0.000003] X configure 115200 8N1',
          '[12.345678] S 300',
          '[13.000000] P input 40 bytes dropped',
          '[13.000001] W (3 bytes): 01 00 ff',
          '[13.000002] R (1 bytes): c0',
          '[13.000003] W (0 bytes):',
          '[13.100000] C read $_uuid (2 bytes): 09 08',
          '[13.100001] C write $_uuid (0 bytes):',
          '[13.200000] I 40047801 unsupported',
          '[13.300000] R (0 bytes):',
          '[13.300001] E -7',
          '# log',
          '# end',
        ]),
      );
      expect(lines.where((l) => l.startsWith('# envelope ')), hasLength(2));

      final back = LibdcRecording.parse(text);
      expect(back.header, recording.header);
      expect(back.events, recording.events);
      expect(back.log, recording.log);
      expect(
        back.envelopes.map((e) => e.encode()),
        recording.envelopes.map((e) => e.encode()),
      );
      expect(back.advertisedName, 'Liberty 1234');
      expect(back.toText(), text);

      // The packed form is the C layer's layout and reads back the same.
      expect(LibdcIoEvent.unpackAll(recording.toReplayEvents()), events);
    },
  );

  test(
    'parse refuses a line whose byte count is wrong, and a newer version',
    () {
      expect(
        () => LibdcRecording.parse('W (3 bytes): 01 02\n'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LibdcRecording.parse('Z what\n'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () =>
            LibdcRecording.parse('# Anchorline download recording 2\n# end\n'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LibdcIoEvent.unpackAll(Uint8List.fromList([0x57, 0, 0, 0])),
        throwsA(isA<FormatException>()),
      );
      // A kind byte that is not ASCII is a FormatException too, not an
      // ArgumentError.
      expect(
        () => LibdcIoEvent.unpackAll(
          Uint8List.fromList([0xd7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('a log entry with line breaks or a leading # cannot break the '
      'text', () {
    final recording = LibdcRecording(
      header: ['advertised two\nlines'],
      log: [
        'ANCHORLINE: the download isolate stopped: Bad state\n# end\nmore',
        '# envelope AAAA',
        '# end',
        'plain',
      ],
      envelopes: [_envelope(1)],
    );
    final text = recording.toText();
    final back = LibdcRecording.parse(text);
    expect(back.header, ['advertised two lines']);
    expect(back.log, [
      'ANCHORLINE: the download isolate stopped: Bad state # end more',
      ' # envelope AAAA',
      ' # end',
      'plain',
    ]);
    expect(back.envelopes.map((e) => e.encode()), [_envelope(1).encode()]);
    expect(text.split('\n').where((l) => l == '# end'), hasLength(1));
  });
}
