// The download session against the Petrel 3 trace, through libdivecomputer's
// own Shearwater driver: replay through the C layer, and the live path
// through TraceLink.
import 'dart:async';
import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:libdivecomputer/src/download/download.dart'
    show debugNativeLinkOf;
import 'package:test/test.dart';

import 'support/trace_link.dart';

/// Whether [bytes] is the start of a compressed dive download
/// (UPLOAD_INIT_REQUEST 0x35 with compression 0x10), after the BLE frame
/// header and the FF 01 len 00 packet header.
bool _isDiveInit(Uint8List bytes) =>
    bytes.length > 7 && bytes[6] == 0x35 && bytes[7] == 0x10;

/// The trace's write indexes where each dive's download starts.
List<int> _diveStarts(LibdcRecording trace) {
  final writes = trace.events.where((e) => e.kind == 'W').toList();
  return [
    for (var i = 0; i < writes.length; i++)
      if (_isDiveInit(writes[i].payload)) i,
  ];
}

List<String> _ids(List<LibdcDiveDownloaded> dives) =>
    dives.map((d) => d.diveId).toList();

void main() {
  final descriptor = petrel3();
  final trace = petrelTrace();
  late final List<LibdcDownloadEvent> full;
  late final List<LibdcDiveDownloaded> fullDives;

  setUpAll(() async {
    full = await collect(
      LibdcDownload.replay(descriptor: descriptor, recording: trace),
    );
    fullDives = divesOf(full);
  });

  test('the raw trace diverges from upstream at write 2: the trace reads the '
      'hardware id, upstream the model', () async {
    final events = await collect(
      LibdcDownload.replay(descriptor: descriptor, recording: rawPetrelTrace()),
    );
    final finished = finishedOf(events);
    expect(finished.status, LibdcStatus.protocol);
    expect(events.whereType<LibdcDeviceInfo>(), isEmpty);
    expect(divesOf(events), isEmpty);
    // Event 4 is write 2 (events 0-3 are two writes and their answers).
    expect(
      finished.recording.log,
      contains(
        startsWith(
          'ERROR: Replay: the write does not match the recording at event 4.',
        ),
      ),
    );
  });

  test('replay of the Petrel 3 trace: device info first, then 8 dives, then '
      'PROTOCOL where the trace stops inside the 9th', () {
    final kinds = full
        .where((e) => e is! LibdcProgress)
        .map((e) => e.runtimeType)
        .toList();
    expect(kinds, [
      LibdcDeviceInfo,
      for (var i = 0; i < 8; i++) LibdcDiveDownloaded,
      LibdcFinished,
    ]);
    final info = full.whereType<LibdcDeviceInfo>().single;
    expect(info.serial, petrelSerial);
    expect(info.model, 10);
    expect(info.firmware, 103);
    // The trace ends with the shutdown in the middle of the 9th dive, where
    // Subsurface stopped: upstream asks for the next block instead.
    final finished = finishedOf(full);
    expect(finished.status, LibdcStatus.protocol);
    expect(
      finished.recording.log,
      contains(
        startsWith(
          'ERROR: Replay: the write does not match the recording at event 12278.',
        ),
      ),
    );
    expect(finished.recording.envelopes, hasLength(8));
    expect(finished.recording.events, isEmpty, reason: 'not recording');
    expect(finished.recording.header, [
      'descriptor Shearwater|Petrel 3|${descriptor.family}|${descriptor.model}',
      'libdivecomputer ${Libdc.pinnedCommit}',
    ]);
  });

  test('every dive carries its envelope, its id and a converted dive', () {
    expect(fullDives, hasLength(8));
    for (final d in fullDives) {
      final e = d.envelope;
      expect(e.pinnedCommit, Libdc.pinnedCommit);
      expect(e.vendor, 'Shearwater');
      expect(e.product, 'Petrel 3');
      expect(e.family, descriptor.family);
      expect(e.descriptorModel, descriptor.model);
      expect(e.devinfoSerial, petrelSerial);
      expect(e.devinfoModel, 10);
      expect(e.devinfoFirmware, 103);
      expect(e.devtime, isNull, reason: 'a Petrel sends no clock event');
      expect(e.fingerprint, hasLength(4));
      expect(e.fingerprint, e.data.sublist(12, 16));
      expect(
        d.diveId,
        libdcDiveId(
          vendor: 'Shearwater',
          serial: petrelSerial,
          fingerprint: e.fingerprint,
        ),
      );
      expect(d.parseError, isNull);
      expect(d.converted, isNotNull);
      expect(d.converted!.dive.id, d.diveId);
      expect(d.converted!.samples.sampleCount, greaterThan(0));
      expect(LibdcEnvelope.decode(e.encode()).data, e.data);
    }
    expect(_ids(fullDives).toSet(), hasLength(8));
    expect(
      finishedOf(full).recording.envelopes.map((e) => e.encode()),
      fullDives.map((d) => d.envelope.encode()),
    );
  });

  test('progress only rises', () {
    final progress = full.whereType<LibdcProgress>().toList();
    expect(progress.length, greaterThan(20));
    for (var i = 0; i < progress.length; i++) {
      final p = progress[i];
      expect(p.current, lessThanOrEqualTo(p.maximum));
      if (i > 0) {
        final q = progress[i - 1];
        expect(
          p.current * q.maximum,
          greaterThan(q.current * p.maximum),
          reason:
              'progress $i: ${q.current}/${q.maximum} then '
              '${p.current}/${p.maximum}',
        );
      }
    }
  });

  test('a known fingerprint for the serial stops at that dive', () async {
    // Live, with a TraceLink that skips ahead: the trace reads five manifest
    // pages, and a download that stops at the third dive reads only the
    // first, so a strict replay can't serve it.
    final third = fullDives[2].envelope.fingerprint;
    final link = TraceLink(trace, skipAhead: true);
    final events = await collect(
      LibdcDownload.start(
        descriptor: descriptor,
        connection: LibdcBleConnection(link),
        knownFingerprints: {petrelSerial: third},
        record: true,
      ),
    );
    expect(_ids(divesOf(events)), _ids(fullDives).take(2));
    final finished = finishedOf(events);
    expect(finished.status, LibdcStatus.success);
    // Set at DEVINFO, before the manifest: one manifest page was read.
    expect(
      finished.recording.log,
      contains(
        'INFO: Fingerprint: size=4, data=${fingerprintHex(third).toUpperCase()}',
      ),
    );
    final manifestRequests = link.received.where(
      (w) => w.length > 7 && w[6] == 0x35 && w[7] == 0x00,
    );
    expect(manifestRequests, hasLength(1));

    // A fingerprint for another serial is not used.
    final other = await collect(
      LibdcDownload.start(
        descriptor: descriptor,
        connection: LibdcBleConnection(TraceLink(trace)),
        knownFingerprints: {petrelSerial + 1: third},
      ),
    );
    expect(_ids(divesOf(other)), _ids(fullDives));
  });

  test('cancel mid-download ends with CANCELLED after the dives already '
      'posted', () async {
    final third = _diveStarts(trace)[2];
    late final LibdcDownload download;
    final link = TraceLink(
      trace,
      onWrite: (index, _) {
        if (index == third + 5) download.cancel();
      },
    );
    download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(link),
    );
    final events = await collect(download);
    expect(_ids(divesOf(events)), _ids(fullDives).take(2));
    expect(finishedOf(events).status, LibdcStatus.cancelled);
    expect(link.hasListener, isFalse);
    expect(debugNativeLinkOf(download)!.isFreed, isTrue);
  });

  test('cancelling the subscription mid-download cancels the download and '
      'frees the link', () async {
    final third = _diveStarts(trace)[2];
    late final StreamSubscription<LibdcDownloadEvent> subscription;
    final link = TraceLink(
      trace,
      onWrite: (index, _) async {
        if (index == third + 5) await subscription.cancel();
      },
    );
    final download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(link),
    );
    final seen = <LibdcDownloadEvent>[];
    subscription = download.events.listen(seen.add);
    final native = debugNativeLinkOf(download)!;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!native.isFreed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(native.isFreed, isTrue);
    expect(native.refusedAfterFree, 0, reason: 'nothing ran after the end');
    expect(_ids(divesOf(seen)), _ids(fullDives).take(2));
    expect(seen.whereType<LibdcFinished>(), isEmpty, reason: 'nobody listens');
    // The write the cancel came in was the last; the shutdown at close was
    // cancelled before it was sent.
    expect(link.matchedWrites, third + 6);
    expect(link.received, hasLength(third + 6));
    expect(link.hasListener, isFalse);
  });

  test('the envelope, the id and the header carry the descriptor opened, '
      'not the one asked for', () async {
    final staleFamily = LibdcDescriptor(
      vendor: descriptor.vendor,
      product: descriptor.product,
      family: descriptor.family + 0x10000,
      model: descriptor.model,
      transports: descriptor.transports,
    );
    final staleName = LibdcDescriptor(
      vendor: descriptor.vendor,
      product: 'Petrel Three',
      family: descriptor.family,
      model: descriptor.model,
      transports: descriptor.transports,
    );
    for (final asked in [staleFamily, staleName]) {
      final events = await collect(
        LibdcDownload.replay(descriptor: asked, recording: trace),
      );
      final finished = finishedOf(events);
      expect(finished.descriptor?.family, descriptor.family);
      expect(finished.descriptor?.product, 'Petrel 3');
      expect(finished.descriptor?.transports, descriptor.transports);
      final dives = divesOf(events);
      expect(dives, hasLength(8));
      for (final d in dives) {
        expect(d.envelope.family, descriptor.family);
        expect(d.envelope.product, 'Petrel 3');
        expect(d.envelope.descriptorModel, descriptor.model);
      }
      expect(_ids(dives), _ids(fullDives));
      expect(finished.recording.header, [
        'descriptor Shearwater|Petrel 3|${descriptor.family}|${descriptor.model}',
        'requested ${asked.vendor}|${asked.product}|${asked.family}|'
            '${asked.model}',
        'libdivecomputer ${Libdc.pinnedCommit}',
      ]);
    }
    expect(finishedOf(full).descriptor?.family, descriptor.family);
  });

  test('a dive is named and identified by the model the computer reported, '
      'not the sibling opened', () async {
    // The Petrel 2 descriptor (model 3, shared with the Petrel) opens the
    // computer, which reports model 10: a Petrel 3.
    final petrel2 = Libdc.descriptors().singleWhere(
      (d) => d.vendor == 'Shearwater' && d.product == 'Petrel 2',
    );
    final events = await collect(
      LibdcDownload.replay(descriptor: petrel2, recording: trace),
    );
    final dives = divesOf(events);
    expect(dives, hasLength(8));
    expect(finishedOf(events).descriptor?.product, 'Petrel 2');
    for (final d in dives) {
      // The envelope records what was opened, and what the computer said.
      expect(d.envelope.product, 'Petrel 2');
      expect(d.envelope.descriptorModel, petrel2.model);
      expect(d.envelope.devinfoModel, descriptor.model);
      expect(d.converted!.dive.dcProduct, 'Petrel 3');
      expect(d.converted!.dive.dcVendor, 'Shearwater');
    }
    expect(_ids(dives), _ids(fullDives));
    expect(
      dives.map((d) => d.converted!.samples.sampleCount),
      fullDives.map((d) => d.converted!.samples.sampleCount),
    );
  });

  test('a write timeout under a millisecond is refused', () {
    for (final timeout in [Duration.zero, const Duration(microseconds: 500)]) {
      expect(
        () => LibdcDownload.start(
          descriptor: descriptor,
          connection: LibdcBleConnection(
            TraceLink(trace),
            writeTimeout: timeout,
          ),
        ),
        throwsArgumentError,
      );
    }
  });

  test('a trace cut halfway ends with an error status and keeps the dives '
      'before it', () async {
    final half = trace.events.length ~/ 2;
    final events = await collect(
      LibdcDownload.replay(
        descriptor: descriptor,
        recording: LibdcRecording(events: trace.events.sublist(0, half)),
      ),
    );
    final dives = divesOf(events);
    expect(dives.length, inInclusiveRange(1, 7));
    expect(_ids(dives), _ids(fullDives).take(dives.length));
    expect(
      finishedOf(events).status,
      anyOf(LibdcStatus.timeout, LibdcStatus.protocol),
    );
  });

  test('the live path through TraceLink gives the same dives as the '
      'replay', () async {
    final link = TraceLink(trace);
    final download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(link),
    );
    final events = await collect(download);
    final dives = divesOf(events);
    expect(
      dives.map((d) => d.envelope.encode()),
      fullDives.map((d) => d.envelope.encode()),
    );
    expect(_ids(dives), _ids(fullDives));
    final info = events.whereType<LibdcDeviceInfo>().single;
    expect(info.serial, petrelSerial);
    // The 9th dive's next block request is not in the trace, so the link
    // fails it; the shutdown that follows is the trace's last write.
    expect(finishedOf(events).status, LibdcStatus.io);
    expect(link.matchedWrites, 3101);
    expect(
      finishedOf(events).recording.header,
      contains('advertised Petrel 3'),
    );
    expect(link.hasListener, isFalse);
  });

  test('a link that drops halfway ends with IO; the dives before it '
      'arrived', () async {
    final dropAt = _diveStarts(trace)[4] + 10;
    late final TraceLink link;
    link = TraceLink(
      trace,
      onWrite: (index, _) {
        if (index != dropAt) return null;
        link.drop();
        return Completer<void>().future; // the write never completes
      },
    );
    final download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(link),
    );
    final events = await collect(download);
    expect(_ids(divesOf(events)), _ids(fullDives).take(4));
    expect(finishedOf(events).status, LibdcStatus.io);
    expect(link.matchedWrites, dropAt + 1);
  });

  test('with record: true the recording parses and replays to the same '
      'dives', () async {
    final download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(TraceLink(trace)),
      record: true,
    );
    final events = await collect(download);
    final recording = finishedOf(events).recording;
    expect(recording.events.where((e) => e.kind == 'W'), hasLength(3102));
    expect(recording.events.first.kind, 'X', reason: 'configure comes first');
    expect(recording.log, isNotEmpty, reason: 'INFO while recording');
    expect(recording.envelopes, hasLength(8));

    final parsed = LibdcRecording.parse(recording.toText());
    expect(parsed.events, recording.events);
    expect(parsed.advertisedName, 'Petrel 3');
    final replayed = await collect(
      LibdcDownload.replay(descriptor: descriptor, recording: parsed),
    );
    expect(_ids(divesOf(replayed)), _ids(fullDives));
    expect(
      divesOf(replayed).map((d) => d.envelope.encode()),
      fullDives.map((d) => d.envelope.encode()),
    );
    // The 9th dive's block request failed live with IO; its E makes the
    // replay fail it the same way.
    expect(
      recording.events
          .where((e) => e.kind == 'E')
          .map((e) => e.toLine().split('] ').last),
      contains('E ${LibdcStatus.io.code}'),
    );
    expect(finishedOf(replayed).status, finishedOf(events).status);
  });

  test('a write that completes only after the download finished does not '
      'call into the freed link', () async {
    final holdAt = _diveStarts(trace)[1] + 3;
    final held = Completer<void>();
    late final TraceLink link;
    link = TraceLink(
      trace,
      onWrite: (index, _) {
        if (index != holdAt) return null;
        link.drop();
        return held.future;
      },
    );
    final download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(link),
    );
    final events = await collect(download);
    expect(finishedOf(events).status, LibdcStatus.io);
    expect(_ids(divesOf(events)), _ids(fullDives).take(1));
    final native = debugNativeLinkOf(download)!;
    expect(native.isFreed, isTrue);
    expect(native.refusedAfterFree, 0);
    expect(link.hasListener, isFalse);

    // Now the write completes, and a stray notification arrives.
    held.complete();
    link.push(Uint8List.fromList([1, 2, 3]));
    await pumpEventQueue();
    expect(native.refusedAfterFree, 1, reason: 'the late completion');
    download.cancel();
    expect(native.refusedAfterFree, 2, reason: 'a cancel after the end');
  });

  test('a write that never completes times out, and the next request is '
      'still served', () async {
    final holdAt = _diveStarts(trace)[0] + 2;
    final link = TraceLink(
      trace,
      onWrite: (index, _) => index == holdAt ? Completer<void>().future : null,
    );
    final download = LibdcDownload.start(
      descriptor: descriptor,
      connection: LibdcBleConnection(
        link,
        writeTimeout: const Duration(milliseconds: 200),
      ),
    );
    final events = await collect(download);
    expect(finishedOf(events).status, LibdcStatus.timeout);
    expect(divesOf(events), isEmpty);
    // The shutdown at close reached the link after the write that hung.
    expect(link.received.last, hexBytes('01 00 ff 01 05 00 2e 90 20 00 c0'));
    expect(link.received, hasLength(holdAt + 2));
  });

  test('a descriptor that does not exist ends with UNSUPPORTED', () async {
    final events = await collect(
      LibdcDownload.replay(
        descriptor: const LibdcDescriptor(
          vendor: 'Nobody',
          product: 'Nothing',
          family: 0x7fff0000,
          model: 1,
          transports: 0,
        ),
        recording: trace,
      ),
    );
    expect(events, hasLength(1));
    expect(finishedOf(events).status, LibdcStatus.unsupported);
    // Nothing was opened: only what was asked for.
    expect(
      finishedOf(events).recording.header.first,
      startsWith('requested Nobody|Nothing|'),
    );
    expect(
      finishedOf(
        events,
      ).recording.header.where((h) => h.startsWith('descriptor ')),
      isEmpty,
    );
    expect(finishedOf(events).descriptor, isNull);
  });
}
