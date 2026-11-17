// One replay of the Petrel 3 trace, shared by the tests that look at its
// eight dives.
import 'package:libdivecomputer/libdivecomputer.dart';

import 'trace_link.dart';

/// The eight dives libdivecomputer decodes from the trace, in download order.
/// The trace stops inside a 9th dive, so the download ends in PROTOCOL.
Future<List<LibdcDiveDownloaded>> replayPetrel3Dives() async {
  final events = await collect(
    LibdcDownload.replay(descriptor: petrel3(), recording: petrelTrace()),
  );
  return divesOf(events);
}
