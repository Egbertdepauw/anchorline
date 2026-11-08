# Anchorline Website, Rollout Steps 3 and 4: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The home page with the live dive profile and real screenshots (step 3), and the user manual with one page per app screen (step 4), on the site that steps 1 and 2 put live at `anchorline.despaankamer.nl`.

**Architecture:** Step 3 adds a Dart export tool in the app repository that turns one of Egbert's dives and one of his cells into an anonymised JSON file, a React SVG component that renders it with a crosshair, a phone-frame component for screenshots, and the home page assembled from the approved wireframe. Step 4 extends the `content` publish action to the manual (`docs/user/`), teaches the site's content loader and Markdown renderer about manual pages and their images, and adds the `/manual` routes; the manual texts and screenshots are written per app tab in docs-only PRs. Both steps reuse the loader, renderer, settings, header and footer from steps 1 and 2.

**Tech Stack:** As before: Next.js 16.4.3, React 19.3.1, Tailwind 4, TypeScript strict, Vitest, Playwright, `react-markdown` + `remark-gfm`; Dart for `tool/site_showcase/` and `tool/publish/` (uses `package:sqlite3`, a dev dependency, and the pure-Dart `SampleCodec`); ImageMagick (`magick`, installed) for screenshot redaction and PNG optimisation.

**Spec:** `docs/superpowers/specs/2026-11-08-website-design.md` (§3, §4.1, §4.5 manual pointer, §4.6, §5, §6, §7 steps 3–4, "Companion work"), plus the approved wireframe `2026-11-08-website-design/home-wireframe-a.html` (section order and content normative; spacing, type and desktop layout the builder's). The first plan `2026-11-08-website-rollout-steps-1-2.md` defines the components this one builds on.

**Scope:** rollout steps 3 and 4. Step 5 (domain, store listings) stays Egbert's checklist in the spec. Task 15 of the first plan (the `content` action for the legal texts) must land before this plan's Task 8; it is still waiting for PR #140.

## Global Constraints

- Everything in git is English; Conventional Commits; PR descriptions end with the attribution line; commits carry the `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` trailer. Every PR waits for Egbert's OK; nothing is pushed or merged outside the PR flow.
- The builder has no SSH access to the server. Deploys happen by merging to `main` of `Egbertdepauw/anchorline-web`; verification is through `https://anchorline.despaankamer.nl`.
- Site repository conventions from steps 1–2 hold: pinned versions; no new runtime dependency without a one-line reason; settings read at request time (`dynamic = "force-dynamic"` on every page and route that uses them); `text-muted` never for body-size text (R18); orange only for calls to action and focus rings; no third-party requests at runtime; `getSettings()`/`getLoader()` getters, never module-level calls.
- Palette and type verbatim from spec §3; chart colours depth `#E0E8EC`, PPO₂ `#FFCC66`, setpoint `#A0AEB6` dashed, cells `#4ADE80`, `#60A5FA`, `#F472B6`; Inter for text, JetBrains Mono with tabular figures for every number in the readout and the download row.
- Live profile (spec §5): one real dive of Egbert's and one of his cells; JSON under 100 kB; samples decimated to one per ten seconds; SVG drawn by one React component; crosshair follows pointer and touch; the static chart renders on the server; no animation beyond the crosshair, none under `prefers-reduced-motion`.
- Anonymisation, binding for every exported number and every screenshot: no date, no location or site name, no notes, no serial numbers, no user or buddy names, no account email. The export carries only relative times and dive ordinals. Screenshots are redacted before they enter any repository, and Egbert reviews every screenshot and the chosen dive before they are published; he may veto.
- Screenshots: Wreck theme, phone size (390 × 844 logical points, 2× scale → 780 × 1688 px), PNG optimised to under 400 kB each (`magick … -strip -define png:compression-level=9`, and a 2× → 1.5× downscale when still over), alternative text that says what the screen shows, shown in the site's generic phone frame (rounded bezel, no manufacturer imagery).
- Manual (spec §4.6): texts in the app repository under `docs/user/`; `index.md` is the contents page and its link order is the reading order; one page per screen, under about 300 words, in the fixed pattern (title, how to get there, screenshot, "What it's for", "On this screen", optional "Good to know", previous/next); second person, present tense; no callouts drawn on screenshots; the manual never gives diving advice. Images in `docs/user/images/<slug>-<n>.png`.
- Publish contract (spec §2): manual pages are `texts` entries keyed `docs/user/<slug>` with `title` = first heading and `updated` = the file's last git commit date; images uploaded next to the pages under `content/docs/user/images/`; the `content` action refuses a page with a missing image or an image without alternative text and removes stale manual objects from the bucket.
- Fixture mode keeps working: the site repository's `fixtures/content/docs/user/` holds a copy of the manual (texts and images), refreshed by `scripts/sync-content.sh`, so the temporary address shows the manual before the bucket exists.
- Lessons from steps 1–2 carried forward: a compose service is never named `web` (not touched here); every Caddyfile change goes through SpaankamerWeb's deploy, which now recreates Caddy when the file changed (not touched here).

## Review Focus

1. **Gaps in the cell traces.** During an open-circuit bailout or before the loop is closed, cell voltages can be zero or missing in the samples. The SVG must break the line at a gap instead of drawing to zero, and the readout must show "—" for a missing value. Test: Task 4 renders a fixture with a gap and asserts the path has two sub-paths and the readout shows "—".
2. **Touch on the profile must not trap scrolling.** A visitor dragging a finger over the chart on a phone expects the page to scroll unless they are deliberately reading the chart. The component uses `touch-action: pan-y` and shows the crosshair on touch without calling `preventDefault`. Test: Task 4's browser test on a 390 px viewport scrolls the page by a touch drag that starts on the chart.
3. **A manual page whose image is missing** (renamed file, failed publish) must still render its text with the alternative text in the frame, and the contents page must still list it. Test: Task 8 unit test with a fixture page pointing at a missing image.
4. **A link in `index.md` to a page that does not exist** must not break the manual: the contents page shows the link as plain text with no previous/next pointing at it, and the loader logs one warning. Test: Task 8 unit test on `parseManualIndex` with an unknown slug.
5. **A screenshot containing a name reaches a repository.** No test can catch this; the control is procedural: Task 3's capture checklist redacts before copying into the repository, the capture folder is outside both repositories, and every screenshot PR lists each image with "reviewed by Egbert: yes" before merge. The reviewer of Tasks 3, 5 and 9 checks the list, not the pixels.

---

## File structure

**App repository (`Egbertdepauw/ccrlogger`)**

```
tool/site_showcase/export.dart           CLI entry: dart tool/site_showcase/export.dart --db PATH [--dive ID] [--cell ID] --out FILE
tool/site_showcase/lib/showcase_db.dart  reads dives, dive_samples, oxygen_cells from a PowerSync SQLite file (package:sqlite3)
tool/site_showcase/lib/cell_series.dart  surface and peak mV per dive for one slot, mirroring EquipmentDao.mvSeriesForCell
tool/site_showcase/lib/showcase.dart     picks the dive and cell, decimates, anonymises, builds the JSON
test/tool/site_showcase/*_test.dart
tool/publish/lib/content.dart            (modify, Task 8) manual texts, images, git dates, deletions
tool/publish/lib/bucket.dart             (modify, Task 8) list(prefix) and delete(key)
docs/user/index.md, docs/user/<slug>.md, docs/user/images/<slug>-<n>.png   (Task 9)
CLAUDE.md                                (modify, Task 9) one line: a PR that changes what a screen shows updates its manual page
```

**Site repository (`Egbertdepauw/anchorline-web`)**

```
src/content/showcase.json                the exported dive and cell (committed; < 100 kB)
src/content/home.ts                      the home page copy: pitch, tour blocks, roadmap, free/paid, supported computers
src/components/phone-frame.tsx           bezel around a screenshot
src/components/live-profile.tsx          server component: static SVG chart + cell strip
src/components/live-profile-crosshair.tsx client island: pointer/touch → crosshair + readout
src/lib/showcase.ts                      parseShowcase, scales, nearest-sample lookup
src/app/page.tsx                         the home page (replaces the placeholder)
src/app/opengraph-image.tsx              social image from the wordmark on hull black
public/screens/<name>.png                home-page screenshots (redacted)
src/lib/manual.ts                        parseManualIndex, manual page loading (Task 8)
src/lib/content.ts                       (modify) manualIndex(), manualPage(slug)
src/components/markdown.tsx              (modify) imageBase prop; headings level shift option
src/app/manual/page.tsx, src/app/manual/[slug]/page.tsx
src/components/site-header.tsx, site-footer.tsx, src/app/support/page.tsx, src/app/sitemap.ts (modify)
scripts/sync-content.sh                  (modify) copies docs/user/ too
fixtures/content/docs/user/…             copies, via the script
tests/*.test.ts(x), tests/e2e/*.spec.ts
```

---

## Task 1: Showcase export tool (app repository)

**Files:**
- Create: `tool/site_showcase/export.dart`, `tool/site_showcase/lib/showcase_db.dart`, `tool/site_showcase/lib/cell_series.dart`, `tool/site_showcase/lib/showcase.dart`
- Test: `test/tool/site_showcase/cell_series_test.dart`, `test/tool/site_showcase/showcase_test.dart`

**Interfaces:**
- Consumes: `SampleCodec.decode({blobs, diveId, sampleCount, sampleIntervalMs})` and `SampleSet` (`depthMeters`, `ppo2Bar`, `setpointBar`, `cellMv0..2`, all `List<double>`; `sampleIntervalMs`) from `lib/data/sample_codec/`; `package:sqlite3` (dev dependency; the tool runs with `dart tool/site_showcase/export.dart`, like `tool/publish/publish.dart`). PowerSync stores `dive_samples` blobs base64-encoded in text columns `depth_blob`, `ppo2_blob`, `setpoint_blob`, `cell_mv0_blob`, `cell_mv1_blob`, `cell_mv2_blob` (plus the others), with `sample_count`; `dives` has `id`, `dc_dive_number`, `start_time`, `duration_seconds`, `max_depth_mm`, `dive_mode`, `sample_interval_ms`, `deleted_at`; `oxygen_cells` has `id`, `slot`, `label`, `installed_date`, `retired_date`, `deleted_at`. The views `dives`, `dive_samples`, `oxygen_cells` exist in the PowerSync SQLite file and are readable with stock SQLite (they read JSON from `ps_data__*`).
- Produces: `src/content/showcase.json` for the site, format:

```json
{
  "format": 1,
  "dive": {
    "intervalSeconds": 10,
    "durationSeconds": 5400,
    "maxDepthMeters": 48.2,
    "depthMeters": [0, 1.2, …],
    "ppo2Bar": [0.7, …],
    "setpointBar": [0.7, …],
    "cellMv": [[9.8, …], [10.1, …], [null, …]]
  },
  "cell": {
    "slot": 1,
    "points": [ { "dive": 1, "day": 0, "surfaceMv": 9.9, "peakMv": 61.2 }, { "dive": 2, "day": 3, "surfaceMv": 9.8, "peakMv": 60.8 } ]
  }
}
```

  `null` marks a missing or zero cell reading. `day` is days since the cell's first dive; `dive` is the ordinal of that dive for this cell. No ids, dates, places, notes, serials or names appear anywhere in the file.

- Dart API in `showcase.dart`: `ShowcaseExport buildShowcase({required ShowcaseDb db, String? diveId, String? cellId})` returning `({String diveId, String cellId, Map<String, Object?> json, String summary})` where `summary` is the one-paragraph text shown to Egbert (dive number, date, max depth, duration, cell label; this text is for the chat only and is never written to the output). Auto-pick rules when ids are omitted: the dive is the most recent non-deleted CCR dive (`dive_mode` is the CCR value in `lib/domain`/parser enums; the builder names it) with `duration_seconds >= 3600`, `max_depth_mm >= 40000` and at least one sample with `decoDepth > 0`; the cell is the non-deleted cell with the most dives in its surface series and, among ties, the largest difference between the median of its first five and last five surface values.
- `cell_series.dart`: `({List<MvPoint> surface, List<MvPoint> peak}) mvSeriesForSlot(Iterable<DiveSamples> dives, int slot)` with `typedef MvPoint = ({DateTime date, double mv, String diveId})`, mirroring `EquipmentDao.mvSeriesForCell` and `_peakMvForSlot` in `lib/data/db/equipment_dao.dart` (lines ~396–520 as of 2026-11-08): the builder reads those two functions and ports their surface-window and peak definitions verbatim, with a comment naming the source, so the site shows the same numbers as the app.
- Decimation: keep every k-th sample where `k = max(1, round(10000 / sampleIntervalMs))`; depth as the maximum of the window, PPO₂ and cells as the mean of non-null values in the window (null when all null), setpoint as the last value. Values rounded to one decimal (mV) or two (bar, metres).

- [ ] **Step 1: Failing tests**

`cell_series_test.dart`: with three synthetic dives (SampleSets built in the test with known surface windows and peaks), `mvSeriesForSlot(…, 0)` returns the expected surface and peak values in dive order; a dive whose slot is all zero contributes no point. `showcase_test.dart`: `decimate(set, 10000)` on a 1 s set of 25 samples yields 3 points with the max depth, mean PPO₂ and null for an all-zero cell window; `buildShowcase` on a fake `ShowcaseDb` with two dives picks the CCR dive with deco over the shallow one, produces JSON with `format: 1`, no key named `id`, `date`, `serial`, `notes`, `site`, `buddy` or `name` anywhere (recursive check), and the JSON encodes to under 100 kB for a 90-minute dive at 10 s.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/tool/site_showcase`
Expected: FAIL, modules not found.

- [ ] **Step 3: Implement the four files**

`ShowcaseDb` opens the SQLite file read-only (`sqlite3.open(path, mode: OpenMode.readOnly)`), queries the views, base64-decodes the blobs and calls `SampleCodec.decode`. `export.dart` parses `--db`, `--dive`, `--cell`, `--out`, prints the `summary` to stdout and writes the JSON to `--out` (2-space indent). A missing `--db` or an unreadable file is a usage error with exit code 1.

- [ ] **Step 4: Run to see them pass, then analyze**

Run: `flutter test test/tool/site_showcase && flutter analyze`
Expected: PASS; "No issues found!".

- [ ] **Step 5: Run it on Egbert's logbook (controller, with Egbert)**

The macOS app on this Mac must be signed in to Egbert's account so PowerSync has pulled his dives; Egbert signs in himself. Find the database: `find ~/Library -name powersync.db 2>/dev/null`. Run `dart tool/site_showcase/export.dart --db <path> --out /tmp/showcase.json`, show Egbert the printed summary (the dive's number, date, depth, duration and the cell's label stay in chat), and wait for his OK or a different `--dive`/`--cell`. Only then copy the JSON to the site repository (Task 4).

- [ ] **Step 6: Commit (app repository branch from main; its own PR)**

```bash
git add tool/site_showcase test/tool/site_showcase
git commit -m "feat(tool): export one dive and one cell's mV history for the website showcase"
```

---

## Task 2: Phone frame and the home-page copy (site)

**Files:**
- Create: `src/components/phone-frame.tsx`, `src/content/home.ts`
- Test: `tests/phone-frame.test.tsx`

**Interfaces:**
- Produces: `<PhoneFrame src alt priority? className? />` renders a `<figure>` with a rounded bezel (card background, steel border, 22 px radius outside, 16 px inside, no notch, no buttons) around a plain `<img>` of 390 × 844 aspect (`width={390} height={844}` attributes so layout is stable, `loading="lazy"` unless `priority`), and `<figcaption>` only when a `caption` prop is given. `home.ts` exports typed constants: `PITCH` ("Dive logging built for CCR."), `PITCH_DETAIL` (the two hero sentences from the spec), `TOUR: { title, text, screen: string | "live-profile" }[]` (six blocks in the spec's order; block 3 is `"live-profile"`), `TOUR_FOOTNOTES` (one line each on Subsurface import and the SOLO gas analyzer), `ROADMAP: { label: "next" | "exploring", text }[]` (next: cell health across a cell's lifetime, two-way Subsurface sync, cloud sync across devices; exploring: other dive computers, the SOLO USB-to-Bluetooth bridge) with the footnote "Plans change; nothing here is a promise.", `FREE_PAID` (two short lists), `SUPPORTED_COMPUTERS` (Predator; Petrel 1, 2 and 3; NERD and NERD 2; Perdix, Perdix AI and Perdix 2; Teric; Peregrine and Peregrine TX; Tern) with the line about other manufacturers; `MANUAL_AVAILABLE = false` (Task 8 flips it to `true`).

- [ ] **Step 1: Failing test** — `PhoneFrame` renders `<figure>` containing an `<img>` with the given `alt`, `width="390"`, `height="844"`; with `priority` the `loading` attribute is absent; without it, `loading="lazy"`.
- [ ] **Step 2: Run, implement, run** — `npx vitest run tests/phone-frame.test.tsx` → PASS.
- [ ] **Step 3: Commit** — `feat: phone frame and home page copy`

---

## Task 3: Screenshots from Egbert's logbook (process task, controller with Egbert)

**Files:**
- Create: `public/screens/README.md` (the list of shots, each with alt text and "reviewed by Egbert"), `public/screens/*.png`
- Scratch (outside both repositories): `~/Desktop/anchorline-shots/raw/`, `…/redacted/`, `…/redact.json`

**Interfaces:**
- Produces the PNGs the home page (Task 5) and later the manual (Task 9) reference, with these names for the home page: `hero-dives.png`, `hero-detail.png`, `hero-cells.png` (the three hero shots: dive list, dive detail with the profile, O2 cells with the mV chart), `tour-deco.png` (deco replay with surface GF, CNS, OTU on the Details tab), `tour-cells.png` (cell detail, mV history), `tour-scrubber.png` (scrubber sessions), `tour-gas.png` (gas density and END on the profile), `tour-blend.png` (Blend tab), `tour-plan.png` (planner).

- [ ] **Step 1: Capture method** — the macOS app built from `main` (`flutter run -d macos --release` or the installed build), signed in as Egbert, Wreck theme, window resized to 390 × 844 points (the app shell is the same bottom-bar layout as on the phone at that width; if a screen lays out differently on desktop, use an iPhone simulator instead: `xcrun simctl create "iPhone 17 Pro" "iPhone 17 Pro" iOS26.4`, install the debug build, Egbert signs in on it). Capture with `screencapture -l <windowId>` (window id from `osascript -e 'tell app "System Events" to id of window 1 of process "Anchorline"'` or the computer-use tools) at 2× into `raw/`.
- [ ] **Step 2: Redact** — for every shot, list the rectangles that hold a user or buddy name, an email, a serial number, a site name, a date or a note in `redact.json` (`{ "file": "hero-detail.png", "boxes": [[x,y,w,h], …] }`), then `magick raw/F -fill '#142028' -draw 'roundrectangle x,y x+w,y+h 6,6' … redacted/F`; the dive list may show dates: crop the list to rows without dates or redact them. Optimise: `magick redacted/F -strip -define png:compression-level=9 public/screens/F`; downscale to 1.5× when still over 400 kB.
- [ ] **Step 3: Egbert reviews** — show him `redacted/` (open the folder); each file gets a line in `public/screens/README.md`: name, alt text, what was redacted, "reviewed by Egbert: yes". Nothing enters the repository before his yes.
- [ ] **Step 4: Verify sizes and commit** — `du -k public/screens/*.png` all under 400; `feat: home page screenshots from a real logbook, anonymised`

---

## Task 4: Live profile component (site)

**Files:**
- Create: `src/lib/showcase.ts`, `src/components/live-profile.tsx`, `src/components/live-profile-crosshair.tsx`, `src/content/showcase.json` (from Task 1 step 5)
- Test: `tests/showcase.test.ts`, `tests/live-profile.test.tsx`, `tests/e2e/home.spec.ts` (crosshair and touch cases; the rest of that file comes in Task 5)

**Interfaces:**
- Produces:

```ts
export type Showcase = { dive: { intervalSeconds: number; durationSeconds: number; maxDepthMeters: number; depthMeters: number[]; ppo2Bar: number[]; setpointBar: number[]; cellMv: (number | null)[][] }; cell: { slot: number; points: { dive: number; day: number; surfaceMv: number; peakMv: number }[] } };
export function parseShowcase(json: unknown): Showcase;            // throws on format !== 1 or unequal series lengths
export function sampleAt(s: Showcase, seconds: number): { depth: number; ppo2: number; setpoint: number; cells: (number | null)[]; index: number }; // nearest sample
export function depthPath(s: Showcase, w: number, h: number): string; // SVG path, one sub-path
export function seriesPath(values: (number | null)[], scale: (v: number) => number, xStep: number): string; // breaks at null (Review Focus 1)
export function formatMinutes(seconds: number): string;              // "12:30"
```

`<LiveProfile />` (server component): loads `src/content/showcase.json` at build/import time (static import, no I/O), renders a `<figure aria-label="Dive profile with PPO₂, setpoint and cell voltages">` containing the static SVG (viewBox `0 0 800 320`; depth axis inverted; depth filled area in `#E0E8EC` at 12% opacity with a 1.5 px line; PPO₂ `#FFCC66`; setpoint `#A0AEB6` dashed `4 4`; three cell lines on a right-hand mV axis; time ticks every 10 minutes in JetBrains Mono), a readout row (time, depth, PPO₂, setpoint, three cells; placeholders "—"), and under it the cell strip: a second SVG (viewBox `0 0 800 120`) with one point per dive of `surfaceMv` connected by a line in the cell's colour and a baseline label "surface mV per dive, one cell, N dives"; `peakMv` as faint points. The crosshair island `<LiveProfileCrosshair showcase />` is a `"use client"` component that overlays the chart: on `pointermove`/`touchmove` it computes `sampleAt` from the x position and updates a vertical line and the readout; `touch-action: pan-y` on the overlay (Review Focus 2); it never calls `preventDefault`; under `prefers-reduced-motion: reduce` the line appears without transition (there is no other animation anyway). The readout uses the `num` utility.

- [ ] **Step 1: Failing tests**

`showcase.test.ts`: `parseShowcase` accepts the committed file and rejects `format: 2` and a `ppo2Bar` shorter than `depthMeters`; `sampleAt(s, 0).index === 0` and `sampleAt(s, durationSeconds)` is the last index; `seriesPath([1, 2, null, 3, 4], id, 10)` contains two `M` commands (the gap); `formatMinutes(750) === "12:30"`. `live-profile.test.tsx` (renderToStaticMarkup): the SVG has one `<path>` per series present, the readout shows "—" for a cell that is null at index 0 of a fixture with a gap, and the figure has the aria label.

- [ ] **Step 2: Run to see them fail; implement; run to see them pass**

Run: `npx vitest run tests/showcase.test.ts tests/live-profile.test.tsx` → PASS. Confirm `src/content/showcase.json` is under 100 kB: `wc -c src/content/showcase.json`.

- [ ] **Step 3: Browser test cases (in `tests/e2e/home.spec.ts`)**

On `/`: moving the pointer to the chart's middle changes the readout's time from "—" to a `mm:ss` value; on a 390 × 844 viewport a touch drag that starts on the chart and moves 300 px up scrolls the page (`window.scrollY > 0`); with `reducedMotion: "reduce"` the page has no element with a non-`none` computed `transition-property` inside the figure.

- [ ] **Step 4: Commit** — `feat: live dive profile with crosshair and cell mV strip`

---

## Task 5: Home page (site)

**Files:**
- Modify: `src/app/page.tsx`, `src/components/site-header.tsx`, `src/components/site-footer.tsx`, `src/app/sitemap.ts`
- Create: `src/app/opengraph-image.tsx`, `public/brand/mark-full-1024.png`
- Test: `tests/e2e/home.spec.ts` (extend), `tests/e2e/shell.spec.ts` (header/footer link lists)

**Interfaces:**
- Consumes: `PITCH`, `PITCH_DETAIL`, `TOUR`, `ROADMAP`, `FREE_PAID`, `SUPPORTED_COMPUTERS` (Task 2); `<PhoneFrame>`; `<LiveProfile>`; `buildDownloadItems(settings, manifest)` and `<DownloadRow items />` from steps 1–2 (the hero's download row is the same component, so the visitor's platform comes first there too); `getLoader().manifest()`.
- Produces the home page in the wireframe's order: (1) hero: wordmark is in the header already, so the hero starts with `<h1>` = `PITCH`, the two sentences, the three `<PhoneFrame>`s (`hero-detail.png` leading and larger, `hero-dives.png` and `hero-cells.png` beside it; stacked on a phone with the leading one first), then `<DownloadRow>`; (2) "What it does today": six blocks alternating screenshot and text on desktop, stacked on a phone; block 3 is `<LiveProfile>`; the two footnote lines; a "Read the manual" link to `/manual` (rendered only when a `MANUAL_AVAILABLE` constant in `home.ts` is true, flipped in Task 8); (3) "Where it's going" with the two pills (`next` in green `#4ADE80` on `#1b3a2a`, `exploring` in `#FFCC66` on `#3a2e1b`, as the wireframe) and the footnote; (4) "Free and paid" two columns; (5) "Supported dive computers"; (6) the footer gets `Open source` (link to `settings.sourceRepoUrl`, rendered only when set) and keeps Manual (Task 8 adds it), Download, Privacy, Terms, Support, Delete your account, publisher. `page.tsx` declares `dynamic = "force-dynamic"` (it reads settings and the manifest). `opengraph-image.tsx` uses `next/og` `ImageResponse` (1200 × 630, hull black, the full mark plus `PITCH` in Inter). Satori renders PNG, not SVG, so the full mark is rasterised once into `public/brand/mark-full-1024.png` with `magick -background none public/brand/mark-full.svg -resize 1024x1024 public/brand/mark-full-1024.png` (the SVG stays the source; spec §3 names the full mark for social previews); `layout.tsx`'s `openGraph.images` is removed so the route is used.
- The placeholder home and its tests are deleted.

- [ ] **Step 1: Browser tests first** (`home.spec.ts`): `/` has exactly one `h1` with text `Dive logging built for CCR.`; three `figure img` in the hero with non-empty `alt`; a download row `ul` with five `li`; headings `What it does today`, `Where it's going`, `Free and paid`, `Supported dive computers`; the live profile figure present; no `Read the manual` link while `MANUAL_AVAILABLE` is false; axe no serious/critical on `/`; 360 px no horizontal scroll (already looped in `shell.spec.ts`); `/opengraph-image` returns 200 with `content-type: image/png`.
- [ ] **Step 2: Implement; run `npm run check && npm run build && CI=true npm run test:e2e`**
- [ ] **Step 3: Lighthouse on the deployed `/` after merge** (mobile): performance and accessibility ≥ 90; the screenshots are the risk — use `priority` only on the leading hero image.
- [ ] **Step 4: Commit, PR, Egbert's look at the home page on the temporary address** — `feat: home page with the live profile and real screenshots`

---

## Task 6: Step-3 wrap-up (controller)

- [ ] Final review of the step-3 branch (whole-branch reviewer, most capable model), one fix wave, Egbert's squash-merge, deploy, Lighthouse numbers recorded in the ledger.
- [ ] Egbert's veto round on the live site: the chosen dive, the cell, every screenshot; anything he vetoes is swapped before the branch is called done.

---

## Task 7: `content` action: the manual (app repository; after Task 15 of the first plan)

**Files:**
- Modify: `tool/publish/lib/content.dart`, `tool/publish/lib/bucket.dart`, `tool/publish/lib/cli.dart` (usage text), `.github/workflows/publish-content.yml` (paths already include `docs/user/**`)
- Test: `test/tool/publish/content_test.dart` (extend), `test/tool/publish/fake_bucket.dart` (extend)

**Interfaces:**
- Consumes: `ContentPublisher.publish({List<ContentText> texts})`, `ContentText(key, source, bucketKey)`, `parseLastUpdated`, `firstHeading`, `encodeContentIndex`, `Bucket` (`getText`, `putFile`, `putText`, `sha256Of`) from Task 15.
- Produces: `Bucket.list(String prefix) → Future<List<String>>` and `Bucket.delete(String key)` (AWS CLI: `aws s3api list-objects-v2 --prefix`, `aws s3 rm`); `FakeBucket` records `delete` calls. `List<ContentText> manualTexts(Directory repoRoot)`: every `docs/user/*.md` becomes `ContentText(key: 'docs/user/<slug>', source: 'docs/user/<slug>.md', bucketKey: 'content/docs/user/<slug>.md')` with `index.md` → key `docs/user/index`. `String gitCommitDate(String repoRoot, String path)` runs `git log -1 --format=%cs -- <path>` (UTC date) and is the `updated` for manual pages (legal texts keep the `_Last updated_` line). `List<String> imageRefs(String markdown)` returns the relative `images/...` paths referenced; `publish` refuses with `PublishError` naming the page when a referenced image file is missing or an image has empty alt text (`![](…)`), uploads `docs/user/images/*.png` as `content/docs/user/images/<name>` with `contentType: image/png` and `cacheControl: public, max-age=86400`, and after writing the index deletes bucket objects under `content/docs/user/` that correspond to no current page or image. Dry run lists would-be deletions.

- [ ] **Step 1: Failing tests** — missing image → `PublishError` mentioning the page and the image path, nothing uploaded; empty alt → the same; happy path uploads pages then images then the index (index last); a stale object `content/docs/user/old.md` in the fake bucket is deleted after the index is written; `gitCommitDate` on a temp git repository with one commit returns that commit's date; dry run performs no put and no delete.
- [ ] **Step 2: Run to see them fail; implement; `flutter test test/tool/publish && flutter analyze`**
- [ ] **Step 3: Commit** — `feat(publish): publish the user manual with the legal texts`

---

## Task 8: Manual on the site

**Files:**
- Create: `src/lib/manual.ts`, `src/app/manual/page.tsx`, `src/app/manual/[slug]/page.tsx`, `src/components/manual-nav.tsx`
- Modify: `src/lib/content.ts`, `src/components/markdown.tsx`, `src/components/site-header.tsx`, `src/components/site-footer.tsx`, `src/app/support/page.tsx`, `src/app/sitemap.ts`, `src/content/home.ts` (`MANUAL_AVAILABLE = true`), `scripts/sync-content.sh`, `fixtures/content/index.json`, `fixtures/content/docs/user/**`
- Test: `tests/manual.test.ts`, `tests/markdown.test.tsx` (extend), `tests/e2e/manual.spec.ts`

**Interfaces:**
- Consumes: `ContentLoader`, `cached`, `isSafeContentPath`, `splitTitle`, `LoadedText` from steps 1–2; `<Markdown>`; `getSettings().downloadsBaseUrl`.
- Produces:

```ts
// manual.ts
export type ManualEntry = { slug: string; title: string; group: string };
export function parseManualIndex(markdown: string): { intro: string; groups: { heading: string; entries: ManualEntry[] }[]; order: string[] }; // links `[Title](<slug>.md)` in document order under `##` headings; unknown-looking links (not `<slug>.md`) are left as text
export function prevNext(order: string[], slug: string): { prev?: string; next?: string };
// content.ts additions
manualIndex(): Promise<{ parsed: ReturnType<typeof parseManualIndex>; updated: string | null } | null>;   // drops a slug from `order` (and renders its link as text) when the content index has no `docs/user/<slug>` entry, with one console.warn naming it (Review Focus 4)
manualPage(slug: string): Promise<LoadedText | null>;   // null when the slug is not in the index (Review Focus 4), fallback copy as for legal texts
// markdown.tsx
imageBase?: string;   // prefix for relative image paths, e.g. `${downloadsBaseUrl}/content/docs/user/` or `/fixtures/content/docs/user/`
```

`/manual`: the contents page from `index.md` (intro, "Written for Anchorline 1.1.0" line as in the text, grouped links); `/manual/[slug]`: `<article>` with the page's title, the Markdown with `imageBase` and `allowedImageOrigins` = `[new URL(imageBase).origin]` when absolute, previous/next links and "Back to contents"; unknown slug → `notFound()`. Header gains `Manual` as its first link; footer gains `Manual`; Support gets the sentence "For what a screen shows, see the manual." linking `/manual`; sitemap lists the index and every page in order. `sync-content.sh` copies `docs/user/` (texts and images) into `fixtures/content/docs/user/` and the fixture `index.json` gains the `docs/user/*` entries (titles from first headings; `updated` by hand). Images inside the manual render through the `img` override of Task 11 (step 2) with `width`/`height` from the PNG when known (a small `images.json` written by the sync script with each image's dimensions, read at render time to set attributes and avoid layout shift).

- [ ] **Step 1: Failing tests** — `parseManualIndex` on a fixture with two `##` groups and three links yields order `["getting-started", "dives", "dive-details"]`, groups with headings, and leaves a link to `https://example.com` as text; `prevNext` at the first, middle and last slugs; `manualPage("no-such")` is `null`; an `index.md` linking `nope.md` while the content index lacks `docs/user/nope` yields an `order` without `nope`, a contents page showing "Nope" as text, and exactly one `console.warn`; a page referencing `images/missing.png` renders `<span>` with the alt text (Review Focus 3); `Markdown` with `imageBase="/fixtures/content/docs/user/"` turns `images/a.png` into `src="/fixtures/content/docs/user/images/a.png"`.
- [ ] **Step 2: Run, implement, run** — `npx vitest run tests/manual.test.ts tests/markdown.test.tsx`
- [ ] **Step 3: Browser tests** (`manual.spec.ts`, against the fixture that Task 9's first group provides; until then a two-page fixture written by this task): `/manual` lists every page in order; `/manual/<first>` shows the title, an `img` with non-empty alt, a `Next` link and no `Previous`; `/manual/no-such` is 404; the crawl in `download.spec.ts` now reaches every manual page.
- [ ] **Step 4: Commit** — `feat: user manual pages from published content`

---

## Task 9: Write the manual (app repository; docs-only PRs per app tab)

**Files:**
- Create: `docs/user/index.md`, the 24 pages listed in spec §4.6, `docs/user/images/<slug>-<n>.png`
- Modify: `CLAUDE.md` (one line under "Working in this project": "A PR that changes what a screen shows updates its page in `docs/user/` and its screenshot.")

**Interfaces:**
- Consumes: the page shape and page list from spec §4.6; the capture and redaction process of Task 3; the `content` action of Task 7 for publication; the fixture sync of Task 8 for the temporary address.
- Produces one PR per group, in this order: Getting started + Dives (list, details, information, media, equipment, sites map, statistics, buddies), Plan, Gas (blend, analyse, log), Import, Equipment (landing, dive computers, O2 cells, scrubbers, cylinders), Settings (general, planning, gas, sync, about). Each PR: the pages, their screenshots (redacted; the README-style checklist with "reviewed by Egbert: yes" in the PR body), `index.md` updated, and after merge `scripts/sync-content.sh` run in the site repository so the temporary address shows the group.

- [ ] **Step 1: `index.md`** — intro (two or three sentences: explains the app, not diving), "Written for Anchorline 1.1.0", the seven group headings, links in reading order. Commit with the first group.
- [ ] **Step 2: For each page** — follow the pattern: `# <Screen name as in the app>`, one line "Where: …", the screenshot(s) with alt text, `## What it's for` (one paragraph), `## On this screen` (list; bold label as in the app, one or two sentences, whether the value comes from the dive computer or from you), optional `## Good to know` (≤ 3 notes), and nothing else (previous/next are the site's). Under 300 words. Written from the running app and the code; terms from the app's labels.
- [ ] **Step 3: Per group** — `flutter analyze` is unaffected; the check is `dart tool/publish/publish.dart content --dry-run` (after Task 7) refusing nothing; Egbert reads the PR; squash-merge; sync the fixture in the site repository and open the matching site PR (fixture only).
- [ ] **Step 4: After the last group** — `CLAUDE.md` line; the home page's tour link already points at `/manual`.

---

## Task 10: In-app "User manual" link (app repository; small, last)

**Files:**
- Modify: the About tab in `lib/ui/screens/settings/` (the file that renders the About tab) — one `ListTile` "User manual" opening `https://anchorline.eu/manual` with `url_launcher` (already a dependency? the builder checks; if not, the link is shown as copyable text instead of adding a dependency).
- Test: the existing settings widget tests gain one case that the tile exists.

- [ ] **Step 1: Failing widget test; implement; `flutter test test/ui/screens/settings` and `flutter analyze`**
- [ ] **Step 2: Commit** — `feat(settings): link to the user manual from About`

---

## Order and parallelism

- Tasks 1, 2 and 3 are independent and may start together (1 and 3 need Egbert at their last step). Task 4 needs 1's JSON; Task 5 needs 2, 3 and 4. Task 6 closes step 3.
- Task 7 waits for Task 15 of the first plan (PR #140). Task 8 can start before 7 with a hand-made two-page fixture; it needs 7 only for publishing. Task 9 needs 3's method and 8's pages to show; its groups go one PR at a time. Task 10 last.
- Done for this plan: the home page with the live profile and real screenshots is live on the temporary address with Lighthouse ≥ 90, Egbert has vetoed nothing (or his vetoes are applied), every manual page is written, reviewed and visible at `/manual` from the fixture, and the `content` action publishes legal texts and manual alike.
