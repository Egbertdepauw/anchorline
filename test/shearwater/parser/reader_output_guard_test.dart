import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/parser_version.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../_helpers/patched_dive_718.dart';

/// Pins what the Shearwater reader produces for each fixture. When the
/// reader's output changes on purpose, bump [kShearwaterParserVersion]
/// (so stored dives are re-parsed) and paste the new digests here.
const int _pinnedVersion = 2;

const Map<int, String> _pinnedDigests = {
711: 'd312eeda2ac4f9f5d4027392a72a14968087df09b99fb5ceb01afab57ccab190',
  712: '247ce5a67bb0456dc99c5e729cd9ecc74481f75bacbfe30be27c5e21a451857b',
  713: '0fb12e8cc8056f24df1deea41ce03d55ff8ef6a633d97d89e717081316ba890d',
  714: '116e5bd8e377a56d7fa21bdb871d06acc0b67ca85e382457ad60e9453ddcc650',
  715: '9d5ff874f8c52a4d7f5ea0d47a26e25da7e2523e81dd709718c0e3d7a963c502',
  716: '383c89f0ed20d3761a48590a22246253512f9869a6e8bff4d3ca7ed453985518',
  717: '51fd216166e3f8ae9df466539036798b2fba78f65a4066540ac35914d6e8708e',
  718: '186b92afb24505ed8612ea0af3241a20470a59003b7a27af5d931de13bf8b9c1',
};

const String _patchedDive718Digest = '29b37177b1d55027f8838f36863ceb3006fafef91a1f73c2e515eb5efde5cc39';

/// SHA-256 over the converter's output for one dive: every scalar field in a
/// fixed, named order, the gas and tank JSON, the raw bytes of every sample
/// array (not the zlib output, which can differ between zlib builds) and every
/// event field. Fields are listed by hand so a newly added [Dive] field does
/// not silently change the digest.
///
/// [withEventsAndBrand] false leaves out the events and the brand fields
/// (vendor, product, family, model code).
String readerDigest(ConvertedDive c, {bool withEventsAndBrand = true}) {
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

  if (withEventsAndBrand) {
    line('dcVendor=${d.dcVendor}');
    line('dcProduct=${d.dcProduct}');
    line('dcFamily=${d.dcFamily}');
    line('dcModelCode=${d.dcModelCode}');
    line('events.count=${c.events.length}');
    for (final e in c.events) {
      line('event=${e.timeMs},${e.type.wire},${e.rawType},${e.value},'
          '${e.bearing}');
    }
  }
  return sha256.convert(b.takeBytes()).toString();
}

ConvertedDive convertFixture(int number) {
  final data = File('test/fixtures/dives/dive_$number.bin').readAsBytesSync();
  final parsed = ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
  return DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: number,
    dcModel: ShearwaterModel.petrel3,
  );
}

/// dive_718 with two bookmarks patched in: the only guarded input with events.
ConvertedDive convertPatchedDive718() {
  final parsed = ShearwaterDiveParser(model: ShearwaterModel.petrel3)
      .parse(patchedDive718());
  return DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: 718,
    dcModel: ShearwaterModel.petrel3,
  );
}

void main() {
  test('reader output matches the digests for this version', () {
    const message = 'Shearwater reader output changed: bump '
        'kShearwaterParserVersion and update these digests';
    expect(kShearwaterParserVersion, _pinnedVersion, reason: message);
    for (final entry in _pinnedDigests.entries) {
      printOnFailure('fixture dive_${entry.key}');
      expect(readerDigest(convertFixture(entry.key)), entry.value,
          reason: message);
    }
    printOnFailure('patched dive_718 (two bookmarks)');
    expect(readerDigest(convertPatchedDive718()), _patchedDive718Digest,
        reason: message);
  });
}
