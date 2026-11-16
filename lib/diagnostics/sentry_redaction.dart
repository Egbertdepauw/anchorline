/// What the app sends to Sentry in place of an error. User information is
/// private: Sentry gets no serials, dive data or user data, and an error's
/// text can carry all three (a SQLite error quotes its statement and the
/// statement's parameters: ids, serials, the user id).
library;

import 'package:sentry_flutter/sentry_flutter.dart'
    show Hint, Scope, Sentry, SentryEvent, SentryException;
import 'package:sqlite3/common.dart' show SqliteException;

/// An error with its text taken out: its type and, for a SQLite error, its
/// extended result code. The stack trace travels beside it, unchanged.
class RedactedError implements Exception {
  /// The type of the error this stands for, such as `SqliteException`.
  final String errorType;

  /// The SQLite extended result code, when the error was a SQLite one.
  final int? sqliteResultCode;

  const RedactedError(this.errorType, [this.sqliteResultCode]);

  @override
  bool operator ==(Object other) =>
      other is RedactedError &&
      other.errorType == errorType &&
      other.sqliteResultCode == sqliteResultCode;

  @override
  int get hashCode => Object.hash(errorType, sqliteResultCode);

  @override
  String toString() => sqliteResultCode == null
      ? errorType
      : '$errorType (result code $sqliteResultCode)';
}

/// The [RedactedError] standing for [error]. An error that is already
/// redacted comes back as it is.
RedactedError redactError(Object error) {
  if (error is RedactedError) return error;
  return RedactedError(
    error.runtimeType.toString(),
    error is SqliteException ? error.extendedResultCode : null,
  );
}

/// Sends [error], redacted, and its real [stack] to Sentry, with [tags] on
/// the event. Tags must be fixed strings from the code, never data. Sentry is
/// only started in release builds (`main.dart`); elsewhere this does nothing.
Future<void> captureRedactedException(
  Object error,
  StackTrace? stack, {
  Map<String, String> tags = const {},
}) async {
  await Sentry.captureException(
    redactError(error),
    stackTrace: stack,
    withScope: tags.isEmpty
        ? null
        : (Scope scope) async {
            for (final tag in tags.entries) {
              await scope.setTag(tag.key, tag.value);
            }
          },
  );
}

/// The app's Sentry `beforeSend` (`main.dart`). It drops the network noise
/// the Supabase SDK reports while it retries, then takes the error text out
/// of every event that is left ([redactEvent]), so an uncaught error is
/// redacted as a captured one is.
SentryEvent? sentryBeforeSend(SentryEvent event, Hint hint) {
  if (isRetriedNetworkNoise(event)) return null;
  return redactEvent(event);
}

/// Whether [event] is a network blip the SDKs recover from on their own.
/// `AuthRetryableFetchException` is the Supabase SDK's "this attempt failed,
/// I'll retry" signal; the device just went offline for a moment (cell tower
/// handoff, waking from sleep). Sentry would get events nobody can act on.
/// Reads the raw error, so it runs before [redactEvent].
bool isRetriedNetworkNoise(SentryEvent event) {
  final thrown = event.throwable?.toString() ??
      event.exceptions?.firstOrNull?.type ??
      '';
  return thrown.contains('AuthRetryableFetchException') ||
      thrown.contains('Failed host lookup') ||
      thrown.contains('SocketException');
}

/// Takes out of [event] the text its errors carry. Each exception keeps its
/// type, mechanism and stack trace, and its value becomes the [RedactedError]
/// text. The FlutterError details keep only the library: their context and
/// information lines describe the failing object (an image URL, a widget's
/// key). A captured message ([Sentry.captureMessage]) is the code's own text
/// and stays.
SentryEvent redactEvent(SentryEvent event) {
  for (final SentryException exception in event.exceptions ?? const []) {
    final Object? throwable = exception.throwable;
    exception.value =
        throwable == null ? null : redactError(throwable).toString();
  }
  final details = event.contexts[_flutterErrorDetails];
  if (details is Map) {
    final library = details['library'];
    if (library == null) {
      event.contexts.remove(_flutterErrorDetails);
    } else {
      event.contexts[_flutterErrorDetails] = <String, String>{
        'library': '$library',
      };
    }
  }
  return event;
}

/// The context sentry_flutter fills from a `FlutterErrorDetails`.
const _flutterErrorDetails = 'flutter_error_details';
