/// The pieces shared by every place that prints a cylinder label (issue
/// #114): the copies stepper, the copies prompt, and [printWithFeedback],
/// which prints and tells the user how it went.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/gas_analysis.dart';
import '../../label_printer/label_printer.dart';
import '../../labels/label_print_service.dart';
import '../theme/tokens.dart';

const int _kMinCopies = 1;
const String _kPrintFailed = 'Printing failed';

/// "Label printed." or "Printed 2 labels.", followed by each of the
/// printer's [warnings] as a sentence ("Printer battery is low.").
String labelPrintedMessage(int copies, List<PrinterFault> warnings) {
  final parts = [copies == 1 ? 'Label printed.' : 'Printed $copies labels.'];
  for (final w in warnings) {
    final text = printerFaultMessage(w);
    parts.add(text.endsWith('.') ? text : '$text.');
  }
  return parts.join(' ');
}

/// − and + buttons around the number of copies, kept between 1 and
/// [kMaxLabelCopies] (9); a button that would pass a limit is disabled.
class CopiesStepper extends StatelessWidget {
  const CopiesStepper({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('copies-dec'),
          tooltip: 'Fewer copies',
          icon: const Icon(Icons.remove),
          onPressed: value > _kMinCopies ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: Spacing.xl,
          child: Text(
            '$value',
            key: const ValueKey('copies-value'),
            textAlign: TextAlign.center,
            style: AppTypography.readoutMd,
          ),
        ),
        IconButton(
          key: const ValueKey('copies-inc'),
          tooltip: 'More copies',
          icon: const Icon(Icons.add),
          onPressed:
              value < kMaxLabelCopies ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// Asks how many copies to print, starting at 1. Returns null when the
/// dialog is cancelled or dismissed.
Future<int?> showCopiesDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _CopiesDialog(),
  );
}

class _CopiesDialog extends StatefulWidget {
  const _CopiesDialog();

  @override
  State<_CopiesDialog> createState() => _CopiesDialogState();
}

class _CopiesDialogState extends State<_CopiesDialog> {
  int _copies = _kMinCopies;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copies'),
      content: Center(
        heightFactor: 1,
        child: CopiesStepper(
          value: _copies,
          onChanged: (v) => setState(() => _copies = v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('copies-dialog-print'),
          onPressed: () => Navigator.of(context).pop(_copies),
          child: const Text('Print'),
        ),
      ],
    );
  }
}

/// Prints [copies] of the label for [analysis] and shows how it went in a
/// SnackBar: "Label printed." / "Printed 2 labels." plus the printer's
/// warnings, or the reason it failed with a "Retry" action. A
/// [LabelPrinterException] gives its own message ("Printer not found",
/// "Printer cover is open"); any other error is logged and shown as
/// "Printing failed". A failed print is reported, never thrown.
///
/// Retry prints again with the same arguments and never saves anything: a
/// failed print leaves the saved analysis as it is. It doesn't need
/// [context] any more, only the messenger found here, so it still works
/// after the screen that printed is gone.
Future<void> printWithFeedback(
  BuildContext context, {
  required LabelPrintService service,
  required GasAnalysis analysis,
  required int copies,
}) {
  return _printAndReport(
    ScaffoldMessenger.of(context),
    service,
    analysis,
    copies,
  );
}

Future<void> _printAndReport(
  ScaffoldMessengerState messenger,
  LabelPrintService service,
  GasAnalysis analysis,
  int copies,
) async {
  String message;
  var failed = false;
  try {
    final warnings = await service.printAnalysis(analysis, copies: copies);
    message = labelPrintedMessage(copies, warnings);
  } on LabelPrinterException catch (e) {
    message = e.message;
    failed = true;
  } catch (e) {
    debugPrint('Label printer: print failed: $e');
    message = _kPrintFailed;
    failed = true;
  }
  // The messenger lives above the screens, so it normally outlives the one
  // that printed. Only an app that was torn down mid-print has none left.
  if (!messenger.mounted) return;
  // A failure bar has an action, so it stays until dismissed, and a new bar
  // would queue behind it: the new result would never show, and the old
  // Retry would still be offered. The newest result replaces what is up.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      // A SnackBar with an action stays until dismissed, so it needs a way
      // to be (there is no swipe on desktop).
      showCloseIcon: failed,
      action: failed
          ? SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(
                _printAndReport(messenger, service, analysis, copies),
              ),
            )
          : null,
    ),
  );
}
