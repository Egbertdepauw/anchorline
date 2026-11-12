/// The planner safety warning (issue #184), in the spirit of the
/// disclaimers MultiDeco and V-Planner show.
///
/// [PlannerWarningGate] shows the full text and asks the diver to accept it
/// before the planner opens; [PlannerWarningLine] is the short reminder that
/// always sits under the planner's OUTPUT and opens the full text on the
/// website.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/safety_colors.dart';
import '../theme/tokens.dart';

/// Subject the acceptance is stored under in user_acknowledgements.
const String kPlannerWarningSubject = 'planner_warning';

/// Version of [kPlannerWarningText]. Bump it when the wording changes in a
/// way the diver must accept again; older acceptances then stop counting.
const int kPlannerWarningVersion = 1;

/// The full warning. Same text as the website (`PLANNER_WARNING` in
/// anchorline-web `src/content/home.ts`); keep the two in step.
const String kPlannerWarningText =
    'A plan from this planner can kill you. Anchorline does not guarantee '
    'that it follows the ZHL-16C or VPM-B models exactly, that it will '
    'protect you from decompression sickness, oxygen toxicity or death, or '
    'that its results are safe or correct. The planner is experimental and '
    'you use it entirely at your own risk. All diving carries risk, '
    'decompression diving more so, and deep mixed-gas diving with helium '
    'most of all. The planner is meant only for experienced divers trained '
    'in decompression and mixed-gas diving by a recognised technical '
    'training agency. If you do not have that training, or do not fully '
    'understand decompression planning, do not use its plans.';

/// The short reminder under OUTPUT.
const String kPlannerWarningShortText =
    'Experimental planner. A plan can kill you; use it at your own risk.';

/// Where the full text lives on the website.
final Uri kPlannerWarningUrl = Uri.parse('https://anchorline.eu/planner-warning');

/// Full-screen acceptance shown in place of the planner until the diver
/// accepts. There is no way past it other than [onAccept]; [onNotNow]
/// leaves the planner (hidden when null).
class PlannerWarningGate extends StatelessWidget {
  const PlannerWarningGate({
    super.key,
    required this.onAccept,
    this.onNotNow,
  });

  final VoidCallback onAccept;
  final VoidCallback? onNotNow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planner')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Only the text scrolls; the buttons stay in view on a
                // small phone.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, Spacing.lg, Spacing.lg, Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: SafetyColors.warning, size: 32),
                            SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Text(
                                'Read this before you plan a dive',
                                style: AppTypography.headline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Spacing.lg),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.palette.surfaceCard,
                            borderRadius: Radii.cardBr,
                            border: const Border(
                              left: BorderSide(
                                  color: SafetyColors.warning, width: 3),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(Spacing.md),
                            child: Text(
                              kPlannerWarningText,
                              key: ValueKey('planner-warning-text'),
                              style: AppTypography.body,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, 0, Spacing.lg, Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: const ValueKey('planner-warning-accept'),
                        onPressed: onAccept,
                        child: const Text('I understand and accept'),
                      ),
                      if (onNotNow != null) ...[
                        const SizedBox(height: Spacing.sm),
                        TextButton(
                          key: const ValueKey('planner-warning-not-now'),
                          onPressed: onNotNow,
                          child: const Text('Not now'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The short warning under OUTPUT. Tapping it opens the full text on the
/// website ([onOpen] replaces that, for tests).
class PlannerWarningLine extends StatelessWidget {
  const PlannerWarningLine({super.key, this.onOpen});

  final VoidCallback? onOpen;

  Future<void> _openFullText() async {
    try {
      await launchUrl(kPlannerWarningUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('PlannerWarningLine: could not open $kPlannerWarningUrl: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        key: const ValueKey('planner-warning-line'),
        onTap: onOpen ?? _openFullText,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: SafetyColors.warning, size: 16),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: '$kPlannerWarningShortText ',
                    children: [
                      TextSpan(
                        text: 'Full warning',
                        style: TextStyle(
                          color: context.palette.accentPrimary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                  style: AppTypography.caption
                      .copyWith(color: context.palette.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
