import 'package:libdivecomputer/src/hook/build_config.dart';
import 'package:test/test.dart';

void main() {
  const allFiles = [
    'aes.c',
    'serial_posix.c',
    'serial_win32.c',
    'divesoft_freedom.c',
    'divesoft_freedom_parser.c',
    'hdlc.c',
    'common.h',
  ];

  test(
    'POSIX targets drop the Win32 serial port and Windows the POSIX one',
    () {
      for (final os in ['android', 'ios', 'macos', 'linux']) {
        final s = sourcesFor(os, allFiles, {});
        expect(s, contains('serial_posix.c'), reason: os);
        expect(s, isNot(contains('serial_win32.c')), reason: os);
      }
      final win = sourcesFor('windows', allFiles, {});
      expect(win, contains('serial_win32.c'));
      expect(win, isNot(contains('serial_posix.c')));
      expect(win, isNot(contains('common.h')));
    },
  );

  test('a left-out family drops its files and keeps the shared ones', () {
    final s = sourcesFor('macos', allFiles, {'divesoft_freedom'});
    expect(s, isNot(contains('divesoft_freedom.c')));
    expect(s, isNot(contains('divesoft_freedom_parser.c')));
    expect(s, contains('hdlc.c'));
  });

  test('defines follow Android.mk and the vcxproj, per OS', () {
    final macos = definesFor('macos', {}).keys.toSet();
    expect(
      macos,
      containsAll([
        'ENABLE_LOGGING',
        'HAVE_VERSION_SUFFIX',
        'HAVE_PTHREAD_H',
        'HAVE_STRUCT_TM_TM_GMTOFF',
        'HAVE_UNISTD_H',
        'HAVE_MACH_MACH_TIME_H',
        'HAVE_MACH_ABSOLUTE_TIME',
        'HAVE_IOKIT_SERIAL_IOSS_H',
      ]),
    );
    expect(macos, isNot(contains('HAVE_LINUX_SERIAL_H')));
    final ios = definesFor('ios', {}).keys.toSet();
    expect(ios, contains('HAVE_MACH_ABSOLUTE_TIME'));
    expect(ios, isNot(contains('HAVE_IOKIT_SERIAL_IOSS_H')));
    expect(definesFor('linux', {}).keys, contains('HAVE_LINUX_SERIAL_H'));
    final android = definesFor('android', {}).keys.toSet();
    expect(android, contains('HAVE_TIMEGM'));
    expect(android, isNot(contains('HAVE_MACH_ABSOLUTE_TIME')));
    final win = definesFor('windows', {}).keys.toSet();
    expect(
      win,
      containsAll([
        '_CRT_SECURE_NO_WARNINGS',
        'WIN32',
        '_WINDOWS',
        '_USRDLL',
        'LIBDIVECOMPUTER_EXPORTS',
        'ENABLE_LOGGING',
      ]),
    );
    expect(win, isNot(contains('HAVE_PTHREAD_H')));
    for (final os in ['android', 'ios', 'macos', 'linux', 'windows']) {
      final keys = definesFor(os, {}).keys;
      for (final never in [
        'HAVE_LIBUSB',
        'HAVE_HIDAPI',
        'HAVE_BLUEZ',
        'HAVE_LIBMTP',
        'HAVE_WS2BTH_H',
        'HAVE_AF_IRDA_H',
      ]) {
        expect(keys, isNot(contains(never)), reason: '$os $never');
      }
    }
  });

  test('a left-out family defines AL_LEFT_OUT_<KEY>', () {
    expect(
      definesFor('macos', {'hw_ostc3'}).keys,
      contains('AL_LEFT_OUT_HW_OSTC3'),
    );
  });

  test('only Apple targets get the header-pad linker flag', () {
    expect(
      linkerFlagsFor('macos'),
      contains('-Wl,-headerpad_max_install_names'),
    );
    expect(linkerFlagsFor('ios'), contains('-Wl,-headerpad_max_install_names'));
    expect(linkerFlagsFor('linux'), isEmpty);
  });

  test('parseLeaveOut accepts the table keys and rejects the rest', () {
    expect(parseLeaveOut(null), isEmpty);
    expect(parseLeaveOut(<Object?>[]), isEmpty);
    expect(parseLeaveOut(['hw_ostc3', 'oceans_s1']), {'hw_ostc3', 'oceans_s1'});
    expect(
      () => parseLeaveOut(['nope']),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('nope'), contains('mclean_extreme')),
        ),
      ),
    );
    expect(() => parseLeaveOut('hw_ostc3'), throwsFormatException);
  });

  test('stubs cover every prototype and return DC_STATUS_UNSUPPORTED', () {
    final text = renderLeaveOutStubs({'pelagic_i330r', 'hw_ostc3'});
    expect(text, contains('pelagic_i330r_device_open'));
    expect(text, contains('hw_ostc3_device_fwupdate'));
    expect(
      RegExp('return DC_STATUS_UNSUPPORTED;').allMatches(text),
      hasLength(1 + 9),
    );
    expect(text, isNot(contains('hw_ostc3_parser_create')));
  });

  test('the Windows .def lists the symbols file, then the al_ functions', () {
    expect(
      renderDefFile('dc_version\n\ndc_buffer_new\n', ['al_family_present']),
      'EXPORTS\n\tdc_version\n\tdc_buffer_new\n\tal_family_present\n',
    );
  });

  test('exportedAlFunctions skips static helpers', () {
    const c = '''
static int
al_helper (int x)
{ return x; }

int
al_family_present (unsigned int family)
{ return 1; }

void
al_other(void) {}
''';
    expect(exportedAlFunctions([c]), ['al_family_present', 'al_other']);
  });
}
