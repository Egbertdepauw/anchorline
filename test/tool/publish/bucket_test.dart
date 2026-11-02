import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/bucket.dart';
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/manifest.dart';

const _endpoint = 'https://acct123.r2.cloudflarestorage.com';

/// What one fake `aws` process saw.
class _Call {
  _Call(this.executable, this.args, this.environment);

  final String executable;
  final List<String> args;
  final Map<String, String>? environment;

  /// The value after [flag], or null.
  String? option(String flag) {
    final i = args.indexOf(flag);
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }
}

ProcessResult _ok([String stdout = '']) => ProcessResult(1, 0, stdout, '');

ProcessResult _failed(String stderr, {int exitCode = 1}) =>
    ProcessResult(1, exitCode, '', stderr);

Matcher _publishError([String? containing]) => throwsA(
  isA<PublishError>().having(
    (e) => e.message,
    'message',
    containing == null ? isNotEmpty : contains(containing),
  ),
);

void main() {
  late List<_Call> calls;
  late Future<ProcessResult> Function(_Call call) onRun;

  AwsCliBucket bucket() => AwsCliBucket(
    accountId: 'acct123',
    bucket: 'anchorline-downloads',
    runner: (executable, args, {environment}) async {
      final call = _Call(executable, args, environment);
      calls.add(call);
      return onRun(call);
    },
  );

  setUp(() {
    calls = [];
    onRun = (_) async => _ok();
  });

  group('putFile', () {
    test('uploads with s3 cp, the R2 endpoint and the content type', () async {
      await bucket().putFile(
        'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
        '/tmp/build/app.exe',
        contentType: 'application/vnd.microsoft.portable-executable',
      );

      final call = calls.single;
      expect(call.executable, 'aws');
      expect(call.args.take(4), [
        's3',
        'cp',
        '/tmp/build/app.exe',
        's3://anchorline-downloads/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      ]);
      expect(call.option('--endpoint-url'), _endpoint);
      expect(call.option('--region'), 'auto');
      expect(
        call.option('--content-type'),
        'application/vnd.microsoft.portable-executable',
      );
      expect(call.args, isNot(contains('--cache-control')));
      expect(call.args, contains('--no-progress'));
    });

    test('a failed upload is a PublishError carrying aws stderr', () async {
      onRun = (_) async => _failed(
        'upload failed: An error occurred (AccessDenied) when calling the '
        'PutObject operation: Access Denied',
      );

      await expectLater(
        bucket().putFile('k', '/tmp/x.exe', contentType: 'a/b'),
        _publishError('Access Denied'),
      );
    });

    test('a missing aws executable is a PublishError', () async {
      final b = AwsCliBucket(
        accountId: 'acct123',
        bucket: 'anchorline-downloads',
        runner: (executable, args, {environment}) =>
            throw const ProcessException(
              'aws',
              [],
              'No such file or directory',
            ),
      );

      await expectLater(
        b.putFile('k', '/tmp/x.exe', contentType: 'a/b'),
        _publishError('aws'),
      );
    });
  });

  group('putText', () {
    test(
      'uploads the text through a temp file that is gone afterwards',
      () async {
        String? pathSeen;
        String? contentSeen;
        onRun = (call) async {
          pathSeen = call.args[2];
          contentSeen = File(pathSeen!).readAsStringSync();
          return _ok();
        };

        await bucket().putText(
          'releases/manifest.json',
          '{"format": 1}\n',
          contentType: 'application/json',
          cacheControl: 'no-cache',
        );

        final call = calls.single;
        expect(call.args[0], 's3');
        expect(call.args[1], 'cp');
        expect(
          call.args[3],
          's3://anchorline-downloads/releases/manifest.json',
        );
        expect(call.option('--content-type'), 'application/json');
        expect(call.option('--cache-control'), 'no-cache');
        expect(call.option('--endpoint-url'), _endpoint);
        expect(contentSeen, '{"format": 1}\n');
        expect(File(pathSeen!).existsSync(), isFalse);
        expect(Directory(File(pathSeen!).parent.path).existsSync(), isFalse);
      },
    );

    test('the temp file is removed when the upload fails', () async {
      String? pathSeen;
      onRun = (call) async {
        pathSeen = call.args[2];
        return _failed('boom');
      };

      await expectLater(
        bucket().putText('k', 'text', contentType: 'text/plain'),
        _publishError('boom'),
      );
      expect(File(pathSeen!).existsSync(), isFalse);
    });

    test('non-ASCII text is written as UTF-8', () async {
      List<int>? bytesSeen;
      onRun = (call) async {
        bytesSeen = File(call.args[2]).readAsBytesSync();
        return _ok();
      };

      await bucket().putText('k', 'Zuurstofcel é', contentType: 'a/b');

      expect(bytesSeen, utf8.encode('Zuurstofcel é'));
    });
  });

  group('getText', () {
    test('downloads with s3 cp and returns the text', () async {
      onRun = (call) async {
        File(call.args[3]).writeAsStringSync('{"format": 1}\n');
        return _ok();
      };

      final text = await bucket().getText('releases/manifest.json');

      expect(text, '{"format": 1}\n');
      final call = calls.single;
      expect(call.args[0], 's3');
      expect(call.args[1], 'cp');
      expect(call.args[2], 's3://anchorline-downloads/releases/manifest.json');
      expect(call.option('--endpoint-url'), _endpoint);
      expect(call.option('--region'), 'auto');
      expect(File(call.args[3]).existsSync(), isFalse);
    });

    for (final stderr in [
      'fatal error: An error occurred (404) when calling the HeadObject '
          'operation: Key "releases/manifest.json" does not exist',
      'An error occurred (404) when calling the HeadObject operation: '
          'Not Found',
      'An error occurred (NoSuchKey) when calling the GetObject operation: '
          'The specified key does not exist.',
    ]) {
      test('an absent object is null ($stderr)', () async {
        onRun = (_) async => _failed(stderr, exitCode: 1);

        expect(await bucket().getText('releases/manifest.json'), isNull);
      });
    }

    test('any other failure is a PublishError, not "absent"', () async {
      onRun = (_) async => _failed(
        'fatal error: An error occurred (403) when calling the HeadObject '
        'operation: Forbidden',
      );

      await expectLater(
        bucket().getText('releases/manifest.json'),
        _publishError('Forbidden'),
      );
    });

    test('a missing bucket is a PublishError, not "absent"', () async {
      onRun = (_) async => _failed(
        'An error occurred (NoSuchBucket) when calling the GetObject '
        'operation: The specified bucket does not exist',
      );

      await expectLater(
        bucket().getText('releases/manifest.json'),
        _publishError('NoSuchBucket'),
      );
    });
  });

  group('sha256Of', () {
    test('downloads the object, hashes it and removes the download', () async {
      String? pathSeen;
      onRun = (call) async {
        pathSeen = call.args[3];
        File(pathSeen!).writeAsStringSync('installer bytes');
        return _ok();
      };

      final hash = await bucket().sha256Of(
        'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );

      expect(hash, sha256.convert(utf8.encode('installer bytes')).toString());
      expect(
        calls.single.args[2],
        's3://anchorline-downloads/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );
      expect(File(pathSeen!).existsSync(), isFalse);
    });

    test('an absent object is null', () async {
      onRun = (_) async => _failed(
        'fatal error: An error occurred (404) when calling the HeadObject '
        'operation: Not Found',
      );

      expect(await bucket().sha256Of('releases/x'), isNull);
    });

    test('any other failure is a PublishError', () async {
      onRun = (_) async => _failed('Unable to locate credentials');

      await expectLater(
        bucket().sha256Of('releases/x'),
        _publishError('Unable to locate credentials'),
      );
    });
  });

  group('every aws process', () {
    test(
      'asks for checksums only when required and adds no credentials',
      () async {
        onRun = (call) async {
          if (call.args[1] == 'cp' && call.args[2].startsWith('s3://')) {
            File(call.args[3]).writeAsStringSync('x');
          }
          return _ok();
        };
        final b = bucket();
        await b.putFile('a', '/tmp/a.exe', contentType: 'a/b');
        await b.putText('b', 'text', contentType: 'a/b');
        await b.getText('c');
        await b.sha256Of('d');

        expect(calls, hasLength(4));
        for (final call in calls) {
          // Only these two are added; the parent environment (credentials
          // included) is inherited by the process, never copied or logged.
          expect(call.environment, {
            'AWS_REQUEST_CHECKSUM_CALCULATION': 'when_required',
            'AWS_RESPONSE_CHECKSUM_VALIDATION': 'when_required',
          });
          expect(call.args.join(' '), isNot(contains('AWS_SECRET')));
        }
      },
    );
  });

  group('fromEnvironment', () {
    test('reads the account and the bucket', () async {
      final b = AwsCliBucket.fromEnvironment(
        {
          'R2_ACCOUNT_ID': 'acct123',
          'R2_BUCKET': 'anchorline-downloads',
          'AWS_ACCESS_KEY_ID': 'id',
          'AWS_SECRET_ACCESS_KEY': 'secret',
        },
        runner: (executable, args, {environment}) async {
          calls.add(_Call(executable, args, environment));
          return _ok();
        },
      );
      await b.putText('k', 'text', contentType: 'a/b');

      expect(calls.single.option('--endpoint-url'), _endpoint);
      expect(calls.single.args[3], 's3://anchorline-downloads/k');
    });
  });
}
