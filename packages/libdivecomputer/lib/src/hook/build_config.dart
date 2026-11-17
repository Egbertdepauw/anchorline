// What the build hook compiles, per OS. Pure Dart so the hook and the tests
// share it; nothing here touches the file system except through arguments.

/// The target OSes the table knows. These are `OS.name` values of
/// `package:code_assets`.
const kPosixOses = {'android', 'ios', 'macos', 'linux'};

/// Platform-specific sources: file name in `src/` -> the OSes that must NOT
/// compile it. Each file is the other platform's implementation of the same
/// interface, and does not compile there. If another file turns out to be
/// platform-only, it goes here with a comment.
const Map<String, Set<String>> kPlatformExcludes = {
  // The Win32 serial port; POSIX targets use serial_posix.c.
  'serial_win32.c': kPosixOses,
  // The POSIX serial port; Windows uses serial_win32.c.
  'serial_posix.c': {'windows'},
};

/// A family the app can leave out of a build, for size or licensing reasons
/// (spec section 10). Every build compiles every family unless the app's
/// `hooks: user_defines: libdivecomputer: leave_out_families` says otherwise.
class LeaveOutFamily {
  const LeaveOutFamily({
    required this.familyConstant,
    required this.header,
    required this.sources,
    required this.stubs,
  });

  /// The `DC_FAMILY_*` name of the family, from `libdivecomputer/common.h`.
  final String familyConstant;

  /// The family's header in `src/`, included by the stub file so a prototype
  /// that drifts after a pin move is a "conflicting types" build error.
  final String header;

  /// Files of `src/` that exist only for this family.
  final List<String> sources;

  /// Exact prototypes (return type, name, parameters, no semicolon) of every
  /// function that other files, or the Windows export list, still call. Copied
  /// from the family's header in `src/`. Each gets a stub that returns
  /// `DC_STATUS_UNSUPPORTED`.
  final List<String> stubs;
}

/// The families that can be left out, keyed by the value that goes in the
/// `leave_out_families` user-define. The key, upper-cased, is also the suffix
/// of the `AL_LEFT_OUT_<KEY>` macro `anchorline_families.c` reads.
const Map<String, LeaveOutFamily> kLeaveOutTable = {
  'suunto_eonsteel': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_SUUNTO_EONSTEEL',
    header: 'suunto_eonsteel.h',
    sources: ['suunto_eonsteel.c', 'suunto_eonsteel_parser.c'],
    stubs: [
      'dc_status_t suunto_eonsteel_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream, unsigned int model)',
      'dc_status_t suunto_eonsteel_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size, unsigned int model)',
    ],
  ),
  'deepblu_cosmiq': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_DEEPBLU_COSMIQ',
    header: 'deepblu_cosmiq.h',
    sources: ['deepblu_cosmiq.c', 'deepblu_cosmiq_parser.c'],
    stubs: [
      'dc_status_t deepblu_cosmiq_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream)',
      'dc_status_t deepblu_cosmiq_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size)',
    ],
  ),
  'oceans_s1': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_OCEANS_S1',
    header: 'oceans_s1.h',
    // oceans_s1_common.c is only used by the two Oceans files.
    sources: ['oceans_s1.c', 'oceans_s1_common.c', 'oceans_s1_parser.c'],
    stubs: [
      'dc_status_t oceans_s1_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream)',
      'dc_status_t oceans_s1_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size)',
    ],
  ),
  'divesoft_freedom': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_DIVESOFT_FREEDOM',
    header: 'divesoft_freedom.h',
    // hdlc.c stays: the Suunto EON Steel backend uses it too.
    sources: ['divesoft_freedom.c', 'divesoft_freedom_parser.c'],
    stubs: [
      'dc_status_t divesoft_freedom_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream)',
      'dc_status_t divesoft_freedom_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size)',
    ],
  ),
  'hw_ostc3': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_HW_OSTC3',
    header: 'hw_ostc3.h',
    // hw_ostc3_parser_create lives in hw_ostc_parser.c, which the older OSTC
    // and Frog families share, so that file and that function stay. The eight
    // hw_ostc3_device_* functions are public API (libdivecomputer.symbols,
    // and so the Windows export list) and are defined in hw_ostc3.c.
    sources: ['hw_ostc3.c'],
    stubs: [
      'dc_status_t hw_ostc3_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream, unsigned int frog)',
      'dc_status_t hw_ostc3_device_version(dc_device_t *device, unsigned char data[], unsigned int size)',
      'dc_status_t hw_ostc3_device_hardware(dc_device_t *device, unsigned char data[], unsigned int size)',
      'dc_status_t hw_ostc3_device_display(dc_device_t *device, const char *text)',
      'dc_status_t hw_ostc3_device_customtext(dc_device_t *device, const char *text)',
      'dc_status_t hw_ostc3_device_config_read(dc_device_t *abstract, unsigned int config, unsigned char data[], unsigned int size)',
      'dc_status_t hw_ostc3_device_config_write(dc_device_t *abstract, unsigned int config, const unsigned char data[], unsigned int size)',
      'dc_status_t hw_ostc3_device_config_reset(dc_device_t *abstract)',
      'dc_status_t hw_ostc3_device_fwupdate(dc_device_t *abstract, const char *filename)',
    ],
  ),
  'pelagic_i330r': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_PELAGIC_I330R',
    header: 'pelagic_i330r.h',
    // The i330R has no parser of its own: it parses with the Oceanic Atom 2
    // parser.
    sources: ['pelagic_i330r.c'],
    stubs: [
      'dc_status_t pelagic_i330r_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream, unsigned int model)',
    ],
  ),
  'deepsix_excursion': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_DEEPSIX_EXCURSION',
    header: 'deepsix_excursion.h',
    sources: ['deepsix_excursion.c', 'deepsix_excursion_parser.c'],
    stubs: [
      'dc_status_t deepsix_excursion_device_open(dc_device_t **out, dc_context_t *context, dc_iostream_t *iostream)',
      'dc_status_t deepsix_excursion_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size)',
    ],
  ),
  'cochran_commander': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_COCHRAN_COMMANDER',
    header: 'cochran_commander.h',
    sources: ['cochran_commander.c', 'cochran_commander_parser.c'],
    stubs: [
      'dc_status_t cochran_commander_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream)',
      'dc_status_t cochran_commander_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size, unsigned int model)',
    ],
  ),
  'mclean_extreme': LeaveOutFamily(
    familyConstant: 'DC_FAMILY_MCLEAN_EXTREME',
    header: 'mclean_extreme.h',
    sources: ['mclean_extreme.c', 'mclean_extreme_parser.c'],
    stubs: [
      'dc_status_t mclean_extreme_device_open(dc_device_t **device, dc_context_t *context, dc_iostream_t *iostream)',
      'dc_status_t mclean_extreme_parser_create(dc_parser_t **parser, dc_context_t *context, const unsigned char data[], size_t size)',
    ],
  ),
};

/// Parses the `leave_out_families` user-define. Throws a [FormatException]
/// that lists the valid names if it is not a list of keys of
/// [kLeaveOutTable].
Set<String> parseLeaveOut(Object? value) {
  final valid = kLeaveOutTable.keys.join(', ');
  if (value == null) return {};
  if (value is! List) {
    throw FormatException(
      'leave_out_families must be a list of family names, got "$value". '
      'Valid names: $valid',
    );
  }
  final result = <String>{};
  for (final entry in value) {
    if (entry is! String || !kLeaveOutTable.containsKey(entry)) {
      throw FormatException(
        'Unknown family "$entry" in leave_out_families. Valid names: $valid',
      );
    }
    result.add(entry);
  }
  return result;
}

/// The preprocessor defines for [os], from `contrib/android/Android.mk` and
/// `contrib/msvc/libdivecomputer.vcxproj` at the pinned commit. There is no
/// `config.h`. Never defined, on purpose: HAVE_LIBUSB, HAVE_HIDAPI,
/// HAVE_BLUEZ, HAVE_LIBMTP, HAVE_WS2BTH_H, HAVE_AF_IRDA_H. Classic Bluetooth
/// waits for phase 3 and IrDA is a non-goal, so bluetooth.c and irda.c
/// compile to their "unsupported" paths.
Map<String, String?> definesFor(String os, Set<String> leftOut) => {
  'ENABLE_LOGGING': null,
  'HAVE_VERSION_SUFFIX': null,
  if (kPosixOses.contains(os)) ...{
    'HAVE_PTHREAD_H': null,
    'HAVE_STRERROR_R': null,
    'HAVE_CLOCK_GETTIME': null,
    'HAVE_LOCALTIME_R': null,
    'HAVE_GMTIME_R': null,
    'HAVE_TIMEGM': null,
    'HAVE_STRUCT_TM_TM_GMTOFF': null,
    'HAVE_UNISTD_H': null,
  },
  if (os == 'ios' || os == 'macos') ...{
    'HAVE_MACH_MACH_TIME_H': null,
    'HAVE_MACH_ABSOLUTE_TIME': null,
  },
  if (os == 'macos') 'HAVE_IOKIT_SERIAL_IOSS_H': null,
  if (os == 'linux') 'HAVE_LINUX_SERIAL_H': null,
  if (os == 'windows') ...{
    '_CRT_SECURE_NO_WARNINGS': null,
    'WIN32': null,
    '_WINDOWS': null,
    '_USRDLL': null,
    'LIBDIVECOMPUTER_EXPORTS': null,
  },
  for (final key in leftOut) 'AL_LEFT_OUT_${key.toUpperCase()}': null,
};

/// Linker flags for [os].
List<String> linkerFlagsFor(String os, {String? defFile}) => [
  // cl.exe hands a bare .def file on its command line to LINK unprocessed;
  // libdivecomputer has no __declspec(dllexport), so the DLL exports only
  // what this file lists.
  if (os == 'windows' && defFile != null) defFile,
  // `flutter test` rewrites install names, and a long worktree path made
  // install_name_tool fail in phase 1 for lack of header room.
  if (os == 'macos' || os == 'ios') '-Wl,-headerpad_max_install_names',
];

/// A cl.exe response file naming [paths], one quoted path per line. Windows
/// refuses a command line over 32,767 characters, and the full source list
/// with absolute paths is longer than that on a CI runner. Forward slashes
/// keep backslash-quote escaping out of the picture; cl.exe accepts them.
String renderResponseFile(Iterable<String> paths) =>
    paths.map((p) => '"${p.replaceAll(r'\', '/')}"\n').join();

/// The `src/*.c` files to compile on [os], given every file name found in
/// `src/` and the families to leave out. Sorted, so builds are reproducible.
List<String> sourcesFor(
  String os,
  Iterable<String> srcFileNames,
  Set<String> leftOut,
) {
  final excluded = {for (final key in leftOut) ...kLeaveOutTable[key]!.sources};
  return [
    for (final name in srcFileNames)
      if (name.endsWith('.c') &&
          !excluded.contains(name) &&
          !(kPlatformExcludes[name]?.contains(os) ?? false))
        name,
  ]..sort();
}

/// The text of `leave_out_stubs.c` for [leftOut]: one stub per entry function
/// of each left-out family, all returning `DC_STATUS_UNSUPPORTED`.
String renderLeaveOutStubs(Set<String> leftOut) {
  final out = StringBuffer()
    ..writeln('/* Generated by hook/build.dart. Do not edit. */')
    ..writeln('#include <stddef.h>')
    ..writeln('#include <libdivecomputer/common.h>')
    ..writeln('#include <libdivecomputer/context.h>')
    ..writeln('#include <libdivecomputer/iostream.h>')
    ..writeln('#include <libdivecomputer/device.h>')
    ..writeln('#include <libdivecomputer/parser.h>');
  for (final key in leftOut.toList()..sort()) {
    out.writeln('#include "${kLeaveOutTable[key]!.header}"');
  }
  out.writeln();
  for (final key in leftOut.toList()..sort()) {
    out.writeln('/* ${kLeaveOutTable[key]!.familyConstant} */');
    for (final prototype in kLeaveOutTable[key]!.stubs) {
      out
        ..writeln(prototype)
        ..writeln('{')
        ..writeln('\treturn DC_STATUS_UNSUPPORTED;')
        ..writeln('}')
        ..writeln();
    }
  }
  return out.toString();
}

/// The Windows module-definition file: `EXPORTS`, every symbol of
/// `src/libdivecomputer.symbols`, then every Anchorline `al_*` function.
String renderDefFile(String symbolsFile, Iterable<String> alFunctions) {
  final names = [
    for (final line in symbolsFile.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
    ...alFunctions,
  ];
  return 'EXPORTS\n${names.map((n) => '\t$n\n').join()}';
}

/// The `al_*` functions that `native/*.c` defines and exports: a definition
/// starts at the first column, and is not static. (Helpers private to a file
/// are `static`, so they stay out of the Windows export list.)
List<String> exportedAlFunctions(Iterable<String> nativeSources) {
  final definition = RegExp(r'^(al_[A-Za-z0-9_]+)\s*\(');
  final result = <String>{};
  for (final source in nativeSources) {
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = definition.firstMatch(lines[i]);
      if (m == null) continue;
      // The return type is on the line before, or on this line before the
      // name; the name at column 0 means it is on the line before.
      final previous = i > 0 ? lines[i - 1].trim() : '';
      if (!previous.startsWith('static')) result.add(m.group(1)!);
    }
  }
  return result.toList()..sort();
}
