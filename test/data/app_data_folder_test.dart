import 'dart:io';

import 'package:ccrlogger/data/app_data_folder.dart';
import 'package:ccrlogger/data/app_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('appDataLocationFor', () {
    const windowsEnv = {
      'LOCALAPPDATA': r'C:\Users\diver\AppData\Local',
      'APPDATA': r'C:\Users\diver\AppData\Roaming',
    };

    test('Windows keeps data in the per-app Local AppData folder', () {
      final location = appDataLocationFor(
        operatingSystem: 'windows',
        environment: windowsEnv,
        nightly: false,
      );
      expect(
        location.folder,
        r'C:\Users\diver\AppData\Local\De Spaankamer\Anchorline',
      );
      expect(location.movesFromDocuments, isTrue);
    });

    test('Windows nightly gets its own folder and leaves Documents alone', () {
      final location = appDataLocationFor(
        operatingSystem: 'windows',
        environment: windowsEnv,
        nightly: true,
      );
      expect(
        location.folder,
        r'C:\Users\diver\AppData\Local\De Spaankamer\Anchorline Nightly',
      );
      expect(location.movesFromDocuments, isFalse);
    });

    test('Windows without LOCALAPPDATA fails instead of guessing', () {
      expect(
        () => appDataLocationFor(
          operatingSystem: 'windows',
          environment: const {},
          nightly: false,
        ),
        throwsStateError,
      );
    });

    test('Linux uses XDG_DATA_HOME', () {
      final location = appDataLocationFor(
        operatingSystem: 'linux',
        environment: const {
          'XDG_DATA_HOME': '/data/xdg',
          'HOME': '/home/diver',
        },
        nightly: false,
      );
      expect(location.folder, '/data/xdg/nl.despaankamer.ccrlogger');
      expect(location.movesFromDocuments, isTrue);
    });

    for (final xdg in [null, '', 'relative/path']) {
      test('Linux falls back to ~/.local/share when XDG_DATA_HOME is '
          '${xdg == null ? 'unset' : '"$xdg"'}', () {
        final location = appDataLocationFor(
          operatingSystem: 'linux',
          environment: {
            'HOME': '/home/diver',
            'XDG_DATA_HOME': ?xdg,
          },
          nightly: false,
        );
        expect(
          location.folder,
          '/home/diver/.local/share/nl.despaankamer.ccrlogger',
        );
      });
    }

    test('Linux nightly gets its own folder and leaves Documents alone', () {
      final location = appDataLocationFor(
        operatingSystem: 'linux',
        environment: const {'HOME': '/home/diver'},
        nightly: true,
      );
      expect(
        location.folder,
        '/home/diver/.local/share/nl.despaankamer.ccrlogger.nightly',
      );
      expect(location.movesFromDocuments, isFalse);
    });

    test('Linux without HOME or XDG_DATA_HOME fails instead of guessing', () {
      expect(
        () => appDataLocationFor(
          operatingSystem: 'linux',
          environment: const {},
          nightly: false,
        ),
        throwsStateError,
      );
    });

    for (final os in ['macos', 'ios', 'android']) {
      for (final nightly in [false, true]) {
        test('$os keeps using its Documents folder '
            '(${nightly ? 'nightly' : 'release'})', () {
          final location = appDataLocationFor(
            operatingSystem: os,
            environment: const {'HOME': '/Users/diver'},
            nightly: nightly,
          );
          expect(location.folder, isNull);
          expect(location.movesFromDocuments, isFalse);
        });
      }
    }
  });

  group('AppDataPaths.inFolder', () {
    test('names every file the app keeps', () {
      final paths = AppDataPaths.inFolder('/data');
      expect(paths.driftDatabase, p.join('/data', 'ccrlogger.sqlite'));
      expect(paths.powerSyncDatabase, p.join('/data', 'powersync.db'));
      expect(paths.subsurfaceClone, p.join('/data', 'subsurface_clone'));
      expect(paths.bleDebugLog, p.join('/data', 'ble-debug.log'));
      expect(paths.bleDebugLogPrevious, p.join('/data', 'ble-debug.log.prev'));
      expect(paths.migration, isNull);
    });
  });

  group('resolveAppDataPaths', () {
    late Directory tmp;
    late String documents;
    late String xdgDataHome;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ccrlog_app_data_');
      documents = p.join(tmp.path, 'Documents');
      xdgDataHome = p.join(tmp.path, 'xdg');
      Directory(documents).createSync();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Map<String, String> linuxEnv() => {
      'HOME': tmp.path,
      'XDG_DATA_HOME': xdgDataHome,
    };

    test('Linux release moves existing data out of Documents', () async {
      File(p.join(documents, 'ccrlogger.sqlite')).writeAsStringSync('dives');

      final paths = await resolveAppDataPaths(
        operatingSystem: 'linux',
        environment: linuxEnv(),
        nightly: false,
        documentsFolder: () async => documents,
      );

      final folder = p.join(xdgDataHome, 'nl.despaankamer.ccrlogger');
      expect(paths.driftDatabase, p.join(folder, 'ccrlogger.sqlite'));
      expect(File(paths.driftDatabase).readAsStringSync(), 'dives');
      expect(File(p.join(documents, 'ccrlogger.sqlite')).existsSync(), isFalse);
      expect(
        paths.migration!.outcomes[AppDataItem.driftDatabase]!.status,
        AppDataMoveStatus.moved,
      );
    });

    test('Linux nightly never touches release data in Documents', () async {
      File(p.join(documents, 'ccrlogger.sqlite')).writeAsStringSync('dives');
      var askedForDocuments = false;

      final paths = await resolveAppDataPaths(
        operatingSystem: 'linux',
        environment: linuxEnv(),
        nightly: true,
        documentsFolder: () async {
          askedForDocuments = true;
          return documents;
        },
      );

      final folder = p.join(xdgDataHome, 'nl.despaankamer.ccrlogger.nightly');
      expect(paths.driftDatabase, p.join(folder, 'ccrlogger.sqlite'));
      expect(Directory(folder).existsSync(), isTrue);
      expect(File(paths.driftDatabase).existsSync(), isFalse);
      expect(askedForDocuments, isFalse);
      expect(
        File(p.join(documents, 'ccrlogger.sqlite')).readAsStringSync(),
        'dives',
      );
    });

    test(
      'Linux without a Documents folder starts in the data folder',
      () async {
        final paths = await resolveAppDataPaths(
          operatingSystem: 'linux',
          environment: linuxEnv(),
          nightly: false,
          documentsFolder: () async => null,
        );

        final folder = p.join(xdgDataHome, 'nl.despaankamer.ccrlogger');
        expect(paths.powerSyncDatabase, p.join(folder, 'powersync.db'));
        expect(Directory(folder).existsSync(), isTrue);
        expect(paths.migration, isNull);
      },
    );

    test('macOS keeps using Documents and moves nothing', () async {
      File(p.join(documents, 'ccrlogger.sqlite')).writeAsStringSync('dives');

      final paths = await resolveAppDataPaths(
        operatingSystem: 'macos',
        environment: {'HOME': tmp.path},
        nightly: false,
        documentsFolder: () async => documents,
      );

      expect(paths.driftDatabase, p.join(documents, 'ccrlogger.sqlite'));
      expect(File(paths.driftDatabase).readAsStringSync(), 'dives');
      expect(paths.migration, isNull);
    });
  });
}
