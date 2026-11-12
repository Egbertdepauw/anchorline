/// Publishes the legal texts from `docs/` to `content/` in the downloads
/// bucket and keeps `content/index.json` in step. Pure Dart, `dart:`
/// libraries only.
///
/// The index is what the website reads, so it is written last: a publish that
/// stops half way leaves texts in the bucket that the index does not yet
/// describe, never an index that points to a missing text. Every text is read
/// and checked before anything is uploaded.
library;

import 'dart:convert';
import 'dart:io';

import 'bucket.dart';
import 'manifest.dart' show PublishError;

/// A text published to `content/`. [key] is its index key, [source] the
/// repository path, [bucketKey] where it lands.
class ContentText {
  const ContentText({
    required this.key,
    required this.source,
    required this.bucketKey,
  });

  final String key;
  final String source;
  final String bucketKey;
}

/// The legal texts, in the order they are uploaded.
const List<ContentText> legalTexts = [
  ContentText(
    key: 'legal/privacy',
    source: 'docs/PRIVACY.md',
    bucketKey: 'content/legal/privacy.md',
  ),
  ContentText(
    key: 'legal/terms',
    source: 'docs/TERMS.md',
    bucketKey: 'content/legal/terms.md',
  ),
  ContentText(
    key: 'legal/account-deletion',
    source: 'docs/ACCOUNT_DELETION.md',
    bucketKey: 'content/legal/account-deletion.md',
  ),
];

/// Where the index lives in the bucket.
const String contentIndexKey = 'content/index.json';

/// One entry of `content/index.json`: [path] is relative to `content/`.
class ContentIndexEntry {
  const ContentIndexEntry({
    required this.title,
    required this.updated,
    required this.path,
  });

  final String title;

  /// ISO date, `2026-11-08`.
  final String updated;
  final String path;
}

const List<String> _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

final RegExp _lastUpdatedLine = RegExp(
  r'^_Last updated: (\d{1,2}) ([A-Za-z]+) (\d{4})_\s*$',
  multiLine: true,
);

/// `_Last updated: 8 November 2026_` as `2026-11-08`; null when there is no
/// such line or the date does not exist. Month names are English, in full or
/// the first three letters.
String? parseLastUpdated(String markdown) {
  final match = _lastUpdatedLine.firstMatch(markdown);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final name = match.group(2)!.toLowerCase();
  final year = int.parse(match.group(3)!);
  final index = _months.indexWhere(
    (m) => m == name || (name.length == 3 && m.startsWith(name)),
  );
  if (index < 0) return null;
  final month = index + 1;
  // DateTime rolls 31 February over to March; a date that does not survive
  // the round trip does not exist.
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

final RegExp _firstHeading = RegExp(r'^# +(.*\S)\s*$', multiLine: true);

/// The first `# ` heading, trimmed; null when there is none.
String? firstHeading(String markdown) =>
    _firstHeading.firstMatch(markdown)?.group(1);

/// `{"format": 1, "texts": {...}}` with the keys sorted, 2-space indent and a
/// trailing newline.
String encodeContentIndex(Map<String, ContentIndexEntry> entries) {
  final keys = entries.keys.toList()..sort();
  final texts = {
    for (final key in keys)
      key: {
        'title': entries[key]!.title,
        'updated': entries[key]!.updated,
        'path': entries[key]!.path,
      },
  };
  return '${const JsonEncoder.withIndent('  ').convert({'format': 1, 'texts': texts})}\n';
}

/// What a publish did (or, in a dry run, would do).
class ContentResult {
  const ContentResult({required this.indexJson, required this.uploadedKeys});

  final String indexJson;

  /// The bucket keys written, in order, the index last.
  final List<String> uploadedKeys;
}

class ContentPublisher {
  ContentPublisher(this.bucket, {required this.repoRoot, this.dryRun = false});

  final Bucket bucket;

  /// The repository checkout the texts are read from.
  final String repoRoot;
  final bool dryRun;

  /// Reads every text and refuses (naming the file) one that is missing, has
  /// no first heading or has no parseable last-updated line. Then uploads each
  /// text and writes `content/index.json` last. In a dry run nothing is
  /// written.
  Future<ContentResult> publish({List<ContentText> texts = legalTexts}) async {
    final bodies = <String>[];
    final entries = <String, ContentIndexEntry>{};
    for (final text in texts) {
      final file = File('$repoRoot/${text.source}');
      if (!file.existsSync()) {
        throw PublishError('${text.source} does not exist.');
      }
      final body = file.readAsStringSync();
      final title = firstHeading(body);
      if (title == null) {
        throw PublishError('${text.source} has no "# " heading.');
      }
      final updated = parseLastUpdated(body);
      if (updated == null) {
        throw PublishError(
          '${text.source} has no parseable "_Last updated: 8 November 2026_" '
          'line.',
        );
      }
      bodies.add(body);
      entries[text.key] = ContentIndexEntry(
        title: title,
        updated: updated,
        // Relative to content/.
        path: text.bucketKey.replaceFirst('content/', ''),
      );
    }
    final indexJson = encodeContentIndex(entries);

    if (!dryRun) {
      for (var i = 0; i < texts.length; i++) {
        await bucket.putText(
          texts[i].bucketKey,
          bodies[i],
          contentType: 'text/markdown; charset=utf-8',
          cacheControl: 'no-cache',
        );
      }
      await bucket.putText(
        contentIndexKey,
        indexJson,
        contentType: 'application/json',
        cacheControl: 'no-cache',
      );
    }
    return ContentResult(
      indexJson: indexJson,
      uploadedKeys: [for (final t in texts) t.bucketKey, contentIndexKey],
    );
  }
}
