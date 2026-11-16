/// The "Not yet analysed (N)" list on the Blend tab: blends that have been
/// filled but not analysed yet, each with a settle dot (issue #112).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../analysis/open_blend_match.dart';
import '../../data/db/open_blends_dao.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

/// The colour of a settle state, the palette of `mixMatchColor`: red while
/// the gas is still mixing, orange halfway, green once it has settled.
Color settleColor(SettleState s) => switch (s) {
      SettleState.red => SafetyColors.danger,
      SettleState.orange => SafetyColors.warning,
      SettleState.green => SafetyColors.success,
    };

/// `just now` under a minute (or below zero), `12 min`, `1 h 05 min`.
String sinceBlendedText(Duration d) {
  final minutes = d.inMinutes;
  if (d.isNegative || minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min';
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '${minutes ~/ 60} h $m min';
}

class OpenBlendsSection extends StatefulWidget {
  const OpenBlendsSection({
    super.key,
    required this.dao,
    required this.settings,
    this.now = DateTime.now,
  });

  final OpenBlendsDaoLike dao;
  final SettingsNotifier settings;
  final DateTime Function() now;

  @override
  State<OpenBlendsSection> createState() => _OpenBlendsSectionState();
}

class _OpenBlendsSectionState extends State<OpenBlendsSection> {
  Timer? _tick;
  late Stream<List<OpenBlend>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.dao.watchOpen();
    // The dots change colour with time, so the rows refresh every minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(OpenBlendsSection old) {
    super.didUpdateWidget(old);
    if (old.dao != widget.dao) _stream = widget.dao.watchOpen();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _dismiss(OpenBlend b) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.dao.dismiss(b.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not dismiss: $e')));
    }
  }

  Widget _row(OpenBlend b, Duration since) => _Row(
        key: ValueKey('open-blend-row-${b.id}'),
        blend: b,
        since: since,
        state: settleState(
          sinceBlended: since,
          settleMinutes: widget.settings.blendSettleMinutes,
        ),
        onDismiss: () => _dismiss(b),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OpenBlend>>(
      stream: _stream,
      builder: (context, snap) {
        final blends = snap.data ?? const <OpenBlend>[];
        if (blends.isEmpty) return const SizedBox.shrink();
        final palette = context.palette;
        final now = widget.now();
        return ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm + 4, Spacing.md, Spacing.sm + 4),
            child: Column(
              key: const ValueKey('open-blends-section'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text('Not yet analysed (${blends.length})',
                      style: AppTypography.label
                          .copyWith(color: palette.accentPrimary)),
                ),
                for (final b in blends)
                  _row(b, now.difference(b.blendedAt)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.blend,
    required this.since,
    required this.state,
    required this.onDismiss,
  });

  final OpenBlend blend;
  final Duration since;
  final SettleState state;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            key: ValueKey('settle-dot-${blend.id}'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: settleColor(state), shape: BoxShape.circle),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(blend.target.name,
                    style: AppTypography.body
                        .copyWith(color: palette.textPrimary)),
                Text(
                  '${blend.role.label} · '
                  '${blend.targetPressureBar.toStringAsFixed(0)} bar',
                  style: AppTypography.caption
                      .copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Text(sinceBlendedText(since),
              style: AppTypography.caption
                  .copyWith(color: palette.textSecondary)),
          PopupMenuButton<String>(
            key: ValueKey('open-blend-menu-${blend.id}'),
            tooltip: 'More',
            onSelected: (_) => onDismiss(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
            ],
          ),
        ],
      ),
    );
  }
}
