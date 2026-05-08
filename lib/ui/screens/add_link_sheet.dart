/// Bottom sheet for adding a [LinkAttachment] to a dive. Validates the
/// URL is parseable and has a non-empty scheme; title / description
/// are free-form and optional. On Save the sheet calls
/// `notifier.addLink(...)` and pops itself; the parent's listener
/// driven re-render then surfaces the new row.
library;

import 'package:flutter/material.dart';

import '../notifiers/dive_attachments_notifier.dart';

Future<void> showAddLinkSheet(
  BuildContext context, {
  required DiveAttachmentsNotifier notifier,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AddLinkSheet(notifier: notifier),
  );
}

class _AddLinkSheet extends StatefulWidget {
  final DiveAttachmentsNotifier notifier;
  const _AddLinkSheet({required this.notifier});

  @override
  State<_AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<_AddLinkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _validateUrl(String? raw) {
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
    try {
      await widget.notifier.addLink(
        url: _url.text.trim(),
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not add link: $e')));
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
                Text('Add link',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _url,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://example.com/wreck-report',
                  ),
                  validator: _validateUrl,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
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
                          : const Text('Add link'),
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
