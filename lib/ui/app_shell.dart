import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db/database.dart';
import '../data/db/dive_annotations_dao.dart';
import '../data/db/dive_dao.dart';
import '../data/db/equipment_dao.dart';
import '../data/db/import_state_dao.dart';
import '../sync/cloud/auth_service.dart';
import '../sync/subsurface_export.dart';
import 'notifiers/dive_list_notifier.dart';
import 'notifiers/import_notifier.dart';
import 'notifiers/settings_notifier.dart';
import 'screens/dive_list_screen.dart';
import 'screens/equipment/equipment_landing_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  final AppDatabase db;
  final SettingsNotifier settingsNotifier;
  final AuthService authService;

  const AppShell({
    super.key,
    required this.db,
    required this.settingsNotifier,
    required this.authService,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final DiveDao _diveDao;
  late final ImportStateDao _importStateDao;
  late final EquipmentDao _equipmentDao;
  late final DiveAnnotationsDao _diveAnnotationsDao;
  late final DiveListNotifier _diveListNotifier;
  late final ImportNotifier _importNotifier;
  late final SubsurfaceExporter _subsurfaceExporter;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _diveDao = DiveDao(widget.db);
    _importStateDao = ImportStateDao(widget.db);
    _equipmentDao = EquipmentDao(widget.db);
    _diveAnnotationsDao = DiveAnnotationsDao(widget.db);
    _diveListNotifier = DiveListNotifier(_diveDao, _diveAnnotationsDao);
    _importNotifier = ImportNotifier(
      dao: _diveDao,
      importStateDao: _importStateDao,
      equipmentDao: _equipmentDao,
      useMock: kDebugMode,
    );
    _subsurfaceExporter = SubsurfaceExporter(
      diveDao: _diveDao,
      annotationsDao: _diveAnnotationsDao,
    );
  }

  @override
  void dispose() {
    _diveListNotifier.dispose();
    _importNotifier.dispose();
    super.dispose();
  }

  void _onViewDives() {
    setState(() => _currentIndex = 0);
    _diveListNotifier.loadDives();
  }

  Future<void> _onUploadToSubsurface() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final messenger = ScaffoldMessenger.of(context);
    // iOS popover anchor — required on iPad, harmless on iPhone, prevents
    // Share.shareXFiles from no-op-failing on some iOS configurations.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final result = await _subsurfaceExporter.exportPending();
      if (!mounted) return;
      if (result == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No new dives to upload.')),
        );
        return;
      }
      debugPrint(
          'Subsurface export wrote ${result.diveCount} dives to ${result.filePath}');
      final share = await Share.shareXFiles(
        [XFile(result.filePath)],
        text: 'CCRLog dives (${result.diveCount})',
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      if (share.status == ShareResultStatus.success) {
        await _subsurfaceExporter.markExported(result.diveIds);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Uploaded ${result.diveCount} dives.')),
        );
        await _diveListNotifier.loadDives();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Upload cancelled.')),
        );
      }
    } catch (e, st) {
      debugPrint('Subsurface upload failed: $e\n$st');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CCRLog'),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Upload to Subsurface',
              icon: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              onPressed: _uploading ? null : _onUploadToSubsurface,
            ),
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(notifier: widget.settingsNotifier),
                ));
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DiveListScreen(
            notifier: _diveListNotifier,
            diveDao: _diveDao,
            annotationsDao: _diveAnnotationsDao,
            equipmentDao: _equipmentDao,
            settingsNotifier: widget.settingsNotifier,
          ),
          ImportScreen(notifier: _importNotifier, onViewDives: _onViewDives),
          EquipmentLandingScreen(
            dao: _equipmentDao,
            diveDao: _diveDao,
            annotationsDao: _diveAnnotationsDao,
          ),
          SettingsScreen(notifier: widget.settingsNotifier),
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
