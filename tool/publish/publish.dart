/// Publishes installers to the downloads bucket and manages its download
/// lists. See `lib/cli.dart` for the options.
///
///     dart tool/publish/publish.dart release --version 1.2.0 --build 45 \
///       --notes-file notes.md --file windows-x64=Anchorline.exe
///
/// Run it with `dart tool/publish/publish.dart`, not `dart run`: in this
/// repository `dart run` runs the package's build hooks first and writes
/// their progress to stdout. Needs `flutter pub get` to have run (it uses
/// `package:crypto`) and the AWS CLI on the path.
library;

import 'dart:io';

import 'lib/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runPublishCli(
    args,
    environment: Platform.environment,
    now: DateTime.now,
  );
}
