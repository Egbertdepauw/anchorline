/// Field and verdict styles shared by the Analyse tab's save section and
/// the Log tab's edit sheet, so both read as one form.
library;

import 'package:flutter/material.dart';

import '../../analysis/mix_match.dart';
import '../../analysis/standard_mix_pick.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'mix_match_indicator.dart' show mixMatchColor;

/// The height of the section's fields on the Analyse tab (spec §4.1 height
/// budget). They grow with large text.
const double kAnalysisFieldHeight = 40;

/// An input with no decoration of its own: the [AnalysisFieldBox] draws it.
InputDecoration analysisBareDecoration(BuildContext context, {String? hint}) =>
    InputDecoration(
      isDense: true,
      filled: false,
      contentPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      hintText: hint,
      hintStyle:
          AppTypography.body.copyWith(color: context.palette.textMuted),
    );

/// The verdict on the desired mix, in the match colour with a dot, e.g.
/// "Matches Tx21/35, the nearest standard mix". The suffix says where an
/// automatic pick came from; a diver's pick has none.
class AnalysisVerdict extends StatelessWidget {
  const AnalysisVerdict({super.key, required this.match, required this.mix, this.source});

  final MixMatch match;
  final DesiredMix mix;
  final MixPickSource? source;

  @override
  Widget build(BuildContext context) {
    final color = mixMatchColor(match.level);
    final suffix = switch (source) {
      MixPickSource.standard => ', the nearest standard mix',
      MixPickSource.blendTarget => ', the Blend target',
      null => '',
    };
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${mixMatchText(match, mix.name)}$suffix',
            key: const ValueKey('analysis-verdict'),
            style: AppTypography.label.copyWith(
              color: color,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

/// A dense field (spec §2): filled `surfaceCard`, a 1 px `surfaceBezel`
/// border (accent while focused, red on an error), a 2 px radius, and a
/// small label inside at the top. At least [kAnalysisFieldHeight] high. A
/// tap anywhere on it focuses [focusNode].
class AnalysisFieldBox extends StatefulWidget {
  const AnalysisFieldBox({
    super.key,
    required this.label,
    required this.child,
    this.focusNode,
    this.error = false,
  });

  final String label;
  final Widget child;
  final FocusNode? focusNode;
  final bool error;

  @override
  State<AnalysisFieldBox> createState() => AnalysisFieldBoxState();
}

class AnalysisFieldBoxState extends State<AnalysisFieldBox> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderColor = widget.error
        ? SafetyColors.danger
        : _focused
            ? palette.accentPrimary
            : palette.surfaceBezel;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.focusNode?.requestFocus,
        child: Container(
          constraints: const BoxConstraints(minHeight: kAnalysisFieldHeight),
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 1),
          decoration: BoxDecoration(
            color: palette.surfaceCard,
            border: Border.all(color: borderColor),
            borderRadius: Radii.cardBr,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                    fontSize: 10.5, height: 1.0, color: palette.textMuted),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}
