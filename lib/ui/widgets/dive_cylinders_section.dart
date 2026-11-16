/// Gas-mix → cylinder mapping block, extracted from
/// [DiveAnnotationsSection] for Phase 3's tabbed dive-detail layout.
///
/// Reads/writes through the same [DiveAnnotationsNotifier] that the
/// other tabs use, so the dirty/save state stays unified — saving the
/// annotations from the AppBar action also commits cylinder picks
/// made here. Cylinder picker rows are reused from
/// `dive_annotations_section.dart`.
library;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/equipment_dao.dart';
import 'package:subsurface_core/data/models/dive.dart';
import '../notifiers/dive_annotations_notifier.dart';
import 'dive_annotations_section.dart' show GasMixRow;

class DiveCylindersSection extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final List<DiveGasMix> gasMixes;
  final Map<int, int> activeSecondsByMix;
  final EquipmentDao equipmentDao;

  const DiveCylindersSection({
    super.key,
    required this.notifier,
    required this.gasMixes,
    required this.activeSecondsByMix,
    required this.equipmentDao,
  });

  @override
  State<DiveCylindersSection> createState() => _DiveCylindersSectionState();
}

class _DiveCylindersSectionState extends State<DiveCylindersSection> {
  DiveAnnotationsNotifier get _n => widget.notifier;
  List<Cylinder> _cylinders = const [];

  @override
  void initState() {
    super.initState();
    _n.addListener(_onChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cylinders = await widget.equipmentDao.listCylinders();
    if (!mounted) return;
    setState(() => _cylinders = cylinders);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unassigned = _n.unassignedCylinders;
    if (widget.gasMixes.isEmpty && unassigned.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.gasMixes.isNotEmpty)
            Text('Gas mixes', style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < widget.gasMixes.length; i++)
            GasMixRow(
              index: i,
              mix: widget.gasMixes[i],
              activeSeconds: widget.activeSecondsByMix[i] ?? 0,
              cylinders: _cylinders,
              selectedCylinderId: _n.cylinderByMix[i],
              onChanged: (cylinderId) => _n.setCylinderForMix(i, cylinderId),
            ),
          for (final e in unassigned.entries)
            _UnassignedCylinderRow(
              label: _labelFor(e.value),
              onRemove: () => _n.removeUnassignedCylinder(e.key),
            ),
        ],
      ),
    );
  }

  String _labelFor(String? cylinderId) {
    for (final c in _cylinders) {
      if (c.id == cylinderId) return '${c.label} (${c.role})';
    }
    return 'Cylinder';
  }
}

/// A cylinder assigned to a gas mix the dive no longer has.
class _UnassignedCylinderRow extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _UnassignedCylinderRow({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  'No longer matches a gas on this dive',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove cylinder',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
