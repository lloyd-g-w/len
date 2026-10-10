import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import '../documents/template_field.dart';

/// What the user chose in [NewNotebookSheet].
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.kind,
    required this.paper,
    required this.coverColor,
    this.template = const PageTemplate(),
    this.importPdf = false,
  });

  /// The user chose to create the notebook from a PDF instead (see
  /// `importPdfFlow`); the other fields are then irrelevant.
  const NewNotebookRequest.importPdf()
    : this(
        title: '',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        importPdf: true,
      );

  final String title;
  final NotebookKind kind;
  final PaperStyle paper;
  final int coverColor;

  /// First page of a paged notebook (its style equals [paper]).
  final PageTemplate template;
  final bool importPdf;
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
  PageTemplate _template = const PageTemplate(style: PaperStyle.collegeRuled);
  PaperStyle get _paper => _template.style;
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
        template: _template,
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
              if (_kind == NotebookKind.canvas && _paper.isRuled) {
                _template = _template.copyWith(style: PaperStyle.dotted);
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
          TemplateField(
            template: _template,
            sizeEditable: _kind == NotebookKind.paged,
            onChanged: (t) => setState(() => _template = t),
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
          // Documents workstream: create a notebook from a PDF instead.
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(const NewNotebookRequest.importPdf()),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Import PDF…'),
          ),
        ],
      ),
    );
  }
}
