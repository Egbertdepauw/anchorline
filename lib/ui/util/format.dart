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

/// Format a gas mix for display: "21/35" for trimix, "EAN32" for nitrox, "Air" for air.
String formatGasMix(int o2, int he) {
  if (he > 0) return '$o2/$he';
  if (o2 == 21) return 'Air';
  if (o2 == 100) return 'O2';
  return 'EAN$o2';
}

/// Format scrubber stack remaining as "H:MM" (e.g. 23777 → "6:36").
/// Truncates to whole minutes — half a minute is noise on a multi-hour total.
String formatStackHm(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

/// Format scrubber per-dive consumption as "M:SS" (e.g. 3484 → "58:04").
String formatStackUsedMs(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Format a date+time from unix seconds: "19 Apr 2026 · 10:38"
String formatDateTime(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  final date = _dayMonth.format(dt);
  final year = dt.year;
  final time =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return '$date $year · $time';
}
