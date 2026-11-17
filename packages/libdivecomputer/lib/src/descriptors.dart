import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.g.dart' as c;
import 'upstream.g.dart';

/// A dive computer model that libdivecomputer supports.
class LibdcDescriptor {
  const LibdcDescriptor({
    required this.vendor,
    required this.product,
    required this.family,
    required this.model,
    required this.transports,
  });

  final String vendor;
  final String product;

  /// A `dc_family_t` value.
  final int family;
  final int model;

  /// A bit mask of `dc_transport_t` values.
  final int transports;

  bool get supportsBle => transports & c.dc_transport_t.DC_TRANSPORT_BLE != 0;

  /// Shearwater computers go to Anchorline's own reader, never to
  /// libdivecomputer.
  bool get isShearwater => vendor == 'Shearwater';

  /// The download asks for a PIN (`DC_IOCTL_BLE_GET_PINCODE`), which the app
  /// can't take yet: the Pelagic i330R family, that is the Aqualung i330R and
  /// the Apeks DSX. They stay unlisted until a PIN prompt exists.
  bool get needsPinCode =>
      family == c.dc_family_t.DC_FAMILY_PELAGIC_I330R;

  /// Whether the app offers this model for a Bluetooth download: a BLE model
  /// that is not a Shearwater and needs no PIN.
  bool get offeredOverBle => supportsBle && !isShearwater && !needsPinCode;

  /// Whether [name] is this model's own advertised name. Only answered for
  /// [needsPinCode] models: upstream's `dc_match_oceanic` gives a Pelagic
  /// computer a BLE name of the model number's two ASCII letters followed by
  /// digits (0x4744 is "GD"), and accepts any family member's name for every
  /// Pelagic model.
  bool _advertisesAs(String name) {
    if (!needsPinCode || name.length < 3) return false;
    final prefix =
        String.fromCharCodes([(model >> 8) & 0xFF, model & 0xFF]);
    return name.startsWith(prefix) && _digit.hasMatch(name[2]);
  }

  static final _digit = RegExp(r'[0-9]');

  @override
  String toString() => '$vendor $product (family $family, model $model)';
}

/// libdivecomputer's version, descriptor list and name matching.
abstract final class Libdc {
  static Pointer<c.dc_context_t>? _context;
  static List<LibdcDescriptor>? _all;

  /// `dc_version(NULL)`, for example `0.10.0-devel-0194f09`.
  static String get version =>
      c.dc_version(nullptr).cast<Utf8>().toDartString();

  /// The upstream commit the vendored tree is at.
  static String get pinnedCommit => kLibdcPinnedCommit;

  /// Every model of a family this build contains, in upstream's order.
  static List<LibdcDescriptor> descriptors() =>
      _all ??= List.unmodifiable(_enumerate(null));

  /// The models the app offers over Bluetooth ([LibdcDescriptor.offeredOverBle])
  /// whose advertised name libdivecomputer recognises. A blank name matches
  /// nothing: `dc_descriptor_filter` matches everything when given no name.
  ///
  /// A computer that needs a PIN matches nothing either. Upstream's name
  /// filter also accepts its name for the other Pelagic models, so leaving
  /// out only the PIN models would still list it, under the wrong family.
  static List<LibdcDescriptor> matchBle(String name) {
    if (name.trim().isEmpty) return const [];
    final matches = _enumerate(name);
    if (matches.any((d) => d._advertisesAs(name))) return const [];
    return [
      for (final d in matches)
        if (!d.needsPinCode) d,
    ];
  }

  /// Whether the build contains [family] (a `dc_family_t` value). False only
  /// when the app left it out with the `leave_out_families` user-define.
  static bool familyPresent(int family) => c.al_family_present(family) != 0;

  static Pointer<c.dc_context_t> _ctx() {
    final existing = _context;
    if (existing != null) return existing;
    return using((arena) {
      final out = arena<Pointer<c.dc_context_t>>();
      _check(c.dc_context_new(out), 'dc_context_new');
      return _context = out.value;
    });
  }

  static void _check(int status, String what) {
    if (status != c.dc_status_t.DC_STATUS_SUCCESS) {
      throw StateError('$what failed with status $status');
    }
  }

  /// Walks the descriptor iterator. With a [bleName], keeps only the
  /// non-Shearwater BLE models whose family is present and that
  /// `dc_descriptor_filter` accepts for that name, PIN models included so
  /// [matchBle] can recognise one; without one, every model of a present
  /// family.
  static List<LibdcDescriptor> _enumerate(String? bleName) {
    final result = <LibdcDescriptor>[];
    return using((arena) {
      final iterator = arena<Pointer<c.dc_iterator_t>>();
      final item = arena<Pointer<c.dc_descriptor_t>>();
      final nameC = bleName?.toNativeUtf8(allocator: arena);
      _check(
        c.dc_descriptor_iterator_new(iterator, _ctx()),
        'dc_descriptor_iterator_new',
      );
      final it = iterator.value;
      try {
        while (true) {
          final status = c.dc_iterator_next(it, item.cast());
          if (status == c.dc_status_t.DC_STATUS_DONE) break;
          _check(status, 'dc_iterator_next');
          final descriptor = item.value;
          try {
            final family = c.dc_descriptor_get_type(descriptor);
            if (!familyPresent(family)) continue;
            final parsed = LibdcDescriptor(
              vendor: c
                  .dc_descriptor_get_vendor(descriptor)
                  .cast<Utf8>()
                  .toDartString(),
              product: c
                  .dc_descriptor_get_product(descriptor)
                  .cast<Utf8>()
                  .toDartString(),
              family: family,
              model: c.dc_descriptor_get_model(descriptor),
              transports: c.dc_descriptor_get_transports(descriptor),
            );
            if (nameC != null) {
              if (parsed.isShearwater || !parsed.supportsBle) continue;
              final accepted = c.dc_descriptor_filter(
                descriptor,
                c.dc_transport_t.DC_TRANSPORT_BLE,
                nameC.cast(),
              );
              if (accepted != 1) continue;
            }
            result.add(parsed);
          } finally {
            c.dc_descriptor_free(descriptor);
          }
        }
      } finally {
        c.dc_iterator_free(it);
      }
      return result;
    });
  }
}
