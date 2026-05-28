import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/db/dive_annotations_dao.dart';

/// Drives the Buddies list screen. Buddies aren't a table — they're the
/// distinct names across every dive annotation's `buddies_json` — so this
/// notifier loads aggregated [BuddyStat]s and exposes the bulk rename /
/// delete operations that span every dive a buddy is named on.
///
/// Mirrors [CylindersNotifier]: watch-subscription in the constructor
/// reloads on any `dive_annotations` change (including PowerSync pulls),
/// a `_disposed` guard prevents writes after teardown, and `dispose`
/// cancels the subscription.
class BuddiesNotifier extends ChangeNotifier {
  final DiveAnnotationsDao _dao;
  StreamSubscription<void>? _watchSub;
  bool _disposed = false;

  BuddiesNotifier(this._dao) {
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

  List<BuddyStat> _buddies = [];
  List<BuddyStat> get buddies => List.unmodifiable(_buddies);

  Future<void> load() async {
    if (_disposed) return;
    final list = await _dao.buddyStats();
    if (_disposed) return;
    _buddies = list;
    notifyListeners();
  }

  /// Renames (and merges, when the target already exists) buddy [from] →
  /// [to] across every dive. Returns the number of annotations changed.
  Future<int> rename(String from, String to) async {
    final changed = await _dao.renameBuddy(from, to);
    await load();
    return changed;
  }

  /// Removes buddy [name] from every dive that names them.
  Future<void> remove(String name) async {
    await _dao.deleteBuddy(name);
    await load();
  }
}
