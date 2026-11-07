# Gas tabs and Settings redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Blend tab, gas analyzer, analysis log and Settings in the dive screen's language. They become one "Gas" destination with Blend | Analyse | Log tabs, and Settings becomes five tabs. The Analyse tab fits one phone screen, fills in the save form for the usual case, and turns Log on OK into a start/stop control.

**Architecture:**
1. Pure-Dart rules first: the nearest standard mix, the role rule, and the per-press automatic pick inside `recordToAnalysis`.
2. Then small shared UI pieces: `HeroStat`, `TabTopBar`, `ValueStepper`.
3. The analyzer session (controller, transport choice, Log on OK logger, wakelock) moves out of the screen into a shell-owned `AnalyzerSession`, so it survives tab switches.
4. The save card's state moves into an `AnalysisSaveController`, so the form (in the scroll view) and the action bar (pinned) can be two widgets.
5. Each page is then rebuilt on those pieces.

**Tech Stack:** Flutter / Dart, SharedPreferences (device-only settings), the existing `GasAnalysesDaoLike`, `flutter_test` widget and unit tests.

**Spec:** `docs/superpowers/specs/2026-11-06-gas-and-settings-redesign-design.md`, with mockups in `docs/superpowers/specs/2026-11-06-gas-and-settings-redesign/` (`gas-tabs.png`, `analyzer-states.png`, `settings-tabs.png`). Read the spec section each task names before starting it. Where this plan and the spec disagree, the spec wins; say so in the task report.

## Global Constraints

- **Mix names:** `gasMixName` (whole numbers) everywhere. Only the Analyse tab's live readout uses `gasMixNameDecimal`. Measured O₂ / He values may show one decimal.
- **MOD rows** are judged against the selected desired mix: `limitDepthMeters(o2, p, desiredO2Percent:)`, with `desiredO2Percent: null` on a hard mismatch, as today.
- **Device-only SharedPreferences** (never synced): MOD ppO₂s, "Use 1.4", label printer, Log on OK, print on OK, **Your initials**, **Fill pressure starts at**, and the **Blend target's used mark**.
- **English in git.** Never run `dart format` on a whole file; main isn't format-clean (about 1000 lines of churn). Match the surrounding style by hand.
- **CCR setpoints** are only 0.7 and 1.3. No new text, default or example may suggest others.
- **Log on OK rules as built in `recordToAnalysis` stay:**
  - OK is the trigger, and room air isn't logged.
  - An OK press doesn't wait for STABLE.
  - It prints when there is a name and the desired mix is none, match or orange.
  - No name, a red or hard mismatch, or a late record flags the entry "needs sign-off".
  - A flagged entry gets no label.
- **An automatic desired-mix pick only happens when it grades match or orange** (`gradeMix`), never red or hard.
- **Colours** come only from `context.palette`, `SafetyColors` and `DataColors`; all six themes must keep working.
- **Touch targets:** buttons and steppers at least 44 pt; chips at least 32 pt.
- **Test keys:** keep every existing test key whose element survives (listed per task). New keys are named in each task.
- **Every task ends** with `flutter analyze` clean and the task's tests passing. The last task runs the whole suite.

## Review Focus

1. **The reading the auto pick sees.** The reading changes between the frame that showed the chip and the save, or between an OK press and its delayed handling. The pick must come from the exact reading being saved (the snapshot on a manual save, the held line on an OK press), never from a later live line. Tests: Task 2 (held line) and Task 9 (snapshot).
2. **Log on OK while you are elsewhere in the app.** With logging running, the diver switches to the Log tab or to Dives and presses OK. The press must still be saved, and the logger must not be rebuilt or lost. Test: Task 6.
3. **Small phones and large text.** At 320 × 568 pt or text scale 1.3, the 4-column planning grid, the two-column fields and the action bar must not throw RenderFlex overflows; they wrap or scroll. Tests: Tasks 7 and 9.
4. **Other themes.** Any colour that isn't a palette token (for example the steel bailout edge in the Log tab) breaks in Ethereal, Catppuccin and the rest. Every restyled page must render in all six themes without exceptions. Tests: Tasks 7 and 12.
5. **Upgrading with an old remembered name.** A device has `analyzer_analysed_by` set and no `your_initials`. After the update, "Analysed by" must still start with that name, and an existing `your_initials` is never overwritten. Test: Task 3.

---

### Task 1: Nearest standard mix and the role rule (pure Dart)

Spec: §4.3.

**Files:**
- Create: `lib/analysis/standard_mix_pick.dart`
- Test: `test/analysis/standard_mix_pick_test.dart`

**Interfaces:**
- Consumes:
  - `gradeMix`, `MixMatchLevel` (`lib/analysis/mix_match.dart`)
  - `DesiredMix`, `GasRole`, `gasRoleForCylinderRole` (`lib/data/models/gas_analysis.dart`)
- Produces:
  - `const List<DesiredMix> kStandardMixes`, in this order: Air (21/0), EAN32, EAN50, O2 (100/0), Tx30/30, Tx21/35, Tx18/45, Tx15/55, Tx12/65, Tx10/70, Tx35/25.
  - `enum MixPickSource { blendTarget, standard }`
  - `typedef MixPick = ({DesiredMix mix, MixPickSource source, MixMatchLevel level});`
  - `MixPick? pickDesiredMix({required double o2Percent, required double hePercent, DesiredMix? blendTarget})`
  - `const double kBailoutRoleAboveO2Percent = 30;`
  - `GasRole gasRoleForMix(double o2Percent)`
  - `GasRole resolveGasRole({GasRole? tapped, String? cylinderRole, required double o2PercentForRule})`

- [ ] **Step 1: Write the failing tests**

```dart
// pickDesiredMix
test('20.4/33.5 picks Tx21/35 as a match', () {
  final p = pickDesiredMix(o2Percent: 20.4, hePercent: 33.5)!;
  expect(p.mix, const DesiredMix(21, 35));
  expect(p.source, MixPickSource.standard);
  expect(p.level, MixMatchLevel.match);
});
test('49.2/0.3 picks EAN50', () => expect(pickDesiredMix(o2Percent: 49.2, hePercent: 0.3)!.mix, const DesiredMix(50, 0)));
test('19.1/43.0 picks Tx18/45 as orange', () {
  final p = pickDesiredMix(o2Percent: 19.1, hePercent: 43.0)!;
  expect(p.mix, const DesiredMix(18, 45));
  expect(p.level, MixMatchLevel.orange);
});
test('20.9/0.4 picks Air', () => expect(pickDesiredMix(o2Percent: 20.9, hePercent: 0.4)!.mix, const DesiredMix(21, 0)));
test('23.0/30.0 picks nothing (Tx21/35 is red)', () => expect(pickDesiredMix(o2Percent: 23.0, hePercent: 30.0), isNull));
test('40.0/0.0 picks nothing', () => expect(pickDesiredMix(o2Percent: 40.0, hePercent: 0.0), isNull));
test('a Blend target within orange beats a standard mix', () {
  final p = pickDesiredMix(o2Percent: 19.6, hePercent: 40.2, blendTarget: const DesiredMix(19, 40))!;
  expect(p.mix, const DesiredMix(19, 40));
  expect(p.source, MixPickSource.blendTarget);
});
test('a Blend target that grades red is ignored', () {
  final p = pickDesiredMix(o2Percent: 20.6, hePercent: 33.8, blendTarget: const DesiredMix(18, 45))!;
  expect(p.mix, const DesiredMix(21, 35));
  expect(p.source, MixPickSource.standard);
});
test('no result is ever red or hard', () {
  for (var o2 = 5.0; o2 <= 100; o2 += 0.7) {
    for (var he = 0.0; he + o2 <= 100; he += 1.3) {
      final p = pickDesiredMix(o2Percent: o2, hePercent: he);
      if (p != null) expect(p.level, anyOf(MixMatchLevel.match, MixMatchLevel.orange));
    }
  }
});
// role rule
test('gasRoleForMix: 30.0 is diluent, 30.1 is bailout', () {
  expect(gasRoleForMix(30.0), GasRole.diluent);
  expect(gasRoleForMix(30.1), GasRole.bailout);
  expect(gasRoleForMix(21), GasRole.diluent);
  expect(gasRoleForMix(100), GasRole.bailout);
});
test('resolveGasRole: a tapped role wins over cylinder and mix', () =>
    expect(resolveGasRole(tapped: GasRole.diluent, cylinderRole: CylinderRole.oxygen, o2PercentForRule: 50), GasRole.diluent));
test('resolveGasRole: a known cylinder role wins over the mix', () =>
    expect(resolveGasRole(cylinderRole: CylinderRole.diluent, o2PercentForRule: 50), GasRole.diluent));
test('resolveGasRole: a cylinder without a role follows the mix', () =>
    expect(resolveGasRole(cylinderRole: null, o2PercentForRule: 50), GasRole.bailout));
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `flutter test test/analysis/standard_mix_pick_test.dart`. Expected: compile errors (the symbols don't exist yet).

- [ ] **Step 3: Implement `lib/analysis/standard_mix_pick.dart`**

- **Grading:** grade each candidate with `gradeMix`, and keep only `match` or `orange`.
- **Candidate order:** the Blend target first (when it passes), then the best standard mix.
- **Ranking among standard mixes:** match beats orange; then the smaller `o2Off`; then the smaller `heOff`.
- **Role resolution:** `resolveGasRole` returns:
  1. `tapped`, if set
  2. else `gasRoleForCylinderRole(cylinderRole)` when `cylinderRole != null`
  3. else `gasRoleForMix(o2PercentForRule)`

- [ ] **Step 4: Run the tests and see them pass**

Run: `flutter test test/analysis/standard_mix_pick_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/analysis/standard_mix_pick.dart test/analysis/standard_mix_pick_test.dart
git commit -m "feat(analysis): nearest standard mix and the role rule"
```

---

### Task 2: Log on OK picks a mix and a role per press

Spec: §4.3 ("Log on OK", "The role follows the mix"), Global Constraints.

**Files:**
- Modify: `lib/analyzer/bridge/record_to_analysis.dart` (`LogOnOkSetup`, step 6 of `recordToAnalysis`)
- Test: `test/analyzer/bridge/record_to_analysis_test.dart`

**Interfaces:**
- Consumes: Task 1's `pickDesiredMix` and `gasRoleForMix`.
- Produces: `LogOnOkSetup` changes:
  - Adds `final bool autoPickMix` (default `false`): true while the diver hasn't picked or cleared a mix.
  - Adds `final DesiredMix? blendTarget` (default `null`): the recent Blend target that isn't used up.
  - `final GasRole? gasRole` becomes nullable (default `null`). It holds the tapped role or a picked cylinder's known role; null means "follow the mix".

  The other fields don't change.

- [ ] **Step 1: Write the failing tests** (live record, named, `printOnOk` and `printerConfigured` true, unless stated otherwise)

```dart
test('auto pick comes from the held line', () {
  final out = decide(held: '19.1 43.0', setup: base.copyWith(autoPickMix: true)) as SaveRecord;
  expect(out.analysis.desiredMix, const DesiredMix(18, 45));
  expect(out.printLabel, isTrue);
});
test('auto pick never takes a red mix; the label then names the analysed gas', () {
  final out = decide(held: '23.0 30.0', setup: base.copyWith(autoPickMix: true)) as SaveRecord;
  expect(out.analysis.desiredMix, isNull);
  expect(out.printLabel, isTrue);
});
test('a diver pick wins over auto pick (and a red one still blocks the print)', () {
  final out = decide(held: '19.1 43.0', setup: base.copyWith(autoPickMix: true, desiredMix: const DesiredMix(21, 35))) as SaveRecord;
  expect(out.analysis.desiredMix, const DesiredMix(21, 35));
  expect(out.printLabel, isFalse);
  expect(out.analysis.needsSignoff, isTrue);
});
test('the Blend target is used when it grades within orange', () {
  final out = decide(held: '19.6 40.2', setup: base.copyWith(autoPickMix: true, blendTarget: const DesiredMix(19, 40))) as SaveRecord;
  expect(out.analysis.desiredMix, const DesiredMix(19, 40));
});
test('the role follows the picked mix', () {
  expect((decide(held: '49.2 0.3', setup: base.copyWith(autoPickMix: true)) as SaveRecord).analysis.gasRole, GasRole.bailout);
  expect((decide(held: '20.6 33.8', setup: base.copyWith(autoPickMix: true)) as SaveRecord).analysis.gasRole, GasRole.diluent);
});
test('with no desired mix the role follows the reading', () =>
    expect((decide(held: '40.0 0.0', setup: base.copyWith(autoPickMix: true)) as SaveRecord).analysis.gasRole, GasRole.bailout));
test('an explicit role wins', () =>
    expect((decide(held: '49.2 0.3', setup: base.copyWith(autoPickMix: true, gasRole: GasRole.diluent)) as SaveRecord).analysis.gasRole, GasRole.diluent));
test('a late record still gets no desired mix and bailout', () {
  final out = decide(held: '20.6 33.8', late: true, setup: base.copyWith(autoPickMix: true)) as SaveRecord;
  expect(out.analysis.desiredMix, isNull);
  expect(out.analysis.gasRole, GasRole.bailout);
});
```

- `decide` is a local helper that builds a `BridgeRecord` from a held SOLO line and calls `recordToAnalysis`. Follow how the existing tests in this file build records and lines.
- Add `copyWith` to `LogOnOkSetup` only if the file's tests need it; a test-local builder is fine.

- [ ] **Step 2: Run the tests and see them fail**

Run: `flutter test test/analyzer/bridge/record_to_analysis_test.dart`. Expected: the new tests fail. The existing tests still compile, because the changed field stays a named parameter.

- [ ] **Step 3: Implement step 6 for a live record**

```dart
final desiredMix = live
    ? (setup.desiredMix ??
        (setup.autoPickMix
            ? pickDesiredMix(o2Percent: o2, hePercent: he, blendTarget: setup.blendTarget)?.mix
            : null))
    : null;
final gasRole = live
    ? (setup.gasRole ?? gasRoleForMix(desiredMix?.o2Percent.toDouble() ?? o2))
    : GasRole.bailout;
```

Update the doc comments for steps 6–8 and `LogOnOkSetup`. Leave steps 7–11 alone.

- [ ] **Step 4: Run this file's tests and the logger's tests**

Run: `flutter test test/analyzer/bridge/record_to_analysis_test.dart test/analyzer/usb_ok_logger_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/analyzer/bridge/record_to_analysis.dart test/analyzer/bridge/record_to_analysis_test.dart
git commit -m "feat(analyzer): Log on OK picks the nearest mix and role per press"
```

---

### Task 3: Device settings (initials, fill pressure start) and the Blend target's used mark

Spec: §4.2, §4.3 ("Used up"), §6 (new settings).

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`, `lib/ui/notifiers/blend_notifier.dart`
- Test: `test/ui/notifiers/settings_notifier_test.dart`, `test/ui/notifiers/blend_notifier_target_test.dart`

**Interfaces:**
- Produces, on `SettingsNotifier`:
  - `String? get yourInitials` and `Future<void> setYourInitials(String? v)`: trimmed; blank means null; key `your_initials`.
  - On `load()`: when `your_initials` is absent and `analyzer_analysed_by` is present, `yourInitials` takes that value and writes `your_initials`.
  - `static const double kDefaultFillPressureStartBar = 230;`
  - `double get analyzerFillPressureStartBar` and `Future<void> setAnalyzerFillPressureStartBar(double bar)`: key `analyzer_fill_pressure_start_bar`. A value that `parseFillPressure` wouldn't accept (not finite, or below 0) is ignored.
  - Keep `analyzerAnalysedBy` / `setAnalyzerAnalysedBy` for now; Task 9 removes them.
- Produces, on `BlendNotifier`:
  - `DesiredMix? unusedRecentTarget()`: `recentTarget()`, unless it is marked used.
  - `Future<void> markRecentTargetUsed()`: key `blend_target_used`.
  - Every `_markEdited()` clears the mark (stores `false`).
  - `loadTarget()` restores the mark, unless the diver edited something this session.
  - `recentTarget()` itself is unchanged; the chips still offer a used target.

- [ ] **Step 1: Write the failing tests**

```dart
test('your initials migrate from analyzer_analysed_by when unset', () async {
  SharedPreferences.setMockInitialValues({'analyzer_analysed_by': 'EdP'});
  final s = SettingsNotifier(); await s.load();
  expect(s.yourInitials, 'EdP');
  expect((await SharedPreferences.getInstance()).getString('your_initials'), 'EdP');
});
test('an existing your_initials is not overwritten', () async {
  SharedPreferences.setMockInitialValues({'analyzer_analysed_by': 'EdP', 'your_initials': 'JS'});
  final s = SettingsNotifier(); await s.load();
  expect(s.yourInitials, 'JS');
});
test('setYourInitials trims and a blank clears', () async { /* ' EdP ' -> 'EdP'; '  ' -> null */ });
test('fill pressure start defaults to 230 and persists', () async { /* default 230.0; set 200 -> reload -> 200.0; set -5 -> stays 200.0 */ });
// blend
test('a used target is hidden from unusedRecentTarget, not from recentTarget', () async { /* edit -> markRecentTargetUsed -> unusedRecentTarget null, recentTarget (21,35) */ });
test('any Blend edit clears the used mark', () async { /* markRecentTargetUsed -> setCurrentPressure(50) -> unusedRecentTarget non-null */ });
test('the used mark survives a reload', () async { /* mark used -> new notifier.loadTarget() -> unusedRecentTarget null */ });
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart test/ui/notifiers/blend_notifier_target_test.dart`.

- [ ] **Step 3: Implement both notifiers**

Follow the existing setter pattern: return early when unchanged, `notifyListeners()`, then write prefs.

- [ ] **Step 4: Run the tests and see them pass** (same command)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/settings_notifier.dart lib/ui/notifiers/blend_notifier.dart test/ui/notifiers/settings_notifier_test.dart test/ui/notifiers/blend_notifier_target_test.dart
git commit -m "feat(settings): your initials, fill pressure start, Blend target used mark"
```

---

### Task 4: Shared pieces: HeroStat, TabTopBar, ValueStepper

Spec: §1 (top row), §2.

**Files:**
- Create:
  - `lib/ui/components/hero_stat.dart`
  - `lib/ui/components/tab_top_bar.dart`
  - `lib/ui/components/value_stepper.dart`
- Modify: `lib/ui/screens/dive_detail_screen.dart` (use `HeroStat`, delete `_HeroStat`)
- Test:
  - `test/ui/components/hero_stat_test.dart`
  - `test/ui/components/tab_top_bar_test.dart`
  - `test/ui/components/value_stepper_test.dart`

**Interfaces:**
- Produces:
  - `HeroStat({Key? key, required String value, String? unit, required String label, Color? valueColor, double valueSize = 22, bool centered = false, Key? valueKey})`
    - The look of today's `_HeroStat`: value in `AppTypography.readoutLg` at `valueSize`; unit 12 pt mono in `textSecondary`; label 10 pt, letter-spacing 1.2, w600, `textSecondary`.
    - `valueKey` goes on the value `Text`.
  - `HeroStatRow({Key? key, required List<Widget> children})`: `Expanded` children with a 25-wide `VerticalDivider` in `palette.surfaceBezel` between them, inside `IntrinsicHeight`.
  - `TabTopBar({Key? key, required List<Widget> tabs, required VoidCallback onHome})`, implementing `PreferredSizeWidget` with `preferredSize.height == 56`. It contains, in order:
    - a 44 × 44 tap target keyed `tab-top-bar-home`, holding `AnchorlineLogo(mark: AnchorlineMark.icon, size: 24)`, which calls `onHome`
    - a 1 px divider in `surfaceRaised`
    - `Expanded(TabBar(tabs: tabs))`, driven by the enclosing `DefaultTabController`
  - `ValueStepper({Key? key, required int value, required int min, required int max, int step = 1, String? unit, required String keyPrefix, required ValueChanged<int> onChanged})`
    - Keys: `'$keyPrefix-dec'`, `'$keyPrefix-value'`, `'$keyPrefix-inc'`.
    - A button that would pass a limit is disabled.
    - 44 pt targets.

- [ ] **Step 1: Write the failing tests**
  - `HeroStat` shows value, unit and label.
  - `HeroStatRow` puts n − 1 `VerticalDivider`s between n stats.
  - `TabTopBar`:
    - tapping `tab-top-bar-home` calls `onHome` once
    - the tab labels render
    - `preferredSize.height == 56`
  - `ValueStepper`:
    - `+` from 20 calls `onChanged(21)`
    - at `max` the `inc` button's `onPressed` is null; at `min` the `dec` button's is null

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/components/`.

- [ ] **Step 3: Implement the three components; switch the dive screen to `HeroStat`** (no visual change there).

- [ ] **Step 4: Run them and see them pass, plus the dive screen tests**

Run: `flutter test test/ui/components/ test/ui/screens/` (the dive detail tests must still pass).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/components/ lib/ui/screens/dive_detail_screen.dart test/ui/components/
git commit -m "feat(ui): HeroStat, TabTopBar and ValueStepper components"
```

---

### Task 5: AnalyzerSession: the analyzer outlives its screen (no visual change)

Spec: §1 ("Analyzer session lifetime").

**Files:**
- Create:
  - `lib/analyzer/transport/analyzer_transport_options.dart`: move `AnalyzerTransportOption` and `defaultAnalyzerTransportOptions` here, unchanged.
  - `lib/ui/notifiers/analyzer_session.dart`
- Modify:
  - `lib/ui/screens/analyzer_screen.dart`:
    - Take a session.
    - Re-export the moved option types with `export '../../analyzer/transport/analyzer_transport_options.dart';`, so test imports keep working.
    - Move `buildOkLogger`, `analyzerSourceIsDemo` and `_setWakelock` into the session file.
  - `lib/ui/app_shell.dart`: create the session in `initState`, dispose it in `dispose`, and pass it to `BlendScreen`.
  - `lib/ui/screens/blend_screen.dart`: pass the session on to the pushed `AnalyzerScreen`.
- Test:
  - Create `test/ui/notifiers/analyzer_session_test.dart`.
  - Modify the `test/ui/screens/analyzer_*` files, constructors only.

**Interfaces:**
- Produces:

```dart
class AnalyzerSession extends ChangeNotifier {
  AnalyzerSession({
    required SettingsNotifier settings,
    GasAnalysesDaoLike? analysesDao,
    LabelPrintService? labelPrinting,
    AnalyzerController? controller,                       // tests
    List<AnalyzerTransportOption>? transportOptions,      // tests
    UsbOkLogger Function()? okLoggerFactory,              // tests
    Future<void> Function(bool awake)? keepAwake,         // tests
  });
  AnalyzerController get controller;
  List<AnalyzerTransportOption> get options;
  int get selected;
  void select(int index);                    // ignored while controller.isBusy
  bool? get sessionIsDemo;
  bool get sourceIsDemo;                     // analyzerSourceIsDemo(...)
  UsbOkLogger? get okLogger;                 // non-null while Log on OK runs
  bool get okRunning;                        // okLogger != null
  bool get held;                             // okRunning && controller.hasHadData && controller.noDataHint
  Future<void> connectSelected(BuildContext context); // option.choose ?? option.create
  Future<void> disconnect();
}
```

- `AnalyzerSession` notifies on controller and settings changes.
- Its logger rules are exactly today's `_okWanted`, `_syncOkLogger` and `_stopOkLogger`.
- `AnalyzerScreen` gains `required AnalyzerSession session` and loses `controller`, `transportOptions`, `okLoggerFactory` and `keepAwake`.

- [ ] **Step 1: Write the failing session tests**

Move today's logger lifecycle tests from `analyzer_log_on_ok_test.dart` that exercise screen state with no UI:
- The logger exists only while Log on OK is on, a non-demo session is connected, and there is a DAO.
- The wakelock is asked for when the logger starts and released when it stops.
- A new transport rebuilds the logger.

Add one more:

```dart
test('the session stays connected when no screen is showing it', () async {
  final s = AnalyzerSession(settings: settings, transportOptions: [fakeOption]);
  await s.connectSelected(fakeContext); // or a choose-less option + test helper
  expect(s.controller.isConnected, isTrue);
});
```

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/notifiers/analyzer_session_test.dart`.

- [ ] **Step 3: Implement the session; switch the screen, Blend and the shell to it.** The screen's behaviour and layout don't change.

- [ ] **Step 4: Run the analyzer and session tests**

Run: `flutter test test/ui/notifiers/analyzer_session_test.dart test/ui/screens/analyzer_log_on_ok_test.dart test/ui/screens/analyzer_save_analysis_test.dart test/ui/screens/analyzer_screen_test.dart test/ui/screens/analyzer_transport_note_test.dart test/ui/screens/blend_screen_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/analyzer/transport/analyzer_transport_options.dart lib/ui/notifiers/analyzer_session.dart lib/ui/screens/analyzer_screen.dart lib/ui/screens/blend_screen.dart lib/ui/app_shell.dart test/ui/notifiers/analyzer_session_test.dart test/ui/screens/
git commit -m "refactor(analyzer): AnalyzerSession owns the connection and Log on OK"
```

---

### Task 6: The Gas destination: Blend | Analyse | Log

Spec: §1.

**Files:**
- Create: `lib/ui/screens/gas_screen.dart`
- Modify:
  - `lib/ui/app_shell.dart`:
    - The nav label "Blend" becomes "Gas". Use `gasNavItem(...)`.
    - The shell's `appBar` is `null` when `_currentIndex` is the Gas index (2) or the Settings index (5).
    - Pass `onHome: _goHome` to `GasScreen`.
  - `lib/ui/screens/blend_screen.dart`: no `Scaffold` and no `AppBar` any more (it is a tab body), and the "Analyze gas" button goes.
  - `lib/ui/screens/analyzer_screen.dart`: no `AppBar`; the "Analysis log" button goes. For now `_StatusIndicator` moves to the top of the body; Task 7 replaces it.
  - `lib/ui/screens/gas_analysis_log_screen.dart`: add `final bool embedded` (default `false`).
    - Embedded: no `AppBar`, and the Export button sits in a row at the top of the list. It keeps the key `analysis-log-export`.
    - Not embedded (the Equipment cylinder screen): unchanged.
- Test:
  - Create `test/ui/screens/gas_screen_test.dart`.
  - Modify `test/ui/screens/blend_screen_test.dart`: drop the "Analyze gas" test.

**Interfaces:**
- Consumes: Task 4's `TabTopBar`; Task 5's `AnalyzerSession`.
- Produces:
  - `GasScreen({Key? key, required BlendNotifier blend, required SettingsNotifier settings, required AnalyzerSession session, GasAnalysesDaoLike? analysesDao, LabelPrintService? labelPrinting, required VoidCallback onHome})`
    - Three tabs, each with icon + label, keyed `gas-tab-blend`, `gas-tab-analyse` and `gas-tab-log`. The Log tab uses `Icons.history`; the other two use different icons, and neither uses the science icon.
    - The tab bodies are kept alive (`AutomaticKeepAliveClientMixin` or an `IndexedStack`).
    - A dot keyed `gas-tab-analyse-dot` sits after "Analyse" while `session.controller.isConnected`: `SafetyColors.success`, or `palette.accentPrimary` while `session.okRunning`.
    - Gas opens on Blend; the shell keeps the `GasScreen` state across bottom-nav switches.
  - `BottomNavigationBarItem gasNavItem({required bool connected, required bool okRunning, required bool selected})`
    - Label "Gas", science icon.
    - When connected and not selected, a small dot `Badge` keyed `nav-gas-dot`, in the same colours.
  - `AnalyzerScreen` gains `BlendNotifier? blend` (read live) and loses `blendTarget`.

- [ ] **Step 1: Write the failing tests**
  - `opens on the Blend tab with three tabs`
  - `switching to Log and back keeps the analyzer connected`: connect through the session with a fake transport, tap `gas-tab-log`, then `gas-tab-analyse`; expect `session.controller.isConnected` to be true and the reading still shown.
  - `an OK press while on the Log tab is still saved` (Review Focus 2):
    1. Start Log on OK with a fake logger factory and a manual clock (as in `analyzer_log_on_ok_test.dart`).
    2. Switch to the Log tab.
    3. Drive a hold.
    4. Expect the DAO to have one row, and `session.okLogger` to be the same instance as before.
  - `the anchor calls onHome`
  - `the Analyse dot shows while connected and turns accent while logging`
  - `gasNavItem shows the dot only when connected and not selected`
  - `the embedded log has no app bar but keeps Export`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/gas_screen_test.dart`.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run them and the touched screens' tests**

Run: `flutter test test/ui/screens/`. Expected: all pass. Fix finders that relied on the removed app bars.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/gas_screen.dart lib/ui/app_shell.dart lib/ui/screens/blend_screen.dart lib/ui/screens/analyzer_screen.dart lib/ui/screens/gas_analysis_log_screen.dart test/ui/screens/
git commit -m "feat(gas): one Gas destination with Blend, Analyse and Log tabs"
```

---

### Task 7: Analyse tab: connection strip, readout band, planning tiles, trend, wide layout

Spec: §4.1 items 1–5, §4.5, §4.6. Mockups: `gas-tabs.png` (middle) and `analyzer-states.png`.

**Files:**
- Create (split out of `analyzer_screen.dart`, which is over 1200 lines):
  - `lib/ui/widgets/analyzer/connection_strip.dart`
  - `lib/ui/widgets/analyzer/readout_band.dart` (holds `StabilityPill`; `analyzer_screen.dart` re-exports it)
  - `lib/ui/widgets/analyzer/planning_grid.dart`
  - `lib/ui/widgets/analyzer/trend_row.dart`
- Modify: `lib/ui/screens/analyzer_screen.dart`: layout only. Delete `_Card`, `_CardLabel`, `_GasReadoutCard`, `_MixCard`, `_KvRow`, `_ChartCard` and `_StatusIndicator`.
- Test:
  - Modify `test/ui/screens/analyzer_screen_test.dart` and `test/ui/screens/analyzer_transport_note_test.dart`.
  - Create `test/ui/screens/analyzer_states_test.dart`.

**Interfaces:**
- Consumes: Task 4's `HeroStat` / `HeroStatRow`; Task 5's `AnalyzerSession`.
- Keys kept: `analyzer-o2`, `analyzer-he`, `analyzer-mix`, `analyzer-pill`, `analyzer-mod-<p>` (from `_fmtPpo2`), `analyzer-end`, `analyzer-min-depth`, `analyzer-density`, `analyzer-temp`, `analyzer-baro`, `analyzer-transport`, `analyzer-connect`, `analyzer-error-banner`, `analyzer-no-data-hint`, `analyzer-transport-note`, `analyzer-status` (now the strip's status text).
- Keys new: `analyzer-n2`, `analyzer-disconnect`, `analyzer-planning-info`, `analyzer-planning-footnote`, `analyzer-trend` (the row), `analyzer-trend-chart`.
- **Exact copy:**
  - Strip status: `SOLO connected · ${transport.name}`, `Not connected`, `Connecting…`
  - No-data banner: `No data is arriving. On the SOLO set Menu → Preferences → "Send data to USB" above zero, and turn printer mode off.`
  - Footnote: `END and density at the 1.4 MOD. Seawater, 10 m/bar. $endNote Orientation only — plan with your own tools.`, where `endNote` is today's text.
  - Trend row: `Trend, last 2 minutes`
  - The Android note (today's text, key `analyzer-transport-note`) is a caption under the strip while that source is selected and not connected.
  - Planning labels: `MOD 1.1` with an accent `DIL` tag (only for 1.1), `MOD 1.4`, `END`, `Density`, `Min. depth`, `Gas temp`, `Ambient`.
- **Values:** every planning value string is exactly today's (`'57 m'`, `'6.3 g/L'`, `'surface'`, `'21.4 °C'`, `'1013 hPa'`, `'n/a'`, `'–'`). Only the layout changes.
- **Sizes:**
  - Phone: strip 32 pt, section padding 10 pt, hero values 30 pt, 6 pt between the mix line and the stats, trend row 30 pt.
  - Wide (≥ `kAnalyzerWideBreakpoint`): mix 34 pt, hero values 44 pt, footnote visible.

- [ ] **Step 1: Write the failing tests** (fake transport feeding SOLO lines, as in today's analyzer tests)
  - `before connecting: Source and Connect in the strip, dashes and NO DATA`: `analyzer-transport` and `analyzer-connect` are found; `analyzer-o2` reads `--.-`; `analyzer-pill` reads `NO DATA`.
  - `connected: transport name and Disconnect`: `analyzer-status` contains `SOLO connected · `; `analyzer-disconnect` is found.
  - `stable 20.6/33.8 shows Tx20.6/33.8, 20.6, 33.8, 45.6 and STABLE`
  - `a sensor error shows ***.* and SENSOR ERROR`
  - `connecting shows Connecting…`
  - `a failed connect shows the error banner and the strip goes back to Not connected`
  - `a settling reading shows SETTLING`
  - `after Disconnect the last reading stays and the strip shows Source and Connect`
  - `a SOLO that never sent a line shows the no-data banner; one that streamed and went quiet doesn't`
  - `planning keeps today's values`: carry over every MOD / END / density / min-depth / temp / baro expectation from today's `analyzer_screen_test.dart`, unchanged.
  - `on a phone the footnote is behind the info button; on wide it is shown`
  - `the trend starts collapsed and opens on tap`: `analyzer-trend-chart` not found, tap `analyzer-trend`, then found.
  - `no overflow at 320×568 and text scale 1.3` (Review Focus 3): `tester.view.physicalSize`, `MediaQuery` text scaler 1.3, pump a stable reading, `expect(tester.takeException(), isNull)`.
  - `renders in every theme` (Review Focus 4): loop over `AppThemes.all`, wrap in `MaterialApp(theme: def.themeData)` (each `AppThemeDef`'s `themeData`, as `AppThemes.byId(...).themeData` in app code), `expect(tester.takeException(), isNull)`.

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/analyzer_states_test.dart`.

- [ ] **Step 3: Implement the four widgets and the new layout.** The save section stays today's card for now (Task 9).

- [ ] **Step 4: Run the analyzer tests**

Run: `flutter test test/ui/screens/analyzer_*`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/analyzer/ lib/ui/screens/analyzer_screen.dart test/ui/screens/
git commit -m "feat(analyse): strip, readout band, planning tiles and collapsed trend"
```

---

### Task 8: AnalysisSaveController: the save card's state moves out (no visual change)

Spec: §4.1 item 6–7 (the form and the pinned bar must be two widgets), §4.6.

**Files:**
- Create: `lib/ui/widgets/analysis_save_controller.dart`
- Modify:
  - `lib/ui/widgets/analysis_save_card.dart`: becomes a view over the controller.
  - `lib/ui/screens/analyzer_screen.dart`:
    - The screen state owns the controller: creates it in `initState`, disposes it in `dispose`, and keeps it in sync with the reading in `build`.
    - The controller replaces `_saveCardKey`. It keeps the form across the breakpoint, the job the `GlobalKey` did.
- Test:
  - Create `test/ui/widgets/analysis_save_controller_test.dart`.
  - Modify `test/ui/widgets/analysis_save_card_print_test.dart`, `test/ui/screens/analyzer_save_analysis_test.dart` and `test/ui/screens/analyzer_log_on_ok_test.dart`: construction only.

**Interfaces:**
- Produces:

```dart
class AnalysisSaveController extends ChangeNotifier {
  AnalysisSaveController({
    required GasAnalysesDaoLike dao,
    required SettingsNotifier settings,
    LabelPrintService? labelPrinting,
    DateTime Function() now = DateTime.now,
  });
  // blendTarget: BlendNotifier.recentTarget() (chips); unusedBlendTarget:
  // BlendNotifier.unusedRecentTarget() (automatic pick, Task 9); connected:
  // the session's controller.isConnected (a false→true change restarts
  // "Analysed by" from Your initials, Task 9).
  void update({AnalyzerReading? reading, required ReadingStability stability,
      DesiredMix? blendTarget, DesiredMix? unusedBlendTarget, required bool connected});
  OkSetup okSetup();                     // what the next OK press saves (today's _okSetup)
  // form state
  DesiredMix? get desiredMix;           void pickMix(DesiredMix? mix);
  GasRole get role;                      void tapRole(GasRole role);
  String? get cylinderId;                void selectCylinder(String? id);
  List<CylinderChoice> get cylinders;    List<DesiredMix> get mixOptions;
  final TextEditingController analysedBy, analysedFor, fillPressure, notes;
  int get copies;                        void setCopies(int copies);
  bool get printReady;                   bool get busy;
  // actions (dialogs need a context)
  Future<void> save(BuildContext context, {bool print = false});
  // Log on OK
  void bindLogger(UsbOkLogger? logger);  // sets logger.setupProvider, listens to results
  OkLogResult? get okResult;
  bool get printOnOk;                    void setPrintOnOk(bool on);
  Future<void> editResult(BuildContext context);
}
```

- All of today's behaviour moves over unchanged: confirm unstable, confirm hard mismatch, `_takenForResult` / `_useUpTaken`, the `_tellAnalysedBy` timing, and `onDesiredMixChanged`. `onDesiredMixChanged` is replaced by listening to the controller.
- `_deleteResult` stays for now; Task 10 removes it.

- [ ] **Step 1: Write the failing controller tests**
  - `a complete OK result uses up only the fields still as taken`: port today's card test.
  - `the OK setup carries the form's values`: `okSetup()` reflects `pickMix`, `tapRole`, the text fields and `copies`.
  - `a non-number fill pressure is passed as no pressure`: port today's card test.

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/widgets/analysis_save_controller_test.dart`.

- [ ] **Step 3: Move the logic; the card renders from the controller.** No UI change.

- [ ] **Step 4: Run the save and analyzer tests**

Run: `flutter test test/ui/widgets/ test/ui/screens/analyzer_*`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/analysis_save_controller.dart lib/ui/widgets/analysis_save_card.dart lib/ui/screens/analyzer_screen.dart test/
git commit -m "refactor(analyse): AnalysisSaveController owns the save form's state"
```

---

### Task 9: Save section and action bar: defaults, nearest mix, role rule (manual saving)

Spec: §4.1 items 6–7, §4.2, §4.3, §4.5 (no printer). Mockups: `gas-tabs.png` (middle), and `analyzer-states.png` ("No label printer set up").

**Files:**
- Create: `lib/ui/widgets/analysis_action_bar.dart` (pinned at the bottom of the tab; on wide, at the bottom of the save column)
- Modify:
  - `lib/ui/widgets/analysis_save_controller.dart`: new rules.
  - `lib/ui/widgets/analysis_save_card.dart`: becomes the "Save analysis" section, with no buttons.
  - `lib/ui/screens/analyzer_screen.dart`: the layout is `Column(Expanded(scroll), AnalysisActionBar)`.
  - `lib/ui/notifiers/settings_notifier.dart`: delete `analyzerAnalysedBy` / `setAnalyzerAnalysedBy` and their key, except the read that Task 3's migration uses.
- Test:
  - Modify `test/ui/screens/analyzer_save_analysis_test.dart`, `test/ui/widgets/analysis_save_card_print_test.dart` and `test/ui/screens/analyzer_log_on_ok_test.dart`: the `analyzerAnalysedBy` tests become "Your initials" tests.
  - Create `test/ui/widgets/analysis_save_defaults_test.dart`.

**Interfaces:**
- Consumes:
  - Task 1's `pickDesiredMix`, `resolveGasRole`, `MixPickSource`
  - Task 3's `yourInitials`, `analyzerFillPressureStartBar`, `unusedRecentTarget`, `markRecentTargetUsed`
- Produces:
  - **Controller additions:**
    - `bool get mixIsAutomatic`
    - `MixPickSource? get mixSource` (null for a diver pick)
    - `void clearMix()` (the diver's "no mix")
    - `VoidCallback? onBlendTargetUsed`, set by the screen to `blend.markRecentTargetUsed`
  - `AnalysisActionBar({Key? key, required AnalysisSaveController controller})`
- **Rules:**
  - **Desired mix:** while `mixIsAutomatic`, `desiredMix` is `pickDesiredMix(reading, blendTarget: unusedBlendTarget)?.mix`, re-evaluated on every `update`. A tap (or Other…) makes it the diver's pick until the next manual save. Tapping the selected chip clears it, also as a diver choice. A manual save sets it back to automatic.
  - **Role:** `resolveGasRole(tapped: _tappedRole, cylinderRole: selectedCylinder?.role, o2PercentForRule: desiredMix?.o2Percent ?? reading.o2)`. A manual save clears `_tappedRole`.
  - **Fill pressure:** starts at `analyzerFillPressureStartBar`, written whole when it is whole (`230`), and goes back to it after a manual save.
  - **Analysed by:** starts from `yourInitials` when a session connects (`update(connected: true)` after `false`). It is never written to settings.
  - **Cylinder:** kept after a manual save. **Notes:** cleared. **Copies:** back to 1.
  - **Blend target used:** a manual save that completes, whose `desiredMix == blend.recentTarget()`, calls `onBlendTargetUsed`.
  - **Save uses the snapshot:** the desired mix saved is the pick for the snapshot reading taken at the start of `save`, not the live one (Review Focus 1).
  - **Chips:** the selected mix, then `blend.recentTarget()`, then `recentDesiredMixes` from the log. No duplicates, at most 3, then "Other…".
- **Exact copy:**
  - Verdict: `mixMatchText(match, mix.name)`, plus `, the nearest standard mix` for a standard auto pick or `, the Blend target` for a target auto pick, and nothing for a diver pick.
  - `+ Add a note`
  - `Set up label printer`
  - Buttons: `Save`, `Save & print`
- **Keys kept:** `analysis-save-card` (on the section), `analysis-gas-role`, `analysis-cylinder`, `analysis-diver`, `analysis-pressure`, `analysis-for`, `analysis-notes`, `analysis-unstable-hint`, `analysis-save`, `analysis-save-print`, `analysis-setup-printer`, `copies-dec`, `copies-value`, `copies-inc`.
- **Keys new:** `analysis-verdict`, `analysis-add-note`, `analysis-action-bar`.
- **Layout:**
  - Action bar with a printer: outlined `Save`, filled `Save & print` (the primary), and `CopiesStepper`.
  - Without a printer: one full-width filled `Save`, and the link in the section.
  - The section loses its card border; its heading is `SectionHeader('Save analysis')`.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('a 20.4/33.5 reading preselects Tx21/35 with the standard suffix', (t) async {
  // reading 20.4/33.5 stable
  expect(find.text('Matches Tx21/35, the nearest standard mix'), findsOneWidget);
});
testWidgets('the role is Diluent for Tx21/35 and Bailout/deco for EAN50', (t) async { /* segment selection */ });
testWidgets('a tapped role survives a reading change and resets after Save', (t) async {});
testWidgets('fill pressure starts at the setting and returns to it after Save', (t) async { /* 230, type 200, save, 230 again */ });
testWidgets('Analysed by starts from Your initials and is not written back', (t) async { /* settings.yourInitials == 'EdP' after typing 'JS' */ });
testWidgets('the cylinder stays after a manual save', (t) async {});
testWidgets('a reading that changes during the unstable dialog saves the snapshot pick', (t) async {
  // reading 19.1/43 (Tx18/45, orange), Save -> unstable dialog open -> feed 23.0/30.0 -> Save anyway
  // stored desiredMix == DesiredMix(18, 45)
});
testWidgets('a completed save of the Blend target marks it used', (t) async { /* onBlendTargetUsed called once */ });
testWidgets('Save & print is the primary button when a printer is set up', (t) async { /* FilledButton key analysis-save-print */ });
testWidgets('without a printer Save is the only button and the link shows', (t) async {});
testWidgets('at most three mix chips plus Other…', (t) async {});
testWidgets('Analyse tab fits 393×852 with insets and the bottom nav (stable, printer set up)', (t) async {
  // MediaQuery padding top 59, bottom 34; host = GasScreen inside a Scaffold with a 56 pt BottomNavigationBar
  // expect the Analyse tab's scrollable maxScrollExtent == 0
});
testWidgets('no overflow at 320×568 and text scale 1.3 with the save section', (t) async {}); // Review Focus 3
```

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/widgets/analysis_save_defaults_test.dart`.

- [ ] **Step 3: Implement the controller rules, the restyled section and the action bar.** Fields are 40 pt high on the Analyse tab (spec §4.1 height budget).

- [ ] **Step 4: Run the analyzer and widget tests**

Run: `flutter test test/ui/widgets/ test/ui/screens/analyzer_* test/ui/screens/gas_screen_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/ lib/ui/screens/analyzer_screen.dart lib/ui/notifiers/settings_notifier.dart test/
git commit -m "feat(analyse): save defaults, nearest standard mix and pinned action bar"
```

---

### Task 10: Log on OK as start and stop

Spec: §4.4, §4.5 (held, room air). Mockup: `analyzer-states.png`.

**Files:**
- Modify:
  - `lib/ui/widgets/analysis_save_card.dart`: heading button, print-on-OK row, result row.
  - `lib/ui/widgets/analysis_action_bar.dart`: the status strip.
  - `lib/ui/widgets/analysis_save_controller.dart`: the OK setup, used mark on OK.
- Test: Modify `test/ui/screens/analyzer_log_on_ok_test.dart`.

**Interfaces:**
- Consumes:
  - Task 2's `LogOnOkSetup(autoPickMix:, blendTarget:, gasRole:)`
  - Task 5's `session.okRunning` and `session.held`
- **Setup the controller hands the logger:**
  - `autoPickMix: mixIsAutomatic`
  - `desiredMix: mixIsAutomatic ? null : desiredMix`
  - `blendTarget: blend.unusedRecentTarget()`
  - `gasRole: _tappedRole ?? (cylinder role when known) ?? null`
- **Used mark on OK:** a complete OK result whose saved entry's desired mix equals `blend.recentTarget()` calls `onBlendTargetUsed`. Read the entry back by `analysisId`.
- **Tapped role:** stays across OK presses until changed (no reset on an OK save).
- **Used up on a complete OK save (plan 1's rule):** the fill pressure goes back to `analyzerFillPressureStartBar` (not empty), the cylinder and notes clear, and only fields still as the press took them change. A press that needs sign-off leaves them in place. Add a test: `a complete OK save puts the fill pressure back to 230`.
- **Keys:**
  - `analyzer-log-on-ok`: now the start button in the heading. It is enabled when `session.controller.isConnected && !session.sourceIsDemo && dao != null`, and hidden for Demo.
  - `analyzer-ok-strip`: the status strip; `analyzer-ok-stop`: Stop; `analysis-ok-strip-save`: room air Save.
  - Kept: `analysis-print-on-ok`, `analysis-ok-result`, `analysis-ok-edit`. `analysis-ok-delete` is removed.
- **Exact copy:**

  | Where | Text |
  |---|---|
  | Heading while running | `● Logging on OK` |
  | Strip, waiting | `Logging on OK` / `Press OK on the SOLO to save` |
  | Strip, held | `Held on the SOLO` / `Press OK there to measure again` |
  | Strip, room air | `Air isn't logged on OK` / `Tap Save to log it` |
  | Print row | `Print a label on each OK` |
  | Not-stable hint | `Not stable yet. An OK press now saves it marked not stable.` |
  | Hint near Stop | `Keep Anchorline open` (in place of "Keep this screen open") |

- **Behaviour:**
  - Start calls `settings.setAnalyzerLogOnOk(true)`; Stop calls `settings.setAnalyzerLogOnOk(false)`.
  - The print row shows only while running with a printer set up.
  - The result row has an icon, text, a 3 pt left edge in the result's colour, and Edit.

- [ ] **Step 1: Update and add tests**
  - Port every existing Log on OK test from the switch to the start/stop button.
  - `the heading button is disabled before connecting and hidden for Demo`
  - `Start shows the strip and the print row; Stop restores Save and Save & print`
  - `held shows "Held on the SOLO"`
  - `room air shows the strip's Save and Stop`
  - `each press picks its own mix: Tx21/35 then EAN50 in one run`: two holds with different held lines. The rows saved are (21/35, diluent) and (50/0, bailout).
  - `a tapped role stays across presses`: tap Bailout/deco, two holds (Tx21/35 and Tx18/45); both rows are bailout.
  - `a complete OK save of the Blend target marks it used`
  - `the result row has Edit and no Delete`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/analyzer_log_on_ok_test.dart`.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the analyzer tests**

Run: `flutter test test/ui/screens/analyzer_* test/ui/screens/gas_screen_test.dart test/ui/widgets/`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/ test/ui/screens/analyzer_log_on_ok_test.dart
git commit -m "feat(analyse): Log on OK as a start/stop control with a status strip"
```

---

### Task 11: Blend tab restyle

Spec: §3. Mockup: `gas-tabs.png` (left).

**Files:**
- Modify: `lib/ui/screens/blend_screen.dart`
- Test: `test/ui/screens/blend_screen_test.dart`

**Interfaces:**
- Consumes: Task 4's `HeroStat` / `HeroStatRow`; Task 1's `kStandardMixes` (target chips: Tx21/35, Tx18/45, Tx15/55, EAN32, EAN50); `DesiredMixPicker`'s "Other…" dialog. Expose its `_OtherMixDialog` as `Future<DesiredMix?> showOtherMixDialog(BuildContext)` in `desired_mix_picker.dart`.
- **Keys kept:**
  - Inputs: `cur-o2`, `cur-he`, `cur-pressure`, `cur-capacity`, `tgt-o2`, `tgt-he`, `tgt-pressure`
  - Fill options: `use-real-gas`, `fill-temp`, `settled-temp`
- **Keys new:**
  - Band: `blend-plan-band`, `blend-step-<i>` (0-based), `blend-cost` (tap → breakdown)
  - Inputs: `blend-target-chip-<o2>-<he>`, `blend-topoff-chip-<o2>-<he>`, `blend-topoff-other`
  - Fill options: `blend-fill-options` (the row), `blend-fill-order`
- **Exact copy:**
  - Band: `to ${pressure} bar`; step labels `${i+1} · Helium` / `· Oxygen` / `· ${gasMixName(topoff)}` / `Drain`; values `+81 bar` / `−40 bar`, with `to 131` under them; cost with no currency symbol, two decimals.
  - Section headers: `Target`, `In the cylinder now`, `Top off with`, `Fill options`.
  - Fill options summary: `${sequenceLabel} · ${realGas ? 'real gas' : 'ideal gas'} · ${fillTemp} °C`
  - The drain, hot-fill, impossible and "Nothing to do" texts stay today's.
- **Colours:** helium `DataColors.helium`, oxygen `SafetyColors.success`, top-off `textPrimary`, drain `SafetyColors.warning`.

- [ ] **Step 1: Write the failing tests**
  - `the band shows the target and one stat per step`: default inputs plus 50 bar of air in 12 L. The band contains `Tx21/35` and `to 230 bar`; `blend-step-0` contains `Helium`.
  - `tapping a target chip fills the fields`: tap `blend-target-chip-18-45`; `tgt-o2` shows `18`.
  - `typing a non-standard target deselects the chips`
  - `Other… sets a custom top-off with its own chip`
  - `fill options start collapsed and open on tap`
  - `the cost opens the breakdown`
  - `an impossible blend shows the danger banner in place of the steps`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/blend_screen_test.dart`.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run them and see them pass** (same command, plus `flutter test test/ui/notifiers/`)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/blend_screen.dart lib/ui/widgets/desired_mix_picker.dart test/ui/screens/blend_screen_test.dart
git commit -m "feat(blend): fill plan band and grouped inputs"
```

---

### Task 12: Log tab rows and the edit sheet

Spec: §5. Mockup: `gas-tabs.png` (right).

**Files:**
- Modify: `lib/ui/screens/gas_analysis_log_screen.dart`, `lib/ui/widgets/analysis_edit_sheet.dart`
- Test: `test/ui/screens/gas_analysis_log_screen_test.dart`, `test/ui/widgets/analysis_edit_sheet_test.dart`

**Interfaces:**
- **Keys kept:** `analysis-log-export`, `analysis-log-signoff-filter` (now the "Needs sign-off ‹n›" chip), `analysis-needs-signoff-<id>`, `analysis-print-<id>`, `analysis-<id>` (the `Dismissible`), and every `analysis-edit-*` key.
- **Keys new / changed:**
  - `analysis-log-filter-all`
  - `analysis-role-<id>`, which replaces `analysis-dil-<id>`; it shows `DIL` or `BO`
  - `analysis-day-<yyyy-MM-dd>`
  - `analysis-notes-<id>`
- **Removed:** `analysis-log-signoff-count`, since the chip carries the count.
- **Row:**
  - **Left edge (3 pt):** `palette.accentPrimary` for diluent. For bailout / deco, use the palette's quieter colour, `palette.textMuted`. Check it against all six themes; do not hard-code `#3A6477`.
  - **Line 1:** role tag, `a.mixName` in mono, the `Needs sign-off` tag, the notes icon, and the time `HH:mm`.
  - **Line 2:** mono, `'${o2.toStringAsFixed(1)} / ${he.toStringAsFixed(1)}'`, then the fill pressure `'230 bar'`, `analysedBy ?? 'no name'`, the cylinder, and `'for $analysedFor'`, joined by ` · `.
  - **Line 3:** `mixMatchText` in the match colour, then `Saved before stable` (amber) when `!a.stable`, joined by ` · `; omitted when empty.
  - **Trailing:** the print button for every entry when a printer is set up.
    - Faded (`Opacity 0.35`) and showing `kSignOffBeforePrintMessage` on tap when `needsSignoff`.
    - This replaces today's "hidden when flagged".
- **Day separators:** `Today`, `Yesterday`, else `d MMM yyyy`.
- **Edit sheet:**
  - The `_MeasuredValues` box becomes a band in `surfaceRaised`: mix name, a pill (`Stable` / `Not stable`), `O2 x.x %   He x.x %` and `date · temp`.
  - The fields use the save section's styles.
  - The buttons and their outcomes don't change.

- [ ] **Step 1: Write the failing tests** (port the existing ones whose finders change)
  - `rows lead with the analysed name and say the desired mix in line 3`: 20.6/33.8 with desired 21/35 shows `Tx21/34` and `Matches Tx21/35`.
  - `an unstable entry says Saved before stable`
  - `a flagged entry's print button is faded and explains on tap`
  - `day separators group entries`
  - `the sign-off chip filters, and All restores`
  - `the bailout edge uses a palette colour in every theme` (Review Focus 4): pump the list under each `AppThemes.all` theme; `expect(tester.takeException(), isNull)`.

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/gas_analysis_log_screen_test.dart test/ui/widgets/analysis_edit_sheet_test.dart`.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run them and see them pass** (same command)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/gas_analysis_log_screen.dart lib/ui/widgets/analysis_edit_sheet.dart test/
git commit -m "feat(log): dive-list style rows, day separators and a restyled edit sheet"
```

---

### Task 13: Settings as five tabs

Spec: §6 (including the table of where every setting goes). Mockup: `settings-tabs.png`.

**Files:**
- Create: `lib/ui/screens/settings/general_tab.dart`, `planning_tab.dart`, `gas_tab.dart`, `sync_tab.dart` (About comes in Task 14), and `lib/ui/components/setting_row.dart`
- Modify:
  - `lib/ui/screens/settings_screen.dart`: becomes the tab host, with `TabTopBar` and `onHome`. The existing dialogs and actions (`_forceStampOwnerId`, `_drainQueueManually`, `_confirmAndResetLocalData`, `_shareBleDebugLog`, auth sheet) stay in this file or move with their tab.
  - `lib/ui/widgets/label_printer_settings_section.dart`: restyle with `SettingRow`; `LabelPrinterSettingsScreen` keeps its own app bar.
  - `lib/ui/widgets/subsurface_sync_section.dart`: restyle only (same controls, labels and keys); it sits in the Sync tab.
  - `_AccountSection`, `_SignInTile`, `_SignedInTile` and `_SyncStatusRow` in `settings_screen.dart`: restyle only, in the Sync tab.
  - `lib/ui/widgets/theme_picker.dart`: a 3-column grid of tiles.
  - `lib/ui/app_shell.dart`: pass `onHome: _goHome`.
- Test: `test/ui/screens/settings_screen_test.dart`, `settings_screen_sync_status_test.dart`, `test/ui/widgets/label_printer_settings_section_test.dart`, `test/ui/notifiers/settings_analyzer_mod_ppo2s_test.dart` (unchanged)

**Interfaces:**
- Consumes: Task 4's `TabTopBar` and `ValueStepper`; Task 3's settings.
- Produces:
  - `SettingRow({Key? key, required String title, String? helper, Widget? control, VoidCallback? onTap, bool danger = false})`
  - `SettingsScreen` gains `required VoidCallback onHome` (tests pass `() {}`).
- **Tab keys:** `settings-tab-general`, `-planning`, `-gas`, `-sync`, `-about`. Labels only: `General`, `Planning`, `Gas`, `Sync`, `About`.
- **Keys kept:** `settings-blend-o2-cost`, `settings-blend-he-cost`, `settings-blend-air-fee`, `settings-blend-topoff-o2`, `settings-blend-topoff-he`, `settings-blend-sequence`, `settings-blend-fill-temp`, `settings-blend-settled-temp`, the `label-printer-*` keys, `theme-<id>`.
- **Keys new:**
  - `settings-your-initials`, `settings-fill-pressure-start`
  - MOD chips: `settings-mod-ppo2-<p>`, `settings-mod-ppo2-<p>-remove`, `settings-mod-ppo2-add`
  - Steppers (key prefixes): `settings-sac-bottom`, `settings-sac-deco`, `settings-ascent-fast`, `settings-ascent-slow`, `settings-watermark`
  - Repair rows: `settings-repair-reassign`, `settings-repair-push`, `settings-repair-reset`
- **Ranges** (as today's sliders): SAC 10–60 L/min, ascent 3–30 m/min, watermark 0–20 % (stored as 0.00–0.20).
- **MOD add dialog:** accepts `analyzerModPpo2Min`–`analyzerModPpo2Max` (0.2–2.0) with two decimals. The ✕ is missing on the last chip.
- **Exact copy:** the row titles and helpers from `settings-tabs.png`. The END helper is `Off: only N₂ counts`, with no agency names (spec §10).
- **Repair rows:** `Re-assign dives to this account`, `Push stuck uploads`, `Reset local data` (danger). Each opens today's dialog.

- [ ] **Step 1: Update and add tests**
  - Every row of the spec §6 table changes its setting from its new tab. Port today's tests, plus one test per new control.
  - `MOD chips: remove 1.6, add 1.25, the last chip has no remove`
  - `steppers stop at their limits`
  - `Your initials and fill pressure start persist`
  - `Repair rows open today's dialogs`
  - `the anchor calls onHome`
  - `renders in every theme without exceptions`

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/ui/screens/settings_screen_test.dart test/ui/screens/settings_screen_sync_status_test.dart test/ui/widgets/label_printer_settings_section_test.dart`.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run them and see them pass** (same command)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/settings_screen.dart lib/ui/screens/settings/ lib/ui/components/setting_row.dart lib/ui/widgets/label_printer_settings_section.dart lib/ui/widgets/theme_picker.dart lib/ui/app_shell.dart test/
git commit -m "feat(settings): five tabs with grouped settings"
```

---

### Task 14: About tab and the build date

Spec: §7.

**Files:**
- Create: `lib/ui/screens/settings/about_tab.dart`
- Modify:
  - `lib/build_info.dart`
  - `lib/ui/screens/settings_screen.dart`: wire the About tab; the Widgetbook long-press moves to the logo.
  - Docs:
    - `docs/BETA_DISTRIBUTION.md`, `docs/MACOS_DISTRIBUTION.md`, `docs/WINDOWS_DISTRIBUTION.md`, `docs/TESTFLIGHT_QUICKSTART.md`: add `--dart-define=APP_BUILD_DATE=<yyyy-MM-dd>` next to every `APP_BUILD`.
    - `docs/superpowers/plans/2026-11-02-cloud-builds.md`: Phase D passes `APP_BUILD_DATE` (UTC date of the build).
- Test: `test/build_info_test.dart` (create, or extend the existing one), `test/ui/screens/settings_about_test.dart`

**Interfaces:**
- Produces:
  - `BuildInfo.buildDate`: `static const String buildDate = String.fromEnvironment('APP_BUILD_DATE');`
  - `String? formatBuildDate(String raw)`: `'2026-11-06'` → `'6 Nov 2026'`; `''` or a malformed date → `null`.
  - `String channelLabel(String channel)`: `release` → `Release`, `nightly` → `Nightly`, anything else → `Development`.
  - `AboutTab({Key? key, String version = BuildInfo.version, String build = BuildInfo.build, String buildDate = BuildInfo.buildDate, String channel = BuildInfo.channel, bool hasLicence = false, VoidCallback? onLongPressLogo})`. The parameters let tests vary them; `hasLicence` stays `false` until the repository has a LICENSE file.
- **Exact copy:**
  - Tagline: `Dive log and analysis for CCR divers`
  - Stats: `Version`, `Build`, `Date`
  - Rows: `Author` / `Egbert de Pauw`, `Channel`, `Licence` / `GPLv2` (only when `hasLicence`)
  - Support: `Share Bluetooth debug log`
  - Development build (empty version or build): `Development build` in place of the three stats.
- **Keys:** `about-version`, `about-build`, `about-date`, `about-dev-build`, `about-author`, `about-licence`, `about-share-ble-log`, `about-logo`.

- [ ] **Step 1: Write the failing tests**

```dart
test('formatBuildDate', () {
  expect(formatBuildDate('2026-11-06'), '6 Nov 2026');
  expect(formatBuildDate(''), isNull);
  expect(formatBuildDate('11/06/2026'), isNull);
});
testWidgets('a release build shows version, build and date', (t) async { /* 1.1.0, 43, 2026-11-06 */ });
testWidgets('no date define hides the Date stat', (t) async {});
testWidgets('a development build shows "Development build"', (t) async {});
testWidgets('the licence row is hidden without a licence', (t) async {});
testWidgets('long-pressing the logo calls onLongPressLogo', (t) async {});
```

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/build_info_test.dart test/ui/screens/settings_about_test.dart`.

- [ ] **Step 3: Implement the About tab and the docs**

- [ ] **Step 4: Run the whole suite and the analyzer**

Run: `flutter analyze` then `flutter test`. Expected: analyze clean, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/build_info.dart lib/ui/screens/settings/about_tab.dart lib/ui/screens/settings_screen.dart docs/ test/
git commit -m "feat(settings): About tab with version, build and build date"
```

---

## After the last task

- Build and run on an iPhone 15 (or its simulator) and on the Mac. On the iPhone, check the Analyse tab in the stable, not-logging state with a printer set up: it must not scroll.
- Then the usual finish: `superpowers:finishing-a-development-branch`. Open an issue, then a PR from the build branch. The spec branch `spec/gas-settings-redesign` holds the spec and this plan.
