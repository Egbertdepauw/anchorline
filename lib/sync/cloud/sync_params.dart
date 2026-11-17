/// Connection parameters sent to PowerSync on every connect. The Sync Streams
/// in `infra/powersync-sync-streams.yaml` read them via `connection.parameter()`.
///
/// `dc_engines` says which dive-computer engines this build can read:
///   * 1 = "this build reads Shearwater only". Rows with `dc_family` set
///     (libdivecomputer dives) are not sent to it.
///   * 2 = builds that also read libdivecomputer dives. PR D of phase 2 sets
///     2 together with the first code that creates libdivecomputer dives;
///     the Subsurface writer here already skips or merges them as phase 2
///     requires.
/// Builds from before phase 1 send nothing, so they never match the gate.
const Map<String, Object> kSyncConnectionParams = {'dc_engines': 1};
