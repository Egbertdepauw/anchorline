// Pure-Dart serializer for Subsurface's plain-text git-repo format.
//
// The serializer's primary responsibility is to emit byte-for-byte equivalent
// output for any [SubsurfaceFile] that came out of [parseSubsurfaceFile]. To
// achieve that, every parsed line carries its verbatim source string, and the
// serializer just re-emits each line followed by a single `\n`.
//
// When a [SsLine] is constructed without a source string (e.g. a new dive
// being built in-memory for Phase B+), the line's [SsLine.renderFromFields]
// is used instead. That path is best-effort and not guaranteed to match any
// specific Subsurface release byte-for-byte; it just produces text that
// Subsurface will parse correctly.

import 'subsurface_format.dart';

/// Serialize a [SubsurfaceFile] back to text. Each line is emitted via
/// [SsLine.render] and terminated with a single `\n`. Subsurface always
/// writes a trailing newline at end-of-file, so we do too.
String serializeSubsurfaceFile(SubsurfaceFile file) {
  final buf = StringBuffer();
  for (final line in file.lines) {
    buf.write(line.render());
    buf.write('\n');
  }
  return buf.toString();
}
