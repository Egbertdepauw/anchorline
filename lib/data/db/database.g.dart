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
    rawBlob,
    parserVersion,
    importedAt,
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

  /// Original decompressed binary blob (for re-parsing).
  final Uint8List rawBlob;

  /// Parser version that produced the cached parse.
  final int parserVersion;

  /// When this dive was imported.
  final int importedAt;
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
    required this.rawBlob,
    required this.parserVersion,
    required this.importedAt,
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
    map['raw_blob'] = Variable<Uint8List>(rawBlob);
    map['parser_version'] = Variable<int>(parserVersion);
    map['imported_at'] = Variable<int>(importedAt);
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
      rawBlob: Value(rawBlob),
      parserVersion: Value(parserVersion),
      importedAt: Value(importedAt),
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
      rawBlob: serializer.fromJson<Uint8List>(json['rawBlob']),
      parserVersion: serializer.fromJson<int>(json['parserVersion']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
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
      'rawBlob': serializer.toJson<Uint8List>(rawBlob),
      'parserVersion': serializer.toJson<int>(parserVersion),
      'importedAt': serializer.toJson<int>(importedAt),
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
    Uint8List? rawBlob,
    int? parserVersion,
    int? importedAt,
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
    rawBlob: rawBlob ?? this.rawBlob,
    parserVersion: parserVersion ?? this.parserVersion,
    importedAt: importedAt ?? this.importedAt,
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
      rawBlob: data.rawBlob.present ? data.rawBlob.value : this.rawBlob,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
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
          ..write('rawBlob: $rawBlob, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('importedAt: $importedAt')
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
    $driftBlobEquality.hash(rawBlob),
    parserVersion,
    importedAt,
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
          $driftBlobEquality.equals(other.rawBlob, this.rawBlob) &&
          other.parserVersion == this.parserVersion &&
          other.importedAt == this.importedAt);
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
  final Value<Uint8List> rawBlob;
  final Value<int> parserVersion;
  final Value<int> importedAt;
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
    this.rawBlob = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.importedAt = const Value.absent(),
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
    required Uint8List rawBlob,
    required int parserVersion,
    required int importedAt,
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
    Expression<Uint8List>? rawBlob,
    Expression<int>? parserVersion,
    Expression<int>? importedAt,
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
      if (rawBlob != null) 'raw_blob': rawBlob,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (importedAt != null) 'imported_at': importedAt,
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
    Value<Uint8List>? rawBlob,
    Value<int>? parserVersion,
    Value<int>? importedAt,
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
      rawBlob: rawBlob ?? this.rawBlob,
      parserVersion: parserVersion ?? this.parserVersion,
      importedAt: importedAt ?? this.importedAt,
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
    if (rawBlob.present) {
      map['raw_blob'] = Variable<Uint8List>(rawBlob.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
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
          ..write('rawBlob: $rawBlob, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('importedAt: $importedAt, ')
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
          ..write('statusBlob: $statusBlob')
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
          $driftBlobEquality.equals(other.statusBlob, this.statusBlob));
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
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
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
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
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
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
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
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<int>(syncStatus);
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
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      syncStatus: Value(syncStatus),
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
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
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
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
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
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
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
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
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
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
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
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    diveId,
    siteName,
    siteLatitudeE5,
    siteLongitudeE5,
    notes,
    buddiesJson,
    tagsJson,
    rating,
    conditions,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
  );
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
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus);
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
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
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
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
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
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
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
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
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
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
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
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
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
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
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
          ..write('syncStatus: $syncStatus')
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
          other.syncStatus == this.syncStatus);
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    slot,
    installedDate,
    retiredDate,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
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
  final int? installedDate;
  final int? retiredDate;
  final String? notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;
  final int syncStatus;
  const OxygenCell({
    required this.id,
    required this.slot,
    this.installedDate,
    this.retiredDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['slot'] = Variable<int>(slot);
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
    return map;
  }

  OxygenCellsCompanion toCompanion(bool nullToAbsent) {
    return OxygenCellsCompanion(
      id: Value(id),
      slot: Value(slot),
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
      installedDate: serializer.fromJson<int?>(json['installedDate']),
      retiredDate: serializer.fromJson<int?>(json['retiredDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'slot': serializer.toJson<int>(slot),
      'installedDate': serializer.toJson<int?>(installedDate),
      'retiredDate': serializer.toJson<int?>(retiredDate),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<int>(syncStatus),
    };
  }

  OxygenCell copyWith({
    String? id,
    int? slot,
    Value<int?> installedDate = const Value.absent(),
    Value<int?> retiredDate = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    int? version,
    int? syncStatus,
  }) => OxygenCell(
    id: id ?? this.id,
    slot: slot ?? this.slot,
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
  );
  OxygenCell copyWithCompanion(OxygenCellsCompanion data) {
    return OxygenCell(
      id: data.id.present ? data.id.value : this.id,
      slot: data.slot.present ? data.slot.value : this.slot,
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('OxygenCell(')
          ..write('id: $id, ')
          ..write('slot: $slot, ')
          ..write('installedDate: $installedDate, ')
          ..write('retiredDate: $retiredDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    slot,
    installedDate,
    retiredDate,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OxygenCell &&
          other.id == this.id &&
          other.slot == this.slot &&
          other.installedDate == this.installedDate &&
          other.retiredDate == this.retiredDate &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus);
}

class OxygenCellsCompanion extends UpdateCompanion<OxygenCell> {
  final Value<String> id;
  final Value<int> slot;
  final Value<int?> installedDate;
  final Value<int?> retiredDate;
  final Value<String?> notes;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> version;
  final Value<int> syncStatus;
  final Value<int> rowid;
  const OxygenCellsCompanion({
    this.id = const Value.absent(),
    this.slot = const Value.absent(),
    this.installedDate = const Value.absent(),
    this.retiredDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OxygenCellsCompanion.insert({
    required String id,
    required int slot,
    this.installedDate = const Value.absent(),
    this.retiredDate = const Value.absent(),
    this.notes = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       slot = Value(slot),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<OxygenCell> custom({
    Expression<String>? id,
    Expression<int>? slot,
    Expression<int>? installedDate,
    Expression<int>? retiredDate,
    Expression<String>? notes,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? version,
    Expression<int>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (slot != null) 'slot': slot,
      if (installedDate != null) 'installed_date': installedDate,
      if (retiredDate != null) 'retired_date': retiredDate,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OxygenCellsCompanion copyWith({
    Value<String>? id,
    Value<int>? slot,
    Value<int?>? installedDate,
    Value<int?>? retiredDate,
    Value<String?>? notes,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<int>? version,
    Value<int>? syncStatus,
    Value<int>? rowid,
  }) {
    return OxygenCellsCompanion(
      id: id ?? this.id,
      slot: slot ?? this.slot,
      installedDate: installedDate ?? this.installedDate,
      retiredDate: retiredDate ?? this.retiredDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
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
          ..write('installedDate: $installedDate, ')
          ..write('retiredDate: $retiredDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
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
          ..write('syncStatus: $syncStatus')
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
          other.syncStatus == this.syncStatus);
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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DivesTable dives = $DivesTable(this);
  late final $DiveSamplesTable diveSamples = $DiveSamplesTable(this);
  late final $DiveAnnotationsTable diveAnnotations = $DiveAnnotationsTable(
    this,
  );
  late final $DiveComputersTable diveComputers = $DiveComputersTable(this);
  late final $OxygenCellsTable oxygenCells = $OxygenCellsTable(this);
  late final $ScrubberSessionsTable scrubberSessions = $ScrubberSessionsTable(
    this,
  );
  late final $ImportStatesTable importStates = $ImportStatesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dives,
    diveSamples,
    diveAnnotations,
    diveComputers,
    oxygenCells,
    scrubberSessions,
    importStates,
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
      required Uint8List rawBlob,
      required int parserVersion,
      required int importedAt,
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
      Value<Uint8List> rawBlob,
      Value<int> parserVersion,
      Value<int> importedAt,
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
                Value<Uint8List> rawBlob = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int> importedAt = const Value.absent(),
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
                rawBlob: rawBlob,
                parserVersion: parserVersion,
                importedAt: importedAt,
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
                required Uint8List rawBlob,
                required int parserVersion,
                required int importedAt,
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
                rawBlob: rawBlob,
                parserVersion: parserVersion,
                importedAt: importedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$DivesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({diveSamplesRefs = false, diveAnnotationsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (diveSamplesRefs) db.diveSamples,
                    if (diveAnnotationsRefs) db.diveAnnotations,
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
      PrefetchHooks Function({bool diveSamplesRefs, bool diveAnnotationsRefs})
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
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
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
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
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
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
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
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
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
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
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
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
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
      Value<int?> installedDate,
      Value<int?> retiredDate,
      Value<String?> notes,
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
      Value<int> rowid,
    });
typedef $$OxygenCellsTableUpdateCompanionBuilder =
    OxygenCellsCompanion Function({
      Value<String> id,
      Value<int> slot,
      Value<int?> installedDate,
      Value<int?> retiredDate,
      Value<String?> notes,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<int> version,
      Value<int> syncStatus,
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
                Value<int?> installedDate = const Value.absent(),
                Value<int?> retiredDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OxygenCellsCompanion(
                id: id,
                slot: slot,
                installedDate: installedDate,
                retiredDate: retiredDate,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int slot,
                Value<int?> installedDate = const Value.absent(),
                Value<int?> retiredDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OxygenCellsCompanion.insert(
                id: id,
                slot: slot,
                installedDate: installedDate,
                retiredDate: retiredDate,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                syncStatus: syncStatus,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DivesTableTableManager get dives =>
      $$DivesTableTableManager(_db, _db.dives);
  $$DiveSamplesTableTableManager get diveSamples =>
      $$DiveSamplesTableTableManager(_db, _db.diveSamples);
  $$DiveAnnotationsTableTableManager get diveAnnotations =>
      $$DiveAnnotationsTableTableManager(_db, _db.diveAnnotations);
  $$DiveComputersTableTableManager get diveComputers =>
      $$DiveComputersTableTableManager(_db, _db.diveComputers);
  $$OxygenCellsTableTableManager get oxygenCells =>
      $$OxygenCellsTableTableManager(_db, _db.oxygenCells);
  $$ScrubberSessionsTableTableManager get scrubberSessions =>
      $$ScrubberSessionsTableTableManager(_db, _db.scrubberSessions);
  $$ImportStatesTableTableManager get importStates =>
      $$ImportStatesTableTableManager(_db, _db.importStates);
}
