import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// The events Sentry would have sent during a test. They are kept here and
/// dropped before any transport sees them.
class SentryCapture {
  SentryCapture._();

  final List<SentryEvent> events = [];

  /// Waits until [count] events have been captured; Sentry hands them over
  /// asynchronously.
  Future<List<SentryEvent>> waitFor(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (events.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('expected $count Sentry events, got ${events.length}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return events;
  }
}

/// Starts the Sentry SDK for the rest of the test (closed in tear-down), as
/// `main.dart` does in release builds, with a fake DSN. [beforeSend] runs
/// first, as the app's own would; the events it lets through are captured.
Future<SentryCapture> startSentryCapture({
  BeforeSendCallback? beforeSend,
}) async {
  final capture = SentryCapture._();
  await Sentry.init((options) {
    options.dsn = 'https://public@sentry.invalid/1';
    options.sendClientReports = false;
    options.beforeSend = (event, hint) async {
      final kept = beforeSend == null ? event : await beforeSend(event, hint);
      if (kept != null) capture.events.add(kept);
      return null;
    };
  });
  addTearDown(Sentry.close);
  return capture;
}
