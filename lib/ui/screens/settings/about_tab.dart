import 'package:flutter/material.dart';

import '../../../build_info.dart';
import '../../components/hero_stat.dart';
import '../../components/setting_row.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchorline_logo.dart';

/// About: the logo, tagline and build stats, then author, channel and
/// (when the repository has a LICENSE file) licence, and the support action.
/// The parameters default to the compile-time [BuildInfo]; tests vary them.
class AboutTab extends StatelessWidget {
  const AboutTab({
    super.key,
    this.version = BuildInfo.version,
    String build = BuildInfo.build,
    this.buildDate = BuildInfo.buildDate,
    this.channel = BuildInfo.channel,
    this.hasLicence = false,
    this.onLongPressLogo,
    this.onShareBleLog,
  }) : buildNumber = build;

  final String version;
  /// Named `build` in the constructor; the field can't take that name
  /// because [build] is the widget's build method.
  final String buildNumber;

  /// `yyyy-MM-dd`; empty hides the Date stat.
  final String buildDate;
  final String channel;

  /// False until the repository has a LICENSE file.
  final bool hasLicence;

  /// Long-press on the logo; opens Widgetbook.
  final VoidCallback? onLongPressLogo;

  final VoidCallback? onShareBleLog;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDev = version.isEmpty || buildNumber.isEmpty;
    final date = formatBuildDate(buildDate);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            children: [
              GestureDetector(
                key: const ValueKey('about-logo'),
                behavior: HitTestBehavior.opaque,
                onLongPress: onLongPressLogo,
                child: const AnchorlineLogo(
                    mark: AnchorlineMark.icon, size: 64),
              ),
              const SizedBox(height: Spacing.md),
              Text('Anchorline',
                  style: AppTypography.title
                      .copyWith(color: palette.textPrimary)),
              const SizedBox(height: Spacing.xs),
              Text('Dive log and analysis for CCR divers',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption
                      .copyWith(color: palette.textMuted)),
              const SizedBox(height: Spacing.lg),
              if (isDev)
                Text('Development build',
                    key: const ValueKey('about-dev-build'),
                    style: AppTypography.body
                        .copyWith(color: palette.textSecondary))
              else
                HeroStatRow(
                  children: [
                    HeroStat(
                      valueKey: const ValueKey('about-version'),
                      value: version,
                      label: 'Version',
                      centered: true,
                    ),
                    HeroStat(
                      valueKey: const ValueKey('about-build'),
                      value: buildNumber,
                      label: 'Build',
                      centered: true,
                    ),
                    if (date != null)
                      HeroStat(
                        valueKey: const ValueKey('about-date'),
                        value: date,
                        label: 'Date',
                        centered: true,
                      ),
                  ],
                ),
            ],
          ),
        ),
        SettingsGroup(
          title: 'About',
          children: [
            const SettingRow(
              key: ValueKey('about-author'),
              title: 'Author',
              control: _Value('Egbert de Pauw'),
            ),
            SettingRow(
              title: 'Channel',
              control: _Value(channelLabel(channel)),
            ),
            if (hasLicence)
              const SettingRow(
                key: ValueKey('about-licence'),
                title: 'Licence',
                control: _Value('GPLv2'),
              ),
          ],
        ),
        SettingsGroup(
          title: 'Support',
          children: [
            SettingRow(
              key: const ValueKey('about-share-ble-log'),
              title: 'Share Bluetooth debug log',
              helper: 'Protocol events and timings only, no dive data',
              onTap: onShareBleLog,
            ),
          ],
        ),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppTypography.body.copyWith(color: context.palette.textSecondary));
}
