import 'dart:io' show SocketException;

import 'package:ccrlogger/diagnostics/sentry_redaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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

  group('sentryBeforeSend', () {
    test('an error sent as it is reaches Sentry without its text', () async {
      final sentry = await startSentryCapture(beforeSend: sentryBeforeSend);
      final error = _sqliteErrorWithSecret();

      // What an uncaught error amounts to: the raw error, not redacted.
      await Sentry.captureException(error, stackTrace: StackTrace.current);

      final event = (await sentry.waitFor(1)).single;
      final exception = event.exceptions!.single;
      expect(exception.type, 'SqliteException');
      expect(exception.value,
          'SqliteException (result code ${error.extendedResultCode})');
      expect(exception.stackTrace?.frames, isNotEmpty);
      expect(event.toJson().toString(), isNot(contains(_secret)));
    });

    test('an error without a SQLite code keeps only its type', () {
      final event = SentryEvent(exceptions: [
        SentryException(
          type: 'StateError',
          value: 'Bad state: dive $_secret',
          throwable: StateError('dive $_secret'),
        ),
      ]);

      final exception = sentryBeforeSend(event, Hint())!.exceptions!.single;

      expect(exception.type, 'StateError');
      expect(exception.value, 'StateError');
    });

    test('an exception it cannot trace back to an error loses its value', () {
      final event = SentryEvent(exceptions: [
        SentryException(type: 'PlatformException', value: 'id $_secret'),
      ]);

      final exception = sentryBeforeSend(event, Hint())!.exceptions!.single;

      expect(exception.type, 'PlatformException');
      expect(exception.value, isNull);
    });

    test('FlutterError details keep only the library', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FlutterError',
            value: 'Unable to load $_secret',
            throwable: StateError('Unable to load $_secret'),
          ),
        ],
        contexts: Contexts()
          ..['flutter_error_details'] = <String, String>{
            'context': 'thrown resolving an image codec',
            'information': 'Image provider: NetworkImage("https://r2/$_secret")',
            'library': 'image resource service',
          },
      );

      final redacted = sentryBeforeSend(event, Hint())!;

      expect(redacted.contexts['flutter_error_details'],
          {'library': 'image resource service'});
      expect(redacted.toJson().toString(), isNot(contains(_secret)));
    });

    test('a captured message is the code\'s own text and stays', () {
      final event = SentryEvent(
        message: SentryMessage('App data not fully moved out of Documents'),
      );

      expect(sentryBeforeSend(event, Hint())!.message?.formatted,
          'App data not fully moved out of Documents');
    });

    test('drops the network blips the SDKs retry on their own', () {
      SentryEvent thrown(Object error) => SentryEvent(throwable: error);

      expect(
          sentryBeforeSend(
              thrown(const SocketException('Connection reset')), Hint()),
          isNull);
      expect(
          sentryBeforeSend(
              thrown(Exception('ClientException: Failed host lookup: x')),
              Hint()),
          isNull);
      expect(sentryBeforeSend(thrown(StateError('a bug')), Hint()), isNotNull);
    });
  });
}
