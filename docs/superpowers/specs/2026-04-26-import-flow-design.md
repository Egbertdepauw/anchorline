# Import Flow

## Context

The app has a dive list and detail screen showing fixture dives. The Import tab currently shows a placeholder. This spec covers the BLE import wizard — the table-stake feature that makes the app usable with real dive computers. A mock backend enables development without hardware.

## Performance Requirement

Fast import is critical, especially on Android. Subsurface's slow Android BLE imports are a well-known pain point for users. The import pipeline must minimize per-dive overhead: download, parse, convert, and commit should be pipelined where possible. The user should never feel like the app is wasting time between dives.

## Wizard Steps

The import flow is a linear stepper with 5 states. The UI shows the current step with a progress indication.

### Step 1: Scan

- "Searching for dive computers..." with a pulsing animation.
- Lists discovered Shearwater BLE devices as they appear (name, signal strength).
- User taps a device to select it.
- In debug mode with mock enabled: shows a fake "Petrel 3 (Mock)" device immediately.
- Timeout after 15 seconds with "No devices found. Make sure your dive computer is in upload mode."

### Step 2: Connect

- "Connecting to [device name]..." with progress indicator.
- Reads device info via RDBI (serial, firmware, model).
- On success: shows a device info card (model name, serial, firmware version).
- On failure: "Connection failed. Tap to retry." with retry button.

### Step 3: Read Manifest

- "Reading dive list..." with progress indicator.
- Downloads manifest pages.
- Compares against already-imported dives in the database (by dive ID / fingerprint).
- Shows summary: "Found N new dives (M total on device)".
- Button: "Import N dives".
- If no new dives: "All dives already imported." with done button.

### Step 4: Download

- Per-dive progress display:
  - "Downloading dive #718... (3 of 12)"
  - Linear progress bar showing current dive within total
  - Running count of successfully imported dives
- Each dive: download (compressed) → decompress → parse → convert → atomic commit to database.
- Each dive is independently committed — interruption at any point leaves the database consistent.
- On BLE disconnect: transition to error state.

### Step 5: Done

- "Imported N dives successfully." with checkmark icon.
- Button: "View Dives" — navigates to the Dives tab.
- The dive list auto-refreshes to show newly imported dives.

## Error Handling

- **Connection lost during download:** "Connection lost. X of Y dives imported successfully. Tap to retry."
- **Retry:** Re-scans, reconnects, re-reads manifest. Dedup logic skips already-imported dives — safe to retry from any point.
- **No auto-reconnect** in this iteration (planned for Step 7).
- **Individual dive parse failure:** Log the error, skip that dive, continue with remaining. Show count of failures in the done screen.

## State Machine

```
idle → scanning → connecting → readingManifest → downloading → done
                                                             ↘ error
         ↑                                                      ↓
         └──────────────────── retry ───────────────────────────┘
```

## ImportNotifier

```dart
enum ImportState { idle, scanning, connecting, readingManifest, downloading, done, error }

class ImportNotifier extends ChangeNotifier {
  ImportState state;
  DeviceInfo? deviceInfo;
  List<ManifestEntry> newDives;    // dives not yet in DB
  int downloadedCount;
  int totalToDownload;
  int? currentDiveNumber;          // dive # being downloaded
  String? errorMessage;
  bool useMock;                    // debug toggle
}
```

## Mock Backend

`MockBleTransport` provides the same interface as `ShearwaterBleTransport`:
- `scan()` — yields a single fake device after 200ms.
- `readDeviceInfo()` — returns Petrel 3 info (serial B89641E4, firmware V103) after 300ms.
- `readManifest()` — returns 8 manifest entries (matching the fixture dives) after 500ms.
- `downloadDives(manifest)` — yields each dive blob from bundled fixture assets with a 500ms delay per dive to simulate BLE transfer.

Activated when `kDebugMode` is true and no real BLE devices are found (or via a debug toggle in the scanning step).

## Files

| File | Purpose |
|------|---------|
| `lib/ui/screens/import_screen.dart` | Wizard UI with step-based layout |
| `lib/ui/notifiers/import_notifier.dart` | State machine ChangeNotifier |
| `lib/shearwater/ble/mock_ble_transport.dart` | Mock backend using fixture assets |
| Modify: `lib/ui/app_shell.dart` | Replace Import placeholder with ImportScreen |

## Navigation

The Import tab in the bottom nav shows the `ImportScreen`. The wizard runs within that tab. "View Dives" at the end switches to the Dives tab (index 0) and triggers a refresh of the dive list.

To enable switching tabs from the import screen, the `AppShell` exposes a callback or the import screen calls a passed-in `onComplete` that switches to tab 0.

## Verification

- Import tab shows the scan step (not a placeholder).
- In debug mode: mock device appears, full flow completes with 8 fixture dives.
- Progress updates per dive during download.
- Done screen shows count and "View Dives" button.
- Tapping "View Dives" switches to Dives tab with new dives visible.
- Simulated error recovery: if mock is interrupted, retry works.
- `flutter analyze` clean, all existing tests pass.

## Future: Dive Selection (next iteration)

Step 3 will be enhanced to show a scrollable list with checkboxes next to each manifest entry. Each row shows dive number, date, duration, and max depth from the manifest. The user can select/deselect individual dives. The import button changes to "Import selected (N)". This enables partial imports for divers who only want specific dives.
