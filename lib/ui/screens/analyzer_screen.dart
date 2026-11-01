/// Live gas-analyzer screen (Divesoft SOLO).
///
/// Big O2 / He readouts, the mix name, a stability pill, a planning card
/// (MOD per configured ppO2, END, min depth, density, temperature,
/// ambient pressure) and a two-minute chart. Works with any
/// [AnalyzerTransport]: desktop USB serial, Android USB and the demo simulator.
/// Further transports (the BLE bridge, #113) plug in as extra
/// [AnalyzerTransportOption]s in [defaultAnalyzerTransportOptions].
///
/// Layout: one column on phones; from [kAnalyzerWideBreakpoint] up, a
/// grid like `docs/prototypes/solo-live.html` (readouts, mix and chart on
/// the left, planning on the right).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../../analysis/end.dart';
import '../../analysis/gas_density.dart';
import '../../analysis/gas_naming.dart';
import '../../analysis/mod.dart';
import '../../analyzer/analyzer_controller.dart';
import '../../analyzer/protocol/analyzer_reading.dart';
import '../../analyzer/stability.dart';
import '../../analyzer/transport/analyzer_transport.dart';
import '../../analyzer/transport/android_usb_transport.dart';
import '../../analyzer/transport/demo_transport.dart';
import '../../analyzer/transport/desktop_serial_transport.dart';
import '../../analyzer/transport/serial_port_selection.dart';
import '../../data/db/gas_analyses_dao.dart';
import '../../labels/label_print_service.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/data_colors.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import '../widgets/analysis_save_card.dart';
import '../widgets/analyzer_live_chart.dart';
import '../widgets/label_printer_settings_section.dart';
import '../widgets/serial_port_picker_dialog.dart';
import 'gas_analysis_log_screen.dart';

/// Width from which the screen switches to the two-column grid.
const double kAnalyzerWideBreakpoint = 840;

/// ppO2 the END and density rows are evaluated at (MOD at this limit).
const double kAnalyzerReferencePpo2 = 1.4;

/// ppO2 (bar) labelled "CCR dil": the max ppO2 on a rebreather diluent.
const double kAnalyzerCcrDiluentPpo2 = 1.1;

/// A transport the diver can pick on the analyzer screen.
class AnalyzerTransportOption {
  const AnalyzerTransportOption({
    required this.label,
    required this.create,
    this.note,
    this.choose,
    this.isDemo = false,
  });

  final String label;

  /// True for the built-in simulator. Its readings are made up, so the
  /// screen offers no way to save them to the gas analysis log.
  final bool isDemo;

  /// One short line shown under the source picker while this option is
  /// selected, or null.
  final String? note;

  /// Builds a fresh transport for one session. The controller owns and
  /// disposes it.
  final AnalyzerTransport Function() create;

  /// Optional interactive variant of [create] (e.g. a port picker), used
  /// by the Connect button when set. Returns null when the diver cancels.
  final Future<AnalyzerTransport?> Function(BuildContext context)? choose;
}

/// Port picked in the last desktop USB session, preselected next time.
String? _lastSerialPort;

/// Desktop USB serial (#108). Only offered on macOS/Windows/Linux, so
/// mobile and web never touch the dart:ffi serial code.
bool get _hasDesktopSerial =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// The transports available on this platform: desktop USB serial (#108)
/// on macOS/Windows/Linux, USB OTG on Android (#109), and the demo
/// simulator everywhere.
List<AnalyzerTransportOption> defaultAnalyzerTransportOptions() => [
      if (_hasDesktopSerial)
        AnalyzerTransportOption(
          label: 'USB',
          create: () => DesktopSerialTransport(
            portPath: _lastSerialPort ??
                preselectSerialPort(listDesktopSerialPorts()) ??
                '',
          ),
          choose: (context) async {
            final port = await showSerialPortPicker(
              context,
              listPorts: listDesktopSerialPorts,
              previous: _lastSerialPort,
            );
            if (port == null) return null;
            _lastSerialPort = port;
            return DesktopSerialTransport(portPath: port);
          },
        ),
      AnalyzerTransportOption(
        label: 'Demo',
        isDemo: true,
        create: () => DemoAnalyzerTransport(),
      ),
      if (!kIsWeb && Platform.isAndroid)
        AnalyzerTransportOption(
          label: 'USB (Android)',
          create: () => AndroidUsbTransport(),
          note: 'The phone powers the analyzer over the USB OTG cable.',
        ),
    ];

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({
    super.key,
    required this.settings,
    this.controller,
    this.transportOptions,
    this.analysesDao,
    this.blendTarget,
    this.labelPrinting,
  });

  final SettingsNotifier settings;

  /// Cylinder analysis log (#111). When null the save card and the log
  /// action are hidden.
  final GasAnalysesDaoLike? analysesDao;

  /// The Blend tab's recent target (#114), offered first as the desired
  /// mix on the save card.
  final DesiredMix? blendTarget;

  /// Cylinder label printing (#114): "Save & print" on the save card, or
  /// its "Set up label printer" link. Null hides both.
  final LabelPrintService? labelPrinting;

  /// Injected for tests. When null the screen owns its own controller.
  final AnalyzerController? controller;

  /// Defaults to [defaultAnalyzerTransportOptions].
  final List<AnalyzerTransportOption>? transportOptions;

  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  late final AnalyzerController _controller;
  late final bool _ownsController;
  late final List<AnalyzerTransportOption> _options;
  int _selected = 0;

  /// Whether the session that produced the current reading was the demo
  /// source, recorded when the session starts. The controller keeps the last
  /// reading after a disconnect and the Source picker is free again, so the
  /// selected option alone says nothing about where a frozen reading came
  /// from. Null until a first session starts.
  bool? _sessionIsDemo;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AnalyzerController();
    _options = widget.transportOptions ?? defaultAnalyzerTransportOptions();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleConnection() async {
    if (_controller.isBusy) {
      await _controller.disconnect();
    } else {
      final option = _options[_selected];
      final choose = option.choose;
      final transport =
          choose != null ? await choose(context) : option.create();
      if (transport == null) return;
      if (!mounted) {
        await transport.dispose();
        return;
      }
      // Before connecting: the controller clears the old reading as it
      // starts, and the new session's readings can arrive during connect.
      // If the connect fails there is no reading, so the flag isn't used.
      setState(() => _sessionIsDemo = option.isDemo);
      await _controller.connect(transport);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gas analyzer'),
        actions: [
          if (widget.analysesDao != null)
            IconButton(
              key: const ValueKey('analyzer-open-log'),
              tooltip: 'Analysis log',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    GasAnalysisLogScreen(dao: widget.analysesDao!),
              )),
            ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _StatusIndicator(controller: _controller),
          ),
          const SizedBox(width: Spacing.md),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_controller, widget.settings]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= kAnalyzerWideBreakpoint;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.md, Spacing.lg, Spacing.xl),
              child: wide ? _wideLayout() : _narrowLayout(),
            );
          },
        ),
      ),
    );
  }

  Widget _connectionBar() {
    final busy = _controller.isBusy;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: const ValueKey('analyzer-transport'),
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: 'Source',
              isDense: true,
            ),
            items: [
              for (var i = 0; i < _options.length; i++)
                DropdownMenuItem(value: i, child: Text(_options[i].label)),
            ],
            onChanged: busy ? null : (i) => setState(() => _selected = i ?? 0),
          ),
        ),
        const SizedBox(width: Spacing.md),
        FilledButton(
          key: const ValueKey('analyzer-connect'),
          onPressed: _toggleConnection,
          child: Text(busy ? 'Disconnect' : 'Connect'),
        ),
      ],
    );
  }

  List<Widget> _banners() {
    final out = <Widget>[];
    final note = _options[_selected].note;
    if (note != null) {
      out.add(Text(
        note,
        key: const ValueKey('analyzer-transport-note'),
        style: AppTypography.caption.copyWith(color: context.palette.textMuted),
      ));
    }
    if (_controller.status == AnalyzerConnectionStatus.error) {
      out.add(_Banner(
        key: const ValueKey('analyzer-error-banner'),
        text: _controller.errorMessage ?? 'Connection to the analyzer failed.',
      ));
    }
    if (_controller.noDataHint) {
      out.add(const _Banner(
        key: ValueKey('analyzer-no-data-hint'),
        text: 'Connected, but no data is arriving. On the analyzer set '
            'Menu → Preferences → "Send data to USB" to a non-zero value, '
            'and make sure printer mode is off.',
      ));
    }
    return [
      for (final b in out) ...[b, const SizedBox(height: Spacing.md)],
    ];
  }

  Widget _narrowLayout() {
    final r = _controller.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _connectionBar(),
        const SizedBox(height: Spacing.md),
        ..._banners(),
        _GasReadoutCard.o2(reading: r, fontSize: 64),
        const SizedBox(height: Spacing.md),
        _GasReadoutCard.he(reading: r, fontSize: 64),
        const SizedBox(height: Spacing.md),
        _MixCard(reading: r, stability: _controller.stability),
        const SizedBox(height: Spacing.md),
        _PlanningCard(reading: r, settings: widget.settings),
        const SizedBox(height: Spacing.md),
        _ChartCard(controller: _controller),
        ..._saveCard(),
      ],
    );
  }

  /// The "Save analysis" card (#111), preceded by a gap; empty without a
  /// DAO, and for readings from the demo source (they are made up). It goes
  /// by the session the reading came from ([_sessionIsDemo]), not the
  /// selected option, because a reading outlives its session and the diver
  /// can switch source in between. With no reading there is no session to
  /// ask (nothing yet, or a connect that failed), so the selected option
  /// decides.
  List<Widget> _saveCard() {
    final dao = widget.analysesDao;
    if (dao == null) return const [];
    final readingFromDemo =
        _controller.latest == null ? null : _sessionIsDemo;
    if (readingFromDemo ?? _options[_selected].isDemo) return const [];
    final printing = widget.labelPrinting;
    return [
      const SizedBox(height: Spacing.md),
      AnalysisSaveCard(
        dao: dao,
        reading: _controller.latest,
        stability: _controller.stability,
        modPpo2s: widget.settings.analyzerModPpo2s,
        blendTarget: widget.blendTarget,
        labelPrinting: printing,
        onSetUpPrinter: printing == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LabelPrinterSettingsScreen(
                    settings: widget.settings,
                    printing: printing,
                  ),
                )),
      ),
    ];
  }

  Widget _wideLayout() {
    final r = _controller.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _connectionBar(),
        const SizedBox(height: Spacing.lg),
        ..._banners(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child:
                              _GasReadoutCard.o2(reading: r, fontSize: 88)),
                      const SizedBox(width: Spacing.lg),
                      Expanded(
                          child:
                              _GasReadoutCard.he(reading: r, fontSize: 88)),
                    ],
                  ),
                  const SizedBox(height: Spacing.lg),
                  _MixCard(reading: r, stability: _controller.stability),
                  const SizedBox(height: Spacing.lg),
                  _ChartCard(controller: _controller),
                ],
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              flex: 11,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PlanningCard(reading: r, settings: widget.settings),
                  ..._saveCard(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Formatting helpers ───────────────────────────────────────────────

/// One-decimal readout: `--.-` before data, `***.*` on a sensor error
/// (what the SOLO itself shows).
String _fmtPercent(double? v) {
  if (v == null) return '--.-';
  if (!v.isFinite) return '***.*';
  return v.toStringAsFixed(1);
}

/// `1.1`, `1.25`, `1.4`: at least one decimal, no trailing zeros beyond.
String _fmtPpo2(double p) {
  var s = p.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

/// Usable gas fractions from a reading, or null when O2/He can't be used
/// for planning numbers (no data or sensor error).
({double fo2, double fhe})? _fractions(AnalyzerReading? r) {
  final o2 = r?.o2;
  final he = r?.he ?? 0;
  if (o2 == null || !o2.isFinite || o2 <= 0 || !he.isFinite) return null;
  return (fo2: o2 / 100, fhe: (he < 0 ? 0.0 : he) / 100);
}

// ── Cards ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        border: Border.all(color: palette.surfaceRaised),
        borderRadius: Radii.cardBr,
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTypography.label.copyWith(
          color: context.palette.textMuted,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: palette.accentPrimary.withValues(alpha: 0.15),
        border: Border.all(color: palette.accentPrimary),
        borderRadius: Radii.cardBr,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: palette.accentPrimary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(text,
                style: AppTypography.body
                    .copyWith(color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _GasReadoutCard extends StatelessWidget {
  const _GasReadoutCard._({
    required this.label,
    required this.valueKey,
    required this.value,
    required this.subtitle,
    required this.isO2,
    required this.fontSize,
  });

  factory _GasReadoutCard.o2(
      {required AnalyzerReading? reading, required double fontSize}) {
    final o2 = reading?.o2;
    final he = reading?.he ?? 0;
    final n2 = (o2 != null && o2.isFinite && he.isFinite)
        ? 100 - o2 - he
        : null;
    return _GasReadoutCard._(
      label: 'Oxygen',
      valueKey: const ValueKey('analyzer-o2'),
      value: _fmtPercent(o2),
      subtitle: 'N₂ balance ${n2 == null ? '–' : n2.toStringAsFixed(1)} %',
      isO2: true,
      fontSize: fontSize,
    );
  }

  factory _GasReadoutCard.he(
      {required AnalyzerReading? reading, required double fontSize}) {
    final he = reading?.he;
    return _GasReadoutCard._(
      label: 'Helium',
      valueKey: const ValueKey('analyzer-he'),
      value: _fmtPercent(he),
      subtitle: reading == null
          ? 'He'
          : (he != null && he.isFinite && he > 0.5
              ? 'Helium present'
              : 'No helium'),
      isO2: false,
      fontSize: fontSize,
    );
  }

  final String label;
  final Key valueKey;
  final String value;
  final String subtitle;
  final bool isO2;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = isO2 ? palette.accentPrimary : DataColors.helium;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(label),
          const SizedBox(height: Spacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  key: valueKey,
                  style: AppTypography.readoutLg.copyWith(
                    fontSize: fontSize,
                    height: 1,
                    color: color,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  '%',
                  style: AppTypography.readoutLg.copyWith(
                    fontSize: fontSize * 0.35,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(subtitle,
              style: AppTypography.body.copyWith(color: palette.textMuted)),
        ],
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard({required this.reading, required this.stability});

  final AnalyzerReading? reading;
  final ReadingStability stability;

  @override
  Widget build(BuildContext context) {
    final o2 = reading?.o2;
    final he = reading?.he ?? 0;
    final name = (o2 != null && o2.isFinite && he.isFinite)
        ? gasMixNameDecimal(o2, he)
        : '—';
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardLabel('Mix'),
                const SizedBox(height: Spacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    key: const ValueKey('analyzer-mix'),
                    style: AppTypography.display.copyWith(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          StabilityPill(stability: stability),
        ],
      ),
    );
  }
}

/// NO DATA / SETTLING / STABLE / SENSOR ERROR.
class StabilityPill extends StatelessWidget {
  const StabilityPill({super.key, required this.stability});

  final ReadingStability stability;

  static String labelFor(ReadingStability s) => switch (s) {
        ReadingStability.noData => 'NO DATA',
        ReadingStability.settling => 'SETTLING',
        ReadingStability.stable => 'STABLE',
        ReadingStability.sensorError => 'SENSOR ERROR',
      };

  @override
  Widget build(BuildContext context) {
    final color = switch (stability) {
      ReadingStability.noData => context.palette.textMuted,
      ReadingStability.settling => SafetyColors.warning,
      ReadingStability.stable => SafetyColors.success,
      ReadingStability.sensorError => SafetyColors.danger,
    };
    final icon = switch (stability) {
      ReadingStability.noData => Icons.remove,
      ReadingStability.settling => Icons.radio_button_unchecked,
      ReadingStability.stable => Icons.circle,
      ReadingStability.sensorError => Icons.error_outline,
    };
    return Container(
      key: const ValueKey('analyzer-pill'),
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: Spacing.sm),
          Text(
            labelFor(stability),
            style: AppTypography.label.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningCard extends StatelessWidget {
  const _PlanningCard({required this.reading, required this.settings});

  final AnalyzerReading? reading;
  final SettingsNotifier settings;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final f = _fractions(reading);
    final rows = <Widget>[];

    for (final p in settings.analyzerModPpo2s) {
      final isDil = (p - kAnalyzerCcrDiluentPpo2).abs() < 1e-9;
      String value = '–';
      if (f != null) {
        final m = modMeters(f.fo2, p);
        // Floored, never rounded up: the label floors too (with the same
        // helper), and a MOD that is too deep is the unsafe direction.
        value = m.isFinite && m > 0 ? '${floorDepthTolerant(m)} m' : 'n/a';
      }
      rows.add(_KvRow(
        key: ValueKey('analyzer-mod-${_fmtPpo2(p)}'),
        label: 'MOD @ ppO₂ ${_fmtPpo2(p)}',
        tag: isDil ? 'CCR dil' : null,
        value: value,
      ));
    }

    final refPpo2 = _fmtPpo2(kAnalyzerReferencePpo2);
    final refMod = f == null ? null : modMeters(f.fo2, kAnalyzerReferencePpo2);
    final refUsable = refMod != null && refMod.isFinite && refMod > 0;

    rows.add(_KvRow(
      key: const ValueKey('analyzer-end'),
      label: 'END @ MOD $refPpo2',
      value: refUsable
          ? '${endMeters(
              depthMeters: refMod,
              o2Fraction: f!.fo2,
              heFraction: f.fhe,
              countsOxygen: settings.endCountsOxygen,
            ).toStringAsFixed(0)} m'
          : '–',
    ));

    String minDepth = '–';
    if (f != null) {
      final d = minDepthMeters(f.fo2);
      minDepth = d <= 0 ? 'surface' : '${d.toStringAsFixed(0)} m';
    }
    rows.add(_KvRow(
      key: const ValueKey('analyzer-min-depth'),
      label: 'Min. depth (ppO₂ ${_fmtPpo2(kMinBreathablePpo2)})',
      value: minDepth,
    ));

    String density = '–';
    Color? densityColor;
    if (refUsable) {
      final ambientBar =
          kStandardAtmosphericPressureMbar / 1000.0 + refMod / 10.0;
      final d = mixDensityAt1Atm(f!.fo2, f.fhe) * ambientBar;
      density = '${d.toStringAsFixed(1)} g/L';
      densityColor = switch (densityBand(d)) {
        DensityBand.green => SafetyColors.bandSafe,
        DensityBand.orange => SafetyColors.bandCaution,
        DensityBand.red => SafetyColors.bandOver,
      };
    }
    rows.add(_KvRow(
      key: const ValueKey('analyzer-density'),
      label: 'Gas density @ MOD $refPpo2',
      value: density,
      valueColor: densityColor,
    ));

    final t = reading?.tempC;
    rows.add(_KvRow(
      key: const ValueKey('analyzer-temp'),
      label: 'Gas temperature',
      value: t != null && t.isFinite ? '${t.toStringAsFixed(1)} °C' : '–',
    ));
    final b = reading?.baroHpa;
    rows.add(_KvRow(
      key: const ValueKey('analyzer-baro'),
      label: 'Ambient pressure',
      value: b != null && b.isFinite ? '${b.toStringAsFixed(0)} hPa' : '–',
    ));

    final endNote = settings.endCountsOxygen
        ? 'END counts O₂ and N₂ as narcotic.'
        : 'END counts only N₂ as narcotic.';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardLabel('Planning'),
          const SizedBox(height: Spacing.sm),
          ...rows,
          const SizedBox(height: Spacing.md),
          Text(
            'Seawater, 10 m/bar. $endNote Orientation only — always plan '
            'with your own tools.',
            style: AppTypography.caption.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({
    super.key,
    required this.label,
    required this.value,
    this.tag,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? tag;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs + 1),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label),
                if (tag != null)
                  TextSpan(
                    text: '  $tag',
                    style: TextStyle(
                      color: palette.accentPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ]),
              style: AppTypography.body.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            value,
            style: AppTypography.readoutMd.copyWith(
              color: valueColor ?? palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.controller});

  final AnalyzerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _CardLabel('Last 2 minutes')),
              legend('O₂', palette.accentPrimary),
              const SizedBox(width: Spacing.lg),
              legend('He', DataColors.helium),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          AnalyzerLiveChart(
            points: controller.history,
            nowSeconds: controller.historyNowSeconds,
            windowSeconds: controller.historyWindow.inSeconds.toDouble(),
            o2Color: palette.accentPrimary,
            heColor: DataColors.helium,
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.controller});

  final AnalyzerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (text, color) = switch (controller.status) {
      AnalyzerConnectionStatus.disconnected =>
        ('Not connected', palette.textMuted),
      AnalyzerConnectionStatus.connecting =>
        ('Connecting…', SafetyColors.warning),
      AnalyzerConnectionStatus.connected => (
          'Connected · ${controller.transport?.name ?? ''}',
          SafetyColors.success
        ),
      AnalyzerConnectionStatus.error => ('Error', SafetyColors.danger),
    };
    return Row(
      key: const ValueKey('analyzer-status'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Spacing.sm),
        Text(text,
            style: AppTypography.body.copyWith(color: palette.textSecondary)),
      ],
    );
  }
}
