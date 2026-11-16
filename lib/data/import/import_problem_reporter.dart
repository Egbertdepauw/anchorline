import 'dart:async' show unawaited;

import '../../diagnostics/sentry_redaction.dart' show captureRedactedException;

/// Reports an import problem that is not the diver's doing (a rejected or
/// failed dive). [where] names the step: `download`, `bootstrap` or
/// `reparse`.
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

/// The production [ImportProblemReporter]: sends the error, redacted to its
/// type ([captureRedactedException]), and the real stack trace to Sentry with
/// the tag `import.where`. No serial, dive data or user data.
void reportImportProblemToSentry(
        Object error, StackTrace? stack, String where) =>
    unawaited(
        captureRedactedException(error, stack, tags: {'import.where': where}));
