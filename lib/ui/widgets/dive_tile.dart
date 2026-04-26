import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import 'sparkline.dart';

class DiveTile extends StatelessWidget {
  final Dive dive;
  final Float32List? sparklineData;
  final VoidCallback onTap;

  const DiveTile({super.key, required this.dive, required this.sparklineData, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final modeColor = diveModeColor(dive.diveMode);
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: modeColor, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 56, height: 36,
              child: sparklineData != null && sparklineData!.isNotEmpty
                  ? DepthSparkline(depths: sparklineData!, color: modeColor)
                  : Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(diveModeLabel(dive.diveMode),
                        style: TextStyle(color: modeColor, fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text('#${dive.dcDiveNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const Spacer(),
                      Text(formatDateShort(dive.startTime),
                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_buildStatsLine(),
                    style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatsLine() {
    final parts = <String>[
      formatDepth(dive.maxDepthMm),
      formatDuration(dive.durationSeconds),
    ];
    final gf = formatGf(dive.gfLow, dive.gfHigh);
    if (gf.isNotEmpty) parts.add(gf);
    return parts.join(' · ');
  }
}
