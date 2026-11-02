import 'dart:io';

import 'package:crypto/crypto.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/bucket.dart';

/// One call to [FakeBucket.putFile].
typedef FilePut = ({String key, String path, String contentType});

/// One call to [FakeBucket.putText].
typedef TextPut = ({
  String key,
  String text,
  String contentType,
  String? cacheControl,
});

/// In-memory [Bucket] for the publish tests. It records every call, in order,
/// as `<method> <key>` in [calls].
class FakeBucket implements Bucket {
  FakeBucket({Map<String, String>? texts}) : texts = {...?texts};

  /// Text objects (the manifests), by key.
  final Map<String, String> texts;

  /// sha256 of every file object, by key; what [sha256Of] answers unless
  /// [hashOverride] or [dropUploads] say otherwise.
  final Map<String, String> objects = {};

  /// Makes [sha256Of] report this hash for a key (a corrupted upload).
  final Map<String, String> hashOverride = {};

  /// Keys [putFile] pretends to store but does not (an upload that vanished).
  final Set<String> dropUploads = {};

  final List<String> calls = [];
  final List<FilePut> filePuts = [];
  final List<TextPut> textPuts = [];

  /// The calls that change the bucket.
  List<String> get putCalls => [
    for (final c in calls)
      if (c.startsWith('putFile ') || c.startsWith('putText ')) c,
  ];

  @override
  Future<String?> getText(String key) async {
    calls.add('getText $key');
    return texts[key];
  }

  @override
  Future<void> putFile(
    String key,
    String path, {
    required String contentType,
  }) async {
    calls.add('putFile $key');
    filePuts.add((key: key, path: path, contentType: contentType));
    if (dropUploads.contains(key)) return;
    objects[key] = sha256.convert(File(path).readAsBytesSync()).toString();
  }

  @override
  Future<void> putText(
    String key,
    String text, {
    required String contentType,
    String? cacheControl,
  }) async {
    calls.add('putText $key');
    textPuts.add((
      key: key,
      text: text,
      contentType: contentType,
      cacheControl: cacheControl,
    ));
    texts[key] = text;
  }

  @override
  Future<String?> sha256Of(String key) async {
    calls.add('sha256Of $key');
    return hashOverride[key] ?? objects[key];
  }
}
