/// Which descriptor a stored dive (or a download) belongs to.
///
/// Pure, so the parser and the device-open path share one rule. A vendor and
/// product name alone is not enough: Aqualung i200C is listed twice
/// (models 0x4649 and 0x4749) with different dive layouts. So the order is:
///
/// 1. vendor + product + model (unique across the table), which survives a
///    family number that changed between libdivecomputer versions;
/// 2. family + model.
///
/// [table] is the descriptor list in upstream's order. Returns the index of
/// the choice, or null when nothing matches.
int? chooseDescriptorIndex(
  List<(String vendor, String product, int family, int model)> table, {
  required String vendor,
  required String product,
  required int family,
  required int model,
}) {
  int? byFamily;
  for (var i = 0; i < table.length; i++) {
    final d = table[i];
    if (d.$1 == vendor && d.$2 == product && d.$4 == model) return i;
    if (byFamily == null && d.$3 == family && d.$4 == model) byFamily = i;
  }
  return byFamily;
}
