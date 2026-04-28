import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/models/equipment.dart';

class CylinderDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String? id; // null = create-new draft

  const CylinderDetailScreen({super.key, required this.dao, this.id});

  @override
  State<CylinderDetailScreen> createState() => _CylinderDetailScreenState();
}

class _CylinderDetailScreenState extends State<CylinderDetailScreen> {
  Cylinder? _c;
  final _label = TextEditingController();
  final _vol = TextEditingController();
  final _press = TextEditingController();
  final _gas = TextEditingController();
  final _notes = TextEditingController();
  final _bailoutOrder = TextEditingController();
  String _role = CylinderRole.bailout;

  bool get _isDraft => widget.id == null;

  @override
  void initState() {
    super.initState();
    if (!_isDraft) _load();
  }

  Future<int> _nextBailoutOrder() async {
    final cylinders = await widget.dao.listCylinders();
    final maxOrder = cylinders
        .where((c) => c.role == CylinderRole.bailout)
        .map((c) => c.bailoutOrder ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return maxOrder + 1;
  }

  Future<void> _load() async {
    final c = await widget.dao.getCylinder(widget.id!);
    if (c == null) return;
    if (!mounted) return;
    setState(() {
      _c = c;
      _label.text = c.label;
      _vol.text = c.volumeLiters.toString();
      _press.text = c.workingPressureBar.toString();
      _gas.text = c.gasMix ?? '';
      _notes.text = c.notes ?? '';
      _bailoutOrder.text = (c.bailoutOrder ?? '').toString();
      _role = c.role;
    });
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (_isDraft) {
      final newId = await widget.dao.addCylinder(
        label: label.isEmpty ? 'New cylinder' : label,
        role: _role,
        bailoutOrder: _role == CylinderRole.bailout
            ? int.tryParse(_bailoutOrder.text.trim()) ?? 1
            : null,
        volumeLiters: double.tryParse(_vol.text.trim()) ?? 5,
        workingPressureBar: int.tryParse(_press.text.trim()) ?? 200,
        gasMix: _gas.text.trim(),
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(newId);
    } else {
      await widget.dao.updateCylinder(
        _c!.id,
        label: label,
        role: _role,
        bailoutOrder: _role == CylinderRole.bailout
            ? int.tryParse(_bailoutOrder.text.trim())
            : null,
        volumeLiters: double.tryParse(_vol.text.trim()),
        workingPressureBar: int.tryParse(_press.text.trim()),
        gasMix: _gas.text.trim(),
        notes: _notes.text.trim(),
      );
      await _load();
    }
  }

  Future<void> _delete() async {
    if (_c == null) return;
    await widget.dao.softDeleteCylinder(_c!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _label.dispose();
    _vol.dispose();
    _press.dispose();
    _gas.dispose();
    _notes.dispose();
    _bailoutOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cylinder')),
      body: (!_isDraft && _c == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final r in CylinderRole.all)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) async {
                    final newRole = v ?? _role;
                    if (newRole == CylinderRole.bailout &&
                        _bailoutOrder.text.trim().isEmpty &&
                        _role != CylinderRole.bailout) {
                      final next = await _nextBailoutOrder();
                      if (!mounted) return;
                      setState(() {
                        _role = newRole;
                        _bailoutOrder.text = next.toString();
                      });
                    } else {
                      setState(() => _role = newRole);
                    }
                  },
                ),
                if (_role == CylinderRole.bailout)
                  TextField(
                    controller: _bailoutOrder,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Bailout order (#)'),
                  ),
                TextField(
                  controller: _vol,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Volume (L)'),
                ),
                TextField(
                  controller: _press,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Working pressure (bar)'),
                ),
                TextField(
                  controller: _gas,
                  decoration: const InputDecoration(
                      labelText: 'Gas mix (e.g. 21/35)'),
                ),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(onPressed: _save, child: const Text('Save')),
                    if (!_isDraft)
                      TextButton(
                          onPressed: _delete, child: const Text('Delete')),
                  ],
                ),
              ],
            ),
    );
  }
}
