/// Display strings for attachment storage usage (issue #196).
///
/// Sizes are decimal (1 GB = 1,000,000,000 bytes) because the Worker's
/// limits are set in decimal bytes, so `1 GB` here is exactly the limit.
library;

import 'package:intl/intl.dart';

import '../../sync/attachments/attachment_signer.dart';

final NumberFormat _count = NumberFormat.decimalPattern('en');

/// Decimal GB with up to two decimals and trailing zeros trimmed:
/// `0.4 GB`, `0.98 GB`, `1 GB`. A non-zero amount under 0.01 GB reads
/// `<0.01 GB`, so a nearly empty account doesn't look empty.
String formatGb(int bytes) {
  if (bytes > 0 && bytes < 10000000) return '<0.01 GB';
  var s = (bytes / 1e9).toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$s GB';
}

/// Decimal MB with one decimal: `4.2 MB`.
String formatMb(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

/// A count with thousands separators: `1,000`.
String formatCount(int n) => _count.format(n);

/// `0.4 GB of 1 GB · 120 of 1,000 files`.
String formatUsageLine(AttachmentUsage u) =>
    '${formatGb(u.usedBytes)} of ${formatGb(u.limitBytes)} · '
    '${formatCount(u.usedFiles)} of ${formatCount(u.limitFiles)} files';
