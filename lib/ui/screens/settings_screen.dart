import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:powersync/powersync.dart' hide SyncStatus, Column;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../../dev/fixture_seeder.dart';
import '../../sync/attachments/attachment_object_wiper.dart';
import '../../sync/cloud/auth_service.dart';
import '../../shearwater/ble/ble_debug_logger.dart';
import '../../sync/cloud/cloud_data_wiper.dart';
import '../../sync/cloud/drift_crud_quarantine.dart';
import '../../sync/cloud/sync_status_source.dart';
import '../../sync/subsurface_git/bootstrap_importer.dart';
import '../../sync/subsurface_git/credentials.dart';
import '../../sync/subsurface_git/sync_orchestrator.dart';
import '../dev/widgetbook_screen.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/subsurface_sync_section.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsNotifier notifier;
  final AuthService? authService;
  final SyncStatusSource? syncStatusSource;
  /// Optional — when both are provided, the Danger zone "Reset local data"
  /// tile is rendered. Tests typically omit them.
  final AppDatabase? db;
  final PowerSyncDatabase? powerSyncDb;
  /// Optional — wires the "also delete cloud data" checkbox in the reset
  /// dialog. Without it the checkbox is hidden and reset stays local-only.
  final CloudDataWiper? cloudDataWiper;

  /// Optional — when present, the Reset-Everything path also sweeps R2
  /// objects so the user's storage bill doesn't carry orphans after the
  /// cloud rows are gone. Best-effort; failures are logged.
  final AttachmentObjectWiper? attachmentObjectWiper;

  /// Optional — when all three of [subsurfaceOrchestrator],
  /// [subsurfaceCredentials], and [diveDao] are non-null, the
  /// "Subsurface sync" card is rendered. Tests omit them and the section
  /// is hidden, so existing settings-screen tests stay unchanged.
  final SubsurfaceSyncOrchestrator? subsurfaceOrchestrator;
  final SubsurfaceCredentialsSource? subsurfaceCredentials;
  final DiveDao? diveDao;

  /// Optional — when present (and the rest of the Subsurface trio is
  /// also wired), the section renders a second "Import from Subsurface"
  /// button that triggers a one-shot bootstrap import. The shell
  /// instantiates this alongside the orchestrator at app boot.
  final SubsurfaceBootstrapImporter? subsurfaceBootstrapImporter;

  const SettingsScreen({
    super.key,
    required this.notifier,
    this.authService,
    this.syncStatusSource,
    this.db,
    this.powerSyncDb,
    this.cloudDataWiper,
    this.attachmentObjectWiper,
    this.subsurfaceOrchestrator,
    this.subsurfaceCredentials,
    this.diveDao,
    this.subsurfaceBootstrapImporter,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final auth = widget.authService;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      // Tap-outside-to-dismiss + drag-to-dismiss for the numeric
      // keyboard. Several settings rows (blender prices, OC SAC,
      // temps, etc.) open the number pad which has no Return key on
      // iOS — without this the diver gets trapped behind the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListenableBuilder(
        listenable: widget.notifier,
        builder: (context, _) {
          return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
          if (auth != null)
            ListenableBuilder(
              listenable: auth,
              builder: (_, _) => _AccountSection(
                authService: auth,
                syncStatusSource: widget.syncStatusSource,
              ),
            ),
          SwitchListTile(
            title: const Text('Use speed coloured graph'),
            subtitle: const Text(
                'Colour the depth trace by vertical speed (red above 9 m/min)'),
            value: widget.notifier.useSpeedColoredGraph,
            onChanged: (v) => widget.notifier.setUseSpeedColoredGraph(v),
          ),
          ListenableBuilder(
            listenable: widget.notifier,
            builder: (context, _) {
              return SwitchListTile(
                title: const Text('Count O₂ as narcotic in END'),
                subtitle: const Text(
                    'On: N₂ + O₂ both count (TDI/IANTD/US-Navy). Off: only N₂ counts (GUE/DIR).'),
                value: widget.notifier.endCountsOxygen,
                onChanged: (v) => widget.notifier.setEndCountsOxygen(v),
              );
            },
          ),
          ListenableBuilder(
            listenable: widget.notifier,
            builder: (context, _) {
              final value = widget.notifier.watermarkOpacity;
              return ListTile(
                title: const Text('Watermark opacity'),
                subtitle: Text(value == 0
                    ? 'Hidden'
                    : '${(value * 100).toStringAsFixed(0)}%'),
                trailing: SizedBox(
                  width: 180,
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 0.20,
                    divisions: 20,
                    onChanged: (v) => widget.notifier.setWatermarkOpacity(v),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Bailout planning',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            title: const Text('Bailout SAC — bottom phase'),
            subtitle: Text(
                '${widget.notifier.bailoutSacBottom} L/min — used until ascent slows at first switch or half-pressure'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutSacBottom.toDouble(),
                min: 10,
                max: 60,
                divisions: 50,
                onChanged: (v) =>
                    widget.notifier.setBailoutSacBottom(v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Bailout SAC — deco phase'),
            subtitle: Text(
                '${widget.notifier.bailoutSacDeco} L/min — used from first deco stop to surface'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutSacDeco.toDouble(),
                min: 10,
                max: 60,
                divisions: 50,
                onChanged: (v) =>
                    widget.notifier.setBailoutSacDeco(v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Ascent rate — fast (bottom to first stop)'),
            subtitle: Text(
                '${widget.notifier.bailoutAscentRateFast} m/min — used from depth to first deco stop'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutAscentRateFast.toDouble(),
                min: 3,
                max: 30,
                divisions: 27,
                onChanged: (v) =>
                    widget.notifier.setBailoutAscentRateFast(v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Ascent rate — slow (deco stops)'),
            subtitle: Text(
                '${widget.notifier.bailoutAscentRateSlow} m/min — used between deco stops and to the surface'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutAscentRateSlow.toDouble(),
                min: 3,
                max: 30,
                divisions: 27,
                onChanged: (v) =>
                    widget.notifier.setBailoutAscentRateSlow(v.round()),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Diluent is bailout-capable (GUE / D7 config)'),
            subtitle: const Text(
                'Off: assumes 2–3 L diluent, recommends a bottom-mix BO cylinder. '
                'On: assumes diluent is sized for OC bailout.'),
            value: widget.notifier.gueDiluentConfig,
            onChanged: (v) => widget.notifier.setGueDiluentConfig(v),
          ),
          SwitchListTile(
            title: const Text('6.8 L / 300 bar stage available'),
            subtitle: const Text(
                'Include a 6.8 L 300 bar stage when computing bailout gas volumes.'),
            value: widget.notifier.tank68L300Available,
            onChanged: (v) => widget.notifier.setTank68L300Available(v),
          ),
          SwitchListTile(
            title: const Text('12 L / 300 bar stage available'),
            subtitle: const Text(
                'Include a 12 L 300 bar stage when computing bailout gas volumes.'),
            value: widget.notifier.tank12L300Available,
            onChanged: (v) => widget.notifier.setTank12L300Available(v),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Gas blending',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            title: const Text('O₂ price per litre'),
            subtitle: Text(
                '${widget.notifier.blendOxygenCostPerLitre.toStringAsFixed(3)} / L — '
                'used to cost the O₂ side of a blend'),
            trailing: SizedBox(
              width: 120,
              child: TextFormField(
                key: const ValueKey('settings-blend-o2-cost'),
                initialValue: widget.notifier.blendOxygenCostPerLitre
                    .toStringAsFixed(3),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null) {
                    widget.notifier.setBlendOxygenCostPerLitre(v);
                  }
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('He price per litre'),
            subtitle: Text(
                '${widget.notifier.blendHeliumCostPerLitre.toStringAsFixed(3)} / L — '
                'used to cost the helium side of a blend'),
            trailing: SizedBox(
              width: 120,
              child: TextFormField(
                key: const ValueKey('settings-blend-he-cost'),
                initialValue: widget.notifier.blendHeliumCostPerLitre
                    .toStringAsFixed(3),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null) {
                    widget.notifier.setBlendHeliumCostPerLitre(v);
                  }
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Air / EAN top-off flat fee'),
            subtitle: Text(
                '${widget.notifier.blendAirFlatFee.toStringAsFixed(2)} per fill — '
                'shop fill charge, applied whenever the blend uses a top-off'),
            trailing: SizedBox(
              width: 120,
              child: TextFormField(
                key: const ValueKey('settings-blend-air-fee'),
                initialValue:
                    widget.notifier.blendAirFlatFee.toStringAsFixed(2),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null) widget.notifier.setBlendAirFlatFee(v);
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Default top-off mix'),
            subtitle: Text(
                '${widget.notifier.blendTopoffOxygenPercent}/'
                '${widget.notifier.blendTopoffHeliumPercent} — '
                'pre-fills the top-off field on the Blend tab'),
            trailing: SizedBox(
              width: 180,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      key: const ValueKey('settings-blend-topoff-o2'),
                      initialValue:
                          '${widget.notifier.blendTopoffOxygenPercent}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: '%'),
                      onChanged: (s) {
                        final v = int.tryParse(s);
                        if (v != null) {
                          widget.notifier.setBlendTopoff(v,
                              widget.notifier.blendTopoffHeliumPercent);
                        }
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('/'),
                  ),
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      key: const ValueKey('settings-blend-topoff-he'),
                      initialValue:
                          '${widget.notifier.blendTopoffHeliumPercent}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: '%'),
                      onChanged: (s) {
                        final v = int.tryParse(s);
                        if (v != null) {
                          widget.notifier.setBlendTopoff(
                              widget.notifier.blendTopoffOxygenPercent, v);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text('Default fill order'),
            subtitle: const Text(
                'Used as the starting fill order on the Blend tab; '
                'override per blend on the tab itself.'),
            trailing: SizedBox(
              width: 200,
              child: DropdownButton<String>(
                key: const ValueKey('settings-blend-sequence'),
                value: widget.notifier.blendFillSequence,
                isDense: true,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'heThenO2ThenTopoff',
                    child: Text('He → O₂ → top-off'),
                  ),
                  DropdownMenuItem(
                    value: 'o2ThenHeThenTopoff',
                    child: Text('O₂ → He → top-off'),
                  ),
                  DropdownMenuItem(
                    value: 'o2ThenTopoffThenHe',
                    child: Text('O₂ → top-off → He'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) widget.notifier.setBlendFillSequence(v);
                },
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Real-gas Z-factor correction'),
            subtitle: const Text(
                'On: van der Waals real-gas math (matches reference '
                'blender tools). Off: ideal-gas math.'),
            value: widget.notifier.blendUseRealGas,
            onChanged: (v) => widget.notifier.setBlendUseRealGas(v),
          ),
          ListTile(
            title: const Text('Default fill temperature'),
            subtitle: Text(
                '${widget.notifier.blendFillTempC.toStringAsFixed(0)} °C — '
                'cylinder temperature during blending; affects how many '
                'moles fit at gauge pressure'),
            trailing: SizedBox(
              width: 100,
              child: TextFormField(
                key: const ValueKey('settings-blend-fill-temp'),
                initialValue: widget.notifier.blendFillTempC.toStringAsFixed(0),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: const InputDecoration(suffixText: '°C'),
                onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null) widget.notifier.setBlendFillTempC(v);
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Default settled temperature'),
            subtitle: Text(
                '${widget.notifier.blendSettledTempC.toStringAsFixed(0)} °C — '
                'where the cylinder ends up after cooling; when this '
                'differs from fill temp the blender adds hot-fill '
                'compensation'),
            trailing: SizedBox(
              width: 100,
              child: TextFormField(
                key: const ValueKey('settings-blend-settled-temp'),
                initialValue:
                    widget.notifier.blendSettledTempC.toStringAsFixed(0),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: const InputDecoration(suffixText: '°C'),
                onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null) widget.notifier.setBlendSettledTempC(v);
                },
              ),
            ),
          ),
          if (widget.subsurfaceOrchestrator != null &&
              widget.subsurfaceCredentials != null &&
              widget.diveDao != null) ...[
            const Divider(height: 32),
            SubsurfaceSyncSection(
              credentials: widget.subsurfaceCredentials!,
              isPlatformSupported:
                  widget.subsurfaceOrchestrator!.isPlatformSupported,
              onSync: widget.subsurfaceOrchestrator!.syncNow,
              lastSyncedAt: widget.diveDao!.lastSubsurfaceUploadedAt,
              onBootstrapImport: widget.subsurfaceBootstrapImporter == null
                  ? null
                  : () => widget.subsurfaceBootstrapImporter!.import(),
            ),
          ],
          if (widget.db != null && widget.powerSyncDb != null) ...[
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Danger zone',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Reset local data'),
              subtitle: const Text(
                  'Wipes imported dives + local sync state. Cloud data is unaffected; if signed in, it re-syncs after restart.'),
              onTap: _confirmAndResetLocalData,
            ),
          ],
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Diagnostics',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Share BLE debug log'),
            subtitle: const Text(
                'Exports the Bluetooth import trace so the developer can diagnose import failures. The file contains no dive content — only protocol events and timings.'),
            onTap: _shareBleDebugLog,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Force-stamp owner_id on local dives'),
            subtitle: const Text(
                'Rewrites owner_id on every local dive + sample to the current signed-in user, then PowerSync uploads them. Use when dives imported under a different (or no) account need to be reassigned to this account.'),
            onTap: _forceStampOwnerId,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Drain upload queue manually'),
            subtitle: const Text(
                'Bypasses PowerSync\'s upload pump and pushes each queued CRUD op directly to Supabase. Use when the queue is stuck (ps_crud is non-empty, sync status shows uploading=false, lastSyncedAt=never). Slow — one HTTP request per op.'),
            onTap: _drainQueueManually,
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: GestureDetector(
              onLongPress: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const WidgetbookScreen()),
              ),
              child: Text(
                'Anchorline',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
              ],
            );
        },
      ),
      ),
    );
  }

  Future<void> _forceStampOwnerId() async {
    final psDb = widget.powerSyncDb;
    final userId = widget.authService?.currentUser?.id;
    final messenger = ScaffoldMessenger.of(context);

    if (psDb == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('PowerSync is not available on this build.'),
      ));
      return;
    }
    if (userId == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Sign in first — there is no current user to stamp.'),
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force-stamp owner_id?'),
        content: Text(
          'Rewrites owner_id on every local dive + sample to the '
          'currently signed-in account ($userId).\n\n'
          'Rows with the wrong owner_id (or none) will then upload to '
          'the cloud on the next sync. This is a one-shot recovery for '
          'dives that were imported under a different (or no) account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stamp'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final report = StringBuffer();
    try {
      Future<int> countTotal(String table) async {
        final r = await psDb.getOptional('SELECT COUNT(*) AS n FROM $table');
        return (r?['n'] as int?) ?? 0;
      }

      Future<int> countMismatched(String table) async {
        final r = await psDb.getOptional(
          'SELECT COUNT(*) AS n FROM $table '
          'WHERE owner_id IS NULL OR owner_id != ?',
          [userId],
        );
        return (r?['n'] as int?) ?? 0;
      }

      report.writeln('User: $userId');
      report.writeln('');

      final divesTotal = await countTotal('dives');
      final samplesTotal = await countTotal('dive_samples');
      final divesToStamp = await countMismatched('dives');
      final samplesToStamp = await countMismatched('dive_samples');
      report.writeln('Local PowerSync rows:');
      report.writeln('  dives: $divesTotal (mismatched owner: $divesToStamp)');
      report.writeln(
          '  dive_samples: $samplesTotal (mismatched owner: $samplesToStamp)');
      report.writeln('');

      // ps_crud holds operations waiting to be uploaded. If this is > 0
      // and not draining, RLS is probably rejecting the upsert.
      final crudTotal = await countTotal('ps_crud');
      report.writeln('Upload queue (ps_crud): $crudTotal');
      if (crudTotal > 0) {
        final byTable = await psDb.getAll(
          "SELECT json_extract(data, '\$.type') AS t, COUNT(*) AS n "
          'FROM ps_crud GROUP BY t ORDER BY n DESC',
        );
        for (final r in byTable) {
          report.writeln('  ${r['t']}: ${r['n']}');
        }
        // Peek at the oldest pending op so we can see what it's trying.
        final firstRow = await psDb.getOptional(
          'SELECT data FROM ps_crud ORDER BY id LIMIT 1',
        );
        if (firstRow != null) {
          final data = firstRow['data'] as String?;
          if (data != null) {
            final preview = data.length > 240 ? '${data.substring(0, 240)}…' : data;
            report.writeln('  oldest op preview: $preview');
          }
        }
      }
      report.writeln('');

      // Ops the connector permanently quarantined so they couldn't wedge the
      // queue (issue #2). A non-zero count means those changes never synced.
      final db = widget.db;
      if (db != null) {
        final quarantined = await DriftCrudQuarantine(db).count();
        report.writeln('Changes that couldn\'t sync (quarantined): '
            '$quarantined');
        report.writeln('');
      }

      // PowerSync sync status.
      final s = widget.syncStatusSource?.currentStatus;
      if (s != null) {
        report.writeln('Sync status:');
        report.writeln('  connected: ${s.connected}');
        report.writeln('  uploading: ${s.uploading}');
        report.writeln('  downloading: ${s.downloading}');
        report.writeln('  lastSyncedAt: ${s.lastSyncedAt ?? "(never)"}');
        // Surface the swallowed upload/download failure — when the queue is
        // wedged on a rejected CRUD op this names the offending table/row +
        // Postgres error (see issue #2).
        report.writeln('  uploadError: ${s.uploadError ?? "(none)"}');
        report.writeln('  downloadError: ${s.downloadError ?? "(none)"}');
        report.writeln('');
      }

      // Stamp owner_id on every synced table that has the column.
      const syncTables = [
        'dives',
        'dive_samples',
        'dive_computers',
        'oxygen_cells',
        'scrubber_sessions',
        'dive_annotations',
        'cylinders',
        'dive_cylinders',
        'pressure_mappings',
        'dive_attachments',
      ];
      report.writeln('Stamped owner_id on live rows:');
      for (final t in syncTables) {
        try {
          final before = await psDb.getOptional(
            'SELECT COUNT(*) AS n FROM $t '
            'WHERE owner_id IS NULL OR owner_id != ?',
            [userId],
          );
          final n = (before?['n'] as int?) ?? 0;
          if (n == 0) continue;
          await psDb.execute(
            'UPDATE $t SET owner_id = ? '
            'WHERE owner_id IS NULL OR owner_id != ?',
            [userId, userId],
          );
          report.writeln('  $t: stamped $n');
        } catch (e) {
          report.writeln('  $t: skipped ($e)');
        }
      }
      report.writeln('');

      // Patch ps_crud entries whose PUT data is missing/wrong owner_id.
      // PowerSync sends `data.data` to Supabase as the row body; if RLS
      // rejects one row the whole batch retries forever and uploading
      // stays false. Rewriting the JSON in-place is invasive but safe —
      // we change only the owner_id field, nothing else.
      final crudRows = await psDb.getAll(
        'SELECT id, data FROM ps_crud ORDER BY id',
      );
      var patched = 0;
      var skippedNonPut = 0;
      for (final r in crudRows) {
        final crudId = r['id'];
        final raw = r['data'] as String?;
        if (raw == null) continue;
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['op'] != 'PUT') {
            skippedNonPut++;
            continue;
          }
          final inner = parsed['data'];
          if (inner is! Map<String, dynamic>) continue;
          final current = inner['owner_id'];
          if (current == userId) continue;
          inner['owner_id'] = userId;
          await psDb.execute(
            'UPDATE ps_crud SET data = ? WHERE id = ?',
            [jsonEncode(parsed), crudId],
          );
          patched++;
        } catch (e) {
          report.writeln('  ps_crud #$crudId: parse/patch failed ($e)');
        }
      }
      report.writeln(
          'Patched $patched queued PUT op(s) ($skippedNonPut non-PUT skipped).');

      // Replay the actual oldest pending op from ps_crud against Supabase.
      // This is exactly what PowerSync's uploader does — if it fails, the
      // error tells us why the queue isn't draining.
      final firstCrud = await psDb.getOptional(
        'SELECT id, data FROM ps_crud ORDER BY id LIMIT 1',
      );
      if (firstCrud != null) {
        final data = firstCrud['data'] as String?;
        report.writeln('');
        report.writeln('Replay oldest ps_crud op (#${firstCrud['id']}):');
        if (data == null) {
          report.writeln('  (no data column)');
        } else {
          try {
            final parsed = jsonDecode(data) as Map<String, dynamic>;
            final opType = parsed['op'] as String?;
            final table = parsed['type'] as String?;
            final rowId = parsed['id'] as String?;
            final rowData = parsed['data'] as Map<String, dynamic>?;
            report.writeln('  op=$opType table=$table id=$rowId');
            if (rowData != null) {
              report.writeln('  cols: ${rowData.keys.toList()..sort()}');
            }
            if (table == null || rowId == null) {
              report.writeln('  → cannot replay (missing table/id)');
            } else {
              try {
                final client = Supabase.instance.client;
                switch (opType) {
                  case 'PUT':
                    await client.from(table).upsert({
                      ...?rowData,
                      'id': rowId,
                    });
                    report.writeln('  → OK');
                  case 'PATCH':
                    if (rowData != null) {
                      await client.from(table).update(rowData).eq('id', rowId);
                      report.writeln('  → OK');
                    } else {
                      report.writeln('  → skipped (no PATCH data)');
                    }
                  case 'DELETE':
                    await client.from(table).delete().eq('id', rowId);
                    report.writeln('  → OK');
                  default:
                    report.writeln('  → unknown op type');
                }
              } catch (e) {
                report.writeln('  → ERROR: $e');
              }
            }
          } catch (e) {
            report.writeln('  → parse failed: $e');
            final preview = data.length > 240 ? '${data.substring(0, 240)}…' : data;
            report.writeln('  raw: $preview');
          }
        }
      }
    } catch (e, st) {
      debugPrint('Force-stamp diag failed: $e\n$st');
      report.writeln('');
      report.writeln('FAILED: $e');
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force-stamp diagnostic'),
        content: SingleChildScrollView(
          child: SelectableText(
            report.toString(),
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report.toString()));
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _drainQueueManually() async {
    final psDb = widget.powerSyncDb;
    final userId = widget.authService?.currentUser?.id;
    final messenger = ScaffoldMessenger.of(context);

    if (psDb == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('PowerSync is not available on this build.'),
      ));
      return;
    }
    if (userId == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Sign in first — no Supabase session to push with.'),
      ));
      return;
    }

    final totalBefore = await psDb.getOptional(
      'SELECT COUNT(*) AS n FROM ps_crud',
    );
    final qSize = (totalBefore?['n'] as int?) ?? 0;
    if (qSize == 0) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Queue is empty — nothing to drain.'),
      ));
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drain upload queue manually?'),
        content: Text(
          'Pushes $qSize queued CRUD operation(s) straight to Supabase, '
          'bypassing PowerSync\'s built-in upload pump. Successful ops are '
          'removed from ps_crud. Failed ops are left in place so you can '
          'inspect them afterwards.\n\n'
          'This is slow — one HTTP request per op. Keep the app open '
          'until it finishes; closing the app mid-drain leaves the rest '
          'in the queue and you can re-run this to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Drain $qSize'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text('Draining $qSize op(s) — this may take a while.'),
      duration: const Duration(seconds: 6),
    ));

    final supa = Supabase.instance.client;
    var processed = 0;
    var failed = 0;
    final errors = <String, int>{}; // error message → count
    var lastId = 0;

    // Walk ps_crud in id order, batching 50 at a time. Advancing `lastId`
    // past every op we touch (success or fail) prevents an infinite loop
    // on a poison-pill row.
    while (mounted) {
      final batch = await psDb.getAll(
        'SELECT id, data FROM ps_crud WHERE id > ? ORDER BY id LIMIT 50',
        [lastId],
      );
      if (batch.isEmpty) break;
      for (final row in batch) {
        final crudId = (row['id'] as int?) ?? 0;
        lastId = crudId;
        final raw = row['data'] as String?;
        if (raw == null) {
          await psDb.execute('DELETE FROM ps_crud WHERE id = ?', [crudId]);
          continue;
        }
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          final op = parsed['op'] as String?;
          final table = parsed['type'] as String?;
          final id = parsed['id'] as String?;
          final data = parsed['data'];
          if (table == null || id == null) {
            // Malformed entry; remove to keep the queue moving.
            await psDb.execute('DELETE FROM ps_crud WHERE id = ?', [crudId]);
            continue;
          }
          switch (op) {
            case 'PUT':
              await supa.from(table).upsert({
                ...?(data as Map<String, dynamic>?),
                'id': id,
              });
            case 'PATCH':
              if (data is Map<String, dynamic>) {
                await supa.from(table).update(data).eq('id', id);
              }
            case 'DELETE':
              await supa.from(table).delete().eq('id', id);
            default:
              // Unknown op — drop it so the drain continues.
              await psDb.execute('DELETE FROM ps_crud WHERE id = ?', [crudId]);
              continue;
          }
          await psDb.execute('DELETE FROM ps_crud WHERE id = ?', [crudId]);
          processed++;
        } catch (e) {
          failed++;
          final key = e.toString().split('\n').first;
          errors[key] = (errors[key] ?? 0) + 1;
          debugPrint('Drain: ps_crud #$crudId failed: $e');
          // Don't delete — leave failed ops in place for inspection.
        }
      }
    }

    if (!mounted) return;
    final remaining = await psDb.getOptional(
      'SELECT COUNT(*) AS n FROM ps_crud',
    );
    final remainingCount = (remaining?['n'] as int?) ?? 0;

    final report = StringBuffer()
      ..writeln('Drain complete.')
      ..writeln('')
      ..writeln('Pushed:      $processed')
      ..writeln('Failed:      $failed')
      ..writeln('ps_crud now: $remainingCount');
    if (errors.isNotEmpty) {
      report.writeln('');
      report.writeln('Failure reasons:');
      final sorted = errors.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sorted.take(5)) {
        final preview = entry.key.length > 200
            ? '${entry.key.substring(0, 200)}…'
            : entry.key;
        report.writeln('  ${entry.value}× $preview');
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drain queue result'),
        content: SingleChildScrollView(
          child: SelectableText(
            report.toString(),
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report.toString()));
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareBleDebugLog() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Force-flush any buffered writes before exporting.
      await BleDebugLogger.instance.flush();
      final path = await BleDebugLogger.instance.filePath();
      final file = File(path);
      if (!file.existsSync() || (await file.length()) == 0) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'No BLE log yet — trigger an import to populate it, then try again.'),
        ));
        return;
      }
      await Share.shareXFiles(
        [XFile(path, name: 'anchorline-ble-debug.log')],
        subject: 'Anchorline BLE debug log',
        text:
            'Bluetooth import trace from Anchorline. No dive content — only '
            'protocol events and timings.',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _confirmAndResetLocalData() async {
    final db = widget.db;
    final psDb = widget.powerSyncDb;
    if (db == null || psDb == null) return;

    final wiper = widget.cloudDataWiper;
    final canWipeCloud =
        wiper != null && (widget.authService?.isSignedIn ?? false);

    var alsoWipeCloud = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Reset data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deletes every imported dive on this device and clears the '
                'local PowerSync cache.\n\n'
                'You will need to quit and reopen the app afterwards.',
              ),
              if (canWipeCloud) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: alsoWipeCloud,
                  onChanged: (v) =>
                      setLocal(() => alsoWipeCloud = v ?? false),
                  title: const Text('Also delete cloud data'),
                  subtitle: const Text(
                      'Permanent. Wipes annotations, cylinders, cells, '
                      'scrubbers, dive computers and pressure mappings '
                      'from your account on every device.'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
                foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(alsoWipeCloud ? 'Reset everything' : 'Reset'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // R2 objects first — once `wiper.wipeAllForCurrentUser()` deletes
      // the dive_attachments rows in Postgres, PowerSync replicates
      // those deletes down and the local cache loses the storage_keys
      // we'd need to delete the objects.
      if (alsoWipeCloud) {
        await widget.attachmentObjectWiper?.wipeAllForCurrentUser();
      }
      // Cloud rows next so logical-replication deletes propagate to
      // other devices before this device cuts itself off from sync.
      if (alsoWipeCloud && wiper != null) {
        await wiper.wipeAllForCurrentUser();
      }
      // Drift: clear all imported-dive related rows. Equipment / annotation
      // tables in Drift are no longer used (PowerSync owns them), but
      // we still wipe them to keep the local file fully fresh.
      await db.transaction(() async {
        await db.customStatement('DELETE FROM dive_samples');
        await db.customStatement('DELETE FROM dives');
        await db.customStatement('DELETE FROM import_states');
        await db.customStatement('DELETE FROM dive_annotations');
        await db.customStatement('DELETE FROM dive_computers');
        await db.customStatement('DELETE FROM oxygen_cells');
        await db.customStatement('DELETE FROM scrubber_sessions');
        await db.customStatement('DELETE FROM cylinders');
        await db.customStatement('DELETE FROM pressure_mappings');
        await db.customStatement('DELETE FROM dive_cylinders');
      });
      // PowerSync: disconnect + clear local SQLite. Re-sync on next start.
      //
      // `disconnectAndClear()` is supposed to remove every `ps_data__*`
      // row but has been observed leaving rows behind (2026-05-10
      // incident: 13 dives survived a Reset Everything). We follow it
      // with an explicit DELETE of every PowerSync-managed local table
      // as a fallback, so a fresh bootstrap-import sees an empty DB and
      // re-parses everything with the current mapper instead of
      // dedup-skipping stale rows. Wrapping in try/catch because the
      // table list isn't part of any contract — if PowerSync renames
      // its local tables in a future SDK rev, the explicit DELETE
      // becomes a no-op rather than blocking the reset.
      await psDb.disconnectAndClear();
      try {
        const psTables = [
          'ps_data__dives',
          'ps_data__dive_samples',
          'ps_data__dive_annotations',
          'ps_data__dive_attachments',
          'ps_data__dive_computers',
          'ps_data__dive_cylinders',
          'ps_data__cylinders',
          'ps_data__oxygen_cells',
          'ps_data__pressure_mappings',
          'ps_data__scrubber_sessions',
          'ps_crud',
          'ps_oplog',
          'ps_buckets',
        ];
        for (final t in psTables) {
          await psDb.execute('DELETE FROM $t');
        }
      } catch (e) {
        debugPrint('Belt-and-braces PowerSync wipe partial: $e');
      }
      // Stop fixture re-seeding from re-populating the empty DB on next
      // launch. Reinstalling the app clears this flag.
      await markFixturesBlocked();
    } catch (e, st) {
      debugPrint('Reset data failed: $e\n$st');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(alsoWipeCloud
          ? 'Local + cloud data cleared. Please quit and reopen the app.'
          : 'Local data cleared. Please quit and reopen the app.'),
      duration: const Duration(seconds: 8),
    ));
  }
}

class _AccountSection extends StatelessWidget {
  final AuthService authService;
  final SyncStatusSource? syncStatusSource;
  const _AccountSection({
    required this.authService,
    this.syncStatusSource,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: authService.isSignedIn
                ? _SignedInTile(
                    authService: authService,
                    syncStatusSource: syncStatusSource,
                  )
                : _SignInTile(authService: authService),
          ),
        ],
      ),
    );
  }
}

class _SignInTile extends StatelessWidget {
  final AuthService authService;
  const _SignInTile({required this.authService});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: const Text('Sign in to enable cloud sync'),
      subtitle: const Text('Optional. The app works fully offline.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openAuthSheet(context, authService),
    );
  }
}

class _SignedInTile extends StatelessWidget {
  final AuthService authService;
  final SyncStatusSource? syncStatusSource;
  const _SignedInTile({
    required this.authService,
    this.syncStatusSource,
  });

  @override
  Widget build(BuildContext context) {
    final email = authService.currentUser?.email ?? '(unknown)';
    final source = syncStatusSource;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text(email),
          subtitle: source == null
              ? const Text('Last synced: never')
              : _SyncStatusRow(source: source),
        ),
        const Divider(height: 0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              onPressed: () => _confirmSignOut(context, authService),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  final SyncStatusSource source;
  const _SyncStatusRow({required this.source});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatusSnapshot>(
      stream: source.statusStream,
      initialData: source.currentStatus,
      builder: (_, snapshot) {
        final s = snapshot.data ?? source.currentStatus;
        return Text(_formatSyncStatus(s));
      },
    );
  }
}

String _formatSyncStatus(SyncStatusSnapshot s) {
  final state = _statusLabel(s);
  final last = s.lastSyncedAt;
  if (last == null) return state;
  return '$state  Last synced: ${_relativeTime(last, DateTime.now())}';
}

String _statusLabel(SyncStatusSnapshot s) {
  if (!s.connected) return '🔴 Offline';
  if (s.uploading || s.downloading) return '🟡 Syncing…';
  return '🟢 Synced';
}

/// Compact relative-time formatting suitable for a status row. Falls back
/// to an absolute date once we cross a day boundary.
String _relativeTime(DateTime when, DateTime now) {
  final diff = now.difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds} sec ago';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m min ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  return DateFormat.yMd().add_Hm().format(when);
}

Future<void> _openAuthSheet(BuildContext context, AuthService auth) {
  // Dialog (rather than modal bottom sheet) avoids a macOS Flutter focus
  // quirk that prevents text-field keyboard input inside a bottom sheet.
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _AuthSheet(authService: auth),
      ),
    ),
  );
}

Future<void> _confirmSignOut(BuildContext context, AuthService auth) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
          'Your local dives stay on the device. Cloud sync will pause until you sign in again.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await auth.signOut();
  messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
}

class _AuthSheet extends StatefulWidget {
  final AuthService authService;
  const _AuthSheet({required this.authService});

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // macOS Flutter has a known race where TextFields inside dialogs
    // don't establish keyboard focus on first paint. Forcing it after
    // the frame settles is the standard workaround.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthResult> Function() op) async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are both required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final res = await op();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res) {
      case AuthSuccess(:final user):
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Signed in as ${user.email ?? user.id}')),
        );
      case AuthEmailConfirmationRequired():
        messenger.showSnackBar(
          const SnackBar(content: Text('Check your inbox to confirm your email')),
        );
      case AuthFailure(:final message):
        setState(() => _error = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cloud sync sign-in',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            enabled: !_busy,
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.authService.signUp(
                            email: _emailCtrl.text.trim(),
                            password: _passwordCtrl.text,
                          )),
                  child: const Text('Create account'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.authService.signIn(
                            email: _emailCtrl.text.trim(),
                            password: _passwordCtrl.text,
                          )),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
