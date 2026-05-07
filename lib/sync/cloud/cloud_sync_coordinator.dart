/// Connects/disconnects the PowerSync database in step with auth state.
///
/// AuthService doesn't know about PowerSync — it just notifies listeners
/// on sign-in/sign-out. This coordinator listens to it, calls
/// `database.connect(connector:)` when signed in, `disconnect()` when not.
///
/// If the user is already signed in at app launch, [start] connects
/// immediately so the first sync doesn't wait for a fresh login.
library;

import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';

import 'auth_service.dart';
import 'ccrlogger_backend_connector.dart';

/// Thin abstraction over the parts of [PowerSyncDatabase] the coordinator
/// uses, so tests can inject a recording fake without faking the whole DB.
abstract class CloudSyncTarget {
  Future<void> connect(PowerSyncBackendConnector connector);
  Future<void> disconnect();
}

class PowerSyncCloudSyncTarget implements CloudSyncTarget {
  final PowerSyncDatabase _db;
  PowerSyncCloudSyncTarget(this._db);

  @override
  Future<void> connect(PowerSyncBackendConnector connector) =>
      _db.connect(connector: connector);

  @override
  Future<void> disconnect() => _db.disconnect();
}

class CloudSyncCoordinator {
  final CloudSyncTarget _target;
  final CcrloggerBackendConnector _connector;
  final AuthService _auth;
  bool _connected = false;

  CloudSyncCoordinator({
    required PowerSyncDatabase database,
    required CcrloggerBackendConnector connector,
    required AuthService authService,
  }) : this._withTarget(
          target: PowerSyncCloudSyncTarget(database),
          connector: connector,
          authService: authService,
        );

  CloudSyncCoordinator._withTarget({
    required CloudSyncTarget target,
    required CcrloggerBackendConnector connector,
    required AuthService authService,
  })  : _target = target,
        _connector = connector,
        _auth = authService;

  /// Test-only constructor — accepts a [CloudSyncTarget] fake directly.
  @visibleForTesting
  factory CloudSyncCoordinator.forTesting({
    required CloudSyncTarget target,
    required CcrloggerBackendConnector connector,
    required AuthService authService,
  }) =>
      CloudSyncCoordinator._withTarget(
        target: target,
        connector: connector,
        authService: authService,
      );

  /// Subscribe to [AuthService] and reconcile current state. Call once.
  void start() {
    _auth.addListener(_reconcile);
    // Run immediately so an already-signed-in user starts syncing on launch.
    _reconcile();
  }

  void dispose() {
    _auth.removeListener(_reconcile);
  }

  bool get isConnected => _connected;

  void _reconcile() {
    if (_auth.isSignedIn) {
      _connect();
    } else {
      _disconnect();
    }
  }

  Future<void> _connect() async {
    if (_connected) return;
    _connected = true;
    try {
      await _target.connect(_connector);
    } catch (e, st) {
      _connected = false;
      debugPrint('CloudSyncCoordinator.connect failed: $e\n$st');
    }
  }

  Future<void> _disconnect() async {
    if (!_connected) return;
    _connected = false;
    try {
      await _target.disconnect();
    } catch (e, st) {
      debugPrint('CloudSyncCoordinator.disconnect failed: $e\n$st');
    }
  }

  /// Forces a fresh PowerSync connection. Used to recover from stale
  /// WebSockets after the app was backgrounded / the Mac came back from
  /// sleep — the indicator can falsely report "connected" while the
  /// underlying socket is dead. No-op when signed out.
  Future<void> forceReconnect() async {
    if (!_auth.isSignedIn) return;
    await _disconnect();
    await _connect();
  }
}
