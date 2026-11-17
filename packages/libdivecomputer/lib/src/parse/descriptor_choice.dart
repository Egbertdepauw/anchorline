/// Which descriptors a download opens with, and which one its dives are.
///
/// Two pure choices over the descriptor table (upstream's order), shared by
/// the download and by the parse of a stored dive:
///
/// - [chooseDescriptorIndex]: the descriptor to open the computer with, and
///   the one an envelope records as opened.
/// - [identityDescriptorIndex]: the descriptor the dive is parsed as and
///   identified by (its dive id's vendor, `dcVendor` and `dcProduct`). The
///   app opens a computer with the first descriptor whose name filter takes
///   the advertised name, which is often a sibling model: an OSTC 4 opens as
///   "OSTC 2". libdivecomputer's own parse at download time,
///   `dc_parser_new(device)`, uses the model the computer reported, so this
///   picks the descriptor with that model.
library;

/// The descriptor to open the computer with: vendor + product + model
/// (unique across the table), which survives a family number that changed
/// between libdivecomputer versions; else family + model. A vendor and
/// product name alone is not enough: Aqualung i200C is listed twice (models
/// 0x4649 and 0x4749) with different dive layouts.
///
/// Returns the index of the choice in [table], or null when nothing matches.
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

/// The descriptor a dive is parsed as and identified by: the first one in
/// [table] in the family of the [opened] descriptor whose model is the one
/// the computer reported ([devinfoModel], from `DC_EVENT_DEVINFO`). The
/// first in table order, even when [opened] has that model too, so that a
/// dive's identity does not depend on which sibling (an Oceanic or an
/// Aqualung row, say) the download happened to open.
///
/// Falls back to [opened] when there is no device info, or when no
/// descriptor of the family has that model (hwOS 3 computers report a
/// hardware byte that no descriptor carries). [opened] is an index into
/// [table], from [chooseDescriptorIndex].
int identityDescriptorIndex(
  List<(String vendor, String product, int family, int model)> table, {
  required int opened,
  required int? devinfoModel,
}) {
  if (devinfoModel == null) return opened;
  final family = table[opened].$3;
  for (var i = 0; i < table.length; i++) {
    if (table[i].$3 == family && table[i].$4 == devinfoModel) return i;
  }
  return opened;
}
