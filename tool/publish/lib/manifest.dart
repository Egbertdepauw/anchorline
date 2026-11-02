/// Reads, changes and writes the two download lists that sit in the public
/// bucket: `releases/manifest.json` (desktop releases that are independent of
/// the stores) and `nightly/manifest.json`. Pure Dart, `dart:` libraries only,
/// so the publish command can run it with `dart tool/publish/publish.dart`
/// from any directory.
///
/// The file format is defined in
/// `docs/superpowers/specs/2026-10-07-website-design.md` (format 1):
///
/// ```json
/// {
///   "format": 1,
///   "latest": { "version": "1.2.0", "build": 45, "date": "2026-11-03",
///               "notes": "...", "files": { "windows-x64": { "url": "...",
///               "size": 1, "sha256": "..." } } },
///   "previous": [ { ...same entry shape... } ]
/// }
/// ```
///
/// Everything here is immutable: an operation never changes the manifest it
/// is given, it returns a new one.
library;

import 'dart:convert';

/// A publish step was refused, or a manifest could not be read. The message is
/// meant to be shown to the person running the command.
class PublishError implements Exception {
  const PublishError(this.message);

  final String message;

  @override
  String toString() => 'PublishError: $message';
}

/// Which list an artifact belongs to.
enum Lane { releases, nightly }

/// The version of the list format this library reads and writes.
const int manifestFormat = 1;

/// One downloadable file of a release. The platform it is for is the key in
/// [ReleaseEntry.files].
class FileEntry {
  const FileEntry({
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String url;
  final int size;
  final String sha256;

  Map<String, Object?> _toJson() => {
    'url': url,
    'size': size,
    'sha256': sha256,
  };
}

/// One published version: a release or a single nightly.
class ReleaseEntry {
  /// [files] is copied; later changes to the map passed in do not show up
  /// here. Throws [PublishError] when [date] is not a real `YYYY-MM-DD` date.
  ReleaseEntry({
    required this.version,
    required this.build,
    required this.date,
    required this.notes,
    required Map<String, FileEntry> files,
  }) : files = Map.unmodifiable(files) {
    _requireDate(date, 'date');
  }

  final String version;
  final int build;

  /// Calendar date (UTC) the entry was published, `YYYY-MM-DD`.
  final String date;

  /// Markdown release notes; empty when there are none.
  final String notes;

  /// Download per platform key (`windows-x64`, `linux-x64`, `macos`, ...).
  /// Keys this library does not know about are kept as they are.
  final Map<String, FileEntry> files;

  Map<String, Object?> _toJson() => {
    'version': version,
    'build': build,
    'date': date,
    'notes': notes,
    'files': {for (final e in files.entries) e.key: e.value._toJson()},
  };
}

/// A download list: the newest entry and the ones before it, newest first.
class Manifest {
  /// [previous] is copied; later changes to the list passed in do not show up
  /// here.
  Manifest({this.latest, List<ReleaseEntry> previous = const []})
    : previous = List.unmodifiable(previous);

  /// A list with nothing published yet.
  static Manifest empty() => Manifest();

  /// The newest entry, or null while nothing is published.
  final ReleaseEntry? latest;

  /// Earlier entries, newest first.
  final List<ReleaseEntry> previous;

  /// Reads a list as written by [encode]. Throws [PublishError] for malformed
  /// JSON, a `format` other than 1, or a missing or wrongly typed field.
  /// `latest` and `previous` may be absent; `notes` may be absent in an entry.
  static Manifest parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw PublishError('manifest is not valid JSON: ${e.message}');
    }
    final doc = _asObject(root, 'manifest');

    final format = doc['format'];
    if (format is! int || format != manifestFormat) {
      throw PublishError(
        'unsupported manifest format: ${format ?? 'missing'} '
        '(expected $manifestFormat)',
      );
    }

    final latestRaw = doc['latest'];
    final ReleaseEntry? latest = latestRaw == null
        ? null
        : _parseEntry(latestRaw, 'latest');

    final previousRaw = doc['previous'];
    final previous = <ReleaseEntry>[];
    if (previousRaw != null) {
      if (previousRaw is! List) {
        throw const PublishError('previous is not a list');
      }
      for (var i = 0; i < previousRaw.length; i++) {
        previous.add(_parseEntry(previousRaw[i], 'previous[$i]'));
      }
    }
    return Manifest(latest: latest, previous: previous);
  }

  /// Pretty JSON, 2-space indent, trailing newline, with a fixed key order so
  /// that publishing the same list twice writes the same bytes.
  String encode() {
    final doc = <String, Object?>{
      'format': manifestFormat,
      'latest': latest?._toJson(),
      'previous': [for (final e in previous) e._toJson()],
    };
    return '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
  }
}

/// Publishes [e] in the releases list.
///
/// [e] becomes `latest` only when nothing is published yet or its version is
/// higher than the latest's (compared numerically per component, so 1.10.0 is
/// above 1.9.0). Otherwise `latest` stays and [e] goes into `previous`: a
/// hotfix for an older line (1.1.1 while 1.2.0 is latest) must not turn into
/// a downgrade for everyone who opens the site. `previous` is always kept
/// sorted by version, newest first, so the old latest lands at the front in
/// the normal case.
///
/// A version that is already in the list is refused, unless [force] is set:
/// then that entry is replaced where it is (the latest stays the latest, a
/// previous entry keeps its slot). Throws [PublishError] when a version is not
/// of the form `X.Y.Z`.
Manifest addRelease(Manifest m, ReleaseEntry e, {bool force = false}) {
  PublishError already() => PublishError(
    'version ${e.version} is already published (use force to replace it)',
  );

  final version = _Version.parse(e.version);
  final latest = m.latest;
  if (latest != null && latest.version == e.version) {
    if (!force) throw already();
    return Manifest(latest: e, previous: _newestFirst(m.previous));
  }

  final i = m.previous.indexWhere((p) => p.version == e.version);
  if (i >= 0) {
    if (!force) throw already();
    return Manifest(
      latest: latest,
      previous: _newestFirst([...m.previous]..[i] = e),
    );
  }

  if (latest == null || version.compareTo(_Version.parse(latest.version)) > 0) {
    return Manifest(
      latest: e,
      previous: _newestFirst([?latest, ...m.previous]),
    );
  }
  return Manifest(latest: latest, previous: _newestFirst([...m.previous, e]));
}

/// Publishes [e] as the new latest nightly; the old latest moves to the front
/// of `previous`. Nightlies are unique by build number, and build numbers only
/// grow, so `previous` stays newest first. Afterwards every previous entry
/// (the old latest included) dated before [now] (as a UTC calendar date) minus
/// [keep] is dropped; the new entry itself is never dropped.
Manifest addNightly(
  Manifest m,
  ReleaseEntry e, {
  required DateTime now,
  Duration keep = const Duration(days: 14),
}) {
  final latest = m.latest;
  final existing = [?latest, ...m.previous];
  if (existing.any((x) => x.build == e.build)) {
    throw PublishError('nightly build ${e.build} is already published');
  }

  final cutoff = _dateOnly(now.toUtc()).subtract(keep);
  final previous = [
    for (final p in existing)
      if (!_parseDate(p.date)!.isBefore(cutoff)) p,
  ];
  return Manifest(latest: e, previous: previous);
}

/// Makes the earlier release [toVersion] the latest again, whatever its
/// version relative to the others. Every other entry, the old latest
/// included, goes to `previous`, sorted by version newest first; no entry is
/// lost or duplicated. The version has to be in `previous`.
Manifest rollback(Manifest m, String toVersion) {
  final latest = m.latest;
  if (latest != null && latest.version == toVersion) {
    throw PublishError('$toVersion is already the latest release');
  }
  final i = m.previous.indexWhere((p) => p.version == toVersion);
  if (i < 0) {
    throw PublishError('version $toVersion is not in the list of releases');
  }
  return Manifest(
    latest: m.previous[i],
    previous: _newestFirst([
      ?latest,
      ...m.previous.take(i),
      ...m.previous.skip(i + 1),
    ]),
  );
}

/// The object key (path in the bucket) of one installer.
///
/// * release: `releases/<V>/Anchorline-<V>-<platform>.<ext>`
/// * nightly: `nightly/<V>-<N>/Anchorline-Nightly-<V>-<N>-<platform>.<ext>`
///
/// where `<N>` is [build]. A release key does not depend on [build].
/// [extension] is given without a leading dot (`exe`, `AppImage`).
String objectKey({
  required Lane lane,
  required String version,
  required int build,
  required String platformKey,
  required String extension,
}) => switch (lane) {
  Lane.releases =>
    'releases/$version/Anchorline-$version-$platformKey.$extension',
  Lane.nightly =>
    'nightly/$version-$build/'
        'Anchorline-Nightly-$version-$build-$platformKey.$extension',
};

// --- parsing helpers --------------------------------------------------------

ReleaseEntry _parseEntry(Object? raw, String where) {
  final map = _asObject(raw, where);
  final date = _string(map, 'date', where);
  _requireDate(date, '$where.date');
  final build = _int(map, 'build', where);
  if (build <= 0) {
    throw PublishError('$where.build must be a positive integer, got $build');
  }
  return ReleaseEntry(
    version: _string(map, 'version', where),
    build: build,
    date: date,
    notes: map['notes'] == null ? '' : _string(map, 'notes', where),
    files: _parseFiles(map['files'], '$where.files'),
  );
}

Map<String, FileEntry> _parseFiles(Object? raw, String where) {
  final map = _asObject(raw, where);
  return {
    for (final e in map.entries) e.key: _parseFile(e.value, '$where.${e.key}'),
  };
}

FileEntry _parseFile(Object? raw, String where) {
  final map = _asObject(raw, where);
  final size = _int(map, 'size', where);
  if (size < 0) {
    throw PublishError('$where.size must not be negative, got $size');
  }
  return FileEntry(
    url: _string(map, 'url', where),
    size: size,
    sha256: _string(map, 'sha256', where),
  );
}

Map<String, Object?> _asObject(Object? value, String where) {
  if (value is Map) return value.cast<String, Object?>();
  throw PublishError('$where is missing or not an object');
}

String _string(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is String) return value;
  throw PublishError('$where.$key is missing or not a string');
}

int _int(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is int) return value;
  throw PublishError('$where.$key is missing or not an integer');
}

// --- versions ---------------------------------------------------------------

/// A version `major.minor.patch`, compared numerically per component.
class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch);

  /// Throws [PublishError] for anything that is not exactly `X.Y.Z`.
  factory _Version.parse(String text) {
    final m = _versionPattern.firstMatch(text);
    final major = int.tryParse(m?.group(1) ?? '');
    final minor = int.tryParse(m?.group(2) ?? '');
    final patch = int.tryParse(m?.group(3) ?? '');
    if (major == null || minor == null || patch == null) {
      throw PublishError("version must look like 1.2.3, got '$text'");
    }
    return _Version(major, minor, patch);
  }

  static final RegExp _versionPattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }
}

/// [entries] sorted by version, newest first. Entries with the same version
/// (only possible in a hand-edited file) keep their relative order.
List<ReleaseEntry> _newestFirst(Iterable<ReleaseEntry> entries) {
  final list = entries.toList();
  final decorated = [
    for (var i = 0; i < list.length; i++)
      (index: i, version: _Version.parse(list[i].version), entry: list[i]),
  ];
  decorated.sort((a, b) {
    final c = b.version.compareTo(a.version);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
  return [for (final d in decorated) d.entry];
}

// --- dates ------------------------------------------------------------------

final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Parses `YYYY-MM-DD` as midnight UTC; null for anything else, including
/// dates that do not exist (2026-02-31).
DateTime? _parseDate(String text) {
  final m = _datePattern.firstMatch(text);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

void _requireDate(String text, String where) {
  if (_parseDate(text) == null) {
    throw PublishError("$where must be a date like 2026-11-03, got '$text'");
  }
}

/// The calendar date of an instant that is already in UTC, as midnight UTC.
DateTime _dateOnly(DateTime utc) => DateTime.utc(utc.year, utc.month, utc.day);
