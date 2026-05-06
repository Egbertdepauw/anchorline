/// Pure-Dart encoder for Subsurface `.ssrf` XML divelog files.
///
/// Takes domain Dive + DiveAnnotation + SampleSet triples and emits a
/// `<divelog>` document compatible with Subsurface's importer (see
/// `core/save-xml.cpp` and `core/parse-xml.cpp` upstream).
///
/// No Flutter / DB / I/O dependencies — testable in isolation.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../data/models/annotation.dart';
import '../data/models/dive.dart';
import '../data/models/sample_set.dart';
import '../shearwater/parser/hardware.dart';
import '../shearwater/parser/parsed_dive.dart' show TankUsage;

/// One dive's worth of data passed to the encoder.
class SubsurfaceDiveExport {
  final Dive dive;
  final DiveAnnotation? annotation;
  final SampleSet? samples;

  SubsurfaceDiveExport({
    required this.dive,
    this.annotation,
    this.samples,
  });
}

/// Encodes a list of dives into a single `.ssrf` XML document.
class SubsurfaceXmlEncoder {
  /// Subsurface dataformat version we target. Matches the value the
  /// upstream writer emits at the time of writing.
  static const int dataformatVersion = 3;

  /// Build the full `<divelog>` document as a pretty-printed string.
  String encode(Iterable<SubsurfaceDiveExport> dives) {
    final list = dives.toList(growable: false);
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('divelog', nest: () {
      builder.attribute('program', 'ccrlogger');
      builder.attribute('version', '$dataformatVersion');
      _writeSettings(builder, list);
      _writeDivesites(builder, list);
      builder.element('dives', nest: () {
        for (final d in list) {
          _writeDive(builder, d);
        }
      });
    });
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  // ── settings ──────────────────────────────────────────────────────────

  void _writeSettings(XmlBuilder b, List<SubsurfaceDiveExport> dives) {
    final seen = <String>{};
    final entries = <_DcIdentity>[];
    for (final d in dives) {
      final id = _dcIdentity(d.dive);
      if (seen.add(id.deviceid)) entries.add(id);
    }
    b.element('settings', nest: () {
      for (final e in entries) {
        b.element('divecomputerid', nest: () {
          b.attribute('model', e.model);
          b.attribute('deviceid', e.deviceid);
          b.attribute('serial', e.serial);
        });
      }
    });
  }

  // ── divesites ─────────────────────────────────────────────────────────

  void _writeDivesites(XmlBuilder b, List<SubsurfaceDiveExport> dives) {
    // Distinct site names → first-seen entry wins (for coords).
    final byName = <String, DiveAnnotation>{};
    for (final d in dives) {
      final ann = d.annotation;
      final name = ann?.siteName?.trim();
      if (ann == null || name == null || name.isEmpty) continue;
      byName.putIfAbsent(name, () => ann);
    }
    if (byName.isEmpty) return;
    b.element('divesites', nest: () {
      final sortedNames = byName.keys.toList()..sort();
      for (final name in sortedNames) {
        final ann = byName[name]!;
        b.element('site', nest: () {
          b.attribute('uuid', siteUuid(name));
          b.attribute('name', name);
          if (ann.siteLatitude != null && ann.siteLongitude != null) {
            b.attribute(
              'gps',
              '${_fmt5(ann.siteLatitude!)} ${_fmt5(ann.siteLongitude!)}',
            );
          }
        });
      }
    });
  }

  // ── dive ──────────────────────────────────────────────────────────────

  void _writeDive(XmlBuilder b, SubsurfaceDiveExport d) {
    final dive = d.dive;
    final ann = d.annotation;
    final localStart = _localStart(dive);
    b.element('dive', nest: () {
      b.attribute('number', '${dive.dcDiveNumber}');
      if (ann?.rating != null) b.attribute('rating', '${ann!.rating}');
      if (ann != null && ann.tags.isNotEmpty) {
        b.attribute('tags', ann.tags.join(', '));
      }
      final siteName = ann?.siteName?.trim();
      if (siteName != null && siteName.isNotEmpty) {
        b.attribute('divesiteid', siteUuid(siteName));
      }
      b.attribute('date', _date(localStart));
      b.attribute('time', _time(localStart));
      b.attribute('duration', _mmss(dive.duration.inSeconds));

      // Buddies + notes are nested elements.
      if (ann != null && ann.buddies.isNotEmpty) {
        b.element('buddy', nest: ann.buddies.join(', '));
      }
      final notes = ann?.notes;
      if (notes != null && notes.isNotEmpty) {
        b.element('notes', nest: notes);
      }

      _writeCylinders(b, dive);
      _writeDiveComputer(b, d);
    });
  }

  void _writeCylinders(XmlBuilder b, Dive dive) {
    final ordered = _cylinderOrder(dive.tanks);
    for (final t in ordered) {
      final mix = _mixForTank(dive, t);
      b.element('cylinder', nest: () {
        b.attribute('size', '${_fmt1(0)} l');
        b.attribute('workpressure', '${_fmt1(t.pressureMaxBar.toDouble())} bar');
        b.attribute('description', _tankDescription(t));
        if (mix != null) {
          b.attribute('o2', '${_fmt1(mix.oxygenPercent.toDouble())}%');
          b.attribute('he', '${_fmt1(mix.heliumPercent.toDouble())}%');
        } else {
          b.attribute('o2', '${_fmt1(_o2ForUsage(t.usage).toDouble())}%');
          b.attribute('he', '${_fmt1(0)}%');
        }
        b.attribute('start', '${_fmt1(t.beginPressureBar)} bar');
        b.attribute('end', '${_fmt1(t.endPressureBar)} bar');
      });
    }
  }

  void _writeDiveComputer(XmlBuilder b, SubsurfaceDiveExport d) {
    final dive = d.dive;
    final samples = d.samples;
    final id = _dcIdentity(dive);
    b.element('divecomputer', nest: () {
      b.attribute('model', id.model);
      b.attribute('deviceid', id.deviceid);

      b.element('depth', nest: () {
        b.attribute('max', '${_fmt2(dive.maxDepthMeters)} m');
      });
      b.element('surface', nest: () {
        b.attribute(
          'pressure',
          '${_fmt3(dive.atmosphericPressureMbar / 1000.0)} bar',
        );
      });
      b.element('water', nest: () {
        b.attribute(
          'salinity',
          '${_fmt3(dive.waterDensityKgM3 / 1000.0)} kg/l',
        );
      });

      // Scrubber stack as extradata (Subsurface displays unknown extradata
      // in the dive computer pane).
      _writeStack(b, 'Configured stack time', dive.configuredStackSeconds);
      _writeStack(b, 'Remaining stack time at start',
          dive.stackRemainingAtStartSeconds);
      _writeStack(
          b, 'Remaining stack time at end', dive.stackRemainingAtEndSeconds);

      if (samples != null) {
        _writeSamples(b, dive, samples);
      }
    });
  }

  void _writeStack(XmlBuilder b, String key, int? seconds) {
    if (seconds == null) return;
    b.element('extradata', nest: () {
      b.attribute('key', key);
      b.attribute('value', _hms(seconds));
    });
  }

  void _writeSamples(XmlBuilder b, Dive dive, SampleSet s) {
    final isOc = !dive.diveMode.isCcr;
    final intervalMs = s.sampleIntervalMs;
    for (var i = 0; i < s.sampleCount; i++) {
      b.element('sample', nest: () {
        final tSec = (i * intervalMs) ~/ 1000;
        b.attribute('time', _mmss(tSec));
        b.attribute('depth', '${_fmt1(s.depthMeters[i])} m');
        final temp = s.temperatureCelsius[i];
        if (temp != 0) {
          b.attribute('temp', '${_fmt1(temp)} °C');
        }
        final ppo2 = s.ppo2Bar[i];
        if (ppo2 > 0) {
          b.attribute('ppo2', '${_fmt2(ppo2)} bar');
        }
        if (!isOc) {
          final sp = s.setpointBar[i];
          if (sp > 0) b.attribute('setpoint', '${_fmt2(sp)} bar');
        }
      });
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────

  static String siteUuid(String name) {
    final input = 'site:${name.trim().toLowerCase()}';
    return sha1.convert(utf8.encode(input)).toString().substring(0, 8);
  }

  _DcIdentity _dcIdentity(Dive dive) {
    final serial = dive.dcSerial.toRadixString(16).padLeft(8, '0').toUpperCase();
    return _DcIdentity(
      model: _modelLabel(dive.dcModel),
      deviceid: serial.toLowerCase(),
      serial: serial,
    );
  }

  String _modelLabel(ShearwaterModel m) {
    return switch (m) {
      ShearwaterModel.predator => 'Predator',
      ShearwaterModel.petrel => 'Petrel',
      ShearwaterModel.petrel2 => 'Petrel 2',
      ShearwaterModel.petrel3 => 'Petrel 3',
      ShearwaterModel.nerd => 'NERD',
      ShearwaterModel.nerd2 => 'NERD 2',
      ShearwaterModel.perdix => 'Perdix',
      ShearwaterModel.perdixAi => 'Perdix AI',
      ShearwaterModel.perdix2 => 'Perdix 2',
      ShearwaterModel.teric => 'Teric',
      ShearwaterModel.peregrine => 'Peregrine',
      ShearwaterModel.peregrineTx => 'Peregrine TX',
      ShearwaterModel.tern => 'Tern',
      ShearwaterModel.unknown => 'Shearwater',
    };
  }

  String _tankDescription(DiveTank t) {
    switch (t.usage) {
      case TankUsage.diluent:
        return 'Diluent';
      case TankUsage.oxygen:
        return 'Oxygen';
      case TankUsage.sidemount:
        return t.name.isEmpty ? 'Sidemount' : t.name;
      case TankUsage.none:
        return t.name.isEmpty ? 'Tank ${t.slot + 1}' : t.name;
    }
  }

  /// Diluent first, oxygen second, then sidemount, then none/other.
  /// Within a usage class, preserve the slot order.
  List<DiveTank> _cylinderOrder(List<DiveTank> tanks) {
    int rank(TankUsage u) {
      return switch (u) {
        TankUsage.diluent => 0,
        TankUsage.oxygen => 1,
        TankUsage.sidemount => 2,
        TankUsage.none => 3,
      };
    }

    final indexed = [
      for (var i = 0; i < tanks.length; i++) (i: i, t: tanks[i]),
    ];
    indexed.sort((a, b) {
      final r = rank(a.t.usage).compareTo(rank(b.t.usage));
      if (r != 0) return r;
      return a.i.compareTo(b.i);
    });
    return [for (final e in indexed) e.t];
  }

  /// Best-effort mix lookup for a tank.
  DiveGasMix? _mixForTank(Dive dive, DiveTank t) {
    if (dive.gasMixes.isEmpty) return null;
    if (t.usage == TankUsage.oxygen) {
      for (final m in dive.gasMixes) {
        if (m.oxygenPercent == 100) return m;
      }
    }
    if (t.usage == TankUsage.diluent) {
      for (final m in dive.gasMixes) {
        if (m.isDiluent) return m;
      }
    }
    return null;
  }

  int _o2ForUsage(TankUsage u) {
    return switch (u) {
      TankUsage.oxygen => 100,
      _ => 21,
    };
  }

  // Format helpers — always '.' decimal, locale-insensitive.
  String _fmt1(double v) => v.toStringAsFixed(1);
  String _fmt2(double v) => v.toStringAsFixed(2);
  String _fmt3(double v) => v.toStringAsFixed(3);
  String _fmt5(double v) => v.toStringAsFixed(5);

  String _mmss(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')} min';
  }

  String _hms(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = s % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  DateTime _localStart(Dive dive) {
    if (dive.utcOffsetMinutes == null) return dive.startTime;
    return dive.startTime.add(Duration(minutes: dive.utcOffsetMinutes!));
  }

  String _date(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

class _DcIdentity {
  final String model;
  final String deviceid;
  final String serial;

  _DcIdentity({
    required this.model,
    required this.deviceid,
    required this.serial,
  });
}
