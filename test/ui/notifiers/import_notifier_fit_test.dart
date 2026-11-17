import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/fit/fit_file_source.dart';
import 'package:ccrlogger/devices/fit/fit_inputs.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:ccrlogger/sync/cloud/usage_tracker.dart' show UsageTracker;
import 'package:fit_reader/fit_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../_helpers/fit_test_support.dart';

class _Dao implements DiveDao {
  final Set<String> stored = {};
  final Set<String> downloaded = {};
  final Map<String, String> overlaps = {};
  final imported = <(ConvertedDive, Uint8List, int)>[];
  ImportOutcome outcome = ImportOutcome.inserted;
  final alreadyCalls = <({String vendor, int serial})>[];

  @override
  Future<Set<String>> existingDiveIdsAmong(List<String> ids) async =>
      {for (final i in ids) if (stored.contains(i)) i};

  @override
  Future<Set<String>> alreadyDownloadedAmong(
    List<({String diveId, int startTimeSeconds, int diveNumber})> listings, {
    required String vendor,
    required int serial,
    Map<String, String> fingerprints = const {},
  }) async {
    alreadyCalls.add((vendor: vendor, serial: serial));
    return {for (final l in listings) if (downloaded.contains(l.diveId)) l.diveId};
  }

  @override
  Future<({String id, String label})?> overlappingDiveFromOtherComputer({
    required int startSeconds,
    required int endSeconds,
    required String vendor,
    required int serial,
  }) async {
    final label = overlaps[startSeconds.toString()];
    return label == null ? null : (id: 'x', label: label);
  }

  @override
  Future<ImportOutcome> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
    bool matchSubsurfaceCopies = true,
  }) async {
    imported.add((converted, rawBlob, parserVersion));
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Equip implements EquipmentDao {
  @override
  Future<String> upsertDiveComputer({
    required String vendor,
    String? product,
    required int serial,
    required int model,
    int? firmwareVersion,
    int? family,
    int? modelCode,
  }) async =>
      'dc';

  @override
  Future<void> applyScrubberEvents({
    required DateTime? scrubberResetAt,
    required int dcSerial,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _States implements ImportStateDao {
  final saved = <String>[];

  @override
  Future<void> saveLastFingerprint(String key, Uint8List fp) async =>
      saved.add(key);

  @override
  Future<Uint8List?> getLastFingerprint(String key) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Tracker implements UsageTracker {
  final events = <(String, Map<String, Object?>?)>[];
  @override
  void track(String eventName, [Map<String, Object?>? properties]) =>
      events.add((eventName, properties));
}

DcIdentity _identity({String product = 'Descent Mk3', int serial = 111}) =>
    DcIdentity(
      vendor: 'Garmin',
      product: product,
      serial: serial,
      family: -1,
      dcModel: ShearwaterModel.unknown,
      computerModel: 0,
      importStateKey: 'fit:1:$serial',
      modelLabel: 'Garmin $product',
      serialLabel: '$serial',
      firmwareLabel: '',
    );

/// A source that lists [dives] (all of one watch) and downloads them.
class _FakeSource implements FitDownloadSource {
  _FakeSource(this.dives, {this.listGate, this.failList, this.closeGate});

  final List<({DiveListing listing, ConvertedDive converted})> dives;
  final Completer<void>? listGate;
  final Object? failList;
  final Completer<void>? closeGate;
  int closed = 0;
  void Function(FitScanCounts)? onProgress;

  @override
  DcIdentity? get identity => null;
  @override
  bool get canListDives => true;

  @override
  ({String vendor, int serial})? watchOf(String diveId) =>
      (vendor: 'Garmin', serial: 111);

  @override
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint}) async {
    onProgress?.call(FitScanCounts(filesRead: 1, filesTotal: 2, dives: 1));
    if (listGate != null) await listGate!.future;
    if (failList != null) throw failList!;
    return [for (final d in dives) d.listing];
  }

  @override
  Stream<DiveSourceEvent> download(
      {List<DiveListing>? selection, Uint8List? sinceFingerprint}) async* {
    yield DiveSourceIdentified(_identity());
    for (final l in selection ?? [for (final d in dives) d.listing]) {
      final d = dives.firstWhere((d) => d.listing.diveId == l.diveId);
      yield DiveSourceDive(
        listing: l,
        converted: d.converted,
        rawBlob: fitBlob(),
        fingerprint: l.fingerprint,
        parserVersion: kFitParserVersion,
      );
    }
    yield const DiveSourceFinished(
        importStateKey: 'fit:1:111', fingerprintToKeep: null);
  }

  @override
  Future<void> close() async {
    closed++;
    if (closeGate != null) await closeGate!.future;
  }
}

DiveListing _listing(String id, int start, {int number = 0}) => DiveListing(
      diveNumber: number,
      startTimestamp: start,
      endTimestamp: start + 3600,
      fingerprint: Uint8List.fromList([1]),
      diveId: id,
      maxDepthMeters: 30,
      durationSeconds: 3600,
      modelLabel: 'Garmin Descent Mk3',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Dao dao;
  late _States states;
  late _Tracker tracker;
  late _FakeSource source;
  late ImportNotifier n;
  late Directory temp;
  final reports = <(Object, String)>[];

  ({DiveListing listing, ConvertedDive converted}) dive(String id, int start) =>
      (listing: _listing(id, start), converted: rebuildFit(fitDive(), id: id));

  void build(_FakeSource s) {
    source = s;
    n = ImportNotifier(
      dao: dao,
      importStateDao: states,
      equipmentDao: _Equip(),
      usageTracker: tracker,
      reporter: (e, st, where) => reports.add((e, where)),
      tempDir: () async => temp,
      pickedCopyRoots: () async => [temp],
      fitSourceFactory: ({required inputs, required workDir, required onProgress}) {
        // Tests may swap [source] for a newer import.
        source.onProgress = onProgress;
        lastWorkDir = workDir;
        return source;
      },
    );
  }

  setUp(() {
    dao = _Dao();
    states = _States();
    tracker = _Tracker();
    reports.clear();
    temp = Directory.systemTemp.createTempSync('fit_notifier_test');
  });
  tearDown(() {
    n.dispose();
    temp.deleteSync(recursive: true);
  });

  const inputs = [FitFileInput('/x/a.fit')];

  test('importFitFiles lists dives and goes to the manifest with counts',
      () async {
    build(_FakeSource([dive('a', 1000), dive('b', 9000)]));
    final f = n.importFitFiles(inputs);
    expect(n.state, ImportFlowState.readingManifest);
    expect(n.isFitReading, isTrue);
    await f;

    expect(n.isFitReading, isFalse);
    expect(n.state, ImportFlowState.readingManifest);
    expect(n.newDives.map((l) => l.diveId), ['a', 'b']);
    expect(n.fitCounts!.filesRead, 1);
    expect(n.fitCounts!.filesTotal, 2);
    expect(n.newDives.every((l) => l.preselected && l.flag == null), isTrue);
    // A random name inside the temp folder, with the purge prefix.
    expect(lastWorkDir.parent.path, temp.path);
    expect(lastWorkDir.uri.pathSegments.where((x) => x.isNotEmpty).last,
        startsWith('fit-import-'));
    expect(lastWorkDir.uri.pathSegments.where((x) => x.isNotEmpty).last,
        isNot(matches(RegExp(r'^fit-import-\d{8}-\d{6}$'))));
  });

  test('a stored dive is flagged "Already in Anchorline" and unticked',
      () async {
    dao.stored.add('a');
    dao.downloaded.add('b');
    build(_FakeSource([dive('a', 1000), dive('b', 9000), dive('c', 20000)]));
    await n.importFitFiles(inputs);

    final byId = {for (final l in n.newDives) l.diveId: l};
    expect(byId['a']!.flag, 'Already in Anchorline');
    expect(byId['a']!.preselected, isFalse);
    expect(byId['b']!.flag, 'Already in Anchorline');
    expect(byId['b']!.preselected, isFalse);
    expect(byId['c']!.flag, isNull);
    expect(byId['c']!.preselected, isTrue);
    // Grouped per watch: one call, with that watch's brand and serial.
    expect(dao.alreadyCalls, [(vendor: 'Garmin', serial: 111)]);
  });

  test('a dive overlapping a Petrel dive is flagged "Overlaps your Petrel 3 '
      'dive" and unticked', () async {
    dao.overlaps['1000'] = 'Petrel 3';
    build(_FakeSource([dive('a', 1000), dive('b', 9000)]));
    await n.importFitFiles(inputs);

    final a = n.newDives.firstWhere((l) => l.diveId == 'a');
    expect(a.flag, 'Overlaps your Petrel 3 dive');
    expect(a.preselected, isFalse);
    expect(n.newDives.firstWhere((l) => l.diveId == 'b').preselected, isTrue);
  });

  test('importing the ticked dives commits each through importDive with the '
      'FIT version', () async {
    build(_FakeSource([dive('a', 1000), dive('b', 9000)]));
    await n.importFitFiles(inputs);
    await n.downloadAll([n.newDives.first]);

    expect(n.state, ImportFlowState.done);
    expect(n.downloadedCount, 1);
    expect(dao.imported, hasLength(1));
    expect(dao.imported.single.$3, kFitParserVersion);
    expect(FitEnvelope.decode(dao.imported.single.$2).fit, fitFixtureBytes());
    expect(tracker.events.single.$1, 'import_completed');
    expect(tracker.events.single.$2!['engine'], 'fit');
    expect(tracker.events.single.$2!['vendor'], 'Garmin');
  });

  test('no fingerprint is saved after a FIT import', () async {
    build(_FakeSource([dive('a', 1000), dive('b', 9000)]));
    await n.importFitFiles(inputs);
    await n.downloadAll();

    expect(n.state, ImportFlowState.done);
    expect(n.downloadedCount, 2);
    expect(states.saved, isEmpty);
  });

  test('untestedModels lists Descent Mk3 when kCheckedFitModels lacks it',
      () async {
    build(_FakeSource([dive('a', 1000)]));
    await n.importFitFiles(inputs);
    await n.downloadAll();

    expect(n.untestedModels, ['Garmin Descent Mk3']);
    expect(n.fitShareDive!.diveId, 'a');
    expect(n.fitShareDive!.vendor, 'Garmin');
    expect(n.fitShareDive!.product, 'Descent Mk3');
  });

  test('the source is closed after done, error and reset', () async {
    build(_FakeSource([dive('a', 1000)]));
    await n.importFitFiles(inputs);
    await n.downloadAll();
    expect(n.state, ImportFlowState.done);
    expect(source.closed, greaterThanOrEqualTo(1));

    // Reset closes it too (and is safe after the download closed it).
    final before = source.closed;
    n.reset();
    expect(source.closed, before + 1);
    expect(n.state, ImportFlowState.idle);
    expect(n.untestedModels, isEmpty);

    // Error while listing.
    build(_FakeSource([], failList: const FormatException('secret.fit')));
    await n.importFitFiles(inputs);
    expect(n.state, ImportFlowState.error);
    expect(n.errorMessage, isNot(contains('secret')));
    expect(source.closed, 1);
    // Reported with where, redacted by the reporter's own contract.
    expect(reports.single.$2, 'download');
  });

  test('cancelling while the files are read closes the source and goes to '
      'idle', () async {
    final gate = Completer<void>();
    build(_FakeSource([dive('a', 1000)], listGate: gate));
    final f = n.importFitFiles(inputs);
    // The work folder is made with real file I/O first.
    while (source.onProgress == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(n.isFitReading, isTrue);

    n.cancelFitImport();
    expect(n.state, ImportFlowState.idle);
    expect(source.closed, 1);

    gate.complete();
    await f;
    expect(n.state, ImportFlowState.idle);
    expect(n.newDives, isEmpty);
  });

  test('a failure while reading, and a failed pick, report import_failed',
      () async {
    build(_FakeSource([], failList: const FormatException('secret.fit')));
    await n.importFitFiles(inputs);
    final e = tracker.events.single;
    expect(e.$1, 'import_failed');
    expect(e.$2!['engine'], 'fit');
    expect(e.$2!['reason'], 'Could not read these files.');

    n.failFitPick('Some message');
    expect(tracker.events.last.$1, 'import_failed');
    expect(tracker.events.last.$2!['engine'], 'fit');
    expect(tracker.events, hasLength(2));
  });

  test('a dive that refreshed a stored copy is no share candidate', () async {
    dao.outcome = ImportOutcome.refreshed;
    build(_FakeSource([dive('a', 1000)]));
    await n.importFitFiles(inputs);
    await n.downloadAll();

    expect(n.downloadedCount, 1);
    expect(n.fitShareDive, isNull);
    // The model still counts as untested.
    expect(n.untestedModels, ['Garmin Descent Mk3']);
  });

  test("the picker's cache copies are deleted after the import, and only "
      'those inside the cache', () async {
    final copy = File('${temp.path}/file_picker/a.fit')
      ..createSync(recursive: true);
    final elsewhere = Directory.systemTemp.createTempSync('fit_keep');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final kept = File('${elsewhere.path}/b.fit')..writeAsBytesSync([1]);
    build(_FakeSource([dive('a', 1000)]));
    await n.importFitFiles([FitFileInput(copy.path), FitFileInput(kept.path)]);
    expect(copy.existsSync(), isTrue);
    await n.downloadAll();

    expect(copy.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
  });

  test('a reset deletes the cache copies too', () async {
    final copy = File('${temp.path}/file_picker/a.fit')
      ..createSync(recursive: true);
    build(_FakeSource([dive('a', 1000)]));
    await n.importFitFiles([FitFileInput(copy.path)]);
    n.reset();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(copy.existsSync(), isFalse);
  });

  test('a cancel before the work folder is known stops the scan and leaves '
      'no source behind', () async {
    final gate = Completer<Directory>();
    var made = 0;
    final s = _FakeSource([dive('a', 1000)]);
    n = ImportNotifier(
      dao: dao,
      importStateDao: states,
      equipmentDao: _Equip(),
      reporter: (e, st, where) {},
      tempDir: () => gate.future,
      pickedCopyRoots: () async => [temp],
      fitSourceFactory: ({required inputs, required workDir, required onProgress}) {
        made++;
        return s;
      },
    );
    final f = n.importFitFiles(inputs);
    await Future<void>.delayed(Duration.zero);
    n.cancelFitImport();
    gate.complete(temp);
    await f;

    expect(made, 0);
    expect(n.state, ImportFlowState.idle);
    expect(n.newDives, isEmpty);
  });

  test('the copies of a finished import are released, a newer import\'s '
      'are not', () async {
    final a = File('${temp.path}/file_picker/a.fit')
      ..createSync(recursive: true);
    final b = File('${temp.path}/file_picker/b.fit')
      ..createSync(recursive: true);
    final closeGate = Completer<void>();
    build(_FakeSource([dive('a', 1000)], closeGate: closeGate));
    await n.importFitFiles([FitFileInput(a.path)]);
    final download = n.downloadAll();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A Retry during the source's close starts a newer import.
    n.reset();
    source = _FakeSource([dive('b', 2000)]);
    await n.importFitFiles([FitFileInput(b.path)]);
    closeGate.complete();
    await download;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue);
  });

  test('desktop has no copy roots, so a file picked from the temp folder is '
      'never deleted', () async {
    expect(await defaultFitCopyRoots(desktop: true), isEmpty);

    final picked = File('${temp.path}/mine.fit')..writeAsBytesSync([1]);
    n = ImportNotifier(
      dao: dao,
      importStateDao: states,
      equipmentDao: _Equip(),
      reporter: (e, st, where) {},
      tempDir: () async => temp,
      pickedCopyRoots: () => defaultFitCopyRoots(desktop: true),
      fitSourceFactory: ({required inputs, required workDir, required onProgress}) =>
          _FakeSource([dive('a', 1000)]),
    );
    await n.importFitFiles([FitFileInput(picked.path)]);
    await n.downloadAll();
    expect(picked.existsSync(), isTrue);
  });

  test('a failed pick goes to the error state', () {
    build(_FakeSource([]));
    n.failFitPick('Not enough free space to read this file.');
    expect(n.state, ImportFlowState.error);
    expect(n.isFitImport, isTrue);
    expect(n.errorMessage, 'Not enough free space to read this file.');
  });
}

late Directory lastWorkDir;
