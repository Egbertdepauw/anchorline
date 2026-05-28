/// Dedicated per-dive O2-cell / PPO2 / setpoint chart.
///
/// The main [ProfileChart] is depth-centric; the cell + PPO2 + setpoint
/// traces are overlays that can crowd it. This widget plots just the CCR
/// loop's oxygen picture on a full-height PPO2 axis (0–2.0 bar) over the
/// dive's sample time axis, so cell divergence / setpoint tracking is
/// easy to read. Lives in a collapsible section on the dive detail
/// screen (collapsed by default, like the tissue heatmap).
///
/// Cell millivolts are converted to PPO2 with the dive's per-cell
/// calibration factor (falling back to the Petrel default 0.021 mV→bar)
/// so all four traces share one comparable axis.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models/sample_set.dart';
import '../theme/tokens.dart';

/// Petrel default mV→PPO2(bar) factor when no calibration is available.
const double _defaultCellCal = 0.021;
const double _ppo2Max = 2.0;

const double _leftPad = 36.0;
const double _rightPad = 12.0;
const double _topPad = 8.0;
const double _bottomPad = 18.0;

class CellDataChart extends StatelessWidget {
  final SampleSet samples;

  /// Per-cell calibration factors (length up to 3). Used to convert raw
  /// mV → PPO2. Missing / non-positive entries fall back to [_defaultCellCal].
  final List<double>? cellCalibration;

  /// Optional physical-cell labels keyed by 1-indexed slot, used in the
  /// legend (e.g. {1: 'Top R-22D'}). Falls back to "Cell N".
  final Map<int, String>? cellLabels;

  final double height;

  const CellDataChart({
    super.key,
    required this.samples,
    this.cellCalibration,
    this.cellLabels,
    this.height = 220,
  });

  double _calOf(int idx) {
    final cal = cellCalibration;
    if (cal == null || idx >= cal.length) return _defaultCellCal;
    final c = cal[idx];
    return c > 0 ? c : _defaultCellCal;
  }

  bool _hasNonZero(Float32List a) {
    for (final v in a) {
      if (v != 0) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cell0 = AppColors.wreck.cell1;
    final cell1 = AppColors.wreck.cell2;
    final cell2 = AppColors.wreck.cell3;
    final ppo2Color = AppColors.wreck.chartTracePpo2;
    final setpointColor = AppColors.wreck.chartTraceSetpoint;

    final hasCells = _hasNonZero(samples.cellMv0) ||
        _hasNonZero(samples.cellMv1) ||
        _hasNonZero(samples.cellMv2);
    final hasPpo2 = _hasNonZero(samples.ppo2Bar);
    final hasSetpoint = _hasNonZero(samples.setpointBar);

    if (!hasCells && !hasPpo2 && !hasSetpoint) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No cell / PPO2 data recorded for this dive',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _CellDataPainter(
              samples: samples,
              cal0: _calOf(0),
              cal1: _calOf(1),
              cal2: _calOf(2),
              cell0Color: cell0,
              cell1Color: cell1,
              cell2Color: cell2,
              ppo2Color: ppo2Color,
              setpointColor: setpointColor,
              gridColor: AppColors.wreck.chartGrid,
              hasCells: hasCells,
              hasPpo2: hasPpo2,
              hasSetpoint: hasSetpoint,
            ),
          ),
        ),
        Positioned(
          left: _leftPad + 4,
          top: _topPad + 2,
          child: _Legend(
            hasCells: hasCells,
            hasPpo2: hasPpo2,
            hasSetpoint: hasSetpoint,
            cell0: cell0,
            cell1: cell1,
            cell2: cell2,
            ppo2Color: ppo2Color,
            setpointColor: setpointColor,
            cellLabels: cellLabels,
          ),
        ),
      ]),
    );
  }
}

class _CellDataPainter extends CustomPainter {
  final SampleSet samples;
  final double cal0;
  final double cal1;
  final double cal2;
  final Color cell0Color;
  final Color cell1Color;
  final Color cell2Color;
  final Color ppo2Color;
  final Color setpointColor;
  final Color gridColor;
  final bool hasCells;
  final bool hasPpo2;
  final bool hasSetpoint;

  _CellDataPainter({
    required this.samples,
    required this.cal0,
    required this.cal1,
    required this.cal2,
    required this.cell0Color,
    required this.cell1Color,
    required this.cell2Color,
    required this.ppo2Color,
    required this.setpointColor,
    required this.gridColor,
    required this.hasCells,
    required this.hasPpo2,
    required this.hasSetpoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = samples.sampleCount;
    if (n < 2) return;

    final chartLeft = _leftPad;
    final chartRight = size.width - _rightPad;
    final chartTop = _topPad;
    final chartBottom = size.height - _bottomPad;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    double xOf(int i) => chartLeft + (i / (n - 1)) * chartWidth;
    double yPpo2(double p) =>
        chartBottom - (p / _ppo2Max).clamp(0.0, 1.0) * chartHeight;

    // Grid + y-axis labels at 0.5 bar intervals.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    final labelStyle = TextStyle(
      color: gridColor,
      fontSize: 9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (final p in [0.5, 1.0, 1.5, 2.0]) {
      final y = yPpo2(p);
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: p.toStringAsFixed(1), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartLeft - tp.width - 3, y - tp.height / 2));
    }

    canvas.save();
    canvas.clipRect(
        Rect.fromLTRB(chartLeft, chartTop, chartRight, chartBottom));

    void drawSolid(Float32List data, double Function(double) yMap,
        Color color, double width) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(xOf(0), yMap(data[0]));
      for (var i = 1; i < n; i++) {
        path.lineTo(xOf(i), yMap(data[i]));
      }
      canvas.drawPath(path, paint);
    }

    // Setpoint first (dashed-ish, thin) so cells/ppo2 read on top.
    if (hasSetpoint) {
      drawSolid(samples.setpointBar, yPpo2, setpointColor, 1.0);
    }
    if (hasCells) {
      drawSolid(samples.cellMv0, (mv) => yPpo2(mv * cal0), cell0Color, 1.0);
      drawSolid(samples.cellMv1, (mv) => yPpo2(mv * cal1), cell1Color, 1.0);
      drawSolid(samples.cellMv2, (mv) => yPpo2(mv * cal2), cell2Color, 1.0);
    }
    // Voted PPO2 on top, slightly heavier — it's the controlling value.
    if (hasPpo2) {
      drawSolid(samples.ppo2Bar, yPpo2, ppo2Color, 1.6);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CellDataPainter old) =>
      !identical(old.samples, samples) ||
      old.cal0 != cal0 ||
      old.cal1 != cal1 ||
      old.cal2 != cal2;
}

class _Legend extends StatelessWidget {
  final bool hasCells;
  final bool hasPpo2;
  final bool hasSetpoint;
  final Color cell0;
  final Color cell1;
  final Color cell2;
  final Color ppo2Color;
  final Color setpointColor;
  final Map<int, String>? cellLabels;

  const _Legend({
    required this.hasCells,
    required this.hasPpo2,
    required this.hasSetpoint,
    required this.cell0,
    required this.cell1,
    required this.cell2,
    required this.ppo2Color,
    required this.setpointColor,
    this.cellLabels,
  });

  String _cellLabel(int slot) => cellLabels?[slot] ?? 'Cell $slot';

  @override
  Widget build(BuildContext context) {
    final items = <(Color, String)>[
      if (hasPpo2) (ppo2Color, 'PPO2'),
      if (hasSetpoint) (setpointColor, 'Setpoint'),
      if (hasCells) ...[
        (cell0, _cellLabel(1)),
        (cell1, _cellLabel(2)),
        (cell2, _cellLabel(3)),
      ],
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final (color, label) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ]),
      ],
    );
  }
}
