/// Top-of-screen banner that surfaces replication-slot WAL retention
/// before it hits Postgres's `max_slot_wal_keep_size` cap.
///
/// Hidden by default; renders when [SyncHealthService.snapshot] has
/// severity above `ok`. Two visual tiers: amber `warn` and red
/// `critical`. Tapping refreshes the snapshot.
library;

import 'package:flutter/material.dart';

import '../../sync/cloud/sync_health_service.dart';

class SyncHealthBanner extends StatelessWidget {
  final SyncHealthService service;

  const SyncHealthBanner({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final snap = service.snapshot;
        if (snap == null || !snap.shouldShowBanner) {
          return const SizedBox.shrink();
        }
        final isCritical = snap.severity == SyncHealthSeverity.critical;
        final bg = isCritical
            ? const Color(0xFFB71C1C)
            : const Color(0xFFE65100);
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
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text(body,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.refresh,
                        color: Colors.white70, size: 18),
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
