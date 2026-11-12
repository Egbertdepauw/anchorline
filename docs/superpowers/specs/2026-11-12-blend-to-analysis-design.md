# Blend to analysis: open blends that an analysis closes

Status: design, 2026-11-12, waiting for Egbert's review. Issue #112 (rescoped; see "Non-goals"). One point is marked **provisional, for Egbert to confirm** (a far-off reading).

## Why

On a fill day Egbert blends a **batch** of cylinders, lets them settle, and
analyses them later. Today the Blend and Analyse tabs barely know about each
other:

- The Blend tab keeps one target mix, on one device (`SharedPreferences`
  in `BlendNotifier`).
- The analyzer offers that target as the desired mix for 24 hours, until one
  complete save has used it (`unusedRecentTarget`, `markRecentTargetUsed`).
- A second blend overwrites the first, so in a batch only the last blend is
  remembered.
- Nothing tells him that a cylinder was blended but never analysed and
  labelled.

The goal is a **confirmation step**: every gas that was blended is also
analysed. The app keeps a list of blends that are still waiting for their
analysis, and an analysis closes one.

His real flow, in his words:

1. Enter the desired mix on the Blend tab.
2. If needed, analyse the residual mix and note how many bars are left.
3. Enter the residual mix on the Blend tab.
4. Blend to the Blend tab's recipe and top off with air.
5. Analyse the mix and label it.

## Goals

1. **Open blends.** Finishing a recipe on the Blend tab can save it as an
   **open blend**. Many can be open at once (a batch). They sync across the
   diver's devices (CLAUDE.md principle 7).
2. **An analysis closes an open blend.** Saving an analysis whose reading
   matches an open blend closes that blend and links the two.
3. **A visible "not yet analysed" count**, so a forgotten cylinder is
   obvious.
4. **Settling shown, never enforced.** Each open blend shows how long ago it
   was blended, as a colour against a settle-time setting.
5. **A role per blend, guessed and correctable**, which travels into the
   analysis and sets how loud a mismatch warning is.
6. **A warning on mismatch that never blocks.** A deco or bailout gas with
   more O₂ than planned gets a loud warning in MOD terms; smaller cases get a
   mild note.
7. **The residual analysis feeds the Blend tab.** It is saved in the log like
   any analysis and fills the Blend tab's residual mix and pressure.

## Non-goals

- Offering analysed gases in the **planner** or in a **dive's gas list**.
  This was the other half of the original #112. It's not part of this flow
  and is left for later.
- **CSV export.** It already exists (`lib/data/models/gas_analysis_csv.dart`,
  the Log tab's export).
- **Tracking cylinder identity.** Egbert identifies bottles by look, and by a
  strip of duct tape with the desired mix ("Tx18/45") when he has several of
  the same. The mix is the name. An open blend does not need a cylinder. The
  existing optional cylinder link on an analysis stays as it is.
- **Blocking anything.** No step is refused because of settling or a
  mismatch.

## Anti-goals

- An analysis that matches no open blend must still save exactly as it does
  today. The new flow is optional, not a gate.
- Older app builds that sync the same account must keep working. They must
  not crash or mislabel rows because of new role values or a new table (see
  "Constraints").
- No nagging about blends the diver deliberately gave up on. A cylinder
  that was vented or never used needs a way out (see "Dismissing").

## How it works

### Open blends

- The Blend tab gets an action to save the current recipe as an open blend.
  *Builder's choice:* its label ("Blended" or similar) and where it sits.
  The open blend records:
  - the target mix and target pressure
  - the residual mix and residual pressure
  - the top-off gas
  - the water capacity
  - the role (below)
  - who blended it (the existing "analysed by" style name field, if one is
    set) and when
- After saving, the Blend tab is free for the next cylinder of the batch. The
  existing "remember the last target on this device" behaviour may stay for
  the inputs, but it **no longer drives** what the analyzer offers. Open
  blends replace the single 24-hour target in that role.
- Open blends are a new synced entity with the full sync metadata
  (`created_at`, `updated_at`, `deleted_at`, `version`, `sync_status`;
  principle 6), `owner_id`, and a nullable link to the analysis that closed
  it.

### The open-blends list

- It's visible on the Gas tab. *Builder's choice:* a section on Analyse, on
  Blend, or both. The "not yet analysed" count must be visible without
  opening anything.
- Each row shows the target mix by its usual name (`gas_naming.dart`), the
  role, the target pressure and the time since blending.
- **Settling colour**, against a new setting **settle time** in minutes
  (Settings → Gas; *default 60 minutes, my call*):
  - **red:** less than half the settle time has passed
  - **orange:** between half and all of it
  - **green:** the full settle time has passed, ready to analyse

  The colour is informational only. Analysing a red blend is allowed.

### Closing a blend by analysing

- When the diver saves an analysis, the app looks for an open blend whose
  target mix grades **match or orange** against the reading. This is the same
  grading the analyzer already uses for its automatic desired-mix pick
  (`standard_mix_pick.dart`, `gradeMix`).
- The analyzer's automatic desired-mix pick should prefer open blends over
  standard mixes, the way it prefers the Blend target today.
- **Two or more open blends of the same mix are interchangeable.** The
  analysis closes the **oldest** of them. Of different candidate mixes, the
  closest grade wins (match before orange, then the smaller O₂ difference,
  as in the existing pick).
- The diver can see which open blend the save will close, and can choose a
  different one or none before saving. *Builder's choice:* how, within the
  Analyse tab's height budget.
- **A far-off reading: provisional, for Egbert to confirm.** The automatic
  close only happens within orange. A seriously rich deco gas, say 55%
  against a 50% target, would otherwise match nothing, close nothing and
  get no loud warning: the most dangerous case would get the weakest
  signal. So:
  - The "choose a different one" list shows **every** open blend: the match
    and orange candidates first, then the rest.
  - Picking a red or hard blend by hand **closes it** and shows the loud
    warning of its role, like any other mismatch.
  - A reading that matches no open blend, while an open blend grades red or
    hard against it, saves with a note: "No open blend matches. Nearest:
    Tx50 (red)."
- Closing:
  - sets the blend's link to the analysis
  - gives the analysis the blend's target mix as its desired mix, and the
    blend's role
  - leaves the analysis itself unchanged otherwise
- A reading that matches no open blend saves as a normal analysis and closes
  nothing.
- **Every save path matches, including the SOLO's OK button** (bridge or USB
  "Log on OK"). *My call:*
  - A live OK capture that saves complete and prints its label at once (a
    name set, grade match or orange) matches and closes an open blend at
    capture. The label then prints with the blend's target and role. The
    matching has to run where `recordToAnalysis` / `LogOnOkSetup` pick the
    desired mix today, which replaces their use of the single Blend target.
  - Today that path takes its role from `gasRoleForMix`, a 30% rule. A
    matched blend's role now wins over it.
  - A capture that lands as `needsSignoff` closes its blend at sign-off,
    with the same matching.

### What "open" means

*My call.* A blend is **open** while it is neither dismissed nor linked to a
**live** analysis. It's derived from the link, not a separate flag.

- If the closing analysis is deleted (a synced soft delete), the blend is
  open again. The cylinder isn't confirmed any more.
- Editing the closing analysis later (its desired mix or role) keeps the
  link. The diver corrected the analysis, not the blend.
- Analyses saved by an older build, or on a device that didn't close the
  blend, never close a blend after the fact. There's no reconciliation
  pass. Dismissing is the way out.

### Dismissing

- An open blend can be dismissed without an analysis, for a cylinder that
  was vented or abandoned. Dismissing is a soft delete, so it syncs like any
  delete. A dismissed blend leaves the count.

### Roles

- **Four roles:** diluent, bailout, backgas (OC) and deco. Today's `GasRole`
  has only `bailout` and `diluent`, so it gains `backgas` and `deco`.
- **The Blend tab guesses the role** for each new blend:
  1. O₂ above 32% → bailout. A gas above 32% O₂ is never a suitable diluent.
  2. Otherwise, a water capacity at or under the new setting **diluent
     cylinder size** (Settings → Gas, litres, *default 3 L*) → diluent. GUE
     divers use 7 L diluent sets and would set 7.
  3. Otherwise → bailout.

  The guess only ever picks diluent or bailout, which covers what Egbert
  fills. Backgas and deco are chosen by hand.
- The role shows as a tappable chip on the Blend tab, with the reason (for
  example "Diluent (3 L)"). Tapping it lets the diver pick any of the four,
  for instance for a third-party fill such as someone's GUE set. The override
  applies to **this blend only**; the next blend guesses again.
- The role carries into the analysis that closes the blend. An analysis with
  no blend keeps today's behaviour: its role comes from the linked cylinder
  (`gasRoleForCylinderRole`) or the manual diluent/bailout choice. That
  choice offers the four roles.
- Bailout and deco are interchangeable in practice: a bailout gas can be a
  deco gas and the reverse. They differ only in name. Neither gets
  behaviour the other lacks.

### Mismatch warning

When an analysis closes a blend, or carries a desired mix in general, its
reading is compared with the target:

| Role | O₂ higher than target | O₂ lower than target |
|---|---|---|
| bailout, deco, backgas | **loud** warning | mild note |
| diluent | mild note | mild note |

- The **loud** warning states the consequence in MOD terms, with **one**
  PPO₂: the one the cylinder label prints the MOD at (`cylinder_label.dart`).
  That's 1.6, or 1.4 for mixes under 50% O₂ when that setting is on. *My
  call:* it keeps the warning consistent with the label on the bottle.
  For example: "O₂ 52% instead of 50%: MOD at 1.6 is 21 m, not 22 m."
- The **mild** note just states both mixes ("analysed 20.4/33, target
  21/35").
- *Why backgas is loud (my call):* an OC bottom mix that's a few percent rich
  gives a higher PPO₂ at depth than planned, just like a rich deco gas.
- *Why diluent is mild:* on a CCR the setpoint governs the loop's PPO₂, so a
  small diluent error barely matters.
- *Builder's choice:* the threshold below which no note shows at all. Use the
  existing grade bands: a "match" shows nothing.
- Nothing blocks. The diver decides whether to reblend.

### The residual analysis

- When analysing the residual gas before a blend, the diver marks the
  analysis as a **residual**. *Builder's choice:* how, for instance an
  "Analysing residual" toggle on the Analyse tab.
- A residual analysis:
  - is saved in the log like any analysis
  - is shown as residual there
  - never closes an open blend
  - is not offered for a label print
- Saving it fills the Blend tab's residual mix and residual pressure with the
  reading and the analysis's fill pressure, if one was entered. The diver
  can still edit them.

## Constraints

- **CLAUDE.md principle 7, sync:**
  - The open-blends table needs a Supabase migration with RLS and the explicit
    `grant ... to authenticated, service_role` (`lint_migrations.sh`), the
    PowerSync client schema, a line in `infra/powersync-sync-rules.yaml`, the
    cloud wipe list and the sign-in `owner_id` backfill. Follow what #186 did
    for `user_acknowledgements`.
  - Egbert deploys the migration and the sync rules before a build with this
    ships.
- **The migration number** is the next free one, `0025`, unless another
  migration lands first.
- **Older builds:**
  - `GasRole.fromDb` maps unknown strings to bailout, so an old build reads
    `backgas` and `deco` as bailout. That's acceptable.
  - The new residual marker must be a column or value an old build ignores.
  - The old build's single-target behaviour keeps working on its own device.
- **Labels:** `cylinder_label.dart` branches on diluent vs not. Backgas and
  deco print like bailout unless the builder finds a reason otherwise. A
  residual analysis prints no label.
- **Settings** (settle time, diluent cylinder size) are device-local
  `SharedPreferences`, like every other setting in `SettingsNotifier` today.
  *My call:* settings don't sync anywhere in the app yet, and a synced
  settings table is its own project. *Builder's choice:* where under
  Settings → Gas.
- **Repo conventions:**
  - Metric in the database.
  - No `dart format` over existing files.
  - Tests for the matching rules (oldest-of-equal, no match, residual never
    closes, sign-off closes) and the role guess (32% rule, size rule,
    override is per blend).
- The existing analyzer tests around `unusedRecentTarget` change meaning.
  Replace them with open-blend equivalents rather than deleting the cases.

## Left to the builder

- Wording and placement of the "save as open blend" action, the open-blends
  list, the residual toggle and the which-blend-closes indicator.
- The table and column names.
- Whether the Blend tab's device-local "last target" memory stays, as long
  as it no longer drives the analyzer's offer.
- How a closed blend shows in the log, if at all, beyond the analysis
  carrying the blend's target and role.
