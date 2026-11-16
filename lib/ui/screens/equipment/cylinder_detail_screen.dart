import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/db/gas_analyses_dao.dart';
import '../../../data/db/open_blends_dao.dart';
import '../../../data/models/equipment.dart';
import '../../../labels/label_print_service.dart';
import '../gas_analysis_log_screen.dart';

class CylinderDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String? id; // null = create-new draft

  /// Cylinder analysis log (#111); null hides the "Gas analyses" entry.
  final GasAnalysesDaoLike? analysesDao;

  /// Cylinder label printing (#114), for reprints from the log.
  final LabelPrintService? labelPrinting;

  /// The open blends a sign-off in the cylinder's log can close (#112).
  final OpenBlendsDaoLike? openBlends;

  const CylinderDetailScreen(
      {super.key,
      required this.dao,
      this.id,
      this.analysesDao,
      this.labelPrinting,
      this.openBlends});

  @override
  State<CylinderDetailScreen> createState() => _CylinderDetailScreenState();
}

class _CylinderDetailScreenState extends State<CylinderDetailScreen> {
  Cylinder? _c;
  final _label = TextEditingController();
  final _vol = TextEditingController();
  final _press = TextEditingController();
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
        volumeLiters: _parseDecimal(_vol.text) ?? 5,
        workingPressureBar: int.tryParse(_press.text.trim()) ?? 200,
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
        volumeLiters: _parseDecimal(_vol.text),
        workingPressureBar: int.tryParse(_press.text.trim()),
        notes: _notes.text.trim(),
      );
      await _load();
    }
  }

  /// Parses a user-typed decimal, accepting `,` as the decimal separator
  /// (Dutch / German / French locales) in addition to `.`. Empty input
  /// returns null. `double.tryParse` only accepts `.`, which silently
  /// drops decimals on iPhone keypads in comma-locale regions.
  double? _parseDecimal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
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
    _notes.dispose();
    _bailoutOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cylinder'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
          if (!_isDraft)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
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
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                if (!_isDraft && widget.analysesDao != null) ...[
                  const SizedBox(height: 16),
                  ListTile(
                    key: const ValueKey('cylinder-analyses'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.science_outlined),
                    title: const Text('Gas analyses'),
                    subtitle:
                        const Text('Analyzer readings saved for this cylinder'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GasAnalysisLogScreen(
                        dao: widget.analysesDao!,
                        cylinderId: widget.id,
                        cylinderLabel: _c?.label,
                        labelPrinting: widget.labelPrinting,
                        openBlends: widget.openBlends,
                      ),
                    )),
                  ),
                ],
              ],
            ),
    );
  }
}
