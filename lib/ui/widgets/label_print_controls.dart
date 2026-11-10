/// The pieces shared by every place that prints a cylinder label (issue
/// #114): the copies stepper, the copies prompt, [printWithFeedback],
/// which prints and tells the user how it went, and
/// [reportLabelPrintError] for errors that aren't the printer's.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;

import '../../data/models/gas_analysis.dart';
import '../../label_printer/label_printer.dart';
import '../../labels/label_print_service.dart';
import '../theme/tokens.dart';

const int _kMinCopies = 1;
const String _kPrintFailed = 'Printing failed';
const String _kDeleted = 'This analysis was deleted.';
const String _kChanged =
    'This analysis changed. Print it again from the log.';

/// Where [reportLabelPrintError] sends an error and its stack trace:
/// Sentry, which `main.dart` only starts in release builds. Elsewhere the
/// capture does nothing. Tests replace it to see what is reported.
@visibleForTesting
Future<void> Function(Object error, StackTrace stack) labelPrintErrorSink =
    (error, stack) => Sentry.captureException(error, stackTrace: stack);

/// Logs and reports a print error that isn't the printer's, such as a
/// render bug or a failed read of the log. The user sees "Printing
/// failed"; this keeps the cause. [what] names the step in the log line.
void reportLabelPrintError(String what, Object error, StackTrace stack) {
  debugPrint('Label printer: $what failed: $error');
  unawaited(labelPrintErrorSink(error, stack));
}

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

  /// 44 pt targets on every platform (the desktop density would shrink
  /// them).
  static const _target = BoxConstraints(minWidth: 44, minHeight: 44);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('copies-dec'),
          tooltip: 'Fewer copies',
          constraints: _target,
          visualDensity: VisualDensity.standard,
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
          constraints: _target,
          visualDensity: VisualDensity.standard,
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
/// "Printer cover is open"); any other error goes to
/// [reportLabelPrintError] and is shown as "Printing failed". A failed
/// print is reported, never thrown.
///
/// Retry prints again with the same copies and never saves anything: a
/// failed print leaves the saved analysis as it is. It doesn't need
/// [context] any more, only the messenger found here, so it still works
/// after the screen that printed is gone.
///
/// The failure bar outlives the screen, so the analysis can be edited or
/// deleted before its Retry is tapped. [reload] reads the analysis as it is
/// stored now, or null when it is gone. With it, Retry reads first and
/// prints nothing for an analysis that was deleted ("This analysis was
/// deleted.") or whose desired mix or gas role changed since the print
/// that failed ("This analysis changed. Print it again from the log.").
/// Otherwise it prints the analysis as read, so a "Print as …" the diver
/// already confirmed still prints without asking again. Without [reload],
/// Retry prints [analysis] as given.
///
/// [snackBarMargin], when given, places the result's floating SnackBars
/// (and those of its Retries), e.g. clear of a pinned action bar.
Future<void> printWithFeedback(
  BuildContext context, {
  required LabelPrintService service,
  required GasAnalysis analysis,
  required int copies,
  Future<GasAnalysis?> Function()? reload,
  EdgeInsetsGeometry? snackBarMargin,
}) {
  return _printAndReport(
    ScaffoldMessenger.of(context),
    _PrintRequest(service, copies, reload, snackBarMargin),
    analysis,
  );
}

/// What a print, and each of its Retries, prints with.
class _PrintRequest {
  const _PrintRequest(this.service, this.copies, this.reload, this.margin);

  final LabelPrintService service;
  final int copies;
  final Future<GasAnalysis?> Function()? reload;

  /// The margin of the floating SnackBars that report it, or null for the
  /// theme's.
  final EdgeInsetsGeometry? margin;
}

Future<void> _printAndReport(
  ScaffoldMessengerState messenger,
  _PrintRequest request,
  GasAnalysis analysis,
) async {
  final copies = request.copies;
  String message;
  var failed = false;
  try {
    final warnings =
        await request.service.printAnalysis(analysis, copies: copies);
    message = labelPrintedMessage(copies, warnings);
  } on LabelPrinterException catch (e) {
    message = e.message;
    failed = true;
  } catch (e, st) {
    reportLabelPrintError('print', e, st);
    message = _kPrintFailed;
    failed = true;
  }
  _report(
    messenger,
    message,
    margin: request.margin,
    retry: failed ? () => _retry(messenger, request, analysis) : null,
  );
}

/// Retry of a print of [failed]: see [printWithFeedback].
Future<void> _retry(
  ScaffoldMessengerState messenger,
  _PrintRequest request,
  GasAnalysis failed,
) async {
  final reload = request.reload;
  if (reload == null) return _printAndReport(messenger, request, failed);
  final GasAnalysis? current;
  try {
    current = await reload();
  } catch (e, st) {
    // Printing what was read before could print a stale label.
    reportLabelPrintError('reading the analysis for Retry', e, st);
    _report(
      messenger,
      _kPrintFailed,
      margin: request.margin,
      retry: () => _retry(messenger, request, failed),
    );
    return;
  }
  if (current == null) {
    _report(messenger, _kDeleted, margin: request.margin);
  } else if (current.desiredMix != failed.desiredMix ||
      current.gasRole != failed.gasRole) {
    // The label's name, depths and kind follow these. The diver decides
    // again, from the log, whether to print the entry as it is now.
    _report(messenger, _kChanged, margin: request.margin);
  } else {
    await _printAndReport(messenger, request, current);
  }
}

/// Shows [message] in place of the SnackBar that is up, with a "Retry"
/// action when [retry] is given. A [margin] floats it there.
void _report(
  ScaffoldMessengerState messenger,
  String message, {
  EdgeInsetsGeometry? margin,
  Future<void> Function()? retry,
}) {
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
      behavior: margin == null ? null : SnackBarBehavior.floating,
      margin: margin,
      // A SnackBar with an action stays until dismissed, so it needs a way
      // to be (there is no swipe on desktop).
      showCloseIcon: retry != null,
      action: retry != null
          ? SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(retry()),
            )
          : null,
    ),
  );
}
