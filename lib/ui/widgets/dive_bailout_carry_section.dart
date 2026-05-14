/// Per-dive bailout-carry editor. Listed on Dive Detail → Equipment tab
/// next to the gas-mix-to-cylinder mapping table. Reads dive_bailout_carry
/// rows for the dive, joined to physical Cylinder rows from Equipment.
///
/// Add → pick a Cylinder via a modal bottom sheet → defaults gas to "21"
/// and fill pressure to the cylinder's working pressure. Each row inline-
/// edits gas mix + fill pressure (taps to open a small dialog) and has a
/// delete button. The list is sorted by bailoutOrder ascending.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/equipment_dao.dart';

class DiveBailoutCarrySection extends StatefulWidget {
  final String diveId;
  final EquipmentDao dao;

  const DiveBailoutCarrySection({
    super.key,
    required this.diveId,
    required this.dao,
  });

  @override
  State<DiveBailoutCarrySection> createState() =>
      _DiveBailoutCarrySectionState();
}

class _DiveBailoutCarrySectionState extends State<DiveBailoutCarrySection> {
  List<({DiveBailoutCarryData carry, Cylinder cylinder})> _rows = const [];
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = widget.dao.watchDiveBailoutCarry().listen((_) => _reload());
  }

  Future<void> _reload() async {
    final rows =
        await widget.dao.listBailoutCarryWithCylinders(widget.diveId);
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bailout carry',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No bailout cylinders configured'),
            )
          else
            for (final r in _rows)
              _CarryRow(
                carry: r.carry,
                cylinder: r.cylinder,
                onEditGas: (newGas) async {
                  await widget.dao
                      .updateBailoutCarry(r.carry.id, gasMix: newGas);
                  await _reload();
                },
                onEditFill: (newFill) async {
                  await widget.dao
                      .updateBailoutCarry(r.carry.id, fillPressureBar: newFill);
                  await _reload();
                },
                onDelete: () async {
                  await widget.dao.deleteBailoutCarry(r.carry.id);
                  await _reload();
                },
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add cylinder'),
              onPressed: () => _addCylinder(context, _rows.length),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCylinder(BuildContext context, int currentRowCount) async {
    final cylinders = await widget.dao.listCylinders();
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<Cylinder>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in cylinders)
              ListTile(
                title: Text(c.label),
                subtitle: Text(
                  '${c.volumeLiters}L @ ${c.workingPressureBar} bar',
                ),
                onTap: () => Navigator.of(ctx).pop(c),
              ),
            if (cylinders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No cylinders defined. Add one in Equipment → Cylinders first.',
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await widget.dao.addBailoutCarry(
      diveId: widget.diveId,
      cylinderId: picked.id,
      gasMix: '21',
      bailoutOrder: currentRowCount + 1,
    );
    await _reload();
  }
}

class _CarryRow extends StatelessWidget {
  final DiveBailoutCarryData carry;
  final Cylinder cylinder;
  final ValueChanged<String> onEditGas;
  final ValueChanged<int> onEditFill;
  final VoidCallback onDelete;

  const _CarryRow({
    required this.carry,
    required this.cylinder,
    required this.onEditGas,
    required this.onEditFill,
    required this.onDelete,
  });

  Future<void> _editGas(BuildContext context) async {
    final v = await _showStringDialog(
      context,
      title: 'Gas mix',
      initial: carry.gasMix,
      hint: 'e.g. 21/35, 50, 100',
    );
    if (v != null && v.isNotEmpty) onEditGas(v);
  }

  Future<void> _editFill(BuildContext context) async {
    final current = carry.fillPressureBar ?? cylinder.workingPressureBar;
    final v = await _showIntDialog(
      context,
      title: 'Fill pressure (bar)',
      initial: current,
    );
    if (v != null && v > 0) onEditFill(v);
  }

  @override
  Widget build(BuildContext context) {
    final fillBar = carry.fillPressureBar ?? cylinder.workingPressureBar;
    final volumeL = (cylinder.volumeLiters * fillBar).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${carry.bailoutOrder}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(flex: 3, child: Text(cylinder.label)),
          GestureDetector(
            onTap: () => _editGas(context),
            child: SizedBox(
              width: 60,
              child: Text(
                carry.gasMix,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _editFill(context),
            child: SizedBox(
              width: 80,
              child: Text(
                '$fillBar bar',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${volumeL}L',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

Future<String?> _showStringDialog(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
}) async {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<int?> _showIntDialog(
  BuildContext context, {
  required String title,
  required int initial,
}) async {
  final ctl = TextEditingController(text: '$initial');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        keyboardType: TextInputType.number,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctl.text.trim())),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
