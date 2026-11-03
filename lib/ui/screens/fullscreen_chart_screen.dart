/// Fullscreen, zoomable/pannable dive profile chart.
///
/// Opened from the inline chart's fullscreen button on the dive detail
/// screen. Because this route has NO TabBarView competing for horizontal
/// drag, a single [GestureDetector.onScaleUpdate] cleanly handles both
/// pinch-to-zoom (scale != 1) AND single-finger-drag pan (scale ≈ 1,
/// focal point moves) — the gesture-arena conflict that blocked inline
/// panning simply doesn't exist here. macOS trackpad scroll is handled
/// via [Listener.onPointerSignal] (no parent Scrollable to eat it).
library;

import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';

import '../../analysis/deco/replay_result.dart';
import '../../data/db/database.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix, DiveTank;
import 'package:subsurface_core/data/models/sample_set.dart';
import '../widgets/crosshair_overlay.dart';
import '../widgets/crosshair_tooltip.dart';
import '../widgets/profile_chart.dart';
import '../widgets/trace_segmented_bar.dart' show TraceType;

class FullscreenChartScreen extends StatefulWidget {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final Map<int, OxygenCell>? cellsBySlot;
  final List<DiveTank>? tanks;
  final Map<int, Cylinder>? mappedCylinders;
  final List<DiveGasMix>? gasMixes;
  final bool useSpeedColoredGraph;
  final bool endCountsOxygen;
  final bool isCcr;
  final DecoReplayResult? decoReplay;
  final String title;

  const FullscreenChartScreen({
    super.key,
    required this.samples,
    required this.visibleTraces,
    required this.title,
    this.cellsBySlot,
    this.tanks,
    this.mappedCylinders,
    this.gasMixes,
    this.useSpeedColoredGraph = true,
    this.endCountsOxygen = true,
    this.isCcr = false,
    this.decoReplay,
  });

  @override
  State<FullscreenChartScreen> createState() => _FullscreenChartScreenState();
}

class _FullscreenChartScreenState extends State<FullscreenChartScreen> {
  // Viewport as fractions of the total sample count.
  double _viewStart = 0.0;
  double _viewEnd = 1.0;
  double _viewStartAtScaleBegin = 0.0;
  double _viewEndAtScaleBegin = 1.0;
  Offset _focalAtScaleBegin = Offset.zero;

  int? _crosshairIndex;

  // Double-tap-to-reset via raw pointer timestamps (onDoubleTap can't
  // coexist with onScaleStart — the scale recognizer claims the pointer
  // first). Active-pointer tracking keeps a two-finger pinch from
  // false-triggering a reset.
  DateTime? _lastSingleTapTime;
  final _activePointers = <int>{};

  bool get _isZoomed => (_viewEnd - _viewStart) < 0.99;

  void _reset() => setState(() {
        _viewStart = 0.0;
        _viewEnd = 1.0;
      });

  void _onScaleStart(ScaleStartDetails d) {
    _viewStartAtScaleBegin = _viewStart;
    _viewEndAtScaleBegin = _viewEnd;
    _focalAtScaleBegin = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      final box = context.size;
      final chartWidth = (box?.width ?? 300) - 84;
      // `d.scale` is cumulative relative to scale-start, so anchor the
      // math on the span captured at begin. scale != 1 → zoom; scale ≈ 1
      // with the focal point moving → pan. Both fall out of focal-point
      // anchoring: the dive fraction under the initial focal point stays
      // under the current focal point.
      final spanAtBegin = _viewEndAtScaleBegin - _viewStartAtScaleBegin;
      final newSpan = (spanAtBegin / d.scale).clamp(0.02, 1.0);
      final initialFocusFrac = _viewStartAtScaleBegin +
          ((_focalAtScaleBegin.dx - 40) / chartWidth).clamp(0.0, 1.0) *
              spanAtBegin;
      final currentFocusInView =
          ((d.localFocalPoint.dx - 40) / chartWidth).clamp(0.0, 1.0);
      var start = initialFocusFrac - currentFocusInView * newSpan;
      start = start.clamp(0.0, 1.0 - newSpan);
      _viewStart = start;
      _viewEnd = start + newSpan;
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    _activePointers.add(e.pointer);
    if (_activePointers.length == 1) {
      final now = DateTime.now();
      if (_lastSingleTapTime != null &&
          now.difference(_lastSingleTapTime!) <
              const Duration(milliseconds: 300)) {
        _reset();
        _lastSingleTapTime = null;
      } else {
        _lastSingleTapTime = now;
      }
    } else {
      _lastSingleTapTime = null;
    }
  }

  void _onPointerUp(PointerUpEvent e) => _activePointers.remove(e.pointer);
  void _onPointerCancel(PointerCancelEvent e) =>
      _activePointers.remove(e.pointer);

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dy = e.scrollDelta.dy;
    final dx = e.scrollDelta.dx;
    if (dy.abs() < 0.5 && dx.abs() < 0.5) return;
    setState(() {
      final box = context.size;
      final chartWidth = (box?.width ?? 300) - 84;
      // Vertical scroll → zoom centred on cursor.
      if (dy.abs() > 0.5) {
        final cursorFrac = _viewStart +
            ((e.localPosition.dx - 40) / chartWidth).clamp(0.0, 1.0) *
                (_viewEnd - _viewStart);
        final zoomFactor = dy > 0 ? 1.1 : 0.9;
        final span = _viewEnd - _viewStart;
        final newSpan = (span * zoomFactor).clamp(0.02, 1.0);
        final cursorInView =
            ((e.localPosition.dx - 40) / chartWidth).clamp(0.0, 1.0);
        var start = cursorFrac - cursorInView * newSpan;
        start = start.clamp(0.0, 1.0 - newSpan);
        _viewStart = start;
        _viewEnd = start + newSpan;
      }
      // Horizontal scroll → pan when zoomed.
      if (dx.abs() > 0.5 && _isZoomed) {
        final span = _viewEnd - _viewStart;
        final panFrac = (dx / chartWidth) * span * 3.0;
        var start = (_viewStart + panFrac).clamp(0.0, 1.0 - span);
        _viewStart = start;
        _viewEnd = start + span;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final samples = widget.samples;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isZoomed)
            IconButton(
              tooltip: 'Reset zoom',
              icon: const Icon(Icons.zoom_out_map),
              onPressed: _reset,
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: CrosshairOverlay(
              sampleCount: samples.sampleCount,
              chartLeftPad: 40,
              chartRightPad: 44,
              viewStart: _viewStart,
              viewEnd: _viewEnd,
              onIndexChanged: (i) => setState(() => _crosshairIndex = i),
              onRelease: () => setState(() => _crosshairIndex = null),
              child: Stack(children: [
                ProfileChart(
                  samples: samples,
                  visibleTraces: widget.visibleTraces,
                  crosshairIndex: _crosshairIndex,
                  cellsBySlot: widget.cellsBySlot,
                  tanks: widget.tanks,
                  mappedCylinders: widget.mappedCylinders,
                  gasMixes: widget.gasMixes,
                  useSpeedColoredGraph: widget.useSpeedColoredGraph,
                  endCountsOxygen: widget.endCountsOxygen,
                  isCcr: widget.isCcr,
                  viewStart: _viewStart,
                  viewEnd: _viewEnd,
                  decoReplay: widget.decoReplay,
                ),
                if (_crosshairIndex != null)
                  CrosshairTooltip(
                    samples: samples,
                    sampleIndex: _crosshairIndex!,
                    visibleTraces: widget.visibleTraces,
                    chartX: 40 +
                        ((_crosshairIndex! / (samples.sampleCount - 1) -
                                    _viewStart) /
                                (_viewEnd - _viewStart)) *
                            (constraints.maxWidth - 84),
                    chartWidth: constraints.maxWidth,
                    cellsBySlot: widget.cellsBySlot,
                    tanks: widget.tanks,
                    mappedCylinders: widget.mappedCylinders,
                    gasMixes: widget.gasMixes,
                    decoReplay: widget.decoReplay,
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}
