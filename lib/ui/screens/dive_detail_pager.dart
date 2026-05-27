/// PageView wrapper around [DiveDetailScreen] that turns a list of dives
/// into a browsable carousel.
///
/// On mobile the user swipes left/right; on every platform the AppBar
/// chevron buttons step through the list. Each page is a self-contained
/// [DiveDetailScreen] keyed by dive id.
///
/// Annotation + attachments lifecycle is owned by this pager (not by
/// each child) so that swiping past a dirty page doesn't silently
/// dispose in-flight edits or in-progress uploads. The pager:
///
///   * caches one [DiveAnnotationsNotifier] per visited dive id;
///   * caches one [DiveAttachmentsNotifier] per visited dive id;
///   * pops a SnackBar warning when the user swipes off a dirty annotation;
///   * wraps the whole pager with a [PopScope] that lists every cached
///     page's unsaved annotation changes when the user tries to leave.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_attachments_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../sync/attachments/attachment_downloader.dart';
import '../../sync/attachments/attachment_uploader.dart';
import '../notifiers/dive_annotations_notifier.dart';
import '../notifiers/dive_attachments_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'dive_detail_screen.dart';

class DiveDetailPager extends StatefulWidget {
  final List<Dive> dives;
  final int initialIndex;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  // Optional: when any of the three are null, the dive-detail screen
  // hides the attachments section. Production wires all three from
  // [AppShell]; tests skip them.
  final DiveAttachmentsDao? attachmentsDao;
  final AttachmentUploader? attachmentUploader;
  final AttachmentDownloader? attachmentDownloader;
  final SettingsNotifier settingsNotifier;

  /// CCRLog-internal sequence number per dive id (newest = N, oldest = 1).
  /// See [DiveListNotifier.sequenceByDiveId]. When omitted/empty the screens
  /// fall back to the DC's own dive number for the `#N` label.
  final Map<String, int> sequenceByDiveId;

  const DiveDetailPager({
    super.key,
    required this.dives,
    required this.initialIndex,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
    this.attachmentsDao,
    this.attachmentUploader,
    this.attachmentDownloader,
    required this.settingsNotifier,
    this.sequenceByDiveId = const {},
  })  : assert(dives.length > 0, 'DiveDetailPager needs at least one dive'),
        assert(initialIndex >= 0, 'initialIndex must be non-negative');

  @override
  State<DiveDetailPager> createState() => _DiveDetailPagerState();
}

class _DiveDetailPagerState extends State<DiveDetailPager> {
  late final PageController _controller;
  late int _currentIndex;
  final Map<String, DiveAnnotationsNotifier> _annotationsByDiveId = {};
  final Map<String, DiveAttachmentsNotifier> _attachmentsByDiveId = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.dives.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    for (final n in _annotationsByDiveId.values) {
      n.removeListener(_onAnyDirtyChanged);
      n.dispose();
    }
    for (final n in _attachmentsByDiveId.values) {
      n.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  /// Lazily creates (and caches) the annotations notifier for [dive].
  /// Triggers an async `load()` on first call; the notifier flips its
  /// own `loaded` flag once the row is in.
  DiveAnnotationsNotifier _annotationsFor(Dive dive) {
    return _annotationsByDiveId.putIfAbsent(dive.id, () {
      final n = DiveAnnotationsNotifier(
        widget.annotationsDao,
        widget.equipmentDao,
      );
      n.addListener(_onAnyDirtyChanged);
      n.load(dive.id);
      return n;
    });
  }

  /// Lazily creates (and caches) the attachments notifier for [dive].
  /// Held alive across PageView page recycling so an upload in progress
  /// on dive A keeps running while the user swipes to dive B. Returns
  /// null when the pager is missing the DAO or uploader (test wiring),
  /// in which case the detail screen hides the attachments section.
  DiveAttachmentsNotifier? _attachmentsFor(Dive dive) {
    final dao = widget.attachmentsDao;
    final uploader = widget.attachmentUploader;
    if (dao == null || uploader == null) return null;
    return _attachmentsByDiveId.putIfAbsent(dive.id, () {
      final n = DiveAttachmentsNotifier(dao, uploader);
      n.load(dive.id);
      return n;
    });
  }

  /// Re-builds the pager when any cached notifier's dirty flag changes.
  /// We need this so the [PopScope]'s `canPop` reflects the latest dirty
  /// state across every visited page.
  void _onAnyDirtyChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _goPrev() {
    if (_currentIndex <= 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _goNext() {
    if (_currentIndex >= widget.dives.length - 1) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int newIndex) {
    final oldIndex = _currentIndex;
    if (oldIndex == newIndex) return;
    final oldDive = widget.dives[oldIndex];
    final oldNotifier = _annotationsByDiveId[oldDive.id];
    if (oldNotifier != null && oldNotifier.dirty) {
      _showUnsavedSnackBar(oldDive, oldNotifier);
    }
    setState(() => _currentIndex = newIndex);
  }

  void _showUnsavedSnackBar(Dive dive, DiveAnnotationsNotifier notifier) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
          'Unsaved annotations on dive #${widget.sequenceByDiveId[dive.id] ?? dive.dcDiveNumber}'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Save',
        onPressed: () async {
          if (!mounted) return;
          await notifier.save();
        },
      ),
    ));
  }

  /// Every cached page that still has unsaved edits, ordered by index so
  /// the dialog summary reads chronologically.
  List<({Dive dive, DiveAnnotationsNotifier notifier})> _dirtyPages() {
    final out = <({Dive dive, DiveAnnotationsNotifier notifier})>[];
    for (var i = 0; i < widget.dives.length; i++) {
      final n = _annotationsByDiveId[widget.dives[i].id];
      if (n != null && n.dirty) {
        out.add((dive: widget.dives[i], notifier: n));
      }
    }
    return out;
  }

  Future<bool> _confirmPopWithDirtyPages(
      List<({Dive dive, DiveAnnotationsNotifier notifier})> dirty) async {
    final summary = dirty
        .map((p) =>
            '#${widget.sequenceByDiveId[p.dive.id] ?? p.dive.dcDiveNumber}')
        .join(', ');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dirty.length == 1
            ? 'Unsaved changes'
            : 'Unsaved changes on ${dirty.length} dives'),
        content: Text(
          'You have unsaved annotation edits on $summary. '
          'Save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      for (final p in dirty) {
        await p.notifier.save();
      }
      return true;
    }
    return result == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirtyPages();
    final currentDive = widget.dives[_currentIndex];
    final currentAnnotations = _annotationsFor(currentDive);
    return PopScope(
      canPop: dirty.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmPopWithDirtyPages(dirty);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: DefaultTabController(
        length: 4,
        child: Builder(builder: (context) {
          // Mirror AppShell's landscape immersion — phones only. On
          // tablets / desktop the chrome doesn't crowd the chart, and
          // desktop windows report Orientation.landscape for any
          // wider-than-tall window which would otherwise hide the
          // chrome permanently. Guard on shortest-side < 600 dp.
          final mq = MediaQuery.of(context);
          final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android;
          final isPhone = isMobile && mq.size.shortestSide < 600;
          final isLandscape =
              isPhone && mq.orientation == Orientation.landscape;
          return Scaffold(
          appBar: isLandscape
              ? null
              : _buildAppBar(context, currentDive, currentAnnotations),
          body: ListenableBuilder(
            listenable: widget.settingsNotifier,
            builder: (context, _) {
              // SafeArea is a no-op in portrait (the AppBar already
              // handles the status-bar inset) — in landscape it pushes
              // the chart out from under the iPhone notch / Dynamic
              // Island on the leading edge and the home-indicator on
              // the bottom edge.
              return SafeArea(
                top: isLandscape,
                bottom: isLandscape,
                left: isLandscape,
                right: isLandscape,
                child: Column(
                  children: [
                    if (!isLandscape) _buildTabBar(context),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: widget.dives.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, i) {
                          final dive = widget.dives[i];
                          return DiveDetailScreen(
                            key: ValueKey(dive.id),
                            dive: dive,
                            sequenceNumber: widget.sequenceByDiveId[dive.id],
                            dao: widget.diveDao,
                            annotationsDao: widget.annotationsDao,
                            equipmentDao: widget.equipmentDao,
                            settingsNotifier: widget.settingsNotifier,
                            annotationsNotifier: _annotationsFor(dive),
                            attachmentsNotifier: _attachmentsFor(dive),
                            attachmentDownloader: widget.attachmentDownloader,
                            onPrev: i > 0 ? _goPrev : null,
                            onNext: i < widget.dives.length - 1 ? _goNext : null,
                            wrappedInPager: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
        }),
      ),
    );
  }

  /// AppBar bound to the current dive — title + subtitle reflect whichever
  /// page is foregrounded, save button reads its dirty state. Listening to
  /// each cached annotations notifier (see [_annotationsFor]) is what
  /// keeps the bar in sync after a page change OR a dirty-flag flip.
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Dive currentDive,
    DiveAnnotationsNotifier annotations,
  ) {
    final siteName = annotations.siteName;
    final subtitle = [
      if (siteName != null && siteName.isNotEmpty) siteName,
      formatDateTime(currentDive.startTime),
    ].join(' · ');
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Dive #${widget.sequenceByDiveId[currentDive.id] ?? currentDive.dcDiveNumber}',
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
      ),
      actions: [
        IconButton(
          tooltip: 'Previous dive',
          icon: const Icon(Icons.chevron_left),
          onPressed: _currentIndex > 0 ? _goPrev : null,
        ),
        IconButton(
          tooltip: 'Next dive',
          icon: const Icon(Icons.chevron_right),
          onPressed: _currentIndex < widget.dives.length - 1 ? _goNext : null,
        ),
        IconButton(
          tooltip: annotations.dirty ? 'Save (unsaved changes)' : 'Save',
          icon: Icon(
            annotations.dirty ? Icons.save : Icons.save_outlined,
            color: annotations.dirty
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          onPressed: annotations.dirty ? () => annotations.save() : null,
        ),
      ],
    );
  }

  /// Fixed tab bar — driven by the inherited [DefaultTabController]. Tab
  /// choice persists across dive swipes, so a user on Information stays
  /// on Information when navigating to the next dive.
  Widget _buildTabBar(BuildContext context) {
    // Hide tab labels on narrow viewports — icons alone keep the bar
    // from overflowing on phones in portrait.
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
  }
}
