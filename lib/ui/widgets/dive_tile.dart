import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import 'package:subsurface_core/data/models/annotation.dart' as dom;
import '../components/numeric_readout.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import 'sparkline.dart';

class DiveTile extends StatelessWidget {
  final Dive dive;
  final Float32List? sparklineData;
  final dom.DiveAnnotation? annotation;
  final VoidCallback onTap;

  /// CCRLog-internal sequence number used for the `#N` label. See
  /// [DiveListNotifier.sequenceByDiveId]. Falls back to the DC's own
  /// dive number when null (e.g. tests that haven't wired the notifier).
  final int? sequenceNumber;

  const DiveTile({
    super.key,
    required this.dive,
    required this.sparklineData,
    required this.onTap,
    this.annotation,
    this.sequenceNumber,
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = diveModeColor(dive.diveMode);
    final scheme = Theme.of(context).colorScheme;
    final annotationLine = _buildAnnotationLine();

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: modeColor, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm + 2),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 36,
              child: sparklineData != null && sparklineData!.isNotEmpty
                  ? DepthSparkline(depths: sparklineData!, color: modeColor)
                  : Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: Radii.cardBr,
                      ),
                    ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        diveModeLabel(dive.diveMode),
                        style: AppTypography.label.copyWith(color: modeColor),
                      ),
                      const SizedBox(width: Spacing.xs + 2),
                      NumericReadout(
                        '#${sequenceNumber ?? dive.dcDiveNumber}',
                        size: ReadoutSize.sm,
                        color: scheme.onSurface,
                      ),
                      if (annotation?.siteName != null &&
                          annotation!.siteName!.isNotEmpty) ...[
                        Text(
                          ' · ',
                          style: AppTypography.body.copyWith(
                            color: scheme.outlineVariant,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            annotation!.siteName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      const SizedBox(width: Spacing.sm - 2),
                      Text(
                        formatDateShort(dive.startTime),
                        style: AppTypography.caption.copyWith(
                          color: scheme.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xs - 2),
                  NumericReadout(
                    _buildStatsLine(),
                    size: ReadoutSize.sm,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                  if (annotationLine != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        annotationLine,
                        style: AppTypography.caption.copyWith(
                          color: SafetyColors.info,
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
