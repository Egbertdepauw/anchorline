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
    if (widget.gasMixes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }
}
