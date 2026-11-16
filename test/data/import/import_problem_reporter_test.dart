import 'package:ccrlogger/data/import/import_problem_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;

void main() {
  test('a SqliteException keeps neither its parameters nor its statement', () {
    final e = SqliteException(
      extendedResultCode: 1555,
      message: 'UNIQUE constraint failed: dives.id',
      causingStatement: 'INSERT INTO dives (id, owner_id, dc_serial) VALUES (?,?,?)',
      parametersToStatement: [3096855012, '6f1c2d3e-aaaa-bbbb-cccc-0123456789ab'],
    );
    expect(e.toString(), contains('3096855012'));
    final text = redactImportError(e).toString();
    expect(text, isNot(contains('3096855012')));
    expect(text, isNot(contains('6f1c2d3e')));
    expect(text, isNot(contains('INSERT')));
    expect(text, contains('SqliteException'));
    expect(text, contains('1555'));
  });

  test('a plain error is reduced to its type', () {
    expect(redactImportError(const FormatException('x at offset 3')).toString(),
        'FormatException');
  });
}
