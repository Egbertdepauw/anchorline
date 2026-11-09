# Log on OK: background gas-analysis logging through the SOLO bridge — design

**Date:** 2026-11-03
**Status:** merged design, 2026-11-03. Nothing is built. OK detection is measured (§1).
This merges two brainstorms of the same feature. This one, and the bridge-logging spec
(`2026-11-03-solo-bridge-background-logging-design.md`), which Egbert approved and which this file
replaces. Egbert settled the two points where they disagreed: decisions 14 and 11 below.
**Issue:** #113 (ESP32 USB→BLE bridge). New issues get filed per build step (see "Build order").
**Builds on:** `2026-10-27-gas-analyzer-solo-design.md` (analyzer, #104–#113) and
`2026-10-31-cylinder-label-printing-design.md` (labels, #114).

## Why

Analysing gas today means holding the phone: the analyzer screen must be open, and the diver taps
Save, then Print. Egbert works with the phone in his pocket. For each cylinder he analyses it,
labels it and moves on to the next, and **a cylinder must never leave without a label**.

The SOLO has an OK button. Pressing it pauses the measurement and keeps the last values on the
display. This design makes that press the save: the phone stays in the pocket, the app saves the
analysis and, when it has enough to go on, prints the label on the Phomemo M110. Anything the app
can't complete on its own waits in the analysis log, marked "needs sign-off".

iPhones can't talk to the SOLO over USB at all, so this rides on the ESP32 USB→BLE bridge that
#113 already plans. The bridge also lets Android work without a cable to the phone.

## What Egbert decided

1. **The OK press on the SOLO is the trigger.** With "Log on OK" on, the phone can be in a pocket,
   locked, or on another screen of the app.
2. **Printing on OK is wanted, but only with two things set beforehand: "analysed by" and the
   desired mix.** Without them, OK still saves; the entry waits for sign-off in the log and is
   printed from there.
3. **"Analysed by" defaults to the Anchorline user.** The label always carries the name of whoever
   analysed the gas.
4. **Three situations have to work:**
   - *Own blend.* The mix is set up on the Blend page (target and residual), so the desired mix is
     known.
   - *Re-check on the boat or at the dive site.* Divers re-analyse their gas now and then to
     confirm it. The cylinders already carry labels, and often there is no printer.
   - *Filled by a filling station.* Egbert analyses the cylinders himself later. He knows what he
     ordered.
5. **Lining up a mixed batch** (a list of the next cylinders' mixes) would be nice, but it's not
   needed now. It is a later step.
6. **Who the gas is for** is a nice extra: Egbert often blends for other people. It goes in the
   log, not on the label.
7. **Sharing an analysis with another Anchorline user**, so that it appears in their log, would be
   very nice, but later. It is a separate project.
8. **The bridge firmware is Apache-2.0,** the same licence as ESP-IDF. The app stays GPLv2.
9. Standing constraints from earlier work:
   - The bridge must not power or charge the SOLO. Keep the bridge's 5 V output switchable in
     firmware; the power-meter readings decide whether it's needed.
   - No new Flutter dependencies.
   - Everything in git is in English.
   - New synced columns are deployed before a build writes them.
   - Don't run `dart format` on whole files.

From the second brainstorm (the bridge-logging spec) and the merge:

10. **No label before sign-off.** An entry that isn't complete is signed off in the log before it
    prints. A cylinder and a gas role (DIL / BO-DECO) should preferably be assigned too.
11. **An OK press on room air saves nothing:** O2 20.5–21.5 % with He 0–1 %. The bridge shows
    `AIR — NOT LOGGED`, and air cylinders are saved by hand on the analyzer screen (§5). Egbert
    chose this narrow band over a wider one.
12. **The bridge screen is the quick status display:** settling, stable, saved, and errors such as
    "connection lost" (§2).
13. **Every save can be changed or deleted,** also right after it is made.
14. **Sessions first.** "Switch the bridge on and it works", without opening the app, is
    preferred. In v1 a session starts from the analyzer screen, and the always-armed connection is
    the first later step (see "Later").
15. **OK is the trigger.** Saving on "the reading went stable" was the fallback in case OK couldn't
    be detected. The capture shows it can (§1), so there is no stable trigger.
16. **Confirmed in the merge** (Egbert: "I agree with the above"):
    - "Analysed by" and the desired mix, set before the OK, count as the sign-off (decisions 2 and
      10 together). Everything else still needs sign-off before it prints.
    - The bridge keeps each OK press in flash until the app confirms the save (call 2 below).
    - The setup carries over from one cylinder to the next (call 6), and the "for" field goes in
      the log, not on the label (decision 6).
    - The firmware is Apache-2.0 (decision 8).
18. **Print on OK needs only "analysed by"** (Egbert, 2026-11-03 evening, after the first real test). This replaces decision 2's desired-mix requirement and §5's stability rule.
    - **Don't wait on stable.** An OK press is the diver's confirmation, so an unstable reading is saved complete and printed. The `stable` flag is still recorded.
    - **The desired mix is optional.** Without one, the label shows the analysed mix, and there is no mismatch check.
    - **A desired mix picked on the card still gives the check:** red and hard still don't print.
17. **Log on OK also works with the SOLO on a USB cable** (Egbert: "Log on OK can be created
    already for directly connected SOLO"). It runs while the analyzer screen is open, on macOS and
    the other desktops, and on Android with USB OTG (§4c). It doesn't wait for the bridge.

## Goals

- Pressing OK on the SOLO saves a `gas_analyses` row while the phone is in a pocket, on iOS and
  Android.
- When the setup is complete and nothing looks wrong, the same press prints the label.
- **No OK press is ever lost.** Not when the link drops, the app is killed, the phone is out of
  range, the bridge is switched off, or there is no network.
- **No OK press is ever saved twice** because of a retry.
- Unfinished entries are obvious in the log, and can be finished there: sign-off, desired mix,
  cylinder and label.

## Non-goals (this design)

- Lining up a batch. It is designed as the first later step; see "Later".
- Sharing analyses between Anchorline users (a separate project).
- OK logging over a direct USB cable **in the background**. With the analyzer screen open, it is in
  v1 (§4c, decision 17).
- Relaunching a killed app in the background (iOS state restoration). The bridge's queue covers this
  case instead.
- Firmware updates over the air, and printing from the bridge straight to the M110.
- A permanent, all-day background connection. Logging runs in sessions.

## Anti-goals (a failure even if it "works")

- **A label printed without anyone looking, in a case where the on-screen flow would have asked the
  diver first.** The pocket rules are stricter than the screen rules, never looser.
- An OK press that is silently dropped, or an analysis whose measured values are changed after the
  fact.
- Gas logic in the firmware. Depths, mix names, match grades and stability stay in Dart (the
  existing pure code). The bridge moves and keeps bytes; it never judges a gas.
- A persistent notification or a battery drain when the diver isn't analysing.

## How it fits together

```
SOLO ──USB-C (CDC-ACM, 115200 8N1, DTR)──▶ ESP32-S3 bridge ──BLE (Nordic UART)──▶ phone app
                                            │ detects the OK press                  │ checks the reading
                                            │ keeps a record of it in flash         │ saves gas_analyses (PowerSync)
                                            │ until the app confirms it             │ prints the label (M110, BLE)
                                            │ shows the result on its screen ◀──────┘ sends the result back
```

- **The bridge** detects the OK press, which is a fact about the SOLO's USB output. It saves a
  record: the held line plus the last 30 s of lines, each with its time offset. It keeps the record
  in flash until the app confirms the save. Because of this queue, a dead app or a dropped link
  loses nothing.
- **The app** turns a record into an analysis with the existing pure code: `parseSoloLine`,
  `StabilityDetector` over the 30 s window, `gradeMix`, `CylinderLabel`. It then saves the row,
  prints when the rules allow, confirms the record (`ACK`), and tells the bridge what happened
  (`FB`) so its screen can show it.
- **"Log on OK" is an option.** It is remembered on the phone and on the bridge.
  - With it on, every OK press makes a record, even while the app is closed.
  - A **session** keeps the app connected in the background. It starts by itself when the analyzer
    screen connects to the bridge, and ends after the bridge has been gone for 60 minutes, on Stop,
    or when the app is killed.
  - Records made outside a session wait on the bridge, and the app collects them at its next
    connection.

## 1. How the app knows OK was pressed

### What the manuals say

- The Divesoft manuals (SOLO 8300, SOLO O2 8302, He/O2 8313, 2019–2022) describe OK only as a
  toggle: "With the OK key, you can suspend and, by pressing it again, resume measuring." While
  suspended, "the last measured values remain displayed."
- They document no save function, no memory, and no USB marker. They also don't say what the USB
  output does while suspended. The real SOLO sends about 5 lines per second, not the documented 1
  (#127), so its firmware is newer than the manuals.

### What the SOLO does (measured 2026-11-03)

Two captures were taken on Egbert's Mac over USB with `solo_capture.py`, a stdlib-only tool that
logs each line's arrival time and every gap longer than 0.5 s. Egbert's own observations confirm
the results:

| Action on the SOLO | USB output |
|---|---|
| **OK (suspend)** | **The stream stops completely.** Silences of 28.7 s and 20.9 s, with nothing sent while suspended. The second OK resumes it. The SOLO's clock field keeps running through the pause (15:21:00 → 15:21:29) |
| **MODE** | Nothing changes. It only changes the display |
| **Quick double OK** | Short dips of 0.5–1.3 s, with nothing visible on the display |
| **Switch off** | The stream stops and the device leaves USB within 0.6 s of the last line (`Device not configured`) |
| **Opening the port** | A stale burst: buffered old lines all at once, then one cut-off line, then live lines with a jump in the clock field |
| **Normal measuring** | One line every 0.2 s. No gap over 0.3 s in about 130 s of live data |

**The 22 s "hole" in the 31 Oct fixture (`solo_trimix_air_2026-10-31.txt`) is this stale burst on
open, not an OK press.** It has the same cut-off line followed by a clock jump.

In live measurement all fields can stay byte-identical for about 4 s, so repeated values are not a
sign of a hold. The silence is.

### The rule (in the bridge's `hold_detector`)

- **A hold:** the SOLO is still attached and no line has come for **2.0 s**, after lines had been
  flowing. Below that threshold:
  - a quick double OK (≤ 1.3 s) makes no record;
  - switching off (detach within 0.6 s) is gone from USB before the 2 s are up.
- **The held reading:** the last complete line before the silence. That is what the SOLO's display
  freezes on.
- **Arming:** the first hold after the SOLO attaches needs ≥ 5 s of flowing lines. This also skips
  the stale burst. Later holds need ≥ 3 s of flow since the last resume, so a stray
  resume-and-suspend doesn't make a second record within seconds.
- **One record per suspend.** A hold is edge-triggered. "OK to resume" never makes a record; it
  re-arms the detector.
- **A USB detach before the 2 s are up cancels the detection.** Unplugging or switching off while
  measuring is never a hold. Switching off while suspended comes after the hold, which is already
  recorded, as it should be.
- **Thresholds are named constants,** tested against the committed captures on the host. The two
  captures go into `test/fixtures/analyzer/solo_ok_presses_2026-11-03_{a,b}.txt` and the tool into
  `tool/solo_capture.py`.
  - Neither capture has key marks: no Enter presses reached the tool.
  - Capture *a* has one long suspend and a slow OK sequence. Capture *b* has MODE, double presses
    and a switch-off.
  - A marked capture of OK, OK, OK at different speeds is a good addition when the firmware's tests
    are written.

## 2. The bridge

### Hardware (ordered 2026-11-01)

- **Board: Espressif ESP32-S3-USB-OTG.**
  - ESP32-S3-MINI-1 with 8 MB flash.
  - Female USB-A host port for the SOLO; a USB-A male device plug for flashing and charging.
  - 5 V boost and MIC2005A 500 mA limiter.
  - 1.3" 240×240 ST7789 LCD, green and yellow LEDs, buttons.
  - Battery and USB-host voltage on ADC pins.
- **Power:** 18650 cells soldered to the battery pads. Use protected cells, since the board has no
  documented low-voltage cut-off. Cable: A-male to C-male to the SOLO.
- **Pins (third-party sources; check them against Espressif's hardware reference before use):**

  | Pin | Function |
  |---|---|
  | GPIO18 | `USB_SEL` (high = host port) |
  | GPIO13 | `BOOST_EN` |
  | GPIO17 | `IDEV_LIMIT_EN` |
  | GPIO15 | green LED |
  | GPIO16 | yellow LED |
  | GPIO9 | LCD backlight |
  | GPIO2 | battery ADC |
  | GPIO1 | host VBUS ADC |

### Host 5 V

- Off by default. A persisted setting (`CFG vbus=off|on`) turns it on, current-limited.
- The bench in step 1 decides the default:
  - Power meter between bridge and SOLO.
  - Does the SOLO enumerate with VBUS off?
  - What does it draw with VBUS on?
- If the SOLO only enumerates with VBUS, it will also charge from it, which Egbert doesn't want.
  That goes back to him with the meter numbers. It is not decided here.

### What the firmware does

- **USB host:** ESP-IDF `usb_host_cdc_acm`.
  - Accept VID 0xA600 / PID 0xE212 only.
  - Set 115200 8N1 and raise DTR.
  - Split lines on `\r?\n`, and timestamp each line with uptime in milliseconds.
  - Keep the last 30 s of lines in a RAM ring buffer.
- **Hold detection:** the rule in §1, in `hold_detector`.
- **Record store:** a queue in a LittleFS partition, holding at most 50 records.
  - **When the queue is full, the bridge stops making records and its screen says so. It never
    overwrites an unconfirmed record.**
  - A record is deleted only on `ACK`.
- **Record ids:** `<epoch>-<counter>`.
  - `epoch` is 8 random hex digits made at first boot and persisted. It is new after a flash
    erase, so a reset counter can't collide with old records.
  - `counter` is a persisted u32.
  - The bridge id is the 12-hex-digit factory MAC (eFuse), not the BLE address the phone sees. iOS
    shows a per-phone UUID instead.
- **Clock:** the bridge has no clock battery. It counts boots (persisted) and uptime. After a `TIME`
  message it also knows wall time until it next powers off.
- **BLE:** NimBLE, Nordic UART Service.
  - One central at a time. Advertises as `Anchorline Bridge XXXX` (the last 4 hex digits of the
    MAC) with the NUS UUID.
  - MTU up to 247. No bonding in v1; see "Risks".
- **Screen and LEDs.** The quick status display (decision 12), with big text readable at arm's
  length.
  - **Status line:** SOLO ✓/✗, phone ✓/✗, battery, VBUS on.
  - **Pending:** "3 waiting for phone".
  - **Main area: one state at a time, by priority.** States the bridge knows itself come first:

    | Situation | Screen |
    |---|---|
    | No phone has connected since power-on | `WAITING FOR PHONE` |
    | A phone was connected and the link dropped | `CONNECTION LOST` |
    | Connected and `LIVE ON`, but no `STATE` for 10 s | `PHONE NOT RESPONDING` |
    | No SOLO attached | `NO SOLO` |
    | SOLO attached but no lines for 4 s, and never a line since attach | `SOLO: TURN ON SEND DATA TO USB` |
    | A hold was detected and its record is waiting for its `FB` | `HELD — SAVING…` |
    | Queue full | `FULL — CONNECT PHONE` |
    | Battery low, or at cut-off | battery warning, or `BATTERY EMPTY` |

    Otherwise the bridge shows the **last result** (from `FB`) for 10 s after it arrives, then the
    **live state** (from `STATE`, §3):
    - last results: `PRINTED EAN32`, `SAVED — SIGN OFF LATER`, `CHECK PHONE: MISMATCH`,
      `AIR — NOT LOGGED`, `NO READING`;
    - live states: `SETTLING… TX21/35`, `STABLE TX21/35`, `SENSOR ERROR`, `AIR`.

    The bridge never works out a state such as stable from the lines itself; the app sends it.
  - **LEDs:** the green LED blinks when the app has confirmed a record; the yellow LED stays on
    while records are waiting or something needs attention.
- **Buttons:** one shows a short info screen (bridge id, firmware, battery, VBUS mode). There is
  no menu system, and OK on the SOLO is the only trigger.
- **Where it lives:** `firmware/solo_bridge/` in this repo.
  - An ESP-IDF project; the IDF version is pinned in its README.
  - Components come through `idf_component.yml`: `usb_host_cdc_acm`, LittleFS, and the
    `esp32_s3_usb_otg` board support package if it fits.
  - **Licence: Apache-2.0** (Egbert, 2026-11-03), with its own `LICENSE` in `firmware/solo_bridge/`.
    ESP-IDF and NimBLE are Apache-2.0, which can't be combined with the app's GPLv2 in a firmware
    file someone else receives. The firmware is a separate program that talks to the app only over
    BLE, so the app keeps GPLv2.
  - One repo keeps the protocol, the app and the firmware changing in the same PRs. Firmware CI
    (an ESP-IDF build in GitHub Actions) is a later nice-to-have. Flashing is `idf.py flash` over the
    device plug.
- **Modules:**

  | Module | Does |
  |---|---|
  | `usb_solo` | USB host, attach and detach, line splitting |
  | `hold_detector` | the OK rule |
  | `record_store` | the flash queue |
  | `ble_link` | NUS and the protocol |
  | `ui` | screen, LEDs, buttons |
  | `power` | VBUS, boost, limiter, battery |

  `hold_detector` and the line splitter build for the host too, so they can be tested against the
  fixtures.

## 3. Bridge protocol v1

- Plain text, one message per line, `\n`-terminated, over the NUS TX (notify) and RX (write)
  characteristics.
- A message may span several notifications. The app reassembles lines with the existing
  `serial_line_buffer.dart`.
- Text keeps it debuggable with nRF Connect. The builder may add messages, but must bump `proto=`
  for anything incompatible.

**Bridge → app**

| Message | When |
|---|---|
| `HELLO proto=1 fw=<semver> bridge=<mac12> epoch=<hex8> boot=<n> up=<ms> solo=<0\|1> rec=<on\|off> vbus=<off\|on> batt=<mV> pending=<n>` | On every connection |
| `ST solo=<0\|1> data=<0\|1> pending=<n> batt=<mV> up=<ms>` | Every 5 s and on change. `data=1` means lines are flowing |
| `L <raw SOLO line>` | Each SOLO line, only while `LIVE ON` |
| `REC <rid> boot=<n> up=<ms> wall=<epoch-ms\|0> live=<0\|1>` | A record starts |
| `W <offset-ms> <raw line>` | The record's window, oldest first; offsets are ≤ 0, relative to the hold |
| `H <raw line>` | The held reading |
| `END <rid>` | The record is complete |

- `live=1` means a phone was connected and subscribed at the moment of the hold.
- Pending records are sent oldest first, **one at a time**. The next one goes only after the `ACK`
  for this one. Unconfirmed records are sent again on every connection.

**App → bridge**

| Message | Meaning |
|---|---|
| `TIME <epoch-ms>` | Sent first on every connection; the bridge keeps wall time until it powers off |
| `LIVE ON` / `LIVE OFF` | Forward `L` lines or not. On while the analyzer screen is visible **or a session runs**, so the bridge screen can show the live state (decision 12). Off only for a short collection connect. In a background session this wakes an iPhone about 5 times a second; the session is bounded, so this is accepted |
| `STATE <code> [<mix>]` | The live state for the bridge screen: `settling`, `stable`, `sensor_error` or `air`, plus the live mix name (`gasMixName`). Sent on every change and at least every 3 s while `LIVE ON`; this doubles as the heartbeat |
| `ACK <rid>` | Sent **after** the local database write has committed (or after deciding not to save, see §5). The bridge deletes the record |
| `FB <rid> <code> <text>` | The result, for the screen. `code` is `printed`, `saved`, `check`, `skipped` or `error`. `text` is ≤ 24 ASCII characters, e.g. `EAN32`, `MISMATCH`, `NO NAME SET`, `SIGN OFF LATER`, `PRINT FAILED`, `AIR - NOT LOGGED` |
| `CFG rec=<on\|off> vbus=<off\|on>` | Persisted on the bridge. `rec` mirrors the app's "Log on OK" option and is sent on every connection; with `rec=off`, OK makes no records at all. The factory default is `off` |

## 4. The app

### New code

- **`lib/analyzer/bridge/bridge_protocol.dart`**: pure Dart. Parses and formats every message
  above, and assembles a `REC…END` block into a `BridgeRecord`. Unit-tested.
- **`lib/analyzer/bridge/record_to_analysis.dart`**: pure Dart. All of §5 in one function: given a
  `BridgeRecord`, the setup in force and "now", it returns what to save and whether to print. It is
  the core of the feature and gets the most tests.
- **`lib/analyzer/transport/ble_bridge_transport.dart`**: an `AnalyzerTransport` over the bridge
  (`L` lines). This is the #113 deliverable. The analyzer screen works through the bridge on
  every platform, iPhone included, with no background work at all.
- **`lib/analyzer/bridge/bridge_link.dart`**: the flutter_blue_plus side.
  - Connect by stored remote id with `autoConnect: true, mtu: null`. On Android, `requestMtu(247)`
    after connecting, as the Phomemo and Shearwater code does.
  - Subscribe, reassemble lines, write messages.
  - Pairing: a scan filtered on the NUS UUID, stored like the label printer's id (Settings →
    Analyzer → Bridge).
- **`lib/analyzer/bridge/log_on_ok_service.dart`**: the session.
  - Owned by the app shell, not by the analyzer screen, so it outlives the screen.
  - Holds the setup and handles records through `record_to_analysis`.
  - Writes through `GasAnalysesDao`, prints through `LabelPrintService.printAnalysis`, sends `ACK`
    and `FB`.
  - Drives the platform background pieces (§6, §7).
- **Android:** `AnalyzerBridgeService.kt`, a foreground service, plus a small method channel
  (§7). No plugin.

### The "Log on OK" option

- **A switch on the analyzer screen,** shown once a bridge is paired. It is remembered on the phone
  (SharedPreferences) and sent to the bridge as `CFG rec` on every connection, so the bridge knows
  it even when the app is closed.
- **Off (the default):** OK on the SOLO only pauses its display, as today. The bridge makes no
  records, and the diver taps Save.
- **On:** every OK press makes a record, including while the app is closed or killed. The record
  waits on the bridge. Turning the option on asks for the Android notification permission.

### The save card becomes the setup

With "Log on OK" on and the bridge connected, the existing save card turns into the setup.
- **Same fields and the same print copies,** but the Save buttons are replaced by a hint: "Press OK
  on the SOLO to save".
  - **Exception:** while the live reading is room air (§5), the Save buttons stay, because OK
    doesn't log air (decision 11).
- **One setup, one save path:** an OK press plus a Save tap can't make two entries. OK never saves
  air, and Save is only offered for air.
- **After each OK, the card shows the result** ("Saved EAN32", "Printed EAN32", "Needs sign-off:
  not stable") with **Edit**, which opens the edit sheet, and **Delete**, which soft-deletes after
  a confirm (decision 13).

| Kind | Fields | Behaviour |
|---|---|---|
| Stays until changed | **Analysed by** | Prefilled with the remembered name, kept between sessions; device-local like the other analyzer settings, which don't sync yet (a known open item). The first time it's empty and asks for a name or initials, since the app holds no user name today, only the account email |
| Stays until changed | **Desired mix picked from the chips** | Four EAN32 cylinders from a filling station take one setup. A deliberate exception to the clear-after-save rule; the match check in §5 is the safety net |
| Stays until changed | **Gas role** | Decides the label layout, so it belongs to the setup |
| Stays until changed | **For** | Who the gas is for: free text, in the log and the CSV, not on the label |
| Stays until changed | **Print label on OK** | On by default when a printer is configured; off on the boat |
| Next cylinder only | **A Blend-page target, the cylinder, fill pressure, notes** | Used up by the first OK press that saves **complete** (`needs_signoff = 0`, printed if printing was wanted). A press that needs sign-off (a mismatch, a failed print, no name) leaves them in place, so pressing OK again on the same cylinder still has them |

- **The Blend-page target** (the 24 h `recentTarget`) is **preselected**.
  - Today the card offers it as the first chip but selects nothing. With the phone in a pocket,
    preselecting is the point.
  - Once used up, it is marked as used in `BlendNotifier`'s stored state, next to the target. So
    reopening the screen or a new session never preselects it again for a second cylinder: one
    blend is one cylinder.
  - Any new edit on the Blend page is a new blend, with a new target.
- **No desired mix is allowed:** OK then saves and the entry waits for sign-off.
- **A status line:** bridge connected or not, records waiting, the last result.

### Records and sessions

- **Records are handled whenever the app is connected to the bridge,** not only in a session. That
  covers the analyzer screen, a session and a short collection connect. One record handler, in
  `LogOnOkService`, serves all three. With the option off, the bridge sends none.
- **A session keeps the connection when the app leaves the screen.** It starts by itself when the
  analyzer screen connects to the bridge with the option on. The screen is visible at that moment,
  which Android 12+ requires for starting a foreground service. A small "Log on OK" chip in the app
  shell shows it's running, has Stop, and links back to the analyzer screen.
- **A session ends** on Stop, when the option is switched off, when the bridge has been out of reach
  for **60 minutes**, or when the app is killed (iOS force-quit, Android swipe-away, or the OS).
  - The 60 minutes allow for filling the next cylinder with the bridge switched off. It's a named
    constant.
  - On iOS, Dart timers don't run while the app is suspended. The check runs on the next wake-up:
    a reconnect, or an `ST` message. A reconnect after the timeout ends the session then: its
    records count as late, waiting records are collected, and the app drops the pending connection.
- **Collecting waiting records outside a session:** when the app starts or comes to the front, with
  a bridge paired and the option on, it tries a short connect by stored id (≤ 15 s, no scan). It
  collects what's waiting and disconnects. No pending connection is left behind once a session ends,
  so nothing runs in the background when the diver isn't analysing.
- A session doesn't resume by itself after an app restart (v1). The collect-on-start covers what was
  waiting.

### 4c. Log on OK over USB (analyzer screen open)

Over a cable the app sees the SOLO's stream itself, so the OK rule of §1 runs in Dart.

- **`lib/analyzer/hold_detector.dart`** is the Dart twin of the firmware's `hold_detector`, with
  the same named thresholds: 2.0 s of silence while attached, 5 s of flow before the first hold,
  3 s before later holds, and a 30 s window.
  - Flow is counted from the first line after attach, or from the last resume. A resume is the
    first line after any silence of 2 s or more, whether or not that silence was recorded as a
    hold.
  - Dips under 2 s don't reset it.
  - The record's window holds only the lines since the last resume, capped at 30 s, so lines from
    the previous cylinder never count towards stability.
  - The firmware's `hold_detector` follows the same two rules.
  - The transport leaving `connected` cancels a pending hold and resets arming.
  - It is tested against the same captures, which give two holds in capture *a* and one in
    capture *b*.
- **A hold becomes a record:** `BridgeRecord` with boot 0, `live=1`, a unique rid, and the window
  and held line. It goes through `recordToAnalysis` with bridge id `usb` and
  `capture_source = 'usb_ok'`. The pocket print rules, sign-off, room-air skip and derived row id
  all apply unchanged. There is no queue and no `ACK`: the app is the only party.
- **`UsbOkLogger`** watches the analyzer session's transport while the analyzer screen is open, a
  non-demo transport is connected, and the "Log on OK" switch is on. An OK press with the screen
  closed only pauses the SOLO, and nothing is saved.
- **Printing:**
  - The entry is saved flagged while its label prints (§5 order of operations).
  - The label is printed from an in-memory copy marked complete, because `LabelPrintService`
    refuses flagged entries.
  - The flag is cleared in the database after the print succeeds.
- **Feedback:** the result shows on the save card (there is no bridge screen), with Edit and
  Delete.
- **The setup card** behaves as in §4, including the sticky and per-cylinder fields. One step is
  deferred to plan 3: preselecting the Blend target and marking it used.

## 5. Turning a record into an analysis

`record_to_analysis` decides everything below. It is pure and tested.

### The reading

- Parse `H` with `parseSoloLine`.
- **Usable** means exactly the save card's rule: O2 finite and > 0, He finite (negative He counts as
  0).
- **Not usable** (`***.*`, no O2): save nothing. Send `ACK`, then `FB error NO READING`. There is
  nothing to keep, and the diver sees it at once on the bridge.
- **Room air** (decision 11): O2 from 20.5 to 21.5 % inclusive and He below 1.0 %. That is
  `kAirO2MinPercent`, `kAirO2MaxPercent` and `kHeliumNoiseFloorPercent` from `gas_naming.dart`, and a
  negative He counts as 0.
  - Save nothing, live or late. Send `ACK`, then `FB skipped AIR — NOT LOGGED`.
  - Nothing per-cylinder is used up.
  - **Calibration caveat:** all three captures read room air at O2 19.7–19.8 % (31 Oct and
    3 Nov). That is outside the band, so on that SOLO an OK on air would save "Hypoxic 20". The
    rule assumes a SOLO calibrated on air, and a calibration hint is not part of this work.
- **Stable:** feed every `W` line, then `H`, to a fresh `StabilityDetector`, using the offsets as
  `elapsed`. `stable` is its state at `H`. This is exactly the screen's rule, not a firmware copy.

### When the OK was pressed (`analysed_at`)

1. If the record's `boot` is the bridge's current boot: phone now − (bridge `up` now − record `up`).
2. Otherwise, the record's `wall` if it isn't 0.
3. Otherwise, the SOLO's own timestamp in `H`. Its clock can be far off: Egbert's SOLO was about 41
   minutes behind the Mac on 2026-11-03. It's still better than nothing.
4. Otherwise, the time of delivery, with a note in `notes` ("time unknown, delivered …").

### Live or late

- **Live:** `live=1`, the record arrives within 30 s of the hold, and the app is on the analyzer
  screen or in a session. The setup applies.
- **Late:** anything else. The setup in force *now* may not be the one that was set when OK was
  pressed, so a late record gets no setup at all:
  - no desired mix, no "for", no role (bailout default);
  - `analysed_by` empty, needs sign-off, never printed.
  - **A record never gets a setup chosen after its OK press.**

### Print or not (pocket rules)

The label prints only when **all** of these hold:

1. "Print label on OK" is on, and a printer is configured.
2. "Analysed by" is set (decision 18; the label always carries the analyser's name).
3. The record is live.
4. The reading is usable. **Stability is not required:** the OK press is the confirmation
   (decision 18).
5. With a desired mix set, `gradeMix` against it is `match` or `orange`. With no desired mix,
   there is no check, and the label shows the analysed mix.

**Stricter than the screen, on purpose:** in the pocket nobody sees the match colour, so with a
desired mix set, red and hard mean no print. A hard mismatch prints the analysed name on screen
after a dialog. In the pocket it doesn't print at all.

### What is saved

- A normal `NewGasAnalysis`:
  - the measured O2, He, temperature and pressure from `H`;
  - `stable`;
  - `mod_ppo2s` from the setting;
  - the setup's desired mix, role, analysed by and "for" (live records only).
- New fields (§8):
  - `capture_source = 'bridge_ok'`;
  - `bridge_record_id = '<bridge>/<rid>'`;
  - `needs_signoff`.
- **The row id is derived, not random:** a UUID v5 of `<bridge>/<rid>`, using SHA-1 from the
  `crypto` package, which is already a dependency. The same record always maps to the same row (see
  §10).

### `needs_signoff`

- **`1`** when any of these is true:
  - no "analysed by";
  - the record is late;
  - a desired mix is set and the match is red or hard;
  - a print was wanted (rule 1 held) but didn't happen.
- **`0`** otherwise. For example, on the boat with printing off but mix and name set, a stable,
  matching re-check needs nothing more.

### Order of operations

1. Save the row with `needs_signoff` as decided, but as `1` if a print is about to be tried.
2. `ACK` the record. It's in the local database now, and PowerSync uploads it whenever there is
   network.
3. If printing: print. On success, clear `needs_signoff` (an `update`) and send `FB printed <mix>`.
   On failure, send `FB check PRINT FAILED`; the entry stays flagged.
4. Not printing: `FB saved <mix>`, or `FB check <reason>`.

A crash between steps leaves the entry flagged, never unflagged without a label.

### Per-cylinder values

- The Blend-page target, cylinder, fill pressure and notes are used up only by a live record that
  saves complete (`needs_signoff = 0`).
- A late record never uses anything up, and never gets anything.
- `record_to_analysis` returns, next to the analysis and the print decision, whether the
  per-cylinder values were used, so the session can clear them.

## 6. Background: iOS

- **`Info.plist`: add `UIBackgroundModes` → `bluetooth-central`.** There are no background modes
  today. Update `NSBluetoothAlwaysUsageDescription` to mention the gas analyzer bridge.
- With that mode, iOS keeps the connection, delivers notifications and runs the app's code while it
  is in the background or the phone is locked. The pending connection from `autoConnect: true`
  never times out: switching the bridge off and on, or walking out of range and back, reconnects
  without the app in front.
- In a session, `LIVE` stays on in the background, so the app can keep sending `STATE` for the
  bridge screen (§3). That means about 5 wake-ups a second, but only during a session. A short
  collection connect, outside a session, uses `LIVE OFF`: only `ST` and records arrive.
- **Printing in the background:** connecting to the M110 by its stored id needs no scan, so the BLE
  side works in the background. **The label is drawn with `Picture.toImage`, and iOS restricts GPU
  work in the background.** This must be tested on an iPhone in step 4. If it fails, the print is
  skipped, the entry is flagged, and the bridge shows `OPEN PHONE TO PRINT`. A fix (a raster-only
  render path, for example) becomes its own issue. The rest of the feature doesn't depend on it.
- **When iOS kills the app in the background** (memory) or the user force-quits it, the session ends
  and records wait on the bridge.
- **State restoration is not used in v1** (decision 14: sessions first). The bridge queue covers
  what a killed app misses.
  - flutter_blue_plus 1.36.8 supports `restoreState`, but the code confirms that a background
    relaunch wouldn't start Dart today:
    - `AppDelegate` is a `FlutterImplicitEngineDelegate`, with a `FlutterSceneDelegate` and the
      `Main` storyboard;
    - the implicit engine is created only when a scene connects;
    - `flutter_blue_plus_darwin` creates its `CBCentralManager` only on the first call from Dart.
  - Making it work is part of the always-armed step in "Later".
- **No local notification per save in v1.** The bridge screen is the feedback, and it's where the
  diver is looking. A notification would need a new permission and native code.

## 7. Background: Android

- **A foreground service, `AnalyzerBridgeService`** (Kotlin, in-app, no plugin), with
  `android:foregroundServiceType="connectedDevice"`.
  - It only keeps the process alive and shows the notification. The BLE link stays in Dart
    (flutter_blue_plus) in the normal Flutter engine.
  - A method channel `nl.despaankamer.ccrlogger/log_on_ok` has `start(title, text)`,
    `update(text)` and `stop()`.
- **Manifest:**
  - `FOREGROUND_SERVICE`;
  - `FOREGROUND_SERVICE_CONNECTED_DEVICE` (API 34+);
  - `POST_NOTIFICATIONS` (API 33+);
  - the `<service>` entry.
  - `BLUETOOTH_CONNECT` is already declared and requested. It must be granted before
    `startForeground` with this type on API 34+, or Android throws.
- **Permissions:** `POST_NOTIFICATIONS` is asked for when "Log on OK" is turned on. If it's
  denied, the service still runs but the notification is hidden; the analyzer screen says so.
- **Notification:** "Logging analyses from the bridge · 3 saved · last EAN32 14:02", with a Stop
  action. It is updated after each record.
- **Swiping the app away** destroys the Flutter engine with the activity. The service stops itself
  in `onTaskRemoved`, and records wait on the bridge. Keeping a cached engine alive to survive the
  swipe is possible later, but not v1: a swipe usually means "stop".
- **Doze:** a foreground service process keeps its BLE link. No battery-optimisation exemption is
  needed. Aggressive OEM task killers are out of scope; the bridge queue covers them.
- `autoConnect: true` for reconnects, as on iOS.

## 8. Data model

**Migration `0021`** (or the next free number at build time; the Subsurface sync spec also expects
`0021`), named `..._gas_analysis_bridge_fields.sql`, adds four columns to `gas_analyses`:

| Column | Type | Meaning |
|---|---|---|
| `needs_signoff` | `integer not null default 0` | 1 = waiting for sign-off in the log (§5). Existing rows are 0 |
| `capture_source` | `text` | null = saved on screen (all rows so far); `'bridge_ok'` = saved from an OK press through the bridge; `'usb_ok'` = saved from an OK press over a USB cable (§4c) |
| `bridge_record_id` | `text` | `<bridge>/<rid>`, for tracing; null for screen saves |
| `analysed_for` | `text` | Who the gas is for, free text. A later sharing project can add a user reference next to it |

- No new table, so no new grants and no publication change. The sync rule
  `SELECT * FROM gas_analyses WHERE owner_id = bucket.user_id` already covers new columns.
- Add the four columns to `gas_analyses` in `lib/sync/cloud/powersync_schema.dart`.
- **Deploy the migration before shipping a build that writes these columns.** The upload connector
  sends the whole row, as with 0020.
- **Model and DAO:**
  - `NewGasAnalysis` and `GasAnalysis` get the four fields.
  - `GasAnalysesDao` gets `addFromBridge(id, analysis)`. In a write transaction it inserts only if
    **no row with that id exists, soft-deleted rows included**; otherwise it does nothing. A record
    the diver already deleted is never brought back.
  - `setNeedsSignoff(id, bool)` bumps `version` and `updated_at` like `update()`.
- **CSV export:** add `analysed_for` and `needs_signoff`.

## 9. The log

- **Badge:** entries with `needs_signoff = 1` get a "Needs sign-off" badge (warning colour, next to
  the existing stable/unstable icon).
- **Count:** the log shows "3 analyses need sign-off" at the top, with a filter to show only those.
  The analyzer screen's session line shows the same count.
- **Edit sheet** (`analysis_edit_sheet.dart`): the editable fields grow. **The measured values never
  change.**
  - **Cylinder:** pick from Equipment. It's stated by the diver, not measured, so it becomes
    editable on all entries.
  - **Fill pressure:** also stated, not measured.
  - **For:** the new "who the gas is for" field.
  - **Desired mix, gas role, analysed by and notes:** as today.
- **Picking a cylinder on an entry with no desired mix** prefills the desired mix and role from that
  cylinder's latest other analysis. This is the re-check-on-the-boat case: it compares against what
  the diver thought was in the cylinder.
- **On a flagged entry, the sheet's button reads "Sign off".**
  - It needs **"analysed by"**, the same thing that lets OK print from the pocket (decision 18), so
    an entry is complete the same way whichever path it takes. A desired mix is optional.
  - Saving clears `needs_signoff`.
  - With a printer configured there is also "Sign off and print". It goes through the existing
    print path, hard-mismatch dialog included.
- **No label while flagged:** a flagged entry has no print action in the log. `LabelPrintService`
  also refuses it, so no code path can print one (decision 10).
- **Delete** (decision 13): a Delete button in the sheet, with a confirm, next to today's swipe.
  It is a soft delete, so a re-sent record never brings it back (§8).
- `GasAnalysisEdit` grows to match: cylinder id, fill pressure, analysed for, and a sign-off flag.

## 10. Duplicates and failure cases

| Case | What happens |
|---|---|
| "Log on OK" off | OK only pauses the SOLO's display. The bridge makes no records, and saving is the Save button, as today |
| Double OK (suspend + resume) | At most one record, made on the suspend. A quick double press (≤ 1.3 s measured) is under the 2 s threshold and makes none; the bridge shows nothing new |
| OK pressed before the reading settled | The OK press is the confirmation (decision 18): saved complete with `stable = 0`, and printed when the other rules allow. The log shows the not-stable icon |
| The bridge comes back after the 60-minute session timeout | The app is woken by the pending connection (iOS) or still running (Android). The session counts as ended, so the record is late: needs sign-off, no label. The app then drops the connection |
| OK, OK, OK on the same gas | Two records, two entries, and two labels if printing. **Never auto-dropped:** a missing analysis is worse than a duplicate, and two cylinders of the same mix are common. The diver deletes the extra one in the log |
| Link drops between hold and `ACK` | The record stays on the bridge and is sent again on reconnect. The derived row id plus `addFromBridge` make the re-send a no-op, and it is confirmed again |
| `ACK` lost after the save | Same as above: the re-send maps to the existing row, nothing is added, and it is confirmed |
| App killed, phone away, bridge out of range | Records wait in flash, with "n waiting for phone" on screen. They are delivered on the next connection as **late** records: needs sign-off, no label |
| Bridge switched off with records waiting | They are kept in flash. Time comes from §5 (uptime is lost, so `wall` or the SOLO clock is used) |
| Bridge queue full (50) | No new records. The screen says "FULL — connect phone". Nothing is overwritten |
| No network | Doesn't matter: the save is local (PowerSync is offline-first) and the `ACK` follows the local commit. The upload happens later |
| Signed out | Same as a manual save today (owner from the session at insert time). No new behaviour. **Known bug, being fixed separately:** `gas_analyses` was missing from `OwnerIdBackfiller._syncedTables`, so rows saved while signed out disappeared from the log after sign-in. The fix is its own issue and PR, from the session "Fix: signed-out gas analyses vanish after sign-in" |
| SOLO sensor error at the hold | Nothing saved, `ACK`, `FB error NO READING` |
| OK pressed on room air | Nothing saved, `ACK`, `FB skipped AIR — NOT LOGGED`. Save air cylinders by hand on the analyzer screen |
| Wrong mix in the setup, or the wrong cylinder | Red or hard: saved, needs sign-off, no label, `FB check MISMATCH`. The cylinder visibly has no label |
| Printer off, out of paper, cover open | Saved, needs sign-off, `FB check PRINT FAILED`. Reprint from the log |
| Two phones | One central at a time. If phone A saved but its `ACK` was lost and phone B connects first, B inserts the same id. Its upload (upsert) could overwrite A's later sign-off. **Accepted:** rare, needs two phones and a lost `ACK`, and loses no measurement |
| Someone else's bridge nearby | The app connects only to the stored bridge id |

## 11. Store review

- **App Store:** guideline 2.5.4 allows background modes for their intended purpose, and keeping a
  BLE accessory connected to collect its data is that purpose.
  - The reviewer has no bridge, so App Review notes need a short description and a demo video:
    phone locked, OK on the SOLO, entry and label appear.
  - The bridge is a plain BLE device, so no MFi is needed.
- **Google Play:** apps targeting API 34+ must declare each foreground-service type in Play Console
  with a reason and a video. Type: `connectedDevice`. Reason: "keeps the connection to the user's
  gas analyzer bridge while logging analyses".

## 12. Build order

Each step is its own issue and PR, and each one is useful on its own.

0. **Capture: done 2026-11-03.** The stream stops on OK (§1). The two capture logs and
   `tool/solo_capture.py` are committed with this spec.
1. **Bridge v0 + #113 transport.**
   - Firmware: USB host, `L` lines, `HELLO`, `ST`, `LIVE`, `CFG vbus`.
   - App: `ble_bridge_transport.dart`, bridge pairing in Settings, and the analyzer screen over the
     bridge on every platform.
   - **Bench the 5 V question with the meter**; Egbert decides.
2. **Bridge v1:** hold detector with host tests, record store, `REC`/`ACK`/`TIME`/`FB`, screen and
   LEDs.
3. **App, foreground first:**
   - `bridge_protocol.dart` and `record_to_analysis.dart` with tests;
   - migration `0021`, schema, DAO and model;
   - log badge, count, filter and edit sheet changes;
   - the save card's "Log on OK" setup, with the analyzer screen open.
   OK logging then works with the phone in hand before any background work.
4. **Background:**
   - iOS `bluetooth-central`;
   - Android foreground service;
   - session lifetime, app-shell chip, print on OK;
   - **test background label rendering on an iPhone.**
   Bench checklist:
   - a 30 min session with the iPhone locked in a pocket;
   - an Android phone with the screen off;
   - kill the app mid-session and confirm the records drain later;
   - power-cycle the bridge with records waiting;
   - airplane mode, then the rows sync later;
   - double OK, and out of range for 2 minutes.
5. **Store submissions** with the review notes from §11.

## Later

- **Line up a batch:** a short "next up" list in the "Log on OK" setup. Each entry has a mix, who it's
  for, and diluent or bailout. Each live OK press uses the top entry. An OK that doesn't print (red,
  hard or unstable) leaves the entry at the top, so analysing out of order never shifts the list.
- **Share an analysis with another Anchorline user** (it appears in their log). This is a separate
  design: finding the user, write access to someone else's log, sync delivery, privacy. CLAUDE.md
  lists social and sharing features as out of scope, so this needs Egbert's explicit decision to
  widen that line. `analysed_for` is the hook.
- **Always armed: the first later step** (decision 14). The goal is to switch the bridge on and
  have the phone connect, with no need to open Anchorline, even after iOS has closed the app
  overnight. The bridge-logging brainstorm worked this out:
  - **iOS.**
    1. Create and run one `FlutterEngine` in `application(_:didFinishLaunchingWithOptions:)`,
       register the plugins on it, and have the scene's `FlutterViewController` attach to that
       engine.
    2. Call `FlutterBluePlus.setOptions(restoreState: true)` at the top of `main()`, then touch the
       adapter, so the central manager exists while iOS is still within the launch window.
    3. Keep a standing `connect(autoConnect: true, mtu: null)` to the stored bridge.

    TN3115 relaunch rules apply: it works after the system kills the app and after a reboot, but
    not after a user force-quit (AccessorySetupKit on iOS 26 is the exception). On restoration,
    disconnect restored peripherals that aren't the bridge, such as a Petrel or the printer.
  - **Android 12+.**
    1. Pair through `CompanionDeviceManager.associate` with a filter on the bridge's service UUID.
    2. Observe presence: `startObservingDevicePresence` on API 31–35, `ObservingDevicePresenceRequest`
       on API 36+.
    3. Start the `connectedDevice` foreground service from the `CompanionDeviceService` when the
       bridge appears. Companion-device apps are allowed to do this from the background.
    4. Cache the Flutter engine, so that swiping the app away doesn't stop logging.
  - Both change app-wide startup and lifecycle (the Shearwater import and the printer share them),
    which is why they are not in v1.
- OK logging over a direct USB cable, by porting the hold rule to Dart with the same fixtures.
- Firmware CI, and OTA updates.

## Bench results, step 1 (2026-11-09)

Board: ESP32-S3-USB-OTG V1.1, powered from its DEBUG port (so the host port can't get 5 V from the
board). SOLO on the USB-A host port, on its own battery. App: macOS debug build of
`feat/173-solo-bridge-v0`.

| Check | Result |
|---|---|
| SOLO enumerates with the bridge's 5 V **off** | **Yes.** `vid=a600 pid=e212 class=02`, attach in under 1 s, lines at 5 Hz. |
| Live readings over Bluetooth on the Mac | **Yes**, after one app fix (below). Readings, the stable pill and `Bridge · SOLO connected · USB powered`. |
| Live readings on the iPhone | Not done yet. |
| SOLO off and on, out of range and back | Not done yet. |
| Meter readings with the bridge's 5 V on | Not done yet: needs the board on the DEV plug. |

- **`host_vbus` reads 5.09 V with the bridge's 5 V off** and the SOLO plugged in. Nothing on the
  board drives that rail in this state, so the SOLO seems to put its own 5 V on VBUS. Check with the
  meter between the port and the cable before trusting this.
- **App bug found and fixed:** the bridge sends `HELLO` as soon as notifications are on, before the
  link layer reports `connected`. The transport then skipped `TIME`/`CFG`/`LIVE ON`, so no live lines
  came. A test now pins that order.
- **macOS needs WCH's CH34x driver** for the DEBUG port (a CH342, `1a86:7522`); macOS has none built
  in.
- **The 5 V switch:** the SOLO does not need host 5 V, so the default stays **off**. Whether "on"
  stays available at all waits for the meter readings.

## Risks and things to verify on hardware

- **A future SOLO firmware could change what OK does on USB.** The captures, as fixtures, make
  that show up as failing host tests the next time the firmware is checked against a new SOLO.
- **The SOLO may need host 5 V to enumerate**, which means it charges from the bridge. That goes
  back to Egbert with the meter readings.
- **Background label rendering on iOS** (`Picture.toImage`). This is unverified, and printing from
  the pocket on iPhone depends on it.
- **`StabilityDetector` thresholds are still untuned.** Since decision 18 they no longer gate
  printing, only the recorded `stable` flag and the screen's pill. Tune them with real use; they
  are already named constants.
- **No BLE bonding:** anyone nearby with a BLE app could connect, read lines, or send `ACK` (that
  would drop a record before the app saves it). The risk is low at a fill station. Bonding, or a
  per-bridge secret written at pairing, is a later hardening.
- **Pin assignments come from third-party listings.** Check them against Espressif's hardware
  reference before writing the power code.
- Unprotected 18650 cells have no low-voltage cut-off on this board.

## Calls made in this design (not Egbert's decisions; for him to check)

1. **OK detection:** 2.0 s without a line while the SOLO stays attached means OK was pressed. The
   first hold needs 5 s of flow, later ones 3 s. These come from the two captures.
2. **No OK press is lost:** the bridge keeps each one in flash (at most 50) until the app confirms
   the save, and never overwrites one.
3. **Gas logic stays in Dart.** The bridge sends 30 s of raw SOLO lines with each OK, and the app
   runs its existing parser and stability check over them.
4. **The pocket print rules are stricter than the screen's:** unstable, red and hard don't print.
   The entry is saved, flagged "needs sign-off", and the bridge says why.
5. **A record the app didn't receive live** (app killed, out of range, after a session ended) gets
   no setup: no desired mix, no name, no label, needs sign-off.
6. **What stays and what's used up.** The picked desired mix, gas role, analysed by and "for" stay
   until changed. The Blend target, cylinder, fill pressure and notes are for one cylinder and are
   used up only by a complete save. The Blend target is preselected and marked as used afterwards.
7. **"Log on OK" is a remembered option, off by default.** With it on, OK on the SOLO replaces the
   Save button.
8. **Sessions** start by themselves when the analyzer screen connects to the bridge. They end on
   Stop, after 60 minutes without the bridge, or when the app is killed. The app also collects
   waiting records whenever it opens or comes to the front.
9. **Not in v1:** iOS state restoration, an Android engine that survives swipe-away, and an iOS
   notification per save. The bridge's screen is the feedback.
10. **Duplicates:** distinct OK presses are never dropped. A retried delivery maps to the same row
    through a derived id. A deleted entry never comes back.
11. **Edit sheet:** cylinder, fill pressure and "for" become editable on every entry. Picking a
    cylinder fills in the desired mix and role from that cylinder's last analysis.
12. **Migration `0021`** adds `needs_signoff`, `capture_source`, `bridge_record_id` and
    `analysed_for` to `gas_analyses`.
13. **Firmware** lives in `firmware/solo_bridge/` in this repo (ESP-IDF). The protocol is text over
    Nordic UART, with no BLE bonding in v1.
14. **Host 5 V is off by default.** The power-meter bench in step 1 decides, and charging the SOLO
    goes back to Egbert if it turns out to be needed.

Calls made in the merge:

15. **Signing off needs "analysed by" and a desired mix,** the same pair that lets OK print. The
    other brainstorm asked only for "analysed by".
16. **The Save button stays on the setup card while the live reading is room air,** since OK
    doesn't log air. It is hidden otherwise, so a cylinder can't be saved twice.
17. **`LIVE` stays on through a background session,** and the app sends `STATE` (live state plus
    heartbeat) so the bridge screen can show settling and stable. This costs extra iPhone
    wake-ups, but only during a session.
18. **The bridge's own states take priority on its screen:** no phone, connection lost, no SOLO,
    no data, held, full, battery. After them comes the last result for 10 s, then the live state.
19. **After an OK save,** the setup card shows the result with Edit and Delete, and the edit sheet
    gets a Delete button with a confirm.
