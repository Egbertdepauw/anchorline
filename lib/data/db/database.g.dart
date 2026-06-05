// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DivesTable extends Dives with TableInfo<$DivesTable, Dive> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DivesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dcSerialMeta = const VerificationMeta(
    'dcSerial',
  );
  @override
  late final GeneratedColumn<int> dcSerial = GeneratedColumn<int>(
    'dc_serial',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dcDiveNumberMeta = const VerificationMeta(
    'dcDiveNumber',
  );
  @override
  late final GeneratedColumn<int> dcDiveNumber = GeneratedColumn<int>(
    'dc_dive_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<int> startTime = GeneratedColumn<int>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<int> endTime = GeneratedColumn<int>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _utcOffsetMinutesMeta = const VerificationMeta(
    'utcOffsetMinutes',
  );
  @override
  late final GeneratedColumn<int> utcOffsetMinutes = GeneratedColumn<int>(
    'utc_offset_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxDepthMmMeta = const VerificationMeta(
    'maxDepthMm',
  );
  @override
  late final GeneratedColumn<int> maxDepthMm = GeneratedColumn<int>(
    'max_depth_mm',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _diveModeMeta = const VerificationMeta(
    'diveMode',
  );
  @override
  late final GeneratedColumn<int> diveMode = GeneratedColumn<int>(
    'dive_mode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decoModelMeta = const VerificationMeta(
    'decoModel',
  );
  @override
  late final GeneratedColumn<int> decoModel = GeneratedColumn<int>(
    'deco_model',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gfLowMeta = const VerificationMeta('gfLow');
  @override
  late final GeneratedColumn<int> gfLow = GeneratedColumn<int>(
    'gf_low',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gfHighMeta = const VerificationMeta('gfHigh');
  @override
  late final GeneratedColumn<int> gfHigh = GeneratedColumn<int>(
    'gf_high',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _atmosphericPressureMbarMeta =
      const VerificationMeta('atmosphericPressureMbar');
  @override
  late final GeneratedColumn<int> atmosphericPressureMbar =
      GeneratedColumn<int>(
        'atmospheric_pressure_mbar',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _waterDensityMeta = const VerificationMeta(
    'waterDensity',
  );
  @override
  late final GeneratedColumn<int> waterDensity = GeneratedColumn<int>(
    'water_density',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _logVersionMeta = const VerificationMeta(
    'logVersion',
  );
  @override
  late final GeneratedColumn<int> logVersion = GeneratedColumn<int>(
    'log_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dcModelMeta = const VerificationMeta(
    'dcModel',
  );
  @override
  late final GeneratedColumn<int> dcModel = GeneratedColumn<int>(
    'dc_model',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dcFirmwareMeta = const VerificationMeta(
    'dcFirmware',
  );
  @override
  late final GeneratedColumn<int> dcFirmware = GeneratedColumn<int>(
    'dc_firmware',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sampleIntervalMsMeta = const VerificationMeta(
    'sampleIntervalMs',
  );
  @override
  late final GeneratedColumn<int> sampleIntervalMs = GeneratedColumn<int>(
    'sample_interval_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gasMixesJsonMeta = const VerificationMeta(
    'gasMixesJson',
  );
  @override
  late final GeneratedColumn<String> gasMixesJson = GeneratedColumn<String>(
    'gas_mixes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tanksJsonMeta = const VerificationMeta(
    'tanksJson',
  );
  @override
  late final GeneratedColumn<String> tanksJson = GeneratedColumn<String>(
    'tanks_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sensorCalibrationJsonMeta =
      const VerificationMeta('sensorCalibrationJson');
  @override
  late final GeneratedColumn<String> sensorCalibrationJson =
      GeneratedColumn<String>(
        'sensor_calibration_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _configuredStackSecondsMeta =
      const VerificationMeta('configuredStackSeconds');
  @override
  late final GeneratedColumn<int> configuredStackSeconds = GeneratedColumn<int>(
    'configured_stack_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stackRemainingAtStartSecondsMeta =
      const VerificationMeta('stackRemainingAtStartSeconds');
  @override
  late final GeneratedColumn<int> stackRemainingAtStartSeconds =
      GeneratedColumn<int>(
        'stack_remaining_at_start_seconds',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _stackRemainingAtEndSecondsMeta =
      const VerificationMeta('stackRemainingAtEndSeconds');
  @override
  late final GeneratedColumn<int> stackRemainingAtEndSeconds =
      GeneratedColumn<int>(
        'stack_remaining_at_end_seconds',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rawBlobMeta = const VerificationMeta(
    'rawBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> rawBlob = GeneratedColumn<Uint8List>(
    'raw_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  @override
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subsurfaceUploadedAtMeta =
      const VerificationMeta('subsurfaceUploadedAt');
  @override
  late final GeneratedColumn<int> subsurfaceUploadedAt = GeneratedColumn<int>(
    'subsurface_uploaded_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dcSerial,
    dcDiveNumber,
    startTime,
    endTime,
    utcOffsetMinutes,
    durationSeconds,
    maxDepthMm,
    diveMode,
    decoModel,
    gfLow,
    gfHigh,
    atmosphericPressureMbar,
    waterDensity,
    logVersion,
    dcModel,
    dcFirmware,
    sampleIntervalMs,
    gasMixesJson,
    tanksJson,
    sensorCalibrationJson,
    configuredStackSeconds,
    stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds,
    rawBlob,
    parserVersion,
    importedAt,
    subsurfaceUploadedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dives';
  @override
  VerificationContext validateIntegrity(
    Insertable<Dive> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('dc_serial')) {
      context.handle(
        _dcSerialMeta,
        dcSerial.isAcceptableOrUnknown(data['dc_serial']!, _dcSerialMeta),
      );
    } else if (isInserting) {
      context.missing(_dcSerialMeta);
    }
    if (data.containsKey('dc_dive_number')) {
      context.handle(
        _dcDiveNumberMeta,
        dcDiveNumber.isAcceptableOrUnknown(
          data['dc_dive_number']!,
          _dcDiveNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dcDiveNumberMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('utc_offset_minutes')) {
      context.handle(
        _utcOffsetMinutesMeta,
        utcOffsetMinutes.isAcceptableOrUnknown(
          data['utc_offset_minutes']!,
          _utcOffsetMinutesMeta,
        ),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('max_depth_mm')) {
      context.handle(
        _maxDepthMmMeta,
        maxDepthMm.isAcceptableOrUnknown(
          data['max_depth_mm']!,
          _maxDepthMmMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_maxDepthMmMeta);
    }
    if (data.containsKey('dive_mode')) {
      context.handle(
        _diveModeMeta,
        diveMode.isAcceptableOrUnknown(data['dive_mode']!, _diveModeMeta),
      );
    } else if (isInserting) {
      context.missing(_diveModeMeta);
    }
    if (data.containsKey('deco_model')) {
      context.handle(
        _decoModelMeta,
        decoModel.isAcceptableOrUnknown(data['deco_model']!, _decoModelMeta),
      );
    } else if (isInserting) {
      context.missing(_decoModelMeta);
    }
    if (data.containsKey('gf_low')) {
      context.handle(
        _gfLowMeta,
        gfLow.isAcceptableOrUnknown(data['gf_low']!, _gfLowMeta),
      );
    }
    if (data.containsKey('gf_high')) {
      context.handle(
        _gfHighMeta,
        gfHigh.isAcceptableOrUnknown(data['gf_high']!, _gfHighMeta),
      );
    }
    if (data.containsKey('atmospheric_pressure_mbar')) {
      context.handle(
        _atmosphericPressureMbarMeta,
        atmosphericPressureMbar.isAcceptableOrUnknown(
          data['atmospheric_pressure_mbar']!,
          _atmosphericPressureMbarMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_atmosphericPressureMbarMeta);
    }
    if (data.containsKey('water_density')) {
      context.handle(
        _waterDensityMeta,
        waterDensity.isAcceptableOrUnknown(
          data['water_density']!,
          _waterDensityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_waterDensityMeta);
    }
    if (data.containsKey('log_version')) {
      context.handle(
        _logVersionMeta,
        logVersion.isAcceptableOrUnknown(data['log_version']!, _logVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_logVersionMeta);
    }
    if (data.containsKey('dc_model')) {
      context.handle(
        _dcModelMeta,
        dcModel.isAcceptableOrUnknown(data['dc_model']!, _dcModelMeta),
      );
    } else if (isInserting) {
      context.missing(_dcModelMeta);
    }
    if (data.containsKey('dc_firmware')) {
      context.handle(
        _dcFirmwareMeta,
        dcFirmware.isAcceptableOrUnknown(data['dc_firmware']!, _dcFirmwareMeta),
      );
    }
    if (data.containsKey('sample_interval_ms')) {
      context.handle(
        _sampleIntervalMsMeta,
        sampleIntervalMs.isAcceptableOrUnknown(
          data['sample_interval_ms']!,
          _sampleIntervalMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sampleIntervalMsMeta);
    }
    if (data.containsKey('gas_mixes_json')) {
      context.handle(
        _gasMixesJsonMeta,
        gasMixesJson.isAcceptableOrUnknown(
          data['gas_mixes_json']!,
          _gasMixesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_gasMixesJsonMeta);
    }
    if (data.containsKey('tanks_json')) {
      context.handle(
        _tanksJsonMeta,
        tanksJson.isAcceptableOrUnknown(data['tanks_json']!, _tanksJsonMeta),
      );
    }
    if (data.containsKey('sensor_calibration_json')) {
      context.handle(
        _sensorCalibrationJsonMeta,
        sensorCalibrationJson.isAcceptableOrUnknown(
          data['sensor_calibration_json']!,
          _sensorCalibrationJsonMeta,
        ),
      );
    }
    if (data.containsKey('configured_stack_seconds')) {
      context.handle(
        _configuredStackSecondsMeta,
        configuredStackSeconds.isAcceptableOrUnknown(
          data['configured_stack_seconds']!,
          _configuredStackSecondsMeta,
        ),
      );
    }
    if (data.containsKey('stack_remaining_at_start_seconds')) {
      context.handle(
        _stackRemainingAtStartSecondsMeta,
        stackRemainingAtStartSeconds.isAcceptableOrUnknown(
          data['stack_remaining_at_start_seconds']!,
          _stackRemainingAtStartSecondsMeta,
        ),
      );
    }
    if (data.containsKey('stack_remaining_at_end_seconds')) {
      context.handle(
        _stackRemainingAtEndSecondsMeta,
        stackRemainingAtEndSeconds.isAcceptableOrUnknown(
          data['stack_remaining_at_end_seconds']!,
          _stackRemainingAtEndSecondsMeta,
        ),
      );
    }
    if (data.containsKey('raw_blob')) {
      context.handle(
        _rawBlobMeta,
        rawBlob.isAcceptableOrUnknown(data['raw_blob']!, _rawBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_rawBlobMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('subsurface_uploaded_at')) {
      context.handle(
        _subsurfaceUploadedAtMeta,
        subsurfaceUploadedAt.isAcceptableOrUnknown(
          data['subsurface_uploaded_at']!,
          _subsurfaceUploadedAtMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Dive map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Dive(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      dcSerial: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dc_serial'],
      )!,
      dcDiveNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dc_dive_number'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time'],
      )!,
      utcOffsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}utc_offset_minutes'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      maxDepthMm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_depth_mm'],
      )!,
      diveMode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dive_mode'],
      )!,
      decoModel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deco_model'],
      )!,
      gfLow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gf_low'],
      ),
      gfHigh: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gf_high'],
      ),
      atmosphericPressureMbar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}atmospheric_pressure_mbar'],
      )!,
      waterDensity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}water_density'],
      )!,
      logVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}log_version'],
      )!,
      dcModel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dc_model'],
      )!,
      dcFirmware: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dc_firmware'],
      ),
      sampleIntervalMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_interval_ms'],
      )!,
      gasMixesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gas_mixes_json'],
      )!,
      tanksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tanks_json'],
      ),
      sensorCalibrationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sensor_calibration_json'],
      ),
      configuredStackSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}configured_stack_seconds'],
      ),
      stackRemainingAtStartSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stack_remaining_at_start_seconds'],
      ),
      stackRemainingAtEndSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stack_remaining_at_end_seconds'],
      ),
      rawBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}raw_blob'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at'],
      )!,
      subsurfaceUploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subsurface_uploaded_at'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $DivesTable createAlias(String alias) {
    return $DivesTable(attachedDatabase, alias);
  }
}

class Dive extends DataClass implements Insertable<Dive> {
  /// Stable ID: hash(serial, diveNumber, startTimestamp).
  final String id;
  final int dcSerial;
  final int dcDiveNumber;

  /// Unix timestamp (seconds UTC).
  final int startTime;
  final int endTime;
  final int? utcOffsetMinutes;

  /// Duration in seconds.
  final int durationSeconds;

  /// Max depth in millimeters (integer precision, always metric).
  final int maxDepthMm;

  /// Dive mode code (DiveMode.value).
  final int diveMode;

  /// Deco model code (DecoModel.value).
  final int decoModel;
  final int? gfLow;
  final int? gfHigh;
  final int atmosphericPressureMbar;
  final int waterDensity;
  final int logVersion;

  /// ShearwaterModel index.
  final int dcModel;
  final int? dcFirmware;
  final int sampleIntervalMs;

  /// Gas mixes as JSON array.
  final String gasMixesJson;

  /// Tanks as JSON array. Null when the parser produced no tank metadata
  /// (no AI configured, OC dives without tank pressure, etc).
  final String? tanksJson;

  /// Per-cell calibration factors as a JSON array of doubles. Length 3
  /// on CCR; null on OC (or older imports made before the column existed).
  /// Used to derive per-cell PPO2 from raw mV at display/export time:
  /// `ppo2_bar = mV * cal / 1000`. The Petrel factory default is 0.021.
  final String? sensorCalibrationJson;

  /// Scrubber stack time (seconds). All null when the diver hasn't
  /// enabled stack tracking on the unit.
  final int? configuredStackSeconds;
  final int? stackRemainingAtStartSeconds;
  final int? stackRemainingAtEndSeconds;

  /// Original decompressed binary blob (for re-parsing).
  final Uint8List rawBlob;

  /// Parser version that produced the cached parse.
  final int parserVersion;

  /// When this dive was imported.
  final int importedAt;

  /// When this dive was last exported to a Subsurface .ssrf file
  /// (unix seconds). Null = pending.
  final int? subsurfaceUploadedAt;

  /// Soft-delete timestamp (millis since epoch). Null = visible.
  /// User-driven via the dive list; restore via the SnackBar undo.
  /// Imported data is otherwise immutable, so we keep the row + raw blob
  /// — re-importing the same dive id finds the soft-deleted row and
  /// resurrects it instead of inserting a duplicate.
  final int? deletedAt;
  const Dive({
    required this.id,
    required this.dcSerial,
    required this.dcDiveNumber,
    required this.startTime,
    required this.endTime,
    this.utcOffsetMinutes,
    required this.durationSeconds,
    required this.maxDepthMm,
    required this.diveMode,
    required this.decoModel,
    this.gfLow,
    this.gfHigh,
    required this.atmosphericPressureMbar,
    required this.waterDensity,
    required this.logVersion,
    required this.dcModel,
    this.dcFirmware,
    required this.sampleIntervalMs,
    required this.gasMixesJson,
    this.tanksJson,
    this.sensorCalibrationJson,
    this.configuredStackSeconds,
    this.stackRemainingAtStartSeconds,
    this.stackRemainingAtEndSeconds,
    required this.rawBlob,
    required this.parserVersion,
    required this.importedAt,
    this.subsurfaceUploadedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['dc_serial'] = Variable<int>(dcSerial);
    map['dc_dive_number'] = Variable<int>(dcDiveNumber);
    map['start_time'] = Variable<int>(startTime);
    map['end_time'] = Variable<int>(endTime);
    if (!nullToAbsent || utcOffsetMinutes != null) {
      map['utc_offset_minutes'] = Variable<int>(utcOffsetMinutes);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['max_depth_mm'] = Variable<int>(maxDepthMm);
    map['dive_mode'] = Variable<int>(diveMode);
    map['deco_model'] = Variable<int>(decoModel);
    if (!nullToAbsent || gfLow != null) {
      map['gf_low'] = Variable<int>(gfLow);
    }
    if (!nullToAbsent || gfHigh != null) {
      map['gf_high'] = Variable<int>(gfHigh);
    }
    map['atmospheric_pressure_mbar'] = Variable<int>(atmosphericPressureMbar);
    map['water_density'] = Variable<int>(waterDensity);
    map['log_version'] = Variable<int>(logVersion);
    map['dc_model'] = Variable<int>(dcModel);
    if (!nullToAbsent || dcFirmware != null) {
      map['dc_firmware'] = Variable<int>(dcFirmware);
    }
    map['sample_interval_ms'] = Variable<int>(sampleIntervalMs);
    map['gas_mixes_json'] = Variable<String>(gasMixesJson);
    if (!nullToAbsent || tanksJson != null) {
      map['tanks_json'] = Variable<String>(tanksJson);
    }
    if (!nullToAbsent || sensorCalibrationJson != null) {
      map['sensor_calibration_json'] = Variable<String>(sensorCalibrationJson);
    }
    if (!nullToAbsent || configuredStackSeconds != null) {
      map['configured_stack_seconds'] = Variable<int>(configuredStackSeconds);
    }
    if (!nullToAbsent || stackRemainingAtStartSeconds != null) {
      map['stack_remaining_at_start_seconds'] = Variable<int>(
        stackRemainingAtStartSeconds,
      );
    }
    if (!nullToAbsent || stackRemainingAtEndSeconds != null) {
      map['stack_remaining_at_end_seconds'] = Variable<int>(
        stackRemainingAtEndSeconds,
      );
    }
    map['raw_blob'] = Variable<Uint8List>(rawBlob);
    map['parser_version'] = Variable<int>(parserVersion);
    map['imported_at'] = Variable<int>(importedAt);
    if (!nullToAbsent || subsurfaceUploadedAt != null) {
      map['subsurface_uploaded_at'] = Variable<int>(subsurfaceUploadedAt);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  DivesCompanion toCompanion(bool nullToAbsent) {
    return DivesCompanion(
      id: Value(id),
      dcSerial: Value(dcSerial),
      dcDiveNumber: Value(dcDiveNumber),
      startTime: Value(startTime),
      endTime: Value(endTime),
      utcOffsetMinutes: utcOffsetMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(utcOffsetMinutes),
      durationSeconds: Value(durationSeconds),
      maxDepthMm: Value(maxDepthMm),
      diveMode: Value(diveMode),
      decoModel: Value(decoModel),
      gfLow: gfLow == null && nullToAbsent
          ? const Value.absent()
          : Value(gfLow),
      gfHigh: gfHigh == null && nullToAbsent
          ? const Value.absent()
          : Value(gfHigh),
      atmosphericPressureMbar: Value(atmosphericPressureMbar),
      waterDensity: Value(waterDensity),
      logVersion: Value(logVersion),
      dcModel: Value(dcModel),
      dcFirmware: dcFirmware == null && nullToAbsent
          ? const Value.absent()
          : Value(dcFirmware),
      sampleIntervalMs: Value(sampleIntervalMs),
      gasMixesJson: Value(gasMixesJson),
      tanksJson: tanksJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tanksJson),
      sensorCalibrationJson: sensorCalibrationJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sensorCalibrationJson),
      configuredStackSeconds: configuredStackSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(configuredStackSeconds),
      stackRemainingAtStartSeconds:
          stackRemainingAtStartSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(stackRemainingAtStartSeconds),
      stackRemainingAtEndSeconds:
          stackRemainingAtEndSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(stackRemainingAtEndSeconds),
      rawBlob: Value(rawBlob),
      parserVersion: Value(parserVersion),
      importedAt: Value(importedAt),
      subsurfaceUploadedAt: subsurfaceUploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(subsurfaceUploadedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Dive.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Dive(
      id: serializer.fromJson<String>(json['id']),
      dcSerial: serializer.fromJson<int>(json['dcSerial']),
      dcDiveNumber: serializer.fromJson<int>(json['dcDiveNumber']),
      startTime: serializer.fromJson<int>(json['startTime']),
      endTime: serializer.fromJson<int>(json['endTime']),
      utcOffsetMinutes: serializer.fromJson<int?>(json['utcOffsetMinutes']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      maxDepthMm: serializer.fromJson<int>(json['maxDepthMm']),
      diveMode: serializer.fromJson<int>(json['diveMode']),
      decoModel: serializer.fromJson<int>(json['decoModel']),
      gfLow: serializer.fromJson<int?>(json['gfLow']),
      gfHigh: serializer.fromJson<int?>(json['gfHigh']),
      atmosphericPressureMbar: serializer.fromJson<int>(
        json['atmosphericPressureMbar'],
      ),
      waterDensity: serializer.fromJson<int>(json['waterDensity']),
      logVersion: serializer.fromJson<int>(json['logVersion']),
      dcModel: serializer.fromJson<int>(json['dcModel']),
      dcFirmware: serializer.fromJson<int?>(json['dcFirmware']),
      sampleIntervalMs: serializer.fromJson<int>(json['sampleIntervalMs']),
      gasMixesJson: serializer.fromJson<String>(json['gasMixesJson']),
      tanksJson: serializer.fromJson<String?>(json['tanksJson']),
      sensorCalibrationJson: serializer.fromJson<String?>(
        json['sensorCalibrationJson'],
      ),
      configuredStackSeconds: serializer.fromJson<int?>(
        json['configuredStackSeconds'],
      ),
      stackRemainingAtStartSeconds: serializer.fromJson<int?>(
        json['stackRemainingAtStartSeconds'],
      ),
      stackRemainingAtEndSeconds: serializer.fromJson<int?>(
        json['stackRemainingAtEndSeconds'],
      ),
      rawBlob: serializer.fromJson<Uint8List>(json['rawBlob']),
      parserVersion: serializer.fromJson<int>(json['parserVersion']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
      subsurfaceUploadedAt: serializer.fromJson<int?>(
        json['subsurfaceUploadedAt'],
      ),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dcSerial': serializer.toJson<int>(dcSerial),
      'dcDiveNumber': serializer.toJson<int>(dcDiveNumber),
      'startTime': serializer.toJson<int>(startTime),
      'endTime': serializer.toJson<int>(endTime),
      'utcOffsetMinutes': serializer.toJson<int?>(utcOffsetMinutes),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'maxDepthMm': serializer.toJson<int>(maxDepthMm),
      'diveMode': serializer.toJson<int>(diveMode),
      'decoModel': serializer.toJson<int>(decoModel),
      'gfLow': serializer.toJson<int?>(gfLow),
      'gfHigh': serializer.toJson<int?>(gfHigh),
      'atmosphericPressureMbar': serializer.toJson<int>(
        atmosphericPressureMbar,
      ),
      'waterDensity': serializer.toJson<int>(waterDensity),
      'logVersion': serializer.toJson<int>(logVersion),
      'dcModel': serializer.toJson<int>(dcModel),
      'dcFirmware': serializer.toJson<int?>(dcFirmware),
      'sampleIntervalMs': serializer.toJson<int>(sampleIntervalMs),
      'gasMixesJson': serializer.toJson<String>(gasMixesJson),
      'tanksJson': serializer.toJson<String?>(tanksJson),
      'sensorCalibrationJson': serializer.toJson<String?>(
        sensorCalibrationJson,
      ),
      'configuredStackSeconds': serializer.toJson<int?>(configuredStackSeconds),
      'stackRemainingAtStartSeconds': serializer.toJson<int?>(
        stackRemainingAtStartSeconds,
      ),
      'stackRemainingAtEndSeconds': serializer.toJson<int?>(
        stackRemainingAtEndSeconds,
      ),
      'rawBlob': serializer.toJson<Uint8List>(rawBlob),
      'parserVersion': serializer.toJson<int>(parserVersion),
      'importedAt': serializer.toJson<int>(importedAt),
      'subsurfaceUploadedAt': serializer.toJson<int?>(subsurfaceUploadedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  Dive copyWith({
    String? id,
    int? dcSerial,
    int? dcDiveNumber,
    int? startTime,
    int? endTime,
    Value<int?> utcOffsetMinutes = const Value.absent(),
    int? durationSeconds,
    int? maxDepthMm,
    int? diveMode,
    int? decoModel,
    Value<int?> gfLow = const Value.absent(),
    Value<int?> gfHigh = const Value.absent(),
    int? atmosphericPressureMbar,
    int? waterDensity,
    int? logVersion,
    int? dcModel,
    Value<int?> dcFirmware = const Value.absent(),
    int? sampleIntervalMs,
    String? gasMixesJson,
    Value<String?> tanksJson = const Value.absent(),
    Value<String?> sensorCalibrationJson = const Value.absent(),
    Value<int?> configuredStackSeconds = const Value.absent(),
    Value<int?> stackRemainingAtStartSeconds = const Value.absent(),
    Value<int?> stackRemainingAtEndSeconds = const Value.absent(),
    Uint8List? rawBlob,
    int? parserVersion,
    int? importedAt,
    Value<int?> subsurfaceUploadedAt = const Value.absent(),
    Value<int?> deletedAt = const Value.absent(),
  }) => Dive(
    id: id ?? this.id,
    dcSerial: dcSerial ?? this.dcSerial,
    dcDiveNumber: dcDiveNumber ?? this.dcDiveNumber,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    utcOffsetMinutes: utcOffsetMinutes.present
        ? utcOffsetMinutes.value
        : this.utcOffsetMinutes,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    maxDepthMm: maxDepthMm ?? this.maxDepthMm,
    diveMode: diveMode ?? this.diveMode,
    decoModel: decoModel ?? this.decoModel,
    gfLow: gfLow.present ? gfLow.value : this.gfLow,
    gfHigh: gfHigh.present ? gfHigh.value : this.gfHigh,
    atmosphericPressureMbar:
        atmosphericPressureMbar ?? this.atmosphericPressureMbar,
    waterDensity: waterDensity ?? this.waterDensity,
    logVersion: logVersion ?? this.logVersion,
    dcModel: dcModel ?? this.dcModel,
    dcFirmware: dcFirmware.present ? dcFirmware.value : this.dcFirmware,
    sampleIntervalMs: sampleIntervalMs ?? this.sampleIntervalMs,
    gasMixesJson: gasMixesJson ?? this.gasMixesJson,
    tanksJson: tanksJson.present ? tanksJson.value : this.tanksJson,
    sensorCalibrationJson: sensorCalibrationJson.present
        ? sensorCalibrationJson.value
        : this.sensorCalibrationJson,
    configuredStackSeconds: configuredStackSeconds.present
        ? configuredStackSeconds.value
        : this.configuredStackSeconds,
    stackRemainingAtStartSeconds: stackRemainingAtStartSeconds.present
        ? stackRemainingAtStartSeconds.value
        : this.stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: stackRemainingAtEndSeconds.present
        ? stackRemainingAtEndSeconds.value
        : this.stackRemainingAtEndSeconds,
    rawBlob: rawBlob ?? this.rawBlob,
    parserVersion: parserVersion ?? this.parserVersion,
    importedAt: importedAt ?? this.importedAt,
    subsurfaceUploadedAt: subsurfaceUploadedAt.present
        ? subsurfaceUploadedAt.value
        : this.subsurfaceUploadedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Dive copyWithCompanion(DivesCompanion data) {
    return Dive(
      id: data.id.present ? data.id.value : this.id,
      dcSerial: data.dcSerial.present ? data.dcSerial.value : this.dcSerial,
      dcDiveNumber: data.dcDiveNumber.present
          ? data.dcDiveNumber.value
          : this.dcDiveNumber,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      utcOffsetMinutes: data.utcOffsetMinutes.present
          ? data.utcOffsetMinutes.value
          : this.utcOffsetMinutes,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      maxDepthMm: data.maxDepthMm.present
          ? data.maxDepthMm.value
          : this.maxDepthMm,
      diveMode: data.diveMode.present ? data.diveMode.value : this.diveMode,
      decoModel: data.decoModel.present ? data.decoModel.value : this.decoModel,
      gfLow: data.gfLow.present ? data.gfLow.value : this.gfLow,
      gfHigh: data.gfHigh.present ? data.gfHigh.value : this.gfHigh,
      atmosphericPressureMbar: data.atmosphericPressureMbar.present
          ? data.atmosphericPressureMbar.value
          : this.atmosphericPressureMbar,
      waterDensity: data.waterDensity.present
          ? data.waterDensity.value
          : this.waterDensity,
      logVersion: data.logVersion.present
          ? data.logVersion.value
          : this.logVersion,
      dcModel: data.dcModel.present ? data.dcModel.value : this.dcModel,
      dcFirmware: data.dcFirmware.present
          ? data.dcFirmware.value
          : this.dcFirmware,
      sampleIntervalMs: data.sampleIntervalMs.present
          ? data.sampleIntervalMs.value
          : this.sampleIntervalMs,
      gasMixesJson: data.gasMixesJson.present
          ? data.gasMixesJson.value
          : this.gasMixesJson,
      tanksJson: data.tanksJson.present ? data.tanksJson.value : this.tanksJson,
      sensorCalibrationJson: data.sensorCalibrationJson.present
          ? data.sensorCalibrationJson.value
          : this.sensorCalibrationJson,
      configuredStackSeconds: data.configuredStackSeconds.present
          ? data.configuredStackSeconds.value
          : this.configuredStackSeconds,
      stackRemainingAtStartSeconds: data.stackRemainingAtStartSeconds.present
          ? data.stackRemainingAtStartSeconds.value
          : this.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: data.stackRemainingAtEndSeconds.present
          ? data.stackRemainingAtEndSeconds.value
          : this.stackRemainingAtEndSeconds,
      rawBlob: data.rawBlob.present ? data.rawBlob.value : this.rawBlob,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      subsurfaceUploadedAt: data.subsurfaceUploadedAt.present
          ? data.subsurfaceUploadedAt.value
          : this.subsurfaceUploadedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Dive(')
          ..write('id: $id, ')
          ..write('dcSerial: $dcSerial, ')
          ..write('dcDiveNumber: $dcDiveNumber, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('utcOffsetMinutes: $utcOffsetMinutes, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('maxDepthMm: $maxDepthMm, ')
          ..write('diveMode: $diveMode, ')
          ..write('decoModel: $decoModel, ')
          ..write('gfLow: $gfLow, ')
          ..write('gfHigh: $gfHigh, ')
          ..write('atmosphericPressureMbar: $atmosphericPressureMbar, ')
          ..write('waterDensity: $waterDensity, ')
          ..write('logVersion: $logVersion, ')
          ..write('dcModel: $dcModel, ')
          ..write('dcFirmware: $dcFirmware, ')
          ..write('sampleIntervalMs: $sampleIntervalMs, ')
          ..write('gasMixesJson: $gasMixesJson, ')
          ..write('tanksJson: $tanksJson, ')
          ..write('sensorCalibrationJson: $sensorCalibrationJson, ')
          ..write('configuredStackSeconds: $configuredStackSeconds, ')
          ..write(
            'stackRemainingAtStartSeconds: $stackRemainingAtStartSeconds, ',
          )
          ..write('stackRemainingAtEndSeconds: $stackRemainingAtEndSeconds, ')
          ..write('rawBlob: $rawBlob, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('subsurfaceUploadedAt: $subsurfaceUploadedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    dcSerial,
    dcDiveNumber,
    startTime,
    endTime,
    utcOffsetMinutes,
    durationSeconds,
    maxDepthMm,
    diveMode,
    decoModel,
    gfLow,
    gfHigh,
    atmosphericPressureMbar,
    waterDensity,
    logVersion,
    dcModel,
    dcFirmware,
    sampleIntervalMs,
    gasMixesJson,
    tanksJson,
    sensorCalibrationJson,
    configuredStackSeconds,
    stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds,
    $driftBlobEquality.hash(rawBlob),
    parserVersion,
    importedAt,
    subsurfaceUploadedAt,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Dive &&
          other.id == this.id &&
          other.dcSerial == this.dcSerial &&
          other.dcDiveNumber == this.dcDiveNumber &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.utcOffsetMinutes == this.utcOffsetMinutes &&
          other.durationSeconds == this.durationSeconds &&
          other.maxDepthMm == this.maxDepthMm &&
          other.diveMode == this.diveMode &&
          other.decoModel == this.decoModel &&
          other.gfLow == this.gfLow &&
          other.gfHigh == this.gfHigh &&
          other.atmosphericPressureMbar == this.atmosphericPressureMbar &&
          other.waterDensity == this.waterDensity &&
          other.logVersion == this.logVersion &&
          other.dcModel == this.dcModel &&
          other.dcFirmware == this.dcFirmware &&
          other.sampleIntervalMs == this.sampleIntervalMs &&
          other.gasMixesJson == this.gasMixesJson &&
          other.tanksJson == this.tanksJson &&
          other.sensorCalibrationJson == this.sensorCalibrationJson &&
          other.configuredStackSeconds == this.configuredStackSeconds &&
          other.stackRemainingAtStartSeconds ==
              this.stackRemainingAtStartSeconds &&
          other.stackRemainingAtEndSeconds == this.stackRemainingAtEndSeconds &&
          $driftBlobEquality.equals(other.rawBlob, this.rawBlob) &&
          other.parserVersion == this.parserVersion &&
          other.importedAt == this.importedAt &&
          other.subsurfaceUploadedAt == this.subsurfaceUploadedAt &&
          other.deletedAt == this.deletedAt);
}

class DivesCompanion extends UpdateCompanion<Dive> {
  final Value<String> id;
  final Value<int> dcSerial;
  final Value<int> dcDiveNumber;
  final Value<int> startTime;
  final Value<int> endTime;
  final Value<int?> utcOffsetMinutes;
  final Value<int> durationSeconds;
  final Value<int> maxDepthMm;
  final Value<int> diveMode;
  final Value<int> decoModel;
  final Value<int?> gfLow;
  final Value<int?> gfHigh;
  final Value<int> atmosphericPressureMbar;
  final Value<int> waterDensity;
  final Value<int> logVersion;
  final Value<int> dcModel;
  final Value<int?> dcFirmware;
  final Value<int> sampleIntervalMs;
  final Value<String> gasMixesJson;
  final Value<String?> tanksJson;
  final Value<String?> sensorCalibrationJson;
  final Value<int?> configuredStackSeconds;
  final Value<int?> stackRemainingAtStartSeconds;
  final Value<int?> stackRemainingAtEndSeconds;
  final Value<Uint8List> rawBlob;
  final Value<int> parserVersion;
  final Value<int> importedAt;
  final Value<int?> subsurfaceUploadedAt;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const DivesCompanion({
    this.id = const Value.absent(),
    this.dcSerial = const Value.absent(),
    this.dcDiveNumber = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.utcOffsetMinutes = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.maxDepthMm = const Value.absent(),
    this.diveMode = const Value.absent(),
    this.decoModel = const Value.absent(),
    this.gfLow = const Value.absent(),
    this.gfHigh = const Value.absent(),
    this.atmosphericPressureMbar = const Value.absent(),
    this.waterDensity = const Value.absent(),
    this.logVersion = const Value.absent(),
    this.dcModel = const Value.absent(),
    this.dcFirmware = const Value.absent(),
    this.sampleIntervalMs = const Value.absent(),
    this.gasMixesJson = const Value.absent(),
    this.tanksJson = const Value.absent(),
    this.sensorCalibrationJson = const Value.absent(),
    this.configuredStackSeconds = const Value.absent(),
    this.stackRemainingAtStartSeconds = const Value.absent(),
    this.stackRemainingAtEndSeconds = const Value.absent(),
    this.rawBlob = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.subsurfaceUploadedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DivesCompanion.insert({
    required String id,
    required int dcSerial,
    required int dcDiveNumber,
    required int startTime,
    required int endTime,
    this.utcOffsetMinutes = const Value.absent(),
    required int durationSeconds,
    required int maxDepthMm,
    required int diveMode,
    required int decoModel,
    this.gfLow = const Value.absent(),
    this.gfHigh = const Value.absent(),
    required int atmosphericPressureMbar,
    required int waterDensity,
    required int logVersion,
    required int dcModel,
    this.dcFirmware = const Value.absent(),
    required int sampleIntervalMs,
    required String gasMixesJson,
    this.tanksJson = const Value.absent(),
    this.sensorCalibrationJson = const Value.absent(),
    this.configuredStackSeconds = const Value.absent(),
    this.stackRemainingAtStartSeconds = const Value.absent(),
    this.stackRemainingAtEndSeconds = const Value.absent(),
    required Uint8List rawBlob,
    required int parserVersion,
    required int importedAt,
    this.subsurfaceUploadedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dcSerial = Value(dcSerial),
       dcDiveNumber = Value(dcDiveNumber),
       startTime = Value(startTime),
       endTime = Value(endTime),
       durationSeconds = Value(durationSeconds),
       maxDepthMm = Value(maxDepthMm),
       diveMode = Value(diveMode),
       decoModel = Value(decoModel),
       atmosphericPressureMbar = Value(atmosphericPressureMbar),
       waterDensity = Value(waterDensity),
       logVersion = Value(logVersion),
       dcModel = Value(dcModel),
       sampleIntervalMs = Value(sampleIntervalMs),
       gasMixesJson = Value(gasMixesJson),
       rawBlob = Value(rawBlob),
       parserVersion = Value(parserVersion),
       importedAt = Value(importedAt);
  static Insertable<Dive> custom({
    Expression<String>? id,
    Expression<int>? dcSerial,
    Expression<int>? dcDiveNumber,
    Expression<int>? startTime,
    Expression<int>? endTime,
    Expression<int>? utcOffsetMinutes,
    Expression<int>? durationSeconds,
    Expression<int>? maxDepthMm,
    Expression<int>? diveMode,
    Expression<int>? decoModel,
    Expression<int>? gfLow,
    Expression<int>? gfHigh,
    Expression<int>? atmosphericPressureMbar,
    Expression<int>? waterDensity,
    Expression<int>? logVersion,
    Expression<int>? dcModel,
    Expression<int>? dcFirmware,
    Expression<int>? sampleIntervalMs,
    Expression<String>? gasMixesJson,
    Expression<String>? tanksJson,
    Expression<String>? sensorCalibrationJson,
    Expression<int>? configuredStackSeconds,
    Expression<int>? stackRemainingAtStartSeconds,
    Expression<int>? stackRemainingAtEndSeconds,
    Expression<Uint8List>? rawBlob,
    Expression<int>? parserVersion,
    Expression<int>? importedAt,
    Expression<int>? subsurfaceUploadedAt,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dcSerial != null) 'dc_serial': dcSerial,
      if (dcDiveNumber != null) 'dc_dive_number': dcDiveNumber,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (utcOffsetMinutes != null) 'utc_offset_minutes': utcOffsetMinutes,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (maxDepthMm != null) 'max_depth_mm': maxDepthMm,
      if (diveMode != null) 'dive_mode': diveMode,
      if (decoModel != null) 'deco_model': decoModel,
      if (gfLow != null) 'gf_low': gfLow,
      if (gfHigh != null) 'gf_high': gfHigh,
      if (atmosphericPressureMbar != null)
        'atmospheric_pressure_mbar': atmosphericPressureMbar,
      if (waterDensity != null) 'water_density': waterDensity,
      if (logVersion != null) 'log_version': logVersion,
      if (dcModel != null) 'dc_model': dcModel,
      if (dcFirmware != null) 'dc_firmware': dcFirmware,
      if (sampleIntervalMs != null) 'sample_interval_ms': sampleIntervalMs,
      if (gasMixesJson != null) 'gas_mixes_json': gasMixesJson,
      if (tanksJson != null) 'tanks_json': tanksJson,
      if (sensorCalibrationJson != null)
        'sensor_calibration_json': sensorCalibrationJson,
      if (configuredStackSeconds != null)
        'configured_stack_seconds': configuredStackSeconds,
      if (stackRemainingAtStartSeconds != null)
        'stack_remaining_at_start_seconds': stackRemainingAtStartSeconds,
      if (stackRemainingAtEndSeconds != null)
        'stack_remaining_at_end_seconds': stackRemainingAtEndSeconds,
      if (rawBlob != null) 'raw_blob': rawBlob,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (importedAt != null) 'imported_at': importedAt,
      if (subsurfaceUploadedAt != null)
        'subsurface_uploaded_at': subsurfaceUploadedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DivesCompanion copyWith({
    Value<String>? id,
    Value<int>? dcSerial,
    Value<int>? dcDiveNumber,
    Value<int>? startTime,
    Value<int>? endTime,
    Value<int?>? utcOffsetMinutes,
    Value<int>? durationSeconds,
    Value<int>? maxDepthMm,
    Value<int>? diveMode,
    Value<int>? decoModel,
    Value<int?>? gfLow,
    Value<int?>? gfHigh,
    Value<int>? atmosphericPressureMbar,
    Value<int>? waterDensity,
    Value<int>? logVersion,
    Value<int>? dcModel,
    Value<int?>? dcFirmware,
    Value<int>? sampleIntervalMs,
    Value<String>? gasMixesJson,
    Value<String?>? tanksJson,
    Value<String?>? sensorCalibrationJson,
    Value<int?>? configuredStackSeconds,
    Value<int?>? stackRemainingAtStartSeconds,
    Value<int?>? stackRemainingAtEndSeconds,
    Value<Uint8List>? rawBlob,
    Value<int>? parserVersion,
    Value<int>? importedAt,
    Value<int?>? subsurfaceUploadedAt,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return DivesCompanion(
      id: id ?? this.id,
      dcSerial: dcSerial ?? this.dcSerial,
      dcDiveNumber: dcDiveNumber ?? this.dcDiveNumber,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      maxDepthMm: maxDepthMm ?? this.maxDepthMm,
      diveMode: diveMode ?? this.diveMode,
      decoModel: decoModel ?? this.decoModel,
      gfLow: gfLow ?? this.gfLow,
      gfHigh: gfHigh ?? this.gfHigh,
      atmosphericPressureMbar:
          atmosphericPressureMbar ?? this.atmosphericPressureMbar,
      waterDensity: waterDensity ?? this.waterDensity,
      logVersion: logVersion ?? this.logVersion,
      dcModel: dcModel ?? this.dcModel,
      dcFirmware: dcFirmware ?? this.dcFirmware,
      sampleIntervalMs: sampleIntervalMs ?? this.sampleIntervalMs,
      gasMixesJson: gasMixesJson ?? this.gasMixesJson,
      tanksJson: tanksJson ?? this.tanksJson,
      sensorCalibrationJson:
          sensorCalibrationJson ?? this.sensorCalibrationJson,
      configuredStackSeconds:
          configuredStackSeconds ?? this.configuredStackSeconds,
      stackRemainingAtStartSeconds:
          stackRemainingAtStartSeconds ?? this.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds:
          stackRemainingAtEndSeconds ?? this.stackRemainingAtEndSeconds,
      rawBlob: rawBlob ?? this.rawBlob,
      parserVersion: parserVersion ?? this.parserVersion,
      importedAt: importedAt ?? this.importedAt,
      subsurfaceUploadedAt: subsurfaceUploadedAt ?? this.subsurfaceUploadedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dcSerial.present) {
      map['dc_serial'] = Variable<int>(dcSerial.value);
    }
    if (dcDiveNumber.present) {
      map['dc_dive_number'] = Variable<int>(dcDiveNumber.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<int>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<int>(endTime.value);
    }
    if (utcOffsetMinutes.present) {
      map['utc_offset_minutes'] = Variable<int>(utcOffsetMinutes.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (maxDepthMm.present) {
      map['max_depth_mm'] = Variable<int>(maxDepthMm.value);
    }
    if (diveMode.present) {
      map['dive_mode'] = Variable<int>(diveMode.value);
    }
    if (decoModel.present) {
      map['deco_model'] = Variable<int>(decoModel.value);
    }
    if (gfLow.present) {
      map['gf_low'] = Variable<int>(gfLow.value);
    }
    if (gfHigh.present) {
      map['gf_high'] = Variable<int>(gfHigh.value);
    }
    if (atmosphericPressureMbar.present) {
      map['atmospheric_pressure_mbar'] = Variable<int>(
        atmosphericPressureMbar.value,
      );
    }
    if (waterDensity.present) {
      map['water_density'] = Variable<int>(waterDensity.value);
    }
    if (logVersion.present) {
      map['log_version'] = Variable<int>(logVersion.value);
    }
    if (dcModel.present) {
      map['dc_model'] = Variable<int>(dcModel.value);
    }
    if (dcFirmware.present) {
      map['dc_firmware'] = Variable<int>(dcFirmware.value);
    }
    if (sampleIntervalMs.present) {
      map['sample_interval_ms'] = Variable<int>(sampleIntervalMs.value);
    }
    if (gasMixesJson.present) {
      map['gas_mixes_json'] = Variable<String>(gasMixesJson.value);
    }
    if (tanksJson.present) {
      map['tanks_json'] = Variable<String>(tanksJson.value);
    }
    if (sensorCalibrationJson.present) {
      map['sensor_calibration_json'] = Variable<String>(
        sensorCalibrationJson.value,
      );
    }
    if (configuredStackSeconds.present) {
      map['configured_stack_seconds'] = Variable<int>(
        configuredStackSeconds.value,
      );
    }
    if (stackRemainingAtStartSeconds.present) {
      map['stack_remaining_at_start_seconds'] = Variable<int>(
        stackRemainingAtStartSeconds.value,
      );
    }
    if (stackRemainingAtEndSeconds.present) {
      map['stack_remaining_at_end_seconds'] = Variable<int>(
        stackRemainingAtEndSeconds.value,
      );
    }
    if (rawBlob.present) {
      map['raw_blob'] = Variable<Uint8List>(rawBlob.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (subsurfaceUploadedAt.present) {
      map['subsurface_uploaded_at'] = Variable<int>(subsurfaceUploadedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DivesCompanion(')
          ..write('id: $id, ')
          ..write('dcSerial: $dcSerial, ')
          ..write('dcDiveNumber: $dcDiveNumber, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('utcOffsetMinutes: $utcOffsetMinutes, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('maxDepthMm: $maxDepthMm, ')
          ..write('diveMode: $diveMode, ')
          ..write('decoModel: $decoModel, ')
          ..write('gfLow: $gfLow, ')
          ..write('gfHigh: $gfHigh, ')
          ..write('atmosphericPressureMbar: $atmosphericPressureMbar, ')
          ..write('waterDensity: $waterDensity, ')
          ..write('logVersion: $logVersion, ')
          ..write('dcModel: $dcModel, ')
          ..write('dcFirmware: $dcFirmware, ')
          ..write('sampleIntervalMs: $sampleIntervalMs, ')
          ..write('gasMixesJson: $gasMixesJson, ')
          ..write('tanksJson: $tanksJson, ')
          ..write('sensorCalibrationJson: $sensorCalibrationJson, ')
          ..write('configuredStackSeconds: $configuredStackSeconds, ')
          ..write(
            'stackRemainingAtStartSeconds: $stackRemainingAtStartSeconds, ',
          )
          ..write('stackRemainingAtEndSeconds: $stackRemainingAtEndSeconds, ')
          ..write('rawBlob: $rawBlob, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('subsurfaceUploadedAt: $subsurfaceUploadedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveSamplesTable extends DiveSamples
    with TableInfo<$DiveSamplesTable, DiveSample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dives (id)',
    ),
  );
  static const VerificationMeta _sampleCountMeta = const VerificationMeta(
    'sampleCount',
  );
  @override
  late final GeneratedColumn<int> sampleCount = GeneratedColumn<int>(
    'sample_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _depthBlobMeta = const VerificationMeta(
    'depthBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> depthBlob = GeneratedColumn<Uint8List>(
    'depth_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _temperatureBlobMeta = const VerificationMeta(
    'temperatureBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> temperatureBlob =
      GeneratedColumn<Uint8List>(
        'temperature_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _ppo2BlobMeta = const VerificationMeta(
    'ppo2Blob',
  );
  @override
  late final GeneratedColumn<Uint8List> ppo2Blob = GeneratedColumn<Uint8List>(
    'ppo2_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cellMv0BlobMeta = const VerificationMeta(
    'cellMv0Blob',
  );
  @override
  late final GeneratedColumn<Uint8List> cellMv0Blob =
      GeneratedColumn<Uint8List>(
        'cell_mv0_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cellMv1BlobMeta = const VerificationMeta(
    'cellMv1Blob',
  );
  @override
  late final GeneratedColumn<Uint8List> cellMv1Blob =
      GeneratedColumn<Uint8List>(
        'cell_mv1_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cellMv2BlobMeta = const VerificationMeta(
    'cellMv2Blob',
  );
  @override
  late final GeneratedColumn<Uint8List> cellMv2Blob =
      GeneratedColumn<Uint8List>(
        'cell_mv2_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _setpointBlobMeta = const VerificationMeta(
    'setpointBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> setpointBlob =
      GeneratedColumn<Uint8List>(
        'setpoint_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cnsBlobMeta = const VerificationMeta(
    'cnsBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> cnsBlob = GeneratedColumn<Uint8List>(
    'cns_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decoDepthBlobMeta = const VerificationMeta(
    'decoDepthBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> decoDepthBlob =
      GeneratedColumn<Uint8List>(
        'deco_depth_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _decoTimeBlobMeta = const VerificationMeta(
    'decoTimeBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> decoTimeBlob =
      GeneratedColumn<Uint8List>(
        'deco_time_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _ttsBlobMeta = const VerificationMeta(
    'ttsBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> ttsBlob = GeneratedColumn<Uint8List>(
    'tts_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gasMixIdxBlobMeta = const VerificationMeta(
    'gasMixIdxBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> gasMixIdxBlob =
      GeneratedColumn<Uint8List>(
        'gas_mix_idx_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _statusBlobMeta = const VerificationMeta(
    'statusBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> statusBlob = GeneratedColumn<Uint8List>(
    'status_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tankPressuresBlobMeta = const VerificationMeta(
    'tankPressuresBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> tankPressuresBlob =
      GeneratedColumn<Uint8List>(
        'tank_pressures_blob',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    diveId,
    sampleCount,
    depthBlob,
    temperatureBlob,
    ppo2Blob,
    cellMv0Blob,
    cellMv1Blob,
    cellMv2Blob,
    setpointBlob,
    cnsBlob,
    decoDepthBlob,
    decoTimeBlob,
    ttsBlob,
    gasMixIdxBlob,
    statusBlob,
    tankPressuresBlob,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveSample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('sample_count')) {
      context.handle(
        _sampleCountMeta,
        sampleCount.isAcceptableOrUnknown(
          data['sample_count']!,
          _sampleCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sampleCountMeta);
    }
    if (data.containsKey('depth_blob')) {
      context.handle(
        _depthBlobMeta,
        depthBlob.isAcceptableOrUnknown(data['depth_blob']!, _depthBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_depthBlobMeta);
    }
    if (data.containsKey('temperature_blob')) {
      context.handle(
        _temperatureBlobMeta,
        temperatureBlob.isAcceptableOrUnknown(
          data['temperature_blob']!,
          _temperatureBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_temperatureBlobMeta);
    }
    if (data.containsKey('ppo2_blob')) {
      context.handle(
        _ppo2BlobMeta,
        ppo2Blob.isAcceptableOrUnknown(data['ppo2_blob']!, _ppo2BlobMeta),
      );
    } else if (isInserting) {
      context.missing(_ppo2BlobMeta);
    }
    if (data.containsKey('cell_mv0_blob')) {
      context.handle(
        _cellMv0BlobMeta,
        cellMv0Blob.isAcceptableOrUnknown(
          data['cell_mv0_blob']!,
          _cellMv0BlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cellMv0BlobMeta);
    }
    if (data.containsKey('cell_mv1_blob')) {
      context.handle(
        _cellMv1BlobMeta,
        cellMv1Blob.isAcceptableOrUnknown(
          data['cell_mv1_blob']!,
          _cellMv1BlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cellMv1BlobMeta);
    }
    if (data.containsKey('cell_mv2_blob')) {
      context.handle(
        _cellMv2BlobMeta,
        cellMv2Blob.isAcceptableOrUnknown(
          data['cell_mv2_blob']!,
          _cellMv2BlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cellMv2BlobMeta);
    }
    if (data.containsKey('setpoint_blob')) {
      context.handle(
        _setpointBlobMeta,
        setpointBlob.isAcceptableOrUnknown(
          data['setpoint_blob']!,
          _setpointBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_setpointBlobMeta);
    }
    if (data.containsKey('cns_blob')) {
      context.handle(
        _cnsBlobMeta,
        cnsBlob.isAcceptableOrUnknown(data['cns_blob']!, _cnsBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_cnsBlobMeta);
    }
    if (data.containsKey('deco_depth_blob')) {
      context.handle(
        _decoDepthBlobMeta,
        decoDepthBlob.isAcceptableOrUnknown(
          data['deco_depth_blob']!,
          _decoDepthBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_decoDepthBlobMeta);
    }
    if (data.containsKey('deco_time_blob')) {
      context.handle(
        _decoTimeBlobMeta,
        decoTimeBlob.isAcceptableOrUnknown(
          data['deco_time_blob']!,
          _decoTimeBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_decoTimeBlobMeta);
    }
    if (data.containsKey('tts_blob')) {
      context.handle(
        _ttsBlobMeta,
        ttsBlob.isAcceptableOrUnknown(data['tts_blob']!, _ttsBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_ttsBlobMeta);
    }
    if (data.containsKey('gas_mix_idx_blob')) {
      context.handle(
        _gasMixIdxBlobMeta,
        gasMixIdxBlob.isAcceptableOrUnknown(
          data['gas_mix_idx_blob']!,
          _gasMixIdxBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_gasMixIdxBlobMeta);
    }
    if (data.containsKey('status_blob')) {
      context.handle(
        _statusBlobMeta,
        statusBlob.isAcceptableOrUnknown(data['status_blob']!, _statusBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_statusBlobMeta);
    }
    if (data.containsKey('tank_pressures_blob')) {
      context.handle(
        _tankPressuresBlobMeta,
        tankPressuresBlob.isAcceptableOrUnknown(
          data['tank_pressures_blob']!,
          _tankPressuresBlobMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveId};
  @override
  DiveSample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveSample(
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      sampleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_count'],
      )!,
      depthBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}depth_blob'],
      )!,
      temperatureBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}temperature_blob'],
      )!,
      ppo2Blob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}ppo2_blob'],
      )!,
      cellMv0Blob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}cell_mv0_blob'],
      )!,
      cellMv1Blob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}cell_mv1_blob'],
      )!,
      cellMv2Blob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}cell_mv2_blob'],
      )!,
      setpointBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}setpoint_blob'],
      )!,
      cnsBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}cns_blob'],
      )!,
      decoDepthBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}deco_depth_blob'],
      )!,
      decoTimeBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}deco_time_blob'],
      )!,
      ttsBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}tts_blob'],
      )!,
      gasMixIdxBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}gas_mix_idx_blob'],
      )!,
      statusBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}status_blob'],
      )!,
      tankPressuresBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}tank_pressures_blob'],
      ),
    );
  }

  @override
  $DiveSamplesTable createAlias(String alias) {
    return $DiveSamplesTable(attachedDatabase, alias);
  }
}

class DiveSample extends DataClass implements Insertable<DiveSample> {
  final String diveId;
  final int sampleCount;
  final Uint8List depthBlob;
  final Uint8List temperatureBlob;
  final Uint8List ppo2Blob;
  final Uint8List cellMv0Blob;
  final Uint8List cellMv1Blob;
  final Uint8List cellMv2Blob;
  final Uint8List setpointBlob;
  final Uint8List cnsBlob;
  final Uint8List decoDepthBlob;
  final Uint8List decoTimeBlob;
  final Uint8List ttsBlob;
  final Uint8List gasMixIdxBlob;
  final Uint8List statusBlob;

  /// Combined per-tank pressure trace blob (gzipped Float32 channels with
  /// a small header). Null for OC dives and pre-v6 imports.
  final Uint8List? tankPressuresBlob;
  const DiveSample({
    required this.diveId,
    required this.sampleCount,
    required this.depthBlob,
    required this.temperatureBlob,
    required this.ppo2Blob,
    required this.cellMv0Blob,
    required this.cellMv1Blob,
    required this.cellMv2Blob,
    required this.setpointBlob,
    required this.cnsBlob,
    required this.decoDepthBlob,
    required this.decoTimeBlob,
    required this.ttsBlob,
    required this.gasMixIdxBlob,
    required this.statusBlob,
    this.tankPressuresBlob,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_id'] = Variable<String>(diveId);
    map['sample_count'] = Variable<int>(sampleCount);
    map['depth_blob'] = Variable<Uint8List>(depthBlob);
    map['temperature_blob'] = Variable<Uint8List>(temperatureBlob);
    map['ppo2_blob'] = Variable<Uint8List>(ppo2Blob);
    map['cell_mv0_blob'] = Variable<Uint8List>(cellMv0Blob);
    map['cell_mv1_blob'] = Variable<Uint8List>(cellMv1Blob);
    map['cell_mv2_blob'] = Variable<Uint8List>(cellMv2Blob);
    map['setpoint_blob'] = Variable<Uint8List>(setpointBlob);
    map['cns_blob'] = Variable<Uint8List>(cnsBlob);
    map['deco_depth_blob'] = Variable<Uint8List>(decoDepthBlob);
    map['deco_time_blob'] = Variable<Uint8List>(decoTimeBlob);
    map['tts_blob'] = Variable<Uint8List>(ttsBlob);
    map['gas_mix_idx_blob'] = Variable<Uint8List>(gasMixIdxBlob);
    map['status_blob'] = Variable<Uint8List>(statusBlob);
    if (!nullToAbsent || tankPressuresBlob != null) {
      map['tank_pressures_blob'] = Variable<Uint8List>(tankPressuresBlob);
    }
    return map;
  }

  DiveSamplesCompanion toCompanion(bool nullToAbsent) {
    return DiveSamplesCompanion(
      diveId: Value(diveId),
      sampleCount: Value(sampleCount),
      depthBlob: Value(depthBlob),
      temperatureBlob: Value(temperatureBlob),
      ppo2Blob: Value(ppo2Blob),
      cellMv0Blob: Value(cellMv0Blob),
      cellMv1Blob: Value(cellMv1Blob),
      cellMv2Blob: Value(cellMv2Blob),
      setpointBlob: Value(setpointBlob),
      cnsBlob: Value(cnsBlob),
      decoDepthBlob: Value(decoDepthBlob),
      decoTimeBlob: Value(decoTimeBlob),
      ttsBlob: Value(ttsBlob),
      gasMixIdxBlob: Value(gasMixIdxBlob),
      statusBlob: Value(statusBlob),
      tankPressuresBlob: tankPressuresBlob == null && nullToAbsent
          ? const Value.absent()
          : Value(tankPressuresBlob),
    );
  }

  factory DiveSample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveSample(
      diveId: serializer.fromJson<String>(json['diveId']),
      sampleCount: serializer.fromJson<int>(json['sampleCount']),
      depthBlob: serializer.fromJson<Uint8List>(json['depthBlob']),
      temperatureBlob: serializer.fromJson<Uint8List>(json['temperatureBlob']),
      ppo2Blob: serializer.fromJson<Uint8List>(json['ppo2Blob']),
      cellMv0Blob: serializer.fromJson<Uint8List>(json['cellMv0Blob']),
      cellMv1Blob: serializer.fromJson<Uint8List>(json['cellMv1Blob']),
      cellMv2Blob: serializer.fromJson<Uint8List>(json['cellMv2Blob']),
      setpointBlob: serializer.fromJson<Uint8List>(json['setpointBlob']),
      cnsBlob: serializer.fromJson<Uint8List>(json['cnsBlob']),
      decoDepthBlob: serializer.fromJson<Uint8List>(json['decoDepthBlob']),
      decoTimeBlob: serializer.fromJson<Uint8List>(json['decoTimeBlob']),
      ttsBlob: serializer.fromJson<Uint8List>(json['ttsBlob']),
      gasMixIdxBlob: serializer.fromJson<Uint8List>(json['gasMixIdxBlob']),
      statusBlob: serializer.fromJson<Uint8List>(json['statusBlob']),
      tankPressuresBlob: serializer.fromJson<Uint8List?>(
        json['tankPressuresBlob'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveId': serializer.toJson<String>(diveId),
      'sampleCount': serializer.toJson<int>(sampleCount),
      'depthBlob': serializer.toJson<Uint8List>(depthBlob),
      'temperatureBlob': serializer.toJson<Uint8List>(temperatureBlob),
      'ppo2Blob': serializer.toJson<Uint8List>(ppo2Blob),
      'cellMv0Blob': serializer.toJson<Uint8List>(cellMv0Blob),
      'cellMv1Blob': serializer.toJson<Uint8List>(cellMv1Blob),
      'cellMv2Blob': serializer.toJson<Uint8List>(cellMv2Blob),
      'setpointBlob': serializer.toJson<Uint8List>(setpointBlob),
      'cnsBlob': serializer.toJson<Uint8List>(cnsBlob),
      'decoDepthBlob': serializer.toJson<Uint8List>(decoDepthBlob),
      'decoTimeBlob': serializer.toJson<Uint8List>(decoTimeBlob),
      'ttsBlob': serializer.toJson<Uint8List>(ttsBlob),
      'gasMixIdxBlob': serializer.toJson<Uint8List>(gasMixIdxBlob),
      'statusBlob': serializer.toJson<Uint8List>(statusBlob),
      'tankPressuresBlob': serializer.toJson<Uint8List?>(tankPressuresBlob),
    };
  }

  DiveSample copyWith({
    String? diveId,
    int? sampleCount,
    Uint8List? depthBlob,
    Uint8List? temperatureBlob,
    Uint8List? ppo2Blob,
    Uint8List? cellMv0Blob,
    Uint8List? cellMv1Blob,
    Uint8List? cellMv2Blob,
    Uint8List? setpointBlob,
    Uint8List? cnsBlob,
    Uint8List? decoDepthBlob,
    Uint8List? decoTimeBlob,
    Uint8List? ttsBlob,
    Uint8List? gasMixIdxBlob,
    Uint8List? statusBlob,
    Value<Uint8List?> tankPressuresBlob = const Value.absent(),
  }) => DiveSample(
    diveId: diveId ?? this.diveId,
    sampleCount: sampleCount ?? this.sampleCount,
    depthBlob: depthBlob ?? this.depthBlob,
    temperatureBlob: temperatureBlob ?? this.temperatureBlob,
    ppo2Blob: ppo2Blob ?? this.ppo2Blob,
    cellMv0Blob: cellMv0Blob ?? this.cellMv0Blob,
    cellMv1Blob: cellMv1Blob ?? this.cellMv1Blob,
    cellMv2Blob: cellMv2Blob ?? this.cellMv2Blob,
    setpointBlob: setpointBlob ?? this.setpointBlob,
    cnsBlob: cnsBlob ?? this.cnsBlob,
    decoDepthBlob: decoDepthBlob ?? this.decoDepthBlob,
    decoTimeBlob: decoTimeBlob ?? this.decoTimeBlob,
    ttsBlob: ttsBlob ?? this.ttsBlob,
    gasMixIdxBlob: gasMixIdxBlob ?? this.gasMixIdxBlob,
    statusBlob: statusBlob ?? this.statusBlob,
    tankPressuresBlob: tankPressuresBlob.present
        ? tankPressuresBlob.value
        : this.tankPressuresBlob,
  );
  DiveSample copyWithCompanion(DiveSamplesCompanion data) {
    return DiveSample(
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      sampleCount: data.sampleCount.present
          ? data.sampleCount.value
          : this.sampleCount,
      depthBlob: data.depthBlob.present ? data.depthBlob.value : this.depthBlob,
      temperatureBlob: data.temperatureBlob.present
          ? data.temperatureBlob.value
          : this.temperatureBlob,
      ppo2Blob: data.ppo2Blob.present ? data.ppo2Blob.value : this.ppo2Blob,
      cellMv0Blob: data.cellMv0Blob.present
          ? data.cellMv0Blob.value
          : this.cellMv0Blob,
      cellMv1Blob: data.cellMv1Blob.present
          ? data.cellMv1Blob.value
          : this.cellMv1Blob,
      cellMv2Blob: data.cellMv2Blob.present
          ? data.cellMv2Blob.value
          : this.cellMv2Blob,
      setpointBlob: data.setpointBlob.present
          ? data.setpointBlob.value
          : this.setpointBlob,
      cnsBlob: data.cnsBlob.present ? data.cnsBlob.value : this.cnsBlob,
      decoDepthBlob: data.decoDepthBlob.present
          ? data.decoDepthBlob.value
          : this.decoDepthBlob,
      decoTimeBlob: data.decoTimeBlob.present
          ? data.decoTimeBlob.value
          : this.decoTimeBlob,
      ttsBlob: data.ttsBlob.present ? data.ttsBlob.value : this.ttsBlob,
      gasMixIdxBlob: data.gasMixIdxBlob.present
          ? data.gasMixIdxBlob.value
          : this.gasMixIdxBlob,
      statusBlob: data.statusBlob.present
          ? data.statusBlob.value
          : this.statusBlob,
      tankPressuresBlob: data.tankPressuresBlob.present
          ? data.tankPressuresBlob.value
          : this.tankPressuresBlob,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveSample(')
          ..write('diveId: $diveId, ')
          ..write('sampleCount: $sampleCount, ')
          ..write('depthBlob: $depthBlob, ')
          ..write('temperatureBlob: $temperatureBlob, ')
          ..write('ppo2Blob: $ppo2Blob, ')
          ..write('cellMv0Blob: $cellMv0Blob, ')
          ..write('cellMv1Blob: $cellMv1Blob, ')
          ..write('cellMv2Blob: $cellMv2Blob, ')
          ..write('setpointBlob: $setpointBlob, ')
          ..write('cnsBlob: $cnsBlob, ')
          ..write('decoDepthBlob: $decoDepthBlob, ')
          ..write('decoTimeBlob: $decoTimeBlob, ')
          ..write('ttsBlob: $ttsBlob, ')
          ..write('gasMixIdxBlob: $gasMixIdxBlob, ')
          ..write('statusBlob: $statusBlob, ')
          ..write('tankPressuresBlob: $tankPressuresBlob')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    diveId,
    sampleCount,
    $driftBlobEquality.hash(depthBlob),
    $driftBlobEquality.hash(temperatureBlob),
    $driftBlobEquality.hash(ppo2Blob),
    $driftBlobEquality.hash(cellMv0Blob),
    $driftBlobEquality.hash(cellMv1Blob),
    $driftBlobEquality.hash(cellMv2Blob),
    $driftBlobEquality.hash(setpointBlob),
    $driftBlobEquality.hash(cnsBlob),
    $driftBlobEquality.hash(decoDepthBlob),
    $driftBlobEquality.hash(decoTimeBlob),
    $driftBlobEquality.hash(ttsBlob),
    $driftBlobEquality.hash(gasMixIdxBlob),
    $driftBlobEquality.hash(statusBlob),
    $driftBlobEquality.hash(tankPressuresBlob),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveSample &&
          other.diveId == this.diveId &&
          other.sampleCount == this.sampleCount &&
          $driftBlobEquality.equals(other.depthBlob, this.depthBlob) &&
          $driftBlobEquality.equals(
            other.temperatureBlob,
            this.temperatureBlob,
          ) &&
          $driftBlobEquality.equals(other.ppo2Blob, this.ppo2Blob) &&
          $driftBlobEquality.equals(other.cellMv0Blob, this.cellMv0Blob) &&
          $driftBlobEquality.equals(other.cellMv1Blob, this.cellMv1Blob) &&
          $driftBlobEquality.equals(other.cellMv2Blob, this.cellMv2Blob) &&
          $driftBlobEquality.equals(other.setpointBlob, this.setpointBlob) &&
          $driftBlobEquality.equals(other.cnsBlob, this.cnsBlob) &&
          $driftBlobEquality.equals(other.decoDepthBlob, this.decoDepthBlob) &&
          $driftBlobEquality.equals(other.decoTimeBlob, this.decoTimeBlob) &&
          $driftBlobEquality.equals(other.ttsBlob, this.ttsBlob) &&
          $driftBlobEquality.equals(other.gasMixIdxBlob, this.gasMixIdxBlob) &&
          $driftBlobEquality.equals(other.statusBlob, this.statusBlob) &&
          $driftBlobEquality.equals(
            other.tankPressuresBlob,
            this.tankPressuresBlob,
          ));
}

class DiveSamplesCompanion extends UpdateCompanion<DiveSample> {
  final Value<String> diveId;
  final Value<int> sampleCount;
  final Value<Uint8List> depthBlob;
  final Value<Uint8List> temperatureBlob;
  final Value<Uint8List> ppo2Blob;
  final Value<Uint8List> cellMv0Blob;
  final Value<Uint8List> cellMv1Blob;
  final Value<Uint8List> cellMv2Blob;
  final Value<Uint8List> setpointBlob;
  final Value<Uint8List> cnsBlob;
  final Value<Uint8List> decoDepthBlob;
  final Value<Uint8List> decoTimeBlob;
  final Value<Uint8List> ttsBlob;
  final Value<Uint8List> gasMixIdxBlob;
  final Value<Uint8List> statusBlob;
  final Value<Uint8List?> tankPressuresBlob;
  final Value<int> rowid;
  const DiveSamplesCompanion({
    this.diveId = const Value.absent(),
    this.sampleCount = const Value.absent(),
    this.depthBlob = const Value.absent(),
    this.temperatureBlob = const Value.absent(),
    this.ppo2Blob = const Value.absent(),
    this.cellMv0Blob = const Value.absent(),
    this.cellMv1Blob = const Value.absent(),
    this.cellMv2Blob = const Value.absent(),
    this.setpointBlob = const Value.absent(),
    this.cnsBlob = const Value.absent(),
    this.decoDepthBlob = const Value.absent(),
    this.decoTimeBlob = const Value.absent(),
    this.ttsBlob = const Value.absent(),
    this.gasMixIdxBlob = const Value.absent(),
    this.statusBlob = const Value.absent(),
    this.tankPressuresBlob = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveSamplesCompanion.insert({
    required String diveId,
    required int sampleCount,
    required Uint8List depthBlob,
    required Uint8List temperatureBlob,
    required Uint8List ppo2Blob,
    required Uint8List cellMv0Blob,
    required Uint8List cellMv1Blob,
    required Uint8List cellMv2Blob,
    required Uint8List setpointBlob,
    required Uint8List cnsBlob,
    required Uint8List decoDepthBlob,
    required Uint8List decoTimeBlob,
    required Uint8List ttsBlob,
    required Uint8List gasMixIdxBlob,
    required Uint8List statusBlob,
    this.tankPressuresBlob = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : diveId = Value(diveId),
       sampleCount = Value(sampleCount),
       depthBlob = Value(depthBlob),
       temperatureBlob = Value(temperatureBlob),
       ppo2Blob = Value(ppo2Blob),
       cellMv0Blob = Value(cellMv0Blob),
       cellMv1Blob = Value(cellMv1Blob),
       cellMv2Blob = Value(cellMv2Blob),
       setpointBlob = Value(setpointBlob),
       cnsBlob = Value(cnsBlob),
       decoDepthBlob = Value(decoDepthBlob),
       decoTimeBlob = Value(decoTimeBlob),
       ttsBlob = Value(ttsBlob),
       gasMixIdxBlob = Value(gasMixIdxBlob),
       statusBlob = Value(statusBlob);
  static Insertable<DiveSample> custom({
    Expression<String>? diveId,
    Expression<int>? sampleCount,
    Expression<Uint8List>? depthBlob,
    Expression<Uint8List>? temperatureBlob,
    Expression<Uint8List>? ppo2Blob,
    Expression<Uint8List>? cellMv0Blob,
    Expression<Uint8List>? cellMv1Blob,
    Expression<Uint8List>? cellMv2Blob,
    Expression<Uint8List>? setpointBlob,
    Expression<Uint8List>? cnsBlob,
    Expression<Uint8List>? decoDepthBlob,
    Expression<Uint8List>? decoTimeBlob,
    Expression<Uint8List>? ttsBlob,
    Expression<Uint8List>? gasMixIdxBlob,
    Expression<Uint8List>? statusBlob,
    Expression<Uint8List>? tankPressuresBlob,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveId != null) 'dive_id': diveId,
      if (sampleCount != null) 'sample_count': sampleCount,
      if (depthBlob != null) 'depth_blob': depthBlob,
      if (temperatureBlob != null) 'temperature_blob': temperatureBlob,
      if (ppo2Blob != null) 'ppo2_blob': ppo2Blob,
      if (cellMv0Blob != null) 'cell_mv0_blob': cellMv0Blob,
      if (cellMv1Blob != null) 'cell_mv1_blob': cellMv1Blob,
      if (cellMv2Blob != null) 'cell_mv2_blob': cellMv2Blob,
      if (setpointBlob != null) 'setpoint_blob': setpointBlob,
      if (cnsBlob != null) 'cns_blob': cnsBlob,
      if (decoDepthBlob != null) 'deco_depth_blob': decoDepthBlob,
      if (decoTimeBlob != null) 'deco_time_blob': decoTimeBlob,
      if (ttsBlob != null) 'tts_blob': ttsBlob,
      if (gasMixIdxBlob != null) 'gas_mix_idx_blob': gasMixIdxBlob,
      if (statusBlob != null) 'status_blob': statusBlob,
      if (tankPressuresBlob != null) 'tank_pressures_blob': tankPressuresBlob,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveSamplesCompanion copyWith({
    Value<String>? diveId,
    Value<int>? sampleCount,
    Value<Uint8List>? depthBlob,
    Value<Uint8List>? temperatureBlob,
    Value<Uint8List>? ppo2Blob,
    Value<Uint8List>? cellMv0Blob,
    Value<Uint8List>? cellMv1Blob,
    Value<Uint8List>? cellMv2Blob,
    Value<Uint8List>? setpointBlob,
    Value<Uint8List>? cnsBlob,
    Value<Uint8List>? decoDepthBlob,
    Value<Uint8List>? decoTimeBlob,
    Value<Uint8List>? ttsBlob,
    Value<Uint8List>? gasMixIdxBlob,
    Value<Uint8List>? statusBlob,
    Value<Uint8List?>? tankPressuresBlob,
    Value<int>? rowid,
  }) {
    return DiveSamplesCompanion(
      diveId: diveId ?? this.diveId,
      sampleCount: sampleCount ?? this.sampleCount,
      depthBlob: depthBlob ?? this.depthBlob,
      temperatureBlob: temperatureBlob ?? this.temperatureBlob,
      ppo2Blob: ppo2Blob ?? this.ppo2Blob,
      cellMv0Blob: cellMv0Blob ?? this.cellMv0Blob,
      cellMv1Blob: cellMv1Blob ?? this.cellMv1Blob,
      cellMv2Blob: cellMv2Blob ?? this.cellMv2Blob,
      setpointBlob: setpointBlob ?? this.setpointBlob,
      cnsBlob: cnsBlob ?? this.cnsBlob,
      decoDepthBlob: decoDepthBlob ?? this.decoDepthBlob,
      decoTimeBlob: decoTimeBlob ?? this.decoTimeBlob,
      ttsBlob: ttsBlob ?? this.ttsBlob,
      gasMixIdxBlob: gasMixIdxBlob ?? this.gasMixIdxBlob,
      statusBlob: statusBlob ?? this.statusBlob,
      tankPressuresBlob: tankPressuresBlob ?? this.tankPressuresBlob,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (sampleCount.present) {
      map['sample_count'] = Variable<int>(sampleCount.value);
    }
    if (depthBlob.present) {
      map['depth_blob'] = Variable<Uint8List>(depthBlob.value);
    }
    if (temperatureBlob.present) {
      map['temperature_blob'] = Variable<Uint8List>(temperatureBlob.value);
    }
    if (ppo2Blob.present) {
      map['ppo2_blob'] = Variable<Uint8List>(ppo2Blob.value);
    }
    if (cellMv0Blob.present) {
      map['cell_mv0_blob'] = Variable<Uint8List>(cellMv0Blob.value);
    }
    if (cellMv1Blob.present) {
      map['cell_mv1_blob'] = Variable<Uint8List>(cellMv1Blob.value);
    }
    if (cellMv2Blob.present) {
      map['cell_mv2_blob'] = Variable<Uint8List>(cellMv2Blob.value);
    }
    if (setpointBlob.present) {
      map['setpoint_blob'] = Variable<Uint8List>(setpointBlob.value);
    }
    if (cnsBlob.present) {
      map['cns_blob'] = Variable<Uint8List>(cnsBlob.value);
    }
    if (decoDepthBlob.present) {
      map['deco_depth_blob'] = Variable<Uint8List>(decoDepthBlob.value);
    }
    if (decoTimeBlob.present) {
      map['deco_time_blob'] = Variable<Uint8List>(decoTimeBlob.value);
    }
    if (ttsBlob.present) {
      map['tts_blob'] = Variable<Uint8List>(ttsBlob.value);
    }
    if (gasMixIdxBlob.present) {
      map['gas_mix_idx_blob'] = Variable<Uint8List>(gasMixIdxBlob.value);
    }
    if (statusBlob.present) {
      map['status_blob'] = Variable<Uint8List>(statusBlob.value);
    }
    if (tankPressuresBlob.present) {
      map['tank_pressures_blob'] = Variable<Uint8List>(tankPressuresBlob.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveSamplesCompanion(')
          ..write('diveId: $diveId, ')
          ..write('sampleCount: $sampleCount, ')
          ..write('depthBlob: $depthBlob, ')
          ..write('temperatureBlob: $temperatureBlob, ')
          ..write('ppo2Blob: $ppo2Blob, ')
          ..write('cellMv0Blob: $cellMv0Blob, ')
          ..write('cellMv1Blob: $cellMv1Blob, ')
          ..write('cellMv2Blob: $cellMv2Blob, ')
          ..write('setpointBlob: $setpointBlob, ')
          ..write('cnsBlob: $cnsBlob, ')
          ..write('decoDepthBlob: $decoDepthBlob, ')
          ..write('decoTimeBlob: $decoTimeBlob, ')
          ..write('ttsBlob: $ttsBlob, ')
          ..write('gasMixIdxBlob: $gasMixIdxBlob, ')
          ..write('statusBlob: $statusBlob, ')
          ..write('tankPressuresBlob: $tankPressuresBlob, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveRawBlobsTable extends DiveRawBlobs
    with TableInfo<$DiveRawBlobsTable, DiveRawBlob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveRawBlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawBlobMeta = const VerificationMeta(
    'rawBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> rawBlob = GeneratedColumn<Uint8List>(
    'raw_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [diveId, rawBlob];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_raw_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveRawBlob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('raw_blob')) {
      context.handle(
        _rawBlobMeta,
        rawBlob.isAcceptableOrUnknown(data['raw_blob']!, _rawBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_rawBlobMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveId};
  @override
  DiveRawBlob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveRawBlob(
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      rawBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}raw_blob'],
      )!,
    );
  }

  @override
  $DiveRawBlobsTable createAlias(String alias) {
    return $DiveRawBlobsTable(attachedDatabase, alias);
  }
}

class DiveRawBlob extends DataClass implements Insertable<DiveRawBlob> {
  final String diveId;
  final Uint8List rawBlob;
  const DiveRawBlob({required this.diveId, required this.rawBlob});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_id'] = Variable<String>(diveId);
    map['raw_blob'] = Variable<Uint8List>(rawBlob);
    return map;
  }

  DiveRawBlobsCompanion toCompanion(bool nullToAbsent) {
    return DiveRawBlobsCompanion(
      diveId: Value(diveId),
      rawBlob: Value(rawBlob),
    );
  }

  factory DiveRawBlob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveRawBlob(
      diveId: serializer.fromJson<String>(json['diveId']),
      rawBlob: serializer.fromJson<Uint8List>(json['rawBlob']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveId': serializer.toJson<String>(diveId),
      'rawBlob': serializer.toJson<Uint8List>(rawBlob),
    };
  }

  DiveRawBlob copyWith({String? diveId, Uint8List? rawBlob}) => DiveRawBlob(
    diveId: diveId ?? this.diveId,
    rawBlob: rawBlob ?? this.rawBlob,
  );
  DiveRawBlob copyWithCompanion(DiveRawBlobsCompanion data) {
    return DiveRawBlob(
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      rawBlob: data.rawBlob.present ? data.rawBlob.value : this.rawBlob,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveRawBlob(')
          ..write('diveId: $diveId, ')
          ..write('rawBlob: $rawBlob')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(diveId, $driftBlobEquality.hash(rawBlob));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveRawBlob &&
          other.diveId == this.diveId &&
          $driftBlobEquality.equals(other.rawBlob, this.rawBlob));
}

class DiveRawBlobsCompanion extends UpdateCompanion<DiveRawBlob> {
  final Value<String> diveId;
  final Value<Uint8List> rawBlob;
  final Value<int> rowid;
  const DiveRawBlobsCompanion({
    this.diveId = const Value.absent(),
    this.rawBlob = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveRawBlobsCompanion.insert({
    required String diveId,
    required Uint8List rawBlob,
    this.rowid = const Value.absent(),
  }) : diveId = Value(diveId),
       rawBlob = Value(rawBlob);
  static Insertable<DiveRawBlob> custom({
    Expression<String>? diveId,
    Expression<Uint8List>? rawBlob,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveId != null) 'dive_id': diveId,
      if (rawBlob != null) 'raw_blob': rawBlob,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveRawBlobsCompanion copyWith({
    Value<String>? diveId,
    Value<Uint8List>? rawBlob,
    Value<int>? rowid,
  }) {
    return DiveRawBlobsCompanion(
      diveId: diveId ?? this.diveId,
      rawBlob: rawBlob ?? this.rawBlob,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (rawBlob.present) {
      map['raw_blob'] = Variable<Uint8List>(rawBlob.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveRawBlobsCompanion(')
          ..write('diveId: $diveId, ')
          ..write('rawBlob: $rawBlob, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveAnnotationsTable extends DiveAnnotations
    with TableInfo<$DiveAnnotationsTable, DiveAnnotation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveAnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dives (id)',
    ),
  );
  static const VerificationMeta _siteNameMeta = const VerificationMeta(
    'siteName',
  );
  @override
  late final GeneratedColumn<String> siteName = GeneratedColumn<String>(
    'site_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _siteLatitudeE5Meta = const VerificationMeta(
    'siteLatitudeE5',
  );
  @override
  late final GeneratedColumn<int> siteLatitudeE5 = GeneratedColumn<int>(
    'site_latitude_e5',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _siteLongitudeE5Meta = const VerificationMeta(
    'siteLongitudeE5',
  );
  @override
  late final GeneratedColumn<int> siteLongitudeE5 = GeneratedColumn<int>(
    'site_longitude_e5',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _buddiesJsonMeta = const VerificationMeta(
    'buddiesJson',
  );
  @override
  late final GeneratedColumn<String> buddiesJson = GeneratedColumn<String>(
    'buddies_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conditionsMeta = const VerificationMeta(
    'conditions',
  );
  @override
  late final GeneratedColumn<String> conditions = GeneratedColumn<String>(
    'conditions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _divemasterMeta = const VerificationMeta(
    'divemaster',
  );
  @override
  late final GeneratedColumn<String> divemaster = GeneratedColumn<String>(
    'divemaster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _visibilityMeta = const VerificationMeta(
    'visibility',
  );
  @override
  late final GeneratedColumn<int> visibility = GeneratedColumn<int>(
    'visibility',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wavesizeMeta = const VerificationMeta(
    'wavesize',
  );
  @override
  late final GeneratedColumn<int> wavesize = GeneratedColumn<int>(
    'wavesize',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentMeta = const VerificationMeta(
    'current',
  );
  @override
  late final GeneratedColumn<int> current = GeneratedColumn<int>(
    'current',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _surgeMeta = const VerificationMeta('surge');
  @override
  late final GeneratedColumn<int> surge = GeneratedColumn<int>(
    'surge',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chillMeta = const VerificationMeta('chill');
  @override
  late final GeneratedColumn<int> chill = GeneratedColumn<int>(
    'chill',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _airTempCMeta = const VerificationMeta(
    'airTempC',
  );
  @override
  late final GeneratedColumn<double> airTempC = GeneratedColumn<double>(
    'air_temp_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waterTempCMeta = const VerificationMeta(
    'waterTempC',
  );
  @override
  late final GeneratedColumn<double> waterTempC = GeneratedColumn<double>(
    'water_temp_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightsJsonMeta = const VerificationMeta(
    'weightsJson',
  );
  @override
  late final GeneratedColumn<String> weightsJson = GeneratedColumn<String>(
    'weights_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayDecoAlgorithmMeta =
      const VerificationMeta('displayDecoAlgorithm');
  @override
  late final GeneratedColumn<String> displayDecoAlgorithm =
      GeneratedColumn<String>(
        'display_deco_algorithm',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    diveId,
    siteName,
    siteLatitudeE5,
    siteLongitudeE5,
    notes,
    buddiesJson,
    tagsJson,
    rating,
    conditions,
    divemaster,
    visibility,
    wavesize,
    current,
    surge,
    chill,
    airTempC,
    waterTempC,
    weightsJson,
    displayDecoAlgorithm,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveAnnotation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('site_name')) {
      context.handle(
        _siteNameMeta,
        siteName.isAcceptableOrUnknown(data['site_name']!, _siteNameMeta),
      );
    }
    if (data.containsKey('site_latitude_e5')) {
      context.handle(
        _siteLatitudeE5Meta,
        siteLatitudeE5.isAcceptableOrUnknown(
          data['site_latitude_e5']!,
          _siteLatitudeE5Meta,
        ),
      );
    }
    if (data.containsKey('site_longitude_e5')) {
      context.handle(
        _siteLongitudeE5Meta,
        siteLongitudeE5.isAcceptableOrUnknown(
          data['site_longitude_e5']!,
          _siteLongitudeE5Meta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('buddies_json')) {
      context.handle(
        _buddiesJsonMeta,
        buddiesJson.isAcceptableOrUnknown(
          data['buddies_json']!,
          _buddiesJsonMeta,
        ),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('conditions')) {
      context.handle(
        _conditionsMeta,
        conditions.isAcceptableOrUnknown(data['conditions']!, _conditionsMeta),
      );
    }
    if (data.containsKey('divemaster')) {
      context.handle(
        _divemasterMeta,
        divemaster.isAcceptableOrUnknown(data['divemaster']!, _divemasterMeta),
      );
    }
    if (data.containsKey('visibility')) {
      context.handle(
        _visibilityMeta,
        visibility.isAcceptableOrUnknown(data['visibility']!, _visibilityMeta),
      );
    }
    if (data.containsKey('wavesize')) {
      context.handle(
        _wavesizeMeta,
        wavesize.isAcceptableOrUnknown(data['wavesize']!, _wavesizeMeta),
      );
    }
    if (data.containsKey('current')) {
      context.handle(
        _currentMeta,
        current.isAcceptableOrUnknown(data['current']!, _currentMeta),
      );
    }
    if (data.containsKey('surge')) {
      context.handle(
        _surgeMeta,
        surge.isAcceptableOrUnknown(data['surge']!, _surgeMeta),
      );
    }
    if (data.containsKey('chill')) {
      context.handle(
        _chillMeta,
        chill.isAcceptableOrUnknown(data['chill']!, _chillMeta),
      );
    }
    if (data.containsKey('air_temp_c')) {
      context.handle(
        _airTempCMeta,
        airTempC.isAcceptableOrUnknown(data['air_temp_c']!, _airTempCMeta),
      );
    }
    if (data.containsKey('water_temp_c')) {
      context.handle(
        _waterTempCMeta,
        waterTempC.isAcceptableOrUnknown(
          data['water_temp_c']!,
          _waterTempCMeta,
        ),
      );
    }
    if (data.containsKey('weights_json')) {
      context.handle(
        _weightsJsonMeta,
        weightsJson.isAcceptableOrUnknown(
          data['weights_json']!,
          _weightsJsonMeta,
        ),
      );
    }
    if (data.containsKey('display_deco_algorithm')) {
      context.handle(
        _displayDecoAlgorithmMeta,
        displayDecoAlgorithm.isAcceptableOrUnknown(
          data['display_deco_algorithm']!,
          _displayDecoAlgorithmMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveId};
  @override
  DiveAnnotation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveAnnotation(
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      siteName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_name'],
      ),
      siteLatitudeE5: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}site_latitude_e5'],
      ),
      siteLongitudeE5: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}site_longitude_e5'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      buddiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}buddies_json'],
      ),
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      conditions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conditions'],
      ),
      divemaster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}divemaster'],
      ),
      visibility: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}visibility'],
      ),
      wavesize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wavesize'],
      ),
      current: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current'],
      ),
      surge: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}surge'],
      ),
      chill: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chill'],
      ),
      airTempC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}air_temp_c'],
      ),
      waterTempC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}water_temp_c'],
      ),
      weightsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weights_json'],
      ),
      displayDecoAlgorithm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_deco_algorithm'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $DiveAnnotationsTable createAlias(String alias) {
    return $DiveAnnotationsTable(attachedDatabase, alias);
  }
}

class DiveAnnotation extends DataClass implements Insertable<DiveAnnotation> {
  final String diveId;
  final String? siteName;
  final int? siteLatitudeE5;
  final int? siteLongitudeE5;
  final String? notes;
  final String? buddiesJson;
  final String? tagsJson;
  final int? rating;
  final String? conditions;
  final String? divemaster;
  final int? visibility;
  final int? wavesize;
  final int? current;
  final int? surge;
  final int? chill;
  final double? airTempC;
  final double? waterTempC;

  /// JSON array of `{"weight_kg": double, "description": string}` objects,
  /// one per `weightsystem` line in Subsurface. Null = no weight entries.
  final String? weightsJson;

  /// User per-dive override of which deco algorithm to display.
  /// Values: 'zhl16c' or 'vpmb'. NULL = use default (ZHL-16C).
  final String? displayDecoAlgorithm;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const DiveAnnotation({
    required this.diveId,
    this.siteName,
    this.siteLatitudeE5,
    this.siteLongitudeE5,
    this.notes,
    this.buddiesJson,
    this.tagsJson,
    this.rating,
    this.conditions,
    this.divemaster,
    this.visibility,
    this.wavesize,
    this.current,
    this.surge,
    this.chill,
    this.airTempC,
    this.waterTempC,
    this.weightsJson,
    this.displayDecoAlgorithm,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_id'] = Variable<String>(diveId);
    if (!nullToAbsent || siteName != null) {
      map['site_name'] = Variable<String>(siteName);
    }
    if (!nullToAbsent || siteLatitudeE5 != null) {
      map['site_latitude_e5'] = Variable<int>(siteLatitudeE5);
    }
    if (!nullToAbsent || siteLongitudeE5 != null) {
      map['site_longitude_e5'] = Variable<int>(siteLongitudeE5);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || buddiesJson != null) {
      map['buddies_json'] = Variable<String>(buddiesJson);
    }
    if (!nullToAbsent || tagsJson != null) {
      map['tags_json'] = Variable<String>(tagsJson);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    if (!nullToAbsent || conditions != null) {
      map['conditions'] = Variable<String>(conditions);
    }
    if (!nullToAbsent || divemaster != null) {
      map['divemaster'] = Variable<String>(divemaster);
    }
    if (!nullToAbsent || visibility != null) {
      map['visibility'] = Variable<int>(visibility);
    }
    if (!nullToAbsent || wavesize != null) {
      map['wavesize'] = Variable<int>(wavesize);
    }
    if (!nullToAbsent || current != null) {
      map['current'] = Variable<int>(current);
    }
    if (!nullToAbsent || surge != null) {
      map['surge'] = Variable<int>(surge);
    }
    if (!nullToAbsent || chill != null) {
      map['chill'] = Variable<int>(chill);
    }
    if (!nullToAbsent || airTempC != null) {
      map['air_temp_c'] = Variable<double>(airTempC);
    }
    if (!nullToAbsent || waterTempC != null) {
      map['water_temp_c'] = Variable<double>(waterTempC);
    }
    if (!nullToAbsent || weightsJson != null) {
      map['weights_json'] = Variable<String>(weightsJson);
    }
    if (!nullToAbsent || displayDecoAlgorithm != null) {
      map['display_deco_algorithm'] = Variable<String>(displayDecoAlgorithm);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  DiveAnnotationsCompanion toCompanion(bool nullToAbsent) {
    return DiveAnnotationsCompanion(
      diveId: Value(diveId),
      siteName: siteName == null && nullToAbsent
          ? const Value.absent()
          : Value(siteName),
      siteLatitudeE5: siteLatitudeE5 == null && nullToAbsent
          ? const Value.absent()
          : Value(siteLatitudeE5),
      siteLongitudeE5: siteLongitudeE5 == null && nullToAbsent
          ? const Value.absent()
          : Value(siteLongitudeE5),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      buddiesJson: buddiesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(buddiesJson),
      tagsJson: tagsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsJson),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      conditions: conditions == null && nullToAbsent
          ? const Value.absent()
          : Value(conditions),
      divemaster: divemaster == null && nullToAbsent
          ? const Value.absent()
          : Value(divemaster),
      visibility: visibility == null && nullToAbsent
          ? const Value.absent()
          : Value(visibility),
      wavesize: wavesize == null && nullToAbsent
          ? const Value.absent()
          : Value(wavesize),
      current: current == null && nullToAbsent
          ? const Value.absent()
          : Value(current),
      surge: surge == null && nullToAbsent
          ? const Value.absent()
          : Value(surge),
      chill: chill == null && nullToAbsent
          ? const Value.absent()
          : Value(chill),
      airTempC: airTempC == null && nullToAbsent
          ? const Value.absent()
          : Value(airTempC),
      waterTempC: waterTempC == null && nullToAbsent
          ? const Value.absent()
          : Value(waterTempC),
      weightsJson: weightsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(weightsJson),
      displayDecoAlgorithm: displayDecoAlgorithm == null && nullToAbsent
          ? const Value.absent()
          : Value(displayDecoAlgorithm),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory DiveAnnotation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveAnnotation(
      diveId: serializer.fromJson<String>(json['diveId']),
      siteName: serializer.fromJson<String?>(json['siteName']),
      siteLatitudeE5: serializer.fromJson<int?>(json['siteLatitudeE5']),
      siteLongitudeE5: serializer.fromJson<int?>(json['siteLongitudeE5']),
      notes: serializer.fromJson<String?>(json['notes']),
      buddiesJson: serializer.fromJson<String?>(json['buddiesJson']),
      tagsJson: serializer.fromJson<String?>(json['tagsJson']),
      rating: serializer.fromJson<int?>(json['rating']),
      conditions: serializer.fromJson<String?>(json['conditions']),
      divemaster: serializer.fromJson<String?>(json['divemaster']),
      visibility: serializer.fromJson<int?>(json['visibility']),
      wavesize: serializer.fromJson<int?>(json['wavesize']),
      current: serializer.fromJson<int?>(json['current']),
      surge: serializer.fromJson<int?>(json['surge']),
      chill: serializer.fromJson<int?>(json['chill']),
      airTempC: serializer.fromJson<double?>(json['airTempC']),
      waterTempC: serializer.fromJson<double?>(json['waterTempC']),
      weightsJson: serializer.fromJson<String?>(json['weightsJson']),
      displayDecoAlgorithm: serializer.fromJson<String?>(
        json['displayDecoAlgorithm'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveId': serializer.toJson<String>(diveId),
      'siteName': serializer.toJson<String?>(siteName),
      'siteLatitudeE5': serializer.toJson<int?>(siteLatitudeE5),
      'siteLongitudeE5': serializer.toJson<int?>(siteLongitudeE5),
      'notes': serializer.toJson<String?>(notes),
      'buddiesJson': serializer.toJson<String?>(buddiesJson),
      'tagsJson': serializer.toJson<String?>(tagsJson),
      'rating': serializer.toJson<int?>(rating),
      'conditions': serializer.toJson<String?>(conditions),
      'divemaster': serializer.toJson<String?>(divemaster),
      'visibility': serializer.toJson<int?>(visibility),
      'wavesize': serializer.toJson<int?>(wavesize),
      'current': serializer.toJson<int?>(current),
      'surge': serializer.toJson<int?>(surge),
      'chill': serializer.toJson<int?>(chill),
      'airTempC': serializer.toJson<double?>(airTempC),
      'waterTempC': serializer.toJson<double?>(waterTempC),
      'weightsJson': serializer.toJson<String?>(weightsJson),
      'displayDecoAlgorithm': serializer.toJson<String?>(displayDecoAlgorithm),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  DiveAnnotation copyWith({
    String? diveId,
    Value<String?> siteName = const Value.absent(),
    Value<int?> siteLatitudeE5 = const Value.absent(),
    Value<int?> siteLongitudeE5 = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> buddiesJson = const Value.absent(),
    Value<String?> tagsJson = const Value.absent(),
    Value<int?> rating = const Value.absent(),
    Value<String?> conditions = const Value.absent(),
    Value<String?> divemaster = const Value.absent(),
    Value<int?> visibility = const Value.absent(),
    Value<int?> wavesize = const Value.absent(),
    Value<int?> current = const Value.absent(),
    Value<int?> surge = const Value.absent(),
    Value<int?> chill = const Value.absent(),
    Value<double?> airTempC = const Value.absent(),
    Value<double?> waterTempC = const Value.absent(),
    Value<String?> weightsJson = const Value.absent(),
    Value<String?> displayDecoAlgorithm = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => DiveAnnotation(
    diveId: diveId ?? this.diveId,
    siteName: siteName.present ? siteName.value : this.siteName,
    siteLatitudeE5: siteLatitudeE5.present
        ? siteLatitudeE5.value
        : this.siteLatitudeE5,
    siteLongitudeE5: siteLongitudeE5.present
        ? siteLongitudeE5.value
        : this.siteLongitudeE5,
    notes: notes.present ? notes.value : this.notes,
    buddiesJson: buddiesJson.present ? buddiesJson.value : this.buddiesJson,
    tagsJson: tagsJson.present ? tagsJson.value : this.tagsJson,
    rating: rating.present ? rating.value : this.rating,
    conditions: conditions.present ? conditions.value : this.conditions,
    divemaster: divemaster.present ? divemaster.value : this.divemaster,
    visibility: visibility.present ? visibility.value : this.visibility,
    wavesize: wavesize.present ? wavesize.value : this.wavesize,
    current: current.present ? current.value : this.current,
    surge: surge.present ? surge.value : this.surge,
    chill: chill.present ? chill.value : this.chill,
    airTempC: airTempC.present ? airTempC.value : this.airTempC,
    waterTempC: waterTempC.present ? waterTempC.value : this.waterTempC,
    weightsJson: weightsJson.present ? weightsJson.value : this.weightsJson,
    displayDecoAlgorithm: displayDecoAlgorithm.present
        ? displayDecoAlgorithm.value
        : this.displayDecoAlgorithm,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  DiveAnnotation copyWithCompanion(DiveAnnotationsCompanion data) {
    return DiveAnnotation(
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      siteName: data.siteName.present ? data.siteName.value : this.siteName,
      siteLatitudeE5: data.siteLatitudeE5.present
          ? data.siteLatitudeE5.value
          : this.siteLatitudeE5,
      siteLongitudeE5: data.siteLongitudeE5.present
          ? data.siteLongitudeE5.value
          : this.siteLongitudeE5,
      notes: data.notes.present ? data.notes.value : this.notes,
      buddiesJson: data.buddiesJson.present
          ? data.buddiesJson.value
          : this.buddiesJson,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      rating: data.rating.present ? data.rating.value : this.rating,
      conditions: data.conditions.present
          ? data.conditions.value
          : this.conditions,
      divemaster: data.divemaster.present
          ? data.divemaster.value
          : this.divemaster,
      visibility: data.visibility.present
          ? data.visibility.value
          : this.visibility,
      wavesize: data.wavesize.present ? data.wavesize.value : this.wavesize,
      current: data.current.present ? data.current.value : this.current,
      surge: data.surge.present ? data.surge.value : this.surge,
      chill: data.chill.present ? data.chill.value : this.chill,
      airTempC: data.airTempC.present ? data.airTempC.value : this.airTempC,
      waterTempC: data.waterTempC.present
          ? data.waterTempC.value
          : this.waterTempC,
      weightsJson: data.weightsJson.present
          ? data.weightsJson.value
          : this.weightsJson,
      displayDecoAlgorithm: data.displayDecoAlgorithm.present
          ? data.displayDecoAlgorithm.value
          : this.displayDecoAlgorithm,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveAnnotation(')
          ..write('diveId: $diveId, ')
          ..write('siteName: $siteName, ')
          ..write('siteLatitudeE5: $siteLatitudeE5, ')
          ..write('siteLongitudeE5: $siteLongitudeE5, ')
          ..write('notes: $notes, ')
          ..write('buddiesJson: $buddiesJson, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('rating: $rating, ')
          ..write('conditions: $conditions, ')
          ..write('divemaster: $divemaster, ')
          ..write('visibility: $visibility, ')
          ..write('wavesize: $wavesize, ')
          ..write('current: $current, ')
          ..write('surge: $surge, ')
          ..write('chill: $chill, ')
          ..write('airTempC: $airTempC, ')
          ..write('waterTempC: $waterTempC, ')
          ..write('weightsJson: $weightsJson, ')
          ..write('displayDecoAlgorithm: $displayDecoAlgorithm, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    diveId,
    siteName,
    siteLatitudeE5,
    siteLongitudeE5,
    notes,
    buddiesJson,
    tagsJson,
    rating,
    conditions,
    divemaster,
    visibility,
    wavesize,
    current,
    surge,
    chill,
    airTempC,
    waterTempC,
    weightsJson,
    displayDecoAlgorithm,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveAnnotation &&
          other.diveId == this.diveId &&
          other.siteName == this.siteName &&
          other.siteLatitudeE5 == this.siteLatitudeE5 &&
          other.siteLongitudeE5 == this.siteLongitudeE5 &&
          other.notes == this.notes &&
          other.buddiesJson == this.buddiesJson &&
          other.tagsJson == this.tagsJson &&
          other.rating == this.rating &&
          other.conditions == this.conditions &&
          other.divemaster == this.divemaster &&
          other.visibility == this.visibility &&
          other.wavesize == this.wavesize &&
          other.current == this.current &&
          other.surge == this.surge &&
          other.chill == this.chill &&
          other.airTempC == this.airTempC &&
          other.waterTempC == this.waterTempC &&
          other.weightsJson == this.weightsJson &&
          other.displayDecoAlgorithm == this.displayDecoAlgorithm &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class DiveAnnotationsCompanion extends UpdateCompanion<DiveAnnotation> {
  final Value<String> diveId;
  final Value<String?> siteName;
  final Value<int?> siteLatitudeE5;
  final Value<int?> siteLongitudeE5;
  final Value<String?> notes;
  final Value<String?> buddiesJson;
  final Value<String?> tagsJson;
  final Value<int?> rating;
  final Value<String?> conditions;
  final Value<String?> divemaster;
  final Value<int?> visibility;
  final Value<int?> wavesize;
  final Value<int?> current;
  final Value<int?> surge;
  final Value<int?> chill;
  final Value<double?> airTempC;
  final Value<double?> waterTempC;
  final Value<String?> weightsJson;
  final Value<String?> displayDecoAlgorithm;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const DiveAnnotationsCompanion({
    this.diveId = const Value.absent(),
    this.siteName = const Value.absent(),
    this.siteLatitudeE5 = const Value.absent(),
    this.siteLongitudeE5 = const Value.absent(),
    this.notes = const Value.absent(),
    this.buddiesJson = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.rating = const Value.absent(),
    this.conditions = const Value.absent(),
    this.divemaster = const Value.absent(),
    this.visibility = const Value.absent(),
    this.wavesize = const Value.absent(),
    this.current = const Value.absent(),
    this.surge = const Value.absent(),
    this.chill = const Value.absent(),
    this.airTempC = const Value.absent(),
    this.waterTempC = const Value.absent(),
    this.weightsJson = const Value.absent(),
    this.displayDecoAlgorithm = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveAnnotationsCompanion.insert({
    required String diveId,
    this.siteName = const Value.absent(),
    this.siteLatitudeE5 = const Value.absent(),
    this.siteLongitudeE5 = const Value.absent(),
    this.notes = const Value.absent(),
    this.buddiesJson = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.rating = const Value.absent(),
    this.conditions = const Value.absent(),
    this.divemaster = const Value.absent(),
    this.visibility = const Value.absent(),
    this.wavesize = const Value.absent(),
    this.current = const Value.absent(),
    this.surge = const Value.absent(),
    this.chill = const Value.absent(),
    this.airTempC = const Value.absent(),
    this.waterTempC = const Value.absent(),
    this.weightsJson = const Value.absent(),
    this.displayDecoAlgorithm = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : diveId = Value(diveId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DiveAnnotation> custom({
    Expression<String>? diveId,
    Expression<String>? siteName,
    Expression<int>? siteLatitudeE5,
    Expression<int>? siteLongitudeE5,
    Expression<String>? notes,
    Expression<String>? buddiesJson,
    Expression<String>? tagsJson,
    Expression<int>? rating,
    Expression<String>? conditions,
    Expression<String>? divemaster,
    Expression<int>? visibility,
    Expression<int>? wavesize,
    Expression<int>? current,
    Expression<int>? surge,
    Expression<int>? chill,
    Expression<double>? airTempC,
    Expression<double>? waterTempC,
    Expression<String>? weightsJson,
    Expression<String>? displayDecoAlgorithm,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveId != null) 'dive_id': diveId,
      if (siteName != null) 'site_name': siteName,
      if (siteLatitudeE5 != null) 'site_latitude_e5': siteLatitudeE5,
      if (siteLongitudeE5 != null) 'site_longitude_e5': siteLongitudeE5,
      if (notes != null) 'notes': notes,
      if (buddiesJson != null) 'buddies_json': buddiesJson,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (rating != null) 'rating': rating,
      if (conditions != null) 'conditions': conditions,
      if (divemaster != null) 'divemaster': divemaster,
      if (visibility != null) 'visibility': visibility,
      if (wavesize != null) 'wavesize': wavesize,
      if (current != null) 'current': current,
      if (surge != null) 'surge': surge,
      if (chill != null) 'chill': chill,
      if (airTempC != null) 'air_temp_c': airTempC,
      if (waterTempC != null) 'water_temp_c': waterTempC,
      if (weightsJson != null) 'weights_json': weightsJson,
      if (displayDecoAlgorithm != null)
        'display_deco_algorithm': displayDecoAlgorithm,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveAnnotationsCompanion copyWith({
    Value<String>? diveId,
    Value<String?>? siteName,
    Value<int?>? siteLatitudeE5,
    Value<int?>? siteLongitudeE5,
    Value<String?>? notes,
    Value<String?>? buddiesJson,
    Value<String?>? tagsJson,
    Value<int?>? rating,
    Value<String?>? conditions,
    Value<String?>? divemaster,
    Value<int?>? visibility,
    Value<int?>? wavesize,
    Value<int?>? current,
    Value<int?>? surge,
    Value<int?>? chill,
    Value<double?>? airTempC,
    Value<double?>? waterTempC,
    Value<String?>? weightsJson,
    Value<String?>? displayDecoAlgorithm,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return DiveAnnotationsCompanion(
      diveId: diveId ?? this.diveId,
      siteName: siteName ?? this.siteName,
      siteLatitudeE5: siteLatitudeE5 ?? this.siteLatitudeE5,
      siteLongitudeE5: siteLongitudeE5 ?? this.siteLongitudeE5,
      notes: notes ?? this.notes,
      buddiesJson: buddiesJson ?? this.buddiesJson,
      tagsJson: tagsJson ?? this.tagsJson,
      rating: rating ?? this.rating,
      conditions: conditions ?? this.conditions,
      divemaster: divemaster ?? this.divemaster,
      visibility: visibility ?? this.visibility,
      wavesize: wavesize ?? this.wavesize,
      current: current ?? this.current,
      surge: surge ?? this.surge,
      chill: chill ?? this.chill,
      airTempC: airTempC ?? this.airTempC,
      waterTempC: waterTempC ?? this.waterTempC,
      weightsJson: weightsJson ?? this.weightsJson,
      displayDecoAlgorithm: displayDecoAlgorithm ?? this.displayDecoAlgorithm,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (siteName.present) {
      map['site_name'] = Variable<String>(siteName.value);
    }
    if (siteLatitudeE5.present) {
      map['site_latitude_e5'] = Variable<int>(siteLatitudeE5.value);
    }
    if (siteLongitudeE5.present) {
      map['site_longitude_e5'] = Variable<int>(siteLongitudeE5.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (buddiesJson.present) {
      map['buddies_json'] = Variable<String>(buddiesJson.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (conditions.present) {
      map['conditions'] = Variable<String>(conditions.value);
    }
    if (divemaster.present) {
      map['divemaster'] = Variable<String>(divemaster.value);
    }
    if (visibility.present) {
      map['visibility'] = Variable<int>(visibility.value);
    }
    if (wavesize.present) {
      map['wavesize'] = Variable<int>(wavesize.value);
    }
    if (current.present) {
      map['current'] = Variable<int>(current.value);
    }
    if (surge.present) {
      map['surge'] = Variable<int>(surge.value);
    }
    if (chill.present) {
      map['chill'] = Variable<int>(chill.value);
    }
    if (airTempC.present) {
      map['air_temp_c'] = Variable<double>(airTempC.value);
    }
    if (waterTempC.present) {
      map['water_temp_c'] = Variable<double>(waterTempC.value);
    }
    if (weightsJson.present) {
      map['weights_json'] = Variable<String>(weightsJson.value);
    }
    if (displayDecoAlgorithm.present) {
      map['display_deco_algorithm'] = Variable<String>(
        displayDecoAlgorithm.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveAnnotationsCompanion(')
          ..write('diveId: $diveId, ')
          ..write('siteName: $siteName, ')
          ..write('siteLatitudeE5: $siteLatitudeE5, ')
          ..write('siteLongitudeE5: $siteLongitudeE5, ')
          ..write('notes: $notes, ')
          ..write('buddiesJson: $buddiesJson, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('rating: $rating, ')
          ..write('conditions: $conditions, ')
          ..write('divemaster: $divemaster, ')
          ..write('visibility: $visibility, ')
          ..write('wavesize: $wavesize, ')
          ..write('current: $current, ')
          ..write('surge: $surge, ')
          ..write('chill: $chill, ')
          ..write('airTempC: $airTempC, ')
          ..write('waterTempC: $waterTempC, ')
          ..write('weightsJson: $weightsJson, ')
          ..write('displayDecoAlgorithm: $displayDecoAlgorithm, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveComputersTable extends DiveComputers
    with TableInfo<$DiveComputersTable, DiveComputer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveComputersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serialMeta = const VerificationMeta('serial');
  @override
  late final GeneratedColumn<int> serial = GeneratedColumn<int>(
    'serial',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<int> model = GeneratedColumn<int>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firmwareVersionMeta = const VerificationMeta(
    'firmwareVersion',
  );
  @override
  late final GeneratedColumn<int> firmwareVersion = GeneratedColumn<int>(
    'firmware_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serial,
    model,
    firmwareVersion,
    nickname,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_computers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveComputer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('serial')) {
      context.handle(
        _serialMeta,
        serial.isAcceptableOrUnknown(data['serial']!, _serialMeta),
      );
    } else if (isInserting) {
      context.missing(_serialMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('firmware_version')) {
      context.handle(
        _firmwareVersionMeta,
        firmwareVersion.isAcceptableOrUnknown(
          data['firmware_version']!,
          _firmwareVersionMeta,
        ),
      );
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiveComputer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveComputer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serial: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}serial'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}model'],
      )!,
      firmwareVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}firmware_version'],
      ),
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $DiveComputersTable createAlias(String alias) {
    return $DiveComputersTable(attachedDatabase, alias);
  }
}

class DiveComputer extends DataClass implements Insertable<DiveComputer> {
  final String id;
  final int serial;
  final int model;
  final int? firmwareVersion;
  final String? nickname;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const DiveComputer({
    required this.id,
    required this.serial,
    required this.model,
    this.firmwareVersion,
    this.nickname,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['serial'] = Variable<int>(serial);
    map['model'] = Variable<int>(model);
    if (!nullToAbsent || firmwareVersion != null) {
      map['firmware_version'] = Variable<int>(firmwareVersion);
    }
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  DiveComputersCompanion toCompanion(bool nullToAbsent) {
    return DiveComputersCompanion(
      id: Value(id),
      serial: Value(serial),
      model: Value(model),
      firmwareVersion: firmwareVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(firmwareVersion),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory DiveComputer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveComputer(
      id: serializer.fromJson<String>(json['id']),
      serial: serializer.fromJson<int>(json['serial']),
      model: serializer.fromJson<int>(json['model']),
      firmwareVersion: serializer.fromJson<int?>(json['firmwareVersion']),
      nickname: serializer.fromJson<String?>(json['nickname']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serial': serializer.toJson<int>(serial),
      'model': serializer.toJson<int>(model),
      'firmwareVersion': serializer.toJson<int?>(firmwareVersion),
      'nickname': serializer.toJson<String?>(nickname),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  DiveComputer copyWith({
    String? id,
    int? serial,
    int? model,
    Value<int?> firmwareVersion = const Value.absent(),
    Value<String?> nickname = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => DiveComputer(
    id: id ?? this.id,
    serial: serial ?? this.serial,
    model: model ?? this.model,
    firmwareVersion: firmwareVersion.present
        ? firmwareVersion.value
        : this.firmwareVersion,
    nickname: nickname.present ? nickname.value : this.nickname,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  DiveComputer copyWithCompanion(DiveComputersCompanion data) {
    return DiveComputer(
      id: data.id.present ? data.id.value : this.id,
      serial: data.serial.present ? data.serial.value : this.serial,
      model: data.model.present ? data.model.value : this.model,
      firmwareVersion: data.firmwareVersion.present
          ? data.firmwareVersion.value
          : this.firmwareVersion,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveComputer(')
          ..write('id: $id, ')
          ..write('serial: $serial, ')
          ..write('model: $model, ')
          ..write('firmwareVersion: $firmwareVersion, ')
          ..write('nickname: $nickname, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serial,
    model,
    firmwareVersion,
    nickname,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveComputer &&
          other.id == this.id &&
          other.serial == this.serial &&
          other.model == this.model &&
          other.firmwareVersion == this.firmwareVersion &&
          other.nickname == this.nickname &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class DiveComputersCompanion extends UpdateCompanion<DiveComputer> {
  final Value<String> id;
  final Value<int> serial;
  final Value<int> model;
  final Value<int?> firmwareVersion;
  final Value<String?> nickname;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const DiveComputersCompanion({
    this.id = const Value.absent(),
    this.serial = const Value.absent(),
    this.model = const Value.absent(),
    this.firmwareVersion = const Value.absent(),
    this.nickname = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveComputersCompanion.insert({
    required String id,
    required int serial,
    required int model,
    this.firmwareVersion = const Value.absent(),
    this.nickname = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       serial = Value(serial),
       model = Value(model),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DiveComputer> custom({
    Expression<String>? id,
    Expression<int>? serial,
    Expression<int>? model,
    Expression<int>? firmwareVersion,
    Expression<String>? nickname,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serial != null) 'serial': serial,
      if (model != null) 'model': model,
      if (firmwareVersion != null) 'firmware_version': firmwareVersion,
      if (nickname != null) 'nickname': nickname,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveComputersCompanion copyWith({
    Value<String>? id,
    Value<int>? serial,
    Value<int>? model,
    Value<int?>? firmwareVersion,
    Value<String?>? nickname,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return DiveComputersCompanion(
      id: id ?? this.id,
      serial: serial ?? this.serial,
      model: model ?? this.model,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      nickname: nickname ?? this.nickname,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serial.present) {
      map['serial'] = Variable<int>(serial.value);
    }
    if (model.present) {
      map['model'] = Variable<int>(model.value);
    }
    if (firmwareVersion.present) {
      map['firmware_version'] = Variable<int>(firmwareVersion.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveComputersCompanion(')
          ..write('id: $id, ')
          ..write('serial: $serial, ')
          ..write('model: $model, ')
          ..write('firmwareVersion: $firmwareVersion, ')
          ..write('nickname: $nickname, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OxygenCellsTable extends OxygenCells
    with TableInfo<$OxygenCellsTable, OxygenCell> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OxygenCellsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _installedDateMeta = const VerificationMeta(
    'installedDate',
  );
  @override
  late final GeneratedColumn<int> installedDate = GeneratedColumn<int>(
    'installed_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retiredDateMeta = const VerificationMeta(
    'retiredDate',
  );
  @override
  late final GeneratedColumn<int> retiredDate = GeneratedColumn<int>(
    'retired_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    slot,
    label,
    installedDate,
    retiredDate,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'oxygen_cells';
  @override
  VerificationContext validateIntegrity(
    Insertable<OxygenCell> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('installed_date')) {
      context.handle(
        _installedDateMeta,
        installedDate.isAcceptableOrUnknown(
          data['installed_date']!,
          _installedDateMeta,
        ),
      );
    }
    if (data.containsKey('retired_date')) {
      context.handle(
        _retiredDateMeta,
        retiredDate.isAcceptableOrUnknown(
          data['retired_date']!,
          _retiredDateMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OxygenCell map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OxygenCell(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      installedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}installed_date'],
      ),
      retiredDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retired_date'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $OxygenCellsTable createAlias(String alias) {
    return $OxygenCellsTable(attachedDatabase, alias);
  }
}

class OxygenCell extends DataClass implements Insertable<OxygenCell> {
  final String id;
  final int slot;
  final String? label;
  final int? installedDate;
  final int? retiredDate;
  final String? notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const OxygenCell({
    required this.id,
    required this.slot,
    this.label,
    this.installedDate,
    this.retiredDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['slot'] = Variable<int>(slot);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    if (!nullToAbsent || installedDate != null) {
      map['installed_date'] = Variable<int>(installedDate);
    }
    if (!nullToAbsent || retiredDate != null) {
      map['retired_date'] = Variable<int>(retiredDate);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  OxygenCellsCompanion toCompanion(bool nullToAbsent) {
    return OxygenCellsCompanion(
      id: Value(id),
      slot: Value(slot),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      installedDate: installedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(installedDate),
      retiredDate: retiredDate == null && nullToAbsent
          ? const Value.absent()
          : Value(retiredDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory OxygenCell.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OxygenCell(
      id: serializer.fromJson<String>(json['id']),
      slot: serializer.fromJson<int>(json['slot']),
      label: serializer.fromJson<String?>(json['label']),
      installedDate: serializer.fromJson<int?>(json['installedDate']),
      retiredDate: serializer.fromJson<int?>(json['retiredDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'slot': serializer.toJson<int>(slot),
      'label': serializer.toJson<String?>(label),
      'installedDate': serializer.toJson<int?>(installedDate),
      'retiredDate': serializer.toJson<int?>(retiredDate),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  OxygenCell copyWith({
    String? id,
    int? slot,
    Value<String?> label = const Value.absent(),
    Value<int?> installedDate = const Value.absent(),
    Value<int?> retiredDate = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => OxygenCell(
    id: id ?? this.id,
    slot: slot ?? this.slot,
    label: label.present ? label.value : this.label,
    installedDate: installedDate.present
        ? installedDate.value
        : this.installedDate,
    retiredDate: retiredDate.present ? retiredDate.value : this.retiredDate,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  OxygenCell copyWithCompanion(OxygenCellsCompanion data) {
    return OxygenCell(
      id: data.id.present ? data.id.value : this.id,
      slot: data.slot.present ? data.slot.value : this.slot,
      label: data.label.present ? data.label.value : this.label,
      installedDate: data.installedDate.present
          ? data.installedDate.value
          : this.installedDate,
      retiredDate: data.retiredDate.present
          ? data.retiredDate.value
          : this.retiredDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OxygenCell(')
          ..write('id: $id, ')
          ..write('slot: $slot, ')
          ..write('label: $label, ')
          ..write('installedDate: $installedDate, ')
          ..write('retiredDate: $retiredDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    slot,
    label,
    installedDate,
    retiredDate,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OxygenCell &&
          other.id == this.id &&
          other.slot == this.slot &&
          other.label == this.label &&
          other.installedDate == this.installedDate &&
          other.retiredDate == this.retiredDate &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class OxygenCellsCompanion extends UpdateCompanion<OxygenCell> {
  final Value<String> id;
  final Value<int> slot;
  final Value<String?> label;
  final Value<int?> installedDate;
  final Value<int?> retiredDate;
  final Value<String?> notes;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const OxygenCellsCompanion({
    this.id = const Value.absent(),
    this.slot = const Value.absent(),
    this.label = const Value.absent(),
    this.installedDate = const Value.absent(),
    this.retiredDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OxygenCellsCompanion.insert({
    required String id,
    required int slot,
    this.label = const Value.absent(),
    this.installedDate = const Value.absent(),
    this.retiredDate = const Value.absent(),
    this.notes = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       slot = Value(slot),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<OxygenCell> custom({
    Expression<String>? id,
    Expression<int>? slot,
    Expression<String>? label,
    Expression<int>? installedDate,
    Expression<int>? retiredDate,
    Expression<String>? notes,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (slot != null) 'slot': slot,
      if (label != null) 'label': label,
      if (installedDate != null) 'installed_date': installedDate,
      if (retiredDate != null) 'retired_date': retiredDate,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OxygenCellsCompanion copyWith({
    Value<String>? id,
    Value<int>? slot,
    Value<String?>? label,
    Value<int?>? installedDate,
    Value<int?>? retiredDate,
    Value<String?>? notes,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return OxygenCellsCompanion(
      id: id ?? this.id,
      slot: slot ?? this.slot,
      label: label ?? this.label,
      installedDate: installedDate ?? this.installedDate,
      retiredDate: retiredDate ?? this.retiredDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (installedDate.present) {
      map['installed_date'] = Variable<int>(installedDate.value);
    }
    if (retiredDate.present) {
      map['retired_date'] = Variable<int>(retiredDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OxygenCellsCompanion(')
          ..write('id: $id, ')
          ..write('slot: $slot, ')
          ..write('label: $label, ')
          ..write('installedDate: $installedDate, ')
          ..write('retiredDate: $retiredDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScrubberSessionsTable extends ScrubberSessions
    with TableInfo<$ScrubberSessionsTable, ScrubberSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScrubberSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedDateMeta = const VerificationMeta(
    'startedDate',
  );
  @override
  late final GeneratedColumn<int> startedDate = GeneratedColumn<int>(
    'started_date',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalMinutesMeta = const VerificationMeta(
    'totalMinutes',
  );
  @override
  late final GeneratedColumn<int> totalMinutes = GeneratedColumn<int>(
    'total_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startedDate,
    totalMinutes,
    mediaType,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scrubber_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScrubberSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('started_date')) {
      context.handle(
        _startedDateMeta,
        startedDate.isAcceptableOrUnknown(
          data['started_date']!,
          _startedDateMeta,
        ),
      );
    }
    if (data.containsKey('total_minutes')) {
      context.handle(
        _totalMinutesMeta,
        totalMinutes.isAcceptableOrUnknown(
          data['total_minutes']!,
          _totalMinutesMeta,
        ),
      );
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScrubberSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScrubberSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      startedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_date'],
      ),
      totalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_minutes'],
      ),
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $ScrubberSessionsTable createAlias(String alias) {
    return $ScrubberSessionsTable(attachedDatabase, alias);
  }
}

class ScrubberSession extends DataClass implements Insertable<ScrubberSession> {
  final String id;
  final int? startedDate;
  final int? totalMinutes;
  final String? mediaType;
  final String? notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const ScrubberSession({
    required this.id,
    this.startedDate,
    this.totalMinutes,
    this.mediaType,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || startedDate != null) {
      map['started_date'] = Variable<int>(startedDate);
    }
    if (!nullToAbsent || totalMinutes != null) {
      map['total_minutes'] = Variable<int>(totalMinutes);
    }
    if (!nullToAbsent || mediaType != null) {
      map['media_type'] = Variable<String>(mediaType);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  ScrubberSessionsCompanion toCompanion(bool nullToAbsent) {
    return ScrubberSessionsCompanion(
      id: Value(id),
      startedDate: startedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(startedDate),
      totalMinutes: totalMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalMinutes),
      mediaType: mediaType == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaType),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory ScrubberSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScrubberSession(
      id: serializer.fromJson<String>(json['id']),
      startedDate: serializer.fromJson<int?>(json['startedDate']),
      totalMinutes: serializer.fromJson<int?>(json['totalMinutes']),
      mediaType: serializer.fromJson<String?>(json['mediaType']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'startedDate': serializer.toJson<int?>(startedDate),
      'totalMinutes': serializer.toJson<int?>(totalMinutes),
      'mediaType': serializer.toJson<String?>(mediaType),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  ScrubberSession copyWith({
    String? id,
    Value<int?> startedDate = const Value.absent(),
    Value<int?> totalMinutes = const Value.absent(),
    Value<String?> mediaType = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => ScrubberSession(
    id: id ?? this.id,
    startedDate: startedDate.present ? startedDate.value : this.startedDate,
    totalMinutes: totalMinutes.present ? totalMinutes.value : this.totalMinutes,
    mediaType: mediaType.present ? mediaType.value : this.mediaType,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  ScrubberSession copyWithCompanion(ScrubberSessionsCompanion data) {
    return ScrubberSession(
      id: data.id.present ? data.id.value : this.id,
      startedDate: data.startedDate.present
          ? data.startedDate.value
          : this.startedDate,
      totalMinutes: data.totalMinutes.present
          ? data.totalMinutes.value
          : this.totalMinutes,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScrubberSession(')
          ..write('id: $id, ')
          ..write('startedDate: $startedDate, ')
          ..write('totalMinutes: $totalMinutes, ')
          ..write('mediaType: $mediaType, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    startedDate,
    totalMinutes,
    mediaType,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScrubberSession &&
          other.id == this.id &&
          other.startedDate == this.startedDate &&
          other.totalMinutes == this.totalMinutes &&
          other.mediaType == this.mediaType &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class ScrubberSessionsCompanion extends UpdateCompanion<ScrubberSession> {
  final Value<String> id;
  final Value<int?> startedDate;
  final Value<int?> totalMinutes;
  final Value<String?> mediaType;
  final Value<String?> notes;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const ScrubberSessionsCompanion({
    this.id = const Value.absent(),
    this.startedDate = const Value.absent(),
    this.totalMinutes = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScrubberSessionsCompanion.insert({
    required String id,
    this.startedDate = const Value.absent(),
    this.totalMinutes = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.notes = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ScrubberSession> custom({
    Expression<String>? id,
    Expression<int>? startedDate,
    Expression<int>? totalMinutes,
    Expression<String>? mediaType,
    Expression<String>? notes,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedDate != null) 'started_date': startedDate,
      if (totalMinutes != null) 'total_minutes': totalMinutes,
      if (mediaType != null) 'media_type': mediaType,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScrubberSessionsCompanion copyWith({
    Value<String>? id,
    Value<int?>? startedDate,
    Value<int?>? totalMinutes,
    Value<String?>? mediaType,
    Value<String?>? notes,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return ScrubberSessionsCompanion(
      id: id ?? this.id,
      startedDate: startedDate ?? this.startedDate,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      mediaType: mediaType ?? this.mediaType,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (startedDate.present) {
      map['started_date'] = Variable<int>(startedDate.value);
    }
    if (totalMinutes.present) {
      map['total_minutes'] = Variable<int>(totalMinutes.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScrubberSessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedDate: $startedDate, ')
          ..write('totalMinutes: $totalMinutes, ')
          ..write('mediaType: $mediaType, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CylindersTable extends Cylinders
    with TableInfo<$CylindersTable, Cylinder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CylindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bailoutOrderMeta = const VerificationMeta(
    'bailoutOrder',
  );
  @override
  late final GeneratedColumn<int> bailoutOrder = GeneratedColumn<int>(
    'bailout_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _volumeLitersMeta = const VerificationMeta(
    'volumeLiters',
  );
  @override
  late final GeneratedColumn<double> volumeLiters = GeneratedColumn<double>(
    'volume_liters',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workingPressureBarMeta =
      const VerificationMeta('workingPressureBar');
  @override
  late final GeneratedColumn<int> workingPressureBar = GeneratedColumn<int>(
    'working_pressure_bar',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    role,
    bailoutOrder,
    volumeLiters,
    workingPressureBar,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cylinders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Cylinder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('bailout_order')) {
      context.handle(
        _bailoutOrderMeta,
        bailoutOrder.isAcceptableOrUnknown(
          data['bailout_order']!,
          _bailoutOrderMeta,
        ),
      );
    }
    if (data.containsKey('volume_liters')) {
      context.handle(
        _volumeLitersMeta,
        volumeLiters.isAcceptableOrUnknown(
          data['volume_liters']!,
          _volumeLitersMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_volumeLitersMeta);
    }
    if (data.containsKey('working_pressure_bar')) {
      context.handle(
        _workingPressureBarMeta,
        workingPressureBar.isAcceptableOrUnknown(
          data['working_pressure_bar']!,
          _workingPressureBarMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workingPressureBarMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Cylinder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Cylinder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      bailoutOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bailout_order'],
      ),
      volumeLiters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume_liters'],
      )!,
      workingPressureBar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}working_pressure_bar'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $CylindersTable createAlias(String alias) {
    return $CylindersTable(attachedDatabase, alias);
  }
}

class Cylinder extends DataClass implements Insertable<Cylinder> {
  final String id;
  final String label;
  final String role;
  final int? bailoutOrder;
  final double volumeLiters;
  final int workingPressureBar;
  final String? notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const Cylinder({
    required this.id,
    required this.label,
    required this.role,
    this.bailoutOrder,
    required this.volumeLiters,
    required this.workingPressureBar,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || bailoutOrder != null) {
      map['bailout_order'] = Variable<int>(bailoutOrder);
    }
    map['volume_liters'] = Variable<double>(volumeLiters);
    map['working_pressure_bar'] = Variable<int>(workingPressureBar);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  CylindersCompanion toCompanion(bool nullToAbsent) {
    return CylindersCompanion(
      id: Value(id),
      label: Value(label),
      role: Value(role),
      bailoutOrder: bailoutOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(bailoutOrder),
      volumeLiters: Value(volumeLiters),
      workingPressureBar: Value(workingPressureBar),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory Cylinder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Cylinder(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      role: serializer.fromJson<String>(json['role']),
      bailoutOrder: serializer.fromJson<int?>(json['bailoutOrder']),
      volumeLiters: serializer.fromJson<double>(json['volumeLiters']),
      workingPressureBar: serializer.fromJson<int>(json['workingPressureBar']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'role': serializer.toJson<String>(role),
      'bailoutOrder': serializer.toJson<int?>(bailoutOrder),
      'volumeLiters': serializer.toJson<double>(volumeLiters),
      'workingPressureBar': serializer.toJson<int>(workingPressureBar),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  Cylinder copyWith({
    String? id,
    String? label,
    String? role,
    Value<int?> bailoutOrder = const Value.absent(),
    double? volumeLiters,
    int? workingPressureBar,
    Value<String?> notes = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => Cylinder(
    id: id ?? this.id,
    label: label ?? this.label,
    role: role ?? this.role,
    bailoutOrder: bailoutOrder.present ? bailoutOrder.value : this.bailoutOrder,
    volumeLiters: volumeLiters ?? this.volumeLiters,
    workingPressureBar: workingPressureBar ?? this.workingPressureBar,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  Cylinder copyWithCompanion(CylindersCompanion data) {
    return Cylinder(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      role: data.role.present ? data.role.value : this.role,
      bailoutOrder: data.bailoutOrder.present
          ? data.bailoutOrder.value
          : this.bailoutOrder,
      volumeLiters: data.volumeLiters.present
          ? data.volumeLiters.value
          : this.volumeLiters,
      workingPressureBar: data.workingPressureBar.present
          ? data.workingPressureBar.value
          : this.workingPressureBar,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Cylinder(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('role: $role, ')
          ..write('bailoutOrder: $bailoutOrder, ')
          ..write('volumeLiters: $volumeLiters, ')
          ..write('workingPressureBar: $workingPressureBar, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    role,
    bailoutOrder,
    volumeLiters,
    workingPressureBar,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Cylinder &&
          other.id == this.id &&
          other.label == this.label &&
          other.role == this.role &&
          other.bailoutOrder == this.bailoutOrder &&
          other.volumeLiters == this.volumeLiters &&
          other.workingPressureBar == this.workingPressureBar &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class CylindersCompanion extends UpdateCompanion<Cylinder> {
  final Value<String> id;
  final Value<String> label;
  final Value<String> role;
  final Value<int?> bailoutOrder;
  final Value<double> volumeLiters;
  final Value<int> workingPressureBar;
  final Value<String?> notes;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const CylindersCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.role = const Value.absent(),
    this.bailoutOrder = const Value.absent(),
    this.volumeLiters = const Value.absent(),
    this.workingPressureBar = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CylindersCompanion.insert({
    required String id,
    required String label,
    required String role,
    this.bailoutOrder = const Value.absent(),
    required double volumeLiters,
    required int workingPressureBar,
    this.notes = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       label = Value(label),
       role = Value(role),
       volumeLiters = Value(volumeLiters),
       workingPressureBar = Value(workingPressureBar),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Cylinder> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<String>? role,
    Expression<int>? bailoutOrder,
    Expression<double>? volumeLiters,
    Expression<int>? workingPressureBar,
    Expression<String>? notes,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (role != null) 'role': role,
      if (bailoutOrder != null) 'bailout_order': bailoutOrder,
      if (volumeLiters != null) 'volume_liters': volumeLiters,
      if (workingPressureBar != null)
        'working_pressure_bar': workingPressureBar,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CylindersCompanion copyWith({
    Value<String>? id,
    Value<String>? label,
    Value<String>? role,
    Value<int?>? bailoutOrder,
    Value<double>? volumeLiters,
    Value<int>? workingPressureBar,
    Value<String?>? notes,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return CylindersCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      role: role ?? this.role,
      bailoutOrder: bailoutOrder ?? this.bailoutOrder,
      volumeLiters: volumeLiters ?? this.volumeLiters,
      workingPressureBar: workingPressureBar ?? this.workingPressureBar,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (bailoutOrder.present) {
      map['bailout_order'] = Variable<int>(bailoutOrder.value);
    }
    if (volumeLiters.present) {
      map['volume_liters'] = Variable<double>(volumeLiters.value);
    }
    if (workingPressureBar.present) {
      map['working_pressure_bar'] = Variable<int>(workingPressureBar.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CylindersCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('role: $role, ')
          ..write('bailoutOrder: $bailoutOrder, ')
          ..write('volumeLiters: $volumeLiters, ')
          ..write('workingPressureBar: $workingPressureBar, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PressureMappingsTable extends PressureMappings
    with TableInfo<$PressureMappingsTable, PressureMapping> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PressureMappingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveComputerIdMeta = const VerificationMeta(
    'diveComputerId',
  );
  @override
  late final GeneratedColumn<String> diveComputerId = GeneratedColumn<String>(
    'dive_computer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelIndexMeta = const VerificationMeta(
    'channelIndex',
  );
  @override
  late final GeneratedColumn<int> channelIndex = GeneratedColumn<int>(
    'channel_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cylinderIdMeta = const VerificationMeta(
    'cylinderId',
  );
  @override
  late final GeneratedColumn<String> cylinderId = GeneratedColumn<String>(
    'cylinder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    diveComputerId,
    channelIndex,
    cylinderId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pressure_mappings';
  @override
  VerificationContext validateIntegrity(
    Insertable<PressureMapping> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_computer_id')) {
      context.handle(
        _diveComputerIdMeta,
        diveComputerId.isAcceptableOrUnknown(
          data['dive_computer_id']!,
          _diveComputerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_diveComputerIdMeta);
    }
    if (data.containsKey('channel_index')) {
      context.handle(
        _channelIndexMeta,
        channelIndex.isAcceptableOrUnknown(
          data['channel_index']!,
          _channelIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_channelIndexMeta);
    }
    if (data.containsKey('cylinder_id')) {
      context.handle(
        _cylinderIdMeta,
        cylinderId.isAcceptableOrUnknown(data['cylinder_id']!, _cylinderIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveComputerId, channelIndex};
  @override
  PressureMapping map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PressureMapping(
      diveComputerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_computer_id'],
      )!,
      channelIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}channel_index'],
      )!,
      cylinderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cylinder_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $PressureMappingsTable createAlias(String alias) {
    return $PressureMappingsTable(attachedDatabase, alias);
  }
}

class PressureMapping extends DataClass implements Insertable<PressureMapping> {
  final String diveComputerId;
  final int channelIndex;
  final String? cylinderId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const PressureMapping({
    required this.diveComputerId,
    required this.channelIndex,
    this.cylinderId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_computer_id'] = Variable<String>(diveComputerId);
    map['channel_index'] = Variable<int>(channelIndex);
    if (!nullToAbsent || cylinderId != null) {
      map['cylinder_id'] = Variable<String>(cylinderId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  PressureMappingsCompanion toCompanion(bool nullToAbsent) {
    return PressureMappingsCompanion(
      diveComputerId: Value(diveComputerId),
      channelIndex: Value(channelIndex),
      cylinderId: cylinderId == null && nullToAbsent
          ? const Value.absent()
          : Value(cylinderId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory PressureMapping.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PressureMapping(
      diveComputerId: serializer.fromJson<String>(json['diveComputerId']),
      channelIndex: serializer.fromJson<int>(json['channelIndex']),
      cylinderId: serializer.fromJson<String?>(json['cylinderId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveComputerId': serializer.toJson<String>(diveComputerId),
      'channelIndex': serializer.toJson<int>(channelIndex),
      'cylinderId': serializer.toJson<String?>(cylinderId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  PressureMapping copyWith({
    String? diveComputerId,
    int? channelIndex,
    Value<String?> cylinderId = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => PressureMapping(
    diveComputerId: diveComputerId ?? this.diveComputerId,
    channelIndex: channelIndex ?? this.channelIndex,
    cylinderId: cylinderId.present ? cylinderId.value : this.cylinderId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  PressureMapping copyWithCompanion(PressureMappingsCompanion data) {
    return PressureMapping(
      diveComputerId: data.diveComputerId.present
          ? data.diveComputerId.value
          : this.diveComputerId,
      channelIndex: data.channelIndex.present
          ? data.channelIndex.value
          : this.channelIndex,
      cylinderId: data.cylinderId.present
          ? data.cylinderId.value
          : this.cylinderId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PressureMapping(')
          ..write('diveComputerId: $diveComputerId, ')
          ..write('channelIndex: $channelIndex, ')
          ..write('cylinderId: $cylinderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    diveComputerId,
    channelIndex,
    cylinderId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PressureMapping &&
          other.diveComputerId == this.diveComputerId &&
          other.channelIndex == this.channelIndex &&
          other.cylinderId == this.cylinderId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class PressureMappingsCompanion extends UpdateCompanion<PressureMapping> {
  final Value<String> diveComputerId;
  final Value<int> channelIndex;
  final Value<String?> cylinderId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const PressureMappingsCompanion({
    this.diveComputerId = const Value.absent(),
    this.channelIndex = const Value.absent(),
    this.cylinderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PressureMappingsCompanion.insert({
    required String diveComputerId,
    required int channelIndex,
    this.cylinderId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : diveComputerId = Value(diveComputerId),
       channelIndex = Value(channelIndex),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PressureMapping> custom({
    Expression<String>? diveComputerId,
    Expression<int>? channelIndex,
    Expression<String>? cylinderId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveComputerId != null) 'dive_computer_id': diveComputerId,
      if (channelIndex != null) 'channel_index': channelIndex,
      if (cylinderId != null) 'cylinder_id': cylinderId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PressureMappingsCompanion copyWith({
    Value<String>? diveComputerId,
    Value<int>? channelIndex,
    Value<String?>? cylinderId,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return PressureMappingsCompanion(
      diveComputerId: diveComputerId ?? this.diveComputerId,
      channelIndex: channelIndex ?? this.channelIndex,
      cylinderId: cylinderId ?? this.cylinderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveComputerId.present) {
      map['dive_computer_id'] = Variable<String>(diveComputerId.value);
    }
    if (channelIndex.present) {
      map['channel_index'] = Variable<int>(channelIndex.value);
    }
    if (cylinderId.present) {
      map['cylinder_id'] = Variable<String>(cylinderId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PressureMappingsCompanion(')
          ..write('diveComputerId: $diveComputerId, ')
          ..write('channelIndex: $channelIndex, ')
          ..write('cylinderId: $cylinderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveCylindersTable extends DiveCylinders
    with TableInfo<$DiveCylindersTable, DiveCylinder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveCylindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dives (id)',
    ),
  );
  static const VerificationMeta _gasMixIndexMeta = const VerificationMeta(
    'gasMixIndex',
  );
  @override
  late final GeneratedColumn<int> gasMixIndex = GeneratedColumn<int>(
    'gas_mix_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cylinderIdMeta = const VerificationMeta(
    'cylinderId',
  );
  @override
  late final GeneratedColumn<String> cylinderId = GeneratedColumn<String>(
    'cylinder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    diveId,
    gasMixIndex,
    cylinderId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_cylinders';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveCylinder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('gas_mix_index')) {
      context.handle(
        _gasMixIndexMeta,
        gasMixIndex.isAcceptableOrUnknown(
          data['gas_mix_index']!,
          _gasMixIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_gasMixIndexMeta);
    }
    if (data.containsKey('cylinder_id')) {
      context.handle(
        _cylinderIdMeta,
        cylinderId.isAcceptableOrUnknown(data['cylinder_id']!, _cylinderIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveId, gasMixIndex};
  @override
  DiveCylinder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveCylinder(
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      gasMixIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gas_mix_index'],
      )!,
      cylinderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cylinder_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $DiveCylindersTable createAlias(String alias) {
    return $DiveCylindersTable(attachedDatabase, alias);
  }
}

class DiveCylinder extends DataClass implements Insertable<DiveCylinder> {
  final String diveId;
  final int gasMixIndex;
  final String? cylinderId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const DiveCylinder({
    required this.diveId,
    required this.gasMixIndex,
    this.cylinderId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_id'] = Variable<String>(diveId);
    map['gas_mix_index'] = Variable<int>(gasMixIndex);
    if (!nullToAbsent || cylinderId != null) {
      map['cylinder_id'] = Variable<String>(cylinderId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  DiveCylindersCompanion toCompanion(bool nullToAbsent) {
    return DiveCylindersCompanion(
      diveId: Value(diveId),
      gasMixIndex: Value(gasMixIndex),
      cylinderId: cylinderId == null && nullToAbsent
          ? const Value.absent()
          : Value(cylinderId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory DiveCylinder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveCylinder(
      diveId: serializer.fromJson<String>(json['diveId']),
      gasMixIndex: serializer.fromJson<int>(json['gasMixIndex']),
      cylinderId: serializer.fromJson<String?>(json['cylinderId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveId': serializer.toJson<String>(diveId),
      'gasMixIndex': serializer.toJson<int>(gasMixIndex),
      'cylinderId': serializer.toJson<String?>(cylinderId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  DiveCylinder copyWith({
    String? diveId,
    int? gasMixIndex,
    Value<String?> cylinderId = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => DiveCylinder(
    diveId: diveId ?? this.diveId,
    gasMixIndex: gasMixIndex ?? this.gasMixIndex,
    cylinderId: cylinderId.present ? cylinderId.value : this.cylinderId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  DiveCylinder copyWithCompanion(DiveCylindersCompanion data) {
    return DiveCylinder(
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      gasMixIndex: data.gasMixIndex.present
          ? data.gasMixIndex.value
          : this.gasMixIndex,
      cylinderId: data.cylinderId.present
          ? data.cylinderId.value
          : this.cylinderId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveCylinder(')
          ..write('diveId: $diveId, ')
          ..write('gasMixIndex: $gasMixIndex, ')
          ..write('cylinderId: $cylinderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    diveId,
    gasMixIndex,
    cylinderId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveCylinder &&
          other.diveId == this.diveId &&
          other.gasMixIndex == this.gasMixIndex &&
          other.cylinderId == this.cylinderId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class DiveCylindersCompanion extends UpdateCompanion<DiveCylinder> {
  final Value<String> diveId;
  final Value<int> gasMixIndex;
  final Value<String?> cylinderId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const DiveCylindersCompanion({
    this.diveId = const Value.absent(),
    this.gasMixIndex = const Value.absent(),
    this.cylinderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveCylindersCompanion.insert({
    required String diveId,
    required int gasMixIndex,
    this.cylinderId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : diveId = Value(diveId),
       gasMixIndex = Value(gasMixIndex),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DiveCylinder> custom({
    Expression<String>? diveId,
    Expression<int>? gasMixIndex,
    Expression<String>? cylinderId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveId != null) 'dive_id': diveId,
      if (gasMixIndex != null) 'gas_mix_index': gasMixIndex,
      if (cylinderId != null) 'cylinder_id': cylinderId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveCylindersCompanion copyWith({
    Value<String>? diveId,
    Value<int>? gasMixIndex,
    Value<String?>? cylinderId,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return DiveCylindersCompanion(
      diveId: diveId ?? this.diveId,
      gasMixIndex: gasMixIndex ?? this.gasMixIndex,
      cylinderId: cylinderId ?? this.cylinderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (gasMixIndex.present) {
      map['gas_mix_index'] = Variable<int>(gasMixIndex.value);
    }
    if (cylinderId.present) {
      map['cylinder_id'] = Variable<String>(cylinderId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveCylindersCompanion(')
          ..write('diveId: $diveId, ')
          ..write('gasMixIndex: $gasMixIndex, ')
          ..write('cylinderId: $cylinderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DivePlansTable extends DivePlans
    with TableInfo<$DivePlansTable, DivePlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DivePlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gasesJsonMeta = const VerificationMeta(
    'gasesJson',
  );
  @override
  late final GeneratedColumn<String> gasesJson = GeneratedColumn<String>(
    'gases_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _segmentsJsonMeta = const VerificationMeta(
    'segmentsJson',
  );
  @override
  late final GeneratedColumn<String> segmentsJson = GeneratedColumn<String>(
    'segments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bailoutJsonMeta = const VerificationMeta(
    'bailoutJson',
  );
  @override
  late final GeneratedColumn<String> bailoutJson = GeneratedColumn<String>(
    'bailout_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settingsJsonMeta = const VerificationMeta(
    'settingsJson',
  );
  @override
  late final GeneratedColumn<String> settingsJson = GeneratedColumn<String>(
    'settings_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    mode,
    gasesJson,
    segmentsJson,
    bailoutJson,
    settingsJson,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<DivePlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('gases_json')) {
      context.handle(
        _gasesJsonMeta,
        gasesJson.isAcceptableOrUnknown(data['gases_json']!, _gasesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_gasesJsonMeta);
    }
    if (data.containsKey('segments_json')) {
      context.handle(
        _segmentsJsonMeta,
        segmentsJson.isAcceptableOrUnknown(
          data['segments_json']!,
          _segmentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_segmentsJsonMeta);
    }
    if (data.containsKey('bailout_json')) {
      context.handle(
        _bailoutJsonMeta,
        bailoutJson.isAcceptableOrUnknown(
          data['bailout_json']!,
          _bailoutJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bailoutJsonMeta);
    }
    if (data.containsKey('settings_json')) {
      context.handle(
        _settingsJsonMeta,
        settingsJson.isAcceptableOrUnknown(
          data['settings_json']!,
          _settingsJsonMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DivePlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DivePlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      gasesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gases_json'],
      )!,
      segmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}segments_json'],
      )!,
      bailoutJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bailout_json'],
      )!,
      settingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings_json'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $DivePlansTable createAlias(String alias) {
    return $DivePlansTable(attachedDatabase, alias);
  }
}

class DivePlan extends DataClass implements Insertable<DivePlan> {
  final String id;
  final String? name;
  final String mode;
  final String gasesJson;
  final String segmentsJson;
  final String bailoutJson;
  final String? settingsJson;
  final String? notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const DivePlan({
    required this.id,
    this.name,
    required this.mode,
    required this.gasesJson,
    required this.segmentsJson,
    required this.bailoutJson,
    this.settingsJson,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['mode'] = Variable<String>(mode);
    map['gases_json'] = Variable<String>(gasesJson);
    map['segments_json'] = Variable<String>(segmentsJson);
    map['bailout_json'] = Variable<String>(bailoutJson);
    if (!nullToAbsent || settingsJson != null) {
      map['settings_json'] = Variable<String>(settingsJson);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  DivePlansCompanion toCompanion(bool nullToAbsent) {
    return DivePlansCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      mode: Value(mode),
      gasesJson: Value(gasesJson),
      segmentsJson: Value(segmentsJson),
      bailoutJson: Value(bailoutJson),
      settingsJson: settingsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(settingsJson),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory DivePlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DivePlan(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      mode: serializer.fromJson<String>(json['mode']),
      gasesJson: serializer.fromJson<String>(json['gasesJson']),
      segmentsJson: serializer.fromJson<String>(json['segmentsJson']),
      bailoutJson: serializer.fromJson<String>(json['bailoutJson']),
      settingsJson: serializer.fromJson<String?>(json['settingsJson']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String?>(name),
      'mode': serializer.toJson<String>(mode),
      'gasesJson': serializer.toJson<String>(gasesJson),
      'segmentsJson': serializer.toJson<String>(segmentsJson),
      'bailoutJson': serializer.toJson<String>(bailoutJson),
      'settingsJson': serializer.toJson<String?>(settingsJson),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  DivePlan copyWith({
    String? id,
    Value<String?> name = const Value.absent(),
    String? mode,
    String? gasesJson,
    String? segmentsJson,
    String? bailoutJson,
    Value<String?> settingsJson = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => DivePlan(
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    mode: mode ?? this.mode,
    gasesJson: gasesJson ?? this.gasesJson,
    segmentsJson: segmentsJson ?? this.segmentsJson,
    bailoutJson: bailoutJson ?? this.bailoutJson,
    settingsJson: settingsJson.present ? settingsJson.value : this.settingsJson,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  DivePlan copyWithCompanion(DivePlansCompanion data) {
    return DivePlan(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      mode: data.mode.present ? data.mode.value : this.mode,
      gasesJson: data.gasesJson.present ? data.gasesJson.value : this.gasesJson,
      segmentsJson: data.segmentsJson.present
          ? data.segmentsJson.value
          : this.segmentsJson,
      bailoutJson: data.bailoutJson.present
          ? data.bailoutJson.value
          : this.bailoutJson,
      settingsJson: data.settingsJson.present
          ? data.settingsJson.value
          : this.settingsJson,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DivePlan(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('mode: $mode, ')
          ..write('gasesJson: $gasesJson, ')
          ..write('segmentsJson: $segmentsJson, ')
          ..write('bailoutJson: $bailoutJson, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    mode,
    gasesJson,
    segmentsJson,
    bailoutJson,
    settingsJson,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DivePlan &&
          other.id == this.id &&
          other.name == this.name &&
          other.mode == this.mode &&
          other.gasesJson == this.gasesJson &&
          other.segmentsJson == this.segmentsJson &&
          other.bailoutJson == this.bailoutJson &&
          other.settingsJson == this.settingsJson &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class DivePlansCompanion extends UpdateCompanion<DivePlan> {
  final Value<String> id;
  final Value<String?> name;
  final Value<String> mode;
  final Value<String> gasesJson;
  final Value<String> segmentsJson;
  final Value<String> bailoutJson;
  final Value<String?> settingsJson;
  final Value<String?> notes;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const DivePlansCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.mode = const Value.absent(),
    this.gasesJson = const Value.absent(),
    this.segmentsJson = const Value.absent(),
    this.bailoutJson = const Value.absent(),
    this.settingsJson = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DivePlansCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    required String mode,
    required String gasesJson,
    required String segmentsJson,
    required String bailoutJson,
    this.settingsJson = const Value.absent(),
    this.notes = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mode = Value(mode),
       gasesJson = Value(gasesJson),
       segmentsJson = Value(segmentsJson),
       bailoutJson = Value(bailoutJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DivePlan> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? mode,
    Expression<String>? gasesJson,
    Expression<String>? segmentsJson,
    Expression<String>? bailoutJson,
    Expression<String>? settingsJson,
    Expression<String>? notes,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (mode != null) 'mode': mode,
      if (gasesJson != null) 'gases_json': gasesJson,
      if (segmentsJson != null) 'segments_json': segmentsJson,
      if (bailoutJson != null) 'bailout_json': bailoutJson,
      if (settingsJson != null) 'settings_json': settingsJson,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DivePlansCompanion copyWith({
    Value<String>? id,
    Value<String?>? name,
    Value<String>? mode,
    Value<String>? gasesJson,
    Value<String>? segmentsJson,
    Value<String>? bailoutJson,
    Value<String?>? settingsJson,
    Value<String?>? notes,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return DivePlansCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      mode: mode ?? this.mode,
      gasesJson: gasesJson ?? this.gasesJson,
      segmentsJson: segmentsJson ?? this.segmentsJson,
      bailoutJson: bailoutJson ?? this.bailoutJson,
      settingsJson: settingsJson ?? this.settingsJson,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (gasesJson.present) {
      map['gases_json'] = Variable<String>(gasesJson.value);
    }
    if (segmentsJson.present) {
      map['segments_json'] = Variable<String>(segmentsJson.value);
    }
    if (bailoutJson.present) {
      map['bailout_json'] = Variable<String>(bailoutJson.value);
    }
    if (settingsJson.present) {
      map['settings_json'] = Variable<String>(settingsJson.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DivePlansCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('mode: $mode, ')
          ..write('gasesJson: $gasesJson, ')
          ..write('segmentsJson: $segmentsJson, ')
          ..write('bailoutJson: $bailoutJson, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveBailoutCarryTable extends DiveBailoutCarry
    with TableInfo<$DiveBailoutCarryTable, DiveBailoutCarryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveBailoutCarryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dives (id)',
    ),
  );
  static const VerificationMeta _cylinderIdMeta = const VerificationMeta(
    'cylinderId',
  );
  @override
  late final GeneratedColumn<String> cylinderId = GeneratedColumn<String>(
    'cylinder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES cylinders (id)',
    ),
  );
  static const VerificationMeta _gasMixMeta = const VerificationMeta('gasMix');
  @override
  late final GeneratedColumn<String> gasMix = GeneratedColumn<String>(
    'gas_mix',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fillPressureBarMeta = const VerificationMeta(
    'fillPressureBar',
  );
  @override
  late final GeneratedColumn<int> fillPressureBar = GeneratedColumn<int>(
    'fill_pressure_bar',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bailoutOrderMeta = const VerificationMeta(
    'bailoutOrder',
  );
  @override
  late final GeneratedColumn<int> bailoutOrder = GeneratedColumn<int>(
    'bailout_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    diveId,
    cylinderId,
    gasMix,
    fillPressureBar,
    bailoutOrder,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_bailout_carry';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveBailoutCarryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('cylinder_id')) {
      context.handle(
        _cylinderIdMeta,
        cylinderId.isAcceptableOrUnknown(data['cylinder_id']!, _cylinderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cylinderIdMeta);
    }
    if (data.containsKey('gas_mix')) {
      context.handle(
        _gasMixMeta,
        gasMix.isAcceptableOrUnknown(data['gas_mix']!, _gasMixMeta),
      );
    } else if (isInserting) {
      context.missing(_gasMixMeta);
    }
    if (data.containsKey('fill_pressure_bar')) {
      context.handle(
        _fillPressureBarMeta,
        fillPressureBar.isAcceptableOrUnknown(
          data['fill_pressure_bar']!,
          _fillPressureBarMeta,
        ),
      );
    }
    if (data.containsKey('bailout_order')) {
      context.handle(
        _bailoutOrderMeta,
        bailoutOrder.isAcceptableOrUnknown(
          data['bailout_order']!,
          _bailoutOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bailoutOrderMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiveBailoutCarryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveBailoutCarryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      cylinderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cylinder_id'],
      )!,
      gasMix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gas_mix'],
      )!,
      fillPressureBar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fill_pressure_bar'],
      ),
      bailoutOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bailout_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $DiveBailoutCarryTable createAlias(String alias) {
    return $DiveBailoutCarryTable(attachedDatabase, alias);
  }
}

class DiveBailoutCarryData extends DataClass
    implements Insertable<DiveBailoutCarryData> {
  final String id;
  final String diveId;
  final String cylinderId;
  final String gasMix;
  final int? fillPressureBar;
  final int bailoutOrder;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const DiveBailoutCarryData({
    required this.id,
    required this.diveId,
    required this.cylinderId,
    required this.gasMix,
    this.fillPressureBar,
    required this.bailoutOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['dive_id'] = Variable<String>(diveId);
    map['cylinder_id'] = Variable<String>(cylinderId);
    map['gas_mix'] = Variable<String>(gasMix);
    if (!nullToAbsent || fillPressureBar != null) {
      map['fill_pressure_bar'] = Variable<int>(fillPressureBar);
    }
    map['bailout_order'] = Variable<int>(bailoutOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  DiveBailoutCarryCompanion toCompanion(bool nullToAbsent) {
    return DiveBailoutCarryCompanion(
      id: Value(id),
      diveId: Value(diveId),
      cylinderId: Value(cylinderId),
      gasMix: Value(gasMix),
      fillPressureBar: fillPressureBar == null && nullToAbsent
          ? const Value.absent()
          : Value(fillPressureBar),
      bailoutOrder: Value(bailoutOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory DiveBailoutCarryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveBailoutCarryData(
      id: serializer.fromJson<String>(json['id']),
      diveId: serializer.fromJson<String>(json['diveId']),
      cylinderId: serializer.fromJson<String>(json['cylinderId']),
      gasMix: serializer.fromJson<String>(json['gasMix']),
      fillPressureBar: serializer.fromJson<int?>(json['fillPressureBar']),
      bailoutOrder: serializer.fromJson<int>(json['bailoutOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'diveId': serializer.toJson<String>(diveId),
      'cylinderId': serializer.toJson<String>(cylinderId),
      'gasMix': serializer.toJson<String>(gasMix),
      'fillPressureBar': serializer.toJson<int?>(fillPressureBar),
      'bailoutOrder': serializer.toJson<int>(bailoutOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  DiveBailoutCarryData copyWith({
    String? id,
    String? diveId,
    String? cylinderId,
    String? gasMix,
    Value<int?> fillPressureBar = const Value.absent(),
    int? bailoutOrder,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => DiveBailoutCarryData(
    id: id ?? this.id,
    diveId: diveId ?? this.diveId,
    cylinderId: cylinderId ?? this.cylinderId,
    gasMix: gasMix ?? this.gasMix,
    fillPressureBar: fillPressureBar.present
        ? fillPressureBar.value
        : this.fillPressureBar,
    bailoutOrder: bailoutOrder ?? this.bailoutOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  DiveBailoutCarryData copyWithCompanion(DiveBailoutCarryCompanion data) {
    return DiveBailoutCarryData(
      id: data.id.present ? data.id.value : this.id,
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      cylinderId: data.cylinderId.present
          ? data.cylinderId.value
          : this.cylinderId,
      gasMix: data.gasMix.present ? data.gasMix.value : this.gasMix,
      fillPressureBar: data.fillPressureBar.present
          ? data.fillPressureBar.value
          : this.fillPressureBar,
      bailoutOrder: data.bailoutOrder.present
          ? data.bailoutOrder.value
          : this.bailoutOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveBailoutCarryData(')
          ..write('id: $id, ')
          ..write('diveId: $diveId, ')
          ..write('cylinderId: $cylinderId, ')
          ..write('gasMix: $gasMix, ')
          ..write('fillPressureBar: $fillPressureBar, ')
          ..write('bailoutOrder: $bailoutOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    diveId,
    cylinderId,
    gasMix,
    fillPressureBar,
    bailoutOrder,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveBailoutCarryData &&
          other.id == this.id &&
          other.diveId == this.diveId &&
          other.cylinderId == this.cylinderId &&
          other.gasMix == this.gasMix &&
          other.fillPressureBar == this.fillPressureBar &&
          other.bailoutOrder == this.bailoutOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class DiveBailoutCarryCompanion extends UpdateCompanion<DiveBailoutCarryData> {
  final Value<String> id;
  final Value<String> diveId;
  final Value<String> cylinderId;
  final Value<String> gasMix;
  final Value<int?> fillPressureBar;
  final Value<int> bailoutOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const DiveBailoutCarryCompanion({
    this.id = const Value.absent(),
    this.diveId = const Value.absent(),
    this.cylinderId = const Value.absent(),
    this.gasMix = const Value.absent(),
    this.fillPressureBar = const Value.absent(),
    this.bailoutOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveBailoutCarryCompanion.insert({
    required String id,
    required String diveId,
    required String cylinderId,
    required String gasMix,
    this.fillPressureBar = const Value.absent(),
    required int bailoutOrder,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       diveId = Value(diveId),
       cylinderId = Value(cylinderId),
       gasMix = Value(gasMix),
       bailoutOrder = Value(bailoutOrder),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DiveBailoutCarryData> custom({
    Expression<String>? id,
    Expression<String>? diveId,
    Expression<String>? cylinderId,
    Expression<String>? gasMix,
    Expression<int>? fillPressureBar,
    Expression<int>? bailoutOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (diveId != null) 'dive_id': diveId,
      if (cylinderId != null) 'cylinder_id': cylinderId,
      if (gasMix != null) 'gas_mix': gasMix,
      if (fillPressureBar != null) 'fill_pressure_bar': fillPressureBar,
      if (bailoutOrder != null) 'bailout_order': bailoutOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveBailoutCarryCompanion copyWith({
    Value<String>? id,
    Value<String>? diveId,
    Value<String>? cylinderId,
    Value<String>? gasMix,
    Value<int?>? fillPressureBar,
    Value<int>? bailoutOrder,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return DiveBailoutCarryCompanion(
      id: id ?? this.id,
      diveId: diveId ?? this.diveId,
      cylinderId: cylinderId ?? this.cylinderId,
      gasMix: gasMix ?? this.gasMix,
      fillPressureBar: fillPressureBar ?? this.fillPressureBar,
      bailoutOrder: bailoutOrder ?? this.bailoutOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (cylinderId.present) {
      map['cylinder_id'] = Variable<String>(cylinderId.value);
    }
    if (gasMix.present) {
      map['gas_mix'] = Variable<String>(gasMix.value);
    }
    if (fillPressureBar.present) {
      map['fill_pressure_bar'] = Variable<int>(fillPressureBar.value);
    }
    if (bailoutOrder.present) {
      map['bailout_order'] = Variable<int>(bailoutOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveBailoutCarryCompanion(')
          ..write('id: $id, ')
          ..write('diveId: $diveId, ')
          ..write('cylinderId: $cylinderId, ')
          ..write('gasMix: $gasMix, ')
          ..write('fillPressureBar: $fillPressureBar, ')
          ..write('bailoutOrder: $bailoutOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportStatesTable extends ImportStates
    with TableInfo<$ImportStatesTable, ImportState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dcSerialMeta = const VerificationMeta(
    'dcSerial',
  );
  @override
  late final GeneratedColumn<String> dcSerial = GeneratedColumn<String>(
    'dc_serial',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastFingerprintMeta = const VerificationMeta(
    'lastFingerprint',
  );
  @override
  late final GeneratedColumn<Uint8List> lastFingerprint =
      GeneratedColumn<Uint8List>(
        'last_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastImportAtMeta = const VerificationMeta(
    'lastImportAt',
  );
  @override
  late final GeneratedColumn<int> lastImportAt = GeneratedColumn<int>(
    'last_import_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    dcSerial,
    lastFingerprint,
    lastImportAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dc_serial')) {
      context.handle(
        _dcSerialMeta,
        dcSerial.isAcceptableOrUnknown(data['dc_serial']!, _dcSerialMeta),
      );
    } else if (isInserting) {
      context.missing(_dcSerialMeta);
    }
    if (data.containsKey('last_fingerprint')) {
      context.handle(
        _lastFingerprintMeta,
        lastFingerprint.isAcceptableOrUnknown(
          data['last_fingerprint']!,
          _lastFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('last_import_at')) {
      context.handle(
        _lastImportAtMeta,
        lastImportAt.isAcceptableOrUnknown(
          data['last_import_at']!,
          _lastImportAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dcSerial};
  @override
  ImportState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportState(
      dcSerial: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dc_serial'],
      )!,
      lastFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}last_fingerprint'],
      ),
      lastImportAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_import_at'],
      ),
    );
  }

  @override
  $ImportStatesTable createAlias(String alias) {
    return $ImportStatesTable(attachedDatabase, alias);
  }
}

class ImportState extends DataClass implements Insertable<ImportState> {
  /// Dive computer serial as string.
  final String dcSerial;

  /// Last successfully imported dive fingerprint (4 bytes).
  final Uint8List? lastFingerprint;

  /// When the last import happened.
  final int? lastImportAt;
  const ImportState({
    required this.dcSerial,
    this.lastFingerprint,
    this.lastImportAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dc_serial'] = Variable<String>(dcSerial);
    if (!nullToAbsent || lastFingerprint != null) {
      map['last_fingerprint'] = Variable<Uint8List>(lastFingerprint);
    }
    if (!nullToAbsent || lastImportAt != null) {
      map['last_import_at'] = Variable<int>(lastImportAt);
    }
    return map;
  }

  ImportStatesCompanion toCompanion(bool nullToAbsent) {
    return ImportStatesCompanion(
      dcSerial: Value(dcSerial),
      lastFingerprint: lastFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFingerprint),
      lastImportAt: lastImportAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastImportAt),
    );
  }

  factory ImportState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportState(
      dcSerial: serializer.fromJson<String>(json['dcSerial']),
      lastFingerprint: serializer.fromJson<Uint8List?>(json['lastFingerprint']),
      lastImportAt: serializer.fromJson<int?>(json['lastImportAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dcSerial': serializer.toJson<String>(dcSerial),
      'lastFingerprint': serializer.toJson<Uint8List?>(lastFingerprint),
      'lastImportAt': serializer.toJson<int?>(lastImportAt),
    };
  }

  ImportState copyWith({
    String? dcSerial,
    Value<Uint8List?> lastFingerprint = const Value.absent(),
    Value<int?> lastImportAt = const Value.absent(),
  }) => ImportState(
    dcSerial: dcSerial ?? this.dcSerial,
    lastFingerprint: lastFingerprint.present
        ? lastFingerprint.value
        : this.lastFingerprint,
    lastImportAt: lastImportAt.present ? lastImportAt.value : this.lastImportAt,
  );
  ImportState copyWithCompanion(ImportStatesCompanion data) {
    return ImportState(
      dcSerial: data.dcSerial.present ? data.dcSerial.value : this.dcSerial,
      lastFingerprint: data.lastFingerprint.present
          ? data.lastFingerprint.value
          : this.lastFingerprint,
      lastImportAt: data.lastImportAt.present
          ? data.lastImportAt.value
          : this.lastImportAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportState(')
          ..write('dcSerial: $dcSerial, ')
          ..write('lastFingerprint: $lastFingerprint, ')
          ..write('lastImportAt: $lastImportAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    dcSerial,
    $driftBlobEquality.hash(lastFingerprint),
    lastImportAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportState &&
          other.dcSerial == this.dcSerial &&
          $driftBlobEquality.equals(
            other.lastFingerprint,
            this.lastFingerprint,
          ) &&
          other.lastImportAt == this.lastImportAt);
}

class ImportStatesCompanion extends UpdateCompanion<ImportState> {
  final Value<String> dcSerial;
  final Value<Uint8List?> lastFingerprint;
  final Value<int?> lastImportAt;
  final Value<int> rowid;
  const ImportStatesCompanion({
    this.dcSerial = const Value.absent(),
    this.lastFingerprint = const Value.absent(),
    this.lastImportAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportStatesCompanion.insert({
    required String dcSerial,
    this.lastFingerprint = const Value.absent(),
    this.lastImportAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : dcSerial = Value(dcSerial);
  static Insertable<ImportState> custom({
    Expression<String>? dcSerial,
    Expression<Uint8List>? lastFingerprint,
    Expression<int>? lastImportAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dcSerial != null) 'dc_serial': dcSerial,
      if (lastFingerprint != null) 'last_fingerprint': lastFingerprint,
      if (lastImportAt != null) 'last_import_at': lastImportAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportStatesCompanion copyWith({
    Value<String>? dcSerial,
    Value<Uint8List?>? lastFingerprint,
    Value<int?>? lastImportAt,
    Value<int>? rowid,
  }) {
    return ImportStatesCompanion(
      dcSerial: dcSerial ?? this.dcSerial,
      lastFingerprint: lastFingerprint ?? this.lastFingerprint,
      lastImportAt: lastImportAt ?? this.lastImportAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dcSerial.present) {
      map['dc_serial'] = Variable<String>(dcSerial.value);
    }
    if (lastFingerprint.present) {
      map['last_fingerprint'] = Variable<Uint8List>(lastFingerprint.value);
    }
    if (lastImportAt.present) {
      map['last_import_at'] = Variable<int>(lastImportAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportStatesCompanion(')
          ..write('dcSerial: $dcSerial, ')
          ..write('lastFingerprint: $lastFingerprint, ')
          ..write('lastImportAt: $lastImportAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiveMergeLinksTable extends DiveMergeLinks
    with TableInfo<$DiveMergeLinksTable, DiveMergeLink> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveMergeLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES dives (id)',
    ),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    diveId,
    groupId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_merge_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveMergeLink> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveId};
  @override
  DiveMergeLink map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveMergeLink(
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $DiveMergeLinksTable createAlias(String alias) {
    return $DiveMergeLinksTable(attachedDatabase, alias);
  }
}

class DiveMergeLink extends DataClass implements Insertable<DiveMergeLink> {
  final String diveId;
  final String groupId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  final String? ownerId;
  const DiveMergeLink({
    required this.diveId,
    required this.groupId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_id'] = Variable<String>(diveId);
    map['group_id'] = Variable<String>(groupId);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  DiveMergeLinksCompanion toCompanion(bool nullToAbsent) {
    return DiveMergeLinksCompanion(
      diveId: Value(diveId),
      groupId: Value(groupId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory DiveMergeLink.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveMergeLink(
      diveId: serializer.fromJson<String>(json['diveId']),
      groupId: serializer.fromJson<String>(json['groupId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveId': serializer.toJson<String>(diveId),
      'groupId': serializer.toJson<String>(groupId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  DiveMergeLink copyWith({
    String? diveId,
    String? groupId,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
    Value<String?> ownerId = const Value.absent(),
  }) => DiveMergeLink(
    diveId: diveId ?? this.diveId,
    groupId: groupId ?? this.groupId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  DiveMergeLink copyWithCompanion(DiveMergeLinksCompanion data) {
    return DiveMergeLink(
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveMergeLink(')
          ..write('diveId: $diveId, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    diveId,
    groupId,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
    ownerId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveMergeLink &&
          other.diveId == this.diveId &&
          other.groupId == this.groupId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.ownerId == this.ownerId);
}

class DiveMergeLinksCompanion extends UpdateCompanion<DiveMergeLink> {
  final Value<String> diveId;
  final Value<String> groupId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const DiveMergeLinksCompanion({
    this.diveId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveMergeLinksCompanion.insert({
    required String diveId,
    required String groupId,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : diveId = Value(diveId),
       groupId = Value(groupId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DiveMergeLink> custom({
    Expression<String>? diveId,
    Expression<String>? groupId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveId != null) 'dive_id': diveId,
      if (groupId != null) 'group_id': groupId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveMergeLinksCompanion copyWith({
    Value<String>? diveId,
    Value<String>? groupId,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<String?>? ownerId,
    Value<int>? rowid,
  }) {
    return DiveMergeLinksCompanion(
      diveId: diveId ?? this.diveId,
      groupId: groupId ?? this.groupId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveMergeLinksCompanion(')
          ..write('diveId: $diveId, ')
          ..write('groupId: $groupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQuarantineTable extends SyncQuarantine
    with TableInfo<$SyncQuarantineTable, SyncQuarantineData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQuarantineTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _opClientIdMeta = const VerificationMeta(
    'opClientId',
  );
  @override
  late final GeneratedColumn<int> opClientId = GeneratedColumn<int>(
    'op_client_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opTypeMeta = const VerificationMeta('opType');
  @override
  late final GeneratedColumn<String> opType = GeneratedColumn<String>(
    'op_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTableMeta = const VerificationMeta(
    'targetTable',
  );
  @override
  late final GeneratedColumn<String> targetTable = GeneratedColumn<String>(
    'target_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opDataMeta = const VerificationMeta('opData');
  @override
  late final GeneratedColumn<String> opData = GeneratedColumn<String>(
    'op_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quarantinedAtMeta = const VerificationMeta(
    'quarantinedAt',
  );
  @override
  late final GeneratedColumn<int> quarantinedAt = GeneratedColumn<int>(
    'quarantined_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    opClientId,
    opType,
    targetTable,
    rowId,
    opData,
    error,
    quarantinedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_quarantine';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQuarantineData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('op_client_id')) {
      context.handle(
        _opClientIdMeta,
        opClientId.isAcceptableOrUnknown(
          data['op_client_id']!,
          _opClientIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_opClientIdMeta);
    }
    if (data.containsKey('op_type')) {
      context.handle(
        _opTypeMeta,
        opType.isAcceptableOrUnknown(data['op_type']!, _opTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_opTypeMeta);
    }
    if (data.containsKey('target_table')) {
      context.handle(
        _targetTableMeta,
        targetTable.isAcceptableOrUnknown(
          data['target_table']!,
          _targetTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetTableMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('op_data')) {
      context.handle(
        _opDataMeta,
        opData.isAcceptableOrUnknown(data['op_data']!, _opDataMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    } else if (isInserting) {
      context.missing(_errorMeta);
    }
    if (data.containsKey('quarantined_at')) {
      context.handle(
        _quarantinedAtMeta,
        quarantinedAt.isAcceptableOrUnknown(
          data['quarantined_at']!,
          _quarantinedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quarantinedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQuarantineData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQuarantineData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      opClientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}op_client_id'],
      )!,
      opType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_type'],
      )!,
      targetTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_table'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      opData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_data'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      )!,
      quarantinedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quarantined_at'],
      )!,
    );
  }

  @override
  $SyncQuarantineTable createAlias(String alias) {
    return $SyncQuarantineTable(attachedDatabase, alias);
  }
}

class SyncQuarantineData extends DataClass
    implements Insertable<SyncQuarantineData> {
  /// Surrogate key — the same row id can be quarantined more than once.
  final int id;

  /// The op's PowerSync `CrudEntry.clientId`.
  final int opClientId;

  /// `put` / `patch` / `delete`.
  final String opType;

  /// The Postgres/PowerSync table the op targeted (named `targetTable` to
  /// avoid clashing with drift's built-in `Table.tableName`).
  final String targetTable;
  final String rowId;

  /// JSON of the op's payload (for a future re-drive); null for deletes.
  final String? opData;

  /// String form of the backend rejection that quarantined the op.
  final String error;

  /// When it was quarantined (epoch milliseconds).
  final int quarantinedAt;
  const SyncQuarantineData({
    required this.id,
    required this.opClientId,
    required this.opType,
    required this.targetTable,
    required this.rowId,
    this.opData,
    required this.error,
    required this.quarantinedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['op_client_id'] = Variable<int>(opClientId);
    map['op_type'] = Variable<String>(opType);
    map['target_table'] = Variable<String>(targetTable);
    map['row_id'] = Variable<String>(rowId);
    if (!nullToAbsent || opData != null) {
      map['op_data'] = Variable<String>(opData);
    }
    map['error'] = Variable<String>(error);
    map['quarantined_at'] = Variable<int>(quarantinedAt);
    return map;
  }

  SyncQuarantineCompanion toCompanion(bool nullToAbsent) {
    return SyncQuarantineCompanion(
      id: Value(id),
      opClientId: Value(opClientId),
      opType: Value(opType),
      targetTable: Value(targetTable),
      rowId: Value(rowId),
      opData: opData == null && nullToAbsent
          ? const Value.absent()
          : Value(opData),
      error: Value(error),
      quarantinedAt: Value(quarantinedAt),
    );
  }

  factory SyncQuarantineData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQuarantineData(
      id: serializer.fromJson<int>(json['id']),
      opClientId: serializer.fromJson<int>(json['opClientId']),
      opType: serializer.fromJson<String>(json['opType']),
      targetTable: serializer.fromJson<String>(json['targetTable']),
      rowId: serializer.fromJson<String>(json['rowId']),
      opData: serializer.fromJson<String?>(json['opData']),
      error: serializer.fromJson<String>(json['error']),
      quarantinedAt: serializer.fromJson<int>(json['quarantinedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'opClientId': serializer.toJson<int>(opClientId),
      'opType': serializer.toJson<String>(opType),
      'targetTable': serializer.toJson<String>(targetTable),
      'rowId': serializer.toJson<String>(rowId),
      'opData': serializer.toJson<String?>(opData),
      'error': serializer.toJson<String>(error),
      'quarantinedAt': serializer.toJson<int>(quarantinedAt),
    };
  }

  SyncQuarantineData copyWith({
    int? id,
    int? opClientId,
    String? opType,
    String? targetTable,
    String? rowId,
    Value<String?> opData = const Value.absent(),
    String? error,
    int? quarantinedAt,
  }) => SyncQuarantineData(
    id: id ?? this.id,
    opClientId: opClientId ?? this.opClientId,
    opType: opType ?? this.opType,
    targetTable: targetTable ?? this.targetTable,
    rowId: rowId ?? this.rowId,
    opData: opData.present ? opData.value : this.opData,
    error: error ?? this.error,
    quarantinedAt: quarantinedAt ?? this.quarantinedAt,
  );
  SyncQuarantineData copyWithCompanion(SyncQuarantineCompanion data) {
    return SyncQuarantineData(
      id: data.id.present ? data.id.value : this.id,
      opClientId: data.opClientId.present
          ? data.opClientId.value
          : this.opClientId,
      opType: data.opType.present ? data.opType.value : this.opType,
      targetTable: data.targetTable.present
          ? data.targetTable.value
          : this.targetTable,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      opData: data.opData.present ? data.opData.value : this.opData,
      error: data.error.present ? data.error.value : this.error,
      quarantinedAt: data.quarantinedAt.present
          ? data.quarantinedAt.value
          : this.quarantinedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQuarantineData(')
          ..write('id: $id, ')
          ..write('opClientId: $opClientId, ')
          ..write('opType: $opType, ')
          ..write('targetTable: $targetTable, ')
          ..write('rowId: $rowId, ')
          ..write('opData: $opData, ')
          ..write('error: $error, ')
          ..write('quarantinedAt: $quarantinedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    opClientId,
    opType,
    targetTable,
    rowId,
    opData,
    error,
    quarantinedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQuarantineData &&
          other.id == this.id &&
          other.opClientId == this.opClientId &&
          other.opType == this.opType &&
          other.targetTable == this.targetTable &&
          other.rowId == this.rowId &&
          other.opData == this.opData &&
          other.error == this.error &&
          other.quarantinedAt == this.quarantinedAt);
}

class SyncQuarantineCompanion extends UpdateCompanion<SyncQuarantineData> {
  final Value<int> id;
  final Value<int> opClientId;
  final Value<String> opType;
  final Value<String> targetTable;
  final Value<String> rowId;
  final Value<String?> opData;
  final Value<String> error;
  final Value<int> quarantinedAt;
  const SyncQuarantineCompanion({
    this.id = const Value.absent(),
    this.opClientId = const Value.absent(),
    this.opType = const Value.absent(),
    this.targetTable = const Value.absent(),
    this.rowId = const Value.absent(),
    this.opData = const Value.absent(),
    this.error = const Value.absent(),
    this.quarantinedAt = const Value.absent(),
  });
  SyncQuarantineCompanion.insert({
    this.id = const Value.absent(),
    required int opClientId,
    required String opType,
    required String targetTable,
    required String rowId,
    this.opData = const Value.absent(),
    required String error,
    required int quarantinedAt,
  }) : opClientId = Value(opClientId),
       opType = Value(opType),
       targetTable = Value(targetTable),
       rowId = Value(rowId),
       error = Value(error),
       quarantinedAt = Value(quarantinedAt);
  static Insertable<SyncQuarantineData> custom({
    Expression<int>? id,
    Expression<int>? opClientId,
    Expression<String>? opType,
    Expression<String>? targetTable,
    Expression<String>? rowId,
    Expression<String>? opData,
    Expression<String>? error,
    Expression<int>? quarantinedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (opClientId != null) 'op_client_id': opClientId,
      if (opType != null) 'op_type': opType,
      if (targetTable != null) 'target_table': targetTable,
      if (rowId != null) 'row_id': rowId,
      if (opData != null) 'op_data': opData,
      if (error != null) 'error': error,
      if (quarantinedAt != null) 'quarantined_at': quarantinedAt,
    });
  }

  SyncQuarantineCompanion copyWith({
    Value<int>? id,
    Value<int>? opClientId,
    Value<String>? opType,
    Value<String>? targetTable,
    Value<String>? rowId,
    Value<String?>? opData,
    Value<String>? error,
    Value<int>? quarantinedAt,
  }) {
    return SyncQuarantineCompanion(
      id: id ?? this.id,
      opClientId: opClientId ?? this.opClientId,
      opType: opType ?? this.opType,
      targetTable: targetTable ?? this.targetTable,
      rowId: rowId ?? this.rowId,
      opData: opData ?? this.opData,
      error: error ?? this.error,
      quarantinedAt: quarantinedAt ?? this.quarantinedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (opClientId.present) {
      map['op_client_id'] = Variable<int>(opClientId.value);
    }
    if (opType.present) {
      map['op_type'] = Variable<String>(opType.value);
    }
    if (targetTable.present) {
      map['target_table'] = Variable<String>(targetTable.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (opData.present) {
      map['op_data'] = Variable<String>(opData.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (quarantinedAt.present) {
      map['quarantined_at'] = Variable<int>(quarantinedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQuarantineCompanion(')
          ..write('id: $id, ')
          ..write('opClientId: $opClientId, ')
          ..write('opType: $opType, ')
          ..write('targetTable: $targetTable, ')
          ..write('rowId: $rowId, ')
          ..write('opData: $opData, ')
          ..write('error: $error, ')
          ..write('quarantinedAt: $quarantinedAt')
          ..write(')'))
        .toString();
  }
}

class $DiveDerivedStatsTable extends DiveDerivedStats
    with TableInfo<$DiveDerivedStatsTable, DiveDerivedStat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiveDerivedStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diveIdMeta = const VerificationMeta('diveId');
  @override
  late final GeneratedColumn<String> diveId = GeneratedColumn<String>(
    'dive_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  @override
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minWaterTempCMeta = const VerificationMeta(
    'minWaterTempC',
  );
  @override
  late final GeneratedColumn<double> minWaterTempC = GeneratedColumn<double>(
    'min_water_temp_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxWaterTempCMeta = const VerificationMeta(
    'maxWaterTempC',
  );
  @override
  late final GeneratedColumn<double> maxWaterTempC = GeneratedColumn<double>(
    'max_water_temp_c',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeInDecoSecondsMeta = const VerificationMeta(
    'timeInDecoSeconds',
  );
  @override
  late final GeneratedColumn<int> timeInDecoSeconds = GeneratedColumn<int>(
    'time_in_deco_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    diveId,
    parserVersion,
    minWaterTempC,
    maxWaterTempC,
    timeInDecoSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dive_derived_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiveDerivedStat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('dive_id')) {
      context.handle(
        _diveIdMeta,
        diveId.isAcceptableOrUnknown(data['dive_id']!, _diveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diveIdMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('min_water_temp_c')) {
      context.handle(
        _minWaterTempCMeta,
        minWaterTempC.isAcceptableOrUnknown(
          data['min_water_temp_c']!,
          _minWaterTempCMeta,
        ),
      );
    }
    if (data.containsKey('max_water_temp_c')) {
      context.handle(
        _maxWaterTempCMeta,
        maxWaterTempC.isAcceptableOrUnknown(
          data['max_water_temp_c']!,
          _maxWaterTempCMeta,
        ),
      );
    }
    if (data.containsKey('time_in_deco_seconds')) {
      context.handle(
        _timeInDecoSecondsMeta,
        timeInDecoSeconds.isAcceptableOrUnknown(
          data['time_in_deco_seconds']!,
          _timeInDecoSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diveId};
  @override
  DiveDerivedStat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiveDerivedStat(
      diveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dive_id'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      minWaterTempC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_water_temp_c'],
      ),
      maxWaterTempC: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_water_temp_c'],
      ),
      timeInDecoSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_in_deco_seconds'],
      )!,
    );
  }

  @override
  $DiveDerivedStatsTable createAlias(String alias) {
    return $DiveDerivedStatsTable(attachedDatabase, alias);
  }
}

class DiveDerivedStat extends DataClass implements Insertable<DiveDerivedStat> {
  final String diveId;
  final int parserVersion;
  final double? minWaterTempC;
  final double? maxWaterTempC;
  final int timeInDecoSeconds;
  const DiveDerivedStat({
    required this.diveId,
    required this.parserVersion,
    this.minWaterTempC,
    this.maxWaterTempC,
    required this.timeInDecoSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['dive_id'] = Variable<String>(diveId);
    map['parser_version'] = Variable<int>(parserVersion);
    if (!nullToAbsent || minWaterTempC != null) {
      map['min_water_temp_c'] = Variable<double>(minWaterTempC);
    }
    if (!nullToAbsent || maxWaterTempC != null) {
      map['max_water_temp_c'] = Variable<double>(maxWaterTempC);
    }
    map['time_in_deco_seconds'] = Variable<int>(timeInDecoSeconds);
    return map;
  }

  DiveDerivedStatsCompanion toCompanion(bool nullToAbsent) {
    return DiveDerivedStatsCompanion(
      diveId: Value(diveId),
      parserVersion: Value(parserVersion),
      minWaterTempC: minWaterTempC == null && nullToAbsent
          ? const Value.absent()
          : Value(minWaterTempC),
      maxWaterTempC: maxWaterTempC == null && nullToAbsent
          ? const Value.absent()
          : Value(maxWaterTempC),
      timeInDecoSeconds: Value(timeInDecoSeconds),
    );
  }

  factory DiveDerivedStat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiveDerivedStat(
      diveId: serializer.fromJson<String>(json['diveId']),
      parserVersion: serializer.fromJson<int>(json['parserVersion']),
      minWaterTempC: serializer.fromJson<double?>(json['minWaterTempC']),
      maxWaterTempC: serializer.fromJson<double?>(json['maxWaterTempC']),
      timeInDecoSeconds: serializer.fromJson<int>(json['timeInDecoSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diveId': serializer.toJson<String>(diveId),
      'parserVersion': serializer.toJson<int>(parserVersion),
      'minWaterTempC': serializer.toJson<double?>(minWaterTempC),
      'maxWaterTempC': serializer.toJson<double?>(maxWaterTempC),
      'timeInDecoSeconds': serializer.toJson<int>(timeInDecoSeconds),
    };
  }

  DiveDerivedStat copyWith({
    String? diveId,
    int? parserVersion,
    Value<double?> minWaterTempC = const Value.absent(),
    Value<double?> maxWaterTempC = const Value.absent(),
    int? timeInDecoSeconds,
  }) => DiveDerivedStat(
    diveId: diveId ?? this.diveId,
    parserVersion: parserVersion ?? this.parserVersion,
    minWaterTempC: minWaterTempC.present
        ? minWaterTempC.value
        : this.minWaterTempC,
    maxWaterTempC: maxWaterTempC.present
        ? maxWaterTempC.value
        : this.maxWaterTempC,
    timeInDecoSeconds: timeInDecoSeconds ?? this.timeInDecoSeconds,
  );
  DiveDerivedStat copyWithCompanion(DiveDerivedStatsCompanion data) {
    return DiveDerivedStat(
      diveId: data.diveId.present ? data.diveId.value : this.diveId,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      minWaterTempC: data.minWaterTempC.present
          ? data.minWaterTempC.value
          : this.minWaterTempC,
      maxWaterTempC: data.maxWaterTempC.present
          ? data.maxWaterTempC.value
          : this.maxWaterTempC,
      timeInDecoSeconds: data.timeInDecoSeconds.present
          ? data.timeInDecoSeconds.value
          : this.timeInDecoSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiveDerivedStat(')
          ..write('diveId: $diveId, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('minWaterTempC: $minWaterTempC, ')
          ..write('maxWaterTempC: $maxWaterTempC, ')
          ..write('timeInDecoSeconds: $timeInDecoSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    diveId,
    parserVersion,
    minWaterTempC,
    maxWaterTempC,
    timeInDecoSeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiveDerivedStat &&
          other.diveId == this.diveId &&
          other.parserVersion == this.parserVersion &&
          other.minWaterTempC == this.minWaterTempC &&
          other.maxWaterTempC == this.maxWaterTempC &&
          other.timeInDecoSeconds == this.timeInDecoSeconds);
}

class DiveDerivedStatsCompanion extends UpdateCompanion<DiveDerivedStat> {
  final Value<String> diveId;
  final Value<int> parserVersion;
  final Value<double?> minWaterTempC;
  final Value<double?> maxWaterTempC;
  final Value<int> timeInDecoSeconds;
  final Value<int> rowid;
  const DiveDerivedStatsCompanion({
    this.diveId = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.minWaterTempC = const Value.absent(),
    this.maxWaterTempC = const Value.absent(),
    this.timeInDecoSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiveDerivedStatsCompanion.insert({
    required String diveId,
    required int parserVersion,
    this.minWaterTempC = const Value.absent(),
    this.maxWaterTempC = const Value.absent(),
    this.timeInDecoSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : diveId = Value(diveId),
       parserVersion = Value(parserVersion);
  static Insertable<DiveDerivedStat> custom({
    Expression<String>? diveId,
    Expression<int>? parserVersion,
    Expression<double>? minWaterTempC,
    Expression<double>? maxWaterTempC,
    Expression<int>? timeInDecoSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diveId != null) 'dive_id': diveId,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (minWaterTempC != null) 'min_water_temp_c': minWaterTempC,
      if (maxWaterTempC != null) 'max_water_temp_c': maxWaterTempC,
      if (timeInDecoSeconds != null) 'time_in_deco_seconds': timeInDecoSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiveDerivedStatsCompanion copyWith({
    Value<String>? diveId,
    Value<int>? parserVersion,
    Value<double?>? minWaterTempC,
    Value<double?>? maxWaterTempC,
    Value<int>? timeInDecoSeconds,
    Value<int>? rowid,
  }) {
    return DiveDerivedStatsCompanion(
      diveId: diveId ?? this.diveId,
      parserVersion: parserVersion ?? this.parserVersion,
      minWaterTempC: minWaterTempC ?? this.minWaterTempC,
      maxWaterTempC: maxWaterTempC ?? this.maxWaterTempC,
      timeInDecoSeconds: timeInDecoSeconds ?? this.timeInDecoSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diveId.present) {
      map['dive_id'] = Variable<String>(diveId.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (minWaterTempC.present) {
      map['min_water_temp_c'] = Variable<double>(minWaterTempC.value);
    }
    if (maxWaterTempC.present) {
      map['max_water_temp_c'] = Variable<double>(maxWaterTempC.value);
    }
    if (timeInDecoSeconds.present) {
      map['time_in_deco_seconds'] = Variable<int>(timeInDecoSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiveDerivedStatsCompanion(')
          ..write('diveId: $diveId, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('minWaterTempC: $minWaterTempC, ')
          ..write('maxWaterTempC: $maxWaterTempC, ')
          ..write('timeInDecoSeconds: $timeInDecoSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DivesTable dives = $DivesTable(this);
  late final $DiveSamplesTable diveSamples = $DiveSamplesTable(this);
  late final $DiveRawBlobsTable diveRawBlobs = $DiveRawBlobsTable(this);
  late final $DiveAnnotationsTable diveAnnotations = $DiveAnnotationsTable(
    this,
  );
  late final $DiveComputersTable diveComputers = $DiveComputersTable(this);
  late final $OxygenCellsTable oxygenCells = $OxygenCellsTable(this);
  late final $ScrubberSessionsTable scrubberSessions = $ScrubberSessionsTable(
    this,
  );
  late final $CylindersTable cylinders = $CylindersTable(this);
  late final $PressureMappingsTable pressureMappings = $PressureMappingsTable(
    this,
  );
  late final $DiveCylindersTable diveCylinders = $DiveCylindersTable(this);
  late final $DivePlansTable divePlans = $DivePlansTable(this);
  late final $DiveBailoutCarryTable diveBailoutCarry = $DiveBailoutCarryTable(
    this,
  );
  late final $ImportStatesTable importStates = $ImportStatesTable(this);
  late final $DiveMergeLinksTable diveMergeLinks = $DiveMergeLinksTable(this);
  late final $SyncQuarantineTable syncQuarantine = $SyncQuarantineTable(this);
  late final $DiveDerivedStatsTable diveDerivedStats = $DiveDerivedStatsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dives,
    diveSamples,
    diveRawBlobs,
    diveAnnotations,
    diveComputers,
    oxygenCells,
    scrubberSessions,
    cylinders,
    pressureMappings,
    diveCylinders,
    divePlans,
    diveBailoutCarry,
    importStates,
    diveMergeLinks,
    syncQuarantine,
    diveDerivedStats,
  ];
}

typedef $$DivesTableCreateCompanionBuilder =
    DivesCompanion Function({
      required String id,
      required int dcSerial,
      required int dcDiveNumber,
      required int startTime,
      required int endTime,
      Value<int?> utcOffsetMinutes,
      required int durationSeconds,
      required int maxDepthMm,
      required int diveMode,
      required int decoModel,
      Value<int?> gfLow,
      Value<int?> gfHigh,
      required int atmosphericPressureMbar,
      required int waterDensity,
      required int logVersion,
      required int dcModel,
      Value<int?> dcFirmware,
      required int sampleIntervalMs,
      required String gasMixesJson,
      Value<String?> tanksJson,
      Value<String?> sensorCalibrationJson,
      Value<int?> configuredStackSeconds,
      Value<int?> stackRemainingAtStartSeconds,
      Value<int?> stackRemainingAtEndSeconds,
      required Uint8List rawBlob,
      required int parserVersion,
      required int importedAt,
      Value<int?> subsurfaceUploadedAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$DivesTableUpdateCompanionBuilder =
    DivesCompanion Function({
      Value<String> id,
      Value<int> dcSerial,
      Value<int> dcDiveNumber,
      Value<int> startTime,
      Value<int> endTime,
      Value<int?> utcOffsetMinutes,
      Value<int> durationSeconds,
      Value<int> maxDepthMm,
      Value<int> diveMode,
      Value<int> decoModel,
      Value<int?> gfLow,
      Value<int?> gfHigh,
      Value<int> atmosphericPressureMbar,
      Value<int> waterDensity,
      Value<int> logVersion,
      Value<int> dcModel,
      Value<int?> dcFirmware,
      Value<int> sampleIntervalMs,
      Value<String> gasMixesJson,
      Value<String?> tanksJson,
      Value<String?> sensorCalibrationJson,
      Value<int?> configuredStackSeconds,
      Value<int?> stackRemainingAtStartSeconds,
      Value<int?> stackRemainingAtEndSeconds,
      Value<Uint8List> rawBlob,
      Value<int> parserVersion,
      Value<int> importedAt,
      Value<int?> subsurfaceUploadedAt,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

final class $$DivesTableReferences
    extends BaseReferences<_$AppDatabase, $DivesTable, Dive> {
  $$DivesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiveSamplesTable, List<DiveSample>>
  _diveSamplesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diveSamples,
    aliasName: $_aliasNameGenerator(db.dives.id, db.diveSamples.diveId),
  );

  $$DiveSamplesTableProcessedTableManager get diveSamplesRefs {
    final manager = $$DiveSamplesTableTableManager(
      $_db,
      $_db.diveSamples,
    ).filter((f) => f.diveId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_diveSamplesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DiveAnnotationsTable, List<DiveAnnotation>>
  _diveAnnotationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diveAnnotations,
    aliasName: $_aliasNameGenerator(db.dives.id, db.diveAnnotations.diveId),
  );

  $$DiveAnnotationsTableProcessedTableManager get diveAnnotationsRefs {
    final manager = $$DiveAnnotationsTableTableManager(
      $_db,
      $_db.diveAnnotations,
    ).filter((f) => f.diveId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diveAnnotationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DiveCylindersTable, List<DiveCylinder>>
  _diveCylindersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diveCylinders,
    aliasName: $_aliasNameGenerator(db.dives.id, db.diveCylinders.diveId),
  );

  $$DiveCylindersTableProcessedTableManager get diveCylindersRefs {
    final manager = $$DiveCylindersTableTableManager(
      $_db,
      $_db.diveCylinders,
    ).filter((f) => f.diveId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_diveCylindersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DiveBailoutCarryTable, List<DiveBailoutCarryData>>
  _diveBailoutCarryRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diveBailoutCarry,
    aliasName: $_aliasNameGenerator(db.dives.id, db.diveBailoutCarry.diveId),
  );

  $$DiveBailoutCarryTableProcessedTableManager get diveBailoutCarryRefs {
    final manager = $$DiveBailoutCarryTableTableManager(
      $_db,
      $_db.diveBailoutCarry,
    ).filter((f) => f.diveId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diveBailoutCarryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DiveMergeLinksTable, List<DiveMergeLink>>
  _diveMergeLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diveMergeLinks,
    aliasName: $_aliasNameGenerator(db.dives.id, db.diveMergeLinks.diveId),
  );

  $$DiveMergeLinksTableProcessedTableManager get diveMergeLinksRefs {
    final manager = $$DiveMergeLinksTableTableManager(
      $_db,
      $_db.diveMergeLinks,
    ).filter((f) => f.diveId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_diveMergeLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DivesTableFilterComposer extends Composer<_$AppDatabase, $DivesTable> {
  $$DivesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dcSerial => $composableBuilder(
    column: $table.dcSerial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dcDiveNumber => $composableBuilder(
    column: $table.dcDiveNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get utcOffsetMinutes => $composableBuilder(
    column: $table.utcOffsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxDepthMm => $composableBuilder(
    column: $table.maxDepthMm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get diveMode => $composableBuilder(
    column: $table.diveMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decoModel => $composableBuilder(
    column: $table.decoModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gfLow => $composableBuilder(
    column: $table.gfLow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gfHigh => $composableBuilder(
    column: $table.gfHigh,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atmosphericPressureMbar => $composableBuilder(
    column: $table.atmosphericPressureMbar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get waterDensity => $composableBuilder(
    column: $table.waterDensity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get logVersion => $composableBuilder(
    column: $table.logVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dcModel => $composableBuilder(
    column: $table.dcModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dcFirmware => $composableBuilder(
    column: $table.dcFirmware,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleIntervalMs => $composableBuilder(
    column: $table.sampleIntervalMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gasMixesJson => $composableBuilder(
    column: $table.gasMixesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tanksJson => $composableBuilder(
    column: $table.tanksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sensorCalibrationJson => $composableBuilder(
    column: $table.sensorCalibrationJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get configuredStackSeconds => $composableBuilder(
    column: $table.configuredStackSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stackRemainingAtStartSeconds => $composableBuilder(
    column: $table.stackRemainingAtStartSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stackRemainingAtEndSeconds => $composableBuilder(
    column: $table.stackRemainingAtEndSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get rawBlob => $composableBuilder(
    column: $table.rawBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subsurfaceUploadedAt => $composableBuilder(
    column: $table.subsurfaceUploadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diveSamplesRefs(
    Expression<bool> Function($$DiveSamplesTableFilterComposer f) f,
  ) {
    final $$DiveSamplesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveSamples,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveSamplesTableFilterComposer(
            $db: $db,
            $table: $db.diveSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> diveAnnotationsRefs(
    Expression<bool> Function($$DiveAnnotationsTableFilterComposer f) f,
  ) {
    final $$DiveAnnotationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveAnnotations,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveAnnotationsTableFilterComposer(
            $db: $db,
            $table: $db.diveAnnotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> diveCylindersRefs(
    Expression<bool> Function($$DiveCylindersTableFilterComposer f) f,
  ) {
    final $$DiveCylindersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveCylinders,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveCylindersTableFilterComposer(
            $db: $db,
            $table: $db.diveCylinders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> diveBailoutCarryRefs(
    Expression<bool> Function($$DiveBailoutCarryTableFilterComposer f) f,
  ) {
    final $$DiveBailoutCarryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveBailoutCarry,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveBailoutCarryTableFilterComposer(
            $db: $db,
            $table: $db.diveBailoutCarry,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> diveMergeLinksRefs(
    Expression<bool> Function($$DiveMergeLinksTableFilterComposer f) f,
  ) {
    final $$DiveMergeLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveMergeLinks,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveMergeLinksTableFilterComposer(
            $db: $db,
            $table: $db.diveMergeLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DivesTableOrderingComposer
    extends Composer<_$AppDatabase, $DivesTable> {
  $$DivesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dcSerial => $composableBuilder(
    column: $table.dcSerial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dcDiveNumber => $composableBuilder(
    column: $table.dcDiveNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get utcOffsetMinutes => $composableBuilder(
    column: $table.utcOffsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxDepthMm => $composableBuilder(
    column: $table.maxDepthMm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get diveMode => $composableBuilder(
    column: $table.diveMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decoModel => $composableBuilder(
    column: $table.decoModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gfLow => $composableBuilder(
    column: $table.gfLow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gfHigh => $composableBuilder(
    column: $table.gfHigh,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atmosphericPressureMbar => $composableBuilder(
    column: $table.atmosphericPressureMbar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get waterDensity => $composableBuilder(
    column: $table.waterDensity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get logVersion => $composableBuilder(
    column: $table.logVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dcModel => $composableBuilder(
    column: $table.dcModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dcFirmware => $composableBuilder(
    column: $table.dcFirmware,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleIntervalMs => $composableBuilder(
    column: $table.sampleIntervalMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gasMixesJson => $composableBuilder(
    column: $table.gasMixesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tanksJson => $composableBuilder(
    column: $table.tanksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sensorCalibrationJson => $composableBuilder(
    column: $table.sensorCalibrationJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get configuredStackSeconds => $composableBuilder(
    column: $table.configuredStackSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stackRemainingAtStartSeconds => $composableBuilder(
    column: $table.stackRemainingAtStartSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stackRemainingAtEndSeconds => $composableBuilder(
    column: $table.stackRemainingAtEndSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get rawBlob => $composableBuilder(
    column: $table.rawBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subsurfaceUploadedAt => $composableBuilder(
    column: $table.subsurfaceUploadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DivesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DivesTable> {
  $$DivesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get dcSerial =>
      $composableBuilder(column: $table.dcSerial, builder: (column) => column);

  GeneratedColumn<int> get dcDiveNumber => $composableBuilder(
    column: $table.dcDiveNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<int> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<int> get utcOffsetMinutes => $composableBuilder(
    column: $table.utcOffsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxDepthMm => $composableBuilder(
    column: $table.maxDepthMm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get diveMode =>
      $composableBuilder(column: $table.diveMode, builder: (column) => column);

  GeneratedColumn<int> get decoModel =>
      $composableBuilder(column: $table.decoModel, builder: (column) => column);

  GeneratedColumn<int> get gfLow =>
      $composableBuilder(column: $table.gfLow, builder: (column) => column);

  GeneratedColumn<int> get gfHigh =>
      $composableBuilder(column: $table.gfHigh, builder: (column) => column);

  GeneratedColumn<int> get atmosphericPressureMbar => $composableBuilder(
    column: $table.atmosphericPressureMbar,
    builder: (column) => column,
  );

  GeneratedColumn<int> get waterDensity => $composableBuilder(
    column: $table.waterDensity,
    builder: (column) => column,
  );

  GeneratedColumn<int> get logVersion => $composableBuilder(
    column: $table.logVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dcModel =>
      $composableBuilder(column: $table.dcModel, builder: (column) => column);

  GeneratedColumn<int> get dcFirmware => $composableBuilder(
    column: $table.dcFirmware,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sampleIntervalMs => $composableBuilder(
    column: $table.sampleIntervalMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gasMixesJson => $composableBuilder(
    column: $table.gasMixesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tanksJson =>
      $composableBuilder(column: $table.tanksJson, builder: (column) => column);

  GeneratedColumn<String> get sensorCalibrationJson => $composableBuilder(
    column: $table.sensorCalibrationJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get configuredStackSeconds => $composableBuilder(
    column: $table.configuredStackSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stackRemainingAtStartSeconds => $composableBuilder(
    column: $table.stackRemainingAtStartSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stackRemainingAtEndSeconds => $composableBuilder(
    column: $table.stackRemainingAtEndSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get rawBlob =>
      $composableBuilder(column: $table.rawBlob, builder: (column) => column);

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subsurfaceUploadedAt => $composableBuilder(
    column: $table.subsurfaceUploadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> diveSamplesRefs<T extends Object>(
    Expression<T> Function($$DiveSamplesTableAnnotationComposer a) f,
  ) {
    final $$DiveSamplesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveSamples,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveSamplesTableAnnotationComposer(
            $db: $db,
            $table: $db.diveSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> diveAnnotationsRefs<T extends Object>(
    Expression<T> Function($$DiveAnnotationsTableAnnotationComposer a) f,
  ) {
    final $$DiveAnnotationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveAnnotations,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveAnnotationsTableAnnotationComposer(
            $db: $db,
            $table: $db.diveAnnotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> diveCylindersRefs<T extends Object>(
    Expression<T> Function($$DiveCylindersTableAnnotationComposer a) f,
  ) {
    final $$DiveCylindersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveCylinders,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveCylindersTableAnnotationComposer(
            $db: $db,
            $table: $db.diveCylinders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> diveBailoutCarryRefs<T extends Object>(
    Expression<T> Function($$DiveBailoutCarryTableAnnotationComposer a) f,
  ) {
    final $$DiveBailoutCarryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveBailoutCarry,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveBailoutCarryTableAnnotationComposer(
            $db: $db,
            $table: $db.diveBailoutCarry,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> diveMergeLinksRefs<T extends Object>(
    Expression<T> Function($$DiveMergeLinksTableAnnotationComposer a) f,
  ) {
    final $$DiveMergeLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveMergeLinks,
      getReferencedColumn: (t) => t.diveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveMergeLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.diveMergeLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DivesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DivesTable,
          Dive,
          $$DivesTableFilterComposer,
          $$DivesTableOrderingComposer,
          $$DivesTableAnnotationComposer,
          $$DivesTableCreateCompanionBuilder,
          $$DivesTableUpdateCompanionBuilder,
          (Dive, $$DivesTableReferences),
          Dive,
          PrefetchHooks Function({
            bool diveSamplesRefs,
            bool diveAnnotationsRefs,
            bool diveCylindersRefs,
            bool diveBailoutCarryRefs,
            bool diveMergeLinksRefs,
          })
        > {
  $$DivesTableTableManager(_$AppDatabase db, $DivesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DivesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DivesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DivesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> dcSerial = const Value.absent(),
                Value<int> dcDiveNumber = const Value.absent(),
                Value<int> startTime = const Value.absent(),
                Value<int> endTime = const Value.absent(),
                Value<int?> utcOffsetMinutes = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<int> maxDepthMm = const Value.absent(),
                Value<int> diveMode = const Value.absent(),
                Value<int> decoModel = const Value.absent(),
                Value<int?> gfLow = const Value.absent(),
                Value<int?> gfHigh = const Value.absent(),
                Value<int> atmosphericPressureMbar = const Value.absent(),
                Value<int> waterDensity = const Value.absent(),
                Value<int> logVersion = const Value.absent(),
                Value<int> dcModel = const Value.absent(),
                Value<int?> dcFirmware = const Value.absent(),
                Value<int> sampleIntervalMs = const Value.absent(),
                Value<String> gasMixesJson = const Value.absent(),
                Value<String?> tanksJson = const Value.absent(),
                Value<String?> sensorCalibrationJson = const Value.absent(),
                Value<int?> configuredStackSeconds = const Value.absent(),
                Value<int?> stackRemainingAtStartSeconds = const Value.absent(),
                Value<int?> stackRemainingAtEndSeconds = const Value.absent(),
                Value<Uint8List> rawBlob = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int> importedAt = const Value.absent(),
                Value<int?> subsurfaceUploadedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DivesCompanion(
                id: id,
                dcSerial: dcSerial,
                dcDiveNumber: dcDiveNumber,
                startTime: startTime,
                endTime: endTime,
                utcOffsetMinutes: utcOffsetMinutes,
                durationSeconds: durationSeconds,
                maxDepthMm: maxDepthMm,
                diveMode: diveMode,
                decoModel: decoModel,
                gfLow: gfLow,
                gfHigh: gfHigh,
                atmosphericPressureMbar: atmosphericPressureMbar,
                waterDensity: waterDensity,
                logVersion: logVersion,
                dcModel: dcModel,
                dcFirmware: dcFirmware,
                sampleIntervalMs: sampleIntervalMs,
                gasMixesJson: gasMixesJson,
                tanksJson: tanksJson,
                sensorCalibrationJson: sensorCalibrationJson,
                configuredStackSeconds: configuredStackSeconds,
                stackRemainingAtStartSeconds: stackRemainingAtStartSeconds,
                stackRemainingAtEndSeconds: stackRemainingAtEndSeconds,
                rawBlob: rawBlob,
                parserVersion: parserVersion,
                importedAt: importedAt,
                subsurfaceUploadedAt: subsurfaceUploadedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int dcSerial,
                required int dcDiveNumber,
                required int startTime,
                required int endTime,
                Value<int?> utcOffsetMinutes = const Value.absent(),
                required int durationSeconds,
                required int maxDepthMm,
                required int diveMode,
                required int decoModel,
                Value<int?> gfLow = const Value.absent(),
                Value<int?> gfHigh = const Value.absent(),
                required int atmosphericPressureMbar,
                required int waterDensity,
                required int logVersion,
                required int dcModel,
                Value<int?> dcFirmware = const Value.absent(),
                required int sampleIntervalMs,
                required String gasMixesJson,
                Value<String?> tanksJson = const Value.absent(),
                Value<String?> sensorCalibrationJson = const Value.absent(),
                Value<int?> configuredStackSeconds = const Value.absent(),
                Value<int?> stackRemainingAtStartSeconds = const Value.absent(),
                Value<int?> stackRemainingAtEndSeconds = const Value.absent(),
                required Uint8List rawBlob,
                required int parserVersion,
                required int importedAt,
                Value<int?> subsurfaceUploadedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DivesCompanion.insert(
                id: id,
                dcSerial: dcSerial,
                dcDiveNumber: dcDiveNumber,
                startTime: startTime,
                endTime: endTime,
                utcOffsetMinutes: utcOffsetMinutes,
                durationSeconds: durationSeconds,
                maxDepthMm: maxDepthMm,
                diveMode: diveMode,
                decoModel: decoModel,
                gfLow: gfLow,
                gfHigh: gfHigh,
                atmosphericPressureMbar: atmosphericPressureMbar,
                waterDensity: waterDensity,
                logVersion: logVersion,
                dcModel: dcModel,
                dcFirmware: dcFirmware,
                sampleIntervalMs: sampleIntervalMs,
                gasMixesJson: gasMixesJson,
                tanksJson: tanksJson,
                sensorCalibrationJson: sensorCalibrationJson,
                configuredStackSeconds: configuredStackSeconds,
                stackRemainingAtStartSeconds: stackRemainingAtStartSeconds,
                stackRemainingAtEndSeconds: stackRemainingAtEndSeconds,
                rawBlob: rawBlob,
                parserVersion: parserVersion,
                importedAt: importedAt,
                subsurfaceUploadedAt: subsurfaceUploadedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$DivesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                diveSamplesRefs = false,
                diveAnnotationsRefs = false,
                diveCylindersRefs = false,
                diveBailoutCarryRefs = false,
                diveMergeLinksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (diveSamplesRefs) db.diveSamples,
                    if (diveAnnotationsRefs) db.diveAnnotations,
                    if (diveCylindersRefs) db.diveCylinders,
                    if (diveBailoutCarryRefs) db.diveBailoutCarry,
                    if (diveMergeLinksRefs) db.diveMergeLinks,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (diveSamplesRefs)
                        await $_getPrefetchedData<
                          Dive,
                          $DivesTable,
                          DiveSample
                        >(
                          currentTable: table,
                          referencedTable: $$DivesTableReferences
                              ._diveSamplesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DivesTableReferences(
                                db,
                                table,
                                p0,
                              ).diveSamplesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.diveId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (diveAnnotationsRefs)
                        await $_getPrefetchedData<
                          Dive,
                          $DivesTable,
                          DiveAnnotation
                        >(
                          currentTable: table,
                          referencedTable: $$DivesTableReferences
                              ._diveAnnotationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DivesTableReferences(
                                db,
                                table,
                                p0,
                              ).diveAnnotationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.diveId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (diveCylindersRefs)
                        await $_getPrefetchedData<
                          Dive,
                          $DivesTable,
                          DiveCylinder
                        >(
                          currentTable: table,
                          referencedTable: $$DivesTableReferences
                              ._diveCylindersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DivesTableReferences(
                                db,
                                table,
                                p0,
                              ).diveCylindersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.diveId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (diveBailoutCarryRefs)
                        await $_getPrefetchedData<
                          Dive,
                          $DivesTable,
                          DiveBailoutCarryData
                        >(
                          currentTable: table,
                          referencedTable: $$DivesTableReferences
                              ._diveBailoutCarryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DivesTableReferences(
                                db,
                                table,
                                p0,
                              ).diveBailoutCarryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.diveId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (diveMergeLinksRefs)
                        await $_getPrefetchedData<
                          Dive,
                          $DivesTable,
                          DiveMergeLink
                        >(
                          currentTable: table,
                          referencedTable: $$DivesTableReferences
                              ._diveMergeLinksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DivesTableReferences(
                                db,
                                table,
                                p0,
                              ).diveMergeLinksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.diveId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DivesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DivesTable,
      Dive,
      $$DivesTableFilterComposer,
      $$DivesTableOrderingComposer,
      $$DivesTableAnnotationComposer,
      $$DivesTableCreateCompanionBuilder,
      $$DivesTableUpdateCompanionBuilder,
      (Dive, $$DivesTableReferences),
      Dive,
      PrefetchHooks Function({
        bool diveSamplesRefs,
        bool diveAnnotationsRefs,
        bool diveCylindersRefs,
        bool diveBailoutCarryRefs,
        bool diveMergeLinksRefs,
      })
    >;
typedef $$DiveSamplesTableCreateCompanionBuilder =
    DiveSamplesCompanion Function({
      required String diveId,
      required int sampleCount,
      required Uint8List depthBlob,
      required Uint8List temperatureBlob,
      required Uint8List ppo2Blob,
      required Uint8List cellMv0Blob,
      required Uint8List cellMv1Blob,
      required Uint8List cellMv2Blob,
      required Uint8List setpointBlob,
      required Uint8List cnsBlob,
      required Uint8List decoDepthBlob,
      required Uint8List decoTimeBlob,
      required Uint8List ttsBlob,
      required Uint8List gasMixIdxBlob,
      required Uint8List statusBlob,
      Value<Uint8List?> tankPressuresBlob,
      Value<int> rowid,
    });
typedef $$DiveSamplesTableUpdateCompanionBuilder =
    DiveSamplesCompanion Function({
      Value<String> diveId,
      Value<int> sampleCount,
      Value<Uint8List> depthBlob,
      Value<Uint8List> temperatureBlob,
      Value<Uint8List> ppo2Blob,
      Value<Uint8List> cellMv0Blob,
      Value<Uint8List> cellMv1Blob,
      Value<Uint8List> cellMv2Blob,
      Value<Uint8List> setpointBlob,
      Value<Uint8List> cnsBlob,
      Value<Uint8List> decoDepthBlob,
      Value<Uint8List> decoTimeBlob,
      Value<Uint8List> ttsBlob,
      Value<Uint8List> gasMixIdxBlob,
      Value<Uint8List> statusBlob,
      Value<Uint8List?> tankPressuresBlob,
      Value<int> rowid,
    });

final class $$DiveSamplesTableReferences
    extends BaseReferences<_$AppDatabase, $DiveSamplesTable, DiveSample> {
  $$DiveSamplesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DivesTable _diveIdTable(_$AppDatabase db) => db.dives.createAlias(
    $_aliasNameGenerator(db.diveSamples.diveId, db.dives.id),
  );

  $$DivesTableProcessedTableManager get diveId {
    final $_column = $_itemColumn<String>('dive_id')!;

    final manager = $$DivesTableTableManager(
      $_db,
      $_db.dives,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_diveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiveSamplesTableFilterComposer
    extends Composer<_$AppDatabase, $DiveSamplesTable> {
  $$DiveSamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get depthBlob => $composableBuilder(
    column: $table.depthBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get temperatureBlob => $composableBuilder(
    column: $table.temperatureBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get ppo2Blob => $composableBuilder(
    column: $table.ppo2Blob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get cellMv0Blob => $composableBuilder(
    column: $table.cellMv0Blob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get cellMv1Blob => $composableBuilder(
    column: $table.cellMv1Blob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get cellMv2Blob => $composableBuilder(
    column: $table.cellMv2Blob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get setpointBlob => $composableBuilder(
    column: $table.setpointBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get cnsBlob => $composableBuilder(
    column: $table.cnsBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get decoDepthBlob => $composableBuilder(
    column: $table.decoDepthBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get decoTimeBlob => $composableBuilder(
    column: $table.decoTimeBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get ttsBlob => $composableBuilder(
    column: $table.ttsBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get gasMixIdxBlob => $composableBuilder(
    column: $table.gasMixIdxBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get statusBlob => $composableBuilder(
    column: $table.statusBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get tankPressuresBlob => $composableBuilder(
    column: $table.tankPressuresBlob,
    builder: (column) => ColumnFilters(column),
  );

  $$DivesTableFilterComposer get diveId {
    final $$DivesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableFilterComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveSamplesTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveSamplesTable> {
  $$DiveSamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get depthBlob => $composableBuilder(
    column: $table.depthBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get temperatureBlob => $composableBuilder(
    column: $table.temperatureBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get ppo2Blob => $composableBuilder(
    column: $table.ppo2Blob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get cellMv0Blob => $composableBuilder(
    column: $table.cellMv0Blob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get cellMv1Blob => $composableBuilder(
    column: $table.cellMv1Blob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get cellMv2Blob => $composableBuilder(
    column: $table.cellMv2Blob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get setpointBlob => $composableBuilder(
    column: $table.setpointBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get cnsBlob => $composableBuilder(
    column: $table.cnsBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get decoDepthBlob => $composableBuilder(
    column: $table.decoDepthBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get decoTimeBlob => $composableBuilder(
    column: $table.decoTimeBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get ttsBlob => $composableBuilder(
    column: $table.ttsBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get gasMixIdxBlob => $composableBuilder(
    column: $table.gasMixIdxBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get statusBlob => $composableBuilder(
    column: $table.statusBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get tankPressuresBlob => $composableBuilder(
    column: $table.tankPressuresBlob,
    builder: (column) => ColumnOrderings(column),
  );

  $$DivesTableOrderingComposer get diveId {
    final $$DivesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableOrderingComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveSamplesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveSamplesTable> {
  $$DiveSamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get depthBlob =>
      $composableBuilder(column: $table.depthBlob, builder: (column) => column);

  GeneratedColumn<Uint8List> get temperatureBlob => $composableBuilder(
    column: $table.temperatureBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get ppo2Blob =>
      $composableBuilder(column: $table.ppo2Blob, builder: (column) => column);

  GeneratedColumn<Uint8List> get cellMv0Blob => $composableBuilder(
    column: $table.cellMv0Blob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get cellMv1Blob => $composableBuilder(
    column: $table.cellMv1Blob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get cellMv2Blob => $composableBuilder(
    column: $table.cellMv2Blob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get setpointBlob => $composableBuilder(
    column: $table.setpointBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get cnsBlob =>
      $composableBuilder(column: $table.cnsBlob, builder: (column) => column);

  GeneratedColumn<Uint8List> get decoDepthBlob => $composableBuilder(
    column: $table.decoDepthBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get decoTimeBlob => $composableBuilder(
    column: $table.decoTimeBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get ttsBlob =>
      $composableBuilder(column: $table.ttsBlob, builder: (column) => column);

  GeneratedColumn<Uint8List> get gasMixIdxBlob => $composableBuilder(
    column: $table.gasMixIdxBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get statusBlob => $composableBuilder(
    column: $table.statusBlob,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get tankPressuresBlob => $composableBuilder(
    column: $table.tankPressuresBlob,
    builder: (column) => column,
  );

  $$DivesTableAnnotationComposer get diveId {
    final $$DivesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableAnnotationComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveSamplesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveSamplesTable,
          DiveSample,
          $$DiveSamplesTableFilterComposer,
          $$DiveSamplesTableOrderingComposer,
          $$DiveSamplesTableAnnotationComposer,
          $$DiveSamplesTableCreateCompanionBuilder,
          $$DiveSamplesTableUpdateCompanionBuilder,
          (DiveSample, $$DiveSamplesTableReferences),
          DiveSample,
          PrefetchHooks Function({bool diveId})
        > {
  $$DiveSamplesTableTableManager(_$AppDatabase db, $DiveSamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveSamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveSamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveSamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveId = const Value.absent(),
                Value<int> sampleCount = const Value.absent(),
                Value<Uint8List> depthBlob = const Value.absent(),
                Value<Uint8List> temperatureBlob = const Value.absent(),
                Value<Uint8List> ppo2Blob = const Value.absent(),
                Value<Uint8List> cellMv0Blob = const Value.absent(),
                Value<Uint8List> cellMv1Blob = const Value.absent(),
                Value<Uint8List> cellMv2Blob = const Value.absent(),
                Value<Uint8List> setpointBlob = const Value.absent(),
                Value<Uint8List> cnsBlob = const Value.absent(),
                Value<Uint8List> decoDepthBlob = const Value.absent(),
                Value<Uint8List> decoTimeBlob = const Value.absent(),
                Value<Uint8List> ttsBlob = const Value.absent(),
                Value<Uint8List> gasMixIdxBlob = const Value.absent(),
                Value<Uint8List> statusBlob = const Value.absent(),
                Value<Uint8List?> tankPressuresBlob = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveSamplesCompanion(
                diveId: diveId,
                sampleCount: sampleCount,
                depthBlob: depthBlob,
                temperatureBlob: temperatureBlob,
                ppo2Blob: ppo2Blob,
                cellMv0Blob: cellMv0Blob,
                cellMv1Blob: cellMv1Blob,
                cellMv2Blob: cellMv2Blob,
                setpointBlob: setpointBlob,
                cnsBlob: cnsBlob,
                decoDepthBlob: decoDepthBlob,
                decoTimeBlob: decoTimeBlob,
                ttsBlob: ttsBlob,
                gasMixIdxBlob: gasMixIdxBlob,
                statusBlob: statusBlob,
                tankPressuresBlob: tankPressuresBlob,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveId,
                required int sampleCount,
                required Uint8List depthBlob,
                required Uint8List temperatureBlob,
                required Uint8List ppo2Blob,
                required Uint8List cellMv0Blob,
                required Uint8List cellMv1Blob,
                required Uint8List cellMv2Blob,
                required Uint8List setpointBlob,
                required Uint8List cnsBlob,
                required Uint8List decoDepthBlob,
                required Uint8List decoTimeBlob,
                required Uint8List ttsBlob,
                required Uint8List gasMixIdxBlob,
                required Uint8List statusBlob,
                Value<Uint8List?> tankPressuresBlob = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveSamplesCompanion.insert(
                diveId: diveId,
                sampleCount: sampleCount,
                depthBlob: depthBlob,
                temperatureBlob: temperatureBlob,
                ppo2Blob: ppo2Blob,
                cellMv0Blob: cellMv0Blob,
                cellMv1Blob: cellMv1Blob,
                cellMv2Blob: cellMv2Blob,
                setpointBlob: setpointBlob,
                cnsBlob: cnsBlob,
                decoDepthBlob: decoDepthBlob,
                decoTimeBlob: decoTimeBlob,
                ttsBlob: ttsBlob,
                gasMixIdxBlob: gasMixIdxBlob,
                statusBlob: statusBlob,
                tankPressuresBlob: tankPressuresBlob,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiveSamplesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diveId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (diveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.diveId,
                                referencedTable: $$DiveSamplesTableReferences
                                    ._diveIdTable(db),
                                referencedColumn: $$DiveSamplesTableReferences
                                    ._diveIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiveSamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveSamplesTable,
      DiveSample,
      $$DiveSamplesTableFilterComposer,
      $$DiveSamplesTableOrderingComposer,
      $$DiveSamplesTableAnnotationComposer,
      $$DiveSamplesTableCreateCompanionBuilder,
      $$DiveSamplesTableUpdateCompanionBuilder,
      (DiveSample, $$DiveSamplesTableReferences),
      DiveSample,
      PrefetchHooks Function({bool diveId})
    >;
typedef $$DiveRawBlobsTableCreateCompanionBuilder =
    DiveRawBlobsCompanion Function({
      required String diveId,
      required Uint8List rawBlob,
      Value<int> rowid,
    });
typedef $$DiveRawBlobsTableUpdateCompanionBuilder =
    DiveRawBlobsCompanion Function({
      Value<String> diveId,
      Value<Uint8List> rawBlob,
      Value<int> rowid,
    });

class $$DiveRawBlobsTableFilterComposer
    extends Composer<_$AppDatabase, $DiveRawBlobsTable> {
  $$DiveRawBlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get diveId => $composableBuilder(
    column: $table.diveId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get rawBlob => $composableBuilder(
    column: $table.rawBlob,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiveRawBlobsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveRawBlobsTable> {
  $$DiveRawBlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get diveId => $composableBuilder(
    column: $table.diveId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get rawBlob => $composableBuilder(
    column: $table.rawBlob,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiveRawBlobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveRawBlobsTable> {
  $$DiveRawBlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get diveId =>
      $composableBuilder(column: $table.diveId, builder: (column) => column);

  GeneratedColumn<Uint8List> get rawBlob =>
      $composableBuilder(column: $table.rawBlob, builder: (column) => column);
}

class $$DiveRawBlobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveRawBlobsTable,
          DiveRawBlob,
          $$DiveRawBlobsTableFilterComposer,
          $$DiveRawBlobsTableOrderingComposer,
          $$DiveRawBlobsTableAnnotationComposer,
          $$DiveRawBlobsTableCreateCompanionBuilder,
          $$DiveRawBlobsTableUpdateCompanionBuilder,
          (
            DiveRawBlob,
            BaseReferences<_$AppDatabase, $DiveRawBlobsTable, DiveRawBlob>,
          ),
          DiveRawBlob,
          PrefetchHooks Function()
        > {
  $$DiveRawBlobsTableTableManager(_$AppDatabase db, $DiveRawBlobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveRawBlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveRawBlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveRawBlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveId = const Value.absent(),
                Value<Uint8List> rawBlob = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveRawBlobsCompanion(
                diveId: diveId,
                rawBlob: rawBlob,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveId,
                required Uint8List rawBlob,
                Value<int> rowid = const Value.absent(),
              }) => DiveRawBlobsCompanion.insert(
                diveId: diveId,
                rawBlob: rawBlob,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiveRawBlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveRawBlobsTable,
      DiveRawBlob,
      $$DiveRawBlobsTableFilterComposer,
      $$DiveRawBlobsTableOrderingComposer,
      $$DiveRawBlobsTableAnnotationComposer,
      $$DiveRawBlobsTableCreateCompanionBuilder,
      $$DiveRawBlobsTableUpdateCompanionBuilder,
      (
        DiveRawBlob,
        BaseReferences<_$AppDatabase, $DiveRawBlobsTable, DiveRawBlob>,
      ),
      DiveRawBlob,
      PrefetchHooks Function()
    >;
typedef $$DiveAnnotationsTableCreateCompanionBuilder =
    DiveAnnotationsCompanion Function({
      required String diveId,
      Value<String?> siteName,
      Value<int?> siteLatitudeE5,
      Value<int?> siteLongitudeE5,
      Value<String?> notes,
      Value<String?> buddiesJson,
      Value<String?> tagsJson,
      Value<int?> rating,
      Value<String?> conditions,
      Value<String?> divemaster,
      Value<int?> visibility,
      Value<int?> wavesize,
      Value<int?> current,
      Value<int?> surge,
      Value<int?> chill,
      Value<double?> airTempC,
      Value<double?> waterTempC,
      Value<String?> weightsJson,
      Value<String?> displayDecoAlgorithm,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$DiveAnnotationsTableUpdateCompanionBuilder =
    DiveAnnotationsCompanion Function({
      Value<String> diveId,
      Value<String?> siteName,
      Value<int?> siteLatitudeE5,
      Value<int?> siteLongitudeE5,
      Value<String?> notes,
      Value<String?> buddiesJson,
      Value<String?> tagsJson,
      Value<int?> rating,
      Value<String?> conditions,
      Value<String?> divemaster,
      Value<int?> visibility,
      Value<int?> wavesize,
      Value<int?> current,
      Value<int?> surge,
      Value<int?> chill,
      Value<double?> airTempC,
      Value<double?> waterTempC,
      Value<String?> weightsJson,
      Value<String?> displayDecoAlgorithm,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

final class $$DiveAnnotationsTableReferences
    extends
        BaseReferences<_$AppDatabase, $DiveAnnotationsTable, DiveAnnotation> {
  $$DiveAnnotationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DivesTable _diveIdTable(_$AppDatabase db) => db.dives.createAlias(
    $_aliasNameGenerator(db.diveAnnotations.diveId, db.dives.id),
  );

  $$DivesTableProcessedTableManager get diveId {
    final $_column = $_itemColumn<String>('dive_id')!;

    final manager = $$DivesTableTableManager(
      $_db,
      $_db.dives,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_diveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiveAnnotationsTableFilterComposer
    extends Composer<_$AppDatabase, $DiveAnnotationsTable> {
  $$DiveAnnotationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get siteName => $composableBuilder(
    column: $table.siteName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get siteLatitudeE5 => $composableBuilder(
    column: $table.siteLatitudeE5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get siteLongitudeE5 => $composableBuilder(
    column: $table.siteLongitudeE5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get buddiesJson => $composableBuilder(
    column: $table.buddiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conditions => $composableBuilder(
    column: $table.conditions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get divemaster => $composableBuilder(
    column: $table.divemaster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wavesize => $composableBuilder(
    column: $table.wavesize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get current => $composableBuilder(
    column: $table.current,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get surge => $composableBuilder(
    column: $table.surge,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chill => $composableBuilder(
    column: $table.chill,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get airTempC => $composableBuilder(
    column: $table.airTempC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get waterTempC => $composableBuilder(
    column: $table.waterTempC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weightsJson => $composableBuilder(
    column: $table.weightsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayDecoAlgorithm => $composableBuilder(
    column: $table.displayDecoAlgorithm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$DivesTableFilterComposer get diveId {
    final $$DivesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableFilterComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveAnnotationsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveAnnotationsTable> {
  $$DiveAnnotationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get siteName => $composableBuilder(
    column: $table.siteName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get siteLatitudeE5 => $composableBuilder(
    column: $table.siteLatitudeE5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get siteLongitudeE5 => $composableBuilder(
    column: $table.siteLongitudeE5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get buddiesJson => $composableBuilder(
    column: $table.buddiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conditions => $composableBuilder(
    column: $table.conditions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get divemaster => $composableBuilder(
    column: $table.divemaster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wavesize => $composableBuilder(
    column: $table.wavesize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get current => $composableBuilder(
    column: $table.current,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get surge => $composableBuilder(
    column: $table.surge,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chill => $composableBuilder(
    column: $table.chill,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get airTempC => $composableBuilder(
    column: $table.airTempC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get waterTempC => $composableBuilder(
    column: $table.waterTempC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weightsJson => $composableBuilder(
    column: $table.weightsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayDecoAlgorithm => $composableBuilder(
    column: $table.displayDecoAlgorithm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$DivesTableOrderingComposer get diveId {
    final $$DivesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableOrderingComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveAnnotationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveAnnotationsTable> {
  $$DiveAnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get siteName =>
      $composableBuilder(column: $table.siteName, builder: (column) => column);

  GeneratedColumn<int> get siteLatitudeE5 => $composableBuilder(
    column: $table.siteLatitudeE5,
    builder: (column) => column,
  );

  GeneratedColumn<int> get siteLongitudeE5 => $composableBuilder(
    column: $table.siteLongitudeE5,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get buddiesJson => $composableBuilder(
    column: $table.buddiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get conditions => $composableBuilder(
    column: $table.conditions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get divemaster => $composableBuilder(
    column: $table.divemaster,
    builder: (column) => column,
  );

  GeneratedColumn<int> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wavesize =>
      $composableBuilder(column: $table.wavesize, builder: (column) => column);

  GeneratedColumn<int> get current =>
      $composableBuilder(column: $table.current, builder: (column) => column);

  GeneratedColumn<int> get surge =>
      $composableBuilder(column: $table.surge, builder: (column) => column);

  GeneratedColumn<int> get chill =>
      $composableBuilder(column: $table.chill, builder: (column) => column);

  GeneratedColumn<double> get airTempC =>
      $composableBuilder(column: $table.airTempC, builder: (column) => column);

  GeneratedColumn<double> get waterTempC => $composableBuilder(
    column: $table.waterTempC,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weightsJson => $composableBuilder(
    column: $table.weightsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayDecoAlgorithm => $composableBuilder(
    column: $table.displayDecoAlgorithm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$DivesTableAnnotationComposer get diveId {
    final $$DivesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableAnnotationComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveAnnotationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveAnnotationsTable,
          DiveAnnotation,
          $$DiveAnnotationsTableFilterComposer,
          $$DiveAnnotationsTableOrderingComposer,
          $$DiveAnnotationsTableAnnotationComposer,
          $$DiveAnnotationsTableCreateCompanionBuilder,
          $$DiveAnnotationsTableUpdateCompanionBuilder,
          (DiveAnnotation, $$DiveAnnotationsTableReferences),
          DiveAnnotation,
          PrefetchHooks Function({bool diveId})
        > {
  $$DiveAnnotationsTableTableManager(
    _$AppDatabase db,
    $DiveAnnotationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveAnnotationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveAnnotationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveAnnotationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveId = const Value.absent(),
                Value<String?> siteName = const Value.absent(),
                Value<int?> siteLatitudeE5 = const Value.absent(),
                Value<int?> siteLongitudeE5 = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> buddiesJson = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<String?> conditions = const Value.absent(),
                Value<String?> divemaster = const Value.absent(),
                Value<int?> visibility = const Value.absent(),
                Value<int?> wavesize = const Value.absent(),
                Value<int?> current = const Value.absent(),
                Value<int?> surge = const Value.absent(),
                Value<int?> chill = const Value.absent(),
                Value<double?> airTempC = const Value.absent(),
                Value<double?> waterTempC = const Value.absent(),
                Value<String?> weightsJson = const Value.absent(),
                Value<String?> displayDecoAlgorithm = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveAnnotationsCompanion(
                diveId: diveId,
                siteName: siteName,
                siteLatitudeE5: siteLatitudeE5,
                siteLongitudeE5: siteLongitudeE5,
                notes: notes,
                buddiesJson: buddiesJson,
                tagsJson: tagsJson,
                rating: rating,
                conditions: conditions,
                divemaster: divemaster,
                visibility: visibility,
                wavesize: wavesize,
                current: current,
                surge: surge,
                chill: chill,
                airTempC: airTempC,
                waterTempC: waterTempC,
                weightsJson: weightsJson,
                displayDecoAlgorithm: displayDecoAlgorithm,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveId,
                Value<String?> siteName = const Value.absent(),
                Value<int?> siteLatitudeE5 = const Value.absent(),
                Value<int?> siteLongitudeE5 = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> buddiesJson = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<String?> conditions = const Value.absent(),
                Value<String?> divemaster = const Value.absent(),
                Value<int?> visibility = const Value.absent(),
                Value<int?> wavesize = const Value.absent(),
                Value<int?> current = const Value.absent(),
                Value<int?> surge = const Value.absent(),
                Value<int?> chill = const Value.absent(),
                Value<double?> airTempC = const Value.absent(),
                Value<double?> waterTempC = const Value.absent(),
                Value<String?> weightsJson = const Value.absent(),
                Value<String?> displayDecoAlgorithm = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveAnnotationsCompanion.insert(
                diveId: diveId,
                siteName: siteName,
                siteLatitudeE5: siteLatitudeE5,
                siteLongitudeE5: siteLongitudeE5,
                notes: notes,
                buddiesJson: buddiesJson,
                tagsJson: tagsJson,
                rating: rating,
                conditions: conditions,
                divemaster: divemaster,
                visibility: visibility,
                wavesize: wavesize,
                current: current,
                surge: surge,
                chill: chill,
                airTempC: airTempC,
                waterTempC: waterTempC,
                weightsJson: weightsJson,
                displayDecoAlgorithm: displayDecoAlgorithm,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiveAnnotationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diveId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (diveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.diveId,
                                referencedTable:
                                    $$DiveAnnotationsTableReferences
                                        ._diveIdTable(db),
                                referencedColumn:
                                    $$DiveAnnotationsTableReferences
                                        ._diveIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiveAnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveAnnotationsTable,
      DiveAnnotation,
      $$DiveAnnotationsTableFilterComposer,
      $$DiveAnnotationsTableOrderingComposer,
      $$DiveAnnotationsTableAnnotationComposer,
      $$DiveAnnotationsTableCreateCompanionBuilder,
      $$DiveAnnotationsTableUpdateCompanionBuilder,
      (DiveAnnotation, $$DiveAnnotationsTableReferences),
      DiveAnnotation,
      PrefetchHooks Function({bool diveId})
    >;
typedef $$DiveComputersTableCreateCompanionBuilder =
    DiveComputersCompanion Function({
      required String id,
      required int serial,
      required int model,
      Value<int?> firmwareVersion,
      Value<String?> nickname,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$DiveComputersTableUpdateCompanionBuilder =
    DiveComputersCompanion Function({
      Value<String> id,
      Value<int> serial,
      Value<int> model,
      Value<int?> firmwareVersion,
      Value<String?> nickname,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

class $$DiveComputersTableFilterComposer
    extends Composer<_$AppDatabase, $DiveComputersTable> {
  $$DiveComputersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serial => $composableBuilder(
    column: $table.serial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiveComputersTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveComputersTable> {
  $$DiveComputersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serial => $composableBuilder(
    column: $table.serial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiveComputersTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveComputersTable> {
  $$DiveComputersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serial =>
      $composableBuilder(column: $table.serial, builder: (column) => column);

  GeneratedColumn<int> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$DiveComputersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveComputersTable,
          DiveComputer,
          $$DiveComputersTableFilterComposer,
          $$DiveComputersTableOrderingComposer,
          $$DiveComputersTableAnnotationComposer,
          $$DiveComputersTableCreateCompanionBuilder,
          $$DiveComputersTableUpdateCompanionBuilder,
          (
            DiveComputer,
            BaseReferences<_$AppDatabase, $DiveComputersTable, DiveComputer>,
          ),
          DiveComputer,
          PrefetchHooks Function()
        > {
  $$DiveComputersTableTableManager(_$AppDatabase db, $DiveComputersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveComputersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveComputersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveComputersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> serial = const Value.absent(),
                Value<int> model = const Value.absent(),
                Value<int?> firmwareVersion = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveComputersCompanion(
                id: id,
                serial: serial,
                model: model,
                firmwareVersion: firmwareVersion,
                nickname: nickname,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int serial,
                required int model,
                Value<int?> firmwareVersion = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveComputersCompanion.insert(
                id: id,
                serial: serial,
                model: model,
                firmwareVersion: firmwareVersion,
                nickname: nickname,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiveComputersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveComputersTable,
      DiveComputer,
      $$DiveComputersTableFilterComposer,
      $$DiveComputersTableOrderingComposer,
      $$DiveComputersTableAnnotationComposer,
      $$DiveComputersTableCreateCompanionBuilder,
      $$DiveComputersTableUpdateCompanionBuilder,
      (
        DiveComputer,
        BaseReferences<_$AppDatabase, $DiveComputersTable, DiveComputer>,
      ),
      DiveComputer,
      PrefetchHooks Function()
    >;
typedef $$OxygenCellsTableCreateCompanionBuilder =
    OxygenCellsCompanion Function({
      required String id,
      required int slot,
      Value<String?> label,
      Value<int?> installedDate,
      Value<int?> retiredDate,
      Value<String?> notes,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$OxygenCellsTableUpdateCompanionBuilder =
    OxygenCellsCompanion Function({
      Value<String> id,
      Value<int> slot,
      Value<String?> label,
      Value<int?> installedDate,
      Value<int?> retiredDate,
      Value<String?> notes,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

class $$OxygenCellsTableFilterComposer
    extends Composer<_$AppDatabase, $OxygenCellsTable> {
  $$OxygenCellsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get installedDate => $composableBuilder(
    column: $table.installedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retiredDate => $composableBuilder(
    column: $table.retiredDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OxygenCellsTableOrderingComposer
    extends Composer<_$AppDatabase, $OxygenCellsTable> {
  $$OxygenCellsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get installedDate => $composableBuilder(
    column: $table.installedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retiredDate => $composableBuilder(
    column: $table.retiredDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OxygenCellsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OxygenCellsTable> {
  $$OxygenCellsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get installedDate => $composableBuilder(
    column: $table.installedDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retiredDate => $composableBuilder(
    column: $table.retiredDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$OxygenCellsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OxygenCellsTable,
          OxygenCell,
          $$OxygenCellsTableFilterComposer,
          $$OxygenCellsTableOrderingComposer,
          $$OxygenCellsTableAnnotationComposer,
          $$OxygenCellsTableCreateCompanionBuilder,
          $$OxygenCellsTableUpdateCompanionBuilder,
          (
            OxygenCell,
            BaseReferences<_$AppDatabase, $OxygenCellsTable, OxygenCell>,
          ),
          OxygenCell,
          PrefetchHooks Function()
        > {
  $$OxygenCellsTableTableManager(_$AppDatabase db, $OxygenCellsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OxygenCellsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OxygenCellsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OxygenCellsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> slot = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<int?> installedDate = const Value.absent(),
                Value<int?> retiredDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OxygenCellsCompanion(
                id: id,
                slot: slot,
                label: label,
                installedDate: installedDate,
                retiredDate: retiredDate,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int slot,
                Value<String?> label = const Value.absent(),
                Value<int?> installedDate = const Value.absent(),
                Value<int?> retiredDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OxygenCellsCompanion.insert(
                id: id,
                slot: slot,
                label: label,
                installedDate: installedDate,
                retiredDate: retiredDate,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OxygenCellsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OxygenCellsTable,
      OxygenCell,
      $$OxygenCellsTableFilterComposer,
      $$OxygenCellsTableOrderingComposer,
      $$OxygenCellsTableAnnotationComposer,
      $$OxygenCellsTableCreateCompanionBuilder,
      $$OxygenCellsTableUpdateCompanionBuilder,
      (
        OxygenCell,
        BaseReferences<_$AppDatabase, $OxygenCellsTable, OxygenCell>,
      ),
      OxygenCell,
      PrefetchHooks Function()
    >;
typedef $$ScrubberSessionsTableCreateCompanionBuilder =
    ScrubberSessionsCompanion Function({
      required String id,
      Value<int?> startedDate,
      Value<int?> totalMinutes,
      Value<String?> mediaType,
      Value<String?> notes,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$ScrubberSessionsTableUpdateCompanionBuilder =
    ScrubberSessionsCompanion Function({
      Value<String> id,
      Value<int?> startedDate,
      Value<int?> totalMinutes,
      Value<String?> mediaType,
      Value<String?> notes,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

class $$ScrubberSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ScrubberSessionsTable> {
  $$ScrubberSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedDate => $composableBuilder(
    column: $table.startedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalMinutes => $composableBuilder(
    column: $table.totalMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScrubberSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScrubberSessionsTable> {
  $$ScrubberSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedDate => $composableBuilder(
    column: $table.startedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalMinutes => $composableBuilder(
    column: $table.totalMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScrubberSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScrubberSessionsTable> {
  $$ScrubberSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startedDate => $composableBuilder(
    column: $table.startedDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalMinutes => $composableBuilder(
    column: $table.totalMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$ScrubberSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScrubberSessionsTable,
          ScrubberSession,
          $$ScrubberSessionsTableFilterComposer,
          $$ScrubberSessionsTableOrderingComposer,
          $$ScrubberSessionsTableAnnotationComposer,
          $$ScrubberSessionsTableCreateCompanionBuilder,
          $$ScrubberSessionsTableUpdateCompanionBuilder,
          (
            ScrubberSession,
            BaseReferences<
              _$AppDatabase,
              $ScrubberSessionsTable,
              ScrubberSession
            >,
          ),
          ScrubberSession,
          PrefetchHooks Function()
        > {
  $$ScrubberSessionsTableTableManager(
    _$AppDatabase db,
    $ScrubberSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScrubberSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScrubberSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScrubberSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int?> startedDate = const Value.absent(),
                Value<int?> totalMinutes = const Value.absent(),
                Value<String?> mediaType = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScrubberSessionsCompanion(
                id: id,
                startedDate: startedDate,
                totalMinutes: totalMinutes,
                mediaType: mediaType,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int?> startedDate = const Value.absent(),
                Value<int?> totalMinutes = const Value.absent(),
                Value<String?> mediaType = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScrubberSessionsCompanion.insert(
                id: id,
                startedDate: startedDate,
                totalMinutes: totalMinutes,
                mediaType: mediaType,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScrubberSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScrubberSessionsTable,
      ScrubberSession,
      $$ScrubberSessionsTableFilterComposer,
      $$ScrubberSessionsTableOrderingComposer,
      $$ScrubberSessionsTableAnnotationComposer,
      $$ScrubberSessionsTableCreateCompanionBuilder,
      $$ScrubberSessionsTableUpdateCompanionBuilder,
      (
        ScrubberSession,
        BaseReferences<_$AppDatabase, $ScrubberSessionsTable, ScrubberSession>,
      ),
      ScrubberSession,
      PrefetchHooks Function()
    >;
typedef $$CylindersTableCreateCompanionBuilder =
    CylindersCompanion Function({
      required String id,
      required String label,
      required String role,
      Value<int?> bailoutOrder,
      required double volumeLiters,
      required int workingPressureBar,
      Value<String?> notes,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$CylindersTableUpdateCompanionBuilder =
    CylindersCompanion Function({
      Value<String> id,
      Value<String> label,
      Value<String> role,
      Value<int?> bailoutOrder,
      Value<double> volumeLiters,
      Value<int> workingPressureBar,
      Value<String?> notes,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

final class $$CylindersTableReferences
    extends BaseReferences<_$AppDatabase, $CylindersTable, Cylinder> {
  $$CylindersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiveBailoutCarryTable, List<DiveBailoutCarryData>>
  _diveBailoutCarryRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diveBailoutCarry,
    aliasName: $_aliasNameGenerator(
      db.cylinders.id,
      db.diveBailoutCarry.cylinderId,
    ),
  );

  $$DiveBailoutCarryTableProcessedTableManager get diveBailoutCarryRefs {
    final manager = $$DiveBailoutCarryTableTableManager(
      $_db,
      $_db.diveBailoutCarry,
    ).filter((f) => f.cylinderId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diveBailoutCarryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CylindersTableFilterComposer
    extends Composer<_$AppDatabase, $CylindersTable> {
  $$CylindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bailoutOrder => $composableBuilder(
    column: $table.bailoutOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volumeLiters => $composableBuilder(
    column: $table.volumeLiters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get workingPressureBar => $composableBuilder(
    column: $table.workingPressureBar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diveBailoutCarryRefs(
    Expression<bool> Function($$DiveBailoutCarryTableFilterComposer f) f,
  ) {
    final $$DiveBailoutCarryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveBailoutCarry,
      getReferencedColumn: (t) => t.cylinderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveBailoutCarryTableFilterComposer(
            $db: $db,
            $table: $db.diveBailoutCarry,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CylindersTableOrderingComposer
    extends Composer<_$AppDatabase, $CylindersTable> {
  $$CylindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bailoutOrder => $composableBuilder(
    column: $table.bailoutOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volumeLiters => $composableBuilder(
    column: $table.volumeLiters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get workingPressureBar => $composableBuilder(
    column: $table.workingPressureBar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CylindersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CylindersTable> {
  $$CylindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get bailoutOrder => $composableBuilder(
    column: $table.bailoutOrder,
    builder: (column) => column,
  );

  GeneratedColumn<double> get volumeLiters => $composableBuilder(
    column: $table.volumeLiters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get workingPressureBar => $composableBuilder(
    column: $table.workingPressureBar,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  Expression<T> diveBailoutCarryRefs<T extends Object>(
    Expression<T> Function($$DiveBailoutCarryTableAnnotationComposer a) f,
  ) {
    final $$DiveBailoutCarryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diveBailoutCarry,
      getReferencedColumn: (t) => t.cylinderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiveBailoutCarryTableAnnotationComposer(
            $db: $db,
            $table: $db.diveBailoutCarry,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CylindersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CylindersTable,
          Cylinder,
          $$CylindersTableFilterComposer,
          $$CylindersTableOrderingComposer,
          $$CylindersTableAnnotationComposer,
          $$CylindersTableCreateCompanionBuilder,
          $$CylindersTableUpdateCompanionBuilder,
          (Cylinder, $$CylindersTableReferences),
          Cylinder,
          PrefetchHooks Function({bool diveBailoutCarryRefs})
        > {
  $$CylindersTableTableManager(_$AppDatabase db, $CylindersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CylindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CylindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CylindersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int?> bailoutOrder = const Value.absent(),
                Value<double> volumeLiters = const Value.absent(),
                Value<int> workingPressureBar = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CylindersCompanion(
                id: id,
                label: label,
                role: role,
                bailoutOrder: bailoutOrder,
                volumeLiters: volumeLiters,
                workingPressureBar: workingPressureBar,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String label,
                required String role,
                Value<int?> bailoutOrder = const Value.absent(),
                required double volumeLiters,
                required int workingPressureBar,
                Value<String?> notes = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CylindersCompanion.insert(
                id: id,
                label: label,
                role: role,
                bailoutOrder: bailoutOrder,
                volumeLiters: volumeLiters,
                workingPressureBar: workingPressureBar,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CylindersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diveBailoutCarryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (diveBailoutCarryRefs) db.diveBailoutCarry,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (diveBailoutCarryRefs)
                    await $_getPrefetchedData<
                      Cylinder,
                      $CylindersTable,
                      DiveBailoutCarryData
                    >(
                      currentTable: table,
                      referencedTable: $$CylindersTableReferences
                          ._diveBailoutCarryRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CylindersTableReferences(
                            db,
                            table,
                            p0,
                          ).diveBailoutCarryRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.cylinderId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CylindersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CylindersTable,
      Cylinder,
      $$CylindersTableFilterComposer,
      $$CylindersTableOrderingComposer,
      $$CylindersTableAnnotationComposer,
      $$CylindersTableCreateCompanionBuilder,
      $$CylindersTableUpdateCompanionBuilder,
      (Cylinder, $$CylindersTableReferences),
      Cylinder,
      PrefetchHooks Function({bool diveBailoutCarryRefs})
    >;
typedef $$PressureMappingsTableCreateCompanionBuilder =
    PressureMappingsCompanion Function({
      required String diveComputerId,
      required int channelIndex,
      Value<String?> cylinderId,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$PressureMappingsTableUpdateCompanionBuilder =
    PressureMappingsCompanion Function({
      Value<String> diveComputerId,
      Value<int> channelIndex,
      Value<String?> cylinderId,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

class $$PressureMappingsTableFilterComposer
    extends Composer<_$AppDatabase, $PressureMappingsTable> {
  $$PressureMappingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get diveComputerId => $composableBuilder(
    column: $table.diveComputerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get channelIndex => $composableBuilder(
    column: $table.channelIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cylinderId => $composableBuilder(
    column: $table.cylinderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PressureMappingsTableOrderingComposer
    extends Composer<_$AppDatabase, $PressureMappingsTable> {
  $$PressureMappingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get diveComputerId => $composableBuilder(
    column: $table.diveComputerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get channelIndex => $composableBuilder(
    column: $table.channelIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cylinderId => $composableBuilder(
    column: $table.cylinderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PressureMappingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PressureMappingsTable> {
  $$PressureMappingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get diveComputerId => $composableBuilder(
    column: $table.diveComputerId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get channelIndex => $composableBuilder(
    column: $table.channelIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cylinderId => $composableBuilder(
    column: $table.cylinderId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$PressureMappingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PressureMappingsTable,
          PressureMapping,
          $$PressureMappingsTableFilterComposer,
          $$PressureMappingsTableOrderingComposer,
          $$PressureMappingsTableAnnotationComposer,
          $$PressureMappingsTableCreateCompanionBuilder,
          $$PressureMappingsTableUpdateCompanionBuilder,
          (
            PressureMapping,
            BaseReferences<
              _$AppDatabase,
              $PressureMappingsTable,
              PressureMapping
            >,
          ),
          PressureMapping,
          PrefetchHooks Function()
        > {
  $$PressureMappingsTableTableManager(
    _$AppDatabase db,
    $PressureMappingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PressureMappingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PressureMappingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PressureMappingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveComputerId = const Value.absent(),
                Value<int> channelIndex = const Value.absent(),
                Value<String?> cylinderId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PressureMappingsCompanion(
                diveComputerId: diveComputerId,
                channelIndex: channelIndex,
                cylinderId: cylinderId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveComputerId,
                required int channelIndex,
                Value<String?> cylinderId = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PressureMappingsCompanion.insert(
                diveComputerId: diveComputerId,
                channelIndex: channelIndex,
                cylinderId: cylinderId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PressureMappingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PressureMappingsTable,
      PressureMapping,
      $$PressureMappingsTableFilterComposer,
      $$PressureMappingsTableOrderingComposer,
      $$PressureMappingsTableAnnotationComposer,
      $$PressureMappingsTableCreateCompanionBuilder,
      $$PressureMappingsTableUpdateCompanionBuilder,
      (
        PressureMapping,
        BaseReferences<_$AppDatabase, $PressureMappingsTable, PressureMapping>,
      ),
      PressureMapping,
      PrefetchHooks Function()
    >;
typedef $$DiveCylindersTableCreateCompanionBuilder =
    DiveCylindersCompanion Function({
      required String diveId,
      required int gasMixIndex,
      Value<String?> cylinderId,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$DiveCylindersTableUpdateCompanionBuilder =
    DiveCylindersCompanion Function({
      Value<String> diveId,
      Value<int> gasMixIndex,
      Value<String?> cylinderId,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

final class $$DiveCylindersTableReferences
    extends BaseReferences<_$AppDatabase, $DiveCylindersTable, DiveCylinder> {
  $$DiveCylindersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DivesTable _diveIdTable(_$AppDatabase db) => db.dives.createAlias(
    $_aliasNameGenerator(db.diveCylinders.diveId, db.dives.id),
  );

  $$DivesTableProcessedTableManager get diveId {
    final $_column = $_itemColumn<String>('dive_id')!;

    final manager = $$DivesTableTableManager(
      $_db,
      $_db.dives,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_diveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiveCylindersTableFilterComposer
    extends Composer<_$AppDatabase, $DiveCylindersTable> {
  $$DiveCylindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get gasMixIndex => $composableBuilder(
    column: $table.gasMixIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cylinderId => $composableBuilder(
    column: $table.cylinderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$DivesTableFilterComposer get diveId {
    final $$DivesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableFilterComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveCylindersTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveCylindersTable> {
  $$DiveCylindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get gasMixIndex => $composableBuilder(
    column: $table.gasMixIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cylinderId => $composableBuilder(
    column: $table.cylinderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$DivesTableOrderingComposer get diveId {
    final $$DivesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableOrderingComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveCylindersTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveCylindersTable> {
  $$DiveCylindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get gasMixIndex => $composableBuilder(
    column: $table.gasMixIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cylinderId => $composableBuilder(
    column: $table.cylinderId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$DivesTableAnnotationComposer get diveId {
    final $$DivesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableAnnotationComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveCylindersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveCylindersTable,
          DiveCylinder,
          $$DiveCylindersTableFilterComposer,
          $$DiveCylindersTableOrderingComposer,
          $$DiveCylindersTableAnnotationComposer,
          $$DiveCylindersTableCreateCompanionBuilder,
          $$DiveCylindersTableUpdateCompanionBuilder,
          (DiveCylinder, $$DiveCylindersTableReferences),
          DiveCylinder,
          PrefetchHooks Function({bool diveId})
        > {
  $$DiveCylindersTableTableManager(_$AppDatabase db, $DiveCylindersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveCylindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveCylindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveCylindersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveId = const Value.absent(),
                Value<int> gasMixIndex = const Value.absent(),
                Value<String?> cylinderId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveCylindersCompanion(
                diveId: diveId,
                gasMixIndex: gasMixIndex,
                cylinderId: cylinderId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveId,
                required int gasMixIndex,
                Value<String?> cylinderId = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveCylindersCompanion.insert(
                diveId: diveId,
                gasMixIndex: gasMixIndex,
                cylinderId: cylinderId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiveCylindersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diveId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (diveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.diveId,
                                referencedTable: $$DiveCylindersTableReferences
                                    ._diveIdTable(db),
                                referencedColumn: $$DiveCylindersTableReferences
                                    ._diveIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiveCylindersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveCylindersTable,
      DiveCylinder,
      $$DiveCylindersTableFilterComposer,
      $$DiveCylindersTableOrderingComposer,
      $$DiveCylindersTableAnnotationComposer,
      $$DiveCylindersTableCreateCompanionBuilder,
      $$DiveCylindersTableUpdateCompanionBuilder,
      (DiveCylinder, $$DiveCylindersTableReferences),
      DiveCylinder,
      PrefetchHooks Function({bool diveId})
    >;
typedef $$DivePlansTableCreateCompanionBuilder =
    DivePlansCompanion Function({
      required String id,
      Value<String?> name,
      required String mode,
      required String gasesJson,
      required String segmentsJson,
      required String bailoutJson,
      Value<String?> settingsJson,
      Value<String?> notes,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$DivePlansTableUpdateCompanionBuilder =
    DivePlansCompanion Function({
      Value<String> id,
      Value<String?> name,
      Value<String> mode,
      Value<String> gasesJson,
      Value<String> segmentsJson,
      Value<String> bailoutJson,
      Value<String?> settingsJson,
      Value<String?> notes,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

class $$DivePlansTableFilterComposer
    extends Composer<_$AppDatabase, $DivePlansTable> {
  $$DivePlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gasesJson => $composableBuilder(
    column: $table.gasesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get segmentsJson => $composableBuilder(
    column: $table.segmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bailoutJson => $composableBuilder(
    column: $table.bailoutJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DivePlansTableOrderingComposer
    extends Composer<_$AppDatabase, $DivePlansTable> {
  $$DivePlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gasesJson => $composableBuilder(
    column: $table.gasesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get segmentsJson => $composableBuilder(
    column: $table.segmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bailoutJson => $composableBuilder(
    column: $table.bailoutJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DivePlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $DivePlansTable> {
  $$DivePlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get gasesJson =>
      $composableBuilder(column: $table.gasesJson, builder: (column) => column);

  GeneratedColumn<String> get segmentsJson => $composableBuilder(
    column: $table.segmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bailoutJson => $composableBuilder(
    column: $table.bailoutJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$DivePlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DivePlansTable,
          DivePlan,
          $$DivePlansTableFilterComposer,
          $$DivePlansTableOrderingComposer,
          $$DivePlansTableAnnotationComposer,
          $$DivePlansTableCreateCompanionBuilder,
          $$DivePlansTableUpdateCompanionBuilder,
          (DivePlan, BaseReferences<_$AppDatabase, $DivePlansTable, DivePlan>),
          DivePlan,
          PrefetchHooks Function()
        > {
  $$DivePlansTableTableManager(_$AppDatabase db, $DivePlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DivePlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DivePlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DivePlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> gasesJson = const Value.absent(),
                Value<String> segmentsJson = const Value.absent(),
                Value<String> bailoutJson = const Value.absent(),
                Value<String?> settingsJson = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DivePlansCompanion(
                id: id,
                name: name,
                mode: mode,
                gasesJson: gasesJson,
                segmentsJson: segmentsJson,
                bailoutJson: bailoutJson,
                settingsJson: settingsJson,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> name = const Value.absent(),
                required String mode,
                required String gasesJson,
                required String segmentsJson,
                required String bailoutJson,
                Value<String?> settingsJson = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DivePlansCompanion.insert(
                id: id,
                name: name,
                mode: mode,
                gasesJson: gasesJson,
                segmentsJson: segmentsJson,
                bailoutJson: bailoutJson,
                settingsJson: settingsJson,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DivePlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DivePlansTable,
      DivePlan,
      $$DivePlansTableFilterComposer,
      $$DivePlansTableOrderingComposer,
      $$DivePlansTableAnnotationComposer,
      $$DivePlansTableCreateCompanionBuilder,
      $$DivePlansTableUpdateCompanionBuilder,
      (DivePlan, BaseReferences<_$AppDatabase, $DivePlansTable, DivePlan>),
      DivePlan,
      PrefetchHooks Function()
    >;
typedef $$DiveBailoutCarryTableCreateCompanionBuilder =
    DiveBailoutCarryCompanion Function({
      required String id,
      required String diveId,
      required String cylinderId,
      required String gasMix,
      Value<int?> fillPressureBar,
      required int bailoutOrder,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$DiveBailoutCarryTableUpdateCompanionBuilder =
    DiveBailoutCarryCompanion Function({
      Value<String> id,
      Value<String> diveId,
      Value<String> cylinderId,
      Value<String> gasMix,
      Value<int?> fillPressureBar,
      Value<int> bailoutOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

final class $$DiveBailoutCarryTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $DiveBailoutCarryTable,
          DiveBailoutCarryData
        > {
  $$DiveBailoutCarryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DivesTable _diveIdTable(_$AppDatabase db) => db.dives.createAlias(
    $_aliasNameGenerator(db.diveBailoutCarry.diveId, db.dives.id),
  );

  $$DivesTableProcessedTableManager get diveId {
    final $_column = $_itemColumn<String>('dive_id')!;

    final manager = $$DivesTableTableManager(
      $_db,
      $_db.dives,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_diveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CylindersTable _cylinderIdTable(_$AppDatabase db) =>
      db.cylinders.createAlias(
        $_aliasNameGenerator(db.diveBailoutCarry.cylinderId, db.cylinders.id),
      );

  $$CylindersTableProcessedTableManager get cylinderId {
    final $_column = $_itemColumn<String>('cylinder_id')!;

    final manager = $$CylindersTableTableManager(
      $_db,
      $_db.cylinders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_cylinderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiveBailoutCarryTableFilterComposer
    extends Composer<_$AppDatabase, $DiveBailoutCarryTable> {
  $$DiveBailoutCarryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gasMix => $composableBuilder(
    column: $table.gasMix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fillPressureBar => $composableBuilder(
    column: $table.fillPressureBar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bailoutOrder => $composableBuilder(
    column: $table.bailoutOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$DivesTableFilterComposer get diveId {
    final $$DivesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableFilterComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CylindersTableFilterComposer get cylinderId {
    final $$CylindersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cylinderId,
      referencedTable: $db.cylinders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CylindersTableFilterComposer(
            $db: $db,
            $table: $db.cylinders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveBailoutCarryTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveBailoutCarryTable> {
  $$DiveBailoutCarryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gasMix => $composableBuilder(
    column: $table.gasMix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fillPressureBar => $composableBuilder(
    column: $table.fillPressureBar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bailoutOrder => $composableBuilder(
    column: $table.bailoutOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$DivesTableOrderingComposer get diveId {
    final $$DivesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableOrderingComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CylindersTableOrderingComposer get cylinderId {
    final $$CylindersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cylinderId,
      referencedTable: $db.cylinders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CylindersTableOrderingComposer(
            $db: $db,
            $table: $db.cylinders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveBailoutCarryTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveBailoutCarryTable> {
  $$DiveBailoutCarryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gasMix =>
      $composableBuilder(column: $table.gasMix, builder: (column) => column);

  GeneratedColumn<int> get fillPressureBar => $composableBuilder(
    column: $table.fillPressureBar,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bailoutOrder => $composableBuilder(
    column: $table.bailoutOrder,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$DivesTableAnnotationComposer get diveId {
    final $$DivesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableAnnotationComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CylindersTableAnnotationComposer get cylinderId {
    final $$CylindersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cylinderId,
      referencedTable: $db.cylinders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CylindersTableAnnotationComposer(
            $db: $db,
            $table: $db.cylinders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveBailoutCarryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveBailoutCarryTable,
          DiveBailoutCarryData,
          $$DiveBailoutCarryTableFilterComposer,
          $$DiveBailoutCarryTableOrderingComposer,
          $$DiveBailoutCarryTableAnnotationComposer,
          $$DiveBailoutCarryTableCreateCompanionBuilder,
          $$DiveBailoutCarryTableUpdateCompanionBuilder,
          (DiveBailoutCarryData, $$DiveBailoutCarryTableReferences),
          DiveBailoutCarryData,
          PrefetchHooks Function({bool diveId, bool cylinderId})
        > {
  $$DiveBailoutCarryTableTableManager(
    _$AppDatabase db,
    $DiveBailoutCarryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveBailoutCarryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveBailoutCarryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveBailoutCarryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> diveId = const Value.absent(),
                Value<String> cylinderId = const Value.absent(),
                Value<String> gasMix = const Value.absent(),
                Value<int?> fillPressureBar = const Value.absent(),
                Value<int> bailoutOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveBailoutCarryCompanion(
                id: id,
                diveId: diveId,
                cylinderId: cylinderId,
                gasMix: gasMix,
                fillPressureBar: fillPressureBar,
                bailoutOrder: bailoutOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String diveId,
                required String cylinderId,
                required String gasMix,
                Value<int?> fillPressureBar = const Value.absent(),
                required int bailoutOrder,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveBailoutCarryCompanion.insert(
                id: id,
                diveId: diveId,
                cylinderId: cylinderId,
                gasMix: gasMix,
                fillPressureBar: fillPressureBar,
                bailoutOrder: bailoutOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiveBailoutCarryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diveId = false, cylinderId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (diveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.diveId,
                                referencedTable:
                                    $$DiveBailoutCarryTableReferences
                                        ._diveIdTable(db),
                                referencedColumn:
                                    $$DiveBailoutCarryTableReferences
                                        ._diveIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (cylinderId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.cylinderId,
                                referencedTable:
                                    $$DiveBailoutCarryTableReferences
                                        ._cylinderIdTable(db),
                                referencedColumn:
                                    $$DiveBailoutCarryTableReferences
                                        ._cylinderIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiveBailoutCarryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveBailoutCarryTable,
      DiveBailoutCarryData,
      $$DiveBailoutCarryTableFilterComposer,
      $$DiveBailoutCarryTableOrderingComposer,
      $$DiveBailoutCarryTableAnnotationComposer,
      $$DiveBailoutCarryTableCreateCompanionBuilder,
      $$DiveBailoutCarryTableUpdateCompanionBuilder,
      (DiveBailoutCarryData, $$DiveBailoutCarryTableReferences),
      DiveBailoutCarryData,
      PrefetchHooks Function({bool diveId, bool cylinderId})
    >;
typedef $$ImportStatesTableCreateCompanionBuilder =
    ImportStatesCompanion Function({
      required String dcSerial,
      Value<Uint8List?> lastFingerprint,
      Value<int?> lastImportAt,
      Value<int> rowid,
    });
typedef $$ImportStatesTableUpdateCompanionBuilder =
    ImportStatesCompanion Function({
      Value<String> dcSerial,
      Value<Uint8List?> lastFingerprint,
      Value<int?> lastImportAt,
      Value<int> rowid,
    });

class $$ImportStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ImportStatesTable> {
  $$ImportStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dcSerial => $composableBuilder(
    column: $table.dcSerial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get lastFingerprint => $composableBuilder(
    column: $table.lastFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastImportAt => $composableBuilder(
    column: $table.lastImportAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportStatesTable> {
  $$ImportStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dcSerial => $composableBuilder(
    column: $table.dcSerial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get lastFingerprint => $composableBuilder(
    column: $table.lastFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastImportAt => $composableBuilder(
    column: $table.lastImportAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportStatesTable> {
  $$ImportStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dcSerial =>
      $composableBuilder(column: $table.dcSerial, builder: (column) => column);

  GeneratedColumn<Uint8List> get lastFingerprint => $composableBuilder(
    column: $table.lastFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastImportAt => $composableBuilder(
    column: $table.lastImportAt,
    builder: (column) => column,
  );
}

class $$ImportStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportStatesTable,
          ImportState,
          $$ImportStatesTableFilterComposer,
          $$ImportStatesTableOrderingComposer,
          $$ImportStatesTableAnnotationComposer,
          $$ImportStatesTableCreateCompanionBuilder,
          $$ImportStatesTableUpdateCompanionBuilder,
          (
            ImportState,
            BaseReferences<_$AppDatabase, $ImportStatesTable, ImportState>,
          ),
          ImportState,
          PrefetchHooks Function()
        > {
  $$ImportStatesTableTableManager(_$AppDatabase db, $ImportStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> dcSerial = const Value.absent(),
                Value<Uint8List?> lastFingerprint = const Value.absent(),
                Value<int?> lastImportAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportStatesCompanion(
                dcSerial: dcSerial,
                lastFingerprint: lastFingerprint,
                lastImportAt: lastImportAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String dcSerial,
                Value<Uint8List?> lastFingerprint = const Value.absent(),
                Value<int?> lastImportAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportStatesCompanion.insert(
                dcSerial: dcSerial,
                lastFingerprint: lastFingerprint,
                lastImportAt: lastImportAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportStatesTable,
      ImportState,
      $$ImportStatesTableFilterComposer,
      $$ImportStatesTableOrderingComposer,
      $$ImportStatesTableAnnotationComposer,
      $$ImportStatesTableCreateCompanionBuilder,
      $$ImportStatesTableUpdateCompanionBuilder,
      (
        ImportState,
        BaseReferences<_$AppDatabase, $ImportStatesTable, ImportState>,
      ),
      ImportState,
      PrefetchHooks Function()
    >;
typedef $$DiveMergeLinksTableCreateCompanionBuilder =
    DiveMergeLinksCompanion Function({
      required String diveId,
      required String groupId,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });
typedef $$DiveMergeLinksTableUpdateCompanionBuilder =
    DiveMergeLinksCompanion Function({
      Value<String> diveId,
      Value<String> groupId,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<String?> ownerId,
      Value<int> rowid,
    });

final class $$DiveMergeLinksTableReferences
    extends BaseReferences<_$AppDatabase, $DiveMergeLinksTable, DiveMergeLink> {
  $$DiveMergeLinksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DivesTable _diveIdTable(_$AppDatabase db) => db.dives.createAlias(
    $_aliasNameGenerator(db.diveMergeLinks.diveId, db.dives.id),
  );

  $$DivesTableProcessedTableManager get diveId {
    final $_column = $_itemColumn<String>('dive_id')!;

    final manager = $$DivesTableTableManager(
      $_db,
      $_db.dives,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_diveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiveMergeLinksTableFilterComposer
    extends Composer<_$AppDatabase, $DiveMergeLinksTable> {
  $$DiveMergeLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  $$DivesTableFilterComposer get diveId {
    final $$DivesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableFilterComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveMergeLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveMergeLinksTable> {
  $$DiveMergeLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  $$DivesTableOrderingComposer get diveId {
    final $$DivesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableOrderingComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveMergeLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveMergeLinksTable> {
  $$DiveMergeLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  $$DivesTableAnnotationComposer get diveId {
    final $$DivesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diveId,
      referencedTable: $db.dives,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DivesTableAnnotationComposer(
            $db: $db,
            $table: $db.dives,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiveMergeLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveMergeLinksTable,
          DiveMergeLink,
          $$DiveMergeLinksTableFilterComposer,
          $$DiveMergeLinksTableOrderingComposer,
          $$DiveMergeLinksTableAnnotationComposer,
          $$DiveMergeLinksTableCreateCompanionBuilder,
          $$DiveMergeLinksTableUpdateCompanionBuilder,
          (DiveMergeLink, $$DiveMergeLinksTableReferences),
          DiveMergeLink,
          PrefetchHooks Function({bool diveId})
        > {
  $$DiveMergeLinksTableTableManager(
    _$AppDatabase db,
    $DiveMergeLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveMergeLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveMergeLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveMergeLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveId = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveMergeLinksCompanion(
                diveId: diveId,
                groupId: groupId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveId,
                required String groupId,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveMergeLinksCompanion.insert(
                diveId: diveId,
                groupId: groupId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                ownerId: ownerId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiveMergeLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diveId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (diveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.diveId,
                                referencedTable: $$DiveMergeLinksTableReferences
                                    ._diveIdTable(db),
                                referencedColumn:
                                    $$DiveMergeLinksTableReferences
                                        ._diveIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiveMergeLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveMergeLinksTable,
      DiveMergeLink,
      $$DiveMergeLinksTableFilterComposer,
      $$DiveMergeLinksTableOrderingComposer,
      $$DiveMergeLinksTableAnnotationComposer,
      $$DiveMergeLinksTableCreateCompanionBuilder,
      $$DiveMergeLinksTableUpdateCompanionBuilder,
      (DiveMergeLink, $$DiveMergeLinksTableReferences),
      DiveMergeLink,
      PrefetchHooks Function({bool diveId})
    >;
typedef $$SyncQuarantineTableCreateCompanionBuilder =
    SyncQuarantineCompanion Function({
      Value<int> id,
      required int opClientId,
      required String opType,
      required String targetTable,
      required String rowId,
      Value<String?> opData,
      required String error,
      required int quarantinedAt,
    });
typedef $$SyncQuarantineTableUpdateCompanionBuilder =
    SyncQuarantineCompanion Function({
      Value<int> id,
      Value<int> opClientId,
      Value<String> opType,
      Value<String> targetTable,
      Value<String> rowId,
      Value<String?> opData,
      Value<String> error,
      Value<int> quarantinedAt,
    });

class $$SyncQuarantineTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQuarantineTable> {
  $$SyncQuarantineTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get opClientId => $composableBuilder(
    column: $table.opClientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opType => $composableBuilder(
    column: $table.opType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opData => $composableBuilder(
    column: $table.opData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quarantinedAt => $composableBuilder(
    column: $table.quarantinedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQuarantineTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQuarantineTable> {
  $$SyncQuarantineTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get opClientId => $composableBuilder(
    column: $table.opClientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opType => $composableBuilder(
    column: $table.opType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opData => $composableBuilder(
    column: $table.opData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quarantinedAt => $composableBuilder(
    column: $table.quarantinedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQuarantineTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQuarantineTable> {
  $$SyncQuarantineTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get opClientId => $composableBuilder(
    column: $table.opClientId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get opType =>
      $composableBuilder(column: $table.opType, builder: (column) => column);

  GeneratedColumn<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get opData =>
      $composableBuilder(column: $table.opData, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get quarantinedAt => $composableBuilder(
    column: $table.quarantinedAt,
    builder: (column) => column,
  );
}

class $$SyncQuarantineTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQuarantineTable,
          SyncQuarantineData,
          $$SyncQuarantineTableFilterComposer,
          $$SyncQuarantineTableOrderingComposer,
          $$SyncQuarantineTableAnnotationComposer,
          $$SyncQuarantineTableCreateCompanionBuilder,
          $$SyncQuarantineTableUpdateCompanionBuilder,
          (
            SyncQuarantineData,
            BaseReferences<
              _$AppDatabase,
              $SyncQuarantineTable,
              SyncQuarantineData
            >,
          ),
          SyncQuarantineData,
          PrefetchHooks Function()
        > {
  $$SyncQuarantineTableTableManager(
    _$AppDatabase db,
    $SyncQuarantineTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQuarantineTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQuarantineTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQuarantineTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> opClientId = const Value.absent(),
                Value<String> opType = const Value.absent(),
                Value<String> targetTable = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String?> opData = const Value.absent(),
                Value<String> error = const Value.absent(),
                Value<int> quarantinedAt = const Value.absent(),
              }) => SyncQuarantineCompanion(
                id: id,
                opClientId: opClientId,
                opType: opType,
                targetTable: targetTable,
                rowId: rowId,
                opData: opData,
                error: error,
                quarantinedAt: quarantinedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int opClientId,
                required String opType,
                required String targetTable,
                required String rowId,
                Value<String?> opData = const Value.absent(),
                required String error,
                required int quarantinedAt,
              }) => SyncQuarantineCompanion.insert(
                id: id,
                opClientId: opClientId,
                opType: opType,
                targetTable: targetTable,
                rowId: rowId,
                opData: opData,
                error: error,
                quarantinedAt: quarantinedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQuarantineTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQuarantineTable,
      SyncQuarantineData,
      $$SyncQuarantineTableFilterComposer,
      $$SyncQuarantineTableOrderingComposer,
      $$SyncQuarantineTableAnnotationComposer,
      $$SyncQuarantineTableCreateCompanionBuilder,
      $$SyncQuarantineTableUpdateCompanionBuilder,
      (
        SyncQuarantineData,
        BaseReferences<_$AppDatabase, $SyncQuarantineTable, SyncQuarantineData>,
      ),
      SyncQuarantineData,
      PrefetchHooks Function()
    >;
typedef $$DiveDerivedStatsTableCreateCompanionBuilder =
    DiveDerivedStatsCompanion Function({
      required String diveId,
      required int parserVersion,
      Value<double?> minWaterTempC,
      Value<double?> maxWaterTempC,
      Value<int> timeInDecoSeconds,
      Value<int> rowid,
    });
typedef $$DiveDerivedStatsTableUpdateCompanionBuilder =
    DiveDerivedStatsCompanion Function({
      Value<String> diveId,
      Value<int> parserVersion,
      Value<double?> minWaterTempC,
      Value<double?> maxWaterTempC,
      Value<int> timeInDecoSeconds,
      Value<int> rowid,
    });

class $$DiveDerivedStatsTableFilterComposer
    extends Composer<_$AppDatabase, $DiveDerivedStatsTable> {
  $$DiveDerivedStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get diveId => $composableBuilder(
    column: $table.diveId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minWaterTempC => $composableBuilder(
    column: $table.minWaterTempC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxWaterTempC => $composableBuilder(
    column: $table.maxWaterTempC,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeInDecoSeconds => $composableBuilder(
    column: $table.timeInDecoSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiveDerivedStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiveDerivedStatsTable> {
  $$DiveDerivedStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get diveId => $composableBuilder(
    column: $table.diveId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minWaterTempC => $composableBuilder(
    column: $table.minWaterTempC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxWaterTempC => $composableBuilder(
    column: $table.maxWaterTempC,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeInDecoSeconds => $composableBuilder(
    column: $table.timeInDecoSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiveDerivedStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiveDerivedStatsTable> {
  $$DiveDerivedStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get diveId =>
      $composableBuilder(column: $table.diveId, builder: (column) => column);

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get minWaterTempC => $composableBuilder(
    column: $table.minWaterTempC,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxWaterTempC => $composableBuilder(
    column: $table.maxWaterTempC,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timeInDecoSeconds => $composableBuilder(
    column: $table.timeInDecoSeconds,
    builder: (column) => column,
  );
}

class $$DiveDerivedStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiveDerivedStatsTable,
          DiveDerivedStat,
          $$DiveDerivedStatsTableFilterComposer,
          $$DiveDerivedStatsTableOrderingComposer,
          $$DiveDerivedStatsTableAnnotationComposer,
          $$DiveDerivedStatsTableCreateCompanionBuilder,
          $$DiveDerivedStatsTableUpdateCompanionBuilder,
          (
            DiveDerivedStat,
            BaseReferences<
              _$AppDatabase,
              $DiveDerivedStatsTable,
              DiveDerivedStat
            >,
          ),
          DiveDerivedStat,
          PrefetchHooks Function()
        > {
  $$DiveDerivedStatsTableTableManager(
    _$AppDatabase db,
    $DiveDerivedStatsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiveDerivedStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiveDerivedStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiveDerivedStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> diveId = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<double?> minWaterTempC = const Value.absent(),
                Value<double?> maxWaterTempC = const Value.absent(),
                Value<int> timeInDecoSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveDerivedStatsCompanion(
                diveId: diveId,
                parserVersion: parserVersion,
                minWaterTempC: minWaterTempC,
                maxWaterTempC: maxWaterTempC,
                timeInDecoSeconds: timeInDecoSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diveId,
                required int parserVersion,
                Value<double?> minWaterTempC = const Value.absent(),
                Value<double?> maxWaterTempC = const Value.absent(),
                Value<int> timeInDecoSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiveDerivedStatsCompanion.insert(
                diveId: diveId,
                parserVersion: parserVersion,
                minWaterTempC: minWaterTempC,
                maxWaterTempC: maxWaterTempC,
                timeInDecoSeconds: timeInDecoSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiveDerivedStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiveDerivedStatsTable,
      DiveDerivedStat,
      $$DiveDerivedStatsTableFilterComposer,
      $$DiveDerivedStatsTableOrderingComposer,
      $$DiveDerivedStatsTableAnnotationComposer,
      $$DiveDerivedStatsTableCreateCompanionBuilder,
      $$DiveDerivedStatsTableUpdateCompanionBuilder,
      (
        DiveDerivedStat,
        BaseReferences<_$AppDatabase, $DiveDerivedStatsTable, DiveDerivedStat>,
      ),
      DiveDerivedStat,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DivesTableTableManager get dives =>
      $$DivesTableTableManager(_db, _db.dives);
  $$DiveSamplesTableTableManager get diveSamples =>
      $$DiveSamplesTableTableManager(_db, _db.diveSamples);
  $$DiveRawBlobsTableTableManager get diveRawBlobs =>
      $$DiveRawBlobsTableTableManager(_db, _db.diveRawBlobs);
  $$DiveAnnotationsTableTableManager get diveAnnotations =>
      $$DiveAnnotationsTableTableManager(_db, _db.diveAnnotations);
  $$DiveComputersTableTableManager get diveComputers =>
      $$DiveComputersTableTableManager(_db, _db.diveComputers);
  $$OxygenCellsTableTableManager get oxygenCells =>
      $$OxygenCellsTableTableManager(_db, _db.oxygenCells);
  $$ScrubberSessionsTableTableManager get scrubberSessions =>
      $$ScrubberSessionsTableTableManager(_db, _db.scrubberSessions);
  $$CylindersTableTableManager get cylinders =>
      $$CylindersTableTableManager(_db, _db.cylinders);
  $$PressureMappingsTableTableManager get pressureMappings =>
      $$PressureMappingsTableTableManager(_db, _db.pressureMappings);
  $$DiveCylindersTableTableManager get diveCylinders =>
      $$DiveCylindersTableTableManager(_db, _db.diveCylinders);
  $$DivePlansTableTableManager get divePlans =>
      $$DivePlansTableTableManager(_db, _db.divePlans);
  $$DiveBailoutCarryTableTableManager get diveBailoutCarry =>
      $$DiveBailoutCarryTableTableManager(_db, _db.diveBailoutCarry);
  $$ImportStatesTableTableManager get importStates =>
      $$ImportStatesTableTableManager(_db, _db.importStates);
  $$DiveMergeLinksTableTableManager get diveMergeLinks =>
      $$DiveMergeLinksTableTableManager(_db, _db.diveMergeLinks);
  $$SyncQuarantineTableTableManager get syncQuarantine =>
      $$SyncQuarantineTableTableManager(_db, _db.syncQuarantine);
  $$DiveDerivedStatsTableTableManager get diveDerivedStats =>
      $$DiveDerivedStatsTableTableManager(_db, _db.diveDerivedStats);
}
