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
  return DateTime.utc(year, month, day, hour, minute, second);
}
