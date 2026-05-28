import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/db/dive_annotations_dao.dart';

/// Drives the Dive sites list. Sites aren't a table — they're the distinct
/// `site_name` values across every dive annotation — so this notifier loads
/// aggregated [SiteStat]s and exposes the bulk rename / delete operations
/// that span every dive a site is named on.
///
/// Mirrors [BuddiesNotifier]: watch-subscription in the constructor reloads
/// on any `dive_annotations` change (including PowerSync pulls), a
/// `_disposed` guard prevents writes after teardown, and `dispose` cancels
/// the subscription.
class SitesNotifier extends ChangeNotifier {
  final DiveAnnotationsDao _dao;
  StreamSubscription<void>? _watchSub;
  bool _disposed = false;

  SitesNotifier(this._dao) {
    _watchSub = _dao.watchChanges().listen(
      (_) async {
        if (_disposed) return;
        try {
          await load();
        } catch (_) {}
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _watchSub?.cancel();
    super.dispose();
  }

  List<SiteStat> _sites = [];
  List<SiteStat> get sites => List.unmodifiable(_sites);

  Future<void> load() async {
    if (_disposed) return;
    final list = await _dao.siteStats();
    if (_disposed) return;
    _sites = list;
    notifyListeners();
  }

  /// Renames (and merges, when the target already exists) site [from] → [to]
  /// across every dive. Returns the number of annotations changed.
  Future<int> rename(String from, String to) async {
    final changed = await _dao.renameSite(from, to);
    await load();
    return changed;
  }

  /// Clears site [name] from every dive that names it (name + coords).
  Future<void> remove(String name) async {
    await _dao.deleteSite(name);
    await load();
  }
}
