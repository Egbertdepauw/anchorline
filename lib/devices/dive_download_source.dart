/// One download shape for every dive computer engine.
///
/// The source opens a connection, downloads, parses, and emits a
/// [ConvertedDive] plus the raw blob per dive. The import notifier only
/// commits. Some engines (libdivecomputer) cannot list dives before
/// downloading and only learn the computer's identity during the download,
/// hence [DiveDownloadSource.canListDives] and [DiveSourceIdentified].
library;

import 'dart:typed_data';

import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

/// Who the connected computer is.
class DcIdentity {
  final String vendor;
  final String? product;
  final int serial;
  final int? family;
  final int? modelCode;
  final int? firmware;

  /// [ShearwaterModel.unknown] outside Shearwater.
  final ShearwaterModel dcModel;

  /// What `dive_computers.model` holds: the Shearwater hardware id.
  final int computerModel;

  /// Key for the per-computer import state (last fingerprint). Shearwater:
  /// the hex serial string, as before.
  final String importStateKey;

  /// Text for the import screen.
  final String modelLabel;
  final String serialLabel;
  final String firmwareLabel;

  const DcIdentity({
    required this.vendor,
    this.product,
    required this.serial,
    this.family,
    this.modelCode,
    this.firmware,
    required this.dcModel,
    required this.computerModel,
    required this.importStateKey,
    required this.modelLabel,
    required this.serialLabel,
    required this.firmwareLabel,
  });
}

/// A dive on the computer, as far as its listing tells.
class DiveListing {
  final int diveNumber;
  final int startTimestamp;
  final int endTimestamp;
  final Uint8List fingerprint;

  /// The computed dive id.
  final String diveId;

  const DiveListing({
    required this.diveNumber,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.fingerprint,
    required this.diveId,
  });
}

sealed class DiveSourceEvent {
  const DiveSourceEvent();
}

class DiveSourceProgress extends DiveSourceEvent {
  final int diveIndex;
  final int? totalDives;
  final int diveBytes;
  final int? diveTotalBytes;
  final DiveListing? listing;

  const DiveSourceProgress({
    required this.diveIndex,
    this.totalDives,
    required this.diveBytes,
    this.diveTotalBytes,
    this.listing,
  });
}

class DiveSourceIdentified extends DiveSourceEvent {
  final DcIdentity identity;

  const DiveSourceIdentified(this.identity);
}

class DiveSourceDive extends DiveSourceEvent {
  final DiveListing? listing;
  final ConvertedDive converted;
  final Uint8List rawBlob;
  final Uint8List fingerprint;
  final int parserVersion;

  const DiveSourceDive({
    required this.listing,
    required this.converted,
    required this.rawBlob,
    required this.fingerprint,
    required this.parserVersion,
  });
}

class DiveSourceDiveFailed extends DiveSourceEvent {
  final DiveListing? listing;
  final Object error;
  final StackTrace stack;

  const DiveSourceDiveFailed({
    required this.listing,
    required this.error,
    required this.stack,
  });
}

/// The end of a download, for engines that learn the result of the whole
/// download only at its end (libdivecomputer). Shearwater never emits it.
class DiveSourceFinished extends DiveSourceEvent {
  /// Where the fingerprint is saved. Null only when the download never
  /// started (the source was closed first).
  final String? importStateKey;

  /// The newest dive's fingerprint, to save once the import itself had no
  /// failed dive. Null after a cancel or a failed download.
  final Uint8List? fingerprintToKeep;

  /// The recording of the download as text: the log and every dive's
  /// envelope, plus every read and write when a recording was asked for.
  /// Null only when the download never started.
  final String? recordingText;

  const DiveSourceFinished({
    this.importStateKey,
    this.fingerprintToKeep,
    this.recordingText,
  });
}

abstract class DiveDownloadSource {
  /// Null until the computer is known (libdivecomputer learns it during the
  /// download and announces it with [DiveSourceIdentified]).
  DcIdentity? get identity;

  bool get canListDives;

  /// Throws [UnsupportedError] when [canListDives] is false.
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint});

  /// Downloads [selection] (every dive when null, or when the engine cannot
  /// list), newer than [sinceFingerprint] when given.
  ///
  /// A [selection] entry must have been returned by this source's latest
  /// [listDives]; any other entry makes the stream throw a [StateError].
  ///
  /// Cancelling the subscription stops delivery but does not disconnect;
  /// only [close] does.
  Stream<DiveSourceEvent> download({
    List<DiveListing>? selection,
    Uint8List? sinceFingerprint,
  });

  /// Disconnects. Idempotent and time-bounded: safe to call twice, and it
  /// returns even when the device never acknowledges the shutdown.
  Future<void> close();
}
