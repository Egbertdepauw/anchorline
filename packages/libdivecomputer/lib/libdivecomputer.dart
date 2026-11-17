/// Vendored libdivecomputer, built by a native assets hook, and the Dart side
/// of Anchorline's access to dive computers from other manufacturers.
library;

export 'src/descriptors.dart' show LibdcDescriptor, Libdc;
export 'src/dive_id.dart' show fingerprintHex, libdcDiveId;
export 'src/envelope.dart' show LibdcEnvelope;
export 'src/mapping/map_dive.dart' show mapLibdcDive;
export 'src/parse/parse_dive.dart' show parseDive;
export 'src/parse/parsed_dive.dart';
export 'src/parse/status.dart' show LibdcParseException, LibdcStatus;
export 'src/parser_version.dart' show kLibdcParserVersion;
