// The download isolate: runs libdivecomputer's blocking download on its own
// thread, over an al_link_t that the main isolate owns.
//
// Everything libdivecomputer calls back (the log, the device events, the
// dives) is a NativeCallable.isolateLocal: it runs synchronously on this
// isolate's thread, inside dc_device_open, dc_device_foreach or
// dc_device_close. Only the link's address crosses from the main isolate;
// the context, the descriptor, the iostream and the device are made and
// freed here. No Dart exception leaves a callback: each one catches, and
// either reports a parse error or cancels the download.
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:subsurface_core/subsurface_core.dart';

import '../bindings.g.dart' as c;
import '../dive_id.dart';
import '../envelope.dart';
import '../mapping/map_dive.dart';
import '../parse/descriptor_choice.dart';
import '../parse/parse_dive.dart';
import '../parse/status.dart';
import '../recording/recording.dart';
import '../upstream.g.dart';
import 'events.dart';

/// What the main isolate hands the download isolate.
final class DownloadArgs {
  DownloadArgs({
    required this.linkAddress,
    required this.vendor,
    required this.product,
    required this.family,
    required this.model,
    required this.advertisedName,
    required this.knownFingerprints,
    required this.record,
    required this.port,
  });

  /// The `al_link_t`; the main isolate keeps it alive until this isolate
  /// has exited.
  final int linkAddress;
  final String vendor;
  final String product;
  final int family;
  final int model;
  final String? advertisedName;

  /// Saved fingerprints by serial number (amendment 7).
  final Map<int, Uint8List> knownFingerprints;

  /// Log at INFO, and return the link's I/O events.
  final bool record;

  /// Gets every [LibdcDownloadEvent]; [LibdcFinished] comes last, with the
  /// isolate's exit.
  final SendPort port;
}

/// The isolate's entry point.
void downloadIsolateMain(DownloadArgs args) {
  final finished = _Download(args).run();
  Isolate.exit(args.port, finished);
}

/// The recording's header lines for a download.
List<String> recordingHeader({
  required String vendor,
  required String product,
  required int family,
  required int model,
  required String? advertisedName,
}) => [
  'descriptor $vendor|$product|$family|$model',
  if (advertisedName != null) 'advertised $advertisedName',
  'libdivecomputer $kLibdcPinnedCommit',
];

const _levelNames = {
  c.dc_loglevel_t.DC_LOGLEVEL_ERROR: 'ERROR',
  c.dc_loglevel_t.DC_LOGLEVEL_WARNING: 'WARNING',
  c.dc_loglevel_t.DC_LOGLEVEL_INFO: 'INFO',
  c.dc_loglevel_t.DC_LOGLEVEL_DEBUG: 'DEBUG',
};

final class _Download {
  _Download(this.args)
    : link = Pointer<c.al_link_t>.fromAddress(args.linkAddress);

  final DownloadArgs args;
  final Pointer<c.al_link_t> link;
  final log = <String>[];
  final envelopes = <LibdcEnvelope>[];

  LibdcDeviceInfo? _devinfo;
  ({int devtime, int systime})? _clock;
  LibdcProgress? _progress;
  var _failed = false;

  LibdcFinished run() {
    var status = c.dc_status_t.DC_STATUS_IO;
    Pointer<c.dc_context_t> context = nullptr;
    Pointer<c.dc_descriptor_t> descriptor = nullptr;
    Pointer<c.dc_iostream_t> iostream = nullptr;
    Pointer<c.dc_device_t> device = nullptr;
    final logCallable = NativeCallable<c.dc_logfunc_tFunction>.isolateLocal(
      _onLog,
    );
    final eventCallable =
        NativeCallable<c.dc_event_callback_tFunction>.isolateLocal(_onEvent);
    final diveCallable =
        NativeCallable<c.dc_dive_callback_tFunction>.isolateLocal(
          _onDive,
          exceptionalReturn: 0,
        );
    var events = const <LibdcIoEvent>[];
    try {
      status = using((arena) {
        final contextOut = arena<Pointer<c.dc_context_t>>();
        var rc = c.dc_context_new(contextOut);
        if (rc != c.dc_status_t.DC_STATUS_SUCCESS) return rc;
        context = contextOut.value;
        c.dc_context_set_loglevel(
          context,
          args.record
              ? c.dc_loglevel_t.DC_LOGLEVEL_INFO
              : c.dc_loglevel_t.DC_LOGLEVEL_WARNING,
        );
        c.dc_context_set_logfunc(context, logCallable.nativeFunction, nullptr);

        descriptor = _findDescriptor(context, args);
        if (descriptor == nullptr) {
          _note('libdivecomputer has no ${args.vendor} ${args.product}.');
          return c.dc_status_t.DC_STATUS_UNSUPPORTED;
        }

        final iostreamOut = arena<Pointer<c.dc_iostream_t>>();
        rc = c.al_link_iostream(link, context, iostreamOut);
        if (rc != c.dc_status_t.DC_STATUS_SUCCESS) return rc;
        iostream = iostreamOut.value;

        final deviceOut = arena<Pointer<c.dc_device_t>>();
        rc = c.dc_device_open(deviceOut, context, descriptor, iostream);
        if (rc != c.dc_status_t.DC_STATUS_SUCCESS) return rc;
        device = deviceOut.value;

        c.dc_device_set_cancel(
          device,
          Native.addressOf<NativeFunction<c.dc_cancel_callback_tFunction>>(
            c.al_link_cancelled,
          ),
          link.cast(),
        );
        c.dc_device_set_events(
          device,
          c.dc_event_type_t.DC_EVENT_PROGRESS |
              c.dc_event_type_t.DC_EVENT_DEVINFO |
              c.dc_event_type_t.DC_EVENT_CLOCK,
          eventCallable.nativeFunction,
          nullptr,
        );
        return c.dc_device_foreach(
          device,
          diveCallable.nativeFunction,
          nullptr,
        );
      });
    } catch (error) {
      _note('the download failed (${error.runtimeType}).');
      status = c.dc_status_t.DC_STATUS_IO;
    } finally {
      if (device != nullptr) {
        // Closing says goodbye to the computer; it can fail after a failed
        // download, and the download's own status is what counts.
        final rc = c.dc_device_close(device);
        if (rc != c.dc_status_t.DC_STATUS_SUCCESS) {
          _note(
            'closing the device returned ${LibdcStatus.fromCode(rc).name}.',
          );
        }
      }
      if (iostream != nullptr) c.dc_iostream_close(iostream);
      if (args.record) events = _recording();
      if (descriptor != nullptr) c.dc_descriptor_free(descriptor);
      if (context != nullptr) c.dc_context_free(context);
      diveCallable.close();
      eventCallable.close();
      logCallable.close();
    }
    if (_failed && status == c.dc_status_t.DC_STATUS_SUCCESS) {
      status = c.dc_status_t.DC_STATUS_CANCELLED;
    }
    return LibdcFinished(
      status: LibdcStatus.fromCode(status),
      recording: LibdcRecording(
        header: recordingHeader(
          vendor: args.vendor,
          product: args.product,
          family: args.family,
          model: args.model,
          advertisedName: args.advertisedName,
        ),
        events: events,
        log: log,
        envelopes: envelopes,
      ),
    );
  }

  /// A line of Anchorline's own in the log.
  void _note(String text) => log.add('ANCHORLINE: $text');

  /// Something in a callback threw: stop the download rather than let the
  /// exception reach libdivecomputer.
  void _fail(String where, Object error) {
    _failed = true;
    _note('$where failed (${error.runtimeType}); the download stops.');
    c.al_link_cancel(link);
  }

  List<LibdcIoEvent> _recording() {
    final size = c.al_link_recording(link, nullptr, 0);
    if (size == 0) return const [];
    return using((arena) {
      final buffer = arena<Uint8>(size);
      final copied = c.al_link_recording(link, buffer, size);
      if (copied != size) return const <LibdcIoEvent>[];
      try {
        return LibdcIoEvent.unpackAll(
          Uint8List.fromList(buffer.asTypedList(size)),
        );
      } on FormatException {
        _note('the recorded I/O does not read back.');
        return const <LibdcIoEvent>[];
      }
    });
  }

  void _onLog(
    Pointer<c.dc_context_t> context,
    int level,
    Pointer<Char> file,
    int line,
    Pointer<Char> function,
    Pointer<Char> message,
    Pointer<Void> userdata,
  ) {
    try {
      final text = _string(message);
      final name = _levelNames[level] ?? 'LOG';
      var where = '';
      if (level == c.dc_loglevel_t.DC_LOGLEVEL_ERROR ||
          level == c.dc_loglevel_t.DC_LOGLEVEL_WARNING) {
        // The file's name only: the build machine's path says nothing.
        final path = _string(file).replaceAll(r'\', '/');
        where = ' [in ${path.split('/').last}:$line (${_string(function)})]';
      }
      final lines = const LineSplitter().convert(text);
      if (lines.isEmpty) lines.add('');
      log.add('$name: ${lines.first}$where');
      for (final more in lines.skip(1)) {
        log.add('  $more');
      }
    } catch (_) {
      // A log line is not worth stopping a download for.
    }
  }

  static String _string(Pointer<Char> text) {
    if (text == nullptr) return '';
    final utf8Text = text.cast<Utf8>();
    return utf8.decode(
      utf8Text.cast<Uint8>().asTypedList(utf8Text.length),
      allowMalformed: true,
    );
  }

  void _onEvent(
    Pointer<c.dc_device_t> device,
    int event,
    Pointer<Void> data,
    Pointer<Void> userdata,
  ) {
    try {
      switch (event) {
        case c.dc_event_type_t.DC_EVENT_DEVINFO:
          final d = data.cast<c.dc_event_devinfo_t>().ref;
          final info = LibdcDeviceInfo(
            model: d.model,
            firmware: d.firmware,
            serial: d.serial,
          );
          _devinfo = info;
          args.port.send(info);
          // Amendment 7: the newest dive saved for this computer, so that
          // libdivecomputer stops there. Set from inside the event, before
          // the backend reads its manifest.
          final fingerprint = args.knownFingerprints[info.serial];
          if (fingerprint != null && fingerprint.isNotEmpty) {
            _setFingerprint(device, fingerprint);
          }
        case c.dc_event_type_t.DC_EVENT_CLOCK:
          final k = data.cast<c.dc_event_clock_t>().ref;
          _clock = (devtime: k.devtime, systime: k.systime);
        case c.dc_event_type_t.DC_EVENT_PROGRESS:
          final p = data.cast<c.dc_event_progress_t>().ref;
          _onProgress(p.current, p.maximum);
      }
    } catch (error) {
      _fail('the device event', error);
    }
  }

  void _setFingerprint(Pointer<c.dc_device_t> device, Uint8List fingerprint) {
    using((arena) {
      final buffer = arena<Uint8>(fingerprint.length);
      buffer.asTypedList(fingerprint.length).setAll(0, fingerprint);
      final rc = c.dc_device_set_fingerprint(
        device,
        buffer.cast(),
        fingerprint.length,
      );
      if (rc != c.dc_status_t.DC_STATUS_SUCCESS) {
        _note(
          'the saved fingerprint was refused '
          '(${LibdcStatus.fromCode(rc).name}); every dive is downloaded.',
        );
      }
    });
  }

  /// Posts progress only when the fraction rises. Backends adjust their
  /// estimate as they go (a Petrel adds a manifest page's worth of dives
  /// for every full page), which would move a progress bar backwards.
  void _onProgress(int current, int maximum) {
    if (maximum <= 0 || current < 0 || current > maximum) return;
    final last = _progress;
    if (last != null && current * last.maximum <= last.current * maximum) {
      return;
    }
    final progress = LibdcProgress(current: current, maximum: maximum);
    _progress = progress;
    args.port.send(progress);
  }

  int _onDive(
    Pointer<UnsignedChar> data,
    int size,
    Pointer<UnsignedChar> fingerprint,
    int fsize,
    Pointer<Void> userdata,
  ) {
    try {
      final info = _devinfo;
      final clock = _clock;
      final envelope = LibdcEnvelope(
        pinnedCommit: kLibdcPinnedCommit,
        vendor: args.vendor,
        product: args.product,
        family: args.family,
        descriptorModel: args.model,
        devinfoModel: info?.model,
        devinfoFirmware: info?.firmware,
        devinfoSerial: info?.serial,
        devtime: clock?.devtime,
        systime: clock?.systime,
        fingerprint: _copy(fingerprint, fsize),
        data: _copy(data, size),
      );
      final diveId = libdcDiveId(
        vendor: args.vendor,
        serial: info?.serial ?? 0,
        fingerprint: envelope.fingerprint,
      );
      ConvertedDive? converted;
      LibdcStatus? parseError;
      try {
        converted = mapLibdcDive(parseDive(envelope), envelope, diveId: diveId);
      } on LibdcParseException catch (e) {
        parseError = e.status;
      } catch (_) {
        parseError = LibdcStatus.dataFormat;
      }
      if (parseError != null) {
        _note(
          'dive ${envelopes.length + 1} did not parse (${parseError.name}).',
        );
      }
      envelopes.add(envelope);
      args.port.send(
        LibdcDiveDownloaded(
          envelope: envelope,
          diveId: diveId,
          converted: converted,
          parseError: parseError,
        ),
      );
      return 1;
    } catch (error) {
      _fail('the dive callback', error);
      return 0;
    }
  }

  static Uint8List _copy(Pointer<UnsignedChar> data, int size) {
    if (data == nullptr || size <= 0) return Uint8List(0);
    return Uint8List.fromList(data.cast<Uint8>().asTypedList(size));
  }
}

/// The descriptor to open the computer with, chosen by
/// [chooseDescriptorIndex] (vendor, product and model, else family and
/// model), the rule the parser uses too. Returns `nullptr` when there is
/// none; the caller frees the result.
Pointer<c.dc_descriptor_t> _findDescriptor(
  Pointer<c.dc_context_t> context,
  DownloadArgs args,
) {
  final all = <Pointer<c.dc_descriptor_t>>[];
  final table = <(String, String, int, int)>[];
  Pointer<c.dc_descriptor_t> chosen = nullptr;
  try {
    using((arena) {
      final iterator = arena<Pointer<c.dc_iterator_t>>();
      final item = arena<Pointer<c.dc_descriptor_t>>();
      if (c.dc_descriptor_iterator_new(iterator, context) !=
          c.dc_status_t.DC_STATUS_SUCCESS) {
        return;
      }
      final it = iterator.value;
      try {
        while (c.dc_iterator_next(it, item.cast()) ==
            c.dc_status_t.DC_STATUS_SUCCESS) {
          final d = item.value;
          all.add(d);
          table.add((
            c.dc_descriptor_get_vendor(d).cast<Utf8>().toDartString(),
            c.dc_descriptor_get_product(d).cast<Utf8>().toDartString(),
            c.dc_descriptor_get_type(d),
            c.dc_descriptor_get_model(d),
          ));
        }
      } finally {
        c.dc_iterator_free(it);
      }
    });
    final index = chooseDescriptorIndex(
      table,
      vendor: args.vendor,
      product: args.product,
      family: args.family,
      model: args.model,
    );
    if (index != null) chosen = all[index];
    return chosen;
  } finally {
    for (final d in all) {
      if (d != chosen) c.dc_descriptor_free(d);
    }
  }
}
