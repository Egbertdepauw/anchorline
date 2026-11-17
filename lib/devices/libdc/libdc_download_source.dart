/// A [DiveDownloadSource] over the libdivecomputer package's [LibdcDownload].
///
/// Nothing here is Bluetooth-specific: the caller hands in a
/// [LibdcConnection] and a way to close it, so the serial transports of phase
/// 3 reuse this class.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../dive_download_source.dart';
import '../fingerprint_store.dart';

/// libdivecomputer could not parse a dive that it did download. Carries only
/// the status, never dive data (it can reach Sentry).
class LibdcDiveParseFailed implements Exception {
  const LibdcDiveParseFailed(this.status);
  final LibdcStatus status;

  @override
  String toString() => 'LibdcDiveParseFailed(${status.name})';
}

/// The download as a whole ended with an error status. Thrown after
/// [DiveSourceFinished], so the dives that arrived are kept.
class LibdcDownloadFailed implements Exception {
  const LibdcDownloadFailed(this.status);
  final LibdcStatus status;

  @override
  String toString() => 'LibdcDownloadFailed(${status.name})';
}

/// What the source needs of a running download: its events, and a way to
/// stop it. [LibdcDownload] provides both.
class LibdcRun {
  const LibdcRun({required this.events, required this.cancel});

  final Stream<LibdcDownloadEvent> events;
  final void Function() cancel;
}

/// Starts a download. The default is [LibdcDownload.start]; tests pass a
/// scripted one.
typedef LibdcStarter =
    LibdcRun Function({
      required LibdcDescriptor descriptor,
      required LibdcConnection connection,
      required Map<int, Uint8List> knownFingerprints,
      required bool record,
    });

LibdcRun _startReal({
  required LibdcDescriptor descriptor,
  required LibdcConnection connection,
  required Map<int, Uint8List> knownFingerprints,
  required bool record,
}) {
  final download = LibdcDownload.start(
    descriptor: descriptor,
    connection: connection,
    knownFingerprints: knownFingerprints,
    record: record,
  );
  return LibdcRun(events: download.events, cancel: download.cancel);
}

const Duration _kCloseTimeout = Duration(seconds: 3);

class LibdcDownloadSource implements DiveDownloadSource {
  LibdcDownloadSource({
    required LibdcDescriptor descriptor,
    required LibdcConnection connection,
    required Future<void> Function() closeConnection,
    FingerprintStore? fingerprints,
    bool record = false,
    LibdcStarter? starter,
  }) : _descriptor = descriptor,
       _connection = connection,
       _closeConnection = closeConnection,
       _fingerprints = fingerprints,
       _record = record,
       _starter = starter ?? _startReal;

  final LibdcDescriptor _descriptor;
  final LibdcConnection _connection;
  final Future<void> Function() _closeConnection;

  /// Null means "download everything again".
  final FingerprintStore? _fingerprints;
  final bool _record;
  final LibdcStarter _starter;

  DcIdentity? _identity;
  LibdcRun? _run;
  Future<void>? _closing;

  @override
  DcIdentity? get identity => _identity;

  @override
  bool get canListDives => false;

  @override
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint}) =>
      throw UnsupportedError(
        'libdivecomputer cannot list dives before downloading them.',
      );

  String _key(int serial) => 'libdc:${_descriptor.family}:$serial';

  /// The saved fingerprints of this family, by the computer's serial number.
  Future<Map<int, Uint8List>> _known() async {
    final store = _fingerprints;
    if (store == null) return const {};
    final prefix = 'libdc:${_descriptor.family}:';
    final saved = await store.withPrefix(prefix);
    final out = <int, Uint8List>{};
    for (final e in saved.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final serial = int.tryParse(e.key.substring(prefix.length));
      if (serial != null) out[serial] = e.value;
    }
    return out;
  }

  /// Downloads from the computer. [selection] and [sinceFingerprint] are
  /// ignored: the saved fingerprints of the family decide where the download
  /// stops, and the computer's serial number is known only mid-download.
  @override
  Stream<DiveSourceEvent> download({
    List<DiveListing>? selection,
    Uint8List? sinceFingerprint,
  }) async* {
    final known = await _known();
    if (_closing != null) {
      // Closed while the saved fingerprints were loading: the link is gone.
      yield const DiveSourceFinished();
      return;
    }
    final run = _starter(
      descriptor: _descriptor,
      connection: _connection,
      knownFingerprints: known,
      record: _record,
    );
    _run = run;

    var dives = 0;
    Uint8List? newest;
    var serial = 0;
    await for (final event in run.events) {
      switch (event) {
        case LibdcDeviceInfo():
          serial = event.serial;
          final d = _descriptor;
          final id = DcIdentity(
            vendor: d.vendor,
            product: d.product,
            serial: serial,
            family: d.family,
            modelCode: event.model,
            firmware: event.firmware,
            dcModel: ShearwaterModel.unknown,
            computerModel: 0,
            importStateKey: _key(serial),
            modelLabel: '${d.vendor} ${d.product}',
            serialLabel: '$serial',
            firmwareLabel: '${event.firmware}',
          );
          _identity = id;
          yield DiveSourceIdentified(id);

        case LibdcProgress():
          yield DiveSourceProgress(
            diveIndex: dives,
            totalDives: null,
            diveBytes: event.current,
            diveTotalBytes: event.maximum,
          );

        case LibdcDiveDownloaded():
          dives++;
          // The computer sends the newest dive first.
          newest ??= event.envelope.fingerprint;
          final converted = event.converted;
          if (converted != null) {
            yield DiveSourceDive(
              listing: null,
              converted: converted,
              rawBlob: event.envelope.encode(),
              fingerprint: event.envelope.fingerprint,
              parserVersion: kLibdcParserVersion,
            );
          } else {
            yield DiveSourceDiveFailed(
              listing: null,
              error: LibdcDiveParseFailed(
                event.parseError ?? LibdcStatus.dataFormat,
              ),
              stack: StackTrace.current,
            );
          }

        case LibdcFinished():
          final clean =
              event.status == LibdcStatus.success ||
              event.status == LibdcStatus.done;
          yield DiveSourceFinished(
            importStateKey: _key(serial),
            fingerprintToKeep: clean ? newest : null,
            recordingText: event.recording.toText(),
          );
          if (!clean && event.status != LibdcStatus.cancelled) {
            throw LibdcDownloadFailed(event.status);
          }
      }
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      _run?.cancel();
    } catch (e) {
      debugPrint('libdivecomputer cancel failed (non-fatal): $e');
    }
    try {
      await _closeConnection().timeout(_kCloseTimeout);
    } catch (e) {
      debugPrint('Disconnect timed out / failed (non-fatal): $e');
    }
  }
}
