import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';

/// What the user chose in [NewNotebookSheet].
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.kind,
    required this.paper,
    required this.coverColor,
  });

  final String title;
  final NotebookKind kind;
  final PaperStyle paper;
  final int coverColor;
}

/// Bottom sheet for creating a notebook or an infinite canvas.
class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({super.key});

  static Future<NewNotebookRequest?> show(BuildContext context) =>
      showModalBottomSheet<NewNotebookRequest>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const NewNotebookSheet(),
      );

  @override
  State<NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<NewNotebookSheet> {
  final _title = TextEditingController();
  NotebookKind _kind = NotebookKind.paged;
  PaperStyle _paper = PaperStyle.lined;
  int _cover = Palette.covers.first;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    Navigator.of(context).pop(
      NewNotebookRequest(
        title: title.isEmpty ? _defaultTitle : title,
        kind: _kind,
        paper: _paper,
        coverColor: _cover,
      ),
    );
  }

  String get _defaultTitle =>
      _kind == NotebookKind.canvas ? 'Untitled canvas' : 'Untitled notebook';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so the form survives a short phone screen with the keyboard
    // up; padded by the keyboard inset so the fields stay visible.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          SegmentedButton<NotebookKind>(
            segments: const [
              ButtonSegment(
                value: NotebookKind.paged,
                icon: Icon(Icons.menu_book_rounded),
                label: Text('Notebook'),
              ),
              ButtonSegment(
                value: NotebookKind.canvas,
                icon: Icon(Icons.all_inclusive_rounded),
                label: Text('Infinite canvas'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.single;
              if (_kind == NotebookKind.canvas && _paper == PaperStyle.lined) {
                _paper = PaperStyle.dotted;
              }
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: _defaultTitle),
          ),
          const SizedBox(height: 20),
          Text('Paper', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final paper in PaperStyle.values)
                ChoiceChip(
                  label: Text(_paperLabel(paper)),
                  selected: _paper == paper,
                  onSelected: (_) => setState(() => _paper = paper),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Cover', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in Palette.covers)
                ColorDot(
                  color: color,
                  selected: _cover == color,
                  onTap: () => setState(() => _cover = color),
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.add),
            label: const Text('Create'),
          ),
        ],
      ),
    );
  }

  static String _paperLabel(PaperStyle p) => switch (p) {
    PaperStyle.blank => 'Blank',
    PaperStyle.lined => 'Lined',
    PaperStyle.grid => 'Grid',
    PaperStyle.dotted => 'Dotted',
  };
}
