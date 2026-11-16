/// Shearwater behind the common download shape.
library;

import 'dart:typed_data';

import 'package:subsurface_core/data/models/dive.dart' show generateDiveId;
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart'
    show kShearwaterVendor, shearwaterProductName;

import '../../shearwater/ble/shearwater_ble_transport.dart';
import '../../shearwater/ble/shearwater_link.dart';
import '../../shearwater/parser/dive_parser.dart';
import '../../shearwater/parser/manifest_parser.dart';
import '../../shearwater/parser/parser_version.dart';
import '../dive_download_source.dart';

class ShearwaterDownloadSource implements DiveDownloadSource {
  final ShearwaterLink _link;
  final DeviceInfo _info;
  final DcIdentity _identity;
  final int _serial;

  /// Manifest entries by dive id, so [download] can map a selection back.
  final Map<String, ManifestEntry> _entries = {};

  ShearwaterDownloadSource._(this._link, this._info, this._identity)
      : _serial = _identity.serial;

  /// Reads the device info, so [identity] is known at once.
  static Future<ShearwaterDownloadSource> open(ShearwaterLink link) async {
    final info = await link.readDeviceInfo();
    final model = info.model;
    final identity = DcIdentity(
      vendor: kShearwaterVendor,
      product: shearwaterProductName(model),
      serial: int.parse(info.serial, radix: 16),
      family: null,
      modelCode: info.hardwareId,
      firmware: _parseFirmwareVersion(info.firmware),
      dcModel: model,
      computerModel: info.hardwareId,
      importStateKey: info.serial,
      modelLabel: model.name,
      serialLabel: info.serial,
      firmwareLabel: info.firmware,
    );
    return ShearwaterDownloadSource._(link, info, identity);
  }

  static int? _parseFirmwareVersion(String firmware) {
    // "V103 DiveCAN" -> 103
    final m = RegExp(r'V(\d+)').firstMatch(firmware);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  @override
  DcIdentity get identity => _identity;

  @override
  bool get canListDives => true;

  DiveListing _listing(ManifestEntry e) => DiveListing(
        diveNumber: e.diveNumber,
        startTimestamp: e.startTimestamp,
        endTimestamp: e.endTimestamp,
        fingerprint: e.fingerprint,
        diveId: generateDiveId(_serial, e.diveNumber, e.startTimestamp),
      );

  @override
  Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint}) async {
    final manifest =
        await _link.readManifest(lastFingerprint: sinceFingerprint);
    _entries.clear();
    final listings = <DiveListing>[];
    for (final e in manifest.where((e) => e.isValid)) {
      final l = _listing(e);
      _entries[l.diveId] = e;
      listings.add(l);
    }
    return listings;
  }

  @override
  Stream<DiveSourceEvent> download({
    List<DiveListing>? selection,
    Uint8List? sinceFingerprint,
  }) async* {
    final List<DiveListing> chosen =
        selection ?? await listDives(sinceFingerprint: sinceFingerprint);
    final entries = <ManifestEntry>[];
    for (final l in chosen) {
      final e = _entries[l.diveId];
      if (e != null) entries.add(e);
    }

    final parser = ShearwaterDiveParser(model: _info.model);
    await for (final event in _link.downloadDives(entries)) {
      switch (event) {
        case DownloadProgressEvent():
          yield DiveSourceProgress(
            diveIndex: event.diveIndex,
            totalDives: event.totalDives,
            diveBytes: event.diveBytes,
            diveTotalBytes: event.diveTotalBytes,
            listing: _listing(event.currentEntry),
          );
        case DownloadedDive():
          final listing = _listing(event.manifest);
          try {
            final parsed = parser.parse(event.data);
            final converted = DiveConverter.convert(
              parsed: parsed,
              dcSerial: _serial,
              dcDiveNumber: event.manifest.diveNumber,
              dcModel: _info.model,
            );
            yield DiveSourceDive(
              listing: listing,
              converted: converted,
              rawBlob: event.data,
              fingerprint: event.manifest.fingerprint,
              parserVersion: kShearwaterParserVersion,
            );
          } catch (e, st) {
            yield DiveSourceDiveFailed(listing: listing, error: e, stack: st);
          }
      }
    }
  }

  @override
  Future<void> close() => _link.disconnect();
}
