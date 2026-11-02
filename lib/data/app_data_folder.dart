/// The one place that decides where the app keeps its local files: the two
/// SQLite databases, the Subsurface clone and the BLE debug log.
///
/// - **macOS, iOS, Android:** the platform's Documents folder, which is
///   already private to the app (the sandbox container, or the app's own
///   storage). Unchanged.
/// - **Windows:** `%LOCALAPPDATA%\De Spaankamer\Anchorline`. Local, not
///   Roaming (where path_provider's application support folder lives): the
///   PowerSync replica and the git clone are large and belong to one
///   device. It is also where the attachment cache already lives.
/// - **Linux:** `$XDG_DATA_HOME/nl.despaankamer.ccrlogger`, normally
///   `~/.local/share/...`. Pinned here rather than taken from the GTK
///   application id, so the data stays put when that id changes.
///
/// Early Windows and Linux builds used the user's own Documents folder;
/// [appDataPaths] moves that data on first start (`app_data_migration.dart`).
///
/// Desktop nightly builds (`--dart-define=BUILD_CHANNEL=nightly`, see the
/// cloud-builds spec §6) get a folder of their own and never touch the
/// release data in Documents. Phone nightlies replace the store app, so
/// they keep its data, as does the macOS nightly, whose own bundle id
/// already gives it a separate container.
///
/// Preferences, secure storage and the attachment cache are not decided
/// here: their plugins pick their own per-app folders.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_data_migration.dart';

/// Where this platform keeps the app's data.
class AppDataLocation {
  const AppDataLocation({
    required this.folder,
    required this.movesFromDocuments,
  });

  /// The per-app data folder, or null for "the platform's Documents
  /// folder" (macOS, iOS, Android).
  final String? folder;

  /// Whether data left in Documents by earlier builds moves to [folder].
  final bool movesFromDocuments;
}

const _windowsCompany = 'De Spaankamer';
const _windowsProduct = 'Anchorline';
const _linuxAppId = 'nl.despaankamer.ccrlogger';

/// Picks the data folder for [operatingSystem] (a `Platform.operatingSystem`
/// value). Throws [StateError] when the environment lacks what the choice
/// needs: guessing a different folder would look like lost data.
AppDataLocation appDataLocationFor({
  required String operatingSystem,
  required Map<String, String> environment,
  required bool nightly,
}) {
  switch (operatingSystem) {
    case 'windows':
      final localAppData = environment['LOCALAPPDATA'];
      if (localAppData == null || localAppData.isEmpty) {
        throw StateError('LOCALAPPDATA is not set');
      }
      return AppDataLocation(
        folder: p.windows.join(
          localAppData,
          _windowsCompany,
          nightly ? '$_windowsProduct Nightly' : _windowsProduct,
        ),
        movesFromDocuments: !nightly,
      );
    case 'linux':
      return AppDataLocation(
        folder: p.posix.join(
          _xdgDataHome(environment),
          nightly ? '$_linuxAppId.nightly' : _linuxAppId,
        ),
        movesFromDocuments: !nightly,
      );
    default:
      return const AppDataLocation(folder: null, movesFromDocuments: false);
  }
}

/// `$XDG_DATA_HOME`, or its default `$HOME/.local/share` when it is unset,
/// empty or relative (the XDG Base Directory spec says to ignore those).
String _xdgDataHome(Map<String, String> environment) {
  final xdg = environment['XDG_DATA_HOME'];
  if (xdg != null && p.posix.isAbsolute(xdg)) return xdg;
  final home = environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('Neither XDG_DATA_HOME nor HOME is set');
  }
  return p.posix.join(home, '.local', 'share');
}

/// Full paths of the app's local files for this launch.
class AppDataPaths {
  AppDataPaths._(String Function(AppDataItem item) folderOf, {this.migration})
    : driftDatabase = _path(folderOf, AppDataItem.driftDatabase),
      powerSyncDatabase = _path(folderOf, AppDataItem.powerSyncDatabase),
      subsurfaceClone = _path(folderOf, AppDataItem.subsurfaceClone),
      bleDebugLog = _path(folderOf, AppDataItem.bleDebugLog),
      bleDebugLogPrevious = p.join(
        folderOf(AppDataItem.bleDebugLog),
        AppDataItem.bleDebugLog.companionNames.single,
      );

  /// Everything in one folder.
  factory AppDataPaths.inFolder(String folder) => AppDataPaths._((_) => folder);

  /// Each item where the migration left it: usually the data folder, but
  /// Documents for an item that could not be moved this time.
  factory AppDataPaths.fromMigration(AppDataMigrationReport report) =>
      AppDataPaths._(report.folderFor, migration: report);

  static String _path(
    String Function(AppDataItem) folderOf,
    AppDataItem item,
  ) => p.join(folderOf(item), item.fileName);

  /// Drift database (`ccrlogger.sqlite`).
  final String driftDatabase;

  /// PowerSync database (`powersync.db`).
  final String powerSyncDatabase;

  /// Folder holding the local clone of the Subsurface Cloud repository.
  final String subsurfaceClone;

  /// BLE debug log, and the previous one it rotates into.
  final String bleDebugLog;
  final String bleDebugLogPrevious;

  /// What the move out of Documents did on this start, or null when this
  /// launch had nothing to move from (no Documents folder, nightly,
  /// macOS/iOS/Android).
  final AppDataMigrationReport? migration;
}

/// Build channel from the cloud-builds pipeline (spec §6). Local and
/// release builds don't set it.
const _buildChannel = String.fromEnvironment('BUILD_CHANNEL');

Future<AppDataPaths>? _appDataPaths;

/// The app's local file paths for this launch. The first call decides the
/// folder and, on Windows and Linux, moves data left in Documents by
/// earlier builds; later calls return the same result.
///
/// Await it before opening anything it names. It throws
/// [AppDataMigrationException] in the one case where neither folder holds
/// a complete database (see that class).
Future<AppDataPaths> appDataPaths() => _appDataPaths ??= resolveAppDataPaths(
  operatingSystem: Platform.operatingSystem,
  environment: Platform.environment,
  nightly: _buildChannel == 'nightly',
  documentsFolder: _documentsFolder,
);

Future<String?> _documentsFolder() async {
  try {
    return (await getApplicationDocumentsDirectory()).path;
  } on MissingPlatformDirectoryException {
    // Linux without xdg-user-dirs: no Documents folder, so nothing to move.
    return null;
  }
}

/// [appDataPaths] with its inputs passed in, for tests.
@visibleForTesting
Future<AppDataPaths> resolveAppDataPaths({
  required String operatingSystem,
  required Map<String, String> environment,
  required bool nightly,
  required Future<String?> Function() documentsFolder,
}) async {
  final location = appDataLocationFor(
    operatingSystem: operatingSystem,
    environment: environment,
    nightly: nightly,
  );

  final folder = location.folder;
  if (folder == null) {
    final documents = await documentsFolder();
    if (documents == null) throw StateError('No Documents folder');
    return AppDataPaths.inFolder(documents);
  }

  final documents = location.movesFromDocuments
      ? await documentsFolder()
      : null;
  if (documents == null) {
    await Directory(folder).create(recursive: true);
    return AppDataPaths.inFolder(folder);
  }

  final report = await AppDataMigration(
    documentsFolder: documents,
    dataFolder: folder,
  ).run();
  for (final problem in report.problems) {
    debugPrint('App data folder: $problem');
  }
  return AppDataPaths.fromMigration(report);
}
