# Gas Analyzer (Divesoft SOLO) — Design Spec / TODO

**Date:** 2026-10-27
**Status:** TODO, not started (issues filed)
**Reference prototype:** `docs/prototypes/solo-live.html`. It is a working Web Serial page, tested against a real SOLO trimix analyzer on macOS. It contains reference implementations of the line parser, gas maths, the stability check and the live chart.

## Tracking

Milestone "Gas analyzer (Divesoft SOLO)":
#104 fixtures + VID/PID · #105 shared MOD helper + mix naming · #106 line parser · #107 stability · #108 desktop transport + demo transport · #109 Android transport · #110 live screen · #111 analysis log · #112 analysed gases in blender/planner + CSV · #113 iPhone BLE bridge · #114 label printing.

## Goal

Read live O2/He values from a Divesoft SOLO trimix analyzer inside Anchorline and show them together with planning numbers, including the CCR diluent MOD. Detect when a reading is stable. Save analyses to a cylinder/gas log that feeds the blender, the planner and the dive's gas list.

Desktop (macOS/Windows/Linux) and Android over USB come first. iPhone needs a BLE bridge; see "Mobile".

## Hardware & protocol facts (verified unless marked)

- **Link:** USB-C, native USB CDC-ACM serial. This is not FTDI on this unit. On macOS the device appears as `/dev/cu.usbmodem101`, not `usbserial-*`.
- **Serial settings:** 115200 baud, 8N1, no flow control. Raise DTR after opening.
- **Enable output on the analyzer:** `Menu → Preferences → Send data to USB` must be > 0. Printer mode on Divesoft analyzers reroutes output to the aux port and disables USB output.
- **Data:** one ASCII line per second, terminated by CRLF. Documented SOLO O2 format:
  `O2 21.1 % Ti 23.9 ~C 1004.1 hPa 2021/12/20 12:03:00`
  The trimix SOLO adds `He xx.x`. The older He/O2 analyzer sends `He xxx.x O2 yyy.y`.
- **Errors:** a failed field is sent as `***.*`. Treat it as NaN, which maps to the SENSOR ERROR state.
- **Parsing:** parse by key (`O2`, `He`, `Ti`, `hPa`, timestamp), not by column position.
- **TODO:** capture 10+ real lines from the trimix SOLO, including an error line, and commit them as fixtures under `test/fixtures/analyzer/`.
- **TODO:** record the USB VID/PID with `system_profiler SPUSBDataType`. It is needed for the Android device filter and for port auto-detect.

## Architecture

```
lib/analyzer/
  protocol/solo_line_parser.dart   # pure Dart, no Flutter/IO (same rule as shearwater/parser)
  protocol/analyzer_reading.dart
  stability.dart                   # pure Dart
  transport/analyzer_transport.dart        # abstract: Stream<String> lines, connect/disconnect, status
  transport/desktop_serial_transport.dart  # flutter_libserialport (macOS/Windows/Linux)
  transport/android_usb_transport.dart     # usb_serial (CDC-ACM over OTG)
  transport/ble_bridge_transport.dart      # flutter_blue_plus, Nordic UART Service (phase 2)
  transport/demo_transport.dart            # simulator for UI work and tests
lib/ui/screens/analyzer_screen.dart
```

Every transport only produces text lines. The parser, stability logic and UI do not know which transport they are fed by. This mirrors the existing `shearwater/parser` vs `shearwater/ble` boundary.

## Tasks

### 1. Parser (pure Dart, unit tested)
- [ ] `AnalyzerReading { double o2, he, tempC, baroHpa; DateTime? deviceTime; String raw }`. Missing fields are null; `***.*` becomes NaN.
- [ ] `parseSoloLine(String)` returns `AnalyzerReading?`, or null for non-data lines. With no `He` field (O2-only SOLO), set he = 0.
- [ ] Tests: SOLO O2 line, real trimix fixture, asterisk error line, garbage line, a partial line with no CRLF.

### 2. Gas maths: reuse existing code, do not duplicate
- [ ] END: use `lib/analysis/end.dart` and respect the `endCountsOxygen` setting.
- [ ] MOD: `(ppO2 / fO2 - 1) * 10` (seawater, 10 m/bar). Check `lib/analysis/deco/` and `gas_safety_readout.dart` for an existing helper first; extract a shared one if none exists.
- [ ] Show MOD at **ppO2 1.1, labelled "CCR dil" (max ppO2 on the diluent for a rebreather)**, 1.4 and 1.6. Make the ppO2 set a setting, default `[1.1, 1.4, 1.6]`.
- [ ] Minimum depth for hypoxic mixes: `(0.16 / fO2 - 1) * 10`; show "surface" if ≤ 0.
- [ ] Gas density at MOD 1.4: reuse `lib/analysis/gas_density.dart` with the existing thresholds 5.2 / 5.7 g/L.
- [ ] Mix naming: Air (20.5–21.5 % O2), EAN xx, Trimix O2/He, Heliox O2/He (O2+He ≥ 99), Oxygen, Hypoxic xx %. Match the existing naming in `GasMixRow` if it differs.

### 3. Stability detection (fix from prototype v1)
- [ ] v1 (8 samples, max−min ≤ 0.15) flagged STABLE too early, while the galvanic O2 cell was still drifting.
- [ ] v2 rule, implemented in the prototype and still to be validated on real cylinders: over the last **20 samples (~20 s at 1 Hz)**, for both O2 and He, spread (max−min) ≤ **0.2 %** AND |least-squares slope| ≤ **0.01 %/s**.
- [ ] Make window, tolerance and slope named constants, then tune them against real analyses (air, EAN32, O2, a hypoxic trimix).
- [ ] States: NO DATA / SETTLING / STABLE / SENSOR ERROR.

### 4. Desktop transport
- [ ] Add `flutter_libserialport`. Port picker; preselect `usbmodem*` / known VID.
- [ ] Open at 115200 8N1, set DTR, split the stream on `\r?\n`.
- [ ] **macOS sandbox:** add `com.apple.security.device.serial` to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`. Without it the sandboxed app cannot open `/dev/cu.*`.
- [ ] Handle unplug. If connected but there are no lines after ~4 s, show the hint: enable "Send data to USB" and turn printer mode off.

### 5. Android transport (USB OTG)
- [ ] Add the `usb_serial` package (supports CDC-ACM). Add the `USB_DEVICE_ATTACHED` intent filter and `res/xml/device_filter.xml` with the SOLO VID/PID, so Android offers to open Anchorline when the analyzer is plugged in.
- [ ] Request USB permission at runtime. Same 115200 8N1 + DTR.
- [ ] Note: the phone powers/charges the analyzer over OTG. That is acceptable, but mention it in the UI.

### 6. iPhone (phase 2): BLE bridge
- [ ] iOS apps cannot talk to a generic USB CDC serial device; that needs MFi / External Accessory. USB DriverKit exists only on M-series iPads, not on iPhone. **A direct USB connection on iPhone is not possible.**
- [ ] Plan: a small bridge dongle. An ESP32-S3 acts as USB host using the ESP-IDF `usb_host_cdc_acm` component and forwards the lines over BLE with the Nordic UART Service. The app uses the existing `flutter_blue_plus` stack and gets `ble_bridge_transport.dart`.
- [ ] Bonus: the bridge also works on Android and desktop, so there is no cable to the phone at the fill station.
- [ ] Optional: the bridge could also drive a label printer (ZPL over BLE/serial).

### 7. Live analyzer screen (UI)
- [ ] Big O2 (`AnchorlineColors.reelOrange` / theme `accentPrimary`) and He readouts, N2 balance, mix name, stability pill.
- [ ] Planning card: MOD 1.1 (CCR dil), MOD 1.4, MOD 1.6, END, min depth, density, gas temp, ambient pressure.
- [ ] Live chart of the last 2 minutes (O2 + He) to show settling.
- [ ] Use theme tokens (`lib/ui/theme/tokens.dart`); no hard-coded colours. The prototype's hex values are approximate.
- [ ] Phone layout first (portrait, one column). Desktop uses the prototype's grid.

### 8. Save analysis / cylinder log
- [ ] Save the current reading with cylinder (link to the Equipment → cylinders entity), diver, fill pressure (bar), O2, He, mix, the MOD set, temp, timestamp and the `stable` flag. Warn when saving a non-stable reading, but do not block it.
- [ ] New user-editable entity: include sync metadata and owner_id, add it to `infra/powersync-sync-rules.yaml`, and add the grant in the migration (see CLAUDE.md principles 6 and 7).
- [ ] Offer analysed gases in the blender and planner, and when assigning gases to a dive.
- [ ] CSV export: time, cylinder, diver, mix, o2, he, mod_1_1, mod_1_4, mod_1_6, pressure_bar, temp_c, stable.

### 9. Later
- [ ] Cylinder label printing (ZPL to Zebra, or a PDF label).
- [ ] The demo transport doubles as a widget-test driver (gas arrives after 3 s and settles to 18.2/45.1; see prototype).

## Notes for Claude Code
- Start in Plan Mode. The parser and stability code are pure Dart with unit tests; build them first.
- Scope: this is outside the Shearwater Phase 1 list. Treat it as a separate track and do not touch the Shearwater parser.
- All code, comments, commits and PR text in English.
