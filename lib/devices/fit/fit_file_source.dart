/// A [DiveDownloadSource] over picked FIT files, folders and Garmin exports.
///
/// The scan reads each FIT entry once: it classifies and maps it in an
/// isolate, keeps only the listing facts, and copies the file into
/// `workDir/dives`, so [download] never walks a zip again. At most one FIT
/// entry's bytes are held in memory outside an isolate call.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/subsurface_core.dart' show kFitDcFamily;

import '../dive_download_source.dart';
import 'fit_inputs.dart';
import 'zip_reader.dart';

/// The wall-clock epoch seconds the dive row stores.
int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Deletes leftover `fit-import-*` folders under [tempRoot], from imports
/// that never reached [FitFileSource.close].
Future<void> purgeStaleFitWorkDirs(Directory tempRoot) async {
  if (!await tempRoot.exists()) return;
  await for (final e in tempRoot.list(followLinks: false)) {
    if (e is! Directory) continue;
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (!name.startsWith('fit-import-')) continue;
    try {
      await e.delete(recursive: true);
    } catch (_) {
      // Best effort: a folder in use is purged on a later start.
    }
  }
}

/// A session that mapped but has nothing to show: no samples or no duration.
class FitDiveUnusable implements Exception {
  const FitDiveUnusable();

  @override
  String toString() => 'FitDiveUnusable';
}

// ── Isolate side ──────────────────────────────────────────────────────

/// What one session tells the listing. Plain data, sent back from an isolate.
class _Meta {
  _Meta({
    required this.diveId,
    required this.diveNumber,
    required this.start,
    required this.end,
    required this.fingerprint,
    required this.maxDepth,
    required this.durationSeconds,
    required this.manufacturer,
    required this.vendor,
    required this.product,
    required this.modelCode,
    required this.serial,
    required this.firmware,
  });

  final String diveId;
  final int diveNumber;
  final int start;
  final int end;
  final Uint8List fingerprint;
  final double maxDepth;
  final int durationSeconds;
  final int manufacturer;
  final String vendor;
  final String? product;
  final int? modelCode;
  final int serial;
  final int? firmware;

  String get modelLabel => product == null ? vendor : '$vendor $product';
}

enum _Kind { dive, apnea, other, unreadable }

class _Analysis {
  _Analysis(this.kind, [this.dives = const []]);

  final _Kind kind;
  final List<_Meta> dives;
}

Uint8List _hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

_Analysis _analyse(Uint8List bytes) {
  try {
    switch (classifyFit(bytes)) {
      case FitFileKind.apnea:
        return _Analysis(_Kind.apnea);
      case FitFileKind.otherActivity || FitFileKind.notActivity:
        return _Analysis(_Kind.other);
      case FitFileKind.dive:
        break;
    }
  } catch (_) {
    return _Analysis(_Kind.unreadable);
  }
  try {
    final file = readFitDives(bytes);
    final metas = <_Meta>[];
    for (final s in file.sessions) {
      final d = mapFitSession(file.id, s).dive;
      metas.add(
        _Meta(
          diveId: d.id,
          diveNumber: d.dcDiveNumber,
          start: _seconds(d.startTime),
          end: _seconds(d.endTime),
          fingerprint: _hexBytes(d.dcFingerprint ?? ''),
          maxDepth: d.maxDepthMeters,
          durationSeconds: d.duration.inSeconds,
          manufacturer: file.id.manufacturer,
          vendor: d.dcVendor ?? fitVendorName(file.id.manufacturer),
          product: d.dcProduct,
          modelCode: d.dcModelCode,
          serial: d.dcSerial,
          firmware: s.firmware,
        ),
      );
    }
    // A dive file with no dive session in it is as good as unreadable.
    if (metas.isEmpty) return _Analysis(_Kind.unreadable);
    return _Analysis(_Kind.dive, metas);
  } catch (_) {

    return _Analysis(_Kind.unreadable);
  }
}

/// The dive [diveId] of a file, fully mapped; null when it is not there.
ConvertedDive? _mapOne(Uint8List bytes, String diveId) {
  final file = readFitDives(bytes);
  for (final s in file.sessions) {
    final c = mapFitSession(file.id, s);
    if (c.dive.id == diveId) return c;
  }
  return null;
}

// The closures must not live in a method: a method's closure context holds
// `this`, which no isolate can receive.
Future<_Analysis> _analyseInIsolate(Uint8List bytes) =>
    Isolate.run(() => _analyse(bytes));

Future<ConvertedDive?> _mapOneInIsolate(Uint8List bytes, String diveId) =>
    Isolate.run(() => _mapOne(bytes, diveId));

// ── Source ────────────────────────────────────────────────────────────

class _Entry {
  _Entry(this.meta, this.path, this.source, this.fileName, this.order);

  final _Meta meta;
  final String path;
  final FitSource source;
  final String fileName;

  /// Position in scan order.
  final int order;
}

class FitFileSource implements DiveDownloadSource {
  FitFileSource({
    required List<FitInput> inputs,
    required Directory workDir,
    void Function(FitScanCounts)? onProgress,
  }) : _inputs = inputs,
       _workDir = workDir,
       _onProgress = onProgress;

  final List<FitInput> _inputs;
  final Directory _workDir;
  final void Function(FitScanCounts)? _onProgress;

  final FitScanCounts _counts = FitScanCounts();
  final Map<String, _Entry> _entries = {};
  Future<void>? _scan;
  bool _closed = false;
  int _copies = 0;
  int _temps = 0;
  DcIdentity? _identity;
  List<DiveListing> _listed = const [];

  @override
  DcIdentity? get identity => _identity;

  @override
  bool get canListDives => true;

  void _report() => _onProgress?.call(_counts.copy());

  Future<void> _ensureScanned() => _scan ??= _runScan();

  @override
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint}) async {
    await _ensureScanned();
    final list = [
      for (final e in _entries.values)
        DiveListing(
          diveNumber: e.meta.diveNumber,
          startTimestamp: e.meta.start,
          endTimestamp: e.meta.end,
          fingerprint: e.meta.fingerprint,
          diveId: e.meta.diveId,
          maxDepthMeters: e.meta.maxDepth,
          durationSeconds: e.meta.durationSeconds,
          modelLabel: e.meta.modelLabel,
        ),
    ]..sort((a, b) => b.startTimestamp.compareTo(a.startTimestamp));
    _listed = list;
    return list;
  }

  // ── Scan ──

  static bool _isFitName(String name) {
    final lower = name.toLowerCase();
    if (!lower.endsWith('.fit')) return false;
    if (lower.startsWith('__macosx/') || lower.contains('/__macosx/')) {
      return false;
    }
    final base = lower.substring(lower.lastIndexOf('/') + 1);
    return !base.startsWith('._');
  }

  static bool _isZipName(String name) => name.toLowerCase().endsWith('.zip');

  static String _baseName(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  Future<void> _runScan() async {
    // Gather the file work first, so the total is known for loose files.
    final work = <(String path, FitSource source)>[];
    for (final input in _inputs) {
      if (_closed) return;
      try {
        if (input is FitFolderInput) {
          final found = <String>[];
          // An entry that cannot be listed (a volume's .Trashes, say) counts
          // as one unreadable file and the listing goes on.
          await for (final e
              in Directory(input.path)
                  .list(recursive: true, followLinks: false)
                  .handleError((Object _) {
            _counts.filesTotal = (_counts.filesTotal ?? 0) + 1;
            _counts.filesRead++;
            _counts.unreadable++;
          })) {
            if (e is File &&
                (_isFitName(e.path) || _isZipName(e.path))) {
              found.add(e.path);
            }
          }
          found.sort();
          for (final p in found) {
            work.add((p, FitSource.folder));
          }
        } else {
          work.add((input.path, FitSource.file));
        }
      } catch (_) {
        _counts.filesTotal = (_counts.filesTotal ?? 0) + 1;
        _counts.filesRead++;
        _counts.unreadable++;
      }
    }
    var loose = 0;
    for (final w in work) {
      if (!_isZipName(w.$1)) loose++;
    }
    _counts.filesTotal = (_counts.filesTotal ?? 0) + loose;
    _report();

    for (final w in work) {
      if (_closed) return;
      if (_isZipName(w.$1)) {
        await _scanTopZip(w.$1, w.$2);
      } else {
        await _scanLooseFile(w.$1, w.$2);
      }
    }
    _counts.filesTotal = _counts.filesRead;
    _report();
  }

  void _countRead() {
    _counts.filesRead++;
    if ((_counts.filesTotal ?? 0) < _counts.filesRead) {
      _counts.filesTotal = _counts.filesRead;
    }
    _report();
  }

  Future<void> _scanLooseFile(String path, FitSource source) async {
    try {
      final bytes = await File(path).readAsBytes();
      await _take(bytes, _baseName(path), source);
    } catch (_) {
      _counts.unreadable++;
    }
    _countRead();
  }

  Future<void> _scanTopZip(String path, FitSource folderSource) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final zip = await ZipReader.open(raf);
      final fits = zip.entries.where(
        (e) => !e.isDirectory && _isFitName(e.name),
      );
      final hasZip = zip.entries.any(
        (e) => !e.isDirectory && _isZipName(e.name),
      );
      final source = (fits.length > 1 || hasZip)
          ? FitSource.accountExport
          : FitSource.connectExport;
      await _scanZip(zip, raf, source, 1);
    } catch (_) {
      // A zip that cannot be opened counts as one unreadable file.
      _counts.filesTotal = (_counts.filesTotal ?? 0) + 1;
      _counts.unreadable++;
      _countRead();
    } finally {
      await raf?.close();
    }
  }

  /// Walks one open zip. [depth] 1 is the picked zip; inner zips are opened
  /// down to depth 3 (two levels inside the picked one).
  Future<void> _scanZip(
    ZipReader zip,
    RandomAccessFile raf,
    FitSource source,
    int depth,
  ) async {
    final fits = zip.entries
        .where((e) => !e.isDirectory && _isFitName(e.name))
        .toList();
    _counts.filesTotal = (_counts.filesTotal ?? 0) + fits.length;
    _report();
    for (final e in zip.entries) {
      if (_closed) return;
      if (e.isDirectory) continue;
      if (_isFitName(e.name)) {
        try {
          final bytes = await zip.read(e);
          await _take(bytes, _baseName(e.name), source);
        } catch (_) {
          _counts.unreadable++;
        }
        _countRead();
      } else if (_isZipName(e.name) && !_baseName(e.name).startsWith('._')) {
        await _scanInnerZip(zip, raf, e, source, depth);
      }
    }
  }

  Future<void> _scanInnerZip(
    ZipReader zip,
    RandomAccessFile raf,
    ZipEntryInfo e,
    FitSource source,
    int depth,
  ) async {
    Future<void> broken() async {
      _counts.filesTotal = (_counts.filesTotal ?? 0) + 1;
      _counts.unreadable++;
      _countRead();
    }

    if (depth >= 3) return broken();
    if (_closed) return;
    File? temp;
    RandomAccessFile? ownRaf;
    try {
      final ZipReader inner;
      final RandomAccessFile innerRaf;
      if (e.isStored) {
        final span = zip.storedSpan(e);
        innerRaf = raf;
        inner = await ZipReader.open(
          raf,
          base: span.base,
          length: span.length,
        );
      } else {
        if (_closed) return;
        await _workDir.create(recursive: true);
        temp = File('${_workDir.path}/inner-${_temps++}.zip');
        await zip.extractTo(e, temp);
        ownRaf = await temp.open();
        innerRaf = ownRaf;
        inner = await ZipReader.open(ownRaf);
      }
      await _scanZip(inner, innerRaf, source, depth + 1);
    } catch (_) {
      await broken();
    } finally {
      await ownRaf?.close();
      if (temp != null) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  /// Classifies [bytes], and for a dive file lists its sessions and keeps
  /// a copy in the work folder.
  Future<void> _take(Uint8List bytes, String fileName, FitSource source) async {
    final a = await _analyseInIsolate(bytes);
    if (_closed) return;
    switch (a.kind) {
      case _Kind.unreadable:
        _counts.unreadable++;
      case _Kind.other:
        _counts.otherActivities++;
      case _Kind.apnea:
        _counts.apnea++;
      case _Kind.dive:
        final fresh = a.dives.where((m) => !_entries.containsKey(m.diveId));
        if (fresh.isEmpty) return;
        if (_closed) return;
        await Directory('${_workDir.path}/dives').create(recursive: true);
        final path = '${_workDir.path}/dives/${_copies++}.fit';
        await File(path).writeAsBytes(bytes, flush: false);
        for (final m in fresh) {
          _entries[m.diveId] = _Entry(
            m,
            path,
            source,
            fileName,
            _entries.length,
          );
          _counts.dives++;
        }
    }
  }

  // ── Download ──

  static String _firmwareLabel(int? fw) => fw == null
      ? ''
      : '${fw ~/ 100}.${(fw % 100).toString().padLeft(2, '0')}';

  DcIdentity _identityOf(_Meta m, int? firmware) => DcIdentity(
    vendor: m.vendor,
    product: m.product,
    serial: m.serial,
    family: kFitDcFamily,
    modelCode: m.modelCode,
    firmware: firmware,
    dcModel: ShearwaterModel.unknown,
    computerModel: 0,
    importStateKey: 'fit:${m.manufacturer}:${m.serial}',
    modelLabel: m.modelLabel,
    serialLabel: '${m.serial}',
    firmwareLabel: _firmwareLabel(firmware),
  );

  @override
  Stream<DiveSourceEvent> download({
    List<DiveListing>? selection,
    Uint8List? sinceFingerprint,
  }) async* {
    await _ensureScanned();
    final chosen = <_Entry>[];
    if (selection == null) {
      chosen.addAll(_entries.values);
    } else {
      final known = {for (final l in _listed) l.diveId};
      for (final l in selection) {
        final e = _entries[l.diveId];
        if (e == null || !known.contains(l.diveId)) {
          throw StateError('The selection holds a dive this source never listed');
        }
        chosen.add(e);
      }
    }

    // Watches in order of first appearance; each watch's dives oldest first.
    final watches = <String, List<_Entry>>{};
    for (final e in chosen..sort((a, b) => a.order.compareTo(b.order))) {
      watches
          .putIfAbsent('${e.meta.manufacturer}:${e.meta.serial}', () => [])
          .add(e);
    }
    var index = 0;
    final total = chosen.length;
    String? lastKey;
    for (final group in watches.values) {
      group.sort((a, b) => a.meta.start.compareTo(b.meta.start));
      int? firmware;
      // The newest dive's firmware wins: the group is oldest first.
      for (final e in group) {
        firmware = e.meta.firmware ?? firmware;
      }
      final id = _identityOf(group.first.meta, firmware);
      if (_closed) return;
      _identity = id;
      lastKey = id.importStateKey;
      yield DiveSourceIdentified(id);

      for (final e in group) {
        if (_closed) return;
        final listing = DiveListing(
          diveNumber: e.meta.diveNumber,
          startTimestamp: e.meta.start,
          endTimestamp: e.meta.end,
          fingerprint: e.meta.fingerprint,
          diveId: e.meta.diveId,
          maxDepthMeters: e.meta.maxDepth,
          durationSeconds: e.meta.durationSeconds,
          modelLabel: e.meta.modelLabel,
        );
        Uint8List? bytes;
        ConvertedDive? converted;
        Object? error;
        StackTrace stack = StackTrace.empty;
        try {
          bytes = await File(e.path).readAsBytes();
          converted = await _mapOneInIsolate(bytes, e.meta.diveId);
          if (converted == null ||
              converted.samples.sampleCount == 0 ||
              converted.dive.duration.inSeconds <= 0) {
            throw const FitDiveUnusable();
          }
        } catch (err, st) {
          error = err;
          stack = st;
        }
        index++;
        yield DiveSourceProgress(
          diveIndex: index,
          totalDives: total,
          diveBytes: bytes?.length ?? 0,
          diveTotalBytes: bytes?.length,
          listing: listing,
        );
        if (error != null || converted == null || bytes == null) {
          yield DiveSourceDiveFailed(
            listing: listing,
            error: error ?? const FitDiveUnusable(),
            stack: stack,
          );
          continue;
        }
        yield DiveSourceDive(
          listing: listing,
          converted: converted,
          rawBlob: FitEnvelope(
            source: e.source,
            fileName: e.fileName,
            fit: bytes,
          ).encode(),
          fingerprint: e.meta.fingerprint,
          parserVersion: kFitParserVersion,
        );
      }
    }
    yield DiveSourceFinished(
      importStateKey: lastKey,
      fingerprintToKeep: null,
      recordingText: null,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    // Let a running scan stop first, or it could recreate the folder.
    try {
      await _scan;
    } catch (_) {}
    try {
      if (await _workDir.exists()) await _workDir.delete(recursive: true);
    } catch (_) {
      // A later purgeStaleFitWorkDirs removes what is left.
    }
  }
}
