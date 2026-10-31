/// Port picker for the desktop USB gas-analyzer transport.
///
/// Lists the candidate serial ports (likely-analyzer `usbmodem` / `ttyACM`
/// ports first), preselects one, and has a refresh button for a SOLO that
/// was plugged in after the dialog opened. Returns the chosen port, or
/// null when cancelled.
library;

import 'package:flutter/material.dart';

import '../../analyzer/transport/serial_port_selection.dart';
import '../theme/tokens.dart';

/// Shows the picker. [listPorts] returns ranked candidate ports (injected
/// so tests need no hardware). [previous] is preselected when present.
Future<String?> showSerialPortPicker(
  BuildContext context, {
  required List<String> Function() listPorts,
  String? previous,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        SerialPortPickerDialog(listPorts: listPorts, previous: previous),
  );
}

class SerialPortPickerDialog extends StatefulWidget {
  const SerialPortPickerDialog({
    super.key,
    required this.listPorts,
    this.previous,
  });

  final List<String> Function() listPorts;
  final String? previous;

  @override
  State<SerialPortPickerDialog> createState() => _SerialPortPickerDialogState();
}

class _SerialPortPickerDialogState extends State<SerialPortPickerDialog> {
  List<String> _ports = const [];
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      _ports = widget.listPorts();
    } catch (_) {
      _ports = const [];
    }
    _selected =
        preselectSerialPort(_ports, previous: _selected ?? widget.previous);
  }

  void _refresh() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Analyzer port'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ports.isEmpty
                    ? const Text(
                        'No serial ports found. Plug in the analyzer with a '
                        'USB data cable, then refresh.',
                        key: ValueKey('serial-port-none'),
                      )
                    : DropdownButton<String>(
                        key: const ValueKey('serial-port-dropdown'),
                        isExpanded: true,
                        value: _selected,
                        hint: const Text('Choose a port'),
                        items: [
                          for (final p in _ports)
                            DropdownMenuItem(
                              value: p,
                              child: Text(p, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (p) => setState(() => _selected = p),
                      ),
              ),
              const SizedBox(width: Spacing.sm),
              IconButton(
                key: const ValueKey('serial-port-refresh'),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('serial-port-connect'),
          onPressed:
              _selected == null ? null : () => Navigator.of(context).pop(_selected),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
