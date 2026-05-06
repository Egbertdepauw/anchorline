import 'dart:typed_data';

import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/data/models/dive.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/shearwater/parser/parsed_dive.dart' show TankUsage;
import 'package:ccrlogger/sync/subsurface_xml_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Dive _dive({
  String id = 'd1',
  int dcSerial = 0xB89641E4,
  int dcDiveNumber = 718,
  DateTime? startTime,
  Duration duration = const Duration(minutes: 57, seconds: 52),
  double maxDepthMeters = 39.2,
  DiveMode diveMode = DiveMode.cc,
  List<DiveGasMix> gasMixes = const [],
  List<DiveTank> tanks = const [],
  int? configuredStackSeconds,
  int? stackRemainingAtStartSeconds,
  int? stackRemainingAtEndSeconds,
}) {
  final start = startTime ??
      DateTime.utc(2026, 4, 19, 10, 38, 45);
  return Dive(
    id: id,
    dcSerial: dcSerial,
    dcDiveNumber: dcDiveNumber,
    startTime: start,
    endTime: start.add(duration),
    duration: duration,
    maxDepthMeters: maxDepthMeters,
    diveMode: diveMode,
    decoModel: DecoModel.gf,
    gfLow: 30,
    gfHigh: 70,
    atmosphericPressureMbar: 1013,
    waterDensityKgM3: 1025,
    logVersion: 17,
    dcModel: ShearwaterModel.petrel3,
    gasMixes: gasMixes,
    tanks: tanks,
    sampleIntervalMs: 10000,
    configuredStackSeconds: configuredStackSeconds,
    stackRemainingAtStartSeconds: stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: stackRemainingAtEndSeconds,
  );
}

DiveAnnotation _ann({
  String diveId = 'd1',
  String? siteName,
  double? lat,
  double? lon,
  String? notes,
  List<String> buddies = const [],
  List<String> tags = const [],
  int? rating,
}) {
  final now = DateTime.utc(2026, 4, 20);
  return DiveAnnotation(
    diveId: diveId,
    siteName: siteName,
    siteLatitude: lat,
    siteLongitude: lon,
    notes: notes,
    buddies: buddies,
    tags: tags,
    rating: rating,
    createdAt: now,
    updatedAt: now,
  );
}

SampleSet _samples({
  String diveId = 'd1',
  required int count,
  int intervalMs = 10000,
  bool ccr = true,
}) {
  final depth = Float32List(count);
  final temp = Float32List(count);
  final ppo2 = Float32List(count);
  final sp = Float32List(count);
  for (var i = 0; i < count; i++) {
    depth[i] = 0.5 + i * 0.7;
    temp[i] = 17.0;
    ppo2[i] = 0.20 + i * 0.10;
    sp[i] = ccr ? 0.7 : 0.0;
  }
  return SampleSet(
    diveId: diveId,
    sampleCount: count,
    sampleIntervalMs: intervalMs,
    depthMeters: depth,
    temperatureCelsius: temp,
    ppo2Bar: ppo2,
    cellMv0: Float32List(count),
    cellMv1: Float32List(count),
    cellMv2: Float32List(count),
    setpointBar: sp,
    cns: Float32List(count),
    decoStopDepthMeters: Float32List(count),
    decoTimeSeconds: Int32List(count),
    ttsSeconds: Int32List(count),
    gasMixIndex: Uint8List(count),
    statusFlags: Uint8List(count),
  );
}

void main() {
  final encoder = SubsurfaceXmlEncoder();

  test('empty list emits a parseable <divelog> with empty <dives>', () {
    final xml = encoder.encode(const []);
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    expect(root.name.local, 'divelog');
    expect(root.getAttribute('program'), 'ccrlogger');
    expect(root.findElements('dives').single.children.whereType<XmlElement>(),
        isEmpty);
  });

  test('one dive with no annotation/tanks/samples', () {
    final xml = encoder.encode([SubsurfaceDiveExport(dive: _dive())]);
    final doc = XmlDocument.parse(xml);
    final dive = doc.rootElement.findAllElements('dive').single;
    expect(dive.getAttribute('number'), '718');
    expect(dive.getAttribute('date'), '2026-04-19');
    expect(dive.getAttribute('time'), '10:38:45');
    expect(dive.getAttribute('duration'), '57:52 min');
    final dc = dive.findElements('divecomputer').single;
    expect(dc.findElements('depth').single.getAttribute('max'), '39.20 m');
    expect(dc.findElements('sample'), isEmpty);
    expect(dive.findElements('cylinder'), isEmpty);
    // No divesites section when no annotations had a site.
    expect(doc.rootElement.findElements('divesites'), isEmpty);
  });

  test('one dive with annotation: site, buddies, notes, rating, tags', () {
    final xml = encoder.encode([
      SubsurfaceDiveExport(
        dive: _dive(),
        annotation: _ann(
          siteName: 'Vinkeveen',
          lat: 52.21456,
          lon: 4.95012,
          notes: 'Free-text notes here',
          buddies: ['Alice', 'Bob'],
          tags: ['wreck', 'deep'],
          rating: 4,
        ),
      )
    ]);
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    final site = root.findElements('divesites').single.findElements('site').single;
    expect(site.getAttribute('name'), 'Vinkeveen');
    expect(site.getAttribute('gps'), '52.21456 4.95012');
    final uuid = site.getAttribute('uuid')!;
    expect(uuid.length, 8);

    final dive = root.findAllElements('dive').single;
    expect(dive.getAttribute('rating'), '4');
    expect(dive.getAttribute('tags'), 'wreck, deep');
    expect(dive.getAttribute('divesiteid'), uuid);
    expect(dive.findElements('buddy').single.innerText, 'Alice, Bob');
    expect(dive.findElements('notes').single.innerText, 'Free-text notes here');
  });

  test('one dive with two tanks emits two <cylinder> with start/end pressure',
      () {
    final dive = _dive(
      gasMixes: [
        DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
        DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
      ],
      tanks: [
        DiveTank(
          slot: 0,
          usage: TankUsage.oxygen,
          name: 'O2',
          serial: 0,
          beginPressureBar: 142.0,
          endPressureBar: 116.0,
          pressureMaxBar: 232,
          pressureReserveBar: 50,
        ),
        DiveTank(
          slot: 1,
          usage: TankUsage.diluent,
          name: 'DI',
          serial: 0,
          beginPressureBar: 168.0,
          endPressureBar: 145.0,
          pressureMaxBar: 232,
          pressureReserveBar: 50,
        ),
      ],
    );
    final xml = encoder.encode([SubsurfaceDiveExport(dive: dive)]);
    final doc = XmlDocument.parse(xml);
    final cylinders =
        doc.rootElement.findAllElements('cylinder').toList(growable: false);
    expect(cylinders, hasLength(2));
    // Diluent first.
    expect(cylinders[0].getAttribute('description'), 'Diluent');
    expect(cylinders[0].getAttribute('start'), '168.0 bar');
    expect(cylinders[0].getAttribute('end'), '145.0 bar');
    expect(cylinders[0].getAttribute('o2'), '21.0%');
    expect(cylinders[0].getAttribute('he'), '35.0%');
    // Oxygen second.
    expect(cylinders[1].getAttribute('description'), 'Oxygen');
    expect(cylinders[1].getAttribute('start'), '142.0 bar');
    expect(cylinders[1].getAttribute('end'), '116.0 bar');
    expect(cylinders[1].getAttribute('o2'), '100.0%');
    expect(cylinders[1].getAttribute('he'), '0.0%');
  });

  test('one dive with samples emits one <sample> per stored sample', () {
    final dive = _dive();
    final samples = _samples(diveId: dive.id, count: 5);
    final xml = encoder.encode(
        [SubsurfaceDiveExport(dive: dive, samples: samples)]);
    final doc = XmlDocument.parse(xml);
    final sampleEls = doc.rootElement.findAllElements('sample').toList();
    expect(sampleEls, hasLength(5));
    expect(sampleEls.first.getAttribute('time'), '0:00 min');
    expect(sampleEls.first.getAttribute('depth'), '0.5 m');
    expect(sampleEls.first.getAttribute('setpoint'), '0.70 bar');
    expect(sampleEls[1].getAttribute('time'), '0:10 min');
  });

  test('distinct sites get distinct UUIDs; same name → same UUID', () {
    final a = SubsurfaceXmlEncoder.siteUuid('Vinkeveen');
    final aTrim = SubsurfaceXmlEncoder.siteUuid('  vinkeveen ');
    final b = SubsurfaceXmlEncoder.siteUuid('Zeelandbrug');
    expect(a, aTrim);
    expect(a, isNot(b));
    expect(a.length, 8);
  });
}
