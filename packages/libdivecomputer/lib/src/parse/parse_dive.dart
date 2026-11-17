import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings.g.dart' as c;
import '../envelope.dart';
import 'parsed_dive.dart';
import 'status.dart';

const int _timezoneNone = -2147483648; // DC_TIMEZONE_NONE (INT_MIN)
const int _gasmixUnknown = 0xFFFFFFFF; // DC_GASMIX_UNKNOWN
const int _sensorNone = 0xFFFFFFFF; // DC_SENSOR_NONE

/// Parses the dive stored in [e] with libdivecomputer's `dc_parser_new2`,
/// using the descriptor found by vendor and product (else by family and
/// model), and returns what it reported.
///
/// Runs on whichever isolate calls it. Everything native it allocates is
/// freed on every path. Throws [LibdcParseException] on any failure.
LibdcParsedDive parseDive(LibdcEnvelope e) {
  Pointer<c.dc_context_t> context = nullptr;
  Pointer<c.dc_descriptor_t> descriptor = nullptr;
  Pointer<c.dc_parser_t> parser = nullptr;
  NativeCallable<c.dc_sample_callback_tFunction>? callable;
  try {
    return using((arena) {
      final contextOut = arena<Pointer<c.dc_context_t>>();
      _check(c.dc_context_new(contextOut));
      context = contextOut.value;

      descriptor = _findDescriptor(context, e);
      if (descriptor == nullptr) {
        throw const LibdcParseException(LibdcStatus.unsupported);
      }

      // A zero-length allocation may be null; always ask for one byte.
      final buffer = arena<Uint8>(e.data.isEmpty ? 1 : e.data.length);
      buffer.asTypedList(e.data.length).setAll(0, e.data);

      final parserOut = arena<Pointer<c.dc_parser_t>>();
      _check(
        c.dc_parser_new2(
          parserOut,
          context,
          descriptor,
          buffer.cast(),
          e.data.length,
        ),
      );
      parser = parserOut.value;

      final devtime = e.devtime;
      final systime = e.systime;
      if (devtime != null && systime != null) {
        // Only some families need the clock; the rest answer UNSUPPORTED.
        c.dc_parser_set_clock(parser, devtime, systime);
      }

      final wall = _datetime(arena, parser);
      final diveTime = _uintField(arena, parser, c.dc_field_type_t.DC_FIELD_DIVETIME);
      final maxDepth = _doubleField(arena, parser, c.dc_field_type_t.DC_FIELD_MAXDEPTH);
      final atmospheric = _doubleField(
        arena,
        parser,
        c.dc_field_type_t.DC_FIELD_ATMOSPHERIC,
      );
      final salinity = _salinity(arena, parser);
      final mixes = _gasMixes(arena, parser);
      final tanks = _tanks(arena, parser);
      final mode = _diveMode(arena, parser);
      final deco = _decoModel(arena, parser);

      final rows = <LibdcSampleRow>[];
      Object? callbackError;
      void onSample(int type, Pointer<c.dc_sample_value_t> value, Pointer<Void> _) {
        if (callbackError != null) return;
        try {
          _onSample(rows, type, value.ref);
        } catch (error) {
          callbackError = error;
        }
      }

      callable = NativeCallable<c.dc_sample_callback_tFunction>.isolateLocal(
        onSample,
      );
      final status = c.dc_parser_samples_foreach(
        parser,
        callable!.nativeFunction,
        nullptr,
      );
      if (callbackError != null) {
        throw const LibdcParseException(LibdcStatus.dataFormat);
      }
      _check(status);

      return LibdcParsedDive(
        wallClock: wall?.$1,
        timezoneSeconds: wall?.$2,
        diveTimeSeconds: diveTime,
        maxDepthM: maxDepth,
        atmosphericBar: atmospheric,
        salinity: salinity,
        gasMixes: mixes,
        tanks: tanks,
        diveMode: mode,
        decoModel: deco,
        rows: rows,
      );
    });
  } finally {
    callable?.close();
    if (parser != nullptr) c.dc_parser_destroy(parser);
    if (descriptor != nullptr) c.dc_descriptor_free(descriptor);
    if (context != nullptr) c.dc_context_free(context);
  }
}

void _check(int status) {
  if (status != c.dc_status_t.DC_STATUS_SUCCESS) {
    throw LibdcParseException(LibdcStatus.fromCode(status));
  }
}

/// True when the field is there; false for UNSUPPORTED; throws otherwise.
bool _present(int status) {
  if (status == c.dc_status_t.DC_STATUS_SUCCESS) return true;
  if (status == c.dc_status_t.DC_STATUS_UNSUPPORTED) return false;
  throw LibdcParseException(LibdcStatus.fromCode(status));
}

/// The descriptor for [e]: by vendor and product name first, since family
/// numbers can change between libdivecomputer versions, and only then by
/// family and model. Returns `nullptr` when there is none; the caller owns
/// the result.
Pointer<c.dc_descriptor_t> _findDescriptor(
  Pointer<c.dc_context_t> context,
  LibdcEnvelope e,
) {
  Pointer<c.dc_descriptor_t> byFamily = nullptr;
  Pointer<c.dc_descriptor_t> byName = nullptr;
  using((arena) {
    final iterator = arena<Pointer<c.dc_iterator_t>>();
    final item = arena<Pointer<c.dc_descriptor_t>>();
    _check(c.dc_descriptor_iterator_new(iterator, context));
    final it = iterator.value;
    try {
      while (byName == nullptr) {
        final status = c.dc_iterator_next(it, item.cast());
        if (status == c.dc_status_t.DC_STATUS_DONE) break;
        _check(status);
        final d = item.value;
        final vendor = c.dc_descriptor_get_vendor(d).cast<Utf8>().toDartString();
        final product = c.dc_descriptor_get_product(d).cast<Utf8>().toDartString();
        if (vendor == e.vendor && product == e.product) {
          byName = d;
        } else if (byFamily == nullptr &&
            c.dc_descriptor_get_type(d) == e.family &&
            c.dc_descriptor_get_model(d) == e.descriptorModel) {
          byFamily = d;
        } else {
          c.dc_descriptor_free(d);
        }
      }
    } catch (_) {
      if (byName != nullptr) c.dc_descriptor_free(byName);
      if (byFamily != nullptr) c.dc_descriptor_free(byFamily);
      rethrow;
    } finally {
      c.dc_iterator_free(it);
    }
  });
  if (byName != nullptr) {
    if (byFamily != nullptr) c.dc_descriptor_free(byFamily);
    return byName;
  }
  return byFamily;
}

(DateTime, int?)? _datetime(Arena arena, Pointer<c.dc_parser_t> parser) {
  final dt = arena<c.dc_datetime_t>();
  if (!_present(c.dc_parser_get_datetime(parser, dt))) return null;
  final r = dt.ref;
  final wall = DateTime.utc(r.year, r.month, r.day, r.hour, r.minute, r.second);
  return (wall, r.timezone == _timezoneNone ? null : r.timezone);
}

int? _uintField(Arena arena, Pointer<c.dc_parser_t> parser, int field) {
  final out = arena<Uint32>();
  return _present(c.dc_parser_get_field(parser, field, 0, out.cast()))
      ? out.value
      : null;
}

double? _doubleField(Arena arena, Pointer<c.dc_parser_t> parser, int field) {
  final out = arena<Double>();
  return _present(c.dc_parser_get_field(parser, field, 0, out.cast()))
      ? out.value
      : null;
}

LibdcSalinity? _salinity(Arena arena, Pointer<c.dc_parser_t> parser) {
  final out = arena<c.dc_salinity_t>();
  if (!_present(
    c.dc_parser_get_field(
      parser,
      c.dc_field_type_t.DC_FIELD_SALINITY,
      0,
      out.cast(),
    ),
  )) {
    return null;
  }
  return LibdcSalinity(
    water: out.ref.type == c.dc_water_t.DC_WATER_SALT
        ? LibdcWater.salt
        : LibdcWater.fresh,
    density: out.ref.density,
  );
}

List<LibdcGasMix> _gasMixes(Arena arena, Pointer<c.dc_parser_t> parser) {
  final count =
      _uintField(arena, parser, c.dc_field_type_t.DC_FIELD_GASMIX_COUNT) ?? 0;
  final out = arena<c.dc_gasmix_t>();
  final mixes = <LibdcGasMix>[];
  for (var i = 0; i < count; i++) {
    _check(
      c.dc_parser_get_field(
        parser,
        c.dc_field_type_t.DC_FIELD_GASMIX,
        i,
        out.cast(),
      ),
    );
    mixes.add(
      LibdcGasMix(
        oxygen: out.ref.oxygen,
        helium: out.ref.helium,
        usage: LibdcUsage.fromCode(out.ref.usage),
      ),
    );
  }
  return mixes;
}

List<LibdcTank> _tanks(Arena arena, Pointer<c.dc_parser_t> parser) {
  final count =
      _uintField(arena, parser, c.dc_field_type_t.DC_FIELD_TANK_COUNT) ?? 0;
  final out = arena<c.dc_tank_t>();
  final tanks = <LibdcTank>[];
  for (var i = 0; i < count; i++) {
    _check(
      c.dc_parser_get_field(
        parser,
        c.dc_field_type_t.DC_FIELD_TANK,
        i,
        out.cast(),
      ),
    );
    final t = out.ref;
    tanks.add(
      LibdcTank(
        gasMix: t.gasmix == _gasmixUnknown ? null : t.gasmix,
        volumeLiters: t.volume,
        workPressureBar: t.workpressure,
        beginPressureBar: t.beginpressure,
        endPressureBar: t.endpressure,
        usage: LibdcUsage.fromCode(t.usage),
      ),
    );
  }
  return tanks;
}

LibdcDiveMode? _diveMode(Arena arena, Pointer<c.dc_parser_t> parser) {
  final code = _uintField(arena, parser, c.dc_field_type_t.DC_FIELD_DIVEMODE);
  return switch (code) {
    c.dc_divemode_t.DC_DIVEMODE_FREEDIVE => LibdcDiveMode.freedive,
    c.dc_divemode_t.DC_DIVEMODE_GAUGE => LibdcDiveMode.gauge,
    c.dc_divemode_t.DC_DIVEMODE_OC => LibdcDiveMode.oc,
    c.dc_divemode_t.DC_DIVEMODE_CCR => LibdcDiveMode.ccr,
    c.dc_divemode_t.DC_DIVEMODE_SCR => LibdcDiveMode.scr,
    _ => null,
  };
}

LibdcDecoModel? _decoModel(Arena arena, Pointer<c.dc_parser_t> parser) {
  final out = arena<c.dc_decomodel_t>();
  if (!_present(
    c.dc_parser_get_field(
      parser,
      c.dc_field_type_t.DC_FIELD_DECOMODEL,
      0,
      out.cast(),
    ),
  )) {
    return null;
  }
  final type = switch (out.ref.type) {
    c.dc_decomodel_type_t.DC_DECOMODEL_BUHLMANN => LibdcDecoModelType.buhlmann,
    c.dc_decomodel_type_t.DC_DECOMODEL_VPM => LibdcDecoModelType.vpm,
    c.dc_decomodel_type_t.DC_DECOMODEL_RGBM => LibdcDecoModelType.rgbm,
    c.dc_decomodel_type_t.DC_DECOMODEL_DCIEM => LibdcDecoModelType.dciem,
    _ => LibdcDecoModelType.none,
  };
  final gf = out.ref.params.gf;
  return LibdcDecoModel(
    type: type,
    gfLow: type == LibdcDecoModelType.buhlmann ? gf.low : null,
    gfHigh: type == LibdcDecoModelType.buhlmann ? gf.high : null,
  );
}

/// One `dc_parser_samples_foreach` callback. `DC_SAMPLE_TIME` opens a row;
/// everything else lands on the open row. Samples before the first time
/// have no row to land on and are dropped.
void _onSample(
  List<LibdcSampleRow> rows,
  int type,
  c.dc_sample_value_t v,
) {
  if (type == c.dc_sample_type_t.DC_SAMPLE_TIME) {
    rows.add(LibdcSampleRow(timeMs: v.time));
    return;
  }
  if (rows.isEmpty) return;
  final row = rows.last;
  switch (type) {
    case c.dc_sample_type_t.DC_SAMPLE_DEPTH:
      row.depthM = v.depth;
    case c.dc_sample_type_t.DC_SAMPLE_PRESSURE:
      row.pressures[v.pressure.tank] = v.pressure.value;
    case c.dc_sample_type_t.DC_SAMPLE_TEMPERATURE:
      row.temperatureC = v.temperature;
    case c.dc_sample_type_t.DC_SAMPLE_EVENT:
      row.events.add(
        LibdcSampleEvent(
          type: v.event.type,
          flags: v.event.flags,
          value: v.event.value,
        ),
      );
    case c.dc_sample_type_t.DC_SAMPLE_SETPOINT:
      row.setpoint = v.setpoint;
    case c.dc_sample_type_t.DC_SAMPLE_PPO2:
      if (v.ppo2.sensor == _sensorNone) {
        row.ppo2Voted = v.ppo2.value;
      } else {
        row.cells[v.ppo2.sensor] = v.ppo2.value;
      }
    case c.dc_sample_type_t.DC_SAMPLE_CNS:
      row.cns = v.cns;
    case c.dc_sample_type_t.DC_SAMPLE_DECO:
      row.deco = LibdcDeco(
        type: switch (v.deco.type) {
          c.dc_deco_type_t.DC_DECO_SAFETYSTOP => LibdcDecoType.safetyStop,
          c.dc_deco_type_t.DC_DECO_DECOSTOP => LibdcDecoType.decoStop,
          c.dc_deco_type_t.DC_DECO_DEEPSTOP => LibdcDecoType.deepStop,
          _ => LibdcDecoType.ndl,
        },
        timeSeconds: v.deco.time,
        depthM: v.deco.depth,
        ttsSeconds: v.deco.tts,
      );
    case c.dc_sample_type_t.DC_SAMPLE_GASMIX:
      row.gasMix = v.gasmix == _gasmixUnknown ? null : v.gasmix;
    default:
      break;
  }
}
