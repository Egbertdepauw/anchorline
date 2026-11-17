import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:libdivecomputer/libdivecomputer.dart';

import '../../build_info.dart';
import '../../devices/dive_download_source.dart';
import '../../devices/libdc/download_share.dart';
import '../../devices/libdc/libdc_tiers.dart';
import '../notifiers/import_notifier.dart';
import '../widgets/libdc_model_picker.dart';

class ImportScreen extends StatefulWidget {
  final ImportNotifier notifier;
  final VoidCallback onViewDives;

  /// Shares a libdivecomputer download's recording. A seam for tests.
  final Future<String?> Function({
    required String recordingText,
    required List<String> extraHeader,
    Rect? origin,
  }) shareDownloadFn;

  const ImportScreen({
    super.key,
    required this.notifier,
    required this.onViewDives,
    this.shareDownloadFn = shareDownload,
  });

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

  List<DiveListing> _selectedEntries() => widget.notifier.newDives
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
    return Center(child: SingleChildScrollView(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.bluetooth, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        const Text('Import Dives', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Connect to your dive computer',
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
        _buildRecordSwitch(n),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => n.startScan(),
          icon: const Icon(Icons.search),
          label: const Text('Start Scan'),
        ),
      ],
    )));
  }

  Widget _buildScanning(ImportNotifier n, ThemeData theme) {
    return Center(child: SingleChildScrollView(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (n.scanEnded) ...[
          const Text('Scan finished', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('scan-again'),
            onPressed: n.scanAgain,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan again'),
          ),
        ] else ...[
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          const Text('Searching for dive computers...', style: TextStyle(fontSize: 16)),
        ],
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

        // Real BLE devices: Shearwater and libdivecomputer ones. Named
        // devices nobody recognises only show up in the model picker.
        for (final r in n.discoveredDevices)
          if (r.kind == ImportDeviceKind.shearwater) ...[
            const SizedBox(height: 8),
            Card(child: ListTile(
              leading: Icon(Icons.bluetooth, color: theme.colorScheme.primary),
              title: Text(r.name.isNotEmpty ? r.name : 'Shearwater DC'),
              subtitle: Text(r.id),
              onTap: () async {
                await n.selectRealDevice(BluetoothDevice.fromId(r.id));
                if (n.state == ImportFlowState.readingManifest) {
                  await n.readManifestAndFilterNew();
                }
              },
            )),
          ] else if (r.kind == ImportDeviceKind.libdc) ...[
            const SizedBox(height: 8),
            _buildLibdcRow(n, theme, r),
          ],

        if (!n.mockDeviceAvailable &&
            !n.discoveredDevices.any((d) => d.kind != ImportDeviceKind.unmatched)) ...[
          const SizedBox(height: 24),
          Text('No devices found yet...',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 12)),
        ],

        const SizedBox(height: 16),
        _buildRecordSwitch(n),
        TextButton(
          onPressed: () => _pickModel(n),
          child: const Text("My computer isn't listed"),
        ),
      ],
    )));
  }

  /// "Record this download": keeps the packets as well as the log, so the
  /// download can be shared with us afterwards.
  Widget _buildRecordSwitch(ImportNotifier n) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: SwitchListTile(
        key: const ValueKey('record-download-switch'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Record this download'),
        subtitle: const Text(
            'Other brands only. Keeps what the computer says so you can '
            'send it to us.'),
        value: n.recordNextDownload,
        onChanged: (v) => n.recordNextDownload = v,
      ),
    );
  }

  /// The row title for the models a name could mean. One product: the vendor
  /// and product, with the advertised name below. Several: the app does not yet
  /// know the model (the computer tells it on connect), so it shows the vendor
  /// and the advertised name and claims no product.
  ({String title, String? subtitle}) _candidateLabel(
      List<LibdcDescriptor> candidates, String advertised) {
    final products = {for (final c in candidates) '${c.vendor} ${c.product}'};
    if (products.length == 1) {
      return (title: products.single, subtitle: advertised);
    }
    final vendors = {for (final c in candidates) c.vendor};
    return (
      title: vendors.length == 1
          ? '${vendors.single} \u00b7 $advertised'
          : advertised,
      subtitle: 'Model found when connected',
    );
  }

  Widget _buildLibdcRow(
      ImportNotifier n, ThemeData theme, ImportScanResult r) {
    final families = {for (final c in r.candidates) c.family};
    final label = _candidateLabel(r.candidates, r.name);
    // Tested only when every family the name could mean is.
    final tested = families.every(isCheckedLibdcFamily);
    return Card(child: ListTile(
      leading: Icon(Icons.bluetooth, color: theme.colorScheme.primary),
      title: Text(label.title),
      subtitle: label.subtitle == null ? null : Text(label.subtitle!),
      trailing: tested
          ? null
          : Chip(
              label: const Text(kNotYetTestedLabel),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
      onTap: () => _connectLibdc(n, r),
    ));
  }

  /// One family connects straight away; a name that several families share
  /// asks which one first. The family decides the protocol; within it the
  /// first candidate stands in for the model.
  Future<void> _connectLibdc(ImportNotifier n, ImportScanResult r) async {
    var chosen = r.candidates.first;
    final byFamily = <int, LibdcDescriptor>{};
    for (final c in r.candidates) {
      byFamily.putIfAbsent(c.family, () => c);
    }
    if (byFamily.length > 1) {
      final pick = await showDialog<LibdcDescriptor>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Which of these is your computer?'),
          children: [
            for (final d in byFamily.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(d),
                child: Text(_candidateLabel(
                        r.candidates.where((c) => c.family == d.family).toList(),
                        r.name)
                    .title),
              ),
          ],
        ),
      );
      if (pick == null) return;
      chosen = pick;
    }
    await n.selectLibdcDevice(r, chosen);
  }

  Future<void> _pickModel(ImportNotifier n) async {
    final pick = await showDialog<LibdcPick>(
      context: context,
      builder: (_) => LibdcModelPicker(devices: n.discoveredDevices, notifier: n),
    );
    if (pick == null) return;
    await n.selectLibdcDevice(pick.device, pick.descriptor);
  }

  Widget _buildConnecting(ImportNotifier n, ThemeData theme) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Connecting to ${n.identity?.modelLabel ?? 'dive computer'}...',
            style: const TextStyle(fontSize: 16)),
      ],
    ));
  }

  Widget _buildManifest(ImportNotifier n, ThemeData theme) {
    if (n.newDives.isEmpty && n.identity != null) {
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
        if (n.identity != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.bluetooth_connected, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.identity!.modelLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('S/N ${n.identity!.serialLabel} · ${n.identity!.firmwareLabel}',
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

  String _formatManifestSubtitle(DiveListing entry) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
            entry.startTimestamp * 1000,
            isUtc: true)
        .toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  /// "Share this download": hands the recording to the share sheet,
  /// anchored at the button (iPad and iOS need it).
  Widget _buildShareButton(ImportNotifier n) {
    final text = n.lastRecordingText;
    if (!n.isLibdcDownload || text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Builder(
        builder: (ctx) => OutlinedButton.icon(
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(ctx);
            final box = ctx.findRenderObject() as RenderBox?;
            final origin =
                box != null ? box.localToGlobal(Offset.zero) & box.size : null;
            try {
              final savedTo = await widget.shareDownloadFn(
                recordingText: text,
                extraHeader: [
                  'app: ${BuildInfo.version.isEmpty ? 'dev' : BuildInfo.version}'
                      '+${BuildInfo.build}',
                  'platform: ${Platform.operatingSystem} '
                      '${Platform.operatingSystemVersion}',
                  'gatt:',
                  ...n.lastGattSummary.map((l) => '  $l'),
                ],
                origin: origin,
              );
              if (savedTo != null) {
                // No share sheet here (Linux): the file was saved instead.
                messenger?.showSnackBar(SnackBar(
                  duration: const Duration(seconds: 20),
                  content: Text('Saved the download to $savedTo'),
                  action: SnackBarAction(
                    label: 'Open folder',
                    onPressed: () => _openFolder(savedTo),
                  ),
                ));
              }
            } catch (e) {
              // Only the error's type: a message could carry a path or text
              // from the file.
              messenger?.showSnackBar(SnackBar(
                  content: Text(
                      "Couldn't share the download: ${e.runtimeType}")));
            }
          },
          icon: const Icon(Icons.ios_share),
          label: const Text('Share this download'),
        ),
      ),
    );
  }

  Future<void> _openFolder(String file) async {
    try {
      await launchUrl(Uri.directory(p.dirname(file)));
    } catch (e) {
      debugPrint('Could not open the folder: $e');
    }
  }

  Widget _buildLibdcDownloading(ImportNotifier n, ThemeData theme) {
    final fade = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Downloading from ${n.identity?.modelLabel ?? 'your dive computer'}...',
            style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: LinearProgressIndicator(value: n.currentDiveProgress),
        ),
        const SizedBox(height: 8),
        Text('${diveCountLabel(n.downloadedCount)} saved',
            style: TextStyle(color: fade)),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: n.cancelDownload,
          child: const Text('Cancel'),
        ),
      ],
    ));
  }

  Widget _buildDownloading(ImportNotifier n, ThemeData theme) {
    if (n.isLibdcDownload) return _buildLibdcDownloading(n, theme);
    // Two progress signals: overall (dives saved / total — drives the
    // big circular ring) and per-dive (compressed bytes received for
    // the dive currently streaming — drives the linear bar). Per-dive
    // is the one that moves during the long BLE transfer; overall
    // only ticks at the end of each demuxed dive.
    final overall = n.totalToDownload > 0
        ? n.downloadedCount / n.totalToDownload
        : 0.0;
    final diveProgress = n.currentDiveProgress;
    final total = n.totalDives ?? n.totalToDownload;
    final index = n.currentDiveIndex;
    final fade = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    String? header;
    if (index != null && total > 0) {
      header = 'Downloading dive ${index + 1} of $total';
    } else if (n.currentDiveNumber != null) {
      header = 'Downloading dive #${n.currentDiveNumber}...';
    }

    String? subtitle;
    final entry = n.currentEntry;
    if (entry != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
              entry.startTimestamp * 1000,
              isUtc: true)
          .toLocal();
      subtitle = '#${entry.diveNumber}  ·  '
          '${DateFormat('yyyy-MM-dd HH:mm').format(dt)}';
    }

    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 80, height: 80, child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(value: overall, strokeWidth: 6),
            Text('${n.downloadedCount}/${n.totalToDownload}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        )),
        const SizedBox(height: 24),
        if (header != null)
          Text(header, style: const TextStyle(fontSize: 16)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: fade)),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          // Per-dive bar; falls back to indeterminate before the first
          // progress event lands (manifest reads, demux phase, etc.).
          child: LinearProgressIndicator(value: diveProgress),
        ),
        const SizedBox(height: 8),
        Text('${n.downloadedCount} of ${n.totalToDownload} dives saved',
            style: TextStyle(color: fade)),
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
        _buildShareButton(n),
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
        // The libdivecomputer message already says how many dives were saved.
        if (n.downloadedCount > 0 && !n.isLibdcDownload) ...[
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
        _buildShareButton(n),
      ],
    ));
  }
}
