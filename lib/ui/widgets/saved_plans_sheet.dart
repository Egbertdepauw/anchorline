library;

import 'package:flutter/material.dart';

import '../theme/safety_colors.dart';

import '../../data/db/dive_plans_dao.dart' show SavedDivePlan;

class SavedPlansSheet extends StatelessWidget {
  const SavedPlansSheet({
    super.key,
    required this.plans,
    required this.onLoad,
    required this.onDelete,
  });

  final List<SavedDivePlan> plans;
  final ValueChanged<String> onLoad;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('No saved plans yet.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: plans.length,
      itemBuilder: (_, i) {
        final p = plans[i];
        return Dismissible(
          key: ValueKey(p.id),
          background: Container(color: SafetyColors.danger),
          onDismissed: (_) => onDelete(p.id),
          child: ListTile(
            title: Text(p.name),
            subtitle: Text(
                '${p.updatedAt.day}/${p.updatedAt.month}/${p.updatedAt.year} '
                '${p.updatedAt.hour}:${p.updatedAt.minute.toString().padLeft(2, '0')}'),
            onTap: () => onLoad(p.id),
          ),
        );
      },
    );
  }
}
