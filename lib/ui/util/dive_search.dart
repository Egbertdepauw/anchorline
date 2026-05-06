import '../../data/db/database.dart';
import '../../data/models/annotation.dart' as dom;
import 'format.dart';

/// Substring match (case-insensitive) across dive number, site name,
/// buddies, notes, tags, and the formatted date string. Empty/whitespace
/// query matches everything. Pure: no Flutter or DB deps.
bool diveMatchesQuery(Dive dive, dom.DiveAnnotation? ann, String q) {
  final needle = q.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final parts = <String>[
    '#${dive.dcDiveNumber}',
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
