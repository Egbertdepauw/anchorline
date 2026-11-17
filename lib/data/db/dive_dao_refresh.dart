part of 'dive_dao.dart';

/// The `dives` columns [StoredDiveKey.fromRow] reads.
const _storedKeySelect = 'SELECT id, dc_vendor, dc_serial, dc_dive_number, '
    'start_time, parser_version, dc_family, dc_fingerprint FROM dives';

/// The sample columns shared by the insert and the refresh, in the order of
/// `sample_count, depth_blob … events_blob`.
const _sampleColumns = [
  'sample_count',
  'depth_blob',
  'temperature_blob',
  'ppo2_blob',
  'cell_mv0_blob',
  'cell_mv1_blob',
  'cell_mv2_blob',
  'setpoint_blob',
  'cns_blob',
  'deco_depth_blob',
  'deco_time_blob',
  'tts_blob',
  'gas_mix_idx_blob',
  'status_blob',
  'tank_pressures_blob',
  'cell_ppo2_blob',
  'events_blob',
];

/// Values for [_sampleColumns]: the count and the base64 blobs.
List<Object?> _encodedSamples(ConvertedDive converted) {
  final blobs = SampleCodec.encode(converted.samples);
  final events = EventCodec.encode(converted.events);
  String? b64(Uint8List? b) => b == null ? null : base64Encode(b);
  return [
    converted.samples.sampleCount,
    b64(blobs['depth']),
    b64(blobs['temperature']),
    b64(blobs['ppo2']),
    b64(blobs['cellMv0']),
    b64(blobs['cellMv1']),
    b64(blobs['cellMv2']),
    b64(blobs['setpoint']),
    b64(blobs['cns']),
    b64(blobs['decoDepth']),
    b64(blobs['decoTime']),
    b64(blobs['tts']),
    b64(blobs['gasMixIdx']),
    b64(blobs['status']),
    b64(blobs['tankPressures']),
    b64(blobs['cellPpo2']),
    b64(events),
  ];
}

/// Refresh and matching internals of [DiveDao.importDive] (spec section 7a).
extension _DiveDaoRefresh on DiveDao {
  Future<StoredDiveKey?> _storedKey(String id) async {
    final row = await _ps.getOptional('$_storedKeySelect WHERE id = ?', [id]);
    return row == null ? null : StoredDiveKey.fromRow(row);
  }

  /// Stored dives that are the same dive as the incoming download [c].
  Future<List<StoredDiveKey>> _sameDiveCandidates(ConvertedDive c) async {
    final t = c.dive.startTime.millisecondsSinceEpoch ~/ 1000;
    final rows = await _ps.getAll(
      '$_storedKeySelect WHERE start_time BETWEEN ? AND ?',
      [t - kSameDiveWindowSeconds, t + kSameDiveWindowSeconds],
    );
    return findSameDive(
      vendor: c.dive.dcVendor ?? kShearwaterVendor,
      serial: c.dive.dcSerial,
      diveNumber: c.dive.dcDiveNumber,
      fingerprint: c.dive.dcFingerprint,
      startTimeSeconds: t,
      excludeId: c.dive.id,
      stored: [for (final r in rows) StoredDiveKey.fromRow(r)],
    );
  }

  /// Whether [converted] may touch [stored] at all (see
  /// [refreshEnginesAgree]); when it may not, not even the raw blob is written.
  bool _enginesAgree(StoredDiveKey stored, ConvertedDive converted) =>
      refreshEnginesAgree(
        storedVersion: stored.parserVersion,
        storedFamily: stored.dcFamily,
        incomingFamily: converted.dive.dcFamily,
      );

  /// Step 1 of the import order for [stored]: the version rule decides.
  /// Null when the dive vanished before the write (nothing was written).
  Future<ImportOutcome?> _refreshStored(
    StoredDiveKey stored,
    ConvertedDive converted,
    int parserVersion, {
    required bool fromDownload,
  }) async {
    // A Subsurface copy (-1) never replaces anything, not even another copy.
    final mayWrite = parserVersion != kSubsurfaceImportedParserVersion &&
        _enginesAgree(stored, converted) &&
        refreshMayWrite(
          storedVersion: stored.parserVersion,
          storedIsLibdc: stored.dcFamily != null,
          incomingVersion: parserVersion,
          incomingIsLibdc: converted.dive.dcFamily != null,
        );
    if (!mayWrite) return ImportOutcome.unchanged;
    if (!isUsableParse(converted)) return ImportOutcome.rejected;
    final wrote = await _writeRefresh(stored.id, converted, parserVersion,
        fromDownload: fromDownload);
    return wrote ? ImportOutcome.refreshed : null;
  }

  /// Replaces the imported data of [diveId] in one PowerSync transaction.
  ///
  /// Never touches `id`, `imported_at`, `deleted_at`,
  /// `subsurface_uploaded_at` or `match_candidates_json`.
  ///
  /// `start_time` is never changed either: the Subsurface writer finds a
  /// pushed dive on Subsurface Cloud by the exact `(serial, startTime)` key,
  /// so moving it would push the dive again as a new Dive-NNN. `end_time`
  /// becomes the stored start plus the incoming dive's length.
  ///
  /// The Postgres triggers refuse a lowered `parser_version` and a
  /// same-version change to the sample blobs; the caller only gets here with
  /// a higher version, so neither fires.
  ///
  /// Returns false, having written nothing, when the dives row is gone.
  Future<bool> _writeRefresh(
    String diveId,
    ConvertedDive converted,
    int parserVersion, {
    required bool fromDownload,
  }) async {
    final dive = converted.dive;
    final gasMixesJson =
        jsonEncode(dive.gasMixes.map((g) => g.toJson()).toList());
    final tanksJson = dive.tanks.isEmpty
        ? null
        : jsonEncode(dive.tanks.map((t) => t.toJson()).toList());
    final sensorCalibrationJson = dive.sensorCalibration.isEmpty
        ? null
        : jsonEncode(dive.sensorCalibration);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final samples = _encodedSamples(converted);

    return await _ps.writeTransaction<bool>((tx) async {
      final old = await tx.getOptional(
          'SELECT gas_mixes_json FROM dives WHERE id = ?', [diveId]);
      // The dive vanished since the check: write nothing (no orphan samples).
      if (old == null) return false;
      final oldMixes = _decodeMixes(old['gas_mixes_json'] as String?);

      await tx.execute(
        'UPDATE dives SET '
        'owner_id = COALESCE(owner_id, ?), '
        'end_time = start_time + ?, utc_offset_minutes = ?, '
        'duration_seconds = ?, max_depth_mm = ?, dive_mode = ?, '
        'deco_model = ?, gf_low = ?, gf_high = ?, '
        'atmospheric_pressure_mbar = ?, water_density = ?, log_version = ?, '
        'dc_model = ?, dc_firmware = COALESCE(?, dc_firmware), '
        'dc_vendor = COALESCE(?, dc_vendor), '
        'dc_product = COALESCE(?, dc_product), '
        'dc_family = ?, dc_model_code = ?, sample_interval_ms = ?, '
        'gas_mixes_json = ?, tanks_json = ?, sensor_calibration_json = ?, '
        'configured_stack_seconds = ?, stack_remaining_at_start_seconds = ?, '
        'stack_remaining_at_end_seconds = ?, parser_version = ?'
        '${fromDownload ? ', dc_serial = ?, dc_dive_number = ?, '
            'dc_fingerprint = COALESCE(?, dc_fingerprint)' : ''}, '
        'version = COALESCE(version, 0) + 1 '
        'WHERE id = ?',
        [
          _ownerId,
          (dive.endTime.millisecondsSinceEpoch -
                  dive.startTime.millisecondsSinceEpoch) ~/
              1000,
          dive.utcOffsetMinutes,
          dive.duration.inSeconds,
          (dive.maxDepthMeters * 1000).round(),
          dive.diveMode.value,
          dive.decoModel.value,
          dive.gfLow,
          dive.gfHigh,
          dive.atmosphericPressureMbar,
          dive.waterDensityKgM3,
          dive.logVersion,
          dive.dcModel.index,
          null, // dc_firmware: the converter does not capture it yet
          dive.dcVendor,
          dive.dcProduct,
          dive.dcFamily,
          dive.dcModelCode,
          dive.sampleIntervalMs,
          gasMixesJson,
          tanksJson,
          sensorCalibrationJson,
          dive.configuredStackSeconds,
          dive.stackRemainingAtStartSeconds,
          dive.stackRemainingAtEndSeconds,
          parserVersion,
          if (fromDownload) ...[
            dive.dcSerial,
            dive.dcDiveNumber,
            dive.dcFingerprint,
          ],
          diveId,
        ],
      );

      final existingSamples = await tx
          .getOptional('SELECT id FROM dive_samples WHERE id = ?', [diveId]);
      if (existingSamples == null) {
        await tx.execute(
          'INSERT INTO dive_samples '
          '(id, owner_id, ${_sampleColumns.join(', ')}, parser_version, '
          'dc_family, created_at, updated_at, version, sync_status) '
          'VALUES (${List.filled(2 + _sampleColumns.length + 6, '?').join(', ')})',
          [
            diveId,
            _ownerId,
            ...samples,
            parserVersion,
            dive.dcFamily,
            nowMs,
            nowMs,
            1,
            0,
          ],
        );
      } else {
        await tx.execute(
          'UPDATE dive_samples SET owner_id = COALESCE(owner_id, ?), '
          '${_sampleColumns.map((c) => '$c = ?').join(', ')}, '
          'parser_version = ?, dc_family = ?, updated_at = ?, '
          'version = COALESCE(version, 0) + 1 WHERE id = ?',
          [_ownerId, ...samples, parserVersion, dive.dcFamily, nowMs, diveId],
        );
      }

      // The sync gate filters carry rows by dc_family; keep it in step.
      await tx.execute(
        'UPDATE dive_bailout_carry SET dc_family = ?, updated_at = ?, '
        'version = COALESCE(version, 0) + 1 '
        'WHERE dive_id = ? AND dc_family IS NOT ?',
        [dive.dcFamily, nowMs, diveId, dive.dcFamily],
      );
      // An unchanged own gas list means an unchanged merged list too, so no
      // cylinder row needs to move (and none is touched).
      if (!_sameGasList(oldMixes, dive.gasMixes)) {
        await _remapCylindersForRefreshTx(
            tx, diveId, oldMixes, dive.gasMixes, nowMs);
      }
      return true;
    });
  }

  /// Same O2, He and diluent flag, in the same order.
  static bool _sameGasList(List<DiveGasMix> a, List<DiveGasMix> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].oxygenPercent != b[i].oxygenPercent ||
          a[i].heliumPercent != b[i].heliumPercent ||
          a[i].isDiluent != b[i].isDiluent) {
        return false;
      }
    }
    return true;
  }

  /// Remaps the cylinder rows a refresh of [diveId] can affect. A merged
  /// dive's rows live under the group's annotations dive (its earliest
  /// member) and are keyed by the merged gas list, so they are remapped
  /// against the group's old and new merged lists; the refreshed dive's own
  /// rows, when it is another member, follow its own lists.
  Future<void> _remapCylindersForRefreshTx(
    dynamic tx,
    String diveId,
    List<DiveGasMix> oldMixes,
    List<DiveGasMix> newMixes,
    int nowMs,
  ) async {
    final link = await tx.getOptional(
        'SELECT group_id FROM dive_merge_links '
        'WHERE id = ? AND deleted_at IS NULL',
        [diveId]);
    if (link != null) {
      final rows = await tx.getAll(
        'SELECT d.id AS id, d.gas_mixes_json AS gas_mixes_json '
        'FROM dive_merge_links l JOIN dives d ON d.id = l.id '
        'WHERE l.group_id = ? AND l.deleted_at IS NULL '
        'AND d.deleted_at IS NULL '
        'ORDER BY d.start_time ASC, d.id ASC',
        [link['group_id']],
      );
      final ids = [for (final r in rows) r['id'] as String];
      // A group with one live member (the other is deleted) shows as a single
      // dive, keyed by its own raw gas list.
      if (ids.length >= 2 && ids.contains(diveId)) {
        // The dives row already holds the new list; the old one is [oldMixes].
        final others = [
          for (final r in rows) _decodeMixes(r['gas_mixes_json'] as String?),
        ];
        List<List<DiveGasMix>> listsWith(List<DiveGasMix> mine) => [
              for (var i = 0; i < ids.length; i++)
                ids[i] == diveId ? mine : others[i],
            ];
        final oldMerged = mergeGasMixLists(listsWith(oldMixes)).mixes;
        final newMerged = mergeGasMixLists(listsWith(newMixes)).mixes;
        await _remapDiveCylindersTx(tx, ids.first, oldMerged, newMerged, nowMs);
        if (ids.first == diveId) return;
      }
    }
    await _remapDiveCylindersTx(tx, diveId, oldMixes, newMixes, nowMs);
  }

  List<DiveGasMix> _decodeMixes(String? json) {
    if (json == null) return const [];
    try {
      return [
        for (final m in jsonDecode(json) as List)
          DiveGasMix.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Moves the dive's live `dive_cylinders` rows to follow their gas mix.
  /// Ids are `'<dive_id>:<gas_mix_index>'`. A row that moves is soft-deleted
  /// at its old id and written (or revived) at the new one.
  Future<void> _remapDiveCylindersTx(
    dynamic tx,
    String diveId,
    List<DiveGasMix> oldMixes,
    List<DiveGasMix> newMixes,
    int nowMs,
  ) async {
    final rows = await tx.getAll(
      'SELECT gas_mix_index, cylinder_id FROM dive_cylinders '
      'WHERE dive_id = ? AND deleted_at IS NULL',
      [diveId],
    );
    if (rows.isEmpty) return;
    final oldRows = <int, String?>{
      for (final r in rows)
        (r['gas_mix_index'] as num).toInt(): r['cylinder_id'] as String?,
    };
    final newRows = remapCylinderRows(
      oldMixes: oldMixes,
      newMixes: newMixes,
      rowsByIndex: oldRows,
    );

    for (final i in oldRows.keys) {
      if (newRows.containsKey(i)) continue;
      await tx.execute(
        'UPDATE dive_cylinders SET owner_id = COALESCE(owner_id, ?), '
        'deleted_at = ?, updated_at = ?, version = COALESCE(version, 0) + 1 '
        'WHERE id = ?',
        [_ownerId, nowMs, nowMs, '$diveId:$i'],
      );
    }
    for (final e in newRows.entries) {
      if (oldRows.containsKey(e.key) && oldRows[e.key] == e.value) continue;
      // An empty row whose mix is gone says nothing worth keeping.
      if (e.key < 0 && e.value == null && !oldRows.containsKey(e.key)) {
        continue;
      }
      final id = '$diveId:${e.key}';
      final existing = await tx
          .getOptional('SELECT version FROM dive_cylinders WHERE id = ?', [id]);
      if (existing == null) {
        await tx.execute(
          'INSERT INTO dive_cylinders '
          '(id, owner_id, dive_id, gas_mix_index, cylinder_id, '
          'created_at, updated_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [id, _ownerId, diveId, e.key, e.value, nowMs, nowMs, null, 1, 0],
        );
      } else {
        await tx.execute(
          'UPDATE dive_cylinders SET owner_id = COALESCE(owner_id, ?), '
          'cylinder_id = ?, deleted_at = NULL, updated_at = ?, '
          'version = COALESCE(version, 0) + 1 WHERE id = ?',
          [_ownerId, e.value, nowMs, id],
        );
      }
    }
  }

  /// Writes the raw blob under [diveId]. If the local write throws, the dive
  /// is marked `rawBlobMissing` and the import still succeeds (spec section
  /// 6); a successful write clears the mark.
  Future<void> _storeRawBlob(String diveId, Uint8List rawBlob) async {
    try {
      await _drift.into(_drift.diveRawBlobs).insertOnConflictUpdate(
            DiveRawBlobsCompanion.insert(diveId: diveId, rawBlob: rawBlob),
          );
    } catch (e, st) {
      developer.log('raw blob write failed for $diveId',
          error: e, stackTrace: st);
      try {
        await _drift.into(_drift.diveImportMarks).insertOnConflictUpdate(
              DiveImportMarksCompanion(
                diveId: Value(diveId),
                rawBlobMissing: const Value(true),
              ),
            );
      } catch (e2, st2) {
        developer.log('raw-blob-missing mark failed for $diveId',
            error: e2, stackTrace: st2);
      }
      return;
    }
    try {
      await (_drift.update(_drift.diveImportMarks)
            ..where((t) => t.diveId.equals(diveId)))
          .write(const DiveImportMarksCompanion(
              rawBlobMissing: Value(false)));
    } catch (_) {
      // The blob is stored; a stale mark only re-lists the dive once.
    }
  }
}
