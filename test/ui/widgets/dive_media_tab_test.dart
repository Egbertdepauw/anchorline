import 'dart:io';

import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/sync/attachments/attachment_uploader.dart';
import 'package:ccrlogger/ui/notifiers/dive_attachments_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_media_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the `_FakeNotifier` pattern from
/// `dive_attachments_section_test.dart` — extending [ChangeNotifier]
/// and implementing the public API the widget consumes is the cleanest
/// way to keep the section/grid behavior testable without a real DAO.
class _FakeNotifier extends ChangeNotifier implements DiveAttachmentsNotifier {
  final List<DiveAttachment> _attachments;
  bool _loading = false;
  String? _error;
  String? _diveId = 'd1';

  final List<({String url, String? title, String? description})> addLinkCalls =
      [];
  final List<PickedAttachmentFile> addFileCalls = [];
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
  }

  @override
  Future<void> updateMetadata(
    String id, {
    String? title,
    String? description,
    String? url,
  }) async {}

  @override
  Future<void> reorder(int oldIndex, int newIndex) async {}

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

/// Wraps the tab in a Scaffold/SingleChildScrollView that fills the
/// test view. Tests that need a specific width set
/// `tester.view.physicalSize` (and reset it via
/// `addTearDown(tester.view.resetPhysicalSize)`) before pumping; the
/// scrollview then exposes that width to the tab's [LayoutBuilder].
Widget _harness(
  _FakeNotifier n, {
  Future<List<PickedAttachmentFile>?> Function(BuildContext)? pickFiles,
  void Function(DiveAttachment)? onOpen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DiveMediaTab(
          notifier: n,
          pickFiles: pickFiles ?? (_) async => null,
          onOpen: onOpen ?? (_) {},
        ),
      ),
    ),
  );
}

/// Configures `tester.view` to the given logical size at DPR 1, and
/// schedules a teardown to reset it. Tests needing a particular
/// width call this before pumping.
void _setLogicalWidth(WidgetTester tester, double width,
    {double height = 1200}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('header reads "MEDIA · N items" with item count and pluralisation',
      (tester) async {
    final n = _FakeNotifier(initial: [_link(), _file()]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('MEDIA'), findsOneWidget);
    expect(find.text('· 2 items'), findsOneWidget);
  });

  testWidgets('"1 item" is singular when count is one', (tester) async {
    final n = _FakeNotifier(initial: [_link()]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('· 1 item'), findsOneWidget);
  });

  testWidgets(
      'empty state: header + Add buttons render, no GridView',
      (tester) async {
    final n = _FakeNotifier();
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('· 0 items'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add file'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Add link'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('grid uses 2 columns on a 400dp-wide constraint',
      (tester) async {
    expect(DiveMediaTab.crossAxisCountFor(400), 2);
    _setLogicalWidth(tester, 400);
    final n = _FakeNotifier(initial: [
      _link(id: 'l1'),
      _link(id: 'l2'),
      _file(id: 'f1'),
      _file(id: 'f2'),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('grid uses 4 columns on a 1100dp-wide constraint',
      (tester) async {
    expect(DiveMediaTab.crossAxisCountFor(1100), 4);
    _setLogicalWidth(tester, 1100);
    final n = _FakeNotifier(initial: [
      _link(id: 'l1'),
      _file(id: 'f1'),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });

  testWidgets('breakpoint pure function covers all bands', (tester) async {
    expect(DiveMediaTab.crossAxisCountFor(360), 2);
    expect(DiveMediaTab.crossAxisCountFor(600), 2);
    expect(DiveMediaTab.crossAxisCountFor(700), 3);
    expect(DiveMediaTab.crossAxisCountFor(900), 3);
    expect(DiveMediaTab.crossAxisCountFor(1000), 4);
    expect(DiveMediaTab.crossAxisCountFor(1200), 4);
    expect(DiveMediaTab.crossAxisCountFor(1400), 6);
  });

  testWidgets('mixed file+link list shows the right tile for each',
      (tester) async {
    final n = _FakeNotifier(initial: [
      _link(id: 'l1', url: 'https://wreck.example.com', title: 'Wreck blog'),
      _file(id: 'f1', mime: 'application/pdf', originalFilename: 'plan.pdf'),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();

    // Document tile shows the basename of the original filename.
    expect(find.text('plan.pdf'), findsOneWidget);
    // Document tile shows the PDF mime icon (full-size, in the grid).
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    // Link tile shows its user-typed title.
    expect(find.text('Wreck blog'), findsOneWidget);
    // Link tile shows its domain as the secondary line.
    expect(find.text('wreck.example.com'), findsOneWidget);
  });

  testWidgets(
      'document tile strips path components from originalFilename',
      (tester) async {
    final n = _FakeNotifier(initial: [
      _file(
        id: 'f1',
        mime: 'application/pdf',
        originalFilename: '/Users/dive/docs/divecenter.pdf',
      ),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('divecenter.pdf'), findsOneWidget);
    expect(find.text('/Users/dive/docs/divecenter.pdf'), findsNothing);
  });

  testWidgets(
      'link tile with no user-typed title falls back to the domain',
      (tester) async {
    final n = _FakeNotifier(initial: [
      _link(id: 'l1', url: 'https://example.com/wreck'),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsOneWidget);
    // We rendered an Image (favicon) + the fallback Icon.link is only
    // shown by the loading/error builder — assert on the Image being
    // the favicon proxy URL rather than its bytes.
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      images.any((img) {
        final provider = img.image;
        return provider is NetworkImage &&
            provider.url.contains('s2/favicons') &&
            provider.url.contains('example.com');
      }),
      isTrue,
    );
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

  testWidgets('Add link button opens the sheet, Save invokes addLink',
      (tester) async {
    final n = _FakeNotifier();
    await tester.pumpWidget(_harness(n));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add link'));
    await tester.pumpAndSettle();

    // Sheet present.
    expect(find.text('Add link'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextFormField, 'URL'),
        'https://wreck.example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Add link'));
    await tester.pumpAndSettle();

    expect(n.addLinkCalls, hasLength(1));
    expect(n.addLinkCalls.single.url, 'https://wreck.example.com');
  });

  testWidgets('error banner renders when notifier.error is set; Retry reloads',
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

  testWidgets('loading indicator renders when notifier.loading is true',
      (tester) async {
    final n = _FakeNotifier();
    n.setLoading(true);
    await tester.pumpWidget(_harness(n));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets(
      'failed-upload tile shows the "Upload failed" badge and Retry control',
      (tester) async {
    final n = _FakeNotifier(initial: [
      _file(
        id: 'f1',
        mime: 'application/pdf',
        originalFilename: 'plan.pdf',
        state: UploadState.failed,
      ),
    ]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();
    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(n.retryCalls, ['f1']);
  });

  testWidgets('tile popup menu invokes onOpen when "Open" is selected',
      (tester) async {
    DiveAttachment? opened;
    final n = _FakeNotifier(initial: [
      _file(id: 'f1', mime: 'application/pdf', originalFilename: 'plan.pdf'),
    ]);
    await tester.pumpWidget(_harness(n, onOpen: (a) => opened = a));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(opened?.id, 'f1');
  });

  testWidgets(
      'tile popup menu Delete soft-deletes and shows UNDO snackbar',
      (tester) async {
    final n = _FakeNotifier(initial: [_link(id: 'l1')]);
    await tester.pumpWidget(_harness(n));
    await tester.pumpAndSettle();

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
}
