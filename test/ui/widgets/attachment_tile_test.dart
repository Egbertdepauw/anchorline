import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/ui/widgets/attachment_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FileAttachment _file({
  String id = 'f1',
  String mime = 'application/pdf',
  String? title = 'Wreck plan',
  String? originalFilename = 'plan.pdf',
  int? sizeBytes = 12345,
  UploadState state = UploadState.uploaded,
}) {
  final now = DateTime.now();
  return FileAttachment(
    id: id,
    parentKind: DiveAttachmentParentKind.dive,
    parentId: 'd1',
    title: title,
    originalFilename: originalFilename,
    storageKey: 'attachments/o/d1/$id.pdf',
    mimeType: mime,
    sizeBytes: sizeBytes,
    uploadState: state,
    createdAt: now,
    updatedAt: now,
  );
}

LinkAttachment _link({
  String id = 'l1',
  String url = 'https://example.com/wreck',
  String? title,
}) {
  final now = DateTime.now();
  return LinkAttachment(
    id: id,
    parentKind: DiveAttachmentParentKind.dive,
    parentId: 'd1',
    title: title,
    url: url,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: ListView(children: [child])));

void main() {
  testWidgets('uploaded file tile shows mime icon and human size',
      (tester) async {
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _file(),
      onOpen: () {},
      onEdit: () {},
      onDelete: () {},
    )));
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.textContaining('12.1 KB'), findsOneWidget);
    expect(find.text('Wreck plan'), findsOneWidget);
  });

  testWidgets('pending file tile shows progress spinner', (tester) async {
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _file(state: UploadState.pending),
      onOpen: () {},
      onEdit: () {},
      onDelete: () {},
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('failed file tile shows badge and retry button fires callback',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _file(state: UploadState.failed),
      onOpen: () {},
      onEdit: () {},
      onDelete: () {},
      onRetry: () => retried++,
    )));
    expect(find.text('Upload failed'), findsOneWidget);
    final retry = find.byIcon(Icons.refresh);
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('link tile renders link icon and url subtitle',
      (tester) async {
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _link(url: 'https://wreck.example.com/report'),
      onOpen: () {},
      onEdit: () {},
      onDelete: () {},
    )));
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('https://wreck.example.com/report'), findsOneWidget);
    // No title was set → fallback to the host.
    expect(find.text('wreck.example.com'), findsOneWidget);
  });

  testWidgets('popup menu Delete fires onDelete', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _link(),
      onOpen: () {},
      onEdit: () {},
      onDelete: () => deleted++,
    )));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
  });

  testWidgets('popup menu Edit fires onEdit on a file', (tester) async {
    var edited = 0;
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _file(),
      onOpen: () {},
      onEdit: () => edited++,
      onDelete: () {},
    )));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edited, 1);
  });

  testWidgets('uploaded file tile tap fires onOpen', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(AttachmentTile(
      attachment: _file(),
      onOpen: () => opened++,
      onEdit: () {},
      onDelete: () {},
    )));
    await tester.tap(find.text('Wreck plan'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
