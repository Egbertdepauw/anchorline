# Subsurface git-repo plain-text format — implementation notes

This document captures non-obvious things we learned while building the
Phase A parser/serializer at `packages/subsurface_core/lib/sync/subsurface_git/format/`. The official
"format spec" is the Subsurface source code; what's below is what we observed
on a real cloned repo (~700 dives, ~195 sites, dives spanning 2004–2026,
with Petrel 1/2/3, Perdix 2, Garmin Descent Mk1 and manually-added dives).

## File kinds

A Subsurface git-format repo has four kinds of files:

1. `00-Subsurface` — top-level metadata. Contains `version`, one
   `divecomputerid` line per known dive computer, one `fingerprint` line per
   known dive, a single `units` line, and one or more `prefs` lines.
2. `01-Divesites/Site-<id>` — one file per dive site.
3. `<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>/Dive-<n>` — per-dive user
   annotations (notes, buddies, cylinders, weight, environmental conditions,
   site link).
4. `<...same path...>/Divecomputer` (or `Divecomputer-001`, `-002`, …) —
   per-DC log: header, events, then samples. A dive folder can hold
   multiple `Divecomputer-NNN` files when the diver wore more than one DC
   for the same dive.

The parser takes a `SubsurfaceFileKind` so it can disambiguate the same
keyword across file kinds (e.g. `model "..."` is a quoted-string field on
both `00-Subsurface`'s `divecomputerid` lines and on a `Divecomputer` file).

## Line layout and ordering

- Newlines are LF (`\n`), and every file ends with exactly one trailing
  `\n`.
- Within a file, line order matters and our serializer preserves it. We do
  not attempt to "canonicalise" tag order, cylinder field order, or anything
  else — Subsurface emits things in a particular order and reordering
  breaks byte equivalence.
- In a `Divecomputer` file, all `event` lines come before any sample line
  (we verified this across the corpus). Samples themselves are 2-space-
  indented; events are flush-left.

## Quoted strings

- Subsurface uses C-style `"..."` quoting. Embedded `"` is escaped as `\"`
  and embedded `\` as `\\`. **Other escapes (`\n`, `\t`, `\u…`) are NOT
  used.** When `notes` contains line breaks or tab indentation, those are
  *literal* `\n` (0x0A) and `\t` (0x09) bytes embedded in the quoted value.
  Result: a single logical `notes "..."` line can span many physical lines.
- Our scanner reads a "logical line" by tracking quote state, only treating
  a `\n` outside quotes as a line terminator. This is essential for sites
  like `Site-ecaf8184` (`Fortunal`) whose `notes` value is a 6-line
  paragraph.

## Forward compatibility

- Anything we don't recognise becomes a `RawLine` whose `source` is the full
  verbatim line. The serializer just re-emits it. So if Subsurface ships a
  new top-level keyword tomorrow, we round-trip it untouched.
- Every typed line still keeps its `source` string. The serializer prefers
  `source` when present, so even known line types round-trip exactly even if
  Subsurface uses a slightly different formatting than our `renderFromFields`
  produces.

## Numeric precision

- We deliberately store numeric values as their original string lexemes
  (e.g. `1.6m`, `12.522m`, `1.001bar`, `1000g/l`). Round-tripping
  `double.parse("1.6").toString()` produces `"1.6"`, but for some numbers
  it produces `"1.6000000000000001"` and silently breaks byte equivalence.
- Helpers in `subsurface_unit_parsing.dart` (`parseLengthMeters`,
  `parseTempCelsius`, `parsePressureBar`, `parseTimeSeconds`) parse the
  lexeme on demand for consumers that need a `double`/`int`. Phase B should
  not store the parsed numerics in the model — keep the lexeme.

## Time formatting

- Sample line times are right-padded to width 6 with leading spaces:
  `  0:05`, ` 10:07`, `100:02`, `1000:05`. Our `padSampleTime` helper does
  exactly that. When you write a new sample line, pass the time as
  `MM:SS`/`HHH:SS` (no leading whitespace) and let the serializer pad it.
- `event` line times are NOT padded — they're written as `event 0:05 …`,
  `event 17:09 …`, `event 100:02 …`.
- `duration 56:20 min` has a trailing ` min` (with space). `lastmanualtime
  56:20min` has NO space before `min`. We don't synthesise either form;
  we round-trip the source verbatim. If Phase B ever needs to emit one of
  these from scratch, follow the existing convention exactly.
- `salinity 1000g/l` (no space) vs. `watersalinity 1030 g/l` (with space)
  — yes, really. Keep them as `ScalarLine` and don't touch.

## Cylinder lines

Order of fields, observed in the corpus and assumed canonical:

```
vol  workpressure  description  o2  he  start  end  use  used(?)  depth
```

`use` values are quoted: `"diluent"`, `"oxygen"`, `"not used"`. `used` was
seen only as part of `use="not used"` (the parser only saw `use` as a key);
treat it as a value of `use`, not a separate key.

Cylinders may omit fields — e.g. `cylinder description="Steel"` is valid
(2008 dive). Phase B must construct cylinder lines with at least the keys
that match Subsurface's per-cylinder defaults; missing keys are interpreted
as "Subsurface default" and that may change across Subsurface versions.

## Sample lines

A sample line, after stripping leading whitespace, is:

```
<time> <pos1> <pos2> <pos3> ... <kv1> <kv2> ...
```

- The first positional token is **always depth** (`X.Ym`, with one or three
  decimal places observed).
- The next zero-or-one positional tokens are temperature (`X.Y°C`).
- The next zero-or-more positional tokens are tank pressures, in either
  the indexed form (`207.946bar:0` for tank 0) or the un-indexed form
  (`187.951bar`). Both forms appear, sometimes in the same dive — we
  haven't yet determined what triggers Subsurface to use one over the
  other. **Treat both as opaque lexemes for round-trip; only parse the
  numeric when the consumer actually needs it.**
- Then `key=value` pairs in original order. Observed keys:
  `tts`, `ndl`, `cns`, `sensor1..4`, `dc_supplied_ppo2`, `po2`, `o2pressure`,
  `heartbeat`, `in_deco`, `stoptime`, `stopdepth`.
- Samples are sparse: each line only carries tokens whose value changed
  since the previous sample. Reconstructing a "fully populated" view of a
  sample is therefore a stateful traversal — we don't do it in this layer
  (Phase B / the analysis layer will).

## Event lines

Two observed shapes:

```
event <time> type=<n> [flags=<n> | value=<n>] name="<text>" [cylinder=<n> [o2=<n>%] [he=<n>%]]
event <time> type=<n> name="<text>"   # bookmark, no flags or value
```

`type=20` is "SP change" (setpoint change) and uses `value=` (the raw
mbar?) instead of `flags=`. `type=25` is "gaschange" and uses `flags=`.
`type=26` is misc Garmin alerts ("Approaching NDL", "Deco completed", etc.)
and uses `flags=`. `type=8` is `name="bookmark"` with no extra fields.

The parser does not interpret these meanings — it stores `(type, flags |
value, name, …)` as an ordered key/value list. Consumers that need
semantics should map `type` -> meaning themselves.

## Things we defaulted on (verify in Phase B)

- **Empty quoted values**: `description ""` and `notes ""` round-trip
  fine, but we haven't tested them as model inputs. The `quoteString`
  helper produces `""` for an empty string, which matches the corpus.
- **Tag order**: `tags "X-CCR", "CCR"` and `tags "CCR", "X-CCR"` both
  appear in the same repo for similar dives. We preserve whatever order
  Subsurface wrote. If Phase B constructs a new `tags` line, it should
  pick *some* deterministic order — pending verification of what
  Subsurface actually does on save.
- **`use="not used"` vs no `use` key**: a cylinder with no `use` key is
  presumably "default" (whatever the dive's profile dictates). We
  preserve whichever form appears.
- **`weightsystem` ordering**: only seen with `weight=…` first and
  `description="…"` second. Phase B should follow that.
- **`Divecomputer` files without `dctype`**: very old dives (e.g. 2004,
  2008) have a minimal `Divecomputer` with only `lastmanualtime`,
  `maxdepth`, `meandepth` and a handful of synthetic samples. There's no
  `model`, no `deviceid`, no `dctype`. Our parser handles this — the
  unknown lines round-trip as typed `ScalarLine` because the keys still
  look like normal `key value` lines.
- **`Divecomputer-002` files** appear when a dive has multiple DCs. They
  parse identically to `Divecomputer`; the file kind is the same.
- **The `invalid` line** (a single keyword on its own line, no value)
  appears on dives the user has flagged as invalid. We model it as
  `FlagLine` and round-trip it.
- **`time HH:MM:SS` and `date YYYY-MM-DD` lines** appear inside some
  `Divecomputer-002` files (different per-DC start time). Treated as
  `ScalarLine`.
- **`filename "..."` lines** appear inside some `Dive-<n>` files
  (attachments). Treated as `QuotedLine`. Phase B should be aware that
  attachments live there.
- **`airpressure 1013`** appears in two old dives. Treated as `ScalarLine`.

## Phase B+ shopping list

Things this layer does NOT do, but the next phase will need:

- Map a CCRLog `Dive` row + samples + events to a `SubsurfaceFile` of
  kind `dive` plus a `divecomputer` companion. The model in this layer
  is the right *target*, but the mapping logic isn't here.
- Hash a dive into a stable Subsurface-style folder path
  (`<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>/`).
- Generate Subsurface-style `Site-<id>` ids (likely 8-char hex of some
  hash) and the matching `divesiteid` field on Dive files.
- Serialize sparse samples (only-changed tokens). This layer's
  `SampleLine` is happy to round-trip a fully-populated or sparse line,
  but the *encoding* (deciding which tokens to emit) is Phase B work.
- Talk to git. None of that is in this layer either.

## Phase B notes (CCRLog → Subsurface mapper)

The mapper at `packages/subsurface_core/lib/sync/subsurface_git/mapper.dart` defaulted on the
following points; flagging them here so Phase D's first push exposes them
quickly if any of them are wrong:

- **Folder timezone**: the mapper formats `Dive.startTime` with UTC
  components (`DateTime.fromMillisecondsSinceEpoch(seconds * 1000,
  isUtc: true)`). The Shearwater binary stores a unix-epoch lexeme without
  a timezone; libdc/Subsurface treat it as the diver's local wall-clock
  time. Decoding it as UTC and emitting UTC components gives back the
  same calendar moment the DC recorded — so the resulting folder name
  matches the diver's wall clock. If a Petrel firmware quirk ever stamps
  a true UTC seconds-since-epoch, the folder name will drift by the
  diver's UTC offset; we'll find out the first time we push a dive whose
  folder name doesn't match what Subsurface Cloud already has.
- **`po2` vs `dc_supplied_ppo2`**: CCRLog stores only the voted PPO2
  (`samples.ppo2Bar`). The mapper emits it as `po2=` (the voted value),
  and uses the per-cell `cellMv*` channels for `sensor1..3`. For
  `dc_supplied_ppo2=` (the cell-averaged value the DC computed before
  voting), we emit the recorded *setpoint* as a proxy on CCR dives — this
  is wrong-ish for OC but acceptable for the v1 round-trip; revisit if
  the diff against an existing Subsurface log shows visible mismatch.
- **`deviceid`**: Subsurface computes its `deviceid` as a libdc-side hash
  of (model + serial). We don't have access to that exact hash, so we
  derive a stable 8-char hex from `sha256("ccrlog:device:$serial")`. This
  is per-CCRLog stable but won't match what Subsurface Cloud already has
  for the same physical computer. Dives pushed by us will have a
  different `deviceid` from dives Subsurface imported directly. For the
  Phase D push, this means the `00-Subsurface` `divecomputerid` line we
  write may collide with an existing one — the orchestrator must
  de-duplicate on `serial` (which is the source of truth), not on
  `deviceid`.
- **Cylinder `description`**: when no `Cylinder` is mapped to a gas mix,
  we synthesise `"<vol>L tank"` (e.g. `"3L tank"`). Subsurface's stock
  cylinder labels have a fancier format (`"3ℓ 232 bar"` per the
  fixtures). When the user has cylinders configured, we use the user's
  label verbatim, which is the right behaviour.
- **`watertemp`**: emitted as the *minimum* (coldest) temperature seen in
  the sample stream, matching the fixture `watertemp 7.0°C` for a dive
  whose mean is ~10°C. If Subsurface actually expects mean-of-samples,
  Phase D's first round-trip will show that.
- **Sample line depth field**: we always emit a depth lexeme on every
  sample, even when unchanged. The fixtures do this too (depth is the
  one positional that's never sparse-skipped); other channels (temp,
  tank pressures, kv tokens) follow the standard sparse-emission rule:
  only when the formatted lexeme differs from the previously-emitted
  one for that channel.
- **Events**: only `gaschange` events are emitted in v1 (on
  `samples.gasMixIndex` transitions). Setpoint changes (`type=20`),
  bookmarks (`type=8`), and other events come later — they're not
  load-bearing for cylinder accounting and the format layer round-trips
  them via `EventLine` already.
- **Salinity**: the Subsurface lexeme is `<density>g/l` with no space
  (e.g. `1000g/l`, `1025g/l`). We emit that form. The corpus also
  contains `watersalinity 1030 g/l` (with space) on some old manual
  dives — we don't synthesise that variant.
- **Site dedup**: site id is `sha256("$latE5:$lonE5").hex.substring(0,
  8)` where `latE5 = (lat * 1e5).round()`. Two annotations whose
  coordinates round to the same `latE5/lonE5` pair get the same id and
  so collapse to one Site file on disk.

## Phase B+ notes (Subsurface → CCRLog read-direction mapper)

The mapper at `packages/subsurface_core/lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart`
is the inverse of the write mapper above. It powers the
"bootstrap-import" path that reads a user's existing Subsurface git repo
and produces CCRLog `Dive` + `SampleSet` + `DiveAnnotation` + per-mix
`ProposedCylinder` bundles. The read direction is *lossier* than the
write direction; the seams below are documented so the orchestrator
(separate work) can choose its tolerance vs strictness policy:

- **Cell mV reverse calibration**: Subsurface stores per-cell PPO2 in bar
  (`sensor1=0.714bar`, 3 decimal places). To recover the source mV we
  invert via the calibration keyvalue: `mV = bar / cal_per_mV`. Petrel
  factory default is `21.00 bar/V` ⇒ `0.021 bar/mV`, so
  `0.714 / 0.021 = 34.0 mV`. Tests allow ±0.5 mV slack to absorb the
  bar-string formatting noise. When the calibration keyvalues are
  absent (older fixtures, OC dives) we fall back to the Petrel default.
- **Setpoint**: Subsurface's `dc_supplied_ppo2=` is the cell-averaged
  PPO2, NOT the setpoint. Real setpoint changes appear as `event` lines
  (`name="setpoint change"` / `name="SP change"`, plus type-11 or
  type-20 depending on Subsurface version — we accept all three forms).
  Without a setpoint event we hold a default of 0.7 bar (Petrel cold-
  start) for the entire dive. The source binary has the real setpoint
  trace; Subsurface drops it.
- **CNS / deco / tts**: emitted sparsely by Subsurface (only on changes).
  Our reconstruction holds the last-seen value forward — same semantic
  as Subsurface's own viewer. Defaults to 0 when never emitted.
- **Status flags**: Subsurface drops the Petrel's status bitfield
  entirely. We always emit `0`. Solenoid-fire analysis requires
  importing from the Petrel binary directly; the Subsurface bootstrap
  path is metadata-only for status.
- **Tank pressure forms**: both `207.946bar:0` (indexed) and `187.951bar`
  (un-indexed) appear. The un-indexed form maps to channel 0; the
  indexed form maps to channel `N`. We allocate `max_index + 1`
  channels per dive.
- **Manual dives**: dives without a `model "..."` line, without a
  `keyvalue "Serial" "..."` line, or with `model "manually added dive"`
  return null — we have no DC identity to anchor a Petrel-shaped
  record. The orchestrator can decide whether to surface these as
  "unmapped legacy" entries or skip silently.
- **Sample interval**: inferred from the time delta between the first
  two sample lines (typically 5s for Petrels, 10s for older firmwares).
  Falls back to 10s for synthetic / single-sample files.
- **`dcDiveNumber`**: Subsurface doesn't store the per-DC dive number;
  it stores its own monotonic `Dive-NNN` counter. We use that counter
  as a stand-in for `generateDiveId`. This means re-importing the same
  dive from the original Petrel binary would produce a *different*
  dive id (the Petrel knows the real `dcDiveNumber`); the orchestrator
  must dedupe on `(dcSerial, startTime)` rather than `id` alone when
  bridging the two import paths.
- **`deviceid`**: not consumed. The libdc-side hash isn't recoverable
  losslessly and we don't need it for the read path.
- **Calibration unit alignment**: parsed `Sensor N calibration [bar / V]`
  values are stored on `Dive.sensorCalibration` as bar-per-mV (i.e.
  divided by 1000). This matches the convention used by the Petrel
  binary parser, so display-time code that does `mV * cal = bar` works
  identically across both import paths. **Verify this alignment
  whenever the Petrel-binary calibration agent makes changes.**
