import 'package:ccrlogger/data/import/import_problem_reporter.dart';
import 'package:ccrlogger/diagnostics/sentry_redaction.dart' show redactError;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The redaction itself (SQLite text, parameters) is tested in
  // test/diagnostics/sentry_redaction_test.dart.
  test('an unusable parse is identifiable by its type once redacted', () {
    expect(redactError(const UnusableParse()).toString(), 'UnusableParse');
  });
}
