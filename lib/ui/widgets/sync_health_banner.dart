/// Top-of-screen banner that surfaces replication-slot WAL retention
/// before it hits Postgres's `max_slot_wal_keep_size` cap.
///
/// Hidden by default; renders when [SyncHealthService.snapshot] has
/// severity above `ok`. Two visual tiers: amber `warn` and red
/// `critical`. Tapping refreshes the snapshot.
library;

import 'package:flutter/material.dart';

import '../../sync/cloud/sync_health_service.dart';
import '../theme/safety_colors.dart';

class SyncHealthBanner extends StatelessWidget {
  final SyncHealthService service;

  const SyncHealthBanner({super.key, required this.service});

  /// Whether the banner shows for [service]'s snapshot now.
  static bool showsFor(SyncHealthService service) =>
      service.snapshot?.shouldShowBanner ?? false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final snap = service.snapshot;
        if (snap == null || !showsFor(service)) {
          return const SizedBox.shrink();
        }
        final isCritical = snap.severity == SyncHealthSeverity.critical;
        final bg = isCritical
            ? SafetyColors.alertCriticalSurface
            : SafetyColors.alertWarningSurface;
        final icon = isCritical ? Icons.error_outline : Icons.warning_amber;
        final mb = snap.worst?.retainedMb ?? 0;
        final lost = snap.worst?.walStatus == 'lost';

        final title = isCritical
            ? (lost
                ? 'Sync queue invalidated'
                : 'Sync queue critical ($mb MB)')
            : 'Sync queue building up ($mb MB)';

        final body = isCritical
            ? (lost
                ? 'PowerSync will re-bootstrap on next reconnect. Your local data is safe.'
                : 'Approaching the WAL retention cap. PowerSync may re-bootstrap soon.')
            : 'Keep the app open so PowerSync can drain the upload queue.';

        return Material(
          color: bg,
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () => service.refresh(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, color: SafetyColors.onAlert, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: SafetyColors.onAlert,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text(body,
                              style: TextStyle(
                                  color: SafetyColors.onAlert
                                      .withValues(alpha: 0.7),
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.refresh,
                        color: SafetyColors.onAlert.withValues(alpha: 0.7),
                        size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [SyncHealthBanner] above [child], the app shell's body.
///
/// While the banner shows, its [SafeArea] takes the status-bar inset, so
/// [child] is told there is none left above it. A destination with no shell
/// app bar and a top bar of its own (Gas, Settings) would otherwise add the
/// inset a second time.
class SyncHealthBannerColumn extends StatelessWidget {
  const SyncHealthBannerColumn({
    super.key,
    required this.service,
    required this.child,
  });

  final SyncHealthService service;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        children: [
          SyncHealthBanner(service: service),
          Expanded(
            // Always a MediaQuery, shown or not, so the banner coming and
            // going keeps the state of [child].
            child: MediaQuery.removePadding(
              context: context,
              removeTop: SyncHealthBanner.showsFor(service),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
