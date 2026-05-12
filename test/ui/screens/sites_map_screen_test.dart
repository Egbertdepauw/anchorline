import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/ui/screens/sites_map_screen.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:ccrlogger/ui/widgets/map_layer_toggle.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

/// 1x1 transparent PNG used to silence map tile requests in widget tests.
final _stubPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

T _withStubbedHttp<T>(T Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _StubOverrides());

class _StubOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _StubClient();
}

class _StubClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest(url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubRequest implements HttpClientRequest {
  @override
  final Uri uri;
  _StubRequest(this.uri);

  @override
  HttpHeaders get headers => _StubHeaders();

  @override
  Future<HttpClientResponse> close() async => _StubResponse();

  @override
  Future<HttpClientResponse> get done => close();

  @override
  noSuchMethod(Invocation invocation) {}
}

class _StubResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _stubPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _StubHeaders();
  @override
  bool get isRedirect => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_stubPng).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  noSuchMethod(Invocation invocation) {}
}

class _StubHeaders implements HttpHeaders {
  @override
  noSuchMethod(Invocation invocation) {}
}

Future<DiveAnnotationsDao> buildDaoWithSites(
    List<({String diveId, double lat, double lon})> sites) async {
  final psDb = await openPowerSyncForTest();
  final dao = DiveAnnotationsDao(psDb, FakeSessionSource());
  final now = DateTime.now();
  for (final s in sites) {
    await dao.upsert(DiveAnnotation(
      diveId: s.diveId,
      siteName: s.diveId,
      siteLatitude: s.lat,
      siteLongitude: s.lon,
      createdAt: now,
      updatedAt: now,
    ));
  }
  return dao;
}

void main() {
  testWidgets('SitesMapScreen builds with markers and AppBar title',
      (tester) async {
    await _withStubbedHttp(() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      late final DiveAnnotationsDao dao;
      await tester.runAsync(() async {
        final psDb = await openPowerSyncForTest();
        dao = DiveAnnotationsDao(psDb, FakeSessionSource());
        final now = DateTime.now();
        await dao.upsert(DiveAnnotation(
          diveId: 'd1',
          siteName: 'Lagoon',
          siteLatitude: 51.5,
          siteLongitude: 4.0,
          createdAt: now,
          updatedAt: now,
        ));
        await dao.upsert(DiveAnnotation(
          diveId: 'd2',
          siteName: 'Reef',
          siteLatitude: 52.5,
          siteLongitude: 5.0,
          createdAt: now,
          updatedAt: now,
        ));
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: SitesMapScreen(dao: dao, currentLat: 51.5, currentLon: 4.0),
        ));
        // Sites are fetched in initState; give the future + setState a beat.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      expect(find.text('Dive sites'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      // Read the MarkerLayer config directly — flutter_map lazy-renders
      // off-viewport markers, so find.byIcon misses pins that aren't
      // currently visible. We want to verify the data made it into the
      // map regardless of viewport.
      final fm = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final ml = fm.children.whereType<MarkerLayer>().single;
      expect(ml.markers, hasLength(2));
    });
  });

  testWidgets('SitesMapScreen shows empty map when no sites', (tester) async {
    await _withStubbedHttp(() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      late final DiveAnnotationsDao dao;
      await tester.runAsync(() async {
        final psDb = await openPowerSyncForTest();
        dao = DiveAnnotationsDao(psDb, FakeSessionSource());
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: SitesMapScreen(dao: dao, currentLat: null, currentLon: null),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('Dive sites'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byIcon(Icons.location_pin), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // New tests for Task 5: zoom-to-dive, accent pin, marker count, toggle.
  // ---------------------------------------------------------------------------

  testWidgets('opens at zoom 14 centred on current dive when given',
      (tester) async {
    await _withStubbedHttp(() async {
      late final DiveAnnotationsDao dao;
      await tester.runAsync(() async {
        dao = await buildDaoWithSites([
          (diveId: 'd1', lat: 51.5, lon: 4.0),
          (diveId: 'd2', lat: 52.5, lon: 5.0),
        ]);
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: SitesMapScreen(dao: dao, currentLat: 51.5, currentLon: 4.0),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      // The screen must have rendered the map (not the loading spinner).
      expect(find.byType(FlutterMap), findsOneWidget);

      // Inspect the MapOptions that were passed to FlutterMap.
      final mapWidget =
          tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(mapWidget.options.initialCenter.latitude,
          closeTo(51.5, 0.001));
      expect(mapWidget.options.initialCenter.longitude,
          closeTo(4.0, 0.001));
      expect(mapWidget.options.initialZoom, 14.0);
    });
  });

  testWidgets('current pin renders in accent colour at size 44',
      (tester) async {
    await _withStubbedHttp(() async {
      late final DiveAnnotationsDao dao;
      await tester.runAsync(() async {
        dao = await buildDaoWithSites([
          (diveId: 'current', lat: 51.5, lon: 4.0),
          (diveId: 'other', lat: 52.5, lon: 5.0),
        ]);
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: SitesMapScreen(dao: dao, currentLat: 51.5, currentLon: 4.0),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      // Read markers from the MarkerLayer config rather than the
      // rendered viewport: at z=14 the other-site pin is off-screen.
      final fm = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final ml = fm.children.whereType<MarkerLayer>().single;
      expect(ml.markers, hasLength(2));

      final accentIcons = ml.markers
          .map((m) => m.child)
          .whereType<Icon>()
          .where((i) => i.color == AppColors.wreck.accentPrimary)
          .toList();
      expect(accentIcons, hasLength(1));
      expect(accentIcons.first.size, 44.0);
    });
  });

  testWidgets('zoom-out preserves other-site pins (4 total)', (tester) async {
    await _withStubbedHttp(() async {
      late final DiveAnnotationsDao dao;
      await tester.runAsync(() async {
        dao = await buildDaoWithSites([
          (diveId: 'current', lat: 51.5, lon: 4.0),
          (diveId: 's2', lat: 52.0, lon: 4.5),
          (diveId: 's3', lat: 53.0, lon: 5.0),
          (diveId: 's4', lat: 54.0, lon: 5.5),
        ]);
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: SitesMapScreen(dao: dao, currentLat: 51.5, currentLon: 4.0),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      // Same as above — read MarkerLayer config to count all 4 even
      // though only one is in the z=14 viewport.
      final fm = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final ml = fm.children.whereType<MarkerLayer>().single;
      expect(ml.markers, hasLength(4));
    });
  });

  testWidgets('layer toggle swaps to satellite TileLayer URL', (tester) async {
    await _withStubbedHttp(() async {
      late final DiveAnnotationsDao dao;
      await tester.runAsync(() async {
        dao = await buildDaoWithSites([
          (diveId: 'd1', lat: 51.5, lon: 4.0),
        ]);
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: SitesMapScreen(dao: dao, currentLat: 51.5, currentLon: 4.0),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      // Before tap: normal OSM tile URL.
      final tileBefore =
          tester.widget<TileLayer>(find.byType(TileLayer).first);
      expect(tileBefore.urlTemplate, osmTileUrl);

      // Tap the toggle.
      await tester.tap(find.byType(MapLayerToggle));
      await tester.pump();

      // After tap: satellite URL.
      final tileAfter =
          tester.widget<TileLayer>(find.byType(TileLayer).first);
      expect(tileAfter.urlTemplate, esriSatelliteTileUrl);
    });
  });
}
