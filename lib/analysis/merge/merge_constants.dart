/// Maximum allowed surface interval between two consecutive dives in a merge.
/// Tunable: raising it re-enables merging repetitive dives with longer
/// surface intervals. (Subsurface imposes no cap on manual merges; we chose a
/// hard 1 h block per product decision 2026-05-31.)
const Duration kMergeMaxSurfaceGap = Duration(hours: 1);
