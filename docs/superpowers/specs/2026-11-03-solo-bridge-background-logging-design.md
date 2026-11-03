# SOLO bridge and background analysis logging — Design

**Date:** 2026-11-03
**Status:** Draft for Egbert's review. Nothing is built yet.
**Issues:** #113 (ESP32 USB-to-BLE bridge). Background logging gets its own issue once this is approved.
**Related:** `2026-10-27-gas-analyzer-solo-design.md` (analyzer, section 6 is the bridge sketch), `2026-10-31-cylinder-label-printing-design.md` (#114, desired mix, gas role, labels), the analysis log (#111).

## Why

Egbert analyses his cylinders at his own fill station with a Divesoft SOLO. Today the SOLO reaches Anchorline only over a USB cable (CDC on Android, serial on desktop). iPhones can't talk to a USB serial device at all, which is why #113 plans an ESP32 bridge that passes the SOLO's serial lines to the phone over Bluetooth LE.

With the bridge in place, the analysis can stop being a phone task. Egbert's words:

> "I want the option that when the user presses "OK" on the SOLO, the data freezes (is stable) and a log should be saved in anchorline. This way it works non obstructive. The user can change the desired mix, and analysed signoff later."

So: switch the bridge on, analyse cylinders on the SOLO as usual, keep the phone in a pocket. Each analysis lands in the log by itself. The diver signs the entries off later, and only then prints labels.

## What Egbert decided (brainstorm, 2026-11-03)

1. **Trigger.** OK on the SOLO if the SOLO's USB stream shows it; otherwise "the reading went stable". Both are fine for him.
2. **Room air is never logged in background mode.** An idle SOLO on the bench is the main problem to avoid. Room air is the Air band: O2 20.5–21.5 % with He between 0 and 1 %. Air cylinders are saved by hand on the analyzer screen, as today.
3. **Sign-off before printing.** An automatic entry can't be printed until it is signed off. A cylinder and gas type (DIL / BO / DECO) should preferably be assigned too.
4. **Switch the bridge on and it works.** No need to open Anchorline first.
5. **The bridge's own screen is the status display:** settling, stable, saved, and errors such as "connection lost".
6. **Auto-save also happens on the analyzer screen** when logging is on. Every save can be changed or deleted.

Standing constraints (from earlier sessions): the bridge must not power or charge the SOLO, so its 5 V output stays switchable in firmware until the power-meter bench shows what the SOLO needs. Avoid new Dart dependencies (the project uses `flutter_blue_plus` 1.36.8). New synced columns need the migration deployed before the build ships. Everything in git is English.

## Goals

- An ESP32-S3 bridge that forwards the SOLO's USB serial output over BLE, shows a status screen, and runs on an 18650 cell.
- A BLE bridge transport for the analyzer screen on iOS, Android and macOS (the core of #113).
- **Background logging** on iOS and Android: with the option on, the phone connects to the bridge whenever it is switched on, also with the app in the background, the screen locked, or the app not running, and saves one analysis per cylinder by itself.
- **Sign-off** for automatic entries: desired mix and "analysed by" filled in later; no label until then.
- Clear feedback on the bridge screen for every outcome, including the ones where nothing was saved and why.

## Non-goals (v1)

- Background logging over a USB cable (Android OTG) or on desktop. Desktop may use the bridge as a live transport on the analyzer screen; it does not log by itself.
- Phone notifications on iOS. The bridge screen is the feedback. (Android shows its required foreground-service notification; see "Android".)
- Printing automatically. Printing stays a deliberate act after sign-off.
- Buffering readings on the bridge while no phone is connected.
- Using the bridge's buttons. They stay free for later ("save now", "skip").
- Surviving a user force-quit on iOS. Apple's AccessorySetupKit on iOS 26 would allow it; left for later.
- BLE bonding or encryption. The data isn't secret; see "Calls to check".
- Over-the-air firmware updates, a web flasher, other analyzers.
- Pairing more than one bridge per phone.

## Anti-goals

These would make the feature a failure even if it technically works:

- **An unsigned automatic entry printed as a label**, from any screen.
- **Room-air entries piling up** from an idle SOLO on the bench.
- **A silent miss:** the diver finishes a cylinder, nothing was saved, and nothing says why. The bridge screen must always say what happened (saved, air not logged, sensor error, save failed, phone not connected).
- **Several entries for one cylinder** because the reading flickered at the edge of the stability rule.
- **Losing an analysis to the network or the link.** The save is local first, as today.
- **The bridge charging the SOLO from its own battery** before Egbert has decided that is acceptable.
- **A phone battery drain while no bridge is around.** No scanning loops; waiting is left to the operating system (iOS pending connection, Android companion-device presence).

## How it fits together

```
 SOLO ──USB-C──► ESP32-S3 bridge ──BLE──► phone (Anchorline)
                 │ USB host, CDC-ACM        │ BleBridgeTransport (lines)
                 │ forwards raw bytes       │ AnalyzerController (parser, stability)
                 │ screen: status           │ AutoSaveTrigger (pure Dart)
                 │ 18650, 5 V switch        │ AnalysisAutoLogger (app-wide service)
                 ◄── display messages ──────┤ GasAnalysesDao → PowerSync → Supabase
```

The bridge is a plain pipe with a screen. **All decisions stay in the app's Dart code**, next to the existing parser, stability detector and fixtures: what a reading is, whether it is stable, whether it is room air, whether to save. The bridge only knows about things it can see directly: whether a phone is connected, whether a SOLO is plugged in, whether bytes arrive, and its battery.

The same transport boundary as today applies: `BleBridgeTransport` implements `AnalyzerTransport` and only produces text lines. The parser, stability detector, controller and UI don't know it is BLE.

## 1. When the app saves an analysis

### The trigger: one save per stable plateau

A new pure-Dart component, `AutoSaveTrigger` (in `lib/analyzer/`, no Flutter, no I/O), watches the controller's readings and stability state and decides when to save.

- **Save when the reading becomes STABLE**, using the existing `StabilityDetector` with its current rule (20 s window, spread ≤ 0.2 points, |slope| ≤ 0.01 points/s, O2 and He). Save at the first STABLE reading, not at the end of the plateau, so "Saved" appears while the diver is still on the cylinder.
- **Never save room air.** Room air is **O2 20.5–21.5 % with He between 0 and 1 %** (Egbert's decision). That is the band `gas_naming.dart` names `Air`, with the same 1.0 % helium floor. A small negative He reading (the SOLO can show −0.2 %) counts as 0. Such a reading is never saved automatically, whether it is stable or the OK was pressed. The bridge shows "Air — not logged".

  **This relies on a calibrated SOLO.** The 2026-10-31 capture was taken on air but reads O2 19.7 %, which is outside the band: that idle SOLO would be logged as "Hypoxic 20". Egbert chose the narrow band over a wider one (19.5–22.5 %), which would have skipped EAN22 and hypoxic nitrox as well. A calibration hint is not part of this work.
- **Never save a sensor error** (`***.*`, NaN). It can't become STABLE anyway.
- **One save per plateau.** After a save, the next save needs the trigger to re-arm. It re-arms when:
  - the reading has been out of STABLE for at least **10 s in a row**, or
  - the reading has moved **≥ 1.0 point** in O2 or He away from the saved values, or
  - the SOLO was unplugged or the link was down for more than 2 minutes.

  A short flicker at the edge of the tolerance (STABLE → settling → STABLE in a second or two) does not re-arm, so it can't create a second entry. Taking the flow restrictor off one cylinder and putting it on the next gives a long unstable stretch, so two cylinders of the same mix still give two entries. All three limits are named constants, tuned at the bench.
- **Reconnects.** When the BLE link drops, the controller session restarts and the 20 s window starts over. If the link comes back within 2 minutes and the first STABLE reading is within 0.3 points (O2 and He) of the last automatic save, it is the same plateau and nothing new is saved.

### The OK button: decided by a capture

What the SOLO sends when OK is pressed is not known yet:

- The SOLO manual (2022, FW 2.29) documents OK only as **suspend/resume measuring**: "the last measured values remain displayed". It says nothing about the USB stream during suspend, and documents no marker, save or record function. The manuals also say one line per second; the real unit sends about five.
- The committed capture (`test/fixtures/analyzer/solo_trimix_air_2026-10-31.txt`) has no marker. It does have a 22 s gap after a cut-off line (15:42:15 → 15:42:37), but the commit describes it as one 20 s capture, so the gap can't be told apart from the capture tool restarting.

This can be settled **now, without the bridge**: the SOLO already works over USB on the Mac. See "Capture plan". Three outcomes, and what the trigger does with each:

| What the capture shows during suspend | OK detection |
|---|---|
| **A. The stream stops** while the SOLO stays plugged in | No line for ≥ 2 s (normal spacing is ~0.2 s) while the bridge still reports the SOLO attached → OK. Save the last reading, unless it is air, a sensor error, or this plateau was already saved. The `stable` flag is the detector's state at that moment. When lines come back, the re-arm rules above apply. |
| **B. Lines continue, frozen** (same values, clock field stops advancing) | ≥ 2 s of byte-identical lines with a frozen clock → OK, handled as in A. |
| **C. The stream carries on live** | No OK signal. The stable plateau is the only trigger. |

OK and STABLE never create two entries for one plateau: whichever comes first saves, and the other is a no-op until the trigger re-arms. If the capture shows A or B, the OK detector is added to `AutoSaveTrigger`, with the capture committed as a fixture. With outcome C, nothing more is needed: Egbert said stable alone is fine.

Outcome A affects the bridge's "No data from SOLO" message: a suspended SOLO is not a SOLO with USB output turned off. The app tells the bridge "held"; see the display states.

### What an automatic entry holds

The same row as a hand-saved analysis (`NewGasAnalysis`), filled from the reading and the phone:

- `analysed_at`: the phone's clock when the trigger fired (as with manual saves, the SOLO's clock is not used).
- `o2_percent`, `he_percent`, `temp_c`, `baro_hpa`: from the reading that fired the trigger.
- `stable`: 1 for a plateau save; the detector's state for an OK save.
- `mod_ppo2s`: the device's current MOD ppO2 setting, as with manual saves.
- `cylinder_id`, `analysed_by`, `fill_pressure_bar`, `notes`, desired mix: empty, except on the analyzer screen, where whatever the diver already filled in on the save card goes in (see section 2).
- `gas_role`: null until sign-off (reads as bailout/deco, as today), or what the card had.
- **New:** `source = 'auto'` and `signed_off_at = null`; see section 2.

## 2. Sign-off

### Data

Two nullable columns on `gas_analyses`, in one new migration (the next free number; 0021 may already be claimed by the Subsurface sync-service spec):

- `source text`: `null` (or `'manual'`) for a hand-saved analysis, `'auto'` for one saved by the logger.
- `signed_off_at bigint`: millis since epoch when the diver signed off an automatic entry.

**An entry needs sign-off when `source = 'auto'` and `signed_off_at` is null.** Every existing row and every hand-saved row counts as signed off, so the manual flow and old data don't change.

The table already exists, so the migration adds no grants or publication change (as with 0020). The sync rule is `SELECT * FROM gas_analyses`, so it picks the new columns up with no change; check that this is what is deployed. Add the columns to `lib/sync/cloud/powersync_schema.dart`. **Deploy the migration before shipping a build that writes these columns:** the upload connector sends the whole row.

Older builds on other devices don't know `source`. They show an automatic entry like any other and would let it be printed there. This is accepted (Egbert's devices update together).

### Rules

- **Signing off needs a desired mix and "analysed by".** Cylinder and gas role are asked for and preselected where possible, but not required ("preferably").
- **Picking a cylinder preselects its gas role** (`gasRoleForCylinderRole`), as the save card does.
- **"Analysed by" is prefilled** with the last name used on this device.
- **After sign-off the entry stays editable** (desired mix, role, analysed by, notes, cylinder, fill pressure). An automatic entry can't be saved again without a desired mix and "analysed by". Changing a signed entry keeps it signed.
- **The measured values never change** (O2, He, temperature, pressure, time, stable flag). An analysis is a record, like imported dive data.
- **Any entry can be deleted** (soft delete, synced): swipe in the log as today, a Delete button in the edit sheet, and Delete on the analyzer screen right after an automatic save.
- **No label for an entry that needs sign-off.** Enforced in the UI (no print action) and again at the label-printing entry point, so no new code path can bypass it.
- **DIL / BO / DECO is the existing gas-role choice:** "Diluent" or "Bailout/deco", one option printing the bailout/deco label. A separate DECO role is not part of this work.

### UI

- **Analysis log.** Entries that need sign-off are grouped at the top under "Needs sign-off (n)", with a warning-coloured marker and no print action. Tapping one opens the edit sheet in sign-off mode. Where the log is reached from (Blend tab, Equipment), show the count so pending entries aren't forgotten. The builder decides the exact placement.
- **Edit sheet** (`lib/ui/widgets/analysis_edit_sheet.dart`). It gains:
  - a cylinder picker, for every entry, not just automatic ones (today the cylinder is fixed once saved; see "Calls to check");
  - fill pressure;
  - a Delete button;
  - for an entry that needs sign-off, a "Sign off" primary button that stays disabled until the desired mix and "analysed by" are set.
- **Analyzer screen, save card** (`lib/ui/widgets/analysis_save_card.dart`). With logging on, an automatic save shows on the card as "Saved Tx21/35 automatically · needs sign-off", with three actions:
  - **Sign off:** signs at once if the card already supplied a desired mix and "analysed by", otherwise opens the sheet.
  - **Sign off & print:** offered when a printer is set up.
  - **Delete:** undo.

  The card's fields then reset for the next cylinder, as after a manual save (cylinder and diver kept). The manual Save button stays for readings the logger doesn't save (room air, or saving before STABLE). It turns into "Sign off" when the current plateau was already saved automatically, so a tap can't create a duplicate.

## 3. The bridge

### Hardware (ordered 2026-11-01)

- **Espressif ESP32-S3-USB-OTG.** It has:
  - a female USB-A host port for the SOLO (A-male to C-male cable);
  - a male USB-A device plug for flashing and charging;
  - a 1.3-inch 240×240 colour LCD and buttons;
  - a battery charging IC;
  - a 5 V boost converter, with the MIC2005A 500 mA limit switch on `IDEV_LIMIT_EN` = GPIO17;
  - host-port power selection through `BOOST_EN` / `DEV_VBUS_EN`.

  Check that the board as delivered matches the Espressif user guide.
- **One 18650 cell** (the same cells as Egbert's X-CCR), soldered to the battery pads. Use a protected cell, or let the firmware cut off at low voltage (below).
- **A YEREADW USB-C power meter** for the bench.

### Firmware: where and how

- **In this repo, under `firmware/solo_bridge/`**: an ESP-IDF (v5.x) project in C, GPL like the app. It versions with the app protocol, and the planned DIY kit (project 3 of the label spec) needs it public anyway. A Dart-only rule can't apply here: nothing runs Dart on an ESP32.
- Components:
  - ESP-IDF `usb_host_cdc_acm` for the SOLO;
  - NimBLE for BLE;
  - the `espressif/esp32_s3_usb_otg` board support package for the LCD, buttons and power pins.

  Using LVGL or plain text drawing is the builder's call.
- No CI job in v1. A build job can come with the cloud-builds work.

### What the firmware does

1. **USB host.** Waits for a CDC-ACM device and opens it. It prefers VID 0xA600 / PID 0xE212 (the SOLO) but accepts any CDC-ACM device, so an O2-only SOLO also works. Sets the line coding to 115200 8N1 and raises DTR, like the other transports.
2. **Stale burst.** Drops every byte for the first 300 ms after opening, then up to and including the next `\n`, mirroring `OpenBurstFilter`. The app's 20 s stability window would ignore a stale burst anyway, but this keeps the stream clean.
3. **Forwarding.** Sends the bytes unchanged over BLE (below) while a phone is subscribed. Lines are never buffered or re-framed. With no phone connected, bytes are dropped.
4. **5 V to the SOLO.** Host-port power is a firmware setting stored in NVS:
   - `off`: the default until the bench says otherwise;
   - `on`: through the 500 mA limit.

   It can be changed from the app's bridge settings (a debug control) and is shown on the bridge screen. The bench decides the default (see "Bench plan"). If the SOLO only enumerates with host 5 V, it will charge from the bridge's 18650 while connected. Egbert decides then whether that's acceptable. It isn't decided here.
5. **Battery.** Measures the cell voltage. Warns on screen at 3.5 V and shuts down (deep sleep, screen off) at 3.3 V, so an unprotected cell isn't drained.
6. **Advertising.** Name `Anchorline Bridge`, plus the bridge's service UUID, whenever no phone is connected. One phone at a time.

### BLE protocol

Two GATT services. Their UUIDs live in one firmware header and one Dart file, `lib/analyzer/transport/bridge_ids.dart`, like `solo_usb_ids.dart`.

- **Nordic UART Service** (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`), the standard, so nRF Connect can debug it.
  - **TX (`6E400003…`, notify):** the SOLO's raw serial bytes, chunked to the negotiated MTU. The app feeds them through the existing `SerialLineBuffer`. At ~5 lines/s × ~75 bytes this is under 400 bytes a second.
  - RX (`6E400002…`) is unused in v1.
- **Anchorline bridge service** (custom 128-bit UUIDs). Payloads are short ASCII `key=value;` pairs, readable in nRF Connect and trivial to parse on both sides:
  - **`bridge_state` (read, notify)**, for example:
    ```
    fw=1.0.0;proto=1;solo=1;data=1;vbus=0;batt_mv=3912;vid=a600;pid=e212
    ```
    It is sent on every change and every 30 s.
    - `solo`: a CDC device is attached.
    - `data`: bytes arrived in the last 4 s.
  - **`display` (write without response), app → bridge**, for example:
    ```
    s=saved;mix=Tx21/35;n=3;seq=17
    ```
    - `s` is a state code from the table below.
    - `mix` is the name the app computed with `gasMixName`.
    - `n` is the number of entries that need sign-off.

    The app writes on every state change, and at least every 3 s as a heartbeat while connected.
  - **`control` (write)**, for example `vbus=on`. It is used for the 5 V setting; room is left for more.
- `proto` lets the app refuse a bridge whose protocol it doesn't know, with a message saying the firmware should be updated.

### Bridge screen

The text is English. The app sends codes; the bridge owns the wording, so the app never sends free text.

**Shown by the bridge on its own** (these override the app's states):

| Situation | Screen |
|---|---|
| No phone has connected since power-on | "Waiting for phone" |
| The phone was connected and the link dropped | "Connection lost — waiting for phone" |
| Connected, but no `display` write for 10 s | "Phone not responding" |
| No CDC device attached | "No SOLO" |
| SOLO attached, no bytes since it was attached | "No data from SOLO — turn on Send data to USB" |
| SOLO attached, bytes stopped after flowing, and the app hasn't said `held` | "SOLO paused" |
| Battery low / cut-off | battery warning / "Battery empty" |

**Sent by the app** (`s=`):

| Code | Screen |
|---|---|
| `settling` | "Settling…" with the live mix name |
| `stable` | "Stable · Tx21/35" (stable, but saved already or not saving) |
| `saved` | "Saved Tx21/35 · 3 to sign off". Stays until the trigger re-arms, so a glance after taking the hose off still shows it. |
| `held` | "Held · saved Tx21/35" (OK detected, outcomes A/B) |
| `air` | "Air — not logged" |
| `sensor_error` | "Sensor error" |
| `save_failed` | "Save failed — check the phone" |
| `logging_off` | "Live — not logging" (connected live, automatic saving off or not available, e.g. macOS) |

A small status line shows battery, 5 V on/off and firmware version.

## 4. Staying connected

### One app-wide logger

`AnalysisAutoLogger`, an app-level service started from `main()`, owns the bridge session for the whole app:

- the `BleBridgeTransport`, an `AnalyzerController` and the `AutoSaveTrigger`;
- the `GasAnalysesDao` writes and the `display` writes;
- a listenable state for the UI.

The analyzer screen gets a "SOLO bridge" transport option (on iOS it is the only real one). When the logger already holds the bridge, the screen **attaches to the running session** instead of opening a second one. A bridge accepts one phone at a time and one connection per phone.

Background launches (iOS state restoration, Android companion-device wake-ups) run the normal `main()` without a visible UI. One engine, one PowerSync database, no second Dart entry point. `main()` must not do anything at startup that needs the foreground (permission prompts, location); the builder checks this. Neither platform does this out of the box; see "Keep Dart alive" under iOS and Android.

**Where automatic saving applies.** Only in the logger's bridge session, on iOS and Android. USB sessions on the analyzer screen (Android OTG, desktop serial) and the bridge used as a live transport on macOS stay manual, as today. The "Log analyses automatically" switch lives in the SOLO bridge settings and is shown only on iOS and Android. `logging_off` on the bridge screen means a phone or Mac is connected live with automatic saving off.

**Signed out works too.** The subscriptions spec promises that "the app works fully without an account", and hand-saved analyses already save while signed out (`owner_id` null). The logger does the same. On sign-in, `OwnerIdBackfiller` must claim those rows. **Today it doesn't:** `gas_analyses` is missing from `_syncedTables` in `lib/sync/cloud/owner_id_backfiller.dart`. As a result, analyses saved while signed out disappear from the log after signing in, because `list()` then filters on `owner_id`. Adding the table fixes the existing manual path as well. It is part of rollout step 3.

### Pairing and settings

**Settings → Analyzer** gets a "SOLO bridge" section, next to the label printer section:

- **Pair:** scan on iOS; the companion-device dialog on Android.
- **Bridge details:** name, firmware, battery, last seen, and the 5 V debug control.
- **"Log analyses automatically"** switch.
- **Forget bridge.**

These settings are device-local (SharedPreferences), like the printer pairing: a BLE id only means something on the phone that paired it.

### iOS

- Add `UIBackgroundModes` → `bluetooth-central` to `ios/Runner/Info.plist`. Update the Bluetooth usage strings to mention the SOLO bridge.
- **Keep Dart alive: an explicit engine.** Today the app uses UIScene with Flutter's implicit engine:
  - `AppDelegate: FlutterImplicitEngineDelegate`, `SceneDelegate: FlutterSceneDelegate`, storyboard `Main`;
  - that engine is only created when a scene connects and the storyboard's `FlutterViewController` loads;
  - a Bluetooth background relaunch connects no scene, so **no Dart would run**;
  - `flutter_blue_plus_darwin` creates its `CBCentralManager` (with the restore identifier) only on the first call from Dart, so `willRestoreState` would never fire either.

  The fix is the iOS twin of the Android cached engine:
  1. In `application(_:didFinishLaunchingWithOptions:)`, create and run one `FlutterEngine`, and register the plugins on it.
  2. Have the scene's `FlutterViewController` attach to that engine.

  This changes app-wide startup and plugin registration, which the Shearwater import and the printer depend on, so test a normal launch, a resume and a background relaunch. If Flutter's UIScene API turns out not to support a pre-made engine, v1 falls back to "backgrounded or screen locked" only (the engine is still alive in those cases), and the relaunch case becomes a follow-up. Egbert is told before that fallback is taken.
- Call `FlutterBluePlus.setOptions(restoreState: true)` once, at the top of `main()`, before any other `flutter_blue_plus` call. Then touch the adapter (for example `FlutterBluePlus.adapterState`), so the central manager exists while iOS is still within the launch window. 1.36.8 supports it: it sets `CBCentralManagerOptionRestoreIdentifierKey` and reconnects restored peripherals in `willRestoreState`. This is app-wide, so the Shearwater import and the label printer share it.
- With logging on, keep a **pending connection** to the stored bridge: `connect(autoConnect: true, mtu: null)`, then request the MTU after connecting. iOS keeps it open with no timeout and no scanning, and connects when the bridge powers on.
- What then works ([TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules.md)):
  - app in the background or the screen locked: yes;
  - app closed by iOS: yes, relaunched in the background when the bridge connects;
  - phone restarted: yes, with the caveats in TN3115;
  - **app force-quit by the user: no**, until it is opened again.

  The settings section says this in one line.
- Each BLE notification wakes the app. The trigger is event-driven: no Dart timer has to fire while the app is suspended. The `display` heartbeat rides on incoming data.
- On restoration, iOS may hand back other peripherals as well, such as the printer or a Petrel that was connected when the app was killed. The logger keeps only the bridge; restored peripherals that aren't the bridge are disconnected, so the Shearwater import never sees a surprise connection.
- Side effect: `bluetooth-central` also keeps BLE callbacks running when the screen locks during a Shearwater import (today `wakelock_plus` covers this). No change to the import is planned here.
- **App Store review:**
  - Explain in the review notes that the app talks to an analyzer bridge while in the background and why.
  - Attach a short video, because the reviewer has no bridge.
  - The background mode only does work while the bridge is connected.

### Android

Android needs native code. `flutter_blue_plus` has no background support, and its docs point to an extra plugin, which the project avoids. The project already has in-app Kotlin (`UsbSerialChannel.kt`), so this follows the same pattern.

- **Android 12+ (API 31): companion device presence.**
  1. Pairing uses `CompanionDeviceManager.associate` with a BLE filter on the bridge service UUID. A system dialog appears once, and it needs no location permission.
  2. The app then observes presence: `startObservingDevicePresence` on API 31–35, `ObservingDevicePresenceRequest` on API 36+.
  3. A `CompanionDeviceService` is bound when the bridge appears, after a reboot too.
  4. From that service the app starts a **foreground service** of type `connectedDevice`. Being a companion-device app is what allows a foreground service to start from the background. The service runs only while the bridge is present, with the notification "SOLO bridge connected · last saved Tx21/35 · 3 to sign off". It stops when the bridge goes away.
  5. The Dart side connects with `flutter_blue_plus`, using the MAC address from the association.
- **Keep Dart alive.** The Flutter engine is created once, in the `Application` (or by the service on a cold start), and cached. `MainActivity` attaches to that cached engine, so swiping the activity away doesn't destroy the engine while the foreground service runs. This changes app-wide lifecycle: test that a cold start and a resume behave as before.
- **Manifest:**
  - permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `POST_NOTIFICATIONS` (asked at runtime on 13+), `REQUEST_OBSERVE_COMPANION_DEVICE_PRESENCE`, `REQUEST_COMPANION_RUN_IN_BACKGROUND`, `REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND`;
  - `uses-feature android.software.companion_device_setup` (not required);
  - the two services.

  `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` are already declared.
- **What then works:**
  - background and screen off: yes;
  - after a reboot: yes;
  - swiped away: yes on most phones (some vendors force-stop on swipe);
  - "Force stop" in Settings: no.
- **Android 11 and older:** logging works only while Anchorline is open, with no foreground service.

### Coexistence

The bridge, the label printer and a Shearwater import can be connected at the same time; `flutter_blue_plus` handles several devices. If the analyzer screen uses USB instead (Android, desktop), the bridge has no SOLO and says so. Two phones armed for the same bridge: the first one to connect wins.

## 5. Failure cases

| Case | What happens |
|---|---|
| Double OK press | OK toggles suspend/resume; the plateau rule allows one save per plateau. No duplicate. |
| Reading flickers at the stability edge | Doesn't re-arm (needs 10 s out of STABLE or a 1-point move). No duplicate. |
| BLE link lost mid-reading | The bridge shows "Connection lost". On reconnect the window restarts. A reconnect within 2 minutes on the same values is the same plateau: no duplicate. A cylinder that wasn't stable yet simply settles again. |
| Link lost right after "Saved" | The entry is already stored locally. Nothing is lost. |
| No network | The save is local (PowerSync) and uploads later, as the log already does. |
| Signed out | Saved locally with no owner, as hand-saved analyses are; claimed by `OwnerIdBackfiller` on sign-in (once `gas_analyses` is added to it). |
| Database write fails | The bridge shows "Save failed — check the phone"; the error is logged to Sentry. The trigger re-tries once on the next reading of the same plateau. |
| SOLO unplugged or switched off mid-reading | The bridge shows "No SOLO". Nothing is saved for an unfinished plateau. |
| "Send data to USB" off | The bridge shows the hint. |
| Stale burst on plug-in | Dropped by the firmware. It couldn't form a 20 s plateau anyway. |
| iOS: app force-quit | No logging until Anchorline is opened. The bridge shows "Waiting for phone". |
| Bridge battery low | Warning, then a clean shutdown at 3.3 V. |
| Unknown bridge protocol version | The app refuses with "Update the bridge firmware". |

## 6. Capture plan (now, on the Mac)

This settles section 1's OK question before the bridge hardware arrives (9–16 Nov).

1. Add a small Dart CLI in `tool/`, for example `tool/solo_capture.dart`. It reuses `lib/analyzer/transport/native_serial_port.dart` and prints each raw line with its arrival time in milliseconds. It needs no new dependency, and it records arrival gaps, which a plain `cat` of the port can't.
2. With the SOLO on USB and "Send data to USB" on, record these as separate runs:
   - 30 s on room air; OK; 20 s held; OK again; 20 s.
   - The same on a gas cylinder (EAN or trimix).
   - ESC, MODE and CAL once each, to see whether any key leaves a trace.
   - Unplug and replug once.
   - If the "Send data to USB" setting offers more values than on/off, one run per value.
3. Commit the runs as fixtures under `test/fixtures/analyzer/`, CRLF kept byte-exact, with a short README of what was pressed when.
4. Decide A, B or C from the table in section 1, with Egbert.

## 7. Bench plan (bridge hardware)

1. **Power** (Mac → meter → SOLO, then bridge → meter → SOLO):
   - Does the SOLO enumerate with the bridge's host 5 V off?
   - What does it draw with 5 V on, charging and while measuring?

   Record the readings in `firmware/solo_bridge/README.md` and set the 5 V default from them, with Egbert.
2. **Pass-through:** the analyzer screen shows live readings from the bridge on iOS, Android and macOS. Compare against the USB capture.
3. **Battery:** run time on one 18650 with the screen on; cut-off behaviour.
4. **Background matrix** on Egbert's iPhone and an Android phone:
   - app in the background;
   - screen locked;
   - app killed by the system (on iOS, kill the process from a debug build);
   - phone restarted;
   - force-quit or swipe-away.

   In each state, switch the bridge on and analyse two cylinders of the same mix and one of air. Expected: two entries, no air entry, and the right screen states.
5. **Tune** the re-arm constants (10 s, 1.0 point, 0.3 point, 2 min) on real cylinders.

## 8. Testing

- **Pure Dart, unit tests:**
  - `AutoSaveTrigger`: plateau save; room-air skip; re-arm rules; flicker; reconnect dedupe; OK signatures A/B once captured;
  - the bridge state/display codecs;
  - `BleBridgeTransport` byte-to-line handling (through `SerialLineBuffer`).

  Feed them the real captures plus synthetic plateaus built from real lines, with an injected clock as in `analyzer_controller_test`.
- **Widget tests:**
  - sign-off mode of the edit sheet (required fields, Delete, cylinder picker);
  - "Needs sign-off" in the log, with no print action;
  - the save card's automatic-save state;
  - printing refused for unsigned entries.

  Use the demo transport to drive the logger.
- **DAO tests:** `source` / `signed_off_at` round-trip; sign-off; edit keeps the measured values.
- **Native code** (iOS restoration, Android companion device and foreground service, firmware) is checked on hardware with the bench matrix, like the Phomemo BLE code.
- `flutter analyze` clean, `flutter test` passing. Don't `dart format` whole files.

## 9. Rollout order

Each step is its own PR, following issue → branch → PR. Steps 1 and 3 don't need the hardware.

1. **OK capture** on the Mac: the CLI and fixtures. Decide A/B/C.
2. **Firmware v0:** USB host → NUS pass-through, 5 V switch, `bridge_state`, a basic screen. Power bench. Gate: the SOLO's lines arrive on a phone.
3. **Sign-off data and UI:** migration (deployed first), schema, DAO, edit sheet (cylinder, pressure, Delete, sign-off mode), log grouping, print guard. Also add `gas_analyses` to `OwnerIdBackfiller`. Testable with hand-made `source='auto'` rows.
4. **`BleBridgeTransport`** and the analyzer screen's "SOLO bridge" option on iOS, Android and macOS, in the foreground. This closes #113's core.
5. **`AutoSaveTrigger` and `AnalysisAutoLogger`** in the foreground; `display` writes and the full bridge screen; the save card's automatic-save state.
6. **Background:** iOS (explicit engine in `AppDelegate`, background mode, restoration, pending connection) and Android (companion device, foreground service, cached engine). Bench matrix.
7. **App Store submission notes** and video; Play listing note for the foreground service.

## Left to the builder

- Exact class and file names beyond those given, and widget layout.
- LVGL or plain text on the LCD; fonts; screen layout within the states above.
- The custom GATT UUIDs (generate once, never change).
- Exact chunking and MTU handling on the NUS TX characteristic.
- How the sign-off count is shown where the log is reached.
- Whether `source` is also exported in the CSV.
- How the Android cached engine is wired (Application vs service-created), as long as there is one engine.

## Calls to check

Calls I made that Egbert didn't state. Each one is easy to flip.

1. **The room-air rule applies to OK saves too**, not just stable plateaus. A small negative He reading counts as 0 %.
2. **Re-arm rule:** 10 s out of STABLE, or a 1.0-point move, or more than 2 minutes unplugged or disconnected. Reconnect dedupe within 2 minutes and 0.3 points. Tuned at the bench.
3. **Save at the first STABLE reading**, not at the end of the plateau.
4. **Sign-off requires a desired mix and "analysed by"**; cylinder and role are asked for, not required. "Analysed by" is prefilled with the last name used on this device.
5. **Hand-saved entries never need sign-off**; existing rows are unaffected.
6. **The cylinder becomes editable on every entry**, not just automatic ones. The #114 sheet kept it fixed; your "saves can be changed" suggests correcting it should be possible. Fill pressure becomes editable too. Measured values stay locked.
7. **On the analyzer screen, an automatic save stays unsigned** even when the card already had the desired mix and name. Signing off is then one tap, but it stays a deliberate act.
8. **DIL / BO / DECO stays two options** (Diluent, Bailout/deco); no separate DECO role or label.
9. **The firmware lives in this repo** (`firmware/solo_bridge/`, ESP-IDF, C). Your Dart-only rule is for backend services, and the ESP32 can't run Dart.
10. **The bridge is a dumb pipe with a screen:** no buffering, no stability logic of its own, no bonding or encryption. Anyone nearby could connect and read your SOLO lines or write the screen; the risk is low.
11. **The 5 V default is off until the bench.** If the SOLO only works with host 5 V, it will charge from the bridge's 18650, and you decide then.
12. **Signed out works,** as the subscriptions spec promises; rows are claimed on sign-in. This includes the backfiller fix, which also repairs today's manual path.
13. **Android:** background logging only on Android 12+; older versions log only with the app open. The foreground-service notification shows only while the bridge is connected.
14. **iOS:** no phone notifications; the bridge screen is the feedback. Force-quit stops logging until the app is opened.
15. **One engine:** background launches run the normal `main()` without UI, on both platforms, instead of a separate background entry point.
16. **The iOS startup change is in v1** (an explicit engine in `AppDelegate`), because "switch the bridge on and it works" should still hold after iOS has closed the app overnight. If Flutter's UIScene API blocks it, you hear first, and v1 covers backgrounded/locked only.
17. **Automatic saving is a bridge feature on iOS and Android only.** USB sessions and the macOS bridge stay manual.
