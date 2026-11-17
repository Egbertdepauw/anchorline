import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bindings.g.dart' as c;

/// A request the main isolate took from a live link.
final class LinkRequest {
  const LinkRequest(this.id, this.kind, this.data, this.uuid);

  /// Nonzero; [NativeLink.complete] completes only this request.
  final int id;

  /// `AL_REQ_WRITE`, `AL_REQ_CHAR_READ` or `AL_REQ_CHAR_WRITE`.
  final int kind;

  /// What to write; empty for a characteristic read.
  final Uint8List data;

  /// The characteristic; empty for a plain write.
  final String uuid;
}

/// The main isolate's handle on an `al_link_t`.
///
/// Every call is refused once [free] ran: a late notification, completion,
/// disconnect or cancel then does nothing (and counts in
/// [refusedAfterFree]) instead of touching freed memory. The C layer can't
/// guard against that, so this is the only place that calls `al_link_*`
/// from the main isolate.
///
/// Requests are taken with [take] and completed by their id with
/// [complete]. The C layer completes only the request that id names, so a
/// late completion of a request that timed out lands nowhere.
final class NativeLink {
  NativeLink._(this._link);

  /// A live link whose requests go to [request]; null when the C layer
  /// can't make one.
  static NativeLink? live(
    String? advertisedName,
    Pointer<NativeFunction<c.al_request_fnFunction>> request,
  ) {
    final link = using(
      (arena) => c.al_link_new_live(_name(advertisedName, arena), request),
    );
    return link == nullptr ? null : NativeLink._(link);
  }

  /// A replay link serving [events] (the C layer's packed layout); null when
  /// the layout is malformed.
  static NativeLink? replay(String? advertisedName, Uint8List events) {
    final link = using((arena) {
      final buffer = arena<Uint8>(events.isEmpty ? 1 : events.length);
      buffer.asTypedList(events.length).setAll(0, events);
      return c.al_link_new_replay(
        _name(advertisedName, arena),
        buffer,
        events.length,
      );
    });
    return link == nullptr ? null : NativeLink._(link);
  }

  static Pointer<Char> _name(String? name, Arena arena) =>
      name == null ? nullptr : name.toNativeUtf8(allocator: arena).cast();

  final Pointer<c.al_link_t> _link;
  var _freed = false;

  /// How many calls came after [free] and were refused.
  int refusedAfterFree = 0;

  bool get isFreed => _freed;

  /// The link's address, for the download isolate.
  int get address => _link.address;

  bool _refused() {
    if (!_freed) return false;
    refusedAfterFree++;
    return true;
  }

  /// Takes the request waiting in the link, or returns null when none is.
  /// Its kind is the one al_link_pending reports, never the request
  /// callback's, which can be stale.
  LinkRequest? take() {
    if (_refused()) return null;
    return using((arena) {
      final uuid = arena<Char>(c.DC_BLE_UUID_SIZE);
      final id = arena<Int64>();
      final kind = arena<Int32>();
      var capacity = 0;
      Pointer<Uint8> data = nullptr;
      while (true) {
        final n = c.al_link_pending(
          _link,
          data,
          capacity,
          uuid,
          c.DC_BLE_UUID_SIZE,
          id,
          kind,
        );
        if (id.value == -1) {
          // Too small: nothing was taken. Ask again with room for it (the
          // request may have changed in between; the loop handles that).
          // The UUID buffer always has DC_BLE_UUID_SIZE, so only the data
          // can be too small, and then it needs more than it has.
          if (n <= capacity) return null;
          capacity = n;
          data = n == 0 ? nullptr : arena<Uint8>(n);
          continue;
        }
        if (id.value <= 0) return null;
        return LinkRequest(
          id.value,
          kind.value,
          Uint8List.fromList(data == nullptr ? const [] : data.asTypedList(n)),
          uuid.cast<Utf8>().toDartString(),
        );
      }
    });
  }

  /// Completes request [id] with [status] (a `dc_status_t`), and for a
  /// characteristic read with [value]. The C layer ignores it unless [id]
  /// is the request its blocking thread still waits for.
  void complete(int id, int status, [Uint8List? value]) {
    if (_refused()) return;
    using((arena) {
      final size = value?.length ?? 0;
      Pointer<Uint8> data = nullptr;
      if (size > 0) {
        data = arena<Uint8>(size);
        data.asTypedList(size).setAll(0, value!);
      }
      c.al_link_complete(_link, id, status, data, size);
    });
  }

  /// A notification from the computer.
  void push(Uint8List packet) {
    if (_refused() || packet.isEmpty) return;
    using((arena) {
      final data = arena<Uint8>(packet.length);
      data.asTypedList(packet.length).setAll(0, packet);
      c.al_link_push(_link, data, packet.length);
    });
  }

  void disconnected() {
    if (_refused()) return;
    c.al_link_disconnected(_link);
  }

  void cancel() {
    if (_refused()) return;
    c.al_link_cancel(_link);
  }

  void setWriteTimeout(int milliseconds) {
    if (_refused()) return;
    c.al_link_set_write_timeout(_link, milliseconds);
  }

  void setRecording(bool enabled) {
    if (_refused()) return;
    c.al_link_set_recording(_link, enabled ? 1 : 0);
  }

  /// What the link recorded, in the C layer's packed layout; empty after
  /// [free].
  Uint8List recording() {
    if (_refused()) return Uint8List(0);
    final size = c.al_link_recording(_link, nullptr, 0);
    if (size == 0) return Uint8List(0);
    return using((arena) {
      final buffer = arena<Uint8>(size);
      // It only grows, and nothing records any more once the download
      // isolate is gone; a size that changed anyway gives nothing.
      if (c.al_link_recording(_link, buffer, size) != size) {
        return Uint8List(0);
      }
      return Uint8List.fromList(buffer.asTypedList(size));
    });
  }

  /// Frees the link. Only once no iostream of it is open and nothing will
  /// call into it from another isolate; from here on every call is refused.
  void free() {
    if (_freed) return;
    _freed = true;
    c.al_link_free(_link);
  }
}
