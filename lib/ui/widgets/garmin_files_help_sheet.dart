import 'package:flutter/material.dart';

/// "Where do I find them?": how to get dives out of a Garmin watch or a
/// Garmin account. It names Garmin's own pages only; the one tool it names
/// for Macs is an example, not a recommendation.
class GarminFilesHelpSheet extends StatelessWidget {
  const GarminFilesHelpSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const GarminFilesHelpSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fade = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(t,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        );
    Widget body(String t) => Text(t, style: TextStyle(color: fade));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Where do I find my Garmin dives?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              heading('One dive'),
              body('Open the Garmin Connect website, open the activity, '
                  'choose the gear menu and then "Export Original". You get a '
                  'zip with the .fit file in it.'),
              heading('Every dive at once'),
              body('In your Garmin account, open Data Management and choose '
                  '"Export Your Data". Garmin emails you a link, which can '
                  'take days. Pick the zip you download from it here.'),
              heading('From the watch, with its cable'),
              body('Connect the watch and open its Garmin/Activity folder. On '
                  'Windows use Explorer; on Linux use the file manager. A '
                  'Descent Mk1 shows up as a drive. On a Mac, a tool such as '
                  'OpenMTP can read the watch (named as an example, not '
                  'endorsed). Then pick the files or the whole folder here.'),
            ],
          ),
        ),
      ),
    );
  }
}
