import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:subsurface_core/subsurface_core.dart';

import 'container.dart';
import 'dive_reader.dart';
import 'messages.dart';
import 'products.dart';

/// Version of this mapping. Bump it when a change would alter the dives a
/// stored FIT file produces, so cached parses can be redone from the raw file.
const int kFitParserVersion = 1;

/// Seconds from the Unix epoch to the FIT epoch (1989-12-31 00:00:00 UTC).
const int _fitEpochUnix = 631065600;

/// The longest dive a file may claim, record span from session start, 48 h.
const int _maxDiveSeconds = 48 * 3600;

/// Atmospheric pressure used when the file gives none, millibar.
const int _defaultAtmosphericMbar = 1013;

/// The dive id of session [session] of a file: the same shape as
/// `generateDiveId` (sha256, first 32 hex characters) over
/// `fit:<manufacturer>:<serial>:<timeCreated>`, with `:<session>` appended
/// for a session after the first.
///
/// A file without a creation time (null [timeCreated]) uses
/// `fit:<manufacturer>:<serial>:start<sessionStart>` instead, where
/// [sessionStart] is the raw FIT seconds of that session's start; otherwise
/// every such file from one watch would share one id. [sessionStart] is
/// ignored when [timeCreated] is given.
///
/// Ids are frozen at first import: never change this formula.
String fitDiveId({
  required int manufacturer,
  required int serial,
  int? timeCreated,
  int? sessionStart,
  int session = 0,
}) {
  final tail = session >= 1 ? ':$session' : '';
  final anchor = timeCreated != null
      ? '$timeCreated'
      : 'start${_requireStart(sessionStart)}';
  final input = 'fit:$manufacturer:$serial:$anchor$tail';
  return sha256.convert(utf8.encode(input)).toString().substring(0, 32);
}

int _requireStart(int? sessionStart) {
  if (sessionStart == null) {
    throw ArgumentError('sessionStart is required without a timeCreated');
  }
  return sessionStart;
}

/// The fingerprint of a session, lower-case hex: the serial and the file's
/// creation time as big-endian u32s, then one byte with the session number
/// for a session after the first. Without a creation time (null
/// [timeCreated]) the raw session start [sessionStart] takes its place, in
/// the same byte layout.
String fitFingerprintHex({
  required int serial,
  int? timeCreated,
  int? sessionStart,
  int session = 0,
}) {
  final b = ByteData(session >= 1 ? 9 : 8)
    ..setUint32(0, serial)
    ..setUint32(4, timeCreated ?? _requireStart(sessionStart));
  if (session >= 1) b.setUint8(8, session & 0xFF);
  return [
    for (final v in b.buffer.asUint8List()) v.toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Reads every dive session of a FIT file and maps each to a dive.
/// Throws [FitFormatException] for an unreadable file.
List<ConvertedDive> mapFitFile(Uint8List bytes) {
  final file = readFitDives(bytes);
  return [
    for (final s in file.sessions) mapFitSession(file.id, s),
  ];
}

DiveMode _modeFor(int? subSport) => switch (subSport) {
  FitSportKind.ccr => DiveMode.cc,
  FitSportKind.gauge => DiveMode.gauge,
  _ => DiveMode.ocTec,
};

DiveEventType _alertType(int code) => switch (code) {
  FitDiveAlert.decoRequired ||
  FitDiveAlert.approachingNdl ||
  FitDiveAlert.approachingDecoStop => DiveEventType.decoWarning,
  FitDiveAlert.decoCeilingBroken ||
  FitDiveAlert.safetyStopCeilingBroken => DiveEventType.ceilingViolation,
  FitDiveAlert.ascentSpeedCritical => DiveEventType.ascentWarning,
  FitDiveAlert.autoSwitchToLowSetpoint ||
  FitDiveAlert.autoSwitchToHighSetpoint ||
  FitDiveAlert.manualSwitchToLowSetpoint ||
  FitDiveAlert.manualSwitchToHighSetpoint => DiveEventType.setpointChange,
  _ => DiveEventType.other,
};

bool _isLowSetpointAlert(int code) =>
    code == FitDiveAlert.autoSwitchToLowSetpoint ||
    code == FitDiveAlert.manualSwitchToLowSetpoint;

bool _isSetpointAlert(int code) =>
    _isLowSetpointAlert(code) ||
    code == FitDiveAlert.autoSwitchToHighSetpoint ||
    code == FitDiveAlert.manualSwitchToHighSetpoint;

class _Gas {
  final int messageIndex;
  final DiveGasMix mix;
  const _Gas(this.messageIndex, this.mix);
}

class _Sensor {
  final int id;
  final String? name;
  final int maxBar;
  final int reserveBar;
  const _Sensor(this.id, this.name, this.maxBar, this.reserveBar);
}

int _barFrom(int? raw, int? units) {
  if (raw == null) return 0;
  return switch (units) {
    0 => (raw * 0.0689476).round(), // PSI
    1 => (raw / 100).round(), // kPa
    _ => raw, // bar
  };
}

/// The most common positive gap between consecutive timestamps, in seconds;
/// the smaller one on a tie; 1 when there is none.
int _commonGap(List<int> times) {
  final counts = <int, int>{};
  for (var i = 1; i < times.length; i++) {
    final g = times[i] - times[i - 1];
    if (g > 0) counts[g] = (counts[g] ?? 0) + 1;
  }
  var best = 1;
  var bestCount = 0;
  counts.forEach((g, c) {
    if (c > bestCount || (c == bestCount && g < best)) {
      best = g;
      bestCount = c;
    }
  });
  return best;
}

/// Sorts by timestamp, keeping file order among equal timestamps (Dart's
/// List.sort is not stable).
List<FitMessage> _byTime(List<FitMessage> l) {
  final idx = [for (var i = 0; i < l.length; i++) i];
  idx.sort((a, b) {
    final c = (l[a].timestamp ?? 0).compareTo(l[b].timestamp ?? 0);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in idx) l[i]];
}

/// The surface pressure in millibar: the ambient pressure of the earliest
/// record at the shallowest depth, among records at 0.5 m or shallower that
/// have one; null when there is none. (Taking merely the first record within
/// 0.5 m would add up to 50 mbar of water column.)
int? _surfaceMbar(List<FitMessage> records) {
  int? bestDepth, bestPa;
  for (final r in records) {
    final d = r.intField(FitRecord.depth);
    final p = r.intField(FitRecord.absPressure);
    if (d == null || p == null || d > 500) continue;
    if (bestDepth == null || d < bestDepth) {
      bestDepth = d;
      bestPa = p;
    }
  }
  return bestPa == null ? null : (bestPa / 100).round();
}

/// Maps one dive session to a dive with its samples and events.
/// The dive id uses the session's [FitDiveSession.fileSessionIndex].
/// Throws [FitFormatException] for an implausible dive length.
ConvertedDive mapFitSession(FitFileId id, FitDiveSession s) {
  final diveId = fitDiveId(
    manufacturer: id.manufacturer,
    serial: id.serial,
    timeCreated: id.timeCreated,
    sessionStart: s.start,
    session: s.fileSessionIndex,
  );
  final mode = _modeFor(s.subSport);
  final settings = s.diveSettings;

  // ── Gases: enabled and backup-only, in file order ──
  final gases = <_Gas>[];
  for (var i = 0; i < s.diveGases.length; i++) {
    final g = s.diveGases[i];
    if (g.intField(FitDiveGas.status) == 0) continue;
    gases.add(
      _Gas(
        g.intField(FitDiveGas.messageIndex) ?? i,
        DiveGasMix(
          oxygenPercent: g.intField(FitDiveGas.oxygen) ?? 0,
          heliumPercent: g.intField(FitDiveGas.helium) ?? 0,
          isDiluent: g.intField(FitDiveGas.type) == 1,
        ),
      ),
    );
  }
  final mixOfGasIndex = <int, int>{
    for (var i = 0; i < gases.length; i++) gases[i].messageIndex: i,
  };

  // ── Water and deco ──
  final density = settings?.doubleField(FitDiveSettings.waterDensity);
  final waterType = settings?.intField(FitDiveSettings.waterType);
  final waterDensity = density != null && density > 0
      ? density.round()
      : (waterType == 1 ? 1025 : (waterType == 0 ? 1000 : 1000));

  // ── Setpoints, centibar ──
  final lowSp = settings?.intField(FitDiveSettings.lowSetpoint);
  final highSp = settings?.intField(FitDiveSettings.highSetpoint);

  // ── Tanks: tank pods in sensor-profile order, then unprofiled senders ──
  final sensors = <_Sensor>[];
  for (final p in s.sensorProfiles) {
    if (p.intField(FitSensorProfile.sensorType) != 28) continue;
    final sid = p.intField(FitSensorProfile.antChannelId);
    if (sid == null || sensors.any((x) => x.id == sid)) continue;
    final units = p.intField(FitSensorProfile.pressureUnits);
    final name = p.stringField(FitSensorProfile.name);
    sensors.add(
      _Sensor(
        sid,
        (name == null || name.trim().isEmpty) ? null : name.trim(),
        _barFrom(p.intField(FitSensorProfile.ratedPressure), units),
        _barFrom(p.intField(FitSensorProfile.reservePressure), units),
      ),
    );
  }
  final updates = _byTime(s.tankUpdates);
  for (final u in updates) {
    final sid = u.intField(FitTankUpdate.sensor);
    if (sid != null && !sensors.any((x) => x.id == sid)) {
      sensors.add(_Sensor(sid, null, 0, 0));
    }
  }
  final channelOfSensor = <int, int>{
    for (var i = 0; i < sensors.length; i++) sensors[i].id: i,
  };

  // ── Grid ──
  final records = _byTime(s.records);
  final gap = _commonGap([for (final r in records) r.timestamp ?? 0]);
  var n = 0;
  if (records.isNotEmpty) {
    final last = records.last.timestamp ?? s.start;
    n = last <= s.start ? 1 : ((last - s.start + gap - 1) ~/ gap) + 1;
    // A session start far before the records (a bad start_time) would size
    // the grid in the millions of samples.
    if (last - s.start > _maxDiveSeconds ||
        n > records.length * 10 + 3600) {
      throw const FitFormatException('implausible dive length');
    }
  }

  final depth = Float32List(n);
  final temp = Float32List(n);
  final setpoint = Float32List(n);
  final cns = Float32List(n);
  final stopDepth = Float32List(n);
  final decoTime = Int32List(n);
  final tts = Int32List(n);
  final gasIdx = Uint8List(n);
  final tankCh = [for (var _ in sensors) Float32List(n)];

  final events = _byTime(s.events);
  final out = <DiveEvent>[];

  var rp = 0, ep = 0, up = 0;
  var curDepth = 0.0, curTemp = 0.0, curCns = 0.0, curStopDepth = 0.0;
  int curStopTime = 0, curNdl = 0, curTts = 0;
  double curSetpoint = mode == DiveMode.cc && lowSp != null ? lowSp / 100.0 : 0;
  var curGas = 0;
  final curTank = List<double>.filled(sensors.length, 0);
  // Grid index of the first logged value per carried channel; samples before
  // it take that first value (see the back-fill after the loop).
  var tempSeen = false, cnsSeen = false;
  int? tempAt, cnsAt;
  final tankSeen = List<bool>.filled(sensors.length, false);
  final tankAt = List<int?>.filled(sensors.length, null);

  void applyEvent(FitMessage e) {
    final ts = e.timestamp ?? s.start;
    final timeMs = (ts - s.start).clamp(0, 1 << 40) * 1000;
    final kind = e.intField(FitEvent.event);
    final data = e.intField(FitEvent.data);
    if (data == null) return;
    if (kind == FitEvent.diveAlertEvent) {
      // The events codec holds a uint16; larger codes are not alerts.
      if (data > 0xFFFF) return;
      int? sp;
      if (_isSetpointAlert(data)) {
        sp = _isLowSetpointAlert(data) ? lowSp : highSp;
        if (mode == DiveMode.cc && sp != null) curSetpoint = sp / 100.0;
      }
      out.add(
        DiveEvent(
          timeMs: timeMs,
          type: _alertType(data),
          rawType: data,
          value: sp,
        ),
      );
    } else if (kind == FitEvent.gasSwitchEvent) {
      final mix = mixOfGasIndex[data];
      if (mix == null) return;
      curGas = mix;
      out.add(
        DiveEvent(
          timeMs: timeMs,
          type: DiveEventType.gasSwitch,
          rawType: kind!,
          value: mix,
        ),
      );
    }
  }

  // Events at or before a grid time apply from that sample on. Events are
  // also all emitted at their exact time, in order.
  for (var k = 0; k < n; k++) {
    final t = s.start + k * gap;
    while (rp < records.length && (records[rp].timestamp ?? 0) <= t) {
      final r = records[rp++];
      final d = r.intField(FitRecord.depth);
      if (d != null) curDepth = d / 1000.0;
      final tc = r.intField(FitRecord.temperature);
      if (tc != null) {
        curTemp = tc.toDouble();
        tempSeen = true;
      }
      final c = r.intField(FitRecord.cnsLoad);
      if (c != null) {
        curCns = c / 100.0;
        cnsSeen = true;
      }
      final sd = r.intField(FitRecord.nextStopDepth);
      if (sd != null) curStopDepth = sd / 1000.0;
      final st = r.intField(FitRecord.nextStopTime);
      if (st != null) curStopTime = st;
      final nd = r.intField(FitRecord.ndl);
      if (nd != null) curNdl = nd;
      final tt = r.intField(FitRecord.timeToSurface);
      if (tt != null) curTts = tt;
    }
    while (ep < events.length && (events[ep].timestamp ?? s.start) <= t) {
      applyEvent(events[ep++]);
    }
    while (up < updates.length && (updates[up].timestamp ?? 0) <= t) {
      final u = updates[up++];
      final ch = channelOfSensor[u.intField(FitTankUpdate.sensor)];
      final p = u.intField(FitTankUpdate.pressure);
      if (ch != null && p != null) {
        curTank[ch] = p / 100.0;
        tankSeen[ch] = true;
      }
    }
    if (tempSeen) tempAt ??= k;
    if (cnsSeen) cnsAt ??= k;
    for (var c = 0; c < sensors.length; c++) {
      if (tankSeen[c]) tankAt[c] ??= k;
    }
    depth[k] = curDepth;
    temp[k] = curTemp;
    cns[k] = curCns;
    stopDepth[k] = curStopDepth;
    decoTime[k] = curStopDepth > 0 ? curStopTime : curNdl;
    tts[k] = curTts;
    setpoint[k] = curSetpoint;
    gasIdx[k] = curGas;
    for (var c = 0; c < sensors.length; c++) {
      tankCh[c][k] = curTank[c];
    }
  }
  // A sample before a channel's first logged value takes that first value.
  final tAt = tempAt, cAt = cnsAt;
  if (tAt != null) temp.fillRange(0, tAt, temp[tAt]);
  if (cAt != null) cns.fillRange(0, cAt, cns[cAt]);
  for (var c = 0; c < sensors.length; c++) {
    final at = tankAt[c];
    if (at != null) tankCh[c].fillRange(0, at, tankCh[c][at]);
  }
  // Events after the last grid point still count.
  while (ep < events.length) {
    applyEvent(events[ep++]);
  }

  // ── Header values from the samples ──
  var maxDepth = 0.0;
  for (final d in depth) {
    if (d > maxDepth) maxDepth = d;
  }
  final duration = n > 0
      ? Duration(seconds: (n - 1) * gap)
      : Duration(seconds: s.end - s.start);

  // A null offset means the file gave none at all, so the wall clock is taken
  // to equal UTC and the start time is the raw FIT start.
  final offset = s.offsetMinutes;
  final startTime = DateTime.fromMillisecondsSinceEpoch(
    (s.start + _fitEpochUnix + (offset ?? 0) * 60) * 1000,
    isUtc: true,
  );

  // ── Tank records ──
  final tanks = <DiveTank>[];
  for (var i = 0; i < sensors.length; i++) {
    final sensor = sensors[i];
    double? begin, end;
    for (final t in s.tankSummaries) {
      if (t.intField(FitTankSummary.sensor) != sensor.id) continue;
      final b = t.intField(FitTankSummary.startPressure);
      final e = t.intField(FitTankSummary.endPressure);
      if (b != null) begin = b / 100.0;
      if (e != null) end = e / 100.0;
    }
    if (begin == null || end == null) {
      double? first, last;
      for (final u in updates) {
        if (u.intField(FitTankUpdate.sensor) != sensor.id) continue;
        final p = u.intField(FitTankUpdate.pressure);
        if (p == null) continue;
        first ??= p / 100.0;
        last = p / 100.0;
      }
      begin ??= first;
      end ??= last;
    }
    tanks.add(
      DiveTank(
        slot: i,
        usage: TankUsage.none,
        name: sensor.name ?? 'T${i + 1}',
        serial: sensor.id,
        beginPressureBar: begin ?? 0,
        endPressureBar: end ?? 0,
        pressureMaxBar: sensor.maxBar,
        pressureReserveBar: sensor.reserveBar,
      ),
    );
  }

  final dive = Dive(
    id: diveId,
    dcSerial: id.serial,
    dcDiveNumber: s.diveNumber ?? 0,
    startTime: startTime,
    endTime: startTime.add(duration),
    utcOffsetMinutes: offset,
    duration: duration,
    maxDepthMeters: maxDepth,
    diveMode: mode,
    decoModel: DecoModel.gf,
    gfLow: settings?.intField(FitDiveSettings.gfLow) ?? 0,
    gfHigh: settings?.intField(FitDiveSettings.gfHigh) ?? 0,
    atmosphericPressureMbar: _surfaceMbar(records) ?? _defaultAtmosphericMbar,
    waterDensityKgM3: waterDensity,
    logVersion: 0,
    dcModel: ShearwaterModel.unknown,
    gasMixes: [for (final g in gases) g.mix],
    tanks: tanks,
    sampleIntervalMs: gap * 1000,
    sensorCalibration: const [],
    dcVendor: fitVendorName(id.manufacturer),
    dcProduct: fitProductName(
      manufacturer: id.manufacturer,
      product: id.product,
      productName: id.productName,
    ),
    dcFamily: kFitDcFamily,
    dcModelCode: id.product,
    dcFingerprint: fitFingerprintHex(
      serial: id.serial,
      timeCreated: id.timeCreated,
      sessionStart: s.start,
      session: s.fileSessionIndex,
    ),
  );

  final samples = SampleSet(
    diveId: diveId,
    sampleCount: n,
    sampleIntervalMs: gap * 1000,
    depthMeters: depth,
    temperatureCelsius: temp,
    ppo2Bar: Float32List(n),
    cellMv0: Float32List(n),
    cellMv1: Float32List(n),
    cellMv2: Float32List(n),
    setpointBar: setpoint,
    cns: cns,
    decoStopDepthMeters: stopDepth,
    decoTimeSeconds: decoTime,
    ttsSeconds: tts,
    gasMixIndex: gasIdx,
    statusFlags: Uint8List(n),
    tankPressuresBar: tankCh,
    cellPpo2Bar: const [],
  );

  return ConvertedDive(dive: dive, samples: samples, events: out);
}
