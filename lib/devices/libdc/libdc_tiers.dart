/// Which libdivecomputer families Anchorline has checked against a real
/// recording from a real computer.
///
/// The map goes from a `dc_family_t` value to a fixture path under
/// `packages/libdivecomputer/test/fixtures/`. A family that is not listed is
/// shown as "Not yet tested by us" on the import screen. The list starts
/// empty: no family other than Shearwater (which has its own reader) has a
/// real recording yet. `test/devices/libdc/libdc_tiers_test.dart` fails when a
/// listed family has no fixture file.
library;

const Map<int, String> kCheckedLibdcFamilies = {};

/// Whether [family] (a `dc_family_t` value) has a real recording behind it.
bool isCheckedLibdcFamily(int family) =>
    kCheckedLibdcFamilies.containsKey(family);

/// The badge on a computer that is not yet in [kCheckedLibdcFamilies].
const String kNotYetTestedLabel = 'Not yet tested by us';
