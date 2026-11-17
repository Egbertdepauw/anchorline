import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:libdivecomputer/src/hook/build_config.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

// The C values of DC_FAMILY_DIVESOFT_FREEDOM and DC_FAMILY_HW_OSTC3 come from
// the generated bindings; the library under test is loaded by path because the
// test runs the hook by hand, outside `dart test`'s own hook run.
import 'package:libdivecomputer/src/bindings.g.dart' show dc_family_t;

PackageUserDefines _leaveOut(List<String> families) => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: {'leave_out_families': families},
    basePath: Uri.directory('.'),
  ),
);

/// Runs the hook for [userDefines] and then [check]. On Windows a loaded DLL
/// cannot be deleted, so the cleanup of the hook's temporary directory fails
/// with an access error after the checks have passed; that error is not the
/// subject of these tests.
Future<void> _runHook(
  List<String> families,
  void Function(BuildInput input, BuildOutput output) check,
) async {
  var passed = false;
  try {
    await testCodeBuildHook(
      mainMethod: hook.main,
      userDefines: _leaveOut(families),
      check: (input, output) {
        check(input, output);
        passed = true;
      },
    );
  } on PathAccessException {
    // Only the cleanup error, and only after every check passed.
    if (!(Platform.isWindows && passed)) rethrow;
  }
}

void main() {
  test(
    'leaving out divesoft_freedom still links; the family reports absent',
    () async {
      await _runHook(
        ['divesoft_freedom'],
        (input, output) {
          final asset = output.assets.code.single;
          final lib = DynamicLibrary.open(asset.file!.toFilePath());
          final present = lib
              .lookupFunction<Int Function(UnsignedInt), int Function(int)>(
                'al_family_present',
              );
          expect(present(dc_family_t.DC_FAMILY_DIVESOFT_FREEDOM), 0);
          expect(present(dc_family_t.DC_FAMILY_HW_OSTC3), 1);
          // The rest of the library is intact (a name on the export list).
          expect(lib.providesSymbol('dc_descriptor_iterator_new'), isTrue);
        },
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'leaving out every family still links and reports each absent',
    () async {
      await _runHook(
        kLeaveOutTable.keys.toList(),
        (input, output) {
          final lib = DynamicLibrary.open(
            output.assets.code.single.file!.toFilePath(),
          );
          final present = lib
              .lookupFunction<Int Function(UnsignedInt), int Function(int)>(
                'al_family_present',
              );
          expect(present(dc_family_t.DC_FAMILY_COCHRAN_COMMANDER), 0);
          expect(present(dc_family_t.DC_FAMILY_HW_OSTC3), 0);
          expect(present(dc_family_t.DC_FAMILY_SUUNTO_EONSTEEL), 0);
          // Families that were not left out are untouched.
          expect(present(dc_family_t.DC_FAMILY_DIVESYSTEM_IDIVE), 1);
        },
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'an unknown leave-out name fails the hook and lists the valid names',
    () async {
      await expectLater(
        testCodeBuildHook(
          mainMethod: hook.main,
          userDefines: _leaveOut(['no_such_family']),
          check: (input, output) {},
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('no_such_family') &&
                kLeaveOutTable.keys.every((k) => e.toString().contains(k)),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
