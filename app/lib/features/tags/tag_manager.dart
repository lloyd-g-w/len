import 'package:flutter/material.dart';

import '../../data/tag_repository.dart';
import '../../domain/tag.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import 'tag_dialog.dart';
import 'tag_widgets.dart';

/// The tag manager: create, rename, recolour and delete tags. [countOf]
/// says how many notebooks carry a tag; [onChanged] runs after every edit.
Future<void> showTagManager(
  BuildContext context, {
  required TagRepository tags,
  required int Function(String tagId) countOf,
  required VoidCallback onChanged,
}) => showDialog<void>(
  context: context,
  builder: (_) => _TagManager(tags: tags, countOf: countOf, onChanged: onChanged),
);

class _TagManager extends StatefulWidget {
  const _TagManager({required this.tags, required this.countOf, required this.onChanged});

  final TagRepository tags;
  final int Function(String tagId) countOf;
  final VoidCallback onChanged;

  @override
  State<_TagManager> createState() => _TagManagerState();
}

class _TagManagerState extends State<_TagManager> {
  late List<Tag> _tags = widget.tags.list();

  void _changed() {
    widget.onChanged();
    setState(() => _tags = widget.tags.list());
  }

  Future<void> _create() async {
    final details = await showTagDialog(
      context,
      title: 'New tag',
      confirmLabel: 'Create',
      initialColor: nextTagColor(_tags.map((t) => t.color)),
    );
    if (details == null) return;
    widget.tags.create(name: details.name, color: details.color);
    _changed();
  }

  Future<void> _edit(Tag tag) async {
    final details = await showTagDialog(
      context,
      title: 'Edit tag',
      confirmLabel: 'Save',
      initialName: tag.name,
      initialColor: tag.color,
    );
    if (details == null) return;
    final clash = widget.tags.byName(details.name);
    if (clash != null && clash.id != tag.id) {
      if (mounted) showMessage(context, 'A tag named “${details.name}” already exists');
      return;
    }
    widget.tags.update(tag.copyWith(name: details.name, color: details.color));
    _changed();
  }

  Future<void> _delete(Tag tag) async {
    final n = widget.countOf(tag.id);
    final ok = await confirmAction(
      context,
      title: 'Delete “${tag.name}”?',
      message: n == 0
          ? 'No notebook carries this tag'
          : 'It is taken off $n ${n == 1 ? 'notebook' : 'notebooks'}. '
                'The notebooks themselves stay.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    widget.tags.delete(tag.id);
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      icon: Icons.sell_outlined,
      title: 'Manage tags',
      content: DialogBody(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: _tags.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gaps.lg),
                  child: Text(
                    'Tags group notebooks across folders. Create one, then tag notebooks '
                    'from their menu.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in _tags)
                      ListTile(
                        key: ValueKey('tag-manager-${t.id}'),
                        contentPadding: const EdgeInsets.only(left: Gaps.sm),
                        leading: TagDot(t.color, size: 16),
                        title: Text(t.name),
                        subtitle: Text(_count(widget.countOf(t.id))),
                        onTap: () => _edit(t),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(t),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              color: theme.colorScheme.error,
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _delete(t),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New tag…'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }

  static String _count(int n) => n == 0 ? 'Not used' : '$n ${n == 1 ? 'notebook' : 'notebooks'}';
}
