import 'package:ccrlogger/diagnostics/sentry_redaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../_helpers/sentry_capture.dart';

/// A value that must never reach Sentry: it stands for a serial, an owner id
/// or dive data in an error's text.
const _secret = 'SERIAL-4242-owner-7f3a';

/// A real SQLite error whose text quotes the statement and its parameters.
SqliteException _sqliteErrorWithSecret() {
  final db = sqlite3.openInMemory();
  addTearDown(db.close);
  db.execute('CREATE TABLE dives (id TEXT PRIMARY KEY)');
  db.execute('INSERT INTO dives (id) VALUES (?)', [_secret]);
  try {
    db.execute('INSERT INTO dives (id) VALUES (?)', [_secret]);
  } on SqliteException catch (e) {
    return e;
  }
  fail('the duplicate insert did not throw');
}

void main() {
  group('redactError', () {
    test('keeps the type of the error and nothing of its text', () {
      final redacted = redactError(StateError('dive $_secret not found'));

      expect(redacted.errorType, 'StateError');
      expect(redacted.sqliteResultCode, isNull);
      expect(redacted.toString(), 'StateError');
    });

    test('keeps a SQLite error\'s result code, not its statement', () {
      final error = _sqliteErrorWithSecret();
      expect(error.toString(), contains(_secret),
          reason: 'the raw error carries the parameter');

      final redacted = redactError(error);

      expect(redacted.errorType, 'SqliteException');
      expect(redacted.sqliteResultCode, error.extendedResultCode);
      expect(redacted.toString(), isNot(contains(_secret)));
      expect(redacted.toString(),
          'SqliteException (result code ${error.extendedResultCode})');
    });

    test('an error that is already redacted comes back as it is', () {
      const redacted = RedactedError('SqliteException', 1555);
      expect(identical(redactError(redacted), redacted), isTrue);
    });
  });

  group('captureRedactedException', () {
    test('the event has the type and the real stack, not the text', () async {
      final sentry = await startSentryCapture();
      final error = _sqliteErrorWithSecret();
      final stack = StackTrace.current;

      await captureRedactedException(error, stack,
          tags: const {'where': 'test'});

      final event = (await sentry.waitFor(1)).single;
      final exception = event.exceptions!.single;
      expect(exception.type, 'RedactedError');
      expect(exception.value,
          'SqliteException (result code ${error.extendedResultCode})');
      expect(exception.stackTrace?.frames, isNotEmpty);
      expect(
        exception.stackTrace!.frames.map((f) => f.absPath ?? f.fileName),
        contains(endsWith('sentry_redaction_test.dart')),
      );
      expect(event.tags, containsPair('where', 'test'));
      expect(event.toJson().toString(), isNot(contains(_secret)));
    });
  });
}
