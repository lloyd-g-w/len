import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../documents/template_field.dart';
import 'cover_picker.dart';
import 'notebook_cover.dart';
import 'paper_swatch.dart';

/// What the user chose in [NewNotebookSheet].
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.kind,
    required this.paper,
    required this.coverColor,
    this.coverStyle = CoverStyle.plain,
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
  final CoverStyle coverStyle;

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
        constraints: const BoxConstraints(maxWidth: 640),
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
  CoverStyle _coverStyle = CoverStyle.plain;

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
        coverStyle: _coverStyle,
        template: _template,
      ),
    );
  }

  String get _defaultTitle =>
      _kind == NotebookKind.canvas ? 'Untitled canvas' : 'Untitled notebook';

  void _setKind(NotebookKind kind) => setState(() {
    _kind = kind;
    if (_kind == NotebookKind.canvas && _paper.isRuled) {
      _template = _template.copyWith(style: PaperStyle.dotted);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // Scrollable so the form survives a short phone screen with the keyboard
    // up; padded by the keyboard inset so the fields stay visible.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Gaps.xl,
        0,
        Gaps.xl,
        Gaps.xl + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('New', style: theme.textTheme.headlineSmall)),
              // At the top, so it stays reachable with the keyboard up.
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
            ],
          ),
          const SizedBox(height: Gaps.lg),
          Row(
            children: [
              Expanded(
                child: _KindCard(
                  icon: Icons.menu_book_rounded,
                  label: 'Notebook',
                  description: 'Pages you can flip through',
                  selected: _kind == NotebookKind.paged,
                  onTap: () => _setKind(NotebookKind.paged),
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: _KindCard(
                  icon: Icons.all_inclusive_rounded,
                  label: 'Infinite canvas',
                  description: 'One endless whiteboard',
                  selected: _kind == NotebookKind.canvas,
                  onTap: () => _setKind(NotebookKind.canvas),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.lg),
          TextField(
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: _defaultTitle),
          ),
          const SizedBox(height: Gaps.xl),
          Text('Paper', style: label),
          const SizedBox(height: Gaps.sm),
          // Quick style choice; the field below opens the full template
          // picker (paper colour and page size too).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final paper in PaperStyle.ordered)
                  Padding(
                    padding: const EdgeInsets.only(right: Gaps.md),
                    child: PaperSwatch(
                      paper: paper,
                      color: _template.color,
                      selected: _paper == paper,
                      onTap: () => setState(() => _template = _template.copyWith(style: paper)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gaps.md),
          TemplateField(
            template: _template,
            sizeEditable: _kind == NotebookKind.paged,
            onChanged: (t) => setState(() => _template = t),
          ),
          const SizedBox(height: Gaps.xl),
          Text('Cover', style: label),
          const SizedBox(height: Gaps.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                height: 116,
                child: NotebookCover(color: _cover, style: _coverStyle, kind: _kind),
              ),
              const SizedBox(width: Gaps.xl),
              Expanded(
                child: CoverPicker(
                  color: _cover,
                  style: _coverStyle,
                  kind: _kind,
                  onColor: (c) => setState(() => _cover = c),
                  onStyle: (s) => setState(() => _coverStyle = s),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.lg),
          // Alternative to a blank notebook: one page per PDF page.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(const NewNotebookRequest.importPdf()),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Import PDF…'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.standard,
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(Radii.control + 2),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.control + 2),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Gaps.md + 2),
              child: Row(
                children: [
                  Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
