# Dive Detail Screen + Profile Chart

## Context

The app shell and dive list (Step 6.1) are complete. Tapping a dive tile currently shows a snackbar placeholder. This spec covers the dive detail screen with the multi-trace profile chart — the core differentiating feature of CCRLogger. The profile chart is what makes this app worth building: no other mobile dive log surfaces per-cell mV data, deco ceilings, and setpoint alongside the depth profile.

## Screen Structure

The dive detail is pushed onto the Dives tab navigator from the dive list. It's a single scrollable screen:

1. **Compact header bar** (fixed height, ~80px)
2. **Profile chart** (hero, ~250px)
3. **Trace toggle chips** (single row)
4. **Stats row** (4 metric cells)
5. **Gas mixes section**

Future additions (not in this spec): annotations editor, equipment links, solenoid markers.

## Compact Header Bar

Background: elevated card color (#152238).

Layout:
```
┌───────────────────────────────────────────┐
│  CC  #718  Petrel 3              28.4m    │
│  19 Apr 2026 · 10:38         57:08 GF35/75│
└───────────────────────────────────────────┘
```

- Left side: mode label (colored text), dive number (bold), DC model name (dimmed)
- Below: date + time
- Right side: max depth (large, accent color), duration + GF below (dimmed)

## Profile Chart

Full-width `CustomPainter`, approximately 250px tall. Dark background (scaffold color, not card).

### Axes

- **Left Y-axis:** Depth in meters, inverted (0m at top, max depth at bottom). Labels at regular intervals (every 5m or 10m depending on max depth).
- **Right Y-axis:** PPO2 / setpoint / cell mV scale, 0.0 at bottom, 2.0 at top. Only shown when PPO2/cells traces are visible.
- **X-axis:** Time in minutes. Labels at regular intervals. Tick marks at bottom.
- **Grid:** Subtle horizontal lines at each Y-axis label. Color: very dim (#1A2A40).

### Traces

Each trace is independently toggleable. Default visibility depends on dive mode.

| Trace | Color | Style | Default (CCR) | Default (OC) |
|-------|-------|-------|---------------|--------------|
| Depth | Cyan #4FC3F7 | Solid 2px + filled area underneath (10% opacity) | Always on | Always on |
| PPO2 (voted) | Green #66BB6A | Solid 1.5px | On | Off |
| Setpoint | Orange #FF9800 | Dashed 1px | On | Off |
| Deco ceiling | Orange #FF9800 | Filled area from top (15% opacity) | On | On |
| Cell 0 mV | Red #EF5350 | Solid 1px thin | Off | Off |
| Cell 1 mV | Yellow #FFEE58 | Solid 1px thin | Off | Off |
| Cell 2 mV | Blue #42A5F5 | Solid 1px thin | Off | Off |
| Tank pressure | Grey #90A4AE | Solid 1px | Off | Off |

Depth is always on and cannot be toggled off.

### Rendering

- Downsample to screen pixel width (e.g., 360 points for a 360px-wide chart). No need to render more points than pixels.
- Depth area fill: draw the depth polyline, then close the path along the top edge (y=0) to create a filled region.
- Deco ceiling: draw from top of chart down to the ceiling depth. Filled area represents "you must not be above this depth."
- Cell mVs are plotted on the PPO2 axis (calibrated values are already in bar-equivalent units).
- All traces anti-aliased.

### Data Mapping

Given a `SampleSet` with N samples:
- X position: `sampleIndex / (N - 1) * chartWidth`
- Depth Y: `depth / maxDepth * chartHeight` (inverted, 0 at top)
- PPO2 Y: `(1.0 - ppo2 / ppo2Max) * chartHeight` (0 at bottom)
- Chart clips to its bounds (no drawing outside the chart area).

## Trace Toggle Chips

A horizontally scrollable row of `FilterChip` widgets below the chart:

- Labels: "PPO2", "Setpoint", "Cells", "Deco", "Tanks"
- Selected state: chip is filled with trace color, deselected is outlined
- Tapping toggles the corresponding trace(s) on/off
- "Cells" toggles all 3 cell traces together
- Chip row scrolls horizontally if needed

## Long-Press Crosshair

Interactive sample inspection via long-press gesture on the chart:

1. **Activate:** Long-press on chart area
2. **Crosshair:** Vertical line at the current X position, spanning full chart height. Color: white with 50% opacity.
3. **Snap to samples:** Crosshair snaps to nearest sample index (not arbitrary pixel position).
4. **Drag:** While pressed, drag horizontally to scrub through samples.
5. **Tooltip:** Floating card near the crosshair showing values at that sample:
   - Time (mm:ss)
   - Depth (m)
   - PPO2 (bar) — if trace visible
   - Setpoint (bar) — if trace visible
   - Cell mVs — if trace visible
   - Temp (°C)
6. **Release:** Crosshair and tooltip disappear.
7. **Haptic:** Light haptic feedback on snap.

The tooltip positions itself to avoid going off-screen (flip sides when near edges).

## Stats Row

Below the toggle chips. Four equal-width metric cells in a row:

| Metric | Source |
|--------|--------|
| AVG PPO2 | Mean of `ppo2Bar` array (CCR only, hidden for OC) |
| CNS | Max value from `cns` array × 100 for display as % |
| TEMP | Min temperature from `temperatureCelsius` array |
| GAS | Primary gas from `gasMixes[0]`: "21/35" format for trimix, "EAN32" for nitrox, "Air" for 21% |

Each cell: large value text, small uppercase label below.

## Gas Mixes Section

Below the stats row. Lists all gas mixes used in the dive:

```
Gas Mixes
─────────────────
  DIL  21/35  (Trimix)
  O2   100/0  (Oxygen)
```

Each row: usage label (DIL/O2/GAS), O2/He percentages, gas name. Colored dot matching whether it's diluent or bailout.

## Data Flow

### DiveDetailNotifier

```
class DiveDetailNotifier extends ChangeNotifier {
  Dive? dive;           // Drift row
  SampleSet? samples;   // Decoded columnar data
  Set<TraceType> visibleTraces;  // Toggle state
  int? crosshairIndex;  // null = not active
  bool loading;
}
```

- Loads dive row from `DiveDao.getAllDives()` result (passed from list)
- Loads `SampleSet` from `DiveDao.getSamples(diveId)`
- Trace visibility initialized from dive mode (CCR defaults vs OC defaults)
- Crosshair index set by gesture, cleared on release

### Navigation

The dive list screen passes the Drift `Dive` row to the detail screen on tap. The detail screen uses the `dive.id` to load samples from the DAO. The `DiveDao` instance is passed through (same as the list screen gets it from the app shell).

## Files to Create/Modify

| File | Purpose |
|------|---------|
| `lib/ui/screens/dive_detail_screen.dart` | Screen: header + chart + chips + stats + gas mixes |
| `lib/ui/widgets/profile_chart.dart` | Multi-trace CustomPainter |
| `lib/ui/widgets/trace_toggle.dart` | FilterChip row for trace visibility |
| `lib/ui/widgets/crosshair_overlay.dart` | GestureDetector + crosshair line + tooltip |
| `lib/ui/notifiers/dive_detail_notifier.dart` | ChangeNotifier: dive + samples + trace state |
| Modify: `lib/ui/screens/dive_list_screen.dart` | Replace snackbar with Navigator.push to detail |
| Modify: `lib/ui/app_shell.dart` | Pass DiveDao to dive list for forwarding to detail |

## Verification

- Tap a dive in the list → navigates to detail screen
- Header shows dive number, mode, depth, duration, GF, date, DC model
- Profile chart renders depth trace (cyan filled area)
- PPO2 and setpoint traces visible by default for CCR dives
- Deco ceiling shows as orange shaded area from top
- Toggle chips enable/disable traces
- Long-press on chart shows crosshair with snapping and value tooltip
- Drag crosshair scrubs through the dive
- Release dismisses crosshair
- Stats row shows avg PPO2, CNS, temp, primary gas
- Gas mixes section lists all mixes
- Back navigation returns to dive list
- `flutter analyze` clean, all existing tests pass
