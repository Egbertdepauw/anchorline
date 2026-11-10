import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/ui/notifiers/dive_attachments_notifier.dart';
import 'package:ccrlogger/ui/widgets/storage_full_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _usage = AttachmentUsage(
  usedBytes: 980000000,
  limitBytes: 1000000000,
  usedFiles: 412,
  limitFiles: 1000,
);

/// A screen with one button that opens the dialog and keeps the result.
class _Host extends StatefulWidget {
  const _Host(this.state);

  final StorageFullState state;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  StorageFullChoice? result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () async {
                final r = await showStorageFullDialog(
                  context,
                  state: widget.state,
                );
                setState(() => result = r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_HostState> _open(WidgetTester tester, StorageFullState state) async {
  await tester.pumpWidget(_Host(state));
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('renders the exact title and body copy', (tester) async {
    await _open(
      tester,
      const StorageFullState(
        usage: _usage,
        fileSizeBytes: 4200000,
        canFreeSpace: true,
      ),
    );

    expect(find.text('Attachment storage full'), findsOneWidget);
    expect(
      find.text('0.98 GB of 1 GB used (412 of 1,000 files). This file needs '
          '4.2 MB. Delete attachments you no longer need to make room.'),
      findsOneWidget,
    );
    expect(find.text('Free space now'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('counts the files of a multi-file add that were not added',
      (tester) async {
    for (final (n, sentence) in [
      (1, " 1 more file wasn't added."),
      (2, " 2 more files weren't added."),
    ]) {
      await _open(
        tester,
        StorageFullState(
          usage: _usage,
          fileSizeBytes: 4200000,
          canFreeSpace: true,
          remainingFiles: n,
        ),
      );
      expect(
        find.text('0.98 GB of 1 GB used (412 of 1,000 files). This file needs '
            '4.2 MB. Delete attachments you no longer need to make room.'
            '$sentence'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('hides Free space now when nothing is purgeable',
      (tester) async {
    await _open(
      tester,
      const StorageFullState(
        usage: _usage,
        fileSizeBytes: 4200000,
        canFreeSpace: false,
      ),
    );

    expect(find.text('Free space now'), findsNothing);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('Free space now returns freeSpace', (tester) async {
    final host = await _open(
      tester,
      const StorageFullState(
        usage: _usage,
        fileSizeBytes: 4200000,
        canFreeSpace: true,
      ),
    );
    await tester.tap(find.text('Free space now'));
    await tester.pumpAndSettle();
    expect(host.result, StorageFullChoice.freeSpace);
    expect(find.text('Attachment storage full'), findsNothing);
  });

  testWidgets('OK and barrier dismiss return ok', (tester) async {
    const state = StorageFullState(
      usage: _usage,
      fileSizeBytes: 4200000,
      canFreeSpace: true,
    );
    final host = await _open(tester, state);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(host.result, StorageFullChoice.ok);

    host.result = null;
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(host.result, StorageFullChoice.ok);
  });
}
