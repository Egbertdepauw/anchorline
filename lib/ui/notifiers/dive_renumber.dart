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

/// Pure display-sequence computation: assign every dive a number, walking
/// chronologically oldest→newest. An explicit [userNumber] (a persisted
/// `user_dive_number`) acts as an anchor that resets the counter to itself;
/// an unnumbered dive gets counter+1, i.e. it continues from the nearest
/// older anchor. With no anchors anywhere this is exactly the chronological
/// 1..N sequence. Returns diveId -> number.
Map<String, int> computeSequence(
    List<({String diveId, int startTime, int? userNumber})> dives) {
  // Sort ascending by start time, tie-broken by diveId — two dives from two
  // DCs could in theory share a start second, and the result must be
  // deterministic regardless of input order.
  final sorted = [...dives]..sort((a, b) {
      final byTime = a.startTime.compareTo(b.startTime);
      return byTime != 0 ? byTime : a.diveId.compareTo(b.diveId);
    });
  final out = <String, int>{};
  var counter = 0;
  for (final d in sorted) {
    counter = d.userNumber ?? (counter + 1);
    out[d.diveId] = counter;
  }
  return out;
}
