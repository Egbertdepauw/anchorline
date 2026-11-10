# Cylinder label printing — Design

Issue: #114. Related: #113 (ESP32 USB-to-BLE bridge), the analyzer spec `2026-10-27-gas-analyzer-solo-design.md`, the analysis log (#111).

## Why

Egbert runs his own fill station. He blends with the Blend tab, lets the cylinders cool, analyses them with a Divesoft SOLO, and then writes a cylinder label by hand: desired mix, analysed O2/He, MOD, date and initials. Anchorline already holds every number on that label once the analysis is saved, so the app should print it.

This is the first of three projects:

1. **Label printing (this doc).** Works today with the USB analyzer on macOS and Android.
2. **The bridge (#113).** ESP32-S3 firmware that passes SOLO readings to the phone over BLE, so iPhones can analyse.
3. **The box and DIY kit.** A small case holding the SOLO, the bridge, the printer and a power bank, with a build guide, so other divers can build one. A pre-built version may be offered later.

Label printing must not depend on 2 or 3. The phone talks to the printer directly. The box will never sit between the phone and the printer.

## Goals

- Print a 50×30 mm cylinder label from a saved analysis on a **Phomemo M110** over BLE, from iOS, Android and macOS.
- Two label types: **bailout/deco** (one big MOD) and **diluent** (three depths for a CCR diluent).
- Store the **desired mix** and the **gas role** with each analysis (synced), because both decide what the label says.
- Reprint any entry from the analysis log.
- Keep the printer code in the same split the rest of the app uses: pure-Dart encoding, a thin BLE transport, and UI on top.

## Non-goals (v1)

- Other printers (Niimbot, Brother P-touch, Zebra). Leave a printer interface so one can be added later, but build only Phomemo.
- Label sizes other than 50×30 mm.
- A minimum-depth line for hypoxic mixes. Egbert decided: MOD only.
- PDF labels, QR codes, logos.
- Printing a label without a saved analysis (typing values for another analyzer). *My call; see "Calls to check".*
- The bridge firmware and the box.
- Windows. Linux only if `flutter_blue_plus` works there without extra work.

## Anti-goals

These would make the feature a failure even if it prints:

- **A MOD that is deeper than the gas allows.** The MOD is computed from the analysed O2 and always rounded **down**.
- **A label whose headline silently disagrees with the analysis.** See "Matching the analysis to the desired mix".
- **Losing the analysis because printing failed.** Always save first, then print.

## The label

There are two label types, chosen by the analysis's **gas role** (see "Desired mix and gas role"):

- **Bailout/deco** (the default): one big MOD.
- **Diluent:** three depths for a CCR diluent.

Both are 50 × 30 mm direct thermal and share the black bar and footer.

### Bailout/deco label

This is "layout 2" from the brainstorm mockups (`.superpowers/brainstorm/…/label-big-mod.html`):

```
┌──────────────────────────────────────┐
│█ Tx21/35 ███████████████████ EdP ████│  black bar, white text
│                                      │
│              67 m                    │  MOD, the biggest element (Tx21/35 at 20.6 %)
│              MOD 1.6                 │  ppO2 used, small
│                                      │
│ O2 20.6  He 33.8          31 Oct 26  │  footer
└──────────────────────────────────────┘
```

- **Black bar, left:** the desired mix name from `gasMixName(targetO2, targetHe)` (`lib/analysis/gas_naming.dart`), e.g. `Tx21/35`, `EAN50`, `Air`, `O2`. With no desired mix stored, or on a hard mismatch (see "Matching the analysis to the desired mix"), use `gasMixName(analysedO2, analysedHe)`.
- **Black bar, right:** `analysed_by` exactly as typed (Egbert types initials, "EdP"). Omit it when blank.
- **Centre:** the MOD in whole metres, very large. Under it, small: `MOD 1.6` or `MOD 1.4`. A 3-digit MOD such as `130 m` must still fit.
- **Footer, left:** analysed O2 and He with one decimal. Omit He when the gas has no helium (below `kHeliumNoiseFloorPercent`).
- **Footer, right:** analysis date as `d MMM yy` (e.g. `31 Oct 26`). This is unambiguous for DIY users in any country.

### Diluent label

This is layout A from `.superpowers/brainstorm/…/label-diluent.html`:

```
┌──────────────────────────────────────┐
│█ [DIL] Tx21/35 ██████████████ EdP ███│  black bar with an outlined "DIL" tag
│                                      │
│              43 m                    │  TOD, the biggest element
│              TOD 1.1                 │
│ 1.3: 53 m              MOD 1.6: 67 m │  small line
│ O2 20.6  He 33.8          31 Oct 26  │  footer
└──────────────────────────────────────┘
```

- **Three depths, all from the analysed O2 and each floored to whole metres:**
  - **TOD** at ppO2 **1.1**: the diluent limit the analyzer screen already labels "CCR dil".
  - The depth at ppO2 **1.3**: the high setpoint.
  - **MOD** at ppO2 **1.6**.
- These three ppO2s are **fixed** in v1. The "Use 1.4 for deeper mixes" setting does not touch the diluent label.
- Example: Tx21/35 analysed at 20.6 % gives 43 / 53 / 67 m.

### MOD rule (bailout/deco label)

- **Default:** the MOD uses ppO2 **1.6** for every mix.
- **New setting "Use 1.4 for deeper mixes"** (default **off**). When on, mixes with **desired O2 ≥ 50 %** keep 1.6 and all other mixes use 1.4.
- The 50 % test uses the **desired** O2, so an EAN50 that analyses at 49.6 % still counts as a 50 % mix. With no desired mix, or on a hard mismatch, use the analysed O2 rounded to a whole percent.
- The depth is `modMeters(analysedO2 / 100, ppO2)` from `lib/analysis/mod.dart`, floored to whole metres. Example: EAN50 analysed at 49.6 % → 22.3 m → prints `22 m`.
- **The live analyzer screen must floor too.** Today it rounds MODs to the nearest metre (`_PlanningCard` in `lib/ui/screens/analyzer_screen.dart`, `toStringAsFixed(0)`), so it would show 68 m where the label prints 67 m. Change it to floor and update its tests.
- This setting is separate from the existing `analyzer_mod_ppo2s` list (1.1/1.4/1.6) that the live analyzer screen shows. Don't merge them.

## Desired mix and gas role

### Data

- Add `target_o2_percent` and `target_he_percent` (integer, nullable) to `gas_analyses`. Store whole numbers, not a name, so the name rule stays in `gas_naming.dart` and the 50 % test works.
- Add `gas_role` (text, nullable) to `gas_analyses`: `'diluent'` or `'bailout'`.
  - `'bailout'` covers bailout, deco, stage and OC.
  - Null means bailout/deco, so old rows print the bailout/deco label.
  - Storing the role on the analysis means a reprint looks the same even if the cylinder's role in Equipment changes later.
- **Supabase:** new migration `0020_…sql` with `alter table gas_analyses add column if not exists …`. `lint_migrations.sh` rejects a bare `add column`. The table already exists, so no new grants are needed.
- **Deploy 0020 to production before any build that writes these columns ships.** Uploads send the whole row (`ccrlogger_backend_connector.dart`), so Supabase rejects analysis uploads from a newer build until the columns exist.
- **PowerSync:** add the three columns to `gas_analyses` in `lib/sync/cloud/powersync_schema.dart`. The sync rule is `SELECT *`, so `infra/powersync-sync-rules.yaml` needs no change. If the Sync Streams migration (#126) has landed by then, check that its stream also selects every column.
- **Code:** update `GasAnalysis`/`NewGasAnalysis` in `lib/data/models/gas_analysis.dart`, `gas_analyses_dao.dart`, and the CSV export (`gas_analysis_csv.dart`) with the new columns.
- **Cylinder choices:** `CylinderChoice` and `listCylinderChoices()` also return the cylinder's `role` (`cylinders.role`, values in `CylinderRole` in `lib/data/models/equipment.dart`).
- **Analysis log screen:** show the desired mix name next to the analysed mix, with the analysed numbers coloured by match level, plus a "DIL" marker on diluent entries.

### Save card input (`lib/ui/widgets/analysis_save_card.dart`)

- Add a "Mix" row of tap-to-pick chips:
  - the Blend-tab target, but only if the diver changed it in the last 24 hours. `BlendNotifier` always has a target (default 18/45), so store an edited-at timestamp with it;
  - the distinct desired mixes from the last ~10 analyses in the log;
  - "Other…", which opens O2 and He whole-number fields.
- No chip is preselected. The field is optional.
- **Gas role:** add a two-way switch, "Diluent" / "Bailout/deco".
  - It defaults from the selected cylinder's role: `diluent` → Diluent; `bailout`, `offboard`, `oxygen` or no role → Bailout/deco.
  - With no cylinder selected it defaults to Bailout/deco.
  - The user can always flip it. It is saved as `gas_role`.
- **Match level:** once a desired mix is picked, colour the analysed numbers on the card green/orange/red, with the "off by" line (see "Matching the analysis to the desired mix"). It updates live as the reading changes.
- **Persist the Blend tab's target O2/He/pressure** in SharedPreferences (today `BlendNotifier` keeps them in memory only). Egbert blends at the fill station and analyses hours later, often after the app has been closed. This is in-flight form state, which principle 7 allows to stay on the device. The pressure is persisted only so the Blend tab restores its form; it doesn't prefill the save card's fill pressure.

### Editing after saving

- From the analysis log, the diver can edit the **desired mix, gas role, analysed by and notes** of an entry. A reprint then uses the corrected values.
- The measured values (O2, He, temperature, pressure, time, stable) are never editable.
- This needs a DAO `update` that bumps `updated_at` and `version` like other user-editable rows.

### Matching the analysis to the desired mix

Egbert decided: **never block printing, and grade how far the analysis is from the desired mix.**

Compare the analysed O2 and He with the desired mix, using absolute difference in percentage points. The overall level is the worse of the two.

| Level | O2 off by | He off by | What the diver sees |
|---|---|---|---|
| **Match** | ≤ 1.0 | ≤ 2.0 | Analysed numbers in **green** on the save card and in the log. |
| **Orange** | > 1.0 to 2.0 | > 2.0 to 4.0 | Numbers in **orange**, plus a line such as "O2 1.5 off Tx21/35". |
| **Red** | > 2.0 to 5.0 | > 4.0 to 10.0 | Numbers in **red**, same line. |
| **Hard mismatch** | > 5.0 | > 10.0 | Red, **plus the warning dialog before printing** (below). |

- **Thresholds:** the O2 levels and the 5.0 O2 / 10.0 He hard limits are Egbert's. The He match/orange/red bounds (2.0 / 4.0) are *my call*, scaled from the O2 ones.
- **Colour is never the only signal:** each level also shows text ("1.5 off"), so it reads in sunlight and for colour-blind divers.
- **Match, orange or red:** the label prints normally with the **desired** mix name in the black bar. The big MOD is still computed from the analysed O2, so it's always right for the gas in the cylinder.
- **Hard mismatch:**
  - Before printing, from "Save & print" or a reprint in the log, show a warning dialog with a red header: **"Mix does not conform to analysis"**.
    - The body reads, for example: "Desired EAN50, analysed O2 32.1 % (EAN32). The label will show EAN32."
    - Buttons: **"Print as EAN32"** (primary), **"Change desired mix"** (opens the edit from the log, or the mix field on the card), and **"Cancel"**.
  - The printed label then uses the analysed values everywhere:
    - the analysed mix name in the black bar;
    - the analysed O2, rounded, for the 50 % test of the "Use 1.4" setting.
  - *My call:* there is no "print the desired name anyway" button.
- **No desired mix:** no level, no colour; the label uses the analysed mix name.
- The level depends only on stored values, so a reprint on any device behaves the same.

## Printing flow

- **Save card:** when a printer is configured, show **"Save & print"** next to "Save". It saves first, exactly as "Save" does today, including the existing confirm for an unstable reading. Then it prints the saved analysis. A print failure shows an error with "Retry"; the analysis stays saved.
- **Copies:** a small stepper (1–9, default 1) next to "Save & print", for twinsets.
- **Analysis log:** each entry gets a print action, with the same copies prompt. A reprint uses the stored values and the stored desired mix. It uses the **current** MOD setting, which can differ from when the analysis was saved.
- **Demo readings never reach the log or a label.** While the Demo transport is selected, the save card (and with it "Save & print") is hidden. The Settings test print covers trying out the printer.
- **No printer configured:** hide "Save & print" and show a small "Set up label printer" link to the settings section.
- **Errors:** show printer status when the Phomemo reports it (out of labels, cover open, low battery, overheated). Show "Printer not found" when it isn't in range or is off.

## Printer setup (Settings → "Label printer")

- "Find printer" scans for Phomemo BLE devices, and the user picks one. Store its BLE remote id and name in SharedPreferences.
  - This stays **device-local** on purpose: BLE ids differ per phone (iOS uses a per-phone UUID), so syncing them is meaningless.
- **"Use 1.4 for deeper mixes"** toggle. It lives in SharedPreferences like the other analyzer settings. It belongs with the existing settings-don't-sync gap noted in the analyzer track; don't build settings sync here.
- **"Print test label"** prints a sample (Tx21/35, 20.6/33.8, today, the current MOD setting).
- **"Forget printer."**

## Architecture

The structure mirrors `shearwater/parser` vs `shearwater/ble`. Directory names are suggestions.

- `lib/labels/` (pure Dart, no Flutter):
  - `CylinderLabel`: the values on the label (mix name, MOD metres, MOD ppO2, O2, He, date, initials), built from a `GasAnalysis` (including its desired mix and gas role) plus the MOD setting. One type covers both label kinds.
  - The MOD rule as a pure function.
  - Heavily unit-tested.
- `lib/labels/render/` (Flutter): draws a `CylinderLabel` with `dart:ui` (`PictureRecorder` → `Image`) at printer resolution and converts it to a 1-bit bitmap. Use a fixed bundled or system bold sans font so output doesn't vary by platform.
- `lib/label_printer/` (pure Dart):
  - `LabelPrinter` interface: connect, `print(bitmap, copies)`, a status stream, disconnect.
  - `phomemo/`: a pure-Dart encoder that turns a 1-bit bitmap into Phomemo command bytes.
- `lib/label_printer/phomemo/ble/`: a thin `flutter_blue_plus` transport. It writes encoder output in chunks, reads status notifications, and holds no protocol logic.
- **Platform files:** update the Bluetooth usage strings in `ios/Runner/Info.plist` and `macos/Runner/Info.plist`. They currently mention only Shearwater; they need to cover label printers too, and the bridge later. Android permissions are already in place for BLE.
- **Dependencies:** none new. `flutter_blue_plus`, `intl` and `shared_preferences` are already in the app. Don't add the `phomemo` pub package: write the encoder (small, and dependency-light per CLAUDE.md). Use the package and the reference projects below to cross-check bytes.

## Phomemo M110: what's known, what to verify on the bench

| | |
|---|---|
| Known (from research, not yet verified on hardware) | BLE service `0xFF00`, write characteristic `0xFF02`, notify characteristic `0xFF03`. 203 dpi, 384-dot (48 mm) print head, labels 20–50 mm wide. ESC/POS-like raster commands. Plain BLE, not MFi, so iOS works through CoreBluetooth. Accepts non-Phomemo gap labels (no RFID lock). |
| References | `github.com/vivier/phomemo-tools`, `github.com/transcriptionstream/phomymo`, `pub.dev/packages/phomemo` (byte builder), `github.com/Niko11111/SpoolmanScale` (ESP32-S3 driving an M220). |
| Verify on the bench before finishing | The exact init, label/gap, density and raster sequence for the M110. Chunk size and write-with/without-response. Whether the black bar prints evenly (density, battery level). Whether it prints while on USB power. The status notification format. |

**Getting real bytes:**
- If an Android phone is available, capture an HCI snoop log of Phomemo's own app printing a 50×30 label. Write the encoder test-first against those bytes.
- Otherwise, build from the references above and correct it on the bench.

A 50 × 30 mm label is about 400 × 240 dots, of which the head covers 384 dots. Render at 384 × 240 with the content inside a safe margin of about 1.5 mm.

**Hardware Egbert is buying for this:** a Phomemo M110 plus 50×30 mm labels (one paper roll, one "waterproof" synthetic roll).

## Testing

- **Unit tests** (pure Dart):
  - MOD rule: the 1.6 default; the setting on with desired 50 vs 49 %; the analysed-O2 fallback; flooring; a 3-digit MOD.
  - Diluent depths: 1.1/1.3/1.6 floored; unaffected by the 1.4 setting; a null `gas_role` gives the bailout/deco label.
  - `CylinderLabel` building: no desired mix, no He, blank initials.
  - Phomemo encoder against byte sequences cross-checked with a reference implementation.
  - DAO round trip of the new columns.
  - Match levels: each boundary for O2 (1.0 / 2.0 / 5.0) and He (2.0 / 4.0 / 10.0); worst of the two wins.
  - The label keeps the desired name up to red.
  - A hard mismatch uses the analysed name and the analysed O2 for the 50 % test (desired EAN50, analysed 32 % with "Use 1.4" on → `EAN32`, 1.4, 33 m).
- **Golden test:** the rendered 1-bit bitmap for a few labels (Tx21/35, EAN50, O2, a 130 m MOD, and a Tx21/35 diluent).
- **Widget tests:** the save card's mix chips, the role switch defaulting from the cylinder, "Save & print" (save happens even when the print fails), the match colours, the "Mix does not conform to analysis" dialog on both print paths (hard mismatch only), and the log's reprint and edit actions, using a fake `LabelPrinter`.
- **Manual on hardware:** a test print and a real analysis → print on macOS, Android and iPhone.
- `flutter analyze` clean, `flutter test` passing.

## Calls to check (made by Claude, not yet confirmed by Egbert)

- No label printing without a saved analysis (no typed-in values) in v1.
- He match/orange/red bounds of 2.0 / 4.0 points (Egbert set only the 10.0 hard limit for He).
- A hard mismatch always prints the analysed mix name; the dialog has no "print the desired name anyway" option.
- Match colours also appear in the analysis log, not only on the save card.
- "Save & print" as a second button, plus the copies stepper (1–9).
- A reprint uses the current MOD setting, not the one at save time.
- The label uses the app's mix names as-is (`Tx21/35`, no space).
- Date format `d MMM yy`.
- Mix chips: the Blend target plus recent desired mixes from the log, and the Blend target persisted on the device.
- The printer's BLE id stays on the device and doesn't sync.
- The diluent label's three ppO2s (1.1 / 1.3 / 1.6) are fixed, not a setting.
- Desired mix, role, analysed by and notes are editable from the log; measured values are not.
- The Demo transport hides the save card, so demo numbers can't be saved or printed.
- The analyzer screen's MODs change from rounded to floored, to match the label.
- The Blend-target chip shows only if the target was changed in the last 24 hours, and no chip is preselected.
- Oxygen and offboard cylinders get the bailout/deco label. The role is stored per analysis, so a reprint doesn't follow later edits in Equipment.

## Left to the builder

File and class names, how to chunk BLE writes, font choice, exact pixel layout within the rules above, and the exact wording of UI strings.
