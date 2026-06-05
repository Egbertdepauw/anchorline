/// Pure renumber computation: assign sequential dive numbers to [targets] in
/// chronological order, oldest = [start]. Returns diveId -> number.
Map<String, int> computeRenumber(
    List<({String diveId, int startTime})> targets, int start) {
  final sorted = [...targets]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final out = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    out[sorted[i].diveId] = start + i;
  }
  return out;
}
