import 'status.dart';

/// The `dc_datetime_t` fields as a UTC [DateTime]. `DateTime.utc` silently
/// rolls impossible fields over (month 0, hour 24), which would freeze a wrong
/// start time at first import, so they are checked first. Throws
/// [LibdcParseException] (`dataFormat`) on an impossible field.
DateTime libdcWallClock(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
) {
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 60) {
    throw const LibdcParseException(LibdcStatus.dataFormat);
  }
  final wall = DateTime.utc(year, month, day, hour, minute, second);
  // 2026-06-31 would roll into July; a leap second (60) rolls into the next
  // minute, which is the one deliberate exception.
  if (wall.year != year ||
      wall.month != month ||
      wall.day != day ||
      (second < 60 && (wall.hour != hour || wall.minute != minute))) {
    throw const LibdcParseException(LibdcStatus.dataFormat);
  }
  return wall;
}
