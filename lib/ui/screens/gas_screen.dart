/// The Gas destination: Blend | Analyse | Log under one [TabTopBar].
///
/// The bar's anchor goes home. The tab bodies are kept alive, so the Analyse
/// tab's save card (which hands Log on OK the setup to save with) stays
/// mounted while another tab is showing. The analyzer connection and the
/// logger themselves live in the shell-owned [AnalyzerSession].
library;

import 'package:flutter/material.dart';

import '../../data/db/gas_analyses_dao.dart';
import '../../data/db/open_blends_dao.dart';
import '../../labels/label_print_service.dart';
import '../components/tab_top_bar.dart';
import '../notifiers/analyzer_session.dart';
import '../notifiers/blend_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'analyzer_screen.dart';
import 'blend_screen.dart';
import 'gas_analysis_log_screen.dart';

/// The colour of the connection dot: green while connected, the accent while
/// Log on OK is running.
Color _connectionDotColor(BuildContext context, bool okRunning) =>
    okRunning ? context.palette.accentPrimary : SafetyColors.success;

/// The bottom-nav item of the Gas destination. A small dot says the analyzer
/// is connected while another destination is showing.
BottomNavigationBarItem gasNavItem({
  required bool connected,
  required bool okRunning,
  required bool selected,
}) {
  const icon = Icon(Icons.science_outlined);
  return BottomNavigationBarItem(
    label: 'Gas',
    icon: connected && !selected
        ? Builder(
            builder: (context) => Badge(
              key: const ValueKey('nav-gas-dot'),
              smallSize: 8,
              backgroundColor: _connectionDotColor(context, okRunning),
              child: icon,
            ),
          )
        : icon,
  );
}

class GasScreen extends StatelessWidget {
  const GasScreen({
    super.key,
    required this.blend,
    required this.settings,
    required this.session,
    required this.onHome,
    this.analysesDao,
    this.openBlendsDao,
    this.labelPrinting,
  });

  final BlendNotifier blend;
  final SettingsNotifier settings;
  final AnalyzerSession session;
  final VoidCallback onHome;

  /// The cylinder analysis log for the Log tab.
  final GasAnalysesDaoLike? analysesDao;

  /// The open blends, for the Blend tab and its count badge.
  final OpenBlendsDaoLike? openBlendsDao;
  final LabelPrintService? labelPrinting;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: TabTopBar(
          onHome: onHome,
          tabs: [
            _GasTab(
              key: const ValueKey('gas-tab-blend'),
              icon: Icons.tune,
              label: 'Blend',
              count: openBlendsDao == null
                  ? null
                  : _OpenCount(dao: openBlendsDao!),
            ),
            ListenableBuilder(
              listenable: session,
              builder: (context, _) => _GasTab(
                key: const ValueKey('gas-tab-analyse'),
                icon: Icons.sensors,
                label: 'Analyse',
                dotColor: session.controller.isConnected
                    ? _connectionDotColor(context, session.okRunning)
                    : null,
              ),
            ),
            const _GasTab(
              key: ValueKey('gas-tab-log'),
              icon: Icons.history,
              label: 'Log',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _KeepAlive(BlendScreen(
                notifier: blend, settings: settings, openBlends: openBlendsDao)),
            _KeepAlive(AnalyzerScreen(
                settings: settings, session: session, blend: blend)),
            _KeepAlive(analysesDao == null
                ? const Center(child: Text('No analysis log on this device.'))
                : GasAnalysisLogScreen(
                    dao: analysesDao!,
                    labelPrinting: labelPrinting,
                    embedded: true,
                    blend: blend,
                  )),
          ],
        ),
      ),
    );
  }
}

/// A tab with an icon and a label on one row, and an optional dot after it.
/// A [Row] rather than [Tab.icon] so it fits the 56 pt bar.
class _GasTab extends StatelessWidget {
  const _GasTab({super.key,
      required this.icon,
      required this.label,
      this.dotColor,
      this.count});

  final IconData icon;
  final String label;
  final Color? dotColor;

  /// A count badge after the label.
  final Widget? count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: Spacing.xs),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (count != null) ...[
            const SizedBox(width: Spacing.xs),
            count!,
          ],
          if (dotColor != null) ...[
            const SizedBox(width: Spacing.xs),
            Container(
              key: const ValueKey('gas-tab-analyse-dot'),
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}

/// The number of open blends, as a small badge; nothing at 0.
class _OpenCount extends StatefulWidget {
  const _OpenCount({required this.dao});

  final OpenBlendsDaoLike dao;

  @override
  State<_OpenCount> createState() => _OpenCountState();
}

class _OpenCountState extends State<_OpenCount> {
  late Stream<List<OpenBlend>> _stream = widget.dao.watchOpen();

  @override
  void didUpdateWidget(_OpenCount old) {
    super.didUpdateWidget(old);
    if (old.dao != widget.dao) _stream = widget.dao.watchOpen();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OpenBlend>>(
      stream: _stream,
      builder: (context, snap) {
        final n = snap.data?.length ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Badge(
          key: const ValueKey('gas-tab-blend-count'),
          label: Text('$n'),
          backgroundColor: context.palette.accentPrimary,
        );
      },
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child);

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
