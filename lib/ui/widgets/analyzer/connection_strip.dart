/// The Analyse tab's connection strip: one 32 pt row with the connection
/// state, and under it the Android note and the slim banners.
library;

import 'package:flutter/material.dart';

import '../../../analyzer/transport/analyzer_transport.dart';
import '../../notifiers/analyzer_session.dart';
import '../../theme/safety_colors.dart';
import '../../theme/tokens.dart';

/// The strip itself: status dot and text on the left; Source and Connect
/// when not connected, Disconnect while connecting or connected.
class ConnectionStrip extends StatelessWidget {
  const ConnectionStrip({super.key, required this.session});

  final AnalyzerSession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = session.controller;
    final busy = controller.isBusy;
    final (text, color) = switch (controller.status) {
      AnalyzerConnectionStatus.connected => (
          'SOLO connected · ${controller.transport?.name ?? ''}',
          SafetyColors.success
        ),
      AnalyzerConnectionStatus.connecting =>
        ('Connecting…', SafetyColors.warning),
      // A failed connect goes back to Not connected; the banner says why.
      AnalyzerConnectionStatus.disconnected ||
      AnalyzerConnectionStatus.error =>
        ('Not connected', palette.textMuted),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                text,
                key: const ValueKey('analyzer-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body
                    .copyWith(fontSize: 13, color: palette.textSecondary),
              ),
            ),
            if (busy)
              TextButton(
                key: const ValueKey('analyzer-disconnect'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 32),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: session.disconnect,
                child: const Text('Disconnect'),
              )
            else ...[
              _SourcePicker(session: session),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                key: const ValueKey('analyzer-connect'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 32),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: () => session.connectSelected(context),
                child: const Text('Connect'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.session});

  final AnalyzerSession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        key: const ValueKey('analyzer-transport'),
        value: session.selected,
        isDense: true,
        style: AppTypography.body
            .copyWith(fontSize: 13, color: palette.textPrimary),
        items: [
          for (var i = 0; i < session.options.length; i++)
            DropdownMenuItem(value: i, child: Text(session.options[i].label)),
        ],
        onChanged: (i) => session.select(i ?? 0),
      ),
    );
  }
}

/// A slim, full-width banner under the strip.
class AnalyzerBanner extends StatelessWidget {
  const AnalyzerBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: palette.accentPrimary.withValues(alpha: 0.15),
        border: Border.symmetric(
            horizontal: BorderSide(color: palette.accentPrimary)),
      ),
      child: Text(text,
          style: AppTypography.body
              .copyWith(fontSize: 13, color: palette.textPrimary)),
    );
  }
}

/// What goes under the strip: the selected source's note while not
/// connected, the connect error, and the no-data hint (only for a SOLO that
/// never sent a line; one that streamed and went quiet is on hold).
class ConnectionNotices extends StatelessWidget {
  const ConnectionNotices({super.key, required this.session});

  final AnalyzerSession session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final note = session.options[session.selected].note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null && !controller.isBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, 0, Spacing.md, Spacing.xs),
            child: Text(
              note,
              key: const ValueKey('analyzer-transport-note'),
              style: AppTypography.caption
                  .copyWith(color: context.palette.textMuted),
            ),
          ),
        if (controller.status == AnalyzerConnectionStatus.error)
          AnalyzerBanner(
            key: const ValueKey('analyzer-error-banner'),
            text: controller.errorMessage ??
                'Connection to the analyzer failed.',
          ),
        if (controller.noDataHint && !controller.hasHadData)
          const AnalyzerBanner(
            key: ValueKey('analyzer-no-data-hint'),
            text: 'No data is arriving. On the SOLO set Menu → Preferences → '
                '"Send data to USB" above zero, and turn printer mode off.',
          ),
      ],
    );
  }
}
