// The output guard: a digest of what the mapping makes of each replayed
// Petrel 3 dive. A change to the mapping (or to the pinned libdivecomputer)
// changes the digests, and with them the dives a re-parse would give, so
// `kLibdcParserVersion` has to be bumped in the same change.
//
// To update after a deliberate change: bump `kLibdcParserVersion`, run this
// test, copy the digests it prints into `_digests` under the new version.
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:test/test.dart';

import 'support/digest.dart';
import 'support/petrel3_replay.dart';

/// Digests per parser version, in download order. Before the first tester
/// build ships no libdivecomputer dive exists, so version 1 may still change.
const _digests = <int, List<String>>{
  1: [
    '54bd883d2c162603d1c5ba6b402784a3a5959a52941093af1214877cd4fa08ba',
    '3ad4e8cfbd8fb431d31ae699436944ca68cd4702e3f425f9a4c80877e3fba1e6',
    '5ae792c327daea3051e1998d738341b2d777ee5c84892bfcb29edf126fafcea4',
    '95c3b536ab34d2dced01df4d527611a74b466d5a6e7478f33d4930488a3a9d3e',
    'f59cab6f17b2848a3f1eb1bc229d3d001e5c522500d1b698b37f72359c04da2a',
    '093bec1070618a78803503b96f9521eb8d93a230ef1021c945658fdba68569dc',
    '889300eeedb8d21ad30b16fca877dd4bf444a7525b29f228dde08372fe24268e',
    'be87c1c833d8b3c8f5f1af5b275d45049e501ce6fd66b6de87e5a0d32e57957c',
  ],
};

void main() {
  test('mapping output matches the digests for kLibdcParserVersion', () async {
    final dives = await replayPetrel3Dives();
    expect(dives, hasLength(8));
    final actual = [for (final d in dives) mappingDigest(d.converted!)];
    final want = _digests[kLibdcParserVersion];
    expect(
      want,
      isNotNull,
      reason:
          'libdivecomputer mapping output changed: bump kLibdcParserVersion '
          'and update these digests\nnew digests:\n${actual.join('\n')}',
    );
    expect(
      actual,
      want,
      reason:
          'libdivecomputer mapping output changed: bump kLibdcParserVersion '
          'and update these digests\nnew digests:\n${actual.join('\n')}',
    );
  });
}
