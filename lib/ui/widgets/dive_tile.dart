import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/db/database.dart';
import '../../data/models/annotation.dart' as dom;
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import 'site_mini_map.dart';
import 'sparkline.dart';

class DiveTile extends StatelessWidget {
  final Dive dive;
  final Float32List? sparklineData;
  final dom.DiveAnnotation? annotation;
  final VoidCallback onTap;

  const DiveTile({
    super.key,
    required this.dive,
    required this.sparklineData,
    required this.onTap,
    this.annotation,
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = diveModeColor(dive.diveMode);
    final theme = Theme.of(context);
    final annotationLine = _buildAnnotationLine();

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: modeColor, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (annotation?.siteLatitude != null &&
                annotation?.siteLongitude != null)
              SiteMiniMap(
                lat: annotation!.siteLatitude!,
                lon: annotation!.siteLongitude!,
                size: 56,
              )
            else
              const SizedBox(width: 56),
            const SizedBox(width: 12),
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
                      if (annotation?.siteName != null &&
                          annotation!.siteName!.isNotEmpty) ...[
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            annotation!.siteName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      const SizedBox(width: 6),
                      Text(formatDateShort(dive.startTime),
                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_buildStatsLine(),
                    style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12)),
                  if (annotationLine != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        annotationLine,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _buildAnnotationLine() {
    final ann = annotation;
    if (ann == null) return null;
    final buddies = ann.buddies;
    if (buddies.isEmpty) return null;
    return buddies.join(', ');
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
