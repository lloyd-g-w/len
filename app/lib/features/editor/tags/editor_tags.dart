import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/tag.dart';
import '../../../ui/messages.dart';
import '../../tags/tag_picker.dart';
import '../editor_session.dart';

/// The tags on [pages], by name, each with the ids of its pages.
List<({Tag tag, Set<String> pages})> pageTagsOf(AppServices services, List<NotebookPage> pages) {
  final ids = {for (final p in pages) p.id};
  final byTag = <String, Set<String>>{};
  services.tags.taggings.all(TagTarget.page).forEach((page, tags) {
    if (!ids.contains(page)) return;
    for (final t in tags) {
      (byTag[t] ??= {}).add(page);
    }
  });
  return [
    for (final t in services.tags.list())
      if (byTag[t.id] case final pages?) (tag: t, pages: pages),
  ];
}

/// Lets the user choose the tags of the open notebook.
Future<void> editNotebookTags(BuildContext context, EditorSession session) =>
    _edit(context, session, session.notebook.id, TagTarget.notebook, 'Notebook tags');

/// Lets the user choose the tags of [page] of the open notebook.
Future<void> editPageTags(BuildContext context, EditorSession session, NotebookPage page) {
  final index = session.doc?.pages.indexWhere((p) => p.id == page.id) ?? -1;
  return _edit(context, session, page.id, TagTarget.page, 'Tags of page ${index + 1}');
}

Future<void> _edit(
  BuildContext context,
  EditorSession session,
  String target,
  TagTarget kind,
  String title,
) async {
  final tags = session.services.tags;
  final changes = await showTagPicker(
    context,
    tags: tags,
    title: title,
    current: [tags.taggings.tagsOf(target)],
  );
  if (changes == null || changes.isEmpty) return;
  session.services.database.transaction(() {
    changes.forEach((tag, on) => tags.taggings.set(tag, target, kind, on: on));
  });
  if (!context.mounted) return;
  final names = [for (final id in tags.taggings.tagsOf(target)) ?tags.get(id)?.name]..sort();
  showMessage(context, names.isEmpty ? 'No tags' : 'Tagged ${names.join(', ')}');
}
