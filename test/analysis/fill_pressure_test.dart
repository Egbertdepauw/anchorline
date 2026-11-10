import 'package:ccrlogger/analysis/fill_pressure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseFillPressure', () {
    test('blank is valid and means none', () {
      expect(parseFillPressure(''), (valid: true, bar: null));
      expect(parseFillPressure('   '), (valid: true, bar: null));
    });

    test('numbers, with a dot or a comma', () {
      expect(parseFillPressure('200'), (valid: true, bar: 200.0));
      expect(parseFillPressure(' 210.5 '), (valid: true, bar: 210.5));
      expect(parseFillPressure('210,5'), (valid: true, bar: 210.5));
      expect(parseFillPressure('0'), (valid: true, bar: 0.0));
    });

    test('a typo is not valid', () {
      for (final bad in ['21o', 'abc', '-5', '2 0', 'NaN', 'Infinity', '1,2,3']) {
        expect(parseFillPressure(bad), (valid: false, bar: null),
            reason: '"$bad"');
      }
    });
  });
}
