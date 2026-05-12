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
import '../sync/cloud/ccrlogger_backend_connector.dart' show SupabaseAuthSessionSource;
import '../sync/cloud/cloud_config.dart';
import '../sync/cloud/cloud_data_wiper.dart';
import '../sync/cloud/cloud_sync_coordinator.dart';
import '../sync/cloud/sync_health_service.dart';
import '../sync/cloud/sync_status_source.dart';
import '../sync/subsurface_git/bootstrap_importer.dart';
import '../sync/subsurface_git/credentials.dart';
import '../sync/subsurface_git/dao_subsurface_sync_data_source.dart';
import '../sync/subsurface_git/sync_orchestrator.dart';
import 'notifiers/dive_list_notifier.dart';
import 'notifiers/import_notifier.dart';
import 'notifiers/settings_notifier.dart';
import 'screens/dive_list_screen.dart';
import 'screens/equipment/equipment_landing_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sites_map_screen.dart';
import 'widgets/sync_health_banner.dart';

class AppShell extends StatefulWidget {
  final AppDatabase db;
  final PowerSyncDatabase powerSyncDb;
  final SettingsNotifier settingsNotifier;
  final AuthService authService;
  final CloudSyncCoordinator cloudSyncCoordinator;
  final CloudDataWiper? cloudDataWiper;

  const AppShell({
    super.key,
    required this.db,
    required this.powerSyncDb,
    required this.settingsNotifier,
    required this.authService,
    required this.cloudSyncCoordinator,
    this.cloudDataWiper,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final DiveDao _diveDao;
  late final ImportStateDao _importStateDao;
  late final EquipmentDao _equipmentDao;
  late final DiveAnnotationsDao _diveAnnotationsDao;
  late final DiveAttachmentsDao _diveAttachmentsDao;
  late final DiveListNotifier _diveListNotifier;
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
    _diveListNotifier = DiveListNotifier(_diveDao, _diveAnnotationsDao);
    _importNotifier = ImportNotifier(
      dao: _diveDao,
      importStateDao: _importStateDao,
      equipmentDao: _equipmentDao,
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
    _authSignInSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) {
        if (event.session != null) {
          _syncHealthService.start();
        } else {
          _syncHealthService.stop();
        }
      },
    );
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
      final cloneRoot =
          Directory(p.join(docsDir.path, 'subsurface_clone'));
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSignInSub?.cancel();
    _syncHealthService.dispose();
    _diveListNotifier.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CCRLog'),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Dive sites map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SitesMapScreen(
                    dao: _diveAnnotationsDao,
                    currentLat: null,
                    currentLon: null,
                  ),
                ));
              },
            ),
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SettingsScreen(
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
                ));
              },
            ),
        ],
      ),
      body: material.Column(
        children: [
          SyncHealthBanner(service: _syncHealthService),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                DiveListScreen(
                  notifier: _diveListNotifier,
                  diveDao: _diveDao,
                  annotationsDao: _diveAnnotationsDao,
                  equipmentDao: _equipmentDao,
                  attachmentsDao: _diveAttachmentsDao,
                  attachmentUploader: _attachmentUploader,
                  attachmentDownloader: _attachmentDownloader,
                  settingsNotifier: widget.settingsNotifier,
                ),
                ImportScreen(
                    notifier: _importNotifier, onViewDives: _onViewDives),
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
                  subsurfaceBootstrapImporter: _subsurfaceBootstrapImporter,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.scuba_diving), label: 'Dives'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Import'),
          BottomNavigationBarItem(icon: Icon(Icons.build_outlined), label: 'Equipment'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
