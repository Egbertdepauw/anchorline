/// Connection parameters sent to PowerSync on every connect. The Sync Streams
/// in `infra/powersync-sync-rules.yaml` read them via `connection.parameter()`.
///
/// `dc_engines` says which dive-computer engines this build can read:
///   * 1 = "this build reads Shearwater only". Rows with `dc_family` set
///     (libdivecomputer dives) are not sent to it.
///   * 2 = builds that also read libdivecomputer dives. Phase 2 sets this in
///     the same PR that makes the Subsurface writer skip libdivecomputer
///     dives.
/// Builds from before phase 1 send nothing, so they never match the gate.
const Map<String, Object> kSyncConnectionParams = {'dc_engines': 1};
