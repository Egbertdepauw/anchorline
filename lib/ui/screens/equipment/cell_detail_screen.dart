import 'package:flutter/material.dart';

import '../../../data/db/equipment_dao.dart';

/// Placeholder — real implementation lands in Task 12 (with the surface-mV
/// chart). Existing for now so Task 11's list screen has a navigation target.
class CellDetailScreen extends StatelessWidget {
  final EquipmentDao dao;
  final String id;

  const CellDetailScreen({super.key, required this.dao, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cell')),
      body: Center(child: Text('Cell $id (placeholder)')),
    );
  }
}
