/// Publishes the legal texts from `docs/` and the user manual from
/// `docs/user/` to `content/` in the downloads bucket and keeps
/// `content/index.json` in step. Pure Dart, `dart:` libraries only.
///
/// The index is what the website reads, so it is written last: a publish that
/// stops half way leaves texts in the bucket that the index does not yet
/// describe, never an index that points to a missing text. Every text, page
/// and image is read and checked before anything is uploaded, so a broken
/// link or a missing image keeps the whole publish out of the bucket.
///
/// Manual objects that are no longer in the repository are deleted after the
/// index is written, and only under `content/docs/user/`: the manual is the
/// one part of the bucket this command owns completely.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Where the manual lives in the repository (relative to the repo root) and
/// in the bucket.
const String manualSourceDir = 'docs/user';
const String manualBucketPrefix = 'content/docs/user/';

/// Where the image sizes of the manual are written.
const String manualImagesKey = '${manualBucketPrefix}images.json';

final RegExp _slugPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');
final RegExp _imageTarget = RegExp(
  r'^images/([A-Za-z0-9][A-Za-z0-9._-]*\.png)$',
);
final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _inlineLink = RegExp(
  r'(!?)\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)',
);
final RegExp _pageLinkTarget = RegExp(
  r'^(?:/manual/([a-z0-9][a-z0-9-]*)|([a-z0-9][a-z0-9-]*)\.md)(?:#.*)?$',
);

/// One `[text](target)` or `![alt](target)` in a Markdown page.
class MarkdownLink {
  const MarkdownLink({
    required this.isImage,
    required this.text,
    required this.target,
  });

  final bool isImage;
  final String text;
  final String target;
}

/// The inline links and images of [markdown], skipping fenced code blocks.
/// Deliberately simple: reference-style links and links inside inline code
/// are not understood.
List<MarkdownLink> markdownLinks(String markdown) {
  final links = <MarkdownLink>[];
  var inFence = false;
  for (final line in const LineSplitter().convert(markdown)) {
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    for (final m in _inlineLink.allMatches(line)) {
      links.add(
        MarkdownLink(
          isImage: m.group(1) == '!',
          text: m.group(2)!,
          target: m.group(3)!,
        ),
      );
    }
  }
  return links;
}

/// The pixel size of a PNG, read from its IHDR chunk. Null when [bytes] is
/// not a PNG (signature, then an IHDR chunk of 13 bytes right after it).
({int width, int height})? pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(8) != 13) return null;
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) return null;
  return (width: width, height: height);
}

/// What the real git says about a file, as the website's "updated" date.
typedef CommitDate = Future<String?> Function(String relativePath);

/// The UTC date (`2026-03-05`) of the last commit that touched
/// [relativePath] in the repository at [repoRoot]; null when git has no
/// commit for it. Throws [PublishError] when git cannot run or fails (a
/// shallow clone does not fail, it just reports the date of the graft).
Future<String?> gitCommitDate(
  String repoRoot,
  String relativePath, {
  ProcessRunner? runner,
}) async {
  final run = runner ?? Process.run;
  final ProcessResult result;
  try {
    result = await run('git', [
      '-C',
      repoRoot,
      'log',
      '-1',
      '--format=%ct',
      '--',
      relativePath,
    ]);
  } on ProcessException catch (e) {
    throw PublishError('could not run git: ${e.message}');
  }
  if (result.exitCode != 0) {
    throw PublishError(
      'git log for $relativePath failed (exit code ${result.exitCode}): '
      '${'${result.stderr}'.trim()}',
    );
  }
  final output = '${result.stdout}'.trim();
  if (output.isEmpty) return null;
  final seconds = int.tryParse(output);
  if (seconds == null) {
    throw PublishError('git log for $relativePath printed "$output".');
  }
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// What a publish did (or, in a dry run, would do).
class ContentResult {
  const ContentResult({
    required this.indexJson,
    required this.uploadedKeys,
    this.deletedKeys = const [],
  });

  final String indexJson;

  /// The bucket keys written, in order, the index last.
  final List<String> uploadedKeys;

  /// The stale manual objects removed after the index was written, in order
  /// (in a dry run: the ones that would be).
  final List<String> deletedKeys;
}

class _ManualImage {
  _ManualImage(this.name, this.path, this.width, this.height);
  final String name;
  final String path;
  final int width;
  final int height;
}

class _ManualPage {
  _ManualPage(this.slug, this.body);
  final String slug;
  final String body;
}

class ContentPublisher {
  ContentPublisher(
    this.bucket, {
    required this.repoRoot,
    this.dryRun = false,
    Future<String?> Function(String relativePath)? commitDate,
  }) : _commitDate = commitDate ?? ((path) => gitCommitDate(repoRoot, path));

  final Bucket bucket;

  /// The repository checkout the texts are read from.
  final String repoRoot;
  final bool dryRun;

  final Future<String?> Function(String relativePath) _commitDate;

  /// Reads every text, manual page and image and refuses (naming the file)
  /// anything wrong with them. Then uploads the legal texts, the manual's
  /// images, `images.json` and the manual's pages, writes `content/index.json`
  /// and deletes the manual objects that are no longer in the repository. In a
  /// dry run the bucket is only read.
  ///
  /// A checkout without `docs/user/` publishes the legal texts only: nothing
  /// of the manual is listed or deleted then, so an old checkout can never
  /// wipe the published manual.
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

    final manualDir = Directory('$repoRoot/$manualSourceDir');
    final hasManual = manualDir.existsSync();
    final images = <_ManualImage>[];
    final pages = <_ManualPage>[];
    var imagesJson = '';
    if (hasManual) {
      await _readManual(manualDir, images, pages, entries);
      imagesJson = _encodeImageSizes(images);
    }
    final indexJson = encodeContentIndex(entries);

    final written = <String>[
      for (final t in texts) t.bucketKey,
      if (hasManual) ...[
        for (final i in images) '${manualBucketPrefix}images/${i.name}',
        manualImagesKey,
        for (final p in pages) '$manualBucketPrefix${p.slug}.md',
      ],
      contentIndexKey,
    ];

    if (!dryRun) {
      for (var i = 0; i < texts.length; i++) {
        await bucket.putText(
          texts[i].bucketKey,
          bodies[i],
          contentType: 'text/markdown; charset=utf-8',
          cacheControl: 'no-cache',
        );
      }
      if (hasManual) {
        for (final image in images) {
          await bucket.putFile(
            '${manualBucketPrefix}images/${image.name}',
            image.path,
            contentType: 'image/png',
            cacheControl: 'public, max-age=86400',
          );
        }
        await bucket.putText(
          manualImagesKey,
          imagesJson,
          contentType: 'application/json',
          cacheControl: 'no-cache',
        );
        for (final page in pages) {
          await bucket.putText(
            '$manualBucketPrefix${page.slug}.md',
            page.body,
            contentType: 'text/markdown; charset=utf-8',
            cacheControl: 'no-cache',
          );
        }
      }
      await bucket.putText(
        contentIndexKey,
        indexJson,
        contentType: 'application/json',
        cacheControl: 'no-cache',
      );
    }

    final deleted = <String>[];
    if (hasManual) {
      final keep = written.toSet();
      for (final key in await bucket.list(manualBucketPrefix)) {
        // Never touch anything outside the manual, whatever the bucket says.
        if (!key.startsWith(manualBucketPrefix) || keep.contains(key)) continue;
        deleted.add(key);
      }
      if (!dryRun) {
        for (final key in deleted) {
          await bucket.delete(key);
        }
      }
    }
    return ContentResult(
      indexJson: indexJson,
      uploadedKeys: written,
      deletedKeys: deleted,
    );
  }

  Future<void> _readManual(
    Directory dir,
    List<_ManualImage> images,
    List<_ManualPage> pages,
    Map<String, ContentIndexEntry> entries,
  ) async {
    const root = manualSourceDir;
    final pageNames = <String>[];
    for (final entity in dir.listSync()) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is! File) continue;
      if (!name.endsWith('.md')) continue;
      final slug = name.substring(0, name.length - 3);
      if (!_slugPattern.hasMatch(slug)) {
        throw PublishError(
          '$root/$name: the page name must be lowercase letters, digits and '
          'dashes.',
        );
      }
      pageNames.add(slug);
    }
    pageNames.sort();
    if (!pageNames.contains('index')) {
      throw PublishError('$root/index.md does not exist.');
    }

    final imageNames = <String>{};
    final imageDir = Directory('${dir.path}/images');
    if (imageDir.existsSync()) {
      final files = imageDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        if (!name.endsWith('.png')) continue;
        final size = pngSize(file.readAsBytesSync());
        if (size == null) {
          throw PublishError('$root/images/$name is not a valid PNG.');
        }
        imageNames.add(name);
        images.add(_ManualImage(name, file.path, size.width, size.height));
      }
    }

    for (final slug in pageNames) {
      final source = '$root/$slug.md';
      final body = File('$repoRoot/$source').readAsStringSync();
      final title = firstHeading(body);
      if (title == null) {
        throw PublishError('$source has no "# " heading.');
      }
      for (final link in markdownLinks(body)) {
        if (link.isImage) {
          if (link.text.trim().isEmpty) {
            throw PublishError(
              '$source: the image ${link.target} has no alt text.',
            );
          }
          final m = _imageTarget.firstMatch(link.target);
          if (m == null) {
            throw PublishError(
              '$source: the image ${link.target} must be a relative '
              'images/<name>.png path.',
            );
          }
          if (!imageNames.contains(m.group(1))) {
            throw PublishError(
              '$source: the image ${link.target} does not exist in '
              '$root/images/.',
            );
          }
          continue;
        }
        final m = _pageLinkTarget.firstMatch(link.target);
        if (m == null) continue;
        final target = m.group(1) ?? m.group(2)!;
        if (!pageNames.contains(target)) {
          throw PublishError(
            '$source: the link ${link.target} points to $root/$target.md, '
            'which does not exist.',
          );
        }
      }
      final updated = await _commitDate(source);
      if (updated == null) {
        throw PublishError('$source is not committed.');
      }
      pages.add(_ManualPage(slug, body));
      entries['docs/user/$slug'] = ContentIndexEntry(
        title: title,
        updated: updated,
        path: 'docs/user/$slug.md',
      );
    }
  }

  /// `{"images/<name>.png": {"width": W, "height": H}}`, keys sorted.
  String _encodeImageSizes(List<_ManualImage> images) {
    final sorted = [...images]..sort((a, b) => a.name.compareTo(b.name));
    final map = {
      for (final i in sorted)
        'images/${i.name}': {'width': i.width, 'height': i.height},
    };
    return '${const JsonEncoder.withIndent('  ').convert(map)}\n';
  }
}
