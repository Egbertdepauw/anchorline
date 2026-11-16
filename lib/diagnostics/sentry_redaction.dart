/// What the app sends to Sentry in place of an error. User information is
/// private: Sentry gets no serials, dive data or user data, and an error's
/// text can carry all three (a SQLite error quotes its statement and the
/// statement's parameters: ids, serials, the user id).
library;

import 'package:sentry_flutter/sentry_flutter.dart' show Scope, Sentry;
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
