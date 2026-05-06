import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/ui/screens/sites_map_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets('SitesMapScreen builds with markers and AppBar title',
      (tester) async {
    await _withStubbedHttp(() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = DiveAnnotationsDao(db);

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

      await tester.pumpWidget(MaterialApp(
        home: SitesMapScreen(dao: dao, currentLat: 51.5, currentLon: 4.0),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dive sites'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byIcon(Icons.location_pin), findsNWidgets(2));
    });
  });

  testWidgets('SitesMapScreen shows empty map when no sites', (tester) async {
    await _withStubbedHttp(() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = DiveAnnotationsDao(db);

      await tester.pumpWidget(MaterialApp(
        home: SitesMapScreen(dao: dao, currentLat: null, currentLon: null),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dive sites'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byIcon(Icons.location_pin), findsNothing);
    });
  });
}
