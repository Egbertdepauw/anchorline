import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

/// The gas list of a merged dive: the members' mixes in member order (the
/// caller sorts members by start time), de-duplicated on O2, He and diluent
/// flag, in order of first appearance. [remaps] gives, per member, the
/// merged index of each of that member's mixes.
///
/// Pure. The merged view and the refresh's cylinder remap use this one
/// function, because a merged dive's cylinder rows are keyed by this list.
({List<DiveGasMix> mixes, List<List<int>> remaps}) mergeGasMixLists(
    Iterable<List<DiveGasMix>> memberLists) {
  final merged = <DiveGasMix>[];
  final remaps = <List<int>>[];
  for (final list in memberLists) {
    final remap = <int>[];
    for (final g in list) {
      final at = merged.indexWhere((e) =>
          e.oxygenPercent == g.oxygenPercent &&
          e.heliumPercent == g.heliumPercent &&
          e.isDiluent == g.isDiluent);
      if (at >= 0) {
        remap.add(at);
      } else {
        remap.add(merged.length);
        merged.add(DiveGasMix(
          oxygenPercent: g.oxygenPercent,
          heliumPercent: g.heliumPercent,
          isDiluent: g.isDiluent,
        ));
      }
    }
    remaps.add(remap);
  }
  return (mixes: merged, remaps: remaps);
}
