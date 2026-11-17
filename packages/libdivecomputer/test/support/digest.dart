// SHA-256 over everything the mapping produces for one dive: the dive's
// fields, the sample arrays (raw bytes) and the events.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:subsurface_core/subsurface_core.dart';

String _bytes(TypedData d) =>
    sha256.convert(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes)).toString();

/// The digest of [c], a hex string. Any change to the mapping's output
/// changes it.
String mappingDigest(ConvertedDive c) {
  final d = c.dive;
  final s = c.samples;
  final text = StringBuffer()
    ..writeln('id=${d.id} samplesId=${s.diveId}')
    ..writeln('serial=${d.dcSerial} number=${d.dcDiveNumber}')
    ..writeln('start=${d.startTime.toIso8601String()}')
    ..writeln('end=${d.endTime.toIso8601String()}')
    ..writeln('utcOffsetMinutes=${d.utcOffsetMinutes}')
    ..writeln('durationMs=${d.duration.inMilliseconds}')
    ..writeln('maxDepth=${d.maxDepthMeters}')
    ..writeln('mode=${d.diveMode.name} deco=${d.decoModel.name}')
    ..writeln('gf=${d.gfLow}/${d.gfHigh}')
    ..writeln('atm=${d.atmosphericPressureMbar} density=${d.waterDensityKgM3}')
    ..writeln('logVersion=${d.logVersion} model=${d.dcModel.name}')
    ..writeln('intervalMs=${d.sampleIntervalMs}')
    ..writeln(
      'identity=${d.dcVendor}|${d.dcProduct}|${d.dcFamily}|${d.dcModelCode}|'
      '${d.dcFingerprint}',
    )
    ..writeln(
      'calibration=${d.sensorCalibration} stack='
      '${d.configuredStackSeconds}/${d.stackRemainingAtStartSeconds}/'
      '${d.stackRemainingAtEndSeconds}',
    );
  for (final g in d.gasMixes) {
    text.writeln('gas ${g.oxygenPercent}/${g.heliumPercent}/${g.isDiluent}');
  }
  for (final t in d.tanks) {
    text.writeln(
      'tank ${t.slot} ${t.usage.name} ${t.name} ${t.serial} '
      '${t.beginPressureBar} ${t.endPressureBar} ${t.pressureMaxBar} '
      '${t.pressureReserveBar}',
    );
  }
  text
    ..writeln('count=${s.sampleCount} sampleInterval=${s.sampleIntervalMs}')
    ..writeln('depth=${_bytes(s.depthMeters)}')
    ..writeln('temperature=${_bytes(s.temperatureCelsius)}')
    ..writeln('ppo2=${_bytes(s.ppo2Bar)}')
    ..writeln('cellMv=${_bytes(s.cellMv0)} ${_bytes(s.cellMv1)} ${_bytes(s.cellMv2)}')
    ..writeln('setpoint=${_bytes(s.setpointBar)}')
    ..writeln('cns=${_bytes(s.cns)}')
    ..writeln('decoStop=${_bytes(s.decoStopDepthMeters)}')
    ..writeln('decoTime=${_bytes(s.decoTimeSeconds)}')
    ..writeln('tts=${_bytes(s.ttsSeconds)}')
    ..writeln('gasIndex=${_bytes(s.gasMixIndex)}')
    ..writeln('status=${_bytes(s.statusFlags)}');
  for (final t in s.tankPressuresBar) {
    text.writeln('tankPressure=${_bytes(t)}');
  }
  for (final cell in s.cellPpo2Bar) {
    text.writeln('cellPpo2=${_bytes(cell)}');
  }
  for (final e in c.events) {
    text.writeln(
      'event ${e.timeMs} ${e.type.name} ${e.rawType} ${e.bearing} ${e.value}',
    );
  }
  return sha256.convert(utf8.encode(text.toString())).toString();
}
