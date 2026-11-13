/// The row of the Analyse card that says which open blend a save closes,
/// with "Change" and the mismatch warning (issue #112), and the
/// "Residual analysis" switch.
///
/// The row is one 32 pt line, with two lines of text at most, and only
/// there while there are open blends. The warning is below it, and only
/// there when the reading is off the blend. The switch is a widget of its
/// own ([ResidualSwitch]) that the card puts on the "+ Add a note" line, so
/// it costs the card no height of its own.
library;

import 'package:flutter/material.dart';

import '../../analysis/open_blend_match.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'analysis_save_controller.dart';
import 'mix_match_indicator.dart' show mixMatchColor;
import 'open_blends_section.dart' show sinceBlendedText;

class BlendCloseRow extends StatelessWidget {
  const BlendCloseRow({super.key, required this.controller});

  final AnalysisSaveController controller;

  /// "Closes Tx18/45 · blended 1 h 05 min ago", "No open blend" or "No open
  /// blend matches. Nearest: Tx50 (red)"; null when there is nothing to
  /// say (no open blends, or a residual).
  String? _text() {
    final c = controller;
    if (c.residual || c.openBlends.isEmpty) return null;
    final blend = c.blendToClose;
    if (blend != null) {
      final since = sinceBlendedText(c.now().difference(blend.blendedAt));
      final ago = since == 'just now' ? 'just now' : '$since ago';
      return 'Closes ${blend.target.name} · blended $ago';
    }
    final nearest = c.nearestUnmatched;
    if (nearest != null) {
      return 'No open blend matches. Nearest: ${nearest.blend.target.name} '
          '(${nearest.grade.level.name})';
    }
    return 'No open blend';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // Nothing to close and nothing to warn about: no row, no height.
    if (c.openBlends.isEmpty || c.residual) return const SizedBox.shrink();
    final palette = context.palette;
    final text = _text();
    final warning = c.warning;
    final loud = warning?.level == WarningLevel.loud;
    final style = AppTypography.caption.copyWith(color: palette.textMuted);
    return Column(
      key: const ValueKey('blend-close-row'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text ?? '',
                  key: const ValueKey('blend-close-text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              TextButton(
                key: const ValueKey('blend-close-change'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: AppTypography.body
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _change(context),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Text(
              warning.text,
              key: const ValueKey('blend-close-warning'),
              style: loud
                  ? AppTypography.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: SafetyColors.danger)
                  : style,
            ),
          ),
      ],
    );
  }

  /// The sheet with every open blend, best match first, and "None".
  Future<void> _change(BuildContext context) async {
    final c = controller;
    final choices = c.blendChoices;
    final now = c.now();
    final picked = await showModalBottomSheet<BlendChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('blend-choice-auto'),
                title: const Text('Automatic'),
                onTap: () => Navigator.of(ctx).pop(const AutoBlend()),
              ),
              for (final r in choices)
                ListTile(
                  key: ValueKey('blend-choice-${r.blend.id}'),
                  leading: Icon(Icons.circle,
                      size: 12, color: mixMatchColor(r.grade.level)),
                  title: Text(r.blend.target.name),
                  subtitle: Text('${r.blend.role.label} · '
                      '${r.grade.level.name} · blended '
                      '${sinceBlendedText(now.difference(r.blend.blendedAt))}'),
                  onTap: () => Navigator.of(ctx).pop(PickedBlend(r.blend)),
                ),
              ListTile(
                key: const ValueKey('blend-choice-none'),
                title: const Text('None'),
                onTap: () => Navigator.of(ctx).pop(const NoBlend()),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) c.chooseBlend(picked);
  }
}

/// The "Residual analysis" switch: the next saves are residuals, which close
/// no blend, have no desired mix and print no label.
class ResidualSwitch extends StatelessWidget {
  const ResidualSwitch({super.key, required this.controller});

  final AnalysisSaveController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style =
        AppTypography.caption.copyWith(color: context.palette.textMuted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Semantics(
            label: 'Residual analysis',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => c.setResidual(!c.residual),
              child: Text('Residual',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ),
        ),
        // The switch is 60 x 40; scaled to 48 x 32 it keeps the line at the
        // card's 32 pt floor.
        SizedBox(
          width: 48,
          height: 32,
          child: FittedBox(
            child: Switch(
              key: const ValueKey('analysis-residual-toggle'),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: c.residual,
              onChanged: c.setResidual,
            ),
          ),
        ),
      ],
    );
  }
}
