/// Pure renumber computation: assign sequential dive numbers to [targets] in
/// chronological order, oldest = [start]. Returns diveId -> number.
Map<String, int> computeRenumber(
    List<({String diveId, int startTime})> targets, int start) {
  // Sort ascending by start time. Ties can't occur in practice: start_time is
  // part of the dive identity hash (so two real dives can't share it), and
  // merged groups are collapsed to a single representative before reaching here.
  final sorted = [...targets]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final out = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    out[sorted[i].diveId] = start + i;
  }
  return out;
}
