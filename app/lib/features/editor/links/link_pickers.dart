import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/link_target.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../editor_session.dart';

/// Asks for a web address; null if cancelled.
Future<UrlLinkTarget?> pickUrlTarget(BuildContext context, {UrlLinkTarget? initial}) =>
    showDialog<UrlLinkTarget>(
      context: context,
      builder: (_) => _UrlDialog(initial: initial?.uri.toString() ?? ''),
    );

class _UrlDialog extends StatefulWidget {
  const _UrlDialog({required this.initial});

  final String initial;

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final target = UrlLinkTarget.parse(_text.text);
    if (target != null) Navigator.pop(context, target);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _text,
    builder: (context, _) {
      final valid = UrlLinkTarget.parse(_text.text) != null;
      return AppDialog(
        title: 'Link to a web address',
        content: DialogBody(
          child: TextField(
            key: const ValueKey('link-url-field'),
            controller: _text,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Address',
              hintText: 'example.com',
              errorText: _text.text.trim().isNotEmpty && !valid ? 'Not a web address' : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: valid ? _submit : null, child: const Text('Link')),
        ],
      );
    },
  );
}

/// Asks for a page of this or another paged notebook; null if cancelled.
Future<PageLinkTarget?> pickPageTarget(BuildContext context, EditorSession session) =>
    showDialog<PageLinkTarget>(
      context: context,
      builder: (_) => _PagePicker(session: session),
    );

class _PagePicker extends StatefulWidget {
  const _PagePicker({required this.session});

  final EditorSession session;

  @override
  State<_PagePicker> createState() => _PagePickerState();
}

class _PagePickerState extends State<_PagePicker> {
  late final List<Notebook> _notebooks = () {
    final here = widget.session.notebook;
    final others = widget.session.services.notebooks.list().where(
      (n) => n.kind == NotebookKind.paged && n.id != here.id,
    );
    return [if (here.kind == NotebookKind.paged) here, ...others];
  }();
  late String? _notebookId = _notebooks.firstOrNull?.id;

  bool get _here => _notebookId == widget.session.notebook.id;

  List<NotebookPage> get _pages {
    final id = _notebookId;
    if (id == null) return const [];
    final doc = widget.session.doc;
    return _here && doc != null ? doc.pages : widget.session.services.pages.pagesOf(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = _pages;
    final current = _here ? widget.session.doc?.currentPage : null;
    final titles = <String, List<String>>{};
    if (_notebookId case final id?) {
      for (final e in widget.session.services.outline.entriesOf(id)) {
        (titles[e.pageId] ??= []).add(e.title);
      }
    }
    return AppDialog(
      title: 'Link to a page',
      content: DialogBody(
        child: _notebooks.isEmpty
            ? const Text('There are no notebooks with pages to link to')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: const ValueKey('link-notebook-field'),
                    initialValue: _notebookId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Notebook'),
                    items: [
                      for (final n in _notebooks)
                        DropdownMenuItem(
                          value: n.id,
                          child: Text(
                            n.id == widget.session.notebook.id
                                ? '${n.title} (this notebook)'
                                : n.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() => _notebookId = id),
                  ),
                  const SizedBox(height: Gaps.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: pages.length,
                      itemBuilder: (context, i) {
                        final page = pages[i];
                        final names = titles[page.id];
                        return ListTile(
                          key: ValueKey('link-page-$i'),
                          dense: true,
                          selected: i == current,
                          leading: Icon(
                            page.bookmarked
                                ? Symbols.bookmark_rounded
                                : Symbols.description_rounded,
                            fill: page.bookmarked ? 1 : 0,
                            size: 20,
                          ),
                          title: Text(i == current ? 'Page ${i + 1} (this page)' : 'Page ${i + 1}'),
                          subtitle: names == null
                              ? null
                              : Text(
                                  names.join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                          onTap: () => Navigator.pop(
                            context,
                            PageLinkTarget(notebookId: _notebookId!, pageId: page.id),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
