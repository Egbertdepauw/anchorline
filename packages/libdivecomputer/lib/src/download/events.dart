import 'package:meta/meta.dart';
import 'package:subsurface_core/subsurface_core.dart';

import '../descriptors.dart';
import '../envelope.dart';
import '../parse/status.dart';
import '../recording/recording.dart';

/// What a download reports, in order. [LibdcFinished] is always the last.
sealed class LibdcDownloadEvent {
  const LibdcDownloadEvent();
}

/// How far the download is. The fraction [current] / [maximum] only rises:
/// the session drops any report from libdivecomputer that would lower it.
final class LibdcProgress extends LibdcDownloadEvent {
  const LibdcProgress({required this.current, required this.maximum});

  final int current;
  final int maximum;

  @override
  String toString() => 'LibdcProgress($current/$maximum)';
}

/// The computer's model, firmware and serial number (`DC_EVENT_DEVINFO`).
final class LibdcDeviceInfo extends LibdcDownloadEvent {
  const LibdcDeviceInfo({
    required this.model,
    required this.firmware,
    required this.serial,
  });

  final int model;
  final int firmware;
  final int serial;

  @override
  String toString() => 'LibdcDeviceInfo(model $model, firmware $firmware)';
}

/// One dive as the computer sent it. [envelope] is the raw blob to store.
/// [converted] is null exactly when [parseError] is set: libdivecomputer's
/// parser failed with that status, or the mapping failed (`dataFormat`).
final class LibdcDiveDownloaded extends LibdcDownloadEvent {
  const LibdcDiveDownloaded({
    required this.envelope,
    required this.diveId,
    this.converted,
    this.parseError,
    this.debugLegacyConverted,
  });

  final LibdcEnvelope envelope;
  final String diveId;
  final ConvertedDive? converted;
  final LibdcStatus? parseError;

  /// Only set by the test-only legacy-parser replay: the same dive parsed
  /// with `dc_parser_new(device)` inside the foreach callback.
  @visibleForTesting
  final ConvertedDive? debugLegacyConverted;

  @override
  String toString() =>
      'LibdcDiveDownloaded($diveId, '
      '${parseError == null ? 'parsed' : parseError!.name})';
}

/// The end of the download: libdivecomputer's status for the whole of it
/// (`dc_device_foreach`), and what it left behind. Comes once every native
/// resource of the download is released.
final class LibdcFinished extends LibdcDownloadEvent {
  const LibdcFinished({
    required this.status,
    required this.recording,
    this.descriptor,
  });

  final LibdcStatus status;
  final LibdcRecording recording;

  /// The descriptor the computer was opened with, or null when none was.
  /// It can differ from the one the download was started with: the lookup
  /// matches vendor, product and model first, then family and model, so a
  /// stale family number or name still opens the right one. Its family is
  /// the one every envelope carries, and the one to save the newest
  /// fingerprint under (`libdc:<family>:<serial>`).
  final LibdcDescriptor? descriptor;

  @override
  String toString() => 'LibdcFinished(${status.name})';
}
