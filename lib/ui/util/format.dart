import 'package:intl/intl.dart';

String formatDepth(int depthMm) {
  final meters = depthMm / 1000.0;
  return '${meters.toStringAsFixed(1)}m';
}

String formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes}min';
  }
  return '${minutes}min';
}

final _dayMonth = DateFormat('d MMM');
final _monthYear = DateFormat('MMMM yyyy');

String formatDateShort(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  return _dayMonth.format(dt);
}

String formatMonthYear(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  return _monthYear.format(dt);
}

String formatSetpoint(double sp) => 'SP ${sp.toStringAsFixed(2)}';

String formatGf(int? low, int? high) {
  if (low == null || high == null) return '';
  return 'GF $low/$high';
}
