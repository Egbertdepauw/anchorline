import 'package:flutter/material.dart';
import '../notifiers/import_notifier.dart';

class ImportScreen extends StatefulWidget {
  final ImportNotifier notifier;
  final VoidCallback onViewDives;

  const ImportScreen({super.key, required this.notifier, required this.onViewDives});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
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
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.bluetooth, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        const Text('Import Dives', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Connect to your Shearwater dive computer',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => widget.notifier.startScan(),
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
        if (n.mockDeviceAvailable) ...[
          const SizedBox(height: 24),
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

    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (n.deviceInfo != null) ...[
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.bluetooth_connected, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.deviceInfo!.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('S/N ${n.deviceInfo!.serial} · ${n.deviceInfo!.firmware}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ])),
            ]),
          )),
        ],
        const SizedBox(height: 24),
        Text('Found ${n.newDives.length} new dives',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => n.downloadAll(),
          icon: const Icon(Icons.download),
          label: Text('Import ${n.newDives.length} dives'),
        ),
      ],
    ));
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
