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
    return ImportOutcome.inserted;
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
  _FakeSource(this.dives, {this.listGate, this.failList});

  final List<({DiveListing listing, ConvertedDive converted})> dives;
  final Completer<void>? listGate;
  final Object? failList;
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
  Future<void> close() async => closed++;
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
      now: () => DateTime(2026, 11, 17, 9, 5, 7),
      fitSourceFactory: ({required inputs, required workDir, required onProgress}) {
        s.onProgress = onProgress;
        lastWorkDir = workDir;
        return s;
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
    expect(lastWorkDir.path, '${temp.path}/fit-import-20261117-090507');
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
    await Future<void>.delayed(Duration.zero);
    expect(n.isFitReading, isTrue);

    n.cancelFitImport();
    expect(n.state, ImportFlowState.idle);
    expect(source.closed, 1);

    gate.complete();
    await f;
    expect(n.state, ImportFlowState.idle);
    expect(n.newDives, isEmpty);
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
