import 'package:sentry_flutter/sentry_flutter.dart' show Sentry, Scope;
import 'package:sqlite3/common.dart' show SqliteException;

/// Reports an import problem that is not the diver's doing (a rejected or
/// failed dive). [where] names the step: `download` or `bootstrap`.
typedef ImportProblemReporter = void Function(
    Object error, StackTrace? stack, String where);

/// A parse the import refused to write (no samples or no duration). Its own
/// type so the redacted Sentry event, which carries only the type name, says
/// what happened.
class UnusableParse implements Exception {
  const UnusableParse();

  @override
  String toString() => 'UnusableParse';
}

/// What Sentry gets in place of an import error: the error's type and, for a
/// SQLite error, its result code. Never its message: a database error's text
/// carries the statement and its parameters (serials, ids, the user id).
class ImportProblem implements Exception {
  final String errorType;
  final int? extendedResultCode;

  const ImportProblem(this.errorType, [this.extendedResultCode]);

  @override
  String toString() => extendedResultCode == null
      ? errorType
      : '$errorType (result code $extendedResultCode)';
}

/// The [ImportProblem] standing for [error].
Object redactImportError(Object error) => ImportProblem(
      error.runtimeType.toString(),
      error is SqliteException ? error.extendedResultCode : null,
    );

/// The production [ImportProblemReporter]: sends the redacted error and the
/// real stack trace to Sentry with the tag `import.where`. It adds no serial,
/// dive data or user data.
void reportImportProblemToSentry(
    Object error, StackTrace? stack, String where) {
  Sentry.captureException(
    redactImportError(error),
    stackTrace: stack,
    withScope: (Scope scope) => scope.setTag('import.where', where),
  );
}
