import 'package:flutter/material.dart';
import 'package:libdivecomputer/libdivecomputer.dart';

import '../notifiers/import_notifier.dart';

bool _descriptorFailureLogged = false;

/// Every model libdivecomputer knows; an empty list when the native library
/// can't be used (logged once), so the picker still opens.
List<LibdcDescriptor> _allDescriptors() {
  try {
    return Libdc.descriptors();
  } catch (e) {
    if (!_descriptorFailureLogged) {
      _descriptorFailureLogged = true;
      debugPrint('libdivecomputer descriptors unavailable: $e');
    }
    return const [];
  }
}

/// What the user picked in [LibdcModelPicker].
typedef LibdcPick = ({LibdcDescriptor descriptor, ImportScanResult device});

/// "My computer isn't listed": pick the brand, then the model, then which of
/// the named devices seen in the scan is the computer.
///
/// Lists every Bluetooth model libdivecomputer knows except Shearwater, which
/// has its own reader. Pops a [LibdcPick] (or null when dismissed).
class LibdcModelPicker extends StatefulWidget {
  const LibdcModelPicker({
    super.key,
    required this.devices,
    this.notifier,
    List<LibdcDescriptor>? descriptors,
  }) : _descriptors = descriptors;

  /// The named devices seen in the scan when the picker opened.
  final List<ImportScanResult> devices;

  /// When given, the device list follows its scan: a computer that starts
  /// advertising after the picker opened still appears.
  final ImportNotifier? notifier;

  final List<LibdcDescriptor>? _descriptors;

  @override
  State<LibdcModelPicker> createState() => _LibdcModelPickerState();
}

class _LibdcModelPickerState extends State<LibdcModelPicker> {
  late final List<LibdcDescriptor> _all = [
    for (final d in widget._descriptors ?? _allDescriptors())
      if (d.supportsBle && !d.isShearwater) d,
  ];
  String? _vendor;
  LibdcDescriptor? _model;

  List<String> get _vendors =>
      ({for (final d in _all) d.vendor}.toList()..sort());

  List<ImportScanResult> get _named => [
        for (final d in widget.notifier?.discoveredDevices ?? widget.devices)
          if (d.name.isNotEmpty && d.kind != ImportDeviceKind.shearwater) d,
      ];

  void _back() => setState(() {
        if (_model != null) {
          _model = null;
        } else {
          _vendor = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    if (notifier == null) return _buildDialog(context);
    return ListenableBuilder(
        listenable: notifier, builder: (ctx, _) => _buildDialog(ctx));
  }

  Widget _buildDialog(BuildContext context) {
    final String title;
    final List<Widget> rows;
    if (_vendor == null) {
      title = 'Which brand?';
      rows = [
        for (final v in _vendors)
          ListTile(
            title: Text(v),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _vendor = v),
          ),
      ];
    } else if (_model == null) {
      title = _vendor!;
      rows = [
        for (final d in _all.where((d) => d.vendor == _vendor))
          ListTile(
            title: Text(d.product),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _model = d),
          ),
      ];
    } else {
      title = 'Which device is your ${_model!.product}?';
      final named = _named;
      rows = [
        if (named.isEmpty)
          const ListTile(
            title: Text('No named Bluetooth devices seen yet'),
            subtitle: Text(
                'Put the computer in Bluetooth upload mode and scan again.'),
          ),
        for (final r in named)
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(r.name),
            subtitle: Text(r.id),
            onTap: () => Navigator.of(context)
                .pop<LibdcPick>((descriptor: _model!, device: r)),
          ),
      ];
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _vendor == null
                  ? null
                  : IconButton(
                      key: const ValueKey('libdc-picker-back'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _back,
                    ),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Divider(height: 1),
            Flexible(child: ListView(shrinkWrap: true, children: rows)),
          ],
        ),
      ),
    );
  }
}
