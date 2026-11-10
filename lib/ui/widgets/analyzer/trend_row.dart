/// The Analyse tab's trend: one 30 pt row, "Trend, last 2 minutes", with a
/// small O₂ / He sparkline on the right. Tapping it opens the chart in
/// place. It starts collapsed every time.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../analyzer/analyzer_controller.dart';
import '../../theme/data_colors.dart';
import '../../theme/tokens.dart';
import '../analyzer_live_chart.dart';

class TrendRow extends StatefulWidget {
  const TrendRow({super.key, required this.controller});

  final AnalyzerController controller;

  @override
  State<TrendRow> createState() => _TrendRowState();
}

class _TrendRowState extends State<TrendRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.controller;
    Widget legend(String text, Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 3, color: color),
            const SizedBox(width: Spacing.xs + 2),
            Text(text,
                style:
                    AppTypography.caption.copyWith(color: palette.textMuted)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('analyzer-trend'),
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Row(
                children: [
                  Icon(_open ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 18, color: palette.textMuted),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      'Trend, last 2 minutes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                          fontSize: 13, color: palette.textSecondary),
                    ),
                  ),
                  if (_open) ...[
                    legend('O₂', palette.accentPrimary),
                    const SizedBox(width: Spacing.md),
                    legend('He', DataColors.helium),
                  ] else
                    SizedBox(
                      width: 64,
                      height: 16,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          points: c.history,
                          nowSeconds: c.historyNowSeconds,
                          windowSeconds:
                              c.historyWindow.inSeconds.toDouble(),
                          o2Color: palette.accentPrimary,
                          heColor: DataColors.helium,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.xs, Spacing.lg, Spacing.md),
            child: AnalyzerLiveChart(
              key: const ValueKey('analyzer-trend-chart'),
              points: c.history,
              nowSeconds: c.historyNowSeconds,
              windowSeconds: c.historyWindow.inSeconds.toDouble(),
              o2Color: palette.accentPrimary,
              heColor: DataColors.helium,
            ),
          ),
      ],
    );
  }
}

/// Two bare lines, O₂ and He, each scaled to its own range.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.nowSeconds,
    required this.windowSeconds,
    required this.o2Color,
    required this.heColor,
  });

  final List<AnalyzerHistoryPoint> points;
  final double nowSeconds;
  final double windowSeconds;
  final Color o2Color;
  final Color heColor;

  @override
  void paint(Canvas canvas, Size size) {
    void line(double Function(AnalyzerHistoryPoint) pick, Color color) {
      final values = [
        for (final p in points)
          if (pick(p).isFinite) (p.seconds, pick(p)),
      ];
      if (values.length < 2) return;
      final lo = values.map((v) => v.$2).reduce(math.min);
      final hi = values.map((v) => v.$2).reduce(math.max);
      final span = math.max(hi - lo, 2.0);
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = (1 - (nowSeconds - values[i].$1) / windowSeconds)
                .clamp(0.0, 1.0) *
            size.width;
        final y = size.height - ((values[i].$2 - lo) / span) * size.height;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    line((p) => p.o2, o2Color);
    line((p) => p.he, heColor);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.nowSeconds != nowSeconds;
}
