import 'dart:async';
import 'dart:typed_data';

/// The Bluetooth link a libdivecomputer download reads and writes through.
///
/// The app implements it over its own BLE seam; the download session only
/// sees this interface, so the package stays free of Flutter and Bluetooth
/// imports.
abstract class LibdcBleLink {
  /// The name the device advertised, for the backends that check it.
  String get advertisedName;

  /// The bytes the device sends, one event per notification or indication,
  /// in arrival order. Nothing is lost between the connection and the first
  /// listener: events are buffered until someone listens.
  Stream<Uint8List> get notifications;

  /// Writes [bytes] to the device's serial-style characteristic, split into
  /// as many writes as the link needs, in order. Completes when the last
  /// write has completed.
  ///
  /// The download normally waits for each call before it makes the next.
  /// After a call has taken longer than the download's write timeout, it
  /// stops waiting, and the next call can begin before that one completed.
  /// The link must then still carry the calls out in the order they began,
  /// one after another: never interleave the chunks of two writes.
  Future<void> write(Uint8List bytes);

  /// Reads the characteristic [uuid] (an access callback some backends
  /// use). Throws [UnsupportedError] where the link can't. Ordered with
  /// every other call, as [write] describes.
  Future<Uint8List> readCharacteristic(String uuid);

  /// Writes [bytes] to the characteristic [uuid]. Throws [UnsupportedError]
  /// where the link can't. Ordered with every other call, as [write]
  /// describes.
  Future<void> writeCharacteristic(String uuid, Uint8List bytes);

  /// Completes when the connection drops, or when the link is closed.
  Future<void> get disconnected;
}
