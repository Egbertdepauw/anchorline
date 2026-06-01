import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';
import '../../data/models/dive_attachment.dart';
import '../../shearwater/parser/parsed_dive.dart' show TankUsage;
import '../../data/sample_codec/active_per_mix.dart';
import '../../data/sample_codec/dive_stats.dart';
import '../../shearwater/parser/hardware.dart';
import '../../sync/attachments/attachment_downloader.dart';
import '../notifiers/dive_annotations_notifier.dart';
import '../notifiers/dive_attachments_notifier.dart';
import '../notifiers/dive_detail_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../util/attachment_picker.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import '../util/tank_labels.dart';
import '../widgets/crosshair_overlay.dart';
import '../widgets/crosshair_tooltip.dart';
import '../widgets/dive_annotations_section.dart';
import '../widgets/dive_bailout_carry_section.dart';
import '../widgets/dive_cylinders_section.dart';
import '../widgets/dive_information_section.dart';
import '../widgets/dive_media_tab.dart';
import '../widgets/dive_equipment_section.dart';
import '../widgets/cell_data_chart.dart';
import '../widgets/profile_chart.dart';
import 'fullscreen_chart_screen.dart';
import '../widgets/site_mini_map.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'sites_map_screen.dart';
import '../widgets/star_rating.dart';
import '../widgets/tissue_saturation_heatmap.dart';
import '../widgets/trace_segmented_bar.dart';
import '../components/stat_tile.dart';
import '../theme/tokens.dart';
import '../../analysis/gas_density.dart';
import '../../analysis/end.dart';
import '../../analysis/deco/replay_engine.dart';
import '../../analysis/deco/replay_result.dart';
import '../../analysis/deco/zhl16c.dart' show SampleStream;
import '../../analysis/bailout/bailout_planner.dart';
import '../../analysis/bailout/tank_recommender.dart';
import '../../analysis/bailout/team_bailout.dart' show distributeForTeam;
import '../widgets/bailout_section.dart';

class DiveDetailScreen extends StatefulWidget {
  final Dive dive;
  final DiveDao dao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final SettingsNotifier settingsNotifier;

  /// Navigation callbacks for the prev/next AppBar buttons. `null` means
  /// "no sibling in that direction"; the button is rendered disabled.
  /// Wired by [DiveDetailPager] when this screen is part of a browsable
  /// list. Solo presentations (single-shot navigation, tests) leave both
  /// null and the buttons stay disabled.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// Externally-owned annotations notifier. When provided, this widget
  /// uses it as-is and does NOT create or dispose a notifier — the
  /// parent owns the lifecycle, so dirty state survives PageView page
  /// rebuilds. Solo callers leave it null and a per-screen notifier is
  /// created internally.
  ///
  /// When [annotationsNotifier] is provided, the inner unsaved-changes
  /// PopScope is also suppressed; the pager wraps everything with its
  /// own scope-wide guard that knows about every cached page's dirty
  /// state, not just the visible one.
  final DiveAnnotationsNotifier? annotationsNotifier;

  /// Externally-owned attachments notifier. When provided, the
  /// attachments section is rendered; when null (solo callers like
  /// the cell-detail screen), the section is hidden. Lifecycle is
  /// owned by the parent so uploads in flight survive page swipes.
  final DiveAttachmentsNotifier? attachmentsNotifier;

  /// Wired by the pager so file-attachment "Open" actions can fetch
  /// bytes through the cache before sharing. Null when the attachments
  /// section is not rendered.
  final AttachmentDownloader? attachmentDownloader;

  /// CCRLog-internal sequence number used for the `#N` label. See
  /// [DiveListNotifier.sequenceByDiveId]. Falls back to the DC's own
  /// dive number when null (solo callers / tests).
  final int? sequenceNumber;

  /// When true, the screen renders only the per-tab body (no Scaffold,
  /// AppBar, DefaultTabController, or TabBar) — the parent is expected
  /// to provide them. [DiveDetailPager] uses this so its top chrome stays
  /// fixed while only the body slides between dives. Default false; solo
  /// callers (cell_detail_screen, tests) get a full self-contained screen.
  final bool wrappedInPager;

  /// Pre-built (synthetic) sample set to use instead of loading from the
  /// database. When non-null, [DiveDetailNotifier] will use this directly
  /// and skip the DAO lookup. Used by merged-dive presentations where the
  /// combined [SampleSet] is built in memory and has no database row.
  final SampleSet? preloadedSamples;

  /// Real dive id to load/save annotations against. For a merged dive, [dive]
  /// is synthetic (its id is a group id), so this points at the earliest
  /// member's real dive id — edits persist there and a pre-merge annotation on
  /// that dive shows through. Null for solo dives → falls back to [dive].id.
  final String? annotationsDiveId;

  const DiveDetailScreen({
    super.key,
    required this.dive,
    required this.dao,
    required this.annotationsDao,
    required this.equipmentDao,
    required this.settingsNotifier,
    this.onPrev,
    this.onNext,
    this.annotationsNotifier,
    this.attachmentsNotifier,
    this.attachmentDownloader,
    this.sequenceNumber,
    this.wrappedInPager = false,
    this.preloadedSamples,
    this.annotationsDiveId,
  });
  @override
  State<DiveDetailScreen> createState() => _DiveDetailScreenState();
}

class _DiveDetailScreenState extends State<DiveDetailScreen> {
  late final DiveDetailNotifier _notifier;
  late final DiveAnnotationsNotifier _annotationsNotifier;
  late final bool _ownsAnnotations;
  final _decoEngine = DecoReplayEngine();

  /// Opens the dive profile in a dedicated fullscreen route where it can
  /// be pinched / dragged to zoom + pan freely — the inline chart stays
  /// a static preview because its TabBarView host makes those gestures
  /// ambiguous (see #24).
  void _openFullscreenChart({
    required SampleSet samples,
    required Set<TraceType> visibleTraces,
    required List<DiveGasMix>? gasMixes,
    required bool useSpeedColored,
    required DecoReplayResult? decoReplay,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullscreenChartScreen(
        samples: samples,
        visibleTraces: visibleTraces,
        title:
            'Dive #${widget.sequenceNumber ?? widget.dive.dcDiveNumber} profile',
        cellsBySlot: _notifier.activeCells,
        tanks: _decodeTanks(),
        mappedCylinders: _notifier.mappedCylinders,
        gasMixes: gasMixes,
        useSpeedColoredGraph: useSpeedColored,
        endCountsOxygen: widget.settingsNotifier.endCountsOxygen,
        isCcr: const {0, 4, 5}.contains(widget.dive.diveMode),
        decoReplay: decoReplay,
      ),
    ));
  }

  /// The surface atmospheric pressure (in bar) the dive computer recorded
  /// for this dive. Feeds every replay-engine call so SurfGF / GF99 match
  /// what Subsurface computes for the same data — without this the engine
  /// falls back to a hard-coded 1.013 bar and the resulting GF inflates
  /// by a few points on weather days, more at altitude. If the column is
  /// missing or implausibly low (legacy data, parser miss) we revert to
  /// the 1013-mbar default rather than swing the result wildly.
  double get _surfacePressureBar {
    final mbar = widget.dive.atmosphericPressureMbar;
    if (mbar < 500) return 1.013;
    return mbar / 1000.0;
  }

  @override
  void initState() {
    super.initState();
    _notifier = DiveDetailNotifier(
      dive: widget.dive,
      dao: widget.dao,
      equipmentDao: widget.equipmentDao,
      preloadedSamples: widget.preloadedSamples,
    );
    _notifier.addListener(_onChanged);
    _notifier.loadSamples();

    _ownsAnnotations = widget.annotationsNotifier == null;
    if (_ownsAnnotations) {
      _annotationsNotifier = DiveAnnotationsNotifier(
        widget.annotationsDao,
        widget.equipmentDao,
      );
      // For a merged dive, [dive].id is a synthetic group id (no annotation
      // row of its own). Anchor annotations to the earliest member's real
      // dive id so edits persist and a pre-merge annotation on that dive
      // shows through. Solo dives leave annotationsDiveId null → dive.id.
      _annotationsNotifier.load(widget.annotationsDiveId ?? widget.dive.id);
    } else {
      _annotationsNotifier = widget.annotationsNotifier!;
    }
    _annotationsNotifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    _annotationsNotifier.removeListener(_onChanged);
    if (_ownsAnnotations) {
      _annotationsNotifier.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dive = widget.dive;
    final theme = Theme.of(context);

    if (widget.wrappedInPager) {
      // Parent owns Scaffold/AppBar/DefaultTabController/TabBar/PopScope
      // so the top chrome stays fixed while only the body slides between
      // dives.
      return _buildPagerBody(theme);
    }

    // In pager mode the parent owns the unsaved-changes guard — it sees
    // every cached page's dirty state, not just the visible one. Solo
    // callers still get the per-screen PopScope.
    final guardPop = _ownsAnnotations;
    return PopScope(
      canPop: !guardPop || !_annotationsNotifier.dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !guardPop) return;
        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
                'You have unsaved annotation edits. Discard them and leave?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (shouldDiscard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Builder(builder: (context) {
          final siteName = _annotationsNotifier.siteName;
          final subtitle = [
            if (siteName != null && siteName.isNotEmpty) siteName,
            formatDateTime(dive.startTime),
          ].join(' · ');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dive #${widget.sequenceNumber ?? dive.dcDiveNumber}',
                style: AppTypography.headline.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ],
          );
        }),
        actions: [
          IconButton(
            tooltip: 'Previous dive',
            icon: const Icon(Icons.chevron_left),
            onPressed: widget.onPrev,
          ),
          IconButton(
            tooltip: 'Next dive',
            icon: const Icon(Icons.chevron_right),
            onPressed: widget.onNext,
          ),
          AnimatedBuilder(
            animation: _annotationsNotifier,
            builder: (context, _) {
              final dirty = _annotationsNotifier.dirty;
              return IconButton(
                tooltip: dirty ? 'Save (unsaved changes)' : 'Save',
                icon: Icon(
                  dirty ? Icons.save : Icons.save_outlined,
                  color: dirty
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: dirty
                    ? () async {
                        await _annotationsNotifier.save();
                      }
                    : null,
              );
            },
          ),
        ],
      ),
      body: _notifier.loading && _notifier.samples == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  Builder(builder: (context) {
                    // Hide tab labels on narrow viewports — icons alone keep
                    // the bar from overflowing on phones in portrait.
                    final compact = MediaQuery.of(context).size.width < 480;
                    Widget tab(IconData icon, String label) => Tab(
                          icon: Icon(icon),
                          text: compact ? null : label,
                        );
                    return TabBar(
                      tabs: [
                        tab(Icons.info_outline, 'Details'),
                        tab(Icons.thermostat_outlined, 'Information'),
                        tab(Icons.photo_library_outlined, 'Media'),
                        tab(Icons.scuba_diving_outlined, 'Equipment'),
                      ],
                    );
                  }),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildDetailsTab(theme),
                        _buildInformationTab(),
                        _buildMediaTab(),
                        _buildEquipmentTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  /// Body used when the screen is wrapped by [DiveDetailPager]. The
  /// pager provides Scaffold + AppBar + DefaultTabController + TabBar
  /// above us; we return just the per-tab content so only this slides
  /// between dives.
  Widget _buildPagerBody(ThemeData theme) {
    if (_notifier.loading && _notifier.samples == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return TabBarView(
      children: [
        _buildDetailsTab(theme),
        _buildInformationTab(),
        _buildMediaTab(),
        _buildEquipmentTab(),
      ],
    );
  }

  /// Tab 1 — every per-dive thing except cylinders/gasses, which moved
  /// to the Equipment tab. Returns a SingleChildScrollView so the body
  /// scrolls independently of the tab bar above it.
  Widget _buildDetailsTab(ThemeData theme) {
    final dive = widget.dive;
    final modeColor = diveModeColor(dive.diveMode);
    final modelName = dive.dcModel < ShearwaterModel.values.length
        ? ShearwaterModel.values[dive.dcModel].name
        : 'Unknown';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                  // Header
                  Builder(builder: (context) {
                    final siteName = _annotationsNotifier.siteName;
                    final hasSite =
                        siteName != null && siteName.isNotEmpty;
                    final lat = _annotationsNotifier.siteLatitude;
                    final lon = _annotationsNotifier.siteLongitude;
                    final hasCoords = lat != null && lon != null;
                    return Container(
                      color: const Color(0xFF152238),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasCoords) ...[
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => SitesMapScreen(
                                    dao: widget.annotationsDao,
                                    currentLat: lat,
                                    currentLon: lon,
                                    settingsNotifier: widget.settingsNotifier,
                                  ),
                                )),
                                child: IgnorePointer(
                                  child: SiteMiniMap(
                                      lat: lat, lon: lon, size: 72),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Text(diveModeLabel(dive.diveMode),
                                        style: TextStyle(
                                            color: modeColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 6),
                                    Text(
                                        '#${widget.sequenceNumber ?? dive.dcDiveNumber}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16)),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(modelName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: theme
                                                  .colorScheme.onSurface
                                                  .withValues(alpha: 0.4),
                                              fontSize: 12)),
                                    ),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(formatDateTime(dive.startTime),
                                      style: TextStyle(
                                          color: theme
                                              .colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 12)),
                                  if (hasSite) ...[
                                    const SizedBox(height: 2),
                                    Text(siteName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: theme
                                                .colorScheme.onSurface
                                                .withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                  if (_annotationsNotifier
                                      .buddies.isNotEmpty)
                                    Text(
                                      _annotationsNotifier.buddies.join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 11),
                                    ),
                                ])),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(formatDepth(dive.maxDepthMm),
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: modeColor)),
                                  Text(
                                      '${formatDuration(dive.durationSeconds)} ${formatGf(dive.gfLow, dive.gfHigh)}',
                                      style: TextStyle(
                                          color: theme
                                              .colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontSize: 11)),
                                  StarRating(
                                    value: _annotationsNotifier.rating,
                                    readOnly: true,
                                    size: 12,
                                  ),
                                ]),
                          ]),
                    );
                  }),

                  // Profile chart
                  if (_notifier.samples != null) ...[
                    ListenableBuilder(
                      listenable: widget.settingsNotifier,
                      builder: (context, _) {
                        final visibleTraces =
                            widget.settingsNotifier.visibleTraces;
                        final useSpeedColored =
                            widget.settingsNotifier.useSpeedColoredGraph;
                        // In PHONE landscape the user is here to study the
                        // graph — let the chart fill most of the viewport
                        // height instead of being clipped to 250 dp.
                        // 250 dp keeps room for the cards below. Guard on
                        // phone: desktop/tablet windows also report
                        // Orientation.landscape (width > height), and there the
                        // fill-height branch made the chart absurdly tall and
                        // pushed the trace toggles + cards off-screen.
                        final mq = MediaQuery.of(context);
                        final isMobile =
                            defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.android;
                        final isPhone =
                            isMobile && mq.size.shortestSide < 600;
                        final isPhoneLandscape = isPhone &&
                            mq.orientation == Orientation.landscape;
                        final chartHeight = isPhoneLandscape
                            ? (mq.size.height - 160).clamp(240.0, 600.0)
                            : 250.0;
                        return Column(
                          children: [
                            SizedBox(
                              height: chartHeight,
                              child: LayoutBuilder(
                                  builder: (context, constraints) {
                                final samples = _notifier.samples!;
                                final needsReplay =
                                    visibleTraces.contains(TraceType.gf99) ||
                                        visibleTraces
                                            .contains(TraceType.ceiling);
                                final gasMixes = _decodeGasMixes();
                                DecoReplayResult? decoReplay;
                                if (needsReplay) {
                                  final algo = _annotationsNotifier
                                              .displayDecoAlgorithm ==
                                          'vpmb'
                                      ? DecoAlgorithm.vpmb
                                      : DecoAlgorithm.zhl16c;
                                  decoReplay = _decoEngine.replay(
                                    diveId: widget.dive.id,
                                    samples: _SampleSetAdapter(samples),
                                    gasMixes: gasMixes,
                                    algorithm: algo,
                                    vpmbConservatism: widget
                                        .settingsNotifier.vpmbConservatism,
                                    gfLow: widget.dive.gfLow,
                                    gfHigh: widget.dive.gfHigh,
                                    surfacePressureBar: _surfacePressureBar,
                                  );
                                }
                                return CrosshairOverlay(
                                  sampleCount: samples.sampleCount,
                                  chartLeftPad: 40,
                                  chartRightPad: 44,
                                  onIndexChanged: _notifier.setCrosshairIndex,
                                  onRelease: _notifier.clearCrosshair,
                                  child: Stack(children: [
                                    ProfileChart(
                                        samples: samples,
                                        visibleTraces: visibleTraces,
                                        crosshairIndex:
                                            _notifier.crosshairIndex,
                                        cellsBySlot: _notifier.activeCells,
                                        tanks: _decodeTanks(),
                                        mappedCylinders:
                                            _notifier.mappedCylinders,
                                        gasMixes: gasMixes,
                                        useSpeedColoredGraph: useSpeedColored,
                                        endCountsOxygen: widget
                                            .settingsNotifier.endCountsOxygen,
                                        isCcr: const {0, 4, 5}
                                            .contains(widget.dive.diveMode),
                                        decoReplay: decoReplay),
                                    // Fullscreen affordance — zoom/pan
                                    // live in the dedicated fullscreen
                                    // route (no TabBarView gesture
                                    // conflict). See #24.
                                    Positioned(
                                      top: 2,
                                      right: 48,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: IconButton(
                                          tooltip: 'Fullscreen',
                                          visualDensity: VisualDensity.compact,
                                          iconSize: 18,
                                          icon: const Icon(Icons.fullscreen,
                                              color: Colors.white70),
                                          onPressed: () =>
                                              _openFullscreenChart(
                                            samples: samples,
                                            visibleTraces: visibleTraces,
                                            gasMixes: gasMixes,
                                            useSpeedColored: useSpeedColored,
                                            decoReplay: decoReplay,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_notifier.crosshairIndex != null)
                                      CrosshairTooltip(
                                        samples: _notifier.samples!,
                                        sampleIndex: _notifier.crosshairIndex!,
                                        visibleTraces: visibleTraces,
                                        chartX: 40 +
                                            (_notifier.crosshairIndex! /
                                                    (_notifier.samples!
                                                            .sampleCount -
                                                        1)) *
                                                (constraints.maxWidth - 84),
                                        chartWidth: constraints.maxWidth,
                                        cellsBySlot: _notifier.activeCells,
                                        tanks: _decodeTanks(),
                                        mappedCylinders:
                                            _notifier.mappedCylinders,
                                        gasMixes: _decodeGasMixes(),
                                      ),
                                  ]),
                                );
                              }),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: Row(
                                children: [
                                  Text(
                                    'Algorithm:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedBuilder(
                                    animation: _annotationsNotifier,
                                    builder: (context, _) {
                                      return DropdownButton<String>(
                                        value: _annotationsNotifier
                                            .displayDecoAlgorithm,
                                        isDense: true,
                                        underline: const SizedBox.shrink(),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'zhl16c',
                                              child: Text('ZHL-16C')),
                                          DropdownMenuItem(
                                              value: 'vpmb',
                                              child: Text('VPM-B')),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            _annotationsNotifier
                                                .setDisplayDecoAlgorithm(v);
                                          }
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            TraceSegmentedBar(
                                visibleTraces: visibleTraces,
                                onToggle: widget.settingsNotifier.toggleTrace),
                          ],
                        );
                      },
                    ),
                    _buildStatsRow(theme),
                    _buildCellDataGraphSection(),
                    _buildTissueHeatmapSection(),
                    _buildAnnotationsSection(),
                    _buildBailoutSection(),
                  ],
        ],
      ),
    );
  }

  /// Tab 2 — Subsurface-style structured conditions + environment.
  /// Weights live on the Equipment tab. Persists via the same notifier
  /// as the Details tab (single save button at the screen level).
  Widget _buildInformationTab() {
    final samples = _notifier.samples;
    double? avgWaterTemp;
    if (samples != null && samples.sampleCount > 0) {
      final stats =
          minAvgMax(samples.temperatureCelsius, samples.sampleCount);
      avgWaterTemp = stats?.avg;
    }
    return DiveInformationSection(
      notifier: _annotationsNotifier,
      dive: widget.dive,
      defaultWaterTempC: avgWaterTemp,
    );
  }

  /// Tab 3 — media (files + links). For the Phase-3 polish this is a
  /// dedicated tab; the actual grid + image viewer enhancements arrive
  /// via the parallel media-tab agent. For now we slot the existing
  /// section unchanged so the tabs ship working.
  Widget _buildMediaTab() {
    if (widget.attachmentsNotifier == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Attachments unavailable on this screen.'),
        ),
      );
    }
    return SingleChildScrollView(
      child: DiveMediaTab(
        notifier: widget.attachmentsNotifier!,
        pickFiles: pickAttachments,
        onOpen: _openAttachment,
        loadFile:
            widget.attachmentDownloader != null ? _loadAttachmentFile : null,
      ),
    );
  }

  /// Tab 3 — equipment used: gas-mix → cylinder mapping (relocated
  /// from the annotations section) + the five Phase-3 freeform fields
  /// (suit / undersuit / weight system / DPV / camera). The fields
  /// themselves are filled in by the parallel equipment-tab agent.
  Widget _buildEquipmentTab() {
    final samples = _notifier.samples;
    final gasMixes = _decodeGasMixes();
    final activeByMix = samples == null
        ? <int, int>{}
        : activeSecondsPerMix(
            gasMixIndexes: samples.gasMixIndex,
            sampleCount: samples.sampleCount,
            sampleIntervalMs: samples.sampleIntervalMs,
          );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiveCylindersSection(
            notifier: _annotationsNotifier,
            gasMixes: gasMixes,
            activeSecondsByMix: activeByMix,
            equipmentDao: widget.equipmentDao,
          ),
          DiveBailoutCarrySection(
            diveId: widget.dive.id,
            dao: widget.equipmentDao,
          ),
          DiveEquipmentSection(
            notifier: _annotationsNotifier,
            annotationsDao: widget.annotationsDao,
          ),
        ],
      ),
    );
  }

  /// Loads the local file for an attachment via [AttachmentDownloader].
  /// Returns null when the downloader isn't wired (solo callers).
  Future<File> _loadAttachmentFile(String storageKey) async {
    final downloader = widget.attachmentDownloader;
    if (downloader == null) {
      throw StateError('attachmentDownloader not wired');
    }
    return downloader.fetch(storageKey: storageKey);
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  /// Resolves an attachment open action.
  ///
  /// * Image files → in-app full-screen viewer.
  /// * PDF files → in-app PDF viewer (same shape as the image viewer).
  ///   Native PDFKit on iOS/macOS, PdfRenderer on Android. Keeps the
  ///   workflow consistent with images instead of dumping the user
  ///   into a share sheet.
  /// * Other files on desktop → `launchUrl(Uri.file(...))` so the OS
  ///   opens it in the user's default app for that MIME.
  /// * Other files on mobile → `Share.shareXFiles` (iOS sandbox makes
  ///   `file://` URLs basically useless for cross-app open; the share
  ///   sheet is the canonical "open in" path on iOS, until/unless we
  ///   add QuickLook integration for DOC/XLSX previews later).
  /// * Links → `launchUrl` with externalApplication.
  ///
  /// Failures surface as a SnackBar; a single open failure shouldn't
  /// tear down the screen.
  Future<void> _openAttachment(DiveAttachment attachment) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // share_plus on iOS rejects a null/zero `sharePositionOrigin`;
    // we pass the screen's bounding rect as a sensible default anchor.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      switch (attachment) {
        case FileAttachment file:
          final cached = await _loadAttachmentFile(file.storageKey);
          if (!mounted) return;
          final mime = file.mimeType.toLowerCase();
          final isImage = mime.startsWith('image/');
          final isPdf = mime == 'application/pdf';
          final viewerTitle = file.title?.trim().isNotEmpty == true
              ? file.title!.trim()
              : (file.originalFilename ?? (isPdf ? 'PDF' : 'Image'));
          // Same delete callback shape for both viewers — pop first so
          // the user is back on the dive screen immediately, then let
          // the soft-delete settle. The grid re-renders via the
          // notifier's listener once the DAO completes.
          Future<void> Function() onViewerDelete(BuildContext viewerCtx) =>
              () async {
                Navigator.of(viewerCtx).pop();
                await widget.attachmentsNotifier?.softDelete(file.id);
              };
          if (isImage) {
            await navigator.push(MaterialPageRoute(
              builder: (viewerCtx) => ImageViewerScreen(
                file: cached,
                title: viewerTitle,
                attachment: file,
                onDelete: () => onViewerDelete(viewerCtx)(),
              ),
            ));
          } else if (isPdf) {
            await navigator.push(MaterialPageRoute(
              builder: (viewerCtx) => PdfViewerScreen(
                file: cached,
                title: viewerTitle,
                attachment: file,
                onDelete: () => onViewerDelete(viewerCtx)(),
              ),
            ));
          } else if (_isDesktop) {
            await launchUrl(Uri.file(cached.path));
          } else {
            await Share.shareXFiles(
              [XFile(cached.path)],
              sharePositionOrigin: origin,
            );
          }
        case LinkAttachment link:
          final uri = Uri.parse(link.url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open: $e')),
      );
    }
  }

  Widget _buildCellDataGraphSection() {
    final samples = _notifier.samples;
    return ListenableBuilder(
      listenable: widget.settingsNotifier,
      builder: (context, _) {
        final expanded = widget.settingsNotifier.cellDataGraphExpanded;
        return Column(
          children: [
            InkWell(
              onTap: () => widget.settingsNotifier
                  .setCellDataGraphExpanded(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      'Cell data',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded && samples != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CellDataChart(
                  samples: samples,
                  cellLabels: {
                    for (final e in _notifier.activeCells.entries)
                      if (e.value.label != null &&
                          e.value.label!.isNotEmpty)
                        e.key: e.value.label!,
                  },
                  height: 220,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTissueHeatmapSection() {
    final samples = _notifier.samples;
    return ListenableBuilder(
      listenable: widget.settingsNotifier,
      builder: (context, _) {
        final expanded = widget.settingsNotifier.tissueHeatmapExpanded;
        final algoLabel =
            _annotationsNotifier.displayDecoAlgorithm == 'vpmb'
                ? 'VPM-B'
                : 'ZHL-16C';
        return Column(
          children: [
            InkWell(
              onTap: () => widget.settingsNotifier
                  .setTissueHeatmapExpanded(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      'Tissue saturation [$algoLabel]',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded && samples != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TissueSaturationHeatmap(
                  replay: _decoEngine.replay(
                    diveId: widget.dive.id,
                    samples: _SampleSetAdapter(samples),
                    gasMixes: _decodeGasMixes(),
                    algorithm:
                        _annotationsNotifier.displayDecoAlgorithm == 'vpmb'
                            ? DecoAlgorithm.vpmb
                            : DecoAlgorithm.zhl16c,
                    vpmbConservatism:
                        widget.settingsNotifier.vpmbConservatism,
                    gfLow: widget.dive.gfLow,
                    gfHigh: widget.dive.gfHigh,
                    surfacePressureBar: _surfacePressureBar,
                  ),
                  totalDuration:
                      Duration(seconds: widget.dive.durationSeconds),
                  height: 320,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBailoutSection() {
    // Subscribe to dive_bailout_carry changes so adding/editing a carry row
    // re-plans automatically. Combined with settingsNotifier for SAC /
    // ascent-rate / GUE-config changes.
    return StreamBuilder<void>(
      stream: widget.equipmentDao.watchDiveBailoutCarry(),
      builder: (context, _) => FutureBuilder<
          List<({DiveBailoutCarryData carry, Cylinder cylinder})>>(
        future:
            widget.equipmentDao.listBailoutCarryWithCylinders(widget.dive.id),
        builder: (context, snap) {
          final carry = snap.data ?? const [];
          return _bailoutSectionBody(carry);
        },
      ),
    );
  }

  Widget _bailoutSectionBody(
      List<({DiveBailoutCarryData carry, Cylinder cylinder})> carry) {
    return ListenableBuilder(
      listenable: widget.settingsNotifier,
      builder: (context, _) {
        final samples = _notifier.samples;
        if (samples == null) return const SizedBox.shrink();

        final gasMixes = _decodeGasMixes();

        // Bailout trigger = the LATEST sample within 5 m of max depth.
        // This captures end-of-bottom-time on both square and multi-level
        // profiles: the diver can't pass through the "within 5 m of max"
        // band on ascent without actually having been there, so the band
        // always lies inside bottom time. A wider band (e.g. ≥ 50 % of
        // max) gets fooled by a deep ascent — the loop locks onto the
        // last sample mid-ascent, well above bottom, and the planner
        // then under-counts bottom-mix gas by 5×. The bailout planner
        // walks the OC ascent from this point; tissue state at the
        // trigger comes from the replay engine (triggerSampleIdx capture).
        double maxDepth = 0;
        for (var i = 0; i < samples.depthMeters.length; i++) {
          if (samples.depthMeters[i] > maxDepth) {
            maxDepth = samples.depthMeters[i];
          }
        }
        final substantialDepth = maxDepth - 5.0;
        var triggerIdx = 0;
        for (var i = samples.depthMeters.length - 1; i >= 0; i--) {
          if (samples.depthMeters[i] >= substantialDepth) {
            triggerIdx = i;
            break;
          }
        }
        final triggerDepth = samples.depthMeters[triggerIdx].toDouble();
        final bottomTimeBeforeTrigger = Duration(
          milliseconds: triggerIdx * samples.sampleIntervalMs,
        );

        // Recorded diluent = the gas actually breathed on the CCR loop at
        // the trigger sample (deepest moment of the dive). Petrels log all
        // configured gases; a diver may have several diluents enabled from
        // past tech dives even though only one was active here. Picking the
        // first-flagged isDiluent gas — the previous approach — could grab
        // 21/35 from a stale configuration even when this dive ran on 21/0
        // air. The active-gas index at trigger always identifies the
        // diluent that was on the loop at depth.
        DiveGasMix? recordedDiluent;
        if (triggerIdx < samples.gasMixIndex.length) {
          final activeIdx = samples.gasMixIndex[triggerIdx];
          if (activeIdx >= 0 && activeIdx < gasMixes.length) {
            final active = gasMixes[activeIdx];
            if (active.isDiluent) recordedDiluent = active;
          }
        }
        // Fallback: if the active gas isn't flagged as diluent (mis-flagged
        // import, or an OC dive in CC-mode logging), fall back to the
        // first-flagged diluent in the list.
        if (recordedDiluent == null) {
          for (final m in gasMixes) {
            if (m.isDiluent) {
              recordedDiluent = m;
              break;
            }
          }
        }

        final replay = _decoEngine.replay(
          diveId: widget.dive.id,
          samples: _SampleSetAdapter(samples),
          gasMixes: gasMixes,
          algorithm: _annotationsNotifier.displayDecoAlgorithm == 'vpmb'
              ? DecoAlgorithm.vpmb
              : DecoAlgorithm.zhl16c,
          vpmbConservatism: widget.settingsNotifier.vpmbConservatism,
          gfLow: widget.dive.gfLow,
          gfHigh: widget.dive.gfHigh,
          triggerSampleIdx: triggerIdx,
          surfacePressureBar: _surfacePressureBar,
        );
        // Trigger-sample tissue state if the engine captured it; fall back
        // to peak-depth state for safety.
        final tissueN2Bar = replay.triggerN2Bar.isNotEmpty
            ? replay.triggerN2Bar
            : replay.peakDepthN2Bar;
        final tissueHeBar = replay.triggerHeBar.isNotEmpty
            ? replay.triggerHeBar
            : replay.peakDepthHeBar;

        // Tank catalogue — always-present aluminium stages plus the
        // user-toggleable European steel tanks.
        final tankCatalogue = [
          kAl40,
          kAl50,
          kAl80,
          if (widget.settingsNotifier.tank68L300Available) kTank68L300,
          if (widget.settingsNotifier.tank12L300Available) kTank12L300,
        ];

        // Build Scenario A inputs from dive_bailout_carry rows. Empty carry
        // list → planBailout treats it as Scenario B (GUE standards).
        final userBailoutTanks = <DiveGasMix>[];
        final userTankVolumesL = <DiveGasMix, double>{};
        for (final entry in carry) {
          final mix = _parseBailoutGasMix(entry.carry.gasMix);
          if (mix == null) continue;
          userBailoutTanks.add(mix);
          final fillBar = entry.carry.fillPressureBar ??
              entry.cylinder.workingPressureBar;
          userTankVolumesL[mix] = (userTankVolumesL[mix] ?? 0.0) +
              entry.cylinder.volumeLiters * fillBar;
        }

        final result = planBailout(
          diveId: widget.dive.id,
          // Bottom-mix selection + staging tier use TRUE max depth so the
          // mix is breathable at the deepest moment the diver actually
          // visited. The OC ascent itself starts from the (potentially
          // shallower) trigger depth — see triggerDepthMeters below.
          maxDepthMeters: maxDepth,
          triggerDepthMeters: triggerDepth,
          recordedDiluent: recordedDiluent,
          tissueN2Bar: tissueN2Bar,
          tissueHeBar: tissueHeBar,
          userBailoutTanks: userBailoutTanks,
          userTankVolumesL: userTankVolumesL,
          isGueConfig: widget.settingsNotifier.gueDiluentConfig,
          gfLow: widget.dive.gfLow ?? 30,
          gfHigh: widget.dive.gfHigh ?? 85,
          sacBottom: widget.settingsNotifier.bailoutSacBottom,
          sacDeco: widget.settingsNotifier.bailoutSacDeco,
          ascentRateFast: widget.settingsNotifier.bailoutAscentRateFast,
          ascentRateSlow: widget.settingsNotifier.bailoutAscentRateSlow,
          availableTanks: tankCatalogue,
        );

        // Team bailout = self + buddies. The Team tab is hidden when
        // teamSize == 1 (no buddies on the dive).
        final teamSize = 1 + _annotationsNotifier.buddies.length;
        final teamCarry = distributeForTeam(
          solo: result,
          teamSize: teamSize,
          availableTanks: tankCatalogue,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: BailoutSection(
            result: result,
            triggerDepthMeters: triggerDepth,
            sacBottom: widget.settingsNotifier.bailoutSacBottom,
            sacDeco: widget.settingsNotifier.bailoutSacDeco,
            isGueConfig: widget.settingsNotifier.gueDiluentConfig,
            bottomTimeBeforeTrigger: bottomTimeBeforeTrigger,
            teamCarry: teamCarry,
          ),
        );
      },
    );
  }

  Widget _buildAnnotationsSection() {
    final samples = _notifier.samples;
    if (samples == null) return const SizedBox.shrink();

    final gasMixes = _decodeGasMixes();
    final activeByMix = activeSecondsPerMix(
      gasMixIndexes: samples.gasMixIndex,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );

    return DiveAnnotationsSection(
      notifier: _annotationsNotifier,
      gasMixes: gasMixes,
      activeSecondsByMix: activeByMix,
      annotationsDao: widget.annotationsDao,
      equipmentDao: widget.equipmentDao,
      settingsNotifier: widget.settingsNotifier,
      // Phase 3: gas-mix → cylinder mapping moved to the Equipment tab
      // (see DiveCylindersSection). Showing it here would duplicate.
      showGasMixes: false,
    );
  }

  /// Decode gas mixes from the dive's JSON column.
  List<DiveGasMix> _decodeGasMixes() {
    return (jsonDecode(widget.dive.gasMixesJson) as List)
        .map((e) => DiveGasMix.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Decode tanks from the dive's JSON column. Returns `[]` when null.
  List<DiveTank> _decodeTanks() {
    final raw = widget.dive.tanksJson;
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => DiveTank.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Choose the diluent label for the GAS column. Picks the diluent with
  /// the most active time; tie-breaker is list order. Returns '—' if the
  /// dive has no diluent (OC dives).
  String _activeDiluentLabel(
      List<DiveGasMix> mixes, Map<int, int> activeSecondsByMix) {
    final diluentEntries = <MapEntry<int, DiveGasMix>>[];
    for (var i = 0; i < mixes.length; i++) {
      if (mixes[i].isDiluent) diluentEntries.add(MapEntry(i, mixes[i]));
    }
    if (diluentEntries.isEmpty) return '—';
    diluentEntries.sort((a, b) {
      final aSec = activeSecondsByMix[a.key] ?? 0;
      final bSec = activeSecondsByMix[b.key] ?? 0;
      return bSec.compareTo(aSec);
    });
    final winner = diluentEntries.first.value;
    return '${winner.oxygenPercent}/${winner.heliumPercent}';
  }

  Widget _buildStatsRow(ThemeData theme) {
    final samples = _notifier.samples!;
    final n = samples.sampleCount;
    final ppo2Stats = minAvgMax(samples.ppo2Bar, n);
    final tempStats = minAvgMax(samples.temperatureCelsius, n);
    var maxCns = 0.0;
    for (var i = 0; i < n; i++) {
      if (samples.cns[i] > maxCns) maxCns = samples.cns[i];
    }
    final gasMixes = _decodeGasMixes();
    final activeByMix = activeSecondsPerMix(
      gasMixIndexes: samples.gasMixIndex,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );
    final gasLabel = _activeDiluentLabel(gasMixes, activeByMix);

    final otu = computeOtu(
      ppo2Bar: samples.ppo2Bar,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );
    final showOtu = otu > 0;

    final vSpeed = verticalSpeedExtremes(
      depthMeters: samples.depthMeters,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );

    // For CCR dives, pass the voted/measured PPO2 trace so density and
    // END are computed against the live LOOP gas (diluent inert +
    // PPO2-derived O2) instead of whichever static mix the parser
    // happened to assign per-sample. Skip for OC — passing null falls
    // back to the static-mix path.
    // Dive.diveMode is the raw int (per DiveMode enum values in
    // shearwater/parser/constants.dart): 0=cc, 4=sc, 5=cc2 — all CCR.
    // Avoiding the import here keeps this file's imports terse; full
    // DiveMode handling lives in dive_mode_color.dart.
    const ccrModes = {0, 4, 5};
    final isCcrDive = ccrModes.contains(widget.dive.diveMode);
    final ppo2Trace = isCcrDive ? samples.ppo2Bar : null;
    final densitySeries = computeDensitySeries(
      depthMeters: samples.depthMeters,
      gasMixIndex: samples.gasMixIndex,
      gasMixes: gasMixes,
      atmosphericPressureMbar: kStandardAtmosphericPressureMbar,
      ppo2Bar: ppo2Trace,
    );
    final endSeries = computeEndSeries(
      depthMeters: samples.depthMeters,
      gasMixIndex: samples.gasMixIndex,
      gasMixes: gasMixes,
      countsOxygen: widget.settingsNotifier.endCountsOxygen,
      ppo2Bar: ppo2Trace,
    );
    var maxDensity = 0.0;
    for (final d in densitySeries) {
      if (!d.isNaN && d > maxDensity) maxDensity = d;
    }
    var maxEnd = 0.0;
    for (final e in endSeries) {
      if (!e.isNaN && e > maxEnd) maxEnd = e;
    }

    // Run replay to get Surface GF + Max GF. Uses the same cached engine
    // instance as the chart (_decoEngine), so no redundant computation when
    // the chart has already run the replay for the same key.
    final decoAlgo = _annotationsNotifier.displayDecoAlgorithm == 'vpmb'
        ? DecoAlgorithm.vpmb
        : DecoAlgorithm.zhl16c;
    final decoReplay = _decoEngine.replay(
      diveId: widget.dive.id,
      samples: _SampleSetAdapter(samples),
      gasMixes: gasMixes,
      algorithm: decoAlgo,
      vpmbConservatism: widget.settingsNotifier.vpmbConservatism,
      gfLow: widget.dive.gfLow,
      gfHigh: widget.dive.gfHigh,
      surfacePressureBar: _surfacePressureBar,
    );
    final surfaceGf = decoReplay.surfaceGfFinal;
    final maxGf = decoReplay.maxGf99;

    Color colourForGf(double gf) {
      final gfHighVal = (widget.dive.gfHigh ?? 85).toDouble();
      if (gf > 100) return const Color(0xFFDC2626); // red
      if (gf > gfHighVal) return const Color(0xFFF59E0B); // orange
      return const Color(0xFF4ADE80); // green
    }

    Color colourForDensityValue(double v) => switch (densityBand(v)) {
          DensityBand.green => const Color(0xFF4ADE80),
          DensityBand.orange => const Color(0xFFF59E0B),
          DensityBand.red => const Color(0xFFDC2626),
        };
    Color colourForEndValue(double v) => switch (endBand(v)) {
          EndBand.green => const Color(0xFF4ADE80),
          EndBand.orange => const Color(0xFFF59E0B),
          EndBand.red => const Color(0xFFDC2626),
        };

    final dive = widget.dive;
    final stackEnd = dive.stackRemainingAtEndSeconds;
    final stackStart = dive.stackRemainingAtStartSeconds;
    final stackCfg = dive.configuredStackSeconds;
    final stackLabel = stackEnd == null ? '—' : formatStackHm(stackEnd);
    final stackUsed = (stackEnd != null && stackStart != null)
        ? formatStackUsedMs(stackStart - stackEnd)
        : null;
    final stackConf = stackCfg != null ? formatStackHm(stackCfg) : null;

    return LayoutBuilder(builder: (context, constraints) {
      final cells = <Widget>[
        if (ppo2Stats != null)
          StatTile(
            label: 'PPO2',
            unit: 'bar',
            value: ppo2Stats.avg.toStringAsFixed(2),
            hint:
                '${ppo2Stats.min.toStringAsFixed(2)} / ${ppo2Stats.max.toStringAsFixed(2)}',
          )
        else
          const StatTile(label: 'PPO2', value: '—'),
        StatTile(label: 'CNS', value: '${(maxCns * 100).round()}%'),
        if (showOtu) StatTile(label: 'OTU', value: '${otu.round()}'),
        if (tempStats != null)
          StatTile(
            label: 'Temp',
            unit: '°C',
            value: '${tempStats.avg.round()}',
            hint: '${tempStats.min.round()} / ${tempStats.max.round()}',
          )
        else
          const StatTile(label: 'Temp', unit: '°C', value: '—'),
        StatTile(
          label: 'V-speed',
          unit: 'm/min',
          value:
              '↓${vSpeed.maxDescentMpm.round()} ↑${vSpeed.maxAscentMpm.round()}',
        ),
        StatTile(label: 'Gas', value: gasLabel),
        if (_activeTanks().isNotEmpty) _tanksCell(_activeTanks(), theme),
        if (stackEnd != null)
          StatTile(
            label: 'Stack',
            value: stackLabel,
            hint: [stackUsed, stackConf]
                .whereType<String>()
                .join(' · '),
          ),
        StatTile(
          label: 'Density',
          unit: 'g/L',
          value: maxDensity.toStringAsFixed(1),
          valueColor: colourForDensityValue(maxDensity),
        ),
        StatTile(
          label: 'END',
          unit: 'm',
          value: maxEnd.round().toString(),
          valueColor: colourForEndValue(maxEnd),
        ),
        StatTile(
          label: 'SurfGF',
          unit: '%',
          value: surfaceGf.round().toString(),
          valueColor: colourForGf(surfaceGf),
        ),
        StatTile(
          label: 'GF',
          unit: '%',
          value: maxGf.round().toString(),
          valueColor: colourForGf(maxGf),
        ),
      ];
      // Width per cell at ~80px lands at 4 columns on iPhone-portrait (374
      // available / 80 ≈ 4.7 → 4 cells fit with spacing). Below that, wrap
      // to a second line. Tablets / desktop windows stay single-row.
      const minCellWidth = 80.0;
      final cellWidth =
          (constraints.maxWidth - 16) / cells.length; // 16 = horizontal padding
      final useWrap = cellWidth < minCellWidth;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: useWrap
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in cells)
                    SizedBox(width: minCellWidth, child: c),
                ],
              )
            : Row(children: [
                for (final c in cells) Expanded(child: c),
              ]),
      );
    });
  }

  /// Active tanks (those with non-zero start or end pressure), sorted
  /// diluent → oxygen → other.
  List<DiveTank> _activeTanks() {
    final list = _decodeTanks()
        .where((t) => t.beginPressureBar > 0 || t.endPressureBar > 0)
        .toList();
    int rank(TankUsage u) => switch (u) {
          TankUsage.diluent => 0,
          TankUsage.oxygen => 1,
          TankUsage.sidemount => 2,
          TankUsage.none => 3,
        };
    list.sort((a, b) => rank(a.usage).compareTo(rank(b.usage)));
    return list;
  }

  /// Multi-line tank pressure cell. Kept as a custom widget because each
  /// tank gets its own row (StatTile only supports a single value line).
  /// Uses StatTile-ish styling so it sits cleanly next to the others.
  Widget _tanksCell(List<DiveTank> tanks, ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TANKS  BAR',
          style: AppTypography.label.copyWith(color: scheme.outlineVariant),
        ),
        const SizedBox(height: Spacing.xs),
        for (final t in tanks)
          Text(
            '${labelForTank(t, _notifier.mappedCylinders)} '
            '${t.beginPressureBar.round()}→${t.endPressureBar.round()}',
            style: AppTypography.readoutSm.copyWith(color: scheme.onSurface),
          ),
      ],
    );
  }
}

/// Parses a `dive_bailout_carry.gas_mix` string ("21/35", "100", "32") into
/// a [DiveGasMix]. Returns null on empty / malformed input — the planner
/// can simply skip the carry row.
DiveGasMix? _parseBailoutGasMix(String raw) {
  if (raw.isEmpty) return null;
  final parts = raw.split('/');
  final o2 = int.tryParse(parts[0]);
  if (o2 == null || o2 <= 0 || o2 > 100) return null;
  final he = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  if (he < 0 || o2 + he > 100) return null;
  return DiveGasMix(
    oxygenPercent: o2,
    heliumPercent: he,
    isDiluent: false,
  );
}

/// Adapts [SampleSet] to the [SampleStream] interface expected by
/// [DecoReplayEngine]. Bridges field names without copying data.
class _SampleSetAdapter implements SampleStream {
  final SampleSet _s;
  const _SampleSetAdapter(this._s);

  @override
  Float32List get depthMeters => _s.depthMeters;

  @override
  Uint8List get gasMixIndex => _s.gasMixIndex;

  @override
  Float32List get setpointBar => _s.setpointBar;

  @override
  int get sampleIntervalMs => _s.sampleIntervalMs;
}
