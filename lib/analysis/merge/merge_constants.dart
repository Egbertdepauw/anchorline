/// Maximum allowed surface interval between two consecutive dives in a merge.
/// Tunable: raising it re-enables merging repetitive dives with longer
/// surface intervals. (Subsurface imposes no cap on manual merges; we chose a
/// hard 1 h block per product decision 2026-05-31.)
const Duration kMergeMaxSurfaceGap = Duration(hours: 1);

/// How much of the real surface interval to *draw* as a flat gap in the
/// stitched profile. The dive computer logs nothing on the surface, so a
/// proportional gap (real SI ÷ sample interval) can be thousands of empty
/// samples that bury the actual dive data. We instead draw a short, fixed-cap
/// surface block so both dives stay legible; the true interval is shown as a
/// label ("SI 1h 12m") on the list tile. Short real gaps still render
/// proportionally — only long ones are clamped to this cap.
const Duration kMergedSurfaceGapDisplayCap = Duration(minutes: 2);
