/// Partial-pressure gas-blending planner.
///
/// Given a cylinder's current contents (gauge pressure + O2/He
/// fractions), a target mix + pressure, a top-off gas, and a fill
/// sequence, returns the ordered list of fill steps the diver should
/// execute, a cost breakdown, and a drain recommendation when the
/// target is unreachable from current contents.
///
/// Implementation lives in MOLE SPACE. We compute how many moles of
/// each gas the target cylinder must hold via van der Waals, subtract
/// what's already there, decompose the delta into "moles from the O2
/// bank", "moles from the He bank", and "moles from the top-off",
/// then walk the chosen fill sequence converting moles → gauge bar
/// at each intermediate cylinder state. By construction the sum of
/// the bar increments equals exactly the target gauge pressure —
/// fixing the earlier "scale top-off by Z" bug that left fills at
/// 257 bar when the user asked for 250.
///
/// Toggling [useRealGas] to false collapses every vdW call into the
/// ideal-gas form (P V = n R T), so the same code path drives both
/// modes. The default is real-gas; matches the reference tooling.
library;

import 'compressibility.dart' as z;

/// Snapshot of a cylinder for blending math. [oxygenPercent] +
/// [heliumPercent] determine the inert split; nitrogen fills the rest.
class CylinderState {
  const CylinderState({
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.pressureBar,
    required this.waterCapacityL,
  });

  final double oxygenPercent;
  final double heliumPercent;
  final double pressureBar;
  final double waterCapacityL;

  double get nitrogenPercent => 100.0 - oxygenPercent - heliumPercent;
  double get fO2 => oxygenPercent / 100.0;
  double get fHe => heliumPercent / 100.0;
  double get fN2 => nitrogenPercent / 100.0;
}

/// Two-fraction descriptor for a fill source (O2 bottle, He bottle,
/// top-off mix). Nitrogen fills the rest.
class FillSource {
  const FillSource({
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  static const o2 = FillSource(oxygenPercent: 100, heliumPercent: 0);
  static const he = FillSource(oxygenPercent: 0, heliumPercent: 100);
  static const air = FillSource(oxygenPercent: 21, heliumPercent: 0);

  final double oxygenPercent;
  final double heliumPercent;

  double get fO2 => oxygenPercent / 100.0;
  double get fHe => heliumPercent / 100.0;
  double get fN2 => (100.0 - oxygenPercent - heliumPercent) / 100.0;
}

enum FillSequence {
  heThenO2ThenTopoff,
  o2ThenHeThenTopoff,
  o2ThenTopoffThenHe,
}

enum BlendStepKind { drain, addO2, addHe, addTopoff }

class BlendStep {
  const BlendStep({
    required this.kind,
    required this.barAdded,
    required this.cumulativePressureBar,
    required this.source,
  });

  final BlendStepKind kind;
  final double barAdded;
  final double cumulativePressureBar;
  final FillSource source;
}

class BlendPrices {
  const BlendPrices({
    required this.oxygenPerLitre,
    required this.heliumPerLitre,
    required this.airFlatFee,
  });

  static const zero = BlendPrices(
    oxygenPerLitre: 0,
    heliumPerLitre: 0,
    airFlatFee: 0,
  );

  final double oxygenPerLitre;
  final double heliumPerLitre;
  final double airFlatFee;
}

class BlendCost {
  const BlendCost({
    required this.oxygenLitres,
    required this.heliumLitres,
    required this.topoffLitres,
    required this.oxygenCost,
    required this.heliumCost,
    required this.airCost,
  });

  static const zero = BlendCost(
    oxygenLitres: 0,
    heliumLitres: 0,
    topoffLitres: 0,
    oxygenCost: 0,
    heliumCost: 0,
    airCost: 0,
  );

  final double oxygenLitres;
  final double heliumLitres;
  final double topoffLitres;
  final double oxygenCost;
  final double heliumCost;
  final double airCost;

  double get total => oxygenCost + heliumCost + airCost;
}

enum BlendError { needsDrain, impossible }

class BlendResult {
  const BlendResult({
    required this.steps,
    required this.finalOxygenPercent,
    required this.finalHeliumPercent,
    required this.finalPressureBar,
    required this.cost,
    this.drainToPressureBar,
    this.settledPressureBar,
    this.settledTemperatureKelvin,
    this.fillTemperatureKelvin,
    this.error,
    this.errorMessage,
  });

  final List<BlendStep> steps;
  final double finalOxygenPercent;
  final double finalHeliumPercent;
  /// Cumulative cylinder gauge at the END of the fill, read at the
  /// **fill** temperature. The per-step cumulativePressureBar values
  /// are read at the same temperature, so the diver can compare them
  /// against the gauge during blending.
  final double finalPressureBar;
  final BlendCost cost;
  final double? drainToPressureBar;

  /// What the gauge will read once the cylinder cools to
  /// [settledTemperatureKelvin]. Equal to the user-requested target
  /// pressure (the inputs interpret target as the "cold" pressure).
  /// Null when fill == settled (no hot-fill compensation needed).
  final double? settledPressureBar;
  final double? settledTemperatureKelvin;
  final double? fillTemperatureKelvin;

  final BlendError? error;
  final String? errorMessage;

  bool get isOk => error == null;
}

/// Blending math entry point. See module docstring.
///
/// [temperatureKelvin] is the FILL temperature — the cylinder's
/// temperature while the diver is at the fill station. The per-step
/// pressures in the returned plan are computed at this temperature so
/// they match the gauge during blending.
///
/// [settledTemperatureKelvin], if non-null and different from
/// [temperatureKelvin], turns on hot-fill compensation: the target
/// pressure is interpreted as the COLD/settled pressure (what the
/// diver wants once the cylinder cools), the target moles are
/// computed at that cold temperature, and the per-step gauge values
/// land on a HIGHER total pressure during the (warm) fill. The
/// returned [BlendResult.settledPressureBar] reports what the gauge
/// will read after cooldown.
BlendResult planBlend({
  required CylinderState current,
  required CylinderState target,
  required FillSource topoff,
  FillSequence sequence = FillSequence.heThenO2ThenTopoff,
  bool useRealGas = true,
  BlendPrices prices = BlendPrices.zero,
  double temperatureKelvin = z.kDefaultBlendingTempKelvin,
  double? settledTemperatureKelvin,
}) {
  // Cold target temp — defaults to the fill temp (no overfill).
  final settledTempK = settledTemperatureKelvin ?? temperatureKelvin;

  // ── Convert tank states → moles per gas ─────────────────────────
  // Current cylinder reading is whatever the diver sees on the gauge
  // now — assume that's at the fill-station temperature (cylinder is
  // already warmed up). If they entered a freshly-arrived cold-stored
  // pressure, the moles would be off by ~T_fill/T_settled, but in
  // practice the diver lets the cylinder equilibrate before reading,
  // so fill-temp is the right call.
  final v = current.waterCapacityL;
  final nTotalCur = z.molesForGauge(
    pressureBar: current.pressureBar,
    volumeL: v,
    fO2: current.fO2,
    fHe: current.fHe,
    temperatureKelvin: temperatureKelvin,
    useRealGas: useRealGas,
  );
  final nHeCur = current.fHe * nTotalCur;
  final nO2Cur = current.fO2 * nTotalCur;
  final nN2Cur = current.fN2 * nTotalCur;

  // Target moles computed at the SETTLED temperature. The diver's
  // target pressure is the gauge reading they want once the tank
  // cools to settled temp, so the moles are fixed at that condition.
  final nTotalTgt = z.molesForGauge(
    pressureBar: target.pressureBar,
    volumeL: v,
    fO2: target.fO2,
    fHe: target.fHe,
    temperatureKelvin: settledTempK,
    useRealGas: useRealGas,
  );
  final nHeTgt = target.fHe * nTotalTgt;
  final nO2Tgt = target.fO2 * nTotalTgt;
  final nN2Tgt = target.fN2 * nTotalTgt;

  // ── Decompose the per-gas mole delta into fill streams ──────────
  //   He bank: pure He
  //   O2 bank: pure O2
  //   top-off: (fO2_t, fHe_t, fN2_t) mix, usually air or EAN
  //
  // Constraints (assuming top-off is the only stream that brings N2):
  //   He:    nHeAdd  + fHe_t · nTop = nHeTgt − nHeCur
  //   O2:    nO2Add  + fO2_t · nTop = nO2Tgt − nO2Cur
  //   N2:                fN2_t · nTop = nN2Tgt − nN2Cur
  final fN2t = topoff.fN2;
  final fO2t = topoff.fO2;
  final fHet = topoff.fHe;
  double nTop;
  if (fN2t <= 1e-9) {
    nTop = 0;
  } else {
    nTop = (nN2Tgt - nN2Cur) / fN2t;
  }
  final nHeAdd = nHeTgt - nHeCur - fHet * nTop;
  final nO2Add = nO2Tgt - nO2Cur - fO2t * nTop;

  // ── Drain check ─────────────────────────────────────────────────
  const eps = 1e-6;
  if (nHeAdd < -eps || nO2Add < -eps || nTop < -eps) {
    final k = _drainFraction(
      current: current,
      target: target,
      topoff: topoff,
      v: v,
      tempK: temperatureKelvin,
      useRealGas: useRealGas,
    );
    if (k == null) {
      return BlendResult(
        steps: const [],
        finalOxygenPercent: current.oxygenPercent,
        finalHeliumPercent: current.heliumPercent,
        finalPressureBar: current.pressureBar,
        cost: BlendCost.zero,
        error: BlendError.impossible,
        errorMessage:
            'Target mix is unreachable from this top-off gas — even '
            'a full drain wouldn\'t yield ${target.oxygenPercent.toStringAsFixed(0)}/'
            '${target.heliumPercent.toStringAsFixed(0)} at '
            '${target.pressureBar.toStringAsFixed(0)} bar.',
      );
    }
    final drainedPressure = k * current.pressureBar;
    final drained = CylinderState(
      oxygenPercent: current.oxygenPercent,
      heliumPercent: current.heliumPercent,
      pressureBar: drainedPressure,
      waterCapacityL: current.waterCapacityL,
    );
    final inner = planBlend(
      current: drained,
      target: target,
      topoff: topoff,
      sequence: sequence,
      useRealGas: useRealGas,
      prices: prices,
      temperatureKelvin: temperatureKelvin,
      settledTemperatureKelvin: settledTemperatureKelvin,
    );
    if (!inner.isOk) return inner;
    return BlendResult(
      steps: [
        BlendStep(
          kind: BlendStepKind.drain,
          barAdded: drainedPressure - current.pressureBar,
          cumulativePressureBar: drainedPressure,
          source: FillSource(
            oxygenPercent: current.oxygenPercent,
            heliumPercent: current.heliumPercent,
          ),
        ),
        ...inner.steps,
      ],
      finalOxygenPercent: inner.finalOxygenPercent,
      finalHeliumPercent: inner.finalHeliumPercent,
      finalPressureBar: inner.finalPressureBar,
      cost: inner.cost,
      drainToPressureBar: drainedPressure,
      settledPressureBar: inner.settledPressureBar,
      settledTemperatureKelvin: inner.settledTemperatureKelvin,
      fillTemperatureKelvin: inner.fillTemperatureKelvin,
    );
  }

  // Quantities the diver actually adds. The He / O2 bank contributions
  // are stored separately from the top-off contribution so the cost
  // calculator can attribute moles correctly.
  final nHeBank = nHeAdd.clamp(0, double.infinity).toDouble();
  final nO2Bank = nO2Add.clamp(0, double.infinity).toDouble();
  final nTopAdd = nTop.clamp(0, double.infinity).toDouble();

  // ── Walk the fill sequence, computing gauge pressure after each
  //    step from the running mole inventory ─────────────────────────
  final steps = <BlendStep>[];
  double curHe = nHeCur;
  double curO2 = nO2Cur;
  double curN2 = nN2Cur;
  double curGauge = current.pressureBar;

  double advanceTo({
    required double nextHe,
    required double nextO2,
    required double nextN2,
  }) {
    final total = nextHe + nextO2 + nextN2;
    if (total <= 0) return 0;
    final fO2 = nextO2 / total;
    final fHe = nextHe / total;
    return z.gaugeForMoles(
      nMol: total,
      volumeL: v,
      fO2: fO2,
      fHe: fHe,
      temperatureKelvin: temperatureKelvin,
      useRealGas: useRealGas,
    );
  }

  void emit({
    required BlendStepKind kind,
    required FillSource source,
    required double newHe,
    required double newO2,
    required double newN2,
  }) {
    final newGauge = advanceTo(nextHe: newHe, nextO2: newO2, nextN2: newN2);
    final delta = newGauge - curGauge;
    // Skip ineffective steps — a sub-half-bar fill is rounding noise
    // the diver can't act on with a typical fill gauge.
    if (delta.abs() < 0.5) {
      curHe = newHe;
      curO2 = newO2;
      curN2 = newN2;
      curGauge = newGauge;
      return;
    }
    steps.add(BlendStep(
      kind: kind,
      barAdded: delta,
      cumulativePressureBar: newGauge,
      source: source,
    ));
    curHe = newHe;
    curO2 = newO2;
    curN2 = newN2;
    curGauge = newGauge;
  }

  void fillHe() {
    emit(
      kind: BlendStepKind.addHe,
      source: FillSource.he,
      newHe: curHe + nHeBank,
      newO2: curO2,
      newN2: curN2,
    );
  }

  void fillO2() {
    emit(
      kind: BlendStepKind.addO2,
      source: FillSource.o2,
      newHe: curHe,
      newO2: curO2 + nO2Bank,
      newN2: curN2,
    );
  }

  void fillTopoff() {
    emit(
      kind: BlendStepKind.addTopoff,
      source: topoff,
      newHe: curHe + fHet * nTopAdd,
      newO2: curO2 + fO2t * nTopAdd,
      newN2: curN2 + fN2t * nTopAdd,
    );
  }

  switch (sequence) {
    case FillSequence.heThenO2ThenTopoff:
      fillHe();
      fillO2();
      fillTopoff();
      break;
    case FillSequence.o2ThenHeThenTopoff:
      fillO2();
      fillHe();
      fillTopoff();
      break;
    case FillSequence.o2ThenTopoffThenHe:
      fillO2();
      fillTopoff();
      fillHe();
      break;
  }

  // ── Cost: each fill stream's moles → bar-litres ─────────────────
  // The diver's "barliter" unit is moles × R × T at the blending
  // temperature. Matches the reference: 37.93 mol of He at 18 °C →
  // 37.93 × 0.08314 × 291.15 ≈ 918 barliter.
  const refR = 0.08314;
  final molesToBarLitres = refR * temperatureKelvin;
  final o2Litres = nO2Bank * molesToBarLitres;
  final heLitres = nHeBank * molesToBarLitres;
  final topoffLitres = nTopAdd * molesToBarLitres;
  final cost = BlendCost(
    oxygenLitres: o2Litres,
    heliumLitres: heLitres,
    topoffLitres: topoffLitres,
    oxygenCost: o2Litres * prices.oxygenPerLitre,
    heliumCost: heLitres * prices.heliumPerLitre,
    airCost: nTopAdd > 0 ? prices.airFlatFee : 0,
  );

  // When fill ≠ settled, expose the cold gauge reading so the UI can
  // surface "fills to X hot → settles to Y cold". Otherwise leave the
  // settled fields null so the UI knows there's no compensation.
  final hotFillCompensationActive =
      (settledTempK - temperatureKelvin).abs() > 0.1;
  return BlendResult(
    steps: steps,
    finalOxygenPercent: target.oxygenPercent,
    finalHeliumPercent: target.heliumPercent,
    finalPressureBar: curGauge,
    cost: cost,
    settledPressureBar:
        hotFillCompensationActive ? target.pressureBar : null,
    settledTemperatureKelvin:
        hotFillCompensationActive ? settledTempK : null,
    fillTemperatureKelvin:
        hotFillCompensationActive ? temperatureKelvin : null,
  );
}

// ── Drain solver (mole-space) ───────────────────────────────────────
//
// Returns the largest fraction k ∈ (0, 1] of current contents we can
// keep such that all three fill quantities become ≥ 0. Returns null
// when even a full drain (k = 0) can't reach the target.
double? _drainFraction({
  required CylinderState current,
  required CylinderState target,
  required FillSource topoff,
  required double v,
  required double tempK,
  required bool useRealGas,
}) {
  // Moles in cylinder at a drained pressure of k × current.pressureBar.
  // For ideal-gas, moles scale linearly with pressure → trivial. For
  // real-gas, moles are a non-linear function of pressure but very
  // close to linear at reasonable pressures; we binary-search k.
  final nTotalTgt = z.molesForGauge(
    pressureBar: target.pressureBar,
    volumeL: v,
    fO2: target.fO2,
    fHe: target.fHe,
    temperatureKelvin: tempK,
    useRealGas: useRealGas,
  );
  final nHeTgt = target.fHe * nTotalTgt;
  final nO2Tgt = target.fO2 * nTotalTgt;
  final nN2Tgt = target.fN2 * nTotalTgt;

  bool feasibleAtK(double k) {
    final nCur = z.molesForGauge(
      pressureBar: k * current.pressureBar,
      volumeL: v,
      fO2: current.fO2,
      fHe: current.fHe,
      temperatureKelvin: tempK,
      useRealGas: useRealGas,
    );
    final nHeCur = current.fHe * nCur;
    final nO2Cur = current.fO2 * nCur;
    final nN2Cur = current.fN2 * nCur;
    final fN2t = topoff.fN2;
    final fO2t = topoff.fO2;
    final fHet = topoff.fHe;
    final nTop = fN2t <= 1e-9 ? 0.0 : (nN2Tgt - nN2Cur) / fN2t;
    final nHeAdd = nHeTgt - nHeCur - fHet * nTop;
    final nO2Add = nO2Tgt - nO2Cur - fO2t * nTop;
    return nTop >= -1e-6 && nHeAdd >= -1e-6 && nO2Add >= -1e-6;
  }

  // Try a full drain first — if even k=0 isn't feasible, the target is
  // unreachable from this top-off.
  if (!feasibleAtK(0)) return null;
  // Binary-search the largest k ∈ [0, 1] that's still feasible.
  double lo = 0, hi = 1;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    if (feasibleAtK(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  // If lo is essentially 1.0, the caller wouldn't have asked us for a
  // drain — return null to be safe (let the caller pick the no-drain
  // branch).
  if (lo >= 1.0 - 1e-6) return null;
  return lo;
}
