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
import 'package:ccrlogger/ui/screens/import_screen.dart';
import 'package:ccrlogger/ui/util/fit_picker.dart';
import 'package:ccrlogger/ui/widgets/garmin_files_help_sheet.dart';
import 'package:fit_reader/fit_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../../_helpers/fit_test_support.dart';

class _Dao implements DiveDao {
  @override
  Future<Set<String>> existingDiveIdsAmong(List<String> ids) async =>
      {'stored'}.intersection(ids.toSet());

  @override
  Future<Set<String>> alreadyDownloadedAmong(
    List<({String diveId, int startTimeSeconds, int diveNumber})> listings, {
    required String vendor,
    required int serial,
    Map<String, String> fingerprints = const {},
  }) async =>
      {};

  @override
  Future<({String id, String label})?> overlappingDiveFromOtherComputer({
    required int startSeconds,
    required int endSeconds,
    required String vendor,
    required int serial,
  }) async =>
      startSeconds == 5000 ? (id: 'p', label: 'Petrel 3') : null;

  @override
  Future<ImportOutcome> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
    bool matchSubsurfaceCopies = true,
  }) async =>
      ImportOutcome.inserted;

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
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _Source implements FitDownloadSource {
  _Source(this.listings);
  final List<DiveListing> listings;

  @override
  DcIdentity? get identity => null;
  @override
  bool get canListDives => true;
  @override
  ({String vendor, int serial})? watchOf(String diveId) =>
      (vendor: 'Garmin', serial: 1);

  @override
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint}) async =>
      listings;

  @override
  Stream<DiveSourceEvent> download(
      {List<DiveListing>? selection, Uint8List? sinceFingerprint}) async* {
    yield DiveSourceIdentified(DcIdentity(
      vendor: 'Garmin',
      product: 'Descent Mk3',
      serial: 1,
      family: -1,
      dcModel: ShearwaterModel.unknown,
      computerModel: 0,
      importStateKey: 'fit:1:1',
      modelLabel: 'Garmin Descent Mk3',
      serialLabel: '1',
      firmwareLabel: '',
    ));
    for (final l in selection!) {
      yield DiveSourceDive(
        listing: l,
        converted: rebuildFit(fitDive(), id: l.diveId),
        rawBlob: fitBlob(),
        fingerprint: l.fingerprint,
        parserVersion: kFitParserVersion,
      );
    }
    yield const DiveSourceFinished();
  }

  @override
  Future<void> close() async {}
}

DiveListing _l(String id, int start, {int number = 0}) => DiveListing(
      diveNumber: number,
      startTimestamp: start,
      endTimestamp: start + 3600,
      fingerprint: Uint8List.fromList([1]),
      diveId: id,
      maxDepthMeters: 32.5,
      durationSeconds: 2700,
      modelLabel: 'Garmin Descent Mk3',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImportNotifier n;
  final shares = <String>[];

  setUp(() {
    shares.clear();
    n = ImportNotifier(
      dao: _Dao(),
      importStateDao: _States(),
      equipmentDao: _Equip(),
      tempDir: () async => Directory.systemTemp,
      fitSourceFactory: ({required inputs, required workDir, required onProgress}) =>
          _Source([_l('stored', 1000), _l('over', 5000), _l('new', 9000)]),
    );
  });
  tearDown(() => n.dispose());

  Future<void> show(WidgetTester tester,
      {Future<List<FitInput>?> Function()? pick}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ImportScreen(
          notifier: n,
          onViewDives: () {},
          pickFilesFn: pick ?? () async => [const FitFileInput('/x/a.fit')],
          shareFitDiveFn: ({
            required diveId,
            required vendor,
            product,
            required loadRawBlob,
            origin,
          }) async {
            shares.add('$vendor/$product/$diveId');
            return null;
          },
        ),
      ),
    ));
  }

  testWidgets('idle shows "Import Garmin files…" and the help link opens the '
      'sheet', (tester) async {
    await show(tester);

    expect(find.text('Import Garmin files…'), findsOneWidget);
    expect(find.text('.fit files, or a Garmin Connect export (.zip)'),
        findsOneWidget);
    await tester.tap(find.text('Where do I find them?'));
    await tester.pumpAndSettle();

    expect(find.byType(GarminFilesHelpSheet), findsOneWidget);
    expect(find.textContaining('"Export Original"'), findsOneWidget);
    expect(find.textContaining('"Export Your Data"'), findsOneWidget);
    expect(find.textContaining('Garmin/Activity'), findsOneWidget);
    expect(find.textContaining('OpenMTP'), findsOneWidget);
  });

  testWidgets('manifest shows flags, depth, duration and model; flagged rows '
      'start unticked', (tester) async {
    await show(tester);
    await tester.tap(find.text('Import Garmin files…'));
    await tester.pumpAndSettle();

    expect(find.text('Already in Anchorline'), findsOneWidget);
    expect(find.text('Overlaps your Petrel 3 dive'), findsOneWidget);
    expect(find.textContaining('32.5 m'), findsWidgets);
    expect(find.textContaining('45 min'), findsWidgets);
    expect(find.textContaining('Garmin Descent Mk3'), findsWidgets);
    expect(find.text('1 of 3 selected'), findsOneWidget);
    expect(find.text('Import 1 dive'), findsOneWidget);

    // Ticking a flagged row adds it.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    expect(find.text('Import 2 dives'), findsOneWidget);
  });

  testWidgets('reading shows the file counts as text only', (tester) async {
    n = ImportNotifier(
      dao: _Dao(),
      importStateDao: _States(),
      equipmentDao: _Equip(),
      tempDir: () async => Directory.systemTemp,
      fitSourceFactory: ({required inputs, required workDir, required onProgress}) {
        onProgress(FitScanCounts(
            filesRead: 3,
            filesTotal: 12,
            dives: 2,
            otherActivities: 4,
            apnea: 1,
            unreadable: 0));
        return _HangingSource();
      },
    );
    await show(tester);
    await tester.tap(find.text('Import Garmin files…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Reading 3 of 12 files…'), findsOneWidget);
    expect(find.text('2 dives, 4 other files skipped, 1 apnea sessions skipped'),
        findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fit-cancel')));
    await tester.pump();
    expect(n.state, ImportFlowState.idle);
  });

  testWidgets('done shows "Not yet tested by us" and the share button for an '
      'unchecked model', (tester) async {
    await show(tester);
    await tester.tap(find.text('Import Garmin files…'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Import 1 dive'));
    await tester.pumpAndSettle();

    expect(find.text('Imported 1 dives'), findsOneWidget);
    expect(find.text('Not yet tested by us: Garmin Descent Mk3'),
        findsOneWidget);
    await tester.tap(find.text('Send us one of these dives'));
    await tester.pump();
    expect(shares, ['Garmin/Descent Mk3/new']);
  });

  testWidgets('a failed pick for lack of space shows the free-space message',
      (tester) async {
    await show(tester,
        pick: () async => throw Exception('write failed: No space left'));
    await tester.tap(find.text('Import Garmin files…'));
    await tester.pumpAndSettle();

    expect(find.text('Not enough free space to read this file.'),
        findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  test('the free-space message names the size when it is known', () {
    expect(fitNoSpaceMessage(12 * 1024 * 1024),
        'Not enough free space to read this file. It needs about 12 MB.');
    expect(isNoSpaceError(Exception('ENOSPC')), isTrue);
    expect(isNoSpaceError(Exception('other')), isFalse);
  });
}

class _HangingSource extends _Source {
  _HangingSource() : super(const []);
  @override
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint}) =>
      Completer<List<DiveListing>>().future;
}
