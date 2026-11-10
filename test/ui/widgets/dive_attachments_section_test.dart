import 'dart:io';

import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/sync/attachments/attachment_uploader.dart';
import 'package:ccrlogger/ui/notifiers/dive_attachments_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_attachments_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lightweight fake that mirrors the public API the section actually
/// uses. Implementing the real notifier (which is a [ChangeNotifier])
/// directly via `extends` is the cleanest path: mutators just bump the
/// fake's stored list and notify, and the section sees the same shape
/// it would in production.
class _FakeNotifier extends ChangeNotifier implements DiveAttachmentsNotifier {
  List<DiveAttachment> _attachments;
  bool _loading = false;
  String? _error;
  String? _diveId = 'd1';

  // Recorded calls so tests can assert behavior.
  final List<({String url, String? title, String? description})> addLinkCalls =
      [];
  final List<PickedAttachmentFile> addFileCalls = [];
  final List<({int oldIndex, int newIndex})> reorderCalls = [];
  final List<String> softDeleteCalls = [];
  final List<String> restoreCalls = [];
  final List<String> retryCalls = [];
  int reloadCalls = 0;

  _FakeNotifier({List<DiveAttachment>? initial})
      : _attachments = initial ?? const [];

  @override
  List<DiveAttachment> get attachments => List.unmodifiable(_attachments);
  @override
  bool get loading => _loading;
  @override
  String? get error => _error;
  @override
  bool get loaded => _diveId != null && !_loading;
  @override
  String? get diveId => _diveId;

  void setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void setError(String? e) {
    _error = e;
    notifyListeners();
  }

  void setAttachments(List<DiveAttachment> next) {
    _attachments = next;
    notifyListeners();
  }

  @override
  Future<void> load(String diveId) async {
    _diveId = diveId;
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    reloadCalls++;
    notifyListeners();
  }

  @override
  Future<void> addLink({
    required String url,
    String? title,
    String? description,
  }) async {
    addLinkCalls.add((url: url, title: title, description: description));
  }

  @override
  Future<void> addFile(PickedAttachmentFile picked) async {
    addFileCalls.add(picked);
    final refusal = refuseAddsWith;
    if (refusal != null) setStorageFull(refusal);
  }

  @override
  Future<void> updateMetadata(
    String id, {
    String? title,
    String? description,
    String? url,
  }) async {}

  @override
  Future<void> reorder(int oldIndex, int newIndex) async {
    reorderCalls.add((oldIndex: oldIndex, newIndex: newIndex));
  }

  @override
  Future<void> softDelete(String id) async {
    softDeleteCalls.add(id);
  }

  @override
  Future<void> restore(String id) async {
    restoreCalls.add(id);
  }

  @override
  Future<void> retryUpload(String id) async {
    retryCalls.add(id);
  }

  StorageFullState? storageFullValue;

  /// When set, every [addFile] is refused for quota with this state.
  StorageFullState? refuseAddsWith;
  bool uploadsPausedValue = false;
  final Set<String> storageFullIds = {};
  int freeSpaceCalls = 0;
  int dismissStorageFullCalls = 0;
  int dismissPausedCalls = 0;

  void setStorageFull(StorageFullState? s) {
    storageFullValue = s;
    notifyListeners();
  }

  void setUploadsPaused(bool v) {
    uploadsPausedValue = v;
    notifyListeners();
  }

  @override
  StorageFullState? get storageFull => storageFullValue;
  @override
  bool get uploadsPaused => uploadsPausedValue;
  @override
  bool isStorageFull(String id) => storageFullIds.contains(id);

  @override
  Future<void> freeSpaceAndRetry() async {
    freeSpaceCalls++;
    storageFullValue = null;
    notifyListeners();
  }

  @override
  void dismissStorageFull() {
    dismissStorageFullCalls++;
    storageFullValue = null;
    notifyListeners();
  }

  @override
  void dismissUploadsPaused() {
    dismissPausedCalls++;
    uploadsPausedValue = false;
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LinkAttachment _link({
  String id = 'l1',
  String url = 'https://example.com',
  int order = 0,
  String? title,
}) {
  final now = DateTime.now();
  return LinkAttachment(
    id: id,
    parentKind: DiveAttachmentParentKind.dive,
    parentId: 'd1',
    url: url,
    title: title,
    displayOrder: order,
    createdAt: now,
    updatedAt: now,
  );
}

FileAttachment _file({
  String id = 'f1',
  int order = 1,
  String mime = 'application/pdf',
  UploadState state = UploadState.uploaded,
  String? originalFilename = 'plan.pdf',
  int? sizeBytes = 1024,
}) {
  final now = DateTime.now();
  return FileAttachment(
    id: id,
    parentKind: DiveAttachmentParentKind.dive,
    parentId: 'd1',
    storageKey: 'attachments/o/d1/$id.pdf',
    mimeType: mime,
    originalFilename: originalFilename,
    sizeBytes: sizeBytes,
    uploadState: state,
    displayOrder: order,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _harness(_FakeNotifier n,
    {Future<List<PickedAttachmentFile>?> Function(BuildContext)? pickFiles,
    void Function(DiveAttachment)? onOpen}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DiveAttachmentsSection(
          notifier: n,
          pickFiles: pickFiles ?? (_) async => null,
          onOpen: onOpen ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders header with item count and mixed tiles in order',
      (tester) async {
    final n = _FakeNotifier(initial: [
      _link(id: 'l1', url: 'https://a.example.com', order: 0),
      _file(id: 'f1', order: 1),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();

    expect(find.text('ATTACHMENTS'), findsOneWidget);
    expect(find.text('· 2 items'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });

  testWidgets('"1 item" singular when count is one', (tester) async {
    final n = _FakeNotifier(initial: [_link()]);
    await tester.pumpWidget(_harness(n));
    expect(find.text('· 1 item'), findsOneWidget);
  });

  testWidgets('empty state shows header and Add buttons only', (tester) async {
    final n = _FakeNotifier();
    await tester.pumpWidget(_harness(n));
    expect(find.text('· 0 items'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add file'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Add link'), findsOneWidget);
  });

  testWidgets('Add link button opens the sheet, Save invokes addLink',
      (tester) async {
    final n = _FakeNotifier();
    await tester.pumpWidget(_harness(n));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add link'));
    await tester.pumpAndSettle();

    // Sheet present.
    expect(find.text('Add link'), findsWidgets);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'URL'), 'https://wreck.example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Add link'));
    await tester.pumpAndSettle();

    expect(n.addLinkCalls, hasLength(1));
    expect(n.addLinkCalls.single.url, 'https://wreck.example.com');
  });

  testWidgets('error banner shows when notifier.error is set; Retry reloads',
      (tester) async {
    final n = _FakeNotifier();
    n.setError('boom');
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(n.reloadCalls, 1);
  });

  testWidgets('loading indicator shows when notifier.loading is true',
      (tester) async {
    final n = _FakeNotifier();
    n.setLoading(true);
    await tester.pumpWidget(_harness(n));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Add file button calls pickFiles and forwards each pick',
      (tester) async {
    final n = _FakeNotifier();
    final picks = [
      PickedAttachmentFile(
        file: File('/tmp/a.pdf'),
        originalFilename: 'a.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 1234,
      ),
      PickedAttachmentFile(
        file: File('/tmp/b.jpg'),
        originalFilename: 'b.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 5678,
      ),
    ];
    var pickerCalls = 0;
    await tester.pumpWidget(_harness(n, pickFiles: (_) async {
      pickerCalls++;
      return picks;
    }));

    await tester.tap(find.widgetWithText(FilledButton, 'Add file'));
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    expect(n.addFileCalls, hasLength(2));
    expect(n.addFileCalls[0].originalFilename, 'a.pdf');
    expect(n.addFileCalls[1].originalFilename, 'b.jpg');
  });

  testWidgets('soft-delete shows UNDO snackbar that triggers restore',
      (tester) async {
    final n = _FakeNotifier(initial: [_link(id: 'l1')]);
    await tester.pumpWidget(_harness(n));

    // Open the popup menu and pick Delete.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(n.softDeleteCalls, ['l1']);
    expect(find.text('Attachment deleted'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(n.restoreCalls, ['l1']);
  });

  group('storage refusals', () {
    const full = StorageFullState(
      usage: AttachmentUsage(
        usedBytes: 980000000,
        limitBytes: 1000000000,
        usedFiles: 412,
        limitFiles: 1000,
      ),
      fileSizeBytes: 4200000,
      canFreeSpace: true,
    );

    testWidgets('storage-full dialog shows once per refusal; OK dismisses',
        (tester) async {
      final n = _FakeNotifier();
      await tester.pumpWidget(_harness(n));
      n.setStorageFull(full);
      await tester.pumpAndSettle();
      expect(find.text('Attachment storage full'), findsOneWidget);

      // A rebuild with the same refusal doesn't stack a second dialog.
      n.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Attachment storage full'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Attachment storage full'), findsNothing);
      expect(n.dismissStorageFullCalls, 1);
      expect(n.freeSpaceCalls, 0);
    });

    testWidgets('a refusal pending at mount shows the dialog',
        (tester) async {
      final n = _FakeNotifier()..storageFullValue = full;
      await tester.pumpWidget(_harness(n));
      await tester.pumpAndSettle();
      expect(find.text('Attachment storage full'), findsOneWidget);
    });

    testWidgets('Free space now calls freeSpaceAndRetry', (tester) async {
      final n = _FakeNotifier();
      await tester.pumpWidget(_harness(n));
      n.setStorageFull(full);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Free space now'));
      await tester.pumpAndSettle();
      expect(n.freeSpaceCalls, 1);
      expect(n.dismissStorageFullCalls, 0);
      expect(find.text('Attachment storage full'), findsNothing);
    });

    testWidgets('uploads paused shows the paused copy; Dismiss clears it',
        (tester) async {
      final n = _FakeNotifier();
      await tester.pumpWidget(_harness(n));
      n.setUploadsPaused(true);
      await tester.pumpAndSettle();
      expect(
        find.text(
            'Uploads are paused right now. Your existing attachments are fine.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(n.dismissPausedCalls, 1);
      expect(find.textContaining('Uploads are paused'), findsNothing);
    });

    testWidgets('a storage-full refusal stops the rest of a multi-file add',
        (tester) async {
      final n = _FakeNotifier()..refuseAddsWith = full;
      final picks = [
        for (final name in ['a.pdf', 'b.pdf', 'c.pdf'])
          PickedAttachmentFile(
            file: File('/tmp/$name'),
            originalFilename: name,
            mimeType: 'application/pdf',
            sizeBytes: 1234,
          ),
      ];
      await tester.pumpWidget(_harness(n, pickFiles: (_) async => picks));
      await tester.tap(find.widgetWithText(FilledButton, 'Add file'));
      await tester.pumpAndSettle();

      expect(n.addFileCalls.map((p) => p.originalFilename), ['a.pdf']);
      expect(find.text('Attachment storage full'), findsOneWidget);
    });

    testWidgets('a failed row refused for quota reads Storage full',
        (tester) async {
      final n = _FakeNotifier(initial: [
        _file(id: 'f1', state: UploadState.failed),
        _file(id: 'f2', order: 2, state: UploadState.failed),
      ])
        ..storageFullIds.add('f1');
      await tester.pumpWidget(_harness(n));
      await tester.pumpAndSettle();
      expect(find.text('Storage full'), findsOneWidget);
      expect(find.text('Upload failed'), findsOneWidget);
    });
  });
}
