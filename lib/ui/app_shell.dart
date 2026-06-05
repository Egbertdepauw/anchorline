import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Column;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db/database.dart';
import '../data/db/dive_annotations_dao.dart';
import '../data/db/dive_attachments_dao.dart';
import '../data/db/dive_dao.dart';
import '../data/db/dive_derived_stats_dao.dart';
import '../data/db/dive_merge_dao.dart';
import '../data/db/dive_plans_dao.dart';
import '../data/db/equipment_dao.dart';
import '../data/db/import_state_dao.dart';
import '../sync/attachments/attachment_cache.dart';
import '../sync/attachments/attachment_downloader.dart';
import '../sync/attachments/attachment_object_wiper.dart';
import '../sync/attachments/attachment_signer.dart';
import '../sync/attachments/attachment_uploader.dart';
import '../sync/attachments/attachment_uploader_impl.dart';
import '../sync/attachments/pending_upload_store.dart';
import '../sync/cloud/auth_service.dart';
import '../sync/cloud/ccrlogger_backend_connector.dart'
    show SupabaseAuthSessionSource;
import '../sync/cloud/cloud_config.dart';
import '../sync/cloud/cloud_data_wiper.dart';
import '../sync/cloud/cloud_sync_coordinator.dart';
import '../sync/cloud/sync_health_service.dart';
import '../sync/cloud/sync_status_source.dart';
import '../sync/cloud/usage_tracker.dart';
import '../sync/subsurface_git/bootstrap_importer.dart';
import '../sync/subsurface_git/credentials.dart';
import '../sync/subsurface_git/dao_subsurface_sync_data_source.dart';
import '../sync/subsurface_git/sync_orchestrator.dart';
import 'notifiers/blend_notifier.dart';
import 'notifiers/dive_list_notifier.dart';
import 'notifiers/dive_plan_notifier.dart';
import 'notifiers/import_notifier.dart';
import 'notifiers/settings_notifier.dart';
import 'screens/blend_screen.dart';
import 'screens/buddies_list_screen.dart';
import 'screens/dive_list_screen.dart';
import 'screens/dive_plan_screen.dart';
import 'screens/equipment/equipment_landing_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sites_map_screen.dart';
import 'screens/statistics_screen.dart';
import 'widgets/anchorline_logo.dart';
import 'widgets/background_watermark.dart';
import 'widgets/renumber_dialog.dart';
import 'widgets/sync_health_banner.dart';

class AppShell extends StatefulWidget {
  final AppDatabase db;
  final PowerSyncDatabase powerSyncDb;
  final SettingsNotifier settingsNotifier;
  final AuthService authService;
  final CloudSyncCoordinator cloudSyncCoordinator;
  final CloudDataWiper? cloudDataWiper;
  final UsageTracker usageTracker;

  const AppShell({
    super.key,
    required this.db,
    required this.powerSyncDb,
    required this.settingsNotifier,
    required this.authService,
    required this.cloudSyncCoordinator,
    required this.usageTracker,
    this.cloudDataWiper,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  bool _syncing = false;
  int _currentIndex = 0;

  /// Key for the Dives tab's nested Navigator, so tapping the Anchorline
  /// logo can pop any pushed route (dive detail) back to the dive list.
  final _divesNavigatorKey = GlobalKey<NavigatorState>();
  late final DiveDao _diveDao;
  late final ImportStateDao _importStateDao;
  late final EquipmentDao _equipmentDao;
  late final DiveAnnotationsDao _diveAnnotationsDao;
  late final DiveAttachmentsDao _diveAttachmentsDao;
  late final DiveMergeDao _diveMergeDao;
  late final DiveDerivedStatsDao _diveDerivedStatsDao;
  late final DiveListNotifier _diveListNotifier;
  late final DivePlansDao _divePlansDao;
  late final DivePlanNotifier _divePlanNotifier;
  late final BlendNotifier _blendNotifier;
  late final ImportNotifier _importNotifier;
  late final SyncStatusSource _syncStatusSource;
  late final SyncHealthService _syncHealthService;
  StreamSubscription<AuthState>? _authSignInSub;

  // Attachments pipeline. The signer URL falls back to a clearly-bogus
  // host when ATTACHMENTS_SIGNER_URL isn't dart-defined so dev builds
  // construct cleanly; actual upload/download then fails with a DNS
  // error and the notifier surfaces it. Set
  // `--dart-define=ATTACHMENTS_SIGNER_URL=…` for staging/prod builds.
  late final AttachmentSigner _attachmentSigner;
  late final AttachmentCache _attachmentCache;
  late final AttachmentDownloader _attachmentDownloader;
  late final AttachmentUploader _attachmentUploader;
  late final PendingUploadStore _pendingUploadStore;
  late final AttachmentObjectWiper _attachmentObjectWiper;

  // Subsurface git sync (Phase E). Constructed asynchronously because
  // path_provider.getApplicationDocumentsDirectory() returns a Future
  // and our [initState] is sync. Until [_initSubsurfaceSync] resolves,
  // these stay null and the Settings UI hides the Subsurface card.
  // SettingsScreen already gates the section behind non-null checks.
  late final SubsurfaceCredentialsSource _subsurfaceCredentials;
  SubsurfaceSyncOrchestrator? _subsurfaceOrchestrator;
  SubsurfaceBootstrapImporter? _subsurfaceBootstrapImporter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Beta telemetry: one "session_started" event per app launch. Drops
    // silently if no signed-in user yet (very-first launch is unsigned
    // until the user enters credentials; subsequent launches fire on
    // restored sessions). Platform tag separates iOS / Android / macOS
    // usage in the dashboard.
    widget.usageTracker.track('session_started', {
      'platform': defaultTargetPlatform.name,
    });

    _diveDao = DiveDao(
      widget.db,
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _importStateDao = ImportStateDao(widget.db);
    _equipmentDao = EquipmentDao(
      widget.db,
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _diveAnnotationsDao = DiveAnnotationsDao(
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _diveAttachmentsDao = DiveAttachmentsDao(
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _diveMergeDao = DiveMergeDao(
      widget.db,
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _diveDerivedStatsDao = DiveDerivedStatsDao(widget.db);
    _diveListNotifier = DiveListNotifier(_diveDao, _diveAnnotationsDao, _diveMergeDao);
    _divePlansDao = DivePlansDao(
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _divePlanNotifier = DivePlanNotifier(
      dao: _divePlansDao,
      settings: widget.settingsNotifier,
    );
    _divePlanNotifier.load();
    _blendNotifier = BlendNotifier(settings: widget.settingsNotifier);
    _importNotifier = ImportNotifier(
      dao: _diveDao,
      importStateDao: _importStateDao,
      equipmentDao: _equipmentDao,
      usageTracker: widget.usageTracker,
      useMock: kDebugMode,
    );
    _syncStatusSource = PowerSyncStatusSource(widget.powerSyncDb);

    // Replication-slot WAL retention monitor. Polls every 5 min while
    // signed in; surfaces a banner before retention crosses the
    // Postgres `max_slot_wal_keep_size = 1GB` cap. See
    // supabase/migrations/0008_sync_health_guards.sql for the
    // server-side guards this complements.
    _syncHealthService = SyncHealthService(
      SupabaseSyncHealthClient(Supabase.instance.client),
    );
    _authSignInSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      event,
    ) {
      if (event.session != null) {
        _syncHealthService.start();
      } else {
        _syncHealthService.stop();
      }
    });
    if (Supabase.instance.client.auth.currentSession != null) {
      _syncHealthService.start();
    }

    _attachmentSigner = AttachmentSigner(
      baseUrl: CloudConfig.attachmentsSignerUrl,
      session: SupabaseAuthSessionSource(Supabase.instance.client),
    );
    _attachmentCache = AttachmentCache();
    _attachmentDownloader = AttachmentDownloader(
      signer: _attachmentSigner,
      cache: _attachmentCache,
    );
    _pendingUploadStore = SharedPrefsPendingUploadStore();
    _attachmentUploader = AttachmentUploaderImpl(
      signer: _attachmentSigner,
      dao: _diveAttachmentsDao,
      pendingStore: _pendingUploadStore,
    );
    _attachmentObjectWiper = AttachmentObjectWiper(
      dao: _diveAttachmentsDao,
      signer: _attachmentSigner,
    );

    _subsurfaceCredentials = SecureStorageSubsurfaceCredentials();
    // Fire-and-forget — _initSubsurfaceSync calls setState when the
    // orchestrator is ready, which re-renders SettingsScreen with the
    // Subsurface card visible. Errors are logged but non-fatal: if
    // path_provider fails the section just stays hidden.
    _initSubsurfaceSync();
  }

  Future<void> _initSubsurfaceSync() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final cloneRoot = Directory(p.join(docsDir.path, 'subsurface_clone'));
      if (!mounted) return;
      setState(() {
        _subsurfaceOrchestrator = SubsurfaceSyncOrchestrator(
          dataSource: DaoSubsurfaceSyncDataSource(
            diveDao: _diveDao,
            annotationsDao: _diveAnnotationsDao,
            equipmentDao: _equipmentDao,
          ),
          credentials: _subsurfaceCredentials,
          localCloneRoot: cloneRoot,
        );
        _subsurfaceBootstrapImporter = SubsurfaceBootstrapImporter(
          credentials: _subsurfaceCredentials,
          localCloneRoot: cloneRoot,
          dataSource: DaoBootstrapDataSource(
            diveDao: _diveDao,
            annotationsDao: _diveAnnotationsDao,
          ),
        );
      });
    } catch (e, st) {
      debugPrint('Subsurface sync init failed: $e\n$st');
    }

    // Future.delayed(const Duration(seconds: 5), () {
    //   throw Exception('Sentry smoke test — please ignore');
    // });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSignInSub?.cancel();
    _syncHealthService.dispose();
    _diveListNotifier.dispose();
    _divePlanNotifier.dispose();
    _blendNotifier.dispose();
    _importNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Force a fresh PowerSync connection when the app resumes — the
    // WebSocket can go stale during Mac sleep / backgrounding without
    // the SyncStatus indicator reflecting it. No-op when signed out.
    if (state == AppLifecycleState.resumed) {
      widget.cloudSyncCoordinator.forceReconnect();
    }
  }

  void _onViewDives() {
    setState(() => _currentIndex = 0);
    _diveListNotifier.loadDives();
  }

  /// Anchorline logo tap → return to the dive list. Pops any route
  /// pushed inside the Dives tab (e.g. a dive detail) back to root, then
  /// switches to the Dives tab.
  void _goHome() {
    _divesNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
  }

  Future<void> _syncSubsurface() async {
    final orchestrator = _subsurfaceOrchestrator;
    if (orchestrator == null || _syncing) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await orchestrator.syncNow();
      if (!mounted) return;
      final aborted = result.abortedDives.length;
      final msg = result.divesPushed == 0 && aborted == 0
          ? 'Already up to date.'
          : 'Pushed ${result.divesPushed} dive(s)'
                '${aborted > 0 ? ", skipped $aborted (foreign edits)" : ""}'
                '${result.divesSkipped > 0 ? ", ${result.divesSkipped} unchanged" : ""}.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } on NoCredentialsException {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No Subsurface Cloud credentials saved. Add them in Settings → Subsurface Cloud.',
          ),
        ),
      );
    } on SubsurfaceSyncException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Sync failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Immersive landscape — phones only. Hide the global AppBar +
    // bottom nav so the pushed route's chart takes the full screen.
    // Tablets and desktop windows are wide enough that the chrome
    // never crowded the chart in the first place, AND on desktops the
    // OS reports `Orientation.landscape` for any window where width >
    // height (which is most of them), so a pure-orientation check
    // hides the nav permanently. Guard on shortest-side < 600 dp,
    // which is the conventional phone-vs-tablet/desktop boundary.
    final mq = MediaQuery.of(context);
    final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final isPhone = isMobile && mq.size.shortestSide < 600;
    final isLandscape =
        isPhone && mq.orientation == Orientation.landscape;
    return ListenableBuilder(
      listenable: _diveListNotifier,
      builder: (context, _) => Scaffold(
      appBar: isLandscape
          ? null
          : (_currentIndex == 0 && _diveListNotifier.selectionMode
              ? _buildSelectionAppBar(context)
              : AppBar(
        // Wordmark SVG (anchor + "Anchorline" lockup) instead of a plain
        // text title. The SVG's dark background blends with the AppBar's
        // wreck-palette surface so only the mark + text show.
        // Tapping the wordmark returns to the dive list: switch to the
        // Dives tab and pop any pushed route (dive detail) back to root.
        title: InkWell(
          onTap: _goHome,
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: AnchorlineLogo(
              mark: AnchorlineMark.wordmarkDark,
              size: 32,
            ),
          ),
        ),
        actions: [
          if (_currentIndex == 0 &&
              (_subsurfaceOrchestrator?.isPlatformSupported ?? false))
            IconButton(
              tooltip: _syncing ? 'Syncing…' : 'Push to Subsurface Cloud',
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              onPressed: _syncing ? null : _syncSubsurface,
            ),
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Buddies',
              icon: const Icon(Icons.people_outline),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BuddiesListScreen(dao: _diveAnnotationsDao),
                  ),
                );
              },
            ),
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Statistics',
              icon: const Icon(Icons.bar_chart),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StatisticsScreen(
                    diveDao: _diveDao,
                    annotationsDao: _diveAnnotationsDao,
                    derivedStatsDao: _diveDerivedStatsDao,
                  ),
                ));
              },
            ),
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Dive sites map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SitesMapScreen(
                      dao: _diveAnnotationsDao,
                      currentLat: null,
                      currentLon: null,
                      settingsNotifier: widget.settingsNotifier,
                    ),
                  ),
                );
              },
            ),
        ],
      )),
      body: material.Column(
        children: [
          SyncHealthBanner(service: _syncHealthService),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.settingsNotifier,
              builder: (context, _) {
                return BackgroundWatermark(
                  // Suppress the branding watermark on the Settings tab
                  // (index 5). Settings is a dense, utilitarian list —
                  // the diver mark reads as visual clutter / a doubled
                  // mark behind the controls there, where it adds nothing.
                  opacity: _currentIndex == 5
                      ? 0.0
                      : widget.settingsNotifier.watermarkOpacity,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      // Nested Navigator for the Dives tab so pushed
                      // routes (dive detail) stack INSIDE this tab
                      // instead of replacing the whole AppShell. Keeps
                      // the bottom nav bar visible on detail screens
                      // and — by virtue of Scaffold's bottomNavigationBar
                      // slot insetting for the system bars — also fixes
                      // the Android edge-to-edge clipping that
                      // otherwise put content behind the gesture-nav
                      // buttons. Only the Dives tab needs this; the
                      // other tabs don't push routes deeper than their
                      // root.
                      Navigator(
                        key: _divesNavigatorKey,
                        onGenerateRoute: (settings) => MaterialPageRoute(
                          settings: settings,
                          builder: (_) => DiveListScreen(
                            notifier: _diveListNotifier,
                            diveDao: _diveDao,
                            annotationsDao: _diveAnnotationsDao,
                            equipmentDao: _equipmentDao,
                            attachmentsDao: _diveAttachmentsDao,
                            attachmentUploader: _attachmentUploader,
                            attachmentDownloader: _attachmentDownloader,
                            settingsNotifier: widget.settingsNotifier,
                          ),
                        ),
                      ),
                      DivePlanScreen(
                        notifier: _divePlanNotifier,
                        settings: widget.settingsNotifier,
                      ),
                      BlendScreen(
                        notifier: _blendNotifier,
                        settings: widget.settingsNotifier,
                      ),
                      ImportScreen(
                        notifier: _importNotifier,
                        onViewDives: _onViewDives,
                      ),
                      EquipmentLandingScreen(
                        dao: _equipmentDao,
                        diveDao: _diveDao,
                        annotationsDao: _diveAnnotationsDao,
                        settingsNotifier: widget.settingsNotifier,
                      ),
                      SettingsScreen(
                        notifier: widget.settingsNotifier,
                        authService: widget.authService,
                        syncStatusSource: _syncStatusSource,
                        db: widget.db,
                        powerSyncDb: widget.powerSyncDb,
                        cloudDataWiper: widget.cloudDataWiper,
                        attachmentObjectWiper: _attachmentObjectWiper,
                        subsurfaceOrchestrator: _subsurfaceOrchestrator,
                        subsurfaceCredentials: _subsurfaceCredentials,
                        diveDao: _diveDao,
                        subsurfaceBootstrapImporter:
                            _subsurfaceBootstrapImporter,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: isLandscape ? null : BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.scuba_diving),
            label: 'Dives',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            label: 'Plan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.science_outlined),
            label: 'Blend',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Import'),
          BottomNavigationBarItem(
            icon: Icon(Icons.build_outlined),
            label: 'Equipment',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    ));
  }

  /// Contextual app bar shown while multi-selecting dives on the Dives tab.
  /// The Merge action is enabled only when the current selection passes the
  /// guardrails; otherwise tapping it explains why via a SnackBar.
  AppBar _buildSelectionAppBar(BuildContext context) {
    final n = _diveListNotifier;
    final eligibility = n.mergeEligibility;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: n.exitSelectionMode,
      ),
      title: Text('${n.selectedDiveIds.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: n.selectAll,
        ),
        IconButton(
          tooltip: 'Renumber selected dives',
          icon: const Icon(Icons.format_list_numbered),
          onPressed: n.selectedDiveIds.isEmpty
              ? null
              : () async {
                  final result = await showRenumberDialog(
                      context, n.selectedDiveIds.length);
                  if (result is RenumberApply) {
                    await n.renumberSelected(result.start);
                  } else if (result is RenumberReset) {
                    await n.resetNumberingSelected();
                  }
                },
        ),
        IconButton(
          tooltip: eligibility.canMerge
              ? 'Merge selected dives'
              : (eligibility.reason ?? 'Cannot merge'),
          icon: const Icon(Icons.merge_type),
          onPressed: eligibility.canMerge
              ? () => n.mergeSelected()
              : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(eligibility.reason ?? 'Cannot merge')),
                  ),
        ),
      ],
    );
  }
}
