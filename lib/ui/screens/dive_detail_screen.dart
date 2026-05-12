import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
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
import '../widgets/dive_cylinders_section.dart';
import '../widgets/dive_information_section.dart';
import '../widgets/dive_media_tab.dart';
import '../widgets/dive_equipment_section.dart';
import '../widgets/profile_chart.dart';
import '../widgets/site_mini_map.dart';
import 'image_viewer_screen.dart';
import 'pdf_viewer_screen.dart';
import 'sites_map_screen.dart';
import '../widgets/star_rating.dart';
import '../widgets/trace_segmented_bar.dart';
import '../components/stat_tile.dart';
import '../theme/tokens.dart';

class DiveDetailScreen extends StatefulWidget {
  final Dive dive;
  final DiveDao dao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final SettingsNotifier? settingsNotifier;

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

  const DiveDetailScreen({
    super.key,
    required this.dive,
    required this.dao,
    required this.annotationsDao,
    required this.equipmentDao,
    this.settingsNotifier,
    this.onPrev,
    this.onNext,
    this.annotationsNotifier,
    this.attachmentsNotifier,
    this.attachmentDownloader,
    this.sequenceNumber,
  });
  @override
  State<DiveDetailScreen> createState() => _DiveDetailScreenState();
}

class _DiveDetailScreenState extends State<DiveDetailScreen> {
  late final DiveDetailNotifier _notifier;
  late final DiveAnnotationsNotifier _annotationsNotifier;
  late final bool _ownsAnnotations;

  @override
  void initState() {
    super.initState();
    _notifier = DiveDetailNotifier(
      dive: widget.dive,
      dao: widget.dao,
      equipmentDao: widget.equipmentDao,
    );
    _notifier.addListener(_onChanged);
    _notifier.loadSamples();

    _ownsAnnotations = widget.annotationsNotifier == null;
    if (_ownsAnnotations) {
      _annotationsNotifier = DiveAnnotationsNotifier(
        widget.annotationsDao,
        widget.equipmentDao,
      );
      _annotationsNotifier.load(widget.dive.id);
    } else {
      _annotationsNotifier = widget.annotationsNotifier!;
    }
    _annotationsNotifier.addListener(_onChanged);

    widget.settingsNotifier?.addListener(_onChanged);
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    _annotationsNotifier.removeListener(_onChanged);
    if (_ownsAnnotations) {
      _annotationsNotifier.dispose();
    }
    widget.settingsNotifier?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dive = widget.dive;
    final theme = Theme.of(context);

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
                                ]),
                          ]),
                    );
                  }),

                  // Star rating: own row so the header text column isn't
                  // squeezed by 5 stars on narrow screens.
                  Container(
                    color: const Color(0xFF152238),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    alignment: Alignment.centerRight,
                    child: StarRating(
                      value: _annotationsNotifier.rating,
                      onChanged: (v) =>
                          _annotationsNotifier.setRating(v),
                    ),
                  ),

                  // Profile chart
                  if (_notifier.samples != null) ...[
                    Builder(builder: (context) {
                      final samples = _notifier.samples!;
                      final useSpeedColored =
                          widget.settingsNotifier?.useSpeedColoredGraph ?? true;
                      return SizedBox(
                        height: 250,
                        child: LayoutBuilder(builder: (context, constraints) {
                          return CrosshairOverlay(
                            sampleCount: samples.sampleCount,
                            chartLeftPad: 40,
                            chartRightPad: 44,
                            onIndexChanged: _notifier.setCrosshairIndex,
                            onRelease: _notifier.clearCrosshair,
                            child: Stack(children: [
                              ProfileChart(
                                  samples: samples,
                                  visibleTraces: _notifier.visibleTraces,
                                  crosshairIndex: _notifier.crosshairIndex,
                                  cellsBySlot: _notifier.activeCells,
                                  tanks: _decodeTanks(),
                                  mappedCylinders: _notifier.mappedCylinders,
                                  gasMixes: _decodeGasMixes(),
                                  useSpeedColoredGraph: useSpeedColored),
                              if (_notifier.crosshairIndex != null)
                                CrosshairTooltip(
                                  samples: _notifier.samples!,
                                  sampleIndex: _notifier.crosshairIndex!,
                                  visibleTraces: _notifier.visibleTraces,
                                  chartX: 40 +
                                      (_notifier.crosshairIndex! /
                                              (_notifier.samples!
                                                      .sampleCount -
                                                  1)) *
                                          (constraints.maxWidth - 84),
                                  chartWidth: constraints.maxWidth,
                                  cellsBySlot: _notifier.activeCells,
                                  tanks: _decodeTanks(),
                                  mappedCylinders: _notifier.mappedCylinders,
                                  gasMixes: _decodeGasMixes(),
                                ),
                            ]),
                          );
                        }),
                      );
                    }),
                    TraceSegmentedBar(
                        visibleTraces: _notifier.visibleTraces,
                        onToggle: _notifier.toggleTrace),
                    _buildStatsRow(theme),
                    _buildAnnotationsSection(),
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
      ];
      // Width per cell at ~95px keeps even the long "PPO2 min/avg/max" label
      // legible. Below that, wrap to a second line.
      const minCellWidth = 95.0;
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
