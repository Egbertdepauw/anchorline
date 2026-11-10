import 'package:flutter/material.dart';

import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'section_header.dart';

/// One settings row: a title, an optional one-line helper under it, and the
/// control on the right. A row with an [onTap] and no [control] shows a
/// chevron; [danger] draws the title in the danger colour.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.helper,
    this.control,
    this.onTap,
    this.danger = false,
  });

  final String title;
  final String? helper;
  final Widget? control;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body.copyWith(
                        color: danger
                            ? SafetyColors.danger
                            : palette.textPrimary,
                      ),
                    ),
                    if (helper != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          helper!,
                          style: AppTypography.caption.copyWith(
                            color: palette.textMuted,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (control != null) ...[
              const SizedBox(width: Spacing.md),
              control!,
            ] else if (onTap != null)
              Icon(Icons.chevron_right, color: palette.textMuted),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// A row whose control sits below the title, for controls too wide to share a
/// line with it (a wrapping set of chips). Same padding as [SettingRow].
class SettingBlock extends StatelessWidget {
  const SettingBlock({
    super.key,
    required this.title,
    this.helper,
    required this.child,
  });

  final String title;
  final String? helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.body.copyWith(color: palette.textPrimary)),
          if (helper != null)
            Text(helper!,
                style: AppTypography.caption.copyWith(color: palette.textMuted)),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}

/// A settings section: the dive screen's uppercase heading over [children],
/// with a hairline between them and one under the last.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = Divider(
        height: 1, thickness: 1, color: context.palette.surfaceRaised);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
          child: SectionHeader(title),
        ),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) line,
          children[i],
        ],
        const SizedBox(height: Spacing.sm),
        line,
      ],
    );
  }
}
