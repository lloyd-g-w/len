import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/segment_label.dart';
import '../../ui/sheet_parts.dart';
import '../documents/template_picker.dart';
import '../documents/templates/page_setup.dart';
import '../documents/templates/planner_options.dart';
import '../documents/templates/template_catalog.dart';
import 'new_notebook/cover_row.dart';
import 'new_notebook/new_notebook_request.dart';
import 'new_notebook/notebook_preview.dart';
import 'new_notebook/paper_row.dart';
import 'new_notebook/recent_papers.dart';

export 'new_notebook/new_notebook_request.dart';

/// Creates a notebook or an infinite canvas, in one column: title;
/// Notebook / Canvas; paper (the recent ones, then "All templates…");
/// cover colour; page size; Create. A dialog with a live preview beside
/// the form on wide screens; a full-height sheet on phones, its preview
/// strip scrolling away with the form.
class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({
    super.key,
    this.wide = false,
    this.today,
    this.kind = NotebookKind.paged,
  });

  /// Dialog layout, the preview beside the form.
  final bool wide;

  /// Today's date, the default start of planners (tests fix it).
  final DateTime? today;

  /// What it starts as (⊕▾ New canvas starts as a canvas).
  final NotebookKind kind;

  static Future<NewNotebookRequest?> show(
    BuildContext context, {
    NotebookKind kind = NotebookKind.paged,
  }) {
    return showDialogOrSheet<NewNotebookRequest>(
      context: context,
      maxWidth: 840,
      maxHeight: 660,
      minHeight: 560,
      sheetDragHandle: false,
      sheetHeightFactor: 0.94,
      builder: (_, wide) => NewNotebookSheet(wide: wide, kind: kind),
    );
  }

  @override
  State<NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<NewNotebookSheet> {
  final _title = TextEditingController();
  late NotebookKind _kind = widget.kind;
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

  PageTemplate get _template => _selection.template;
  PaperStyle get _paper => _template.style;
  bool get _canvas => _kind == NotebookKind.canvas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recent = AppScope.maybeRead(context)?.preferences.recentPapers ?? const [];
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

  String get _defaultTitle => _canvas ? 'Untitled canvas' : 'Untitled notebook';

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

  /// "College ruled · White · A4 portrait", with the page count of a
  /// planner.
  String get _summary {
    final chosen = _chosenPapers;
    if (chosen == null || _canvas || !_paper.isPlanner) {
      return describeSelection(_selection, canvas: _canvas);
    }
    final pages = chosen.length;
    return '${describeTemplate(_template.copyWith(paper: Paper(_paper)))} · '
        '$pages ${pages == 1 ? 'page' : 'pages'}';
  }

  void _importPdf() => Navigator.of(context).pop(const NewNotebookRequest.importPdf());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Surfaces.overlay(theme.brightness),
      child: widget.wide ? _wideLayout(context) : _phoneLayout(context),
    );
  }

  Widget _header(BuildContext context, {Widget? trailing}) => SheetHeader(
    title: _canvas ? 'New canvas' : 'New notebook',
    trailing: trailing,
    onClose: () => Navigator.of(context).pop(),
  );

  Widget _preview(double height) => Center(
    child: NotebookPreview(kind: _kind, coverColor: _cover, template: _template, height: height),
  );

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
            icon: Icon(Symbols.menu_book_rounded),
            label: SegmentLabel('Notebook'),
          ),
          ButtonSegment(
            value: NotebookKind.canvas,
            icon: Icon(Symbols.all_inclusive_rounded),
            label: SegmentLabel('Canvas'),
          ),
        ],
        selected: {_kind},
        onSelectionChanged: (s) => _setKind(s.single),
      ),
      const SizedBox(height: Gaps.xl),
      PickerLabel('Paper', key: const ValueKey('template-summary'), trailing: _summary),
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

  Widget _wideLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The preview beside the form.
        Container(
          width: 320,
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.all(Gaps.xl),
          child: LayoutBuilder(builder: (context, c) => _preview(c.maxHeight.clamp(120.0, 220.0))),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.md, Gaps.sm),
                child: _header(context),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.xl, Gaps.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _form(context, wide: true),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.md, Gaps.xl, Gaps.lg),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _importPdf,
                      icon: const Icon(Symbols.picture_as_pdf_rounded, size: Glyphs.menu),
                      label: const Text('Import PDF…'),
                    ),
                    const Spacer(),
                    SheetActions(
                      onCancel: () => Navigator.of(context).pop(),
                      primary: FilledButton(onPressed: _submit, child: const Text('Create')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _phoneLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    // With the keyboard up, or in a short window (a phone held sideways),
    // the preview yields its space to the form.
    final keyboard = media.viewInsets.bottom > 0 || media.size.height < 520;
    // Large text needs the room more than the preview does.
    final previewHeight = media.textScaler.scale(10) > 11.5 ? 88.0 : 120.0;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.sm, Gaps.sm),
            child: _header(
              context,
              trailing: TextButton(onPressed: _importPdf, child: const Text('Import PDF…')),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Gaps.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The preview scrolls away with the form, so the form
                  // keeps the screen when it is long (large text).
                  AnimatedSize(
                    duration: Motion.medium,
                    curve: Motion.standard,
                    child: keyboard
                        ? const SizedBox(width: double.infinity)
                        : ClipRect(
                            child: Container(
                              height: previewHeight + Gaps.lg * 2,
                              color: scheme.surfaceContainerLow,
                              padding: const EdgeInsets.symmetric(vertical: Gaps.lg),
                              child: _preview(previewHeight),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _form(context, wide: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Gaps.xl,
              Gaps.sm,
              Gaps.xl,
              Gaps.md + (keyboard ? 0 : media.padding.bottom),
            ),
            child: SheetActions(
              stacked: true,
              primary: FilledButton(onPressed: _submit, child: const Text('Create')),
            ),
          ),
        ],
      ),
    );
  }
}
