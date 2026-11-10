import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/ui/format/attachment_usage_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatGb', () {
    test('decimal GB with trailing zeros trimmed', () {
      expect(formatGb(400000000), '0.4 GB');
      expect(formatGb(980000000), '0.98 GB');
      expect(formatGb(1000000000), '1 GB');
      expect(formatGb(0), '0 GB');
    });

    test('a non-zero value under 0.01 GB reads <0.01 GB', () {
      expect(formatGb(1), '<0.01 GB');
      expect(formatGb(9999999), '<0.01 GB');
      expect(formatGb(10000000), '0.01 GB');
    });
  });

  test('formatMb uses one decimal', () {
    expect(formatMb(4200000), '4.2 MB');
  });

  test('formatUsageLine', () {
    const usage = AttachmentUsage(
      usedBytes: 400000000,
      limitBytes: 1000000000,
      usedFiles: 120,
      limitFiles: 1000,
    );
    expect(formatUsageLine(usage), '0.4 GB of 1 GB · 120 of 1,000 files');
  });
}
