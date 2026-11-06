# Gas tabs and Settings redesign — Design

Date: 2026-11-06. No issue yet.
Related: #111 (analysis log), #113 / #151 / PR #152 (Log on OK), #114 (cylinder labels), #145 / PR #146 (MODs as 3 m stops).

Mockups, in `2026-11-06-gas-and-settings-redesign/` next to this file (open the `.html` in a browser, or look at the `.png`):

| File | Shows |
|---|---|
| `gas-tabs.png` / `.html` | The new **Gas** destination: the Blend, Analyse and Log tabs on an iPhone 15 (393 × 852 pt) with the bottom nav. |
| `analyzer-states.png` / `.html` | The Analyse tab with Log on OK running, every other state as a crop, and the wide layout. |
| `settings-tabs.png` / `.html` | Settings as five tabs: General, Planning, Gas, Sync, About. |

The mockups are layout and hierarchy, not pixels. Where this document and a mockup disagree, this document wins.

## Why

The Blend tab, the gas analyzer, the analysis log and Settings grew one feature at a time (#111, #113, #114, #145), and each feature added another card and more controls. Egbert reviewed them on his phone. What bothers him:

- **Analyzer:** it scrolls on a phone and everything is too big. Source and Connect take too much room. "Log on OK" doesn't read as something you switch on. The trend chart is nice but rarely useful. The save card makes him pick a mix, a role, a pressure and a name for every cylinder, when the app could fill most of that in.
- **Blend:** doesn't look like the rest of the app (the dive screen). The analyzer and the analysis log hang off it as pushed screens instead of being part of it.
- **Settings:** one long, cluttered list. No About section with version, build, date and author.

He wants all four pages to look like the **dive screen** (the dive detail summary band, its stat tiles and section headings), and both the Blend and Settings destinations to be **tabbed like the dive screen**.

## Who uses this, and where

- **At his own fill station:** blends on the Blend tab, lets the cylinders cool, analyses each with the Divesoft SOLO, prints a Phomemo M110 label. Phone on the bench, or in a pocket with Log on OK.
- **On the boat:** re-checks a cylinder, no printer.
- **At a filling station:** analyses gas someone else filled.
- **On the Mac at the bench:** the same pages in a wide window.

## Goals

1. The Analyse tab fits on one iPhone 15 screen, bottom nav included, with nothing to scroll in the normal (not logging) case.
2. One **Gas** destination with three tabs: Blend, Analyse, Log.
3. The save section is filled in for the usual case: you check it and press Save & print.
4. Log on OK reads as something you start and stop, and you can see from across the bench whether it is running.
5. Settings as five tabs with grouped settings and an About tab.
6. One visual language across the four pages, taken from the dive screen.

## Non-goals

- The dive screen itself, the Plan tab, Import and Equipment do not change. (The dive screen's icon-only tabs on phones stay as they are.)
- No change to what is measured, saved, synced or printed, apart from the defaults below. No new database columns or sync rules.
- No new analyzer transports (the BLE bridge is plan 2 of #113).
- Settings stay where they are stored today. The device-only ones stay device-only (see Constraints).

## Anti-goals (a failure even if it works)

- **A label that names a mix the diver never chose and that is off by more than "orange".** The label prints the desired mix's name up to a red match. A guessed desired mix must never put a wrong name on a cylinder (see "Desired mix: the nearest standard mix").
- **Losing data from the Planning section.** Egbert: "I like all data in the PLANNING section, keep the data as is."
- **Hiding the reading, or the fact that it isn't stable, behind the save form.**
- **A Settings item that disappears.** Every setting today must have a home (table in §6).

## Constraints (must keep)

- **Mix names** are prefixed (`Tx`, `Hx`, `EAN`, `Air`, `O2`, `Hypoxic`) and use whole numbers everywhere (`gasMixName`). The only exception is the live readout on the Analyse tab, which uses one decimal (`gasMixNameDecimal`). Measured O₂ and He values are numbers, not names. They may still show one decimal: in the log rows, the edit sheet, and the analyzer's numbers.
- On the Analyse tab the **MOD rows are judged against the desired mix** picked in the save section (#145: `limitDepthMeters` with `desiredO2Percent`, except on a hard mismatch).
- The analyzer settings (MOD ppO₂s, "Use 1.4", label printer, Log on OK, print on OK, and now "Your initials" and "Fill pressure starts at") are **device-only SharedPreferences** for now.
- Everything in git is English. **Don't run `dart format` on whole files**; main isn't format-clean and it churns about 1000 lines. Match the surrounding style by hand.
- Egbert's CCR setpoints are only 0.7 and 1.3. Nothing here should suggest others.
- Every decision of the Log on OK spec (`2026-11-03-background-gas-logging-design.md`) and plan 1 still holds, unless this document says otherwise. As built in `recordToAnalysis`, that covers:
  - OK is the trigger, and room air isn't logged.
  - An OK press doesn't wait for STABLE (decision 18). It saves the reading marked not stable, and prints when there is a name and the desired mix is none, match or orange.
  - No name, a red or hard mismatch, or a late record flags the entry "needs sign-off".
  - A flagged entry gets no label.
- Colours come from `context.palette`, `SafetyColors` and `DataColors`, so all six themes keep working.

## 1. Navigation: the Gas destination

- The bottom-nav item **"Blend" becomes "Gas"** (same science icon, same position).
- Gas has **three tabs: Blend, Analyse, Log.**
- **The top bar on Gas (and on Settings) is one 56 pt row:**
  - a small anchor mark (`AnchorlineLogo` with `AnchorlineMark.icon`) at the left; tapping it goes back to Dives, as the wordmark does today (`_goHome`)
  - a divider
  - the tabs
- That row replaces the shell's wordmark app bar on these two destinations only. Dives, Plan, Import and Equipment keep the full wordmark bar.
- The Blend and Settings screens' own titled app bars go, so no bar is stacked under another any more. This was Egbert's choice, made because it lets the Analyse tab fit with the bottom nav on screen.
- Tabs show **icon + label**. Use three different icons. The Blend tab and the Gas nav item must not share one icon the way "Analyze gas" and the Blend nav item do today. The Log tab uses `Icons.history`, as the analyzer's log button does today. The style is the dive screen's `TabBar`: accent label and underline on the selected tab.
- The **Blend tab's "Analyze gas" button** and the **analyzer's "Analysis log" button** go away. They are tabs now.
- Gas opens on the **Blend** tab after a cold start. While the app runs, the last tab you used is kept.
- **Equipment → cylinder → "Gas analyses"** still pushes a log screen filtered to that cylinder: the same rows as the Log tab, with an app bar titled "Analyses · ‹cylinder›".
- The **"Set up label printer" link** on the Analyse tab still pushes the label-printer settings screen (`LabelPrinterSettingsScreen`), restyled like Settings → Gas.

### Analyzer session lifetime

Today the analyzer is a pushed route, and leaving it disconnects. Now:

- The **analyzer session (controller, transport, Log on OK logger, wakelock) lives above the Gas tabs.** Switching between Gas tabs, or to another bottom-nav destination, keeps the SOLO connected and Log on OK running. You can watch the Log tab fill up while pressing OK on the SOLO.
- It ends on **Disconnect**, when the analyzer goes away (cable out), or when the app quits.
- While connected, the **Analyse tab shows a small dot** after its label: green when connected, accent when Log on OK is running. **The Gas item in the bottom nav shows the same dot** while you are on another destination.
- The Log on OK hint changes from "Keep this screen open" to **"Keep Anchorline open"**.

## 2. Shared style: the dive screen's language

Use the same pieces on all four pages:

- **Summary band:** full-bleed `surfaceRaised` block at the top, holding the page's main numbers as hero stats. A hero stat is a tabular mono value with a small unit, over an uppercase micro-label, with vertical `surfaceBezel` dividers between stats. This is the dive detail header (`_HeroStat` in `dive_detail_screen.dart`); extract it into a shared component rather than copy it.
- **Stat tiles:** `StatTile` (`lib/ui/components/stat_tile.dart`): a micro-label over a mono value.
- **Section headings:** the dive screen's uppercase micro-label in the accent colour (`SectionHeader`). Sections are separated by 1 px `surfaceRaised` lines. **No boxed cards** (today's `_Card` borders go).
- **Fields:** dense, filled `surfaceCard`, 1 px `surfaceBezel` border, 2 px radius, small label inside at the top, unit at the right ("230 bar").
- **Chips and segmented buttons:** today's `ChoiceChip` and `SegmentedButton` look: 2 px radius, accent tint when selected.
- **Primary action:** one filled accent button per screen, at most.
- **Touch targets:** at least 44 pt for buttons and steppers. Chips may be shorter, but no shorter than 32 pt.

## 3. Blend tab

Mockup: `gas-tabs.png`, left phone.

**Summary band: the fill plan.** It sits at the top and updates as you type below it.
- Line 1: target mix name (`gasMixName`, e.g. `Tx21/35`), then "to 230 bar".
- Hero stats: one per fill step, in order, numbered because it is a sequence: "1 · Helium", "2 · Oxygen", "3 · Air" (top-off named with `gasMixName`; pure helium stays "Helium").
  - Each value shows the bar to add ("+81 bar") with "to 131" (cumulative) under it.
  - Colours: helium `DataColors.helium`, oxygen `SafetyColors.success` (as today), top-off `textPrimary`.
  - A drain step comes first as "Drain", "−40 bar", in `SafetyColors.warning`. Up to four steps fit (drain + three).
- Under the steps, one mono line: litres per source ("He 966 L · O₂ 257 L · Air 937 L"), and the total cost on the right.
  - There is no currency symbol, as today.
  - Tapping the cost shows today's breakdown (He · O₂ · air).
- Drain-first and hot-fill notes: slim banners inside the band, under the steps (warning and info colours, today's texts).
- An impossible blend replaces the steps with a danger banner carrying today's message. "Nothing to do" replaces them with a muted line.

**Inputs, below the band, in this order:**
1. **Target:** chips for Tx21/35, Tx18/45, Tx15/55, EAN32 and EAN50.
   - A chip is selected when the fields hold that mix. Tapping one fills the fields. Typing a different mix deselects all chips.
   - No "Other…" chip; the fields are right there.
   - Then O₂ %, He %, Pressure bar (whole numbers).
2. **In the cylinder now:** O₂ %, He %, Pressure bar, Size L (water capacity).
3. **Top off with:** chips Air, EAN32, EAN50, Other….
   - "Other…" opens the same O₂ / He dialog as the desired-mix picker.
   - A custom top-off gets its own selected chip, as `DesiredMixPicker` does.
4. **Fill options:** one collapsed row with a summary on the right ("He → O₂ → top-off · real gas · 20 °C").
   - Tapping it opens Fill order (dropdown), Real-gas maths (switch), Fill temp and Settled temp.
   - It starts collapsed each time; that isn't remembered.

The keyboard escape hatches of today (tap outside, drag to dismiss) stay. The target is still kept on the device for 24 h (`BlendNotifier.recentTarget()`), and the Analyse tab still offers it (§4.3).

## 4. Analyse tab

Mockups: `gas-tabs.png`, middle phone; `analyzer-states.png` for everything else.

### 4.1 Phone layout, top to bottom

1. **Connection strip** (32 pt):
   - Connected: status dot + "SOLO connected · USB" (the transport's name) + a text button "Disconnect".
   - Not connected: grey dot + "Not connected", a small Source dropdown (USB / Demo / USB (Android)) and a small filled "Connect".
   - Connecting: "Connecting…" with an amber dot.
   - Error: today's error text as a banner under the strip.
   - The Android note ("The phone powers the analyzer over the USB OTG cable.") shows as a caption under the strip while that source is picked and not connected.
2. **Banners**, slim, full width, under the strip, only when needed: today's connect error, and today's "no data is arriving" hint. Show the hint only for a SOLO that never sent a line, as today.
3. **Summary band:**
   - Line 1: the mix name with one decimal (`Tx20.6/33.8`, `Air`, `—` before data) and the stability pill on the right: NO DATA / SETTLING / STABLE / SENSOR ERROR, with today's colours.
   - Then three hero stats:
     - **Oxygen** (accent colour)
     - **Helium** (`DataColors.helium`)
     - **N₂ balance** (`textPrimary`)
   - Each stat is one decimal plus "%"; `--.-` before data and `***.*` on a sensor error, as today.
   - On a phone the values are about 30 pt; the dive screen's are 22, but these are read from further away.
4. **Planning:** heading "Planning" with an ⓘ on the right. The same data as today, as a 4-column grid of stat tiles (it wraps to more rows if more MOD ppO₂s are set):
   - **MOD ‹p›:** one tile per configured ppO₂. The 1.1 tile carries a small accent "DIL" tag. Depths come from `limitDepthMeters`, judged against the desired mix, as today.
   - **END:** at the 1.4 MOD.
   - **Density:** at the 1.4 MOD, in the density band colour.
   - **Min. depth:** "surface" or "‹n› m".
   - **Gas temp**
   - **Ambient**

   The labels shorten to "END" and "Density". The footnote says what they are measured at: "END and density at the 1.4 MOD. Seawater, 10 m/bar. END counts O₂ and N₂ as narcotic (or only N₂). Orientation only — plan with your own tools." On a phone that footnote sits behind the ⓘ (tap shows it); on wide it shows under the grid.
5. **Trend:** one row, "▸ Trend, last 2 minutes", with a small inline sparkline of O₂ and He on the right. Tapping it opens today's chart in place. It starts **collapsed** every time.
6. **Save analysis** section (hidden for the Demo source and without a log, as today):
   - **Heading row:** "Save analysis" on the left, the **Log on OK** button on the right (§4.4).
   - **Desired mix chips:** at most three mix chips plus "Other…", so they stay on one line on a phone (§4.3).
   - **Verdict line:** one line in the match colour, e.g. "Matches Tx21/35, the nearest standard mix" or "O₂ 1.1 off Tx18/45, the nearest standard mix".
     - The suffix says where the mix came from: ", the nearest standard mix" or ", the Blend target". There is no suffix when the diver picked it.
     - Today's two-number line (`O2 20.6 He 33.8`) is not repeated here, because the summary band shows the numbers.
   - **Role:** segmented Diluent | Bailout / deco.
   - **Two-column rows:**
     - Cylinder (dropdown, "No cylinder") | Fill pressure (bar)
     - Analysed by | For (optional)
   - **"+ Add a note":** opens a Notes field in place. It stays open while it holds text.
   - **Hints**, as today, when they apply: "Not stable yet…" (amber), and "Set up label printer" (link) when there is no printer.
7. **Action bar**, pinned at the bottom of the tab, above the bottom nav:
   - With a printer set up: **Save** (outlined), **Save & print** (filled, primary), and the copies stepper (− 1 +, 1–9).
   - Without a printer: one filled **Save**, full width.
   - While Log on OK runs, the bar becomes the status strip (§4.4).

**Height budget, iPhone 15 (393 × 852 pt).** The fixed parts take:

| Part | Height |
|---|---|
| Top safe area | 59 pt |
| Gas top row | 56 pt |
| Action bar | 64 pt |
| Bottom nav | 56 pt |
| Home indicator | 34 pt |

That leaves **583 pt** for the content. The mockup fills it exactly with these sizes:
- the 32 pt connection strip
- 10 pt section padding
- the 30 pt trend row
- 40 pt fields
- 6 pt between the mix line and the hero stats

Smaller phones scroll, and that is accepted.

### 4.2 Defaults in the save section

Egbert's notes: "Type: Diluent. Analysed by: Anchorline user initials. Fill pressure: 230. Default button: Save & Print."

| Field | Starts as | After a save |
|---|---|---|
| Desired mix | Picked automatically (§4.3) | Back to automatic |
| Role | **Diluent**, or **Bailout / deco** when the desired mix has more than 30 % O₂ (EAN32, EAN50, O2, Tx35/25), or, with no desired mix, when the reading does. A picked cylinder's Equipment role wins over that, and a role the diver taps wins over both. | Manual save: back to that rule, as today's reset. Log on OK: a tapped role stays across presses (§4.3). |
| Cylinder | No cylinder | Kept after a manual save, as today. Cleared by a complete OK save (plan 1's "used up"). |
| Fill pressure | **Settings → Gas → "Fill pressure starts at"** (default **230** bar) | Back to that value (today it clears) |
| Analysed by | **Settings → General → "Your initials"** | Kept for this session; see below |
| For | Empty | Kept, as today |
| Notes | Empty, folded | Cleared, as today |
| Copies | 1 | Back to 1, as today |
| Primary button | **Save & print** when a printer is set up | — |

"Analysed by" starts from "Your initials" each time a session connects. A different name typed there (someone else analysing) holds until Disconnect. It is **not** written back to the setting.

Today's remember-the-last-name behaviour (`analyzerAnalysedBy`) is replaced. On first run after the update, "Your initials" takes the remembered name if it is empty.

In Log on OK mode the "used up" rule of plan 1 still applies: a complete OK save uses up the per-cylinder fields. "Used up" now means "back to its start value" (pressure back to 230, cylinder cleared, notes cleared), not empty. A press that needs sign-off leaves them in place, as today.

### 4.3 Desired mix: the nearest standard mix

Egbert: the desired mix defaults to the closest standard mix. His examples:

- 20.4/33.5 → Tx21/35
- 49.2 → EAN50
- 19.1/43 → Tx18/45

He wrote "Tx21/34" for the first; that is read as Tx21/35.

**Standard mixes:** Air, EAN32, EAN50, O2, Tx30/30, Tx21/35, Tx18/45, Tx15/55, Tx12/65, Tx10/70, Tx35/25. Keep them in one `const` list in pure Dart under `lib/analysis/`; the Blend tab's target chips are a subset of it.

**Which mix gets picked, for a usable reading:**
1. The **Blend target**, if `BlendNotifier.recentTarget()` has one, it is **not used up**, and it grades **match or orange** against the reading.
   - "Used up" is the earlier spec's rule: one blend is one cylinder.
     - The first complete save (manual, or an OK press that saves complete) uses the target up, and `BlendNotifier` stores it as used next to the target.
     - Reopening the app or a new session never offers it for a second cylinder.
     - Any new edit on the Blend tab is a new blend with a new target.
   - That mark was planned for plan 3 of #113 and was never built; this redesign builds it.
2. Otherwise the **standard mix** that grades best against the reading. Match beats orange; among equals, the smaller O₂ difference wins, then the smaller He difference.
3. If no candidate grades match or orange, **nothing is picked**. A label then names the analysed mix (whole numbers), as today without a desired mix.

The grading is `gradeMix`, with today's bounds: match is O₂ ≤ 1.0 and He ≤ 2.0 points off; orange is O₂ ≤ 2.0 and He ≤ 4.0. The examples land on match, match and orange.

**Why only up to orange (the safety rule):** up to a red match the label prints the desired mix's name. If the app guessed further than orange, a 23/30 cylinder would be labelled "Tx21/35", and with Log on OK nobody is looking at the screen. A diver can still pick any mix by hand, with today's red and hard-mismatch handling, including the "Mix does not conform" dialog.

**Automatic vs the diver's pick:**
- While the pick is automatic it **follows the live reading**: it re-evaluates as the gas settles. A small hysteresis is the builder's call (§9).
- Tapping a chip, or using "Other…", makes it **the diver's pick**. That holds until the next manual save, and then the pick is automatic again.
- Tapping the selected chip clears it (no desired mix). That also counts as the diver's choice until the next save.
- **Log on OK:** an automatic pick is made **from the held reading of each press**, so every cylinder in a batch gets its own nearest mix. A diver's pick stays for every press, as today ("lining up a batch of the same mix").

**The role follows the mix.** The role decides the label layout:
- A **diluent** label leads with TOD 1.1, with MOD 1.6 in a corner.
- A **bailout** label leads with MOD 1.6, or MOD 1.4 below 50 % O₂ with "Use 1.4" on.

A batch with automatic picks can mix trimix and deco gas, so the role is worked out per cylinder:
- While the diver hasn't tapped a role and no cylinder is picked, a desired mix with **more than 30 % O₂** gets **Bailout / deco**. Anything else gets **Diluent**.
- This holds for an automatic pick and for a mix the diver picks.
- With Log on OK it is worked out **per press**, from that press's mix.
- A role the diver taps stays for every press until changed (the earlier spec's "stays until changed"). In manual mode a save resets it, as today.
- A picked cylinder's Equipment role wins as long as that cylinder is picked.
- With no desired mix, the rule looks at the reading's own O₂. An EAN40 that matches no standard mix still gets Bailout / deco.

**Chips offered:** the selected mix first (automatic or the diver's), then the Blend target, then recent desired mixes from the log. No duplicates, at most three, then "Other…".

The MOD rows in Planning follow whatever is selected, automatic or not (§4.1), as #145 does today.

### 4.4 Log on OK: start and stop

Egbert chose "something you start and stop" (option B) over a mode switch.

- **Start:** a small outlined **"Log on OK"** button with a ring icon, at the right of the "Save analysis" heading.
  - It is enabled while a real (non-Demo) analyzer is connected and there is a log; disabled before connecting; hidden for Demo.
  - It sits in the heading rather than the bottom bar, because a phone's bar only fits Save, Save & print and the copies. That was my call; Egbert was fine with either.
- **Running:**
  - The heading's right side reads **"● Logging on OK"** in the accent colour.
  - The **action bar becomes a status strip**: accent-tinted, with a pulsing dot, two lines of text, and **Stop** on the right.
    - Waiting: "Logging on OK" / "Press OK on the SOLO to save".
    - Held (the SOLO went quiet after streaming; today's rule): grey dot, "Held on the SOLO" / "Press OK there to measure again".
    - Room air (OK doesn't log air): "Air isn't logged on OK" / "Tap Save to log it", with a filled **Save** and then **Stop**.
  - A row **"Print a label on each OK"** appears in the save section, with the copies stepper and the switch. It is only there while running and a printer is set up; without a printer the "Set up label printer" link shows instead.
  - Under it, **the last press's result**: icon, today's messages ("Printed …", "Saved …", "Saved, needs sign-off: …", "Needs sign-off: …", "Room air: not logged", "Not saved: …"; the mockup's wording is illustrative), the result's colour as a 3 pt left edge, and **Edit**.
    - Delete is no longer on this row; it lives in the edit sheet, which already has it.
  - The not-stable hint reads as today: "Not stable yet. An OK press now saves it marked not stable."
- **Stop** = today's switch off. A press already being handled still finishes and is saved, as today.
- It is **remembered on the device**, as today's switch is (`analyzerLogOnOk`). Left running, it runs again on the next connect.
- The wakelock rule is unchanged: it is held while the logger watches.

While running, the tab scrolls by about one row on an iPhone 15 (mockup: "Analyse tab, Log on OK running"). That is accepted.

### 4.5 States (all on the Analyse tab)

| State | What changes (mockup crop) |
|---|---|
| Not connected | Strip: Source + Connect. Band: `—`, `--.-`, NO DATA. Save section buttons and Log on OK disabled. |
| Connecting | Strip: amber dot, "Connecting…". |
| Connect failed | Error banner under the strip; strip back to Not connected. |
| Connected, never any data | "No data is arriving…" banner (today's text, shortened as in the mockup). |
| Settling | Amber SETTLING pill; amber "Not stable yet…" line in the save section; manual Save / Save & print still work and ask first (today's dialog). |
| Stable | Green STABLE pill. |
| Sensor error | Red SENSOR ERROR pill; `***.*` values; Save disabled (no usable reading, as today). |
| Room air | Mix name "Air"; automatic pick Air; with Log on OK running, the room-air strip (§4.4). |
| Log on OK running / held / result | §4.4. |
| No printer set up | Save is the only (filled) button; "Set up label printer" link. |
| Demo source | No save section, no Log on OK (made-up readings), as today. |
| Disconnected after a session | The last reading stays, as today, with the strip back to Not connected. |

### 4.6 Wide layout (≥ `kAnalyzerWideBreakpoint`, 840)

Mockup: `analyzer-states.png`, bottom.

- The tab bar and the connection strip span the full width.
- **Left column (≈ 60 %):** summary band (mix name ≈ 34 pt, values ≈ 44 pt), Planning with its footnote shown, and Trend.
- **Right column (≈ 40 %):** the save section, with its own action bar (or status strip) at the bottom of the column.
- Today's `GlobalKey` that keeps the save section's state across the breakpoint stays.

## 5. Log tab

Mockup: `gas-tabs.png`, right phone.

- **Tool row:**
  - Filter chips **"All ‹n›"** and **"Needs sign-off ‹n›"**. The second is amber and only shown when n > 0. Together they replace today's "‹n› analyses need sign-off" line and its "Show only these" chip; the filter rules stay as they are.
  - **Export** (share icon) on the right exports the shown entries, as today.
- **Day separators:** "Today", "Yesterday", "3 Nov 2026".
- **Rows, in the dive list's style** (`DiveTile`):
  - **Left edge (3 pt):** the role colour. Diluent uses the accent; bailout / deco uses a second, quieter palette colour that reads in all six themes (the mockup uses slack steel `#3A6477` on Wreck).
  - **Line 1:**
    - a role tag, "DIL" or "BO"
    - **the analysed mix's name**, in mono, whole numbers (`gasMixName` of the measured values, today's `GasAnalysis.mixName`): "Tx21/34" for 20.6/33.8. It is not the label's name. The log records what was measured; line 3 says what it was meant to be.
    - an amber "Needs sign-off" tag when flagged
    - a notes icon when there is a note (tap or hover shows it)
    - the time ("14:02") on the right
  - **Line 2:** mono, small, secondary: measured "20.6 / 33.8" (O₂ / He, one decimal), "230 bar", analysed by (or "no name"), the cylinder, and "for ‹name›".
  - **Line 3:** the verdict against the desired mix, in its match colour ("Matches Tx21/35", "O₂ 1.1 off Tx18/45"). For an entry saved before stable it reads "Saved before stable" in amber, after the verdict if there is one. There is no line 3 when there is nothing to say. Why an entry is flagged isn't stored yet (plan 3, M4), so the row doesn't say why.
  - **Trailing:** a print button when a printer is set up. On a flagged entry it is faded, and a tap shows today's "sign off before printing" message.
- Tap a row to open the edit sheet. Swipe left to delete. The reprint flow (copies, mismatch dialog, print with Retry) is unchanged.
- **Edit sheet:** the same pieces as the save section.
  - The measured values become a small summary band: mix name, a stable / not-stable pill, O₂ and He with one decimal, date · temperature.
  - Then the desired-mix chips with the verdict line, the role, the two-column fields, For and Notes.
  - The buttons and their meaning are unchanged: Sign off, Sign off and print, Delete, Cancel, Save. The sheet is not mocked.
- The empty state is unchanged in meaning.

## 6. Settings

Mockup: `settings-tabs.png`.

- **Five tabs: General, Planning, Gas, Sync, About.** The top row is the anchor plus the tabs, as on Gas (§1). They are **labels only**, because five icons would not explain themselves (testers already missed a bare icon once).
- Rows use one shape: label, an optional one-line helper under it, and the control on the right.
- **Sliders become − / + steppers** (SAC 10–60 L/min, ascent rates 3–30 m/min, watermark 0–20 %), with the same ranges and steps as today.
- **MOD ppO₂ limits become chips:**
  - Each chip has a ✕, except the last one left.
  - "+ Add" opens a dialog that accepts 0.2–2.0, with two decimals (`analyzerModPpo2Min` / `Max`).
  - Today's comma-separated text field goes.

Where every setting goes:

| Today (section → item) | New tab → section |
|---|---|
| Account (sign in / signed in, sync status, sign out) | Sync → Anchorline account |
| Appearance → theme picker | General → Theme. A 3-column grid of tiles: name + 4 swatches + ✓ |
| *(new)* Your initials | General → You |
| Use speed coloured graph | General → Dive profile ("Colour by ascent speed") |
| Watermark opacity | General → Dive profile (stepper, %) |
| Count O₂ as narcotic in END | General → Dive profile |
| Bailout SAC bottom / deco | Planning → Bailout breathing rate (SAC) |
| Ascent rate fast / slow | Planning → Ascent rate ("To the first stop" / "Between stops") |
| Diluent is bailout-capable | Planning → Your bailout kit |
| 6.8 L and 12 L / 300 bar stage available | Planning → Your bailout kit |
| O₂ / He price per litre, top-off flat fee | Gas → Blending prices |
| Default top-off mix, default fill order, real-gas Z, default fill / settled temp | Gas → Blend tab starts with |
| MOD ppO₂ limits | Gas → Analyzer (chips) |
| *(new)* Fill pressure starts at (default 230 bar) | Gas → Analyzer |
| Label printer (printer, Find, Print test, Forget) | Gas → Label printer |
| Use 1.4 for deeper mixes | Gas → Label printer |
| Subsurface sync (all of it) | Sync → Subsurface Cloud. The same controls and button labels as today's `SubsurfaceSyncSection`, restyled |
| Force-stamp owner_id on local dives | Sync → Repair → "Re-assign dives to this account" |
| Drain upload queue manually | Sync → Repair → "Push stuck uploads" |
| Danger zone → Reset local data | Sync → Repair → "Reset local data" (danger colour) |
| Share BLE debug log | About → Support → "Share Bluetooth debug log" |
| Version | About |
| Footer "Anchorline" (long-press → Widgetbook) | About: long-press the logo |

Helper texts get shorter (see the mockup). The Repair items keep today's confirm dialogs and result sheets unchanged.

Log on OK, "print a label on each OK" and its copies stay on the Analyse tab, remembered on the device as today. They are not in Settings.

## 7. About tab and the build date

- **Summary band:**
  - The logo (`AnchorlineLogo`), "Anchorline", and the line "Dive log and analysis for CCR divers".
  - Three hero stats:
    - **Version** (`APP_VERSION`)
    - **Build** (`APP_BUILD`)
    - **Date** (new `APP_BUILD_DATE`, shown as "6 Nov 2026")
  - A development build (no version) shows "Development build" in place of the stats, as `BuildInfo.label` does today.
- **Rows:**
  - Author: "Egbert de Pauw"
  - Channel: Release, Nightly or Development
  - Licence: "GPLv2". The row is hidden while the repository has no LICENSE file, which it doesn't today.
- **Support:** "Share Bluetooth debug log" (today's action).
- **Build date:**
  - A new compile-time define `APP_BUILD_DATE` (`yyyy-MM-dd`, the UTC date of the build), read in `BuildInfo`.
  - Every place that passes `APP_VERSION` / `APP_BUILD` passes it too: the release commands in `docs/BETA_DISTRIBUTION.md`, `MACOS_DISTRIBUTION.md`, `WINDOWS_DISTRIBUTION.md` and `TESTFLIGHT_QUICKSTART.md`.
  - Add it to the cloud-builds plan (`docs/superpowers/plans/2026-11-02-cloud-builds.md`), whose build workflow (Phase D) will pass these defines. No CI passes them today; `tool/ci/version.dart` only works out the channel and version.
  - Without it, the Date stat is hidden.

## 8. Decisions

**Egbert's:**
- All four pages restyled like the dive screen.
- Analyzer: no scrolling on a phone; smaller Source and Connect; Log on OK made obvious; all Planning data kept; the trend collapsible and collapsed by default.
- Save defaults:
  - The desired mix is the nearest standard mix (his examples).
  - Role Diluent, "analysed by" from your initials, fill pressure 230.
  - Save & print is the primary button.
- Log on OK as start / stop (option B).
- Analyse and the log become tabs next to Blend.
- Settings tabbed and grouped, with an About section: version + build number, author, version date.
- The mockups were approved page by page: "much better", "This is what I meant".
- After the builder check:
  - The top bar on Gas and Settings is one row of anchor + tabs (§1). The other options were the wordmark bar plus a row of tabs, which scrolls, or no bar at all.
  - A desired mix above 30 % O₂ gets Bailout / deco unless the diver or a cylinder says otherwise (§4.3). The other option was keeping one role for the whole batch.

**My calls, which Egbert saw in chat and didn't object to:**
- Only preselect up to orange; otherwise no desired mix (the safety rule in §4.3).
- The Blend target before the nearest standard mix.
- "Tx21/34" read as Tx21/35.
- "Your initials" as a new setting under General.
- Fill pressure goes back to the start value after each save.
- Log on OK remembered on the device.
- Delete only in the edit sheet.
- The print-on-OK row only while running.
- The Log on OK button in the heading.
- Renaming the destination "Gas".
- The session survives tab switches, with the dot on the tab.
- The Equipment cylinder log stays a pushed screen.
- British "Analyse".
- The Settings grouping and tab names.
- Sliders → steppers.
- MOD chips.
- The fill-pressure setting.
- Repair items renamed.
- The licence row.
- The build-date define.

**My calls made while writing this, for Egbert to check:**
- Tx30/30 and Tx35/25 added to the standard list. They are GUE standard mixes; only "within orange" ever picks them.
- No "Other…" chip on the Blend target.
- No currency symbol.
- The verdict line's suffix.
- At most three mix chips.
- Hysteresis left to the builder.
- "Analysed by" holds for the session and is not written back.
- Migrating the remembered name into "Your initials".
- The tagline copy.
- After the builder check:
  - The Blend target's "used up" mark from the earlier spec is built here, so the automatic pick can honour it.
  - Log rows lead with the analysed mix's name (as today), not the label's.
  - The "more than 30 % O₂ → Bailout / deco" rule also covers a mix the diver picks, not only an automatic one. With no desired mix it looks at the reading's own O₂.
  - The Analyse tab's tighter sizes (32 pt strip, 30 pt trend row, 40 pt fields) make it fit under the real 59 pt top inset.

## 9. Left to the builder

- Widget structure. That includes where the analyzer session lives (the shell or a kept-alive Gas host), how the tab bar is built, and how the hero-stat component is extracted.
- Exact sizes, paddings and icons, within the mockups and the touch-target floor.
- A hysteresis on the automatic mix pick, if a reading on a boundary makes the chip flicker.
- Keeping existing test keys where the element survives (e.g. `analyzer-o2`, `analysis-save`, `analysis-save-print`, `analysis-print-‹id›`). The Log on OK switch's key moves to the start / stop button.
- Phone landscape. The shell already hides the bottom nav there; the Analyse tab may use the wide layout when it is ≥ 840 wide.
- Wide Blend, Log and Settings (not mocked): content in a centred column, about 720 pt at most.

## 10. Follow-ups (not part of this redesign)

- **The END setting contradicts the code.** Settings says "Off: only N₂ counts (GUE/DIR)", while `lib/analysis/end.dart` calls the O₂-narcotic formula the GUE / DIR one. The new helper text leaves agencies out; which is right needs settling.
- **Settings that should sync:** "Your initials" and the other device-only analyzer settings, once settings sync exists (CLAUDE.md principle 7).
- **The rest of the app** (Plan, Import, Equipment) in the same dive-screen language, if this lands well.

## 11. Testing

- Widget tests for each state in §4.5, the defaults table (§4.2), and the auto-pick rules (§4.3).
  - The auto-pick tests need Egbert's three examples, a reading with no candidate within orange (no pick), a Blend target beating a standard mix, and a diver pick surviving OK presses.
  - The pick itself is a pure function in `lib/analysis/` with unit tests.
- A test that an OK press with an automatic pick uses the **held** reading's nearest mix.
- Role tests (§4.3):
  - EAN50 picked → Bailout / deco; Tx21/35 → Diluent.
  - A cylinder's role wins over the mix rule; a tapped role wins over both.
  - A tapped role stays across OK presses; the role is re-worked per press when untapped.
- A test that the Blend target is not picked again after one complete save, and is picked again after a new Blend edit.
- A test that a label never carries an automatic pick that grades red or worse.
- A height check: the Analyse tab at 393 × 852, with a 59 pt top and 34 pt bottom inset and the bottom nav on screen, does not scroll in the stable, not-logging case with a printer set up. A widget test at that size is enough.
- Every row in the §6 table still changes its setting (the existing settings tests, moved to their tabs).
- `flutter analyze` clean and `flutter test` passing, as always. No whole-file `dart format`.
