import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';

import '../../shearwater/parser/manifest_parser.dart';
import '../notifiers/import_notifier.dart';

class ImportScreen extends StatefulWidget {
  final ImportNotifier notifier;
  final VoidCallback onViewDives;

  const ImportScreen({super.key, required this.notifier, required this.onViewDives});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  /// Dive numbers the user has unchecked in the manifest list. We track
  /// the *excluded* set so a freshly-loaded manifest defaults to "all
  /// selected" without us having to backfill the set every time.
  final Set<int> _excludedDiveNumbers = {};

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

  List<ManifestEntry> _selectedEntries() => widget.notifier.newDives
      .where((e) => !_excludedDiveNumbers.contains(e.diveNumber))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final n = widget.notifier;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: switch (n.state) {
        ImportFlowState.idle => _buildIdle(theme),
        ImportFlowState.scanning => _buildScanning(n, theme),
        ImportFlowState.connecting => _buildConnecting(n, theme),
        ImportFlowState.readingManifest => _buildManifest(n, theme),
        ImportFlowState.downloading => _buildDownloading(n, theme),
        ImportFlowState.done => _buildDone(n, theme),
        ImportFlowState.error => _buildError(n, theme),
      },
    );
  }

  Widget _buildIdle(ThemeData theme) {
    final n = widget.notifier;
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.bluetooth, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        const Text('Import Dives', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Connect to your Shearwater dive computer',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: n.forceFullReimport,
              onChanged: (v) => n.forceFullReimport = v ?? false,
            ),
            GestureDetector(
              onTap: () => n.forceFullReimport = !n.forceFullReimport,
              child: Text('Re-import all dives (ignore prior imports)',
                  style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => n.startScan(),
          icon: const Icon(Icons.search),
          label: const Text('Start Scan'),
        ),
      ],
    ));
  }

  Widget _buildScanning(ImportNotifier n, ThemeData theme) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        const Text('Searching for dive computers...', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text('Make sure your dive computer is in upload mode',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12)),

        // Mock device (debug only)
        if (n.mockDeviceAvailable) ...[
          const SizedBox(height: 16),
          Card(child: ListTile(
            leading: const Icon(Icons.bluetooth_connected),
            title: const Text('Petrel 3 (Mock)'),
            subtitle: const Text('Debug device'),
            onTap: () async {
              await n.selectMockDevice();
              if (n.state == ImportFlowState.readingManifest) {
                await n.readManifestAndFilterNew();
              }
            },
          )),
        ],

        // Real BLE devices
        for (final BluetoothDevice device in n.discoveredDevices) ...[
          const SizedBox(height: 8),
          Card(child: ListTile(
            leading: Icon(Icons.bluetooth, color: theme.colorScheme.primary),
            title: Text(device.platformName.isNotEmpty ? device.platformName : 'Shearwater DC'),
            subtitle: Text(device.remoteId.toString()),
            onTap: () async {
              await n.selectRealDevice(device);
              if (n.state == ImportFlowState.readingManifest) {
                await n.readManifestAndFilterNew();
              }
            },
          )),
        ],

        if (!n.mockDeviceAvailable && n.discoveredDevices.isEmpty) ...[
          const SizedBox(height: 24),
          Text('No devices found yet...',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 12)),
        ],
      ],
    ));
  }

  Widget _buildConnecting(ImportNotifier n, ThemeData theme) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Connecting to ${n.deviceInfo?.model.name ?? 'dive computer'}...',
            style: const TextStyle(fontSize: 16)),
      ],
    ));
  }

  Widget _buildManifest(ImportNotifier n, ThemeData theme) {
    if (n.newDives.isEmpty && n.deviceInfo != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          const Text('All dives already imported', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          FilledButton(onPressed: widget.onViewDives, child: const Text('View Dives')),
        ],
      ));
    }

    final selected = _selectedEntries();
    final fade = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (n.deviceInfo != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.bluetooth_connected, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.deviceInfo!.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('S/N ${n.deviceInfo!.serial} · ${n.deviceInfo!.firmware}',
                    style: TextStyle(fontSize: 12, color: fade)),
              ])),
            ]),
          )),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(
              '${selected.length} of ${n.newDives.length} selected',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _excludedDiveNumbers.isEmpty
                ? null
                : () => setState(_excludedDiveNumbers.clear),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: _excludedDiveNumbers.length == n.newDives.length
                ? null
                : () => setState(() => _excludedDiveNumbers
                    .addAll(n.newDives.map((e) => e.diveNumber))),
            child: const Text('None'),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Tip: import in batches if you have a lot of dives. Petrel '
          'log-mode sessions can time out around the 60-second mark.',
          style: TextStyle(fontSize: 12, color: fade),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: n.newDives.length,
            itemBuilder: (context, i) {
              final entry = n.newDives[i];
              final excluded = _excludedDiveNumbers.contains(entry.diveNumber);
              return CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                controlAffinity: ListTileControlAffinity.leading,
                value: !excluded,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _excludedDiveNumbers.remove(entry.diveNumber);
                  } else {
                    _excludedDiveNumbers.add(entry.diveNumber);
                  }
                }),
                title: Text('Dive #${entry.diveNumber}'),
                subtitle: Text(_formatManifestSubtitle(entry),
                    style: TextStyle(fontSize: 12, color: fade)),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: selected.isEmpty
              ? null
              : () => n.downloadAll(selected),
          icon: const Icon(Icons.download),
          label: Text(selected.length == n.newDives.length
              ? 'Import all ${selected.length} dives'
              : 'Import ${selected.length} selected'),
        ),
      ],
    );
  }

  String _formatManifestSubtitle(ManifestEntry entry) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
            entry.startTimestamp * 1000,
            isUtc: true)
        .toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  Widget _buildDownloading(ImportNotifier n, ThemeData theme) {
    final progress = n.totalToDownload > 0 ? n.downloadedCount / n.totalToDownload : 0.0;
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 80, height: 80, child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: progress, strokeWidth: 6),
            Text('${n.downloadedCount}/${n.totalToDownload}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        )),
        const SizedBox(height: 24),
        if (n.currentDiveNumber != null)
          Text('Downloading dive #${n.currentDiveNumber}...', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text('${n.downloadedCount} of ${n.totalToDownload} imported',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: LinearProgressIndicator(value: progress)),
      ],
    ));
  }

  Widget _buildDone(ImportNotifier n, ThemeData theme) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Imported ${n.downloadedCount} dives',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        if (n.failedCount > 0) ...[
          const SizedBox(height: 8),
          Text('${n.failedCount} failed', style: TextStyle(color: theme.colorScheme.error, fontSize: 14)),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: widget.onViewDives,
          icon: const Icon(Icons.list),
          label: const Text('View Dives'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => widget.notifier.reset(),
          child: const Text('Import More'),
        ),
      ],
    ));
  }

  Widget _buildError(ImportNotifier n, ThemeData theme) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 24),
        Text(n.errorMessage ?? 'An error occurred',
            style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
        if (n.downloadedCount > 0) ...[
          const SizedBox(height: 8),
          Text('${n.downloadedCount} dives were imported successfully',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => n.retry(),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ));
  }
}
