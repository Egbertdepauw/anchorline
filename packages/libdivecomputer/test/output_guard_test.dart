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
    '7843384de36634c596cf521cc9d9d6ee9ecffc127118bd730a6cf717dcba0a3b',
    'e1a4f18bf3a14582462071b68d5241293625efbf566314035de4a3a04ebfe89b',
    'a424735aeb184a8cf96f080ad28a64cb3d194737f11255a5b90b6e9fdccd2946',
    'f60c6dc40418be9d059725e0537309303d5652436e1ff157f85b4e9605a5be34',
    'ffd607866e8b7ab1ba9f8d5503ee83eac5cd3da30ab36e011c6928b0e9cadd10',
    'ab181a5871a64870feac22ba2c51f03cc8993d3edb66a818fa0fda3cfe970d38',
    '1748b8d53439b9ac28fcf1f4bb319d21378e8ebab97ff08138bdfd3dd03051d8',
    '3d0c66f86c800182da7adb16b5135b1329b189622f03ba5d9e2a8bc19c81a9fa',
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
