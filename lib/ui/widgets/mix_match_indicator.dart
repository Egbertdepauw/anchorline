/// Shows how close an analysed gas is to the desired mix (issue #114), with
/// the colour of its match level.
library;

import 'package:flutter/material.dart';

import '../../analysis/mix_match.dart';
import '../../data/models/gas_analysis.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

/// The colour for a match level: green for a match, orange for orange, red
/// for red and for a hard mismatch.
Color mixMatchColor(MixMatchLevel level) => switch (level) {
      MixMatchLevel.match => SafetyColors.success,
      MixMatchLevel.orange => SafetyColors.warning,
      MixMatchLevel.red || MixMatchLevel.hard => SafetyColors.danger,
    };

/// The analysed numbers (`O2 20.6  He 33.8`) in the colour of the match
/// level, and under them the one-line explanation from [mixMatchText]
/// (`Matches Tx21/35`, `O2 1.5 off Tx21/35`), so the colour is never the
/// only signal.
///
/// [o2Percent] and [hePercent] must be finite, like a reading the save card
/// accepts: grading a NaN or infinite value throws.
class MixMatchIndicator extends StatelessWidget {
  const MixMatchIndicator({
    super.key,
    required this.o2Percent,
    required this.hePercent,
    required this.desired,
  });

  final double o2Percent;
  final double hePercent;
  final DesiredMix desired;

  @override
  Widget build(BuildContext context) {
    final match = gradeMix(
      o2Percent: o2Percent,
      hePercent: hePercent,
      targetO2Percent: desired.o2Percent,
      targetHePercent: desired.hePercent,
    );
    final color = mixMatchColor(match.level);
    return Column(
      key: const ValueKey('mix-match-indicator'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'O2 ${o2Percent.toStringAsFixed(1)}  '
          'He ${hePercent.toStringAsFixed(1)}',
          style: AppTypography.readoutMd.copyWith(color: color),
        ),
        Text(
          mixMatchText(match, desired.name),
          style: AppTypography.label.copyWith(color: color),
        ),
      ],
    );
  }
}
