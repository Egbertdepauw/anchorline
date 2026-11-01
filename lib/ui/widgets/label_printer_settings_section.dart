/// Settings for the cylinder label printer (issue #114): find and pair a
/// Bluetooth label printer, print a test label, forget the printer, and the
/// "Use 1.4 for deeper mixes" switch.
///
/// [LabelPrinterSettingsSection] sits in Settings after "Gas analyzer" and is
/// also what [LabelPrinterSettingsScreen] shows on its own, for the "Set up
/// label printer" link on the analyzer screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../label_printer/label_printer.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import 'label_print_controls.dart';

const String _kNoPrinter = 'No printer set up';
const String _kScanFailed = 'Bluetooth scan failed';
const String _kPrintFailed = 'Printing failed';

/// The label printer settings, without a heading: the host provides one
/// (Settings has a "Label printer" heading, the screen has a title).
class LabelPrinterSettingsSection extends StatelessWidget {
  const LabelPrinterSettingsSection({
    super.key,
    required this.settings,
    required this.printing,
  });

  final SettingsNotifier settings;
  final LabelPrintService printing;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final id = settings.labelPrinterId;
        final configured = id != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(
                configured ? (settings.labelPrinterName ?? id) : _kNoPrinter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    key: const ValueKey('label-printer-find'),
                    onPressed: () => _findPrinter(context),
                    child: const Text('Find printer'),
                  ),
                  _PrintTestLabelButton(
                    printing: printing,
                    enabled: configured,
                  ),
                  if (configured)
                    TextButton(
                      key: const ValueKey('label-printer-forget'),
                      onPressed: settings.forgetLabelPrinter,
                      child: const Text('Forget printer'),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              key: const ValueKey('label-printer-use14'),
              title: const Text('Use 1.4 for deeper mixes'),
              subtitle: const Text(
                'MOD at ppO₂ 1.4 for mixes below 50 % O₂. '
                'Off: 1.6 for all mixes.',
              ),
              value: settings.labelUse14ForDeeperMixes,
              onChanged: settings.setLabelUse14ForDeeperMixes,
            ),
          ],
        );
      },
    );
  }

  Future<void> _findPrinter(BuildContext context) async {
    final picked = await showDialog<FoundLabelPrinter>(
      context: context,
      builder: (_) => _FindPrinterDialog(scanner: printing.scanner),
    );
    if (picked != null) {
      await settings.setLabelPrinter(id: picked.id, name: picked.name);
    }
  }
}

/// A screen holding only the label printer settings, titled "Label printer".
class LabelPrinterSettingsScreen extends StatelessWidget {
  const LabelPrinterSettingsScreen({
    super.key,
    required this.settings,
    required this.printing,
  });

  final SettingsNotifier settings;
  final LabelPrintService printing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label printer')),
      body: ListView(
        children: [
          LabelPrinterSettingsSection(settings: settings, printing: printing),
        ],
      ),
    );
  }
}

/// "Print test label". Disables itself while a print is in flight, so a
/// second tap doesn't start a second job on a printer that may take up to
/// the connect timeout to answer.
class _PrintTestLabelButton extends StatefulWidget {
  const _PrintTestLabelButton({required this.printing, required this.enabled});

  final LabelPrintService printing;
  final bool enabled;

  @override
  State<_PrintTestLabelButton> createState() => _PrintTestLabelButtonState();
}

class _PrintTestLabelButtonState extends State<_PrintTestLabelButton> {
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const ValueKey('label-printer-test'),
      onPressed: widget.enabled && !_printing ? _print : null,
      child: const Text('Print test label'),
    );
  }

  Future<void> _print() async {
    // The messenger outlives this button, so the result still shows if the
    // user leaves the screen while the printer works.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _printing = true);
    String message;
    try {
      message = labelPrintedMessage(1, await widget.printing.printTestLabel());
    } on LabelPrinterException catch (e) {
      message = e.message;
    } catch (e, st) {
      reportLabelPrintError('test print', e, st);
      message = _kPrintFailed;
    }
    if (mounted) setState(() => _printing = false);
    if (!messenger.mounted) return;
    // A label print's failure bar has a Retry, so it stays until dismissed,
    // and this result would queue behind it unseen.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Scans for printers and pops the one the user taps.
///
/// The scan stays open while it runs and emits the printers found so far
/// each time the list changes. A scan that finds nothing emits nothing and
/// just closes, and one that can't run (Bluetooth off) ends with an error
/// event, so the dialog tracks "searching" and "failed" itself.
class _FindPrinterDialog extends StatefulWidget {
  const _FindPrinterDialog({required this.scanner});

  final LabelPrinterScanner scanner;

  @override
  State<_FindPrinterDialog> createState() => _FindPrinterDialogState();
}

class _FindPrinterDialogState extends State<_FindPrinterDialog> {
  StreamSubscription<List<FoundLabelPrinter>>? _scan;
  List<FoundLabelPrinter> _found = const [];
  bool _searching = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan = widget.scanner.scan().listen(
      (found) => setState(() => _found = found),
      onError: (Object e) => setState(() {
        _searching = false;
        _error = e is LabelPrinterException ? e.message : _kScanFailed;
      }),
      onDone: () => setState(() => _searching = false),
    );
  }

  @override
  void dispose() {
    // Closing the dialog, by any route, ends the scan and the radio's.
    unawaited(_scan?.cancel());
    unawaited(widget.scanner.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Find printer'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (error != null)
              Text(error, key: const ValueKey('label-printer-scan-error'))
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
                    Text('Searching for printers…'),
                  ],
                ),
              )
            else if (_found.isEmpty)
              const Text(
                'No printers found. Turn the printer on, keep it close, '
                'and try again.',
              ),
            for (final p in _found)
              ListTile(
                key: ValueKey('label-printer-result-${p.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                onTap: () => Navigator.of(context).pop(p),
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
