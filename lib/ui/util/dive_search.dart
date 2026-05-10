import '../../data/db/database.dart';
import '../../data/models/annotation.dart' as dom;
import 'format.dart';

/// Substring match (case-insensitive) across dive number, site name,
/// buddies, notes, tags, and the formatted date string. Empty/whitespace
/// query matches everything. Pure: no Flutter or DB deps.
///
/// [sequenceNumber] is the CCRLog-internal display number (see
/// [DiveListNotifier.sequenceByDiveId]); when supplied, it's searchable
/// alongside the DC's own number, so a query like "#705" hits whichever
/// the user typed.
bool diveMatchesQuery(
  Dive dive,
  dom.DiveAnnotation? ann,
  String q, {
  int? sequenceNumber,
}) {
  final needle = q.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final parts = <String>[
    '#${dive.dcDiveNumber}',
    if (sequenceNumber != null) '#$sequenceNumber',
    formatDateTime(dive.startTime),
  ];
  if (ann != null) {
    if (ann.siteName != null) parts.add(ann.siteName!);
    if (ann.notes != null) parts.add(ann.notes!);
    if (ann.buddies.isNotEmpty) parts.add(ann.buddies.join(' '));
    if (ann.tags.isNotEmpty) parts.add(ann.tags.join(' '));
  }
  return parts.join(' ').toLowerCase().contains(needle);
}

/// Facet-AND, value-OR within facet. `mode == null` skips the mode filter;
/// empty/null sets skip their facet. Pure: no Flutter or DB deps.
bool diveMatchesFilters(
  Dive dive,
  dom.DiveAnnotation? ann, {
  int? mode,
  Set<String>? sites,
  Set<String>? buddies,
  Set<String>? tags,
}) {
  if (mode != null && dive.diveMode != mode) return false;
  if (sites != null && sites.isNotEmpty) {
    final s = ann?.siteName;
    if (s == null || !sites.contains(s)) return false;
  }
  if (buddies != null && buddies.isNotEmpty) {
    final list = ann?.buddies ?? const <String>[];
    if (!list.any(buddies.contains)) return false;
  }
  if (tags != null && tags.isNotEmpty) {
    final list = ann?.tags ?? const <String>[];
    if (!list.any(tags.contains)) return false;
  }
  return true;
}
