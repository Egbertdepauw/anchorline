import 'package:ccrlogger/sync/cloud/upload_permission_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../_helpers/sentry_capture.dart';

void main() {
  final denied = PostgrestException(
      message: 'new row violates row-level security policy for table '
          '"dive_computers" dc_b89641e4',
      code: '42501');

  test('sends one redacted event with the fixed tags only', () async {
    final capture = await startSentryCapture();
    await reportUploadPermissionDenied(
        'dive_computers', UpdateType.put, denied, StackTrace.current);
    final events = await capture.waitFor(1);
    expect(events, hasLength(1));
    expect(events.single.tags, {
      'sync.table': 'dive_computers',
      'sync.op': 'put',
      'sync.sqlstate': '42501',
    });
    final text = [
      for (final e in events.single.exceptions ?? const []) ...[e.type, e.value],
      events.single.message?.formatted,
    ].join(' ');
    expect(text, isNot(contains('dc_b89641e4')));
    expect(text, isNot(contains('row-level')));
  });

  test('an unknown table is tagged other', () async {
    final capture = await startSentryCapture();
    await reportUploadPermissionDenied(
        'not_a_table', UpdateType.patch, denied, StackTrace.current);
    final events = await capture.waitFor(1);
    expect(events.single.tags!['sync.table'], 'other');
    expect(events.single.tags!['sync.op'], 'patch');
  });
}
