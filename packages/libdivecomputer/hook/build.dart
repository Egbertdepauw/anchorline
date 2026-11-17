import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:libdivecomputer/src/hook/build_config.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds the vendored libdivecomputer and Anchorline's C layer into one
/// dynamic library, `package:libdivecomputer/src/bindings.g.dart`.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    final osName = os.name;
    final leftOut = _readLeaveOut(input);

    final root = input.packageRoot;
    final upstream = root.resolve('third_party/libdivecomputer/');
    final srcDir = Directory.fromUri(upstream.resolve('src/'));
    final nativeDir = Directory.fromUri(root.resolve('native/'));
    final outDir = input.outputDirectory;
    await Directory.fromUri(outDir).create(recursive: true);

    final srcNames = [
      for (final f in srcDir.listSync().whereType<File>())
        f.uri.pathSegments.last,
    ];
    final nativeSources = [
      for (final f in nativeDir.listSync().whereType<File>())
        if (f.path.endsWith('.c')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));

    final sources = <String>[
      for (final name in sourcesFor(osName, srcNames, leftOut))
        upstream.resolve('src/$name').toFilePath(),
      for (final f in nativeSources) f.path,
    ];

    if (leftOut.isNotEmpty) {
      final stubs = await _writeIfChanged(
        outDir.resolve('leave_out_stubs.c'),
        renderLeaveOutStubs(leftOut),
      );
      sources.add(stubs.toFilePath());
    }

    final flags = [...linkerFlagsFor(osName)];
    final libraries = <String>[];
    if (os == OS.windows) {
      final symbols = File.fromUri(
        upstream.resolve('src/libdivecomputer.symbols'),
      ).readAsStringSync();
      final alFunctions = exportedAlFunctions([
        for (final f in nativeSources) f.readAsStringSync(),
      ]);
      final def = await _writeIfChanged(
        outDir.resolve('libdivecomputer.def'),
        renderDefFile(symbols, alFunctions),
      );
      flags.addAll(linkerFlagsFor(osName, defFile: def.toFilePath()));
      libraries.add('ws2_32');
    }

    final builder = CBuilder.library(
      name: 'divecomputer',
      assetName: 'src/bindings.g.dart',
      sources: sources,
      includes: [
        root.resolve('native/include/').toFilePath(),
        upstream.resolve('include/').toFilePath(),
        upstream.resolve('src/').toFilePath(),
        nativeDir.path,
      ],
      defines: definesFor(osName, leftOut),
      flags: flags,
      libraries: libraries,
    );
    await builder.run(input: input, output: output);

    output.dependencies.add(root.resolve('native/'));
    output.dependencies.add(upstream.resolve('src/'));
    output.dependencies.add(root.resolve('hook/build.dart'));
    output.dependencies.add(root.resolve('lib/src/hook/build_config.dart'));
    output.dependencies.add(upstream.resolve('src/libdivecomputer.symbols'));
  });
}

/// An unknown name throws a [FormatException] listing the valid ones: an
/// uncaught exception fails the hook, and the build prints the message.
Set<String> _readLeaveOut(BuildInput input) =>
    parseLeaveOut(input.userDefines['leave_out_families']);

/// Writes [content] unless the file already has it, so an unchanged file keeps
/// its modification time and does not retrigger the build.
Future<Uri> _writeIfChanged(Uri uri, String content) async {
  final file = File.fromUri(uri);
  if (!file.existsSync() || file.readAsStringSync() != content) {
    await file.writeAsString(content);
  }
  return uri;
}
