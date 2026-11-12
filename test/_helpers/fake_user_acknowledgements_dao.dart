/// In-memory [UserAcknowledgementsDaoLike] for widget tests (no PowerSync
/// I/O, so it works under the fake clock of `testWidgets`).
library;

import 'dart:async';

import 'package:ccrlogger/data/db/user_acknowledgements_dao.dart';
import 'package:ccrlogger/ui/widgets/planner_warning.dart';

class FakeUserAcknowledgementsDao implements UserAcknowledgementsDaoLike {
  /// [plannerWarningAccepted] starts the fake with the current planner
  /// warning already accepted.
  FakeUserAcknowledgementsDao({bool plannerWarningAccepted = false}) {
    if (plannerWarningAccepted) {
      accepted.add((kPlannerWarningSubject, kPlannerWarningVersion));
    }
  }

  /// (subject, text_version) pairs accepted so far.
  final List<(String, int)> accepted = [];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<bool> isAccepted(String subject, int textVersion) async =>
      accepted.any((a) => a.$1 == subject && a.$2 >= textVersion);

  @override
  Future<void> accept(String subject, int textVersion) async {
    accepted.add((subject, textVersion));
    _changes.add(null);
  }

  /// Simulates an acceptance arriving by sync from another device.
  void acceptFromElsewhere(String subject, int textVersion) {
    accepted.add((subject, textVersion));
    _changes.add(null);
  }

  @override
  Stream<void> watchChanges() => _changes.stream;
}
