/// Version of the Shearwater reader's output, stored with every imported dive.
///
/// Bump whenever the Shearwater reader's output changes.
/// `test/shearwater/parser/reader_output_guard_test.dart` pins the output per
/// fixture and fails until you bump this and update its digests.
///
/// History:
///  1. Before phase 1. Every build since 73bab2a wrote 1 while the reader's
///     output changed under it (raw cell mV and stack time on 2026-04-28;
///     tanks and tank pressures on 2026-05-06), so re-parsing a very old dive
///     changes those fields too.
///  2. Events and brand fields (vendor, product).
const int kShearwaterParserVersion = 2;
