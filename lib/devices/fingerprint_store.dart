/// Where an engine keeps the fingerprint of the newest dive it has imported
/// from each computer. Device-local state (it never syncs), so a fresh device
/// downloads everything once.
library;

import 'dart:typed_data';

abstract interface class FingerprintStore {
  /// Every saved fingerprint whose key starts with [prefix], by key.
  Future<Map<String, Uint8List>> withPrefix(String prefix);
}
