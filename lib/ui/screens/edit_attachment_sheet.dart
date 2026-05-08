/// Bottom sheet for editing the user-facing metadata of a
/// [DiveAttachment]. Title and description are always editable; the
/// URL field only appears for [LinkAttachment] rows (file rows have
/// an immutable `storage_key` instead and no user-visible URL).
library;

import 'package:flutter/material.dart';

import '../../data/models/dive_attachment.dart';
import '../notifiers/dive_attachments_notifier.dart';

Future<void> showEditAttachmentSheet(
  BuildContext context, {
  required DiveAttachmentsNotifier notifier,
  required DiveAttachment attachment,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _EditAttachmentSheet(
      notifier: notifier,
      attachment: attachment,
    ),
  );
}

class _EditAttachmentSheet extends StatefulWidget {
  final DiveAttachmentsNotifier notifier;
  final DiveAttachment attachment;
  const _EditAttachmentSheet({
    required this.notifier,
    required this.attachment,
  });

  @override
  State<_EditAttachmentSheet> createState() => _EditAttachmentSheetState();
}

class _EditAttachmentSheetState extends State<_EditAttachmentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.attachment.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.attachment.description ?? '');
  late final TextEditingController _url = TextEditingController(
    text: widget.attachment is LinkAttachment
        ? (widget.attachment as LinkAttachment).url
        : '',
  );
  bool _saving = false;

  bool get _isLink => widget.attachment is LinkAttachment;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  String? _validateUrl(String? raw) {
    if (!_isLink) return null;
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'URL is required';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.scheme.isEmpty) return 'Enter a valid URL';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final title = _title.text.trim();
    final description = _description.text.trim();
    final url = _url.text.trim();
    try {
      await widget.notifier.updateMetadata(
        widget.attachment.id,
        title: title.isEmpty ? null : title,
        description: description.isEmpty ? null : description,
        url: _isLink ? url : null,
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Could not save changes: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_isLink ? 'Edit link' : 'Edit file',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (_isLink) ...[
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'URL'),
                    validator: _validateUrl,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Title (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
