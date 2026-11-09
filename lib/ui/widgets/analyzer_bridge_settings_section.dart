/// Settings for the SOLO bridge: find and pair the bridge, forget it, and
/// the switch that has the bridge power the analyzer.
///
/// [AnalyzerBridgeSettingsSection] sits on the Gas tab under "Label
/// printer". [showFindBridgeDialog] is also what the Bridge source's picker
/// opens when no bridge is set up yet.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../analyzer/bridge/bridge_link.dart' show BridgeLinkException;
import '../../analyzer/bridge/bridge_link_ble.dart';
import '../components/setting_row.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';

const String _kNoBridge = 'No bridge set up';
const String _kScanFailed = 'Bluetooth scan failed';

/// The bridge settings, without a heading: the Gas tab provides one.
class AnalyzerBridgeSettingsSection extends StatelessWidget {
  const AnalyzerBridgeSettingsSection({
    super.key,
    required this.settings,
    this.findBridge,
  });

  final SettingsNotifier settings;

  /// Replaces the find dialog, for tests.
  final Future<FoundBridge?> Function(BuildContext context)? findBridge;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final id = settings.analyzerBridgeId;
        final configured = id != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingRow(
              title: configured
                  ? (settings.analyzerBridgeName ?? id)
                  : _kNoBridge,
              helper: configured ? 'Set up on this device' : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    key: const ValueKey('analyzer-bridge-find'),
                    onPressed: () => _find(context),
                    child: const Text('Find bridge'),
                  ),
                  if (configured)
                    TextButton(
                      key: const ValueKey('analyzer-bridge-forget'),
                      onPressed: settings.forgetAnalyzerBridge,
                      child: const Text('Forget bridge'),
                    ),
                ],
              ),
            ),
            Divider(
                height: 1,
                thickness: 1,
                color: context.palette.surfaceRaised),
            SettingRow(
              title: 'Power the analyzer from the bridge',
              helper: 'Off: the SOLO runs on its own battery. On: the bridge '
                  'supplies 5 V, which also charges the SOLO.',
              onTap: () =>
                  settings.setAnalyzerBridgeVbus(!settings.analyzerBridgeVbus),
              control: Switch(
                key: const ValueKey('analyzer-bridge-vbus'),
                value: settings.analyzerBridgeVbus,
                onChanged: settings.setAnalyzerBridgeVbus,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _find(BuildContext context) async {
    final picked = await (findBridge ?? showFindBridgeDialog)(context);
    if (picked != null) {
      await settings.setAnalyzerBridge(id: picked.id, name: picked.name);
    }
  }
}

/// Scans for bridges and returns the one the diver taps, or null.
Future<FoundBridge?> showFindBridgeDialog(BuildContext context) =>
    showDialog<FoundBridge>(
      context: context,
      builder: (_) => const _FindBridgeDialog(),
    );

/// Scans for bridges and pops the one the user taps. Same shape as the
/// label printer's find dialog.
class _FindBridgeDialog extends StatefulWidget {
  const _FindBridgeDialog();

  @override
  State<_FindBridgeDialog> createState() => _FindBridgeDialogState();
}

class _FindBridgeDialogState extends State<_FindBridgeDialog> {
  StreamSubscription<List<FoundBridge>>? _scan;
  List<FoundBridge> _found = const [];
  bool _searching = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan = scanForBridges().listen(
      (found) => setState(() => _found = found),
      onError: (Object e) => setState(() {
        _searching = false;
        _error = e is BridgeLinkException ? e.message : _kScanFailed;
      }),
      onDone: () => setState(() => _searching = false),
    );
  }

  @override
  void dispose() {
    // Closing the dialog, by any route, ends the scan and the radio's.
    unawaited(_scan?.cancel());
    unawaited(stopBridgeScan());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Find bridge'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (error != null)
              Text(error, key: const ValueKey('analyzer-bridge-scan-error'))
            else if (_searching)
              const Padding(
                padding: EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: Spacing.md),
                    Text('Searching for bridges…'),
                  ],
                ),
              )
            else if (_found.isEmpty)
              const Text(
                'No bridge found. Switch it on and keep it close.',
              ),
            for (final b in _found)
              ListTile(
                key: ValueKey('analyzer-bridge-result-${b.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(b.name),
                onTap: () => Navigator.of(context).pop(b),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
