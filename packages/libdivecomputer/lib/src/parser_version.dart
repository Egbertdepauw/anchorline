/// The version of Anchorline's mapping from libdivecomputer output to its
/// own dive model. A dive stores the version that produced it, and a refresh
/// re-parses dives with an older one.
///
/// Bump it on every upstream pin move and every change to the mapping.
///
/// History:
/// - 1 = first mapping (phase 2).
const int kLibdcParserVersion = 1;
