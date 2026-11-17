import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fit_reader/fit_reader.dart';
import 'package:subsurface_core/subsurface_core.dart';
import 'package:test/test.dart';

/// Pins what the FIT reader produces for each fixture. When the reader's
/// output changes on purpose, bump [kFitParserVersion] (so stored dives are
/// re-parsed) and paste the new digests here.
const int _pinnedVersion = 1;

const Map<String, String> _pinnedDigests = {
  'garmin_mk1_ccr_2023-08-17.fit':
      'aea8d955c0508d4a216418cb61a0d50bf09257d4c662e63c2970fbf962db9bd3',
  'garmin_mk1_ccr_2023-10-21.fit':
      'e57b97ff09352a2f20d14b1553402c618fb9e888e0114846c9413aafc8009d8b',
  'suunto_ocean_nitrox.fit':
      '503f266e097521c8636dc80ceb4ad203bcd2c4a93ef0bbccfa1897b71e81ec2b',
};

/// SHA-256 over the reader's output for one dive: every scalar field in a
/// fixed, named order, the gas and tank JSON, the raw bytes of every sample
/// array (not compressed output, which can differ between zlib builds) and
/// every event field. Fields are listed by hand so a newly added [Dive]
/// field does not silently change the digest.
String fitReaderDigest(ConvertedDive c) {
  final d = c.dive;
  final b = BytesBuilder();
  void line(String s) => b.add(utf8.encode('$s\n'));

  line('id=${d.id}');
  line('dcSerial=${d.dcSerial}');
  line('dcDiveNumber=${d.dcDiveNumber}');
  line('startTime=${d.startTime.millisecondsSinceEpoch}');
  line('endTime=${d.endTime.millisecondsSinceEpoch}');
  line('utcOffsetMinutes=${d.utcOffsetMinutes}');
  line('duration=${d.duration.inMilliseconds}');
  line('maxDepthMeters=${d.maxDepthMeters}');
  line('diveMode=${d.diveMode.index}');
  line('decoModel=${d.decoModel.index}');
  line('gfLow=${d.gfLow}');
  line('gfHigh=${d.gfHigh}');
  line('atmosphericPressureMbar=${d.atmosphericPressureMbar}');
  line('waterDensityKgM3=${d.waterDensityKgM3}');
  line('logVersion=${d.logVersion}');
  line('dcModel=${d.dcModel.index}');
  line('sampleIntervalMs=${d.sampleIntervalMs}');
  line('sensorCalibration=${d.sensorCalibration}');
  line('configuredStackSeconds=${d.configuredStackSeconds}');
  line('stackRemainingAtStartSeconds=${d.stackRemainingAtStartSeconds}');
  line('stackRemainingAtEndSeconds=${d.stackRemainingAtEndSeconds}');
  line('dcVendor=${d.dcVendor}');
  line('dcProduct=${d.dcProduct}');
  line('dcFamily=${d.dcFamily}');
  line('dcModelCode=${d.dcModelCode}');
  line('dcFingerprint=${d.dcFingerprint}');
  line('gasMixes=${jsonEncode([for (final g in d.gasMixes) g.toJson()])}');
  line('tanks=${jsonEncode([for (final t in d.tanks) t.toJson()])}');

  final s = c.samples;
  line('samples.diveId=${s.diveId}');
  line('samples.sampleCount=${s.sampleCount}');
  line('samples.sampleIntervalMs=${s.sampleIntervalMs}');
  void column(String name, TypedData data) {
    line('$name:${data.lengthInBytes}');
    b.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  column('depthMeters', s.depthMeters);
  column('temperatureCelsius', s.temperatureCelsius);
  column('ppo2Bar', s.ppo2Bar);
  column('cellMv0', s.cellMv0);
  column('cellMv1', s.cellMv1);
  column('cellMv2', s.cellMv2);
  column('setpointBar', s.setpointBar);
  column('cns', s.cns);
  column('decoStopDepthMeters', s.decoStopDepthMeters);
  column('decoTimeSeconds', s.decoTimeSeconds);
  column('ttsSeconds', s.ttsSeconds);
  column('gasMixIndex', s.gasMixIndex);
  column('statusFlags', s.statusFlags);
  line('tankPressuresBar.count=${s.tankPressuresBar.length}');
  for (var i = 0; i < s.tankPressuresBar.length; i++) {
    column('tankPressuresBar[$i]', s.tankPressuresBar[i]);
  }
  line('cellPpo2Bar.count=${s.cellPpo2Bar.length}');
  for (var i = 0; i < s.cellPpo2Bar.length; i++) {
    column('cellPpo2Bar[$i]', s.cellPpo2Bar[i]);
  }

  line('events.count=${c.events.length}');
  for (final e in c.events) {
    line('event=${e.timeMs},${e.type.wire},${e.rawType},${e.value},'
        '${e.bearing}');
  }
  return sha256.convert(b.takeBytes()).toString();
}

List<ConvertedDive> _convert(String name) =>
    mapFitFile(File('test/fixtures/$name').readAsBytesSync());

void main() {
  test('kFitParserVersion matches the pinned version, and every fixture '
      'matches its digest', () {
    const message = 'FIT reader output changed: bump kFitParserVersion and '
        'update these digests';
    expect(kFitParserVersion, _pinnedVersion, reason: message);
    for (final entry in _pinnedDigests.entries) {
      printOnFailure('fixture ${entry.key}');
      final dives = _convert(entry.key);
      expect(dives, hasLength(1));
      expect(fitReaderDigest(dives.single), entry.value, reason: message);
    }
  });
}
