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

  /// The file `s3api get-object` writes to (the argument after `--key K`).
  String get outfile => args[6];

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

    test(
      'hands aws an absolute path, so a leading dash is no option',
      () async {
        await bucket().putFile('k', '-weird.exe', contentType: 'a/b');

        final path = calls.single.args[2];
        expect(path, File('-weird.exe').absolute.path);
        expect(path, isNot(startsWith('-')));
      },
    );

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

    test('a temp dir that cannot be deleted does not hide the error', () async {
      onRun = (call) async {
        // Delete the directory under the bucket's feet, so its own cleanup
        // fails.
        File(call.args[2]).parent.deleteSync(recursive: true);
        return _failed('the real problem');
      };

      await expectLater(
        bucket().putText('k', 'text', contentType: 'text/plain'),
        _publishError('the real problem'),
      );
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
    test('reads with s3api get-object and returns the text', () async {
      onRun = (call) async {
        File(call.outfile).writeAsStringSync('{"format": 1}\n');
        return _ok('{"ContentLength": 14}');
      };

      final text = await bucket().getText('releases/manifest.json');

      expect(text, '{"format": 1}\n');
      final call = calls.single;
      expect(call.args.take(6), [
        's3api',
        'get-object',
        '--bucket',
        'anchorline-downloads',
        '--key',
        'releases/manifest.json',
      ]);
      expect(call.option('--endpoint-url'), _endpoint);
      expect(call.option('--region'), 'auto');
      expect(File(call.outfile).existsSync(), isFalse);
    });

    test('only NoSuchKey means the object is absent', () async {
      onRun = (_) async => _failed(
        '\nAn error occurred (NoSuchKey) when calling the GetObject '
        'operation: The specified key does not exist.',
        exitCode: 254,
      );

      expect(await bucket().getText('releases/manifest.json'), isNull);
    });

    // Everything else is an error, because reading it as "absent" would show
    // an empty list (and let a rollback or dry run answer confidently) for a
    // wrong bucket, a bad token or a network problem.
    for (final stderr in [
      'An error occurred (NoSuchBucket) when calling the GetObject '
          'operation: The specified bucket does not exist.',
      // What a HEAD request reports: no error code, only the status. A missing
      // bucket looks exactly like this too.
      'An error occurred (404) when calling the HeadObject operation: '
          'Not Found',
      'An error occurred (403) when calling the GetObject operation: '
          'Forbidden',
      'An error occurred (AccessDenied) when calling the GetObject '
          'operation: Access Denied',
      'An error occurred (InvalidAccessKeyId) when calling the GetObject '
          'operation: The Access Key Id you provided does not exist in our '
          'records.',
      'Unable to locate credentials. You can configure credentials by '
          'running "aws configure".',
      'Could not connect to the endpoint URL: '
          '"https://acct123.r2.cloudflarestorage.com/anchorline-downloads/k"',
    ]) {
      test('is a PublishError, not "absent": $stderr', () async {
        onRun = (_) async => _failed(stderr, exitCode: 254);

        await expectLater(
          bucket().getText('releases/manifest.json'),
          _publishError(stderr.split('\n').first),
        );
      });
    }
  });

  group('sha256Of', () {
    test('downloads the object, hashes it and removes the download', () async {
      onRun = (call) async {
        File(call.outfile).writeAsStringSync('installer bytes');
        return _ok();
      };

      final hash = await bucket().sha256Of(
        'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );

      expect(hash, sha256.convert(utf8.encode('installer bytes')).toString());
      final call = calls.single;
      expect(call.args.take(2), ['s3api', 'get-object']);
      expect(call.option('--bucket'), 'anchorline-downloads');
      expect(
        call.option('--key'),
        'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );
      expect(File(call.outfile).existsSync(), isFalse);
    });

    test('an object that does not exist is null', () async {
      onRun = (_) async => _failed(
        'An error occurred (NoSuchKey) when calling the GetObject operation: '
        'The specified key does not exist.',
        exitCode: 254,
      );

      expect(await bucket().sha256Of('releases/x'), isNull);
    });

    test('a missing bucket is a PublishError, not "absent"', () async {
      onRun = (_) async => _failed(
        'An error occurred (NoSuchBucket) when calling the GetObject '
        'operation: The specified bucket does not exist.',
        exitCode: 254,
      );

      await expectLater(
        bucket().sha256Of('releases/x'),
        _publishError('NoSuchBucket'),
      );
    });

    test('a HEAD-style 404 is a PublishError, not "absent"', () async {
      onRun = (_) async => _failed(
        'An error occurred (404) when calling the HeadObject operation: '
        'Not Found',
      );

      await expectLater(bucket().sha256Of('releases/x'), _publishError('404'));
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
          if (call.args[1] == 'get-object') {
            File(call.outfile).writeAsStringSync('x');
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
    test('trims the values, like the check that they are set', () async {
      final b = AwsCliBucket.fromEnvironment(
        {'R2_ACCOUNT_ID': ' acct123\n', 'R2_BUCKET': '\tanchorline-downloads '},
        runner: (executable, args, {environment}) async {
          calls.add(_Call(executable, args, environment));
          return _ok();
        },
      );
      await b.putText('k', 'text', contentType: 'a/b');

      expect(calls.single.option('--endpoint-url'), _endpoint);
      expect(calls.single.args[3], 's3://anchorline-downloads/k');
    });

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
