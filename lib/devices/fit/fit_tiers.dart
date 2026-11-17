/// Which FIT dive computer models Anchorline has checked against a real
/// recording from a real watch.
///
/// The map goes from a model name (the product name FIT files carry, such as
/// "Descent Mk1") to a fixture path under `packages/fit_reader/test/fixtures/`.
/// A model that is not listed is shown as "Not yet tested by us" on the
/// import screen. The list starts empty; a model is added once its fixture is
/// in the tree. `test/devices/fit/fit_tiers_test.dart` fails when a listed
/// model has no fixture file.
library;

const Map<String, String> kCheckedFitModels = {};

/// Whether [product] has a real recording behind it.
bool isCheckedFitModel(String product) =>
    kCheckedFitModels.containsKey(product);
