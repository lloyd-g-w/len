import 'package:flutter/material.dart';

import '../../data/tag_repository.dart';
import '../../domain/tag.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import 'tag_dialog.dart';
import 'tag_widgets.dart';

/// Lets the user choose the tags of one or more notebooks or pages, whose
/// current tags are [current] (one set per item). New tags can be created
/// by typing a name. Returns the tags to put on (true) or take off (false)
/// every item — only those the user changed — or null if cancelled.
Future<Map<String, bool>?> showTagPicker(
  BuildContext context, {
  required TagRepository tags,
  required List<Set<String>> current,
  String title = 'Tags',
}) => showDialog<Map<String, bool>>(
  context: context,
  builder: (_) => TagPicker(tags: tags, current: current, title: title),
);

/// The dialog of [showTagPicker].
class TagPicker extends StatefulWidget {
  const TagPicker({super.key, required this.tags, required this.current, required this.title});

  final TagRepository tags;
  final List<Set<String>> current;
  final String title;

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  final _query = TextEditingController();
  late List<Tag> _all = widget.tags.list();

  /// Choices the user made; tags not in here keep their initial state.
  final Map<String, bool> _changes = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// true: on every item, false: on none, null: on some.
  bool? _initial(String id) {
    final on = widget.current.where((s) => s.contains(id)).length;
    if (on == 0) return false;
    return on == widget.current.length ? true : null;
  }

  bool? _state(String id) => _changes[id] ?? _initial(id);

  void _toggle(String id) => setState(() {
    final next = _state(id) != true;
    if (next == _initial(id)) {
      _changes.remove(id);
    } else {
      _changes[id] = next;
    }
  });

  void _create(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final tag = widget.tags.create(name: trimmed, color: nextTagColor(_all.map((t) => t.color)));
    setState(() {
      _all = widget.tags.list();
      _changes[tag.id] = true;
      _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _query,
      builder: (context, _) {
        final q = _query.text.trim();
        final lower = q.toLowerCase();
        final shown = [
          for (final t in _all)
            if (t.name.toLowerCase().contains(lower)) t,
        ];
        final exact = _all.any((t) => t.name.toLowerCase() == lower);
        return AppDialog(
          icon: Icons.sell_outlined,
          title: widget.title,
          content: DialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('tag-picker-field'),
                  controller: _query,
                  autofocus: true,
                  maxLength: TagRepository.maxNameLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _all.isEmpty ? 'Name a new tag' : 'Find or create a tag',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    counterText: '',
                  ),
                  onSubmitted: (value) {
                    final match = shown.where((t) => t.name.toLowerCase() == lower);
                    if (match.isNotEmpty) {
                      _toggle(match.first.id);
                      _query.clear();
                    } else {
                      _create(value);
                    }
                  },
                ),
                const SizedBox(height: Gaps.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (q.isNotEmpty && !exact)
                        ListTile(
                          key: const ValueKey('tag-picker-create'),
                          leading: const Icon(Icons.add_rounded),
                          title: Text('Create “$q”'),
                          onTap: () => _create(q),
                        ),
                      for (final t in shown)
                        CheckboxListTile(
                          key: ValueKey('tag-picker-${t.id}'),
                          tristate: true,
                          value: _state(t.id),
                          onChanged: (_) => _toggle(t.id),
                          controlAffinity: ListTileControlAffinity.trailing,
                          secondary: TagDot(t.color, size: 14),
                          title: Text(t.name),
                        ),
                      if (_all.isEmpty && q.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(Gaps.md),
                          child: Text(
                            'No tags yet. Type a name to create one.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, Map.of(_changes)),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}
