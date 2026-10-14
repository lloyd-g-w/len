import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/scroll_fade.dart';
import '../../ui/segment_label.dart';
import '../../ui/sheet_parts.dart';
import '../documents/template_picker.dart';
import '../documents/templates/page_setup.dart';
import '../documents/templates/planner_options.dart';
import '../documents/templates/template_catalog.dart';
import 'new_notebook/cover_row.dart';
import 'new_notebook/default_title.dart';
import 'new_notebook/new_notebook_request.dart';
import 'new_notebook/notebook_preview.dart';
import 'new_notebook/paper_row.dart';
import 'new_notebook/recent_papers.dart';

export 'new_notebook/new_notebook_request.dart';

part 'new_notebook/new_notebook_layout.dart';

/// What the phone's new-notebook sheet imports instead.
enum SheetImport { pdf, len }

/// Creates a notebook or an infinite canvas, in one column: title;
/// Notebook / Canvas; paper (the recent ones, then "More…");
/// cover colour; page size; Create. A dialog with a live preview beside
/// the form on wide screens; a full-height sheet on phones, its preview
/// strip scrolling away with the form.
class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({super.key, this.wide = false, this.today, this.onImport});

  /// Offers "Import PDF…" and "Import Len file…" under Notebook / Canvas,
  /// which close the sheet and call this: where phones, which have no ⊕▾,
  /// find importing.
  final ValueChanged<SheetImport>? onImport;

  /// Dialog layout, the preview beside the form.
  final bool wide;

  /// Today's date, the default start of planners (tests fix it).
  final DateTime? today;

  static Future<NewNotebookRequest?> show(
    BuildContext context, {
    ValueChanged<SheetImport>? onImport,
  }) {
    return showDialogOrSheet<NewNotebookRequest>(
      context: context,
      maxWidth: 840,
      maxHeight: 720,
      minHeight: 560,
      builder: (_, wide) => NewNotebookSheet(wide: wide, onImport: onImport),
    );
  }

  @override
  State<NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<NewNotebookSheet> {
  final _title = TextEditingController();
  NotebookKind _kind = NotebookKind.paged;
  late final DateTime _today = widget.today ?? DateTime.now();
  late TemplateSelection _selection = initialSelection(
    PageTemplate.of(_canvas ? PaperStyle.dotted : PaperStyle.collegeRuled),
    _today,
    calendar: defaultPlannerCalendar(),
  );

  /// The pages the full chooser generated (a planner's date range), while
  /// its choice stands.
  List<Paper>? _chosenPapers;
  int _cover = Palette.covers.first;
  List<String> _recent = const [];

  /// The title when none is typed: today's date (numbered if taken).
  String _defaultTitle = '';

  PageTemplate get _template => _selection.template;
  PaperStyle get _paper => _template.style;
  bool get _canvas => _kind == NotebookKind.canvas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.maybeRead(context);
    _recent = services?.preferences.recentPapers ?? const [];
    _defaultTitle = defaultNotebookTitle(_today, [
      for (final n in services?.notebooks.list() ?? const <Notebook>[]) n.title,
    ], language: defaultPlannerCalendar().language);
  }

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
        paper: _paper.needsParams ? PaperStyle.blank : _paper,
        coverColor: _cover,
        template: _template,
        papers: !_canvas && _paper.isPlanner
            ? (_chosenPapers ?? _selection.pagesToCreate())
            : const [],
      ),
    );
  }

  void _setKind(NotebookKind kind) => setState(() {
    _kind = kind;
    _chosenPapers = null;
    if (_canvas && (_paper.isRuled || !_paper.canvas)) {
      _selection = _selection.copyWith(
        template: _template.copyWith(paper: const Paper(PaperStyle.dotted), clearCustomSize: true),
      );
    }
  });

  void _select(TemplateEntry entry) => setState(() {
    _selection = _selection.select(entry);
    _chosenPapers = null;
  });

  Future<void> _chooseTemplate() async {
    final choice = await showTemplatePicker(
      context,
      initial: _template,
      mode: _canvas ? TemplatePickerMode.canvas : TemplatePickerMode.create,
      today: _today,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _selection = initialSelection(choice.template, _today, calendar: defaultPlannerCalendar());
      _chosenPapers = choice.papers;
    });
  }

  /// "College ruled, white, A4 portrait", with the page count of a
  /// planner.
  String get _summary {
    final chosen = _chosenPapers;
    if (chosen == null || _canvas || !_paper.isPlanner) {
      return describeSelection(_selection, canvas: _canvas);
    }
    final pages = chosen.length;
    return describeWithPages(_template.copyWith(paper: Paper(_paper)), pages);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The sheet paints its own rounded surface; the dialog needs one.
    return Material(
      type: widget.wide ? MaterialType.canvas : MaterialType.transparency,
      color: widget.wide ? Surfaces.overlay(theme.brightness) : null,
      child: widget.wide ? _wideLayout(context) : _phoneLayout(context),
    );
  }

  /// The form, one column.
  List<Widget> _form(BuildContext context, {required bool wide}) {
    final custom = _template.customSize != null;
    return [
      TextField(
        controller: _title,
        autofocus: wide,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: 'Title', hintText: _defaultTitle),
      ),
      const SizedBox(height: Gaps.lg),
      SegmentedButton<NotebookKind>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: const [
          ButtonSegment(
            value: NotebookKind.paged,
            icon: Icon(Symbols.menu_book_sharp),
            label: SegmentLabel('Notebook'),
          ),
          ButtonSegment(
            value: NotebookKind.canvas,
            icon: Icon(Symbols.all_inclusive_sharp),
            label: SegmentLabel('Canvas'),
          ),
        ],
        selected: {_kind},
        onSelectionChanged: (s) => _setKind(s.single),
      ),
      if (widget.onImport case final onImport?)
        // On the form's edge, like the fields and labels.
        Wrap(
          spacing: Gaps.md,
          children: [
            for (final (kind, icon, label) in [
              (SheetImport.pdf, Symbols.picture_as_pdf_sharp, 'Import PDF…'),
              (SheetImport.len, Symbols.file_open_sharp, 'Import Len file…'),
            ])
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsetsDirectional.only(end: Gaps.md),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onImport(kind);
                },
                icon: Icon(icon, size: Glyphs.menu),
                label: Text(label),
              ),
          ],
        ),
      const SizedBox(height: Gaps.xl),
      PickerLabel(
        _canvas ? 'Background' : 'Template',
        key: const ValueKey('template-summary'),
        trailing: _summary,
      ),
      PaperRow(
        selection: _canvas
            ? _selection.copyWith(
                template: _template.copyWith(orientation: PageOrientation.portrait),
              )
            : _selection,
        styles: recentPapers(_recent, canvas: _canvas),
        onSelect: _select,
        onAll: () => unawaited(_chooseTemplate()),
      ),
      const SizedBox(height: Gaps.lg),
      PickerLabel('Cover', trailing: Palette.coverName(_cover)),
      CoverRow(color: _cover, onColor: (c) => setState(() => _cover = c)),
      if (!_canvas && !custom) ...[
        const SizedBox(height: Gaps.xl),
        const PickerLabel('Page size'),
        PageSizeRow(
          template: _template,
          onChanged: (t) => setState(() => _selection = _selection.copyWith(template: t)),
        ),
      ],
    ];
  }
}
