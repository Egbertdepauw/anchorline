import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;

/// Moves cylinder assignments to follow their gas mix across a refresh.
///
/// [rowsByIndex] maps a stored gas-mix index to its cylinder id (null for a
/// row with no cylinder yet). Returns the final rows, again index to cylinder
/// id. A row at a valid old index follows its mix to the new index with the
/// same O2 and He, preferring the same `isDiluent` and then the lowest unused
/// index. A row whose mix is gone, or whose old index is out of range, takes
/// the next unused negative index (-1, -2, ...), meaning "unassigned". A row
/// already at a negative index keeps it.
///
/// O2 and He are whole percentages ([DiveGasMix] stores ints), so they are
/// compared exactly.
Map<int, String?> remapCylinderRows({
  required List<DiveGasMix> oldMixes,
  required List<DiveGasMix> newMixes,
  required Map<int, String?> rowsByIndex,
}) {
  final result = <int, String?>{};
  final usedNew = <int>{};
  final taken = <int>{}; // negative indexes already present or assigned
  final gone = <int>[];

  final oldIndexes = rowsByIndex.keys.toList()..sort();

  for (final i in oldIndexes) {
    if (i < 0) {
      result[i] = rowsByIndex[i];
      taken.add(i);
    }
  }

  final pending = [
    for (final i in oldIndexes)
      if (i >= 0) i,
  ];

  int? pick(DiveGasMix old, {required bool sameDiluent}) {
    for (var n = 0; n < newMixes.length; n++) {
      final m = newMixes[n];
      if (usedNew.contains(n)) continue;
      if (m.oxygenPercent != old.oxygenPercent ||
          m.heliumPercent != old.heliumPercent) {
        continue;
      }
      if (sameDiluent && m.isDiluent != old.isDiluent) continue;
      return n;
    }
    return null;
  }

  // First pass claims exact matches (same diluent flag) so a later row cannot
  // lose its own mix to an earlier row of the same O2/He; the second pass
  // lets leftovers take any mix with the same O2/He.
  final unresolved = <int>[];
  for (final i in pending) {
    if (i >= oldMixes.length) {
      gone.add(i);
      continue;
    }
    final n = pick(oldMixes[i], sameDiluent: true);
    if (n == null) {
      unresolved.add(i);
    } else {
      usedNew.add(n);
      result[n] = rowsByIndex[i];
    }
  }
  for (final i in unresolved) {
    final n = pick(oldMixes[i], sameDiluent: false);
    if (n == null) {
      gone.add(i);
    } else {
      usedNew.add(n);
      result[n] = rowsByIndex[i];
    }
  }

  gone.sort();
  var next = -1;
  for (final i in gone) {
    while (taken.contains(next)) {
      next--;
    }
    taken.add(next);
    result[next] = rowsByIndex[i];
  }
  return result;
}
