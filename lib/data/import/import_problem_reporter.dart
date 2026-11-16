import 'package:sentry_flutter/sentry_flutter.dart' show Sentry, Scope;

/// Reports an import problem that is not the diver's doing (a rejected or
/// failed dive). [where] names the step: `download` or `bootstrap`.
typedef ImportProblemReporter = void Function(
    Object error, StackTrace? stack, String where);

/// The production [ImportProblemReporter]: sends the exception to Sentry with
/// the tag `import.where`. It adds no serial, dive data or user data.
void reportImportProblemToSentry(
    Object error, StackTrace? stack, String where) {
  Sentry.captureException(
    error,
    stackTrace: stack,
    withScope: (Scope scope) => scope.setTag('import.where', where),
  );
}
