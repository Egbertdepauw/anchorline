/// Closing an open blend when an entry is signed off (issue #112).
///
/// A capture that landed as needs-sign-off could not close its blend at
/// capture time; it closes it here, once the diver has signed it off, with
/// the same matching as a save.
library;

import 'package:flutter/foundation.dart';

import '../analysis/mix_match.dart';
import '../analysis/open_blend_match.dart';
import '../data/db/gas_analyses_dao.dart';
import '../data/db/open_blends_dao.dart';

/// Closes the open blend that [signedOff], the entry as stored after its
/// sign-off, belongs to. Nothing for an entry that still needs sign-off or
/// is a residual.
///
/// With a desired mix: the oldest open blend of exactly that mix, whatever
/// the reading grades; the diver confirmed it by signing off. Without one:
/// the best open blend that grades match or orange, and the entry then
/// takes that blend's target and role.
///
/// A failure is printed and goes no further: the sign-off stands either way
/// and the blend stays open for the diver to close or dismiss.
Future<void> closeBlendOnSignOff({
  required GasAnalysis signedOff,
  required OpenBlendsDaoLike openBlends,
  required GasAnalysesDaoLike analyses,
}) async {
  if (signedOff.needsSignoff || signedOff.isResidual) return;
  try {
    // One analysis closes one blend: a second call (a sign-off on the log,
    // then a save on the card's result) finds it already closed.
    if (await openBlends.blendClosedBy(signedOff.id) != null) return;
    final desired = signedOff.desiredMix;
    if (desired != null) {
      await openBlends.closeOldestOpen(desired, signedOff.id);
      return;
    }
    final ranked = rankOpenBlends(
      o2Percent: signedOff.o2Percent,
      hePercent: signedOff.hePercent,
      open: await openBlends.listOpen(),
    );
    if (ranked.isEmpty) return;
    final level = ranked.first.grade.level;
    if (level != MixMatchLevel.match && level != MixMatchLevel.orange) return;
    final rankedBlend = ranked.first.blend;
    if (!await openBlends.closeBlend(rankedBlend, signedOff.id)) return;
    // closeBlend can fall back to another blend of the same target.
    final blend = await openBlends.blendClosedBy(signedOff.id) ?? rankedBlend;
    await analyses.update(
      signedOff.id,
      GasAnalysisEdit(
        desiredMix: blend.target,
        gasRole: blend.role,
        analysedBy: signedOff.analysedBy,
        notes: signedOff.notes,
        cylinderId: signedOff.cylinderId,
        fillPressureBar: signedOff.fillPressureBar,
        analysedFor: signedOff.analysedFor,
      ),
    );
  } catch (e) {
    debugPrint('Closing the blend on sign-off failed: $e');
  }
}
