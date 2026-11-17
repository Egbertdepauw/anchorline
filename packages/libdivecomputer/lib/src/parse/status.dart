/// Mirrors libdivecomputer's `dc_status_t`.
enum LibdcStatus {
  success(0),
  done(1),
  unsupported(-1),
  invalidArgs(-2),
  noMemory(-3),
  noDevice(-4),
  noAccess(-5),
  io(-6),
  timeout(-7),
  protocol(-8),
  dataFormat(-9),
  cancelled(-10);

  const LibdcStatus(this.code);

  final int code;

  /// An unknown code maps to [io].
  static LibdcStatus fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return io;
  }
}

/// A dive that libdivecomputer or the mapping could not turn into a parse.
/// Carries only the status, never dive data (it can reach Sentry).
class LibdcParseException implements Exception {
  const LibdcParseException(this.status);

  final LibdcStatus status;

  @override
  String toString() => 'LibdcParseException(${status.name})';
}
