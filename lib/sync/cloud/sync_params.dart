/// Connection parameters sent to PowerSync on every connect. The Sync Streams
/// in `infra/powersync-sync-streams.yaml` read them via `connection.parameter()`.
///
/// `dc_engines` says which dive-computer engines this build can read:
///   * 1 = phase 1 builds, which read Shearwater only. Rows with `dc_family`
///     set (libdivecomputer dives) are not sent to them.
///   * 2 = this build reads libdivecomputer dives, and its Subsurface writer
///     skips the ones it never pushed: a dive from another brand is only
///     merged into a dive Subsurface Cloud already has, never written as a
///     new one (`SyncPlanner.plan`).
/// Builds from before phase 1 send nothing, so they never match the gate.
const Map<String, Object> kSyncConnectionParams = {'dc_engines': 2};
