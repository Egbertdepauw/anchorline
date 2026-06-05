import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Result of the renumber dialog.
sealed class RenumberResult {}

class RenumberApply extends RenumberResult {
  final int start;
  RenumberApply(this.start);
}

class RenumberReset extends RenumberResult {}

/// Dialog to renumber [count] dives. Returns a [RenumberApply] (with the start
/// number), a [RenumberReset], or null if cancelled.
Future<RenumberResult?> showRenumberDialog(BuildContext context, int count) {
  return showDialog<RenumberResult>(
    context: context,
    builder: (_) => _RenumberDialog(count: count),
  );
}

class _RenumberDialog extends StatefulWidget {
  final int count;
  const _RenumberDialog({required this.count});
  @override
  State<_RenumberDialog> createState() => _RenumberDialogState();
}

class _RenumberDialogState extends State<_RenumberDialog> {
  final _ctrl = TextEditingController(text: '1');

  int get _start => int.tryParse(_ctrl.text.trim()) ?? 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final end = start + widget.count - 1;
    return AlertDialog(
      title: Text('Renumber ${widget.count} '
          '${widget.count == 1 ? 'dive' : 'dives'}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Start number'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('#$start → #$end · by date (oldest first)',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(RenumberReset()),
          child: const Text('Reset to automatic'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(RenumberApply(start)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
