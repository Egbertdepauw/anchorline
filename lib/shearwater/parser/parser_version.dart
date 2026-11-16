/// Version of the Shearwater reader's output, stored with every imported dive.
///
/// Bump whenever the Shearwater reader's output changes.
/// `test/shearwater/parser/reader_output_guard_test.dart` pins the output per
/// fixture and fails until you bump this and update its digests.
///
/// History:
///  1. Before phase 1.
///  2. Events and brand fields (vendor, product).
const int kShearwaterParserVersion = 2;
