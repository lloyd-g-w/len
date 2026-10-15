import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/notebook_style.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/roving_focus.dart';
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
import 'new_notebook/style_actions.dart';
import 'new_notebook/style_row.dart';

export 'new_notebook/new_notebook_request.dart';

part 'new_notebook/new_notebook_layout.dart';

/// What the phone's new-notebook sheet imports instead.
enum SheetImport { scan, pdf, len }

/// Creates a notebook or an infinite canvas, in one column: title; the
/// saved notebook styles (each fills in the rest at once; "Save as
/// style…" names the current choice); Notebook / Canvas; paper (the recent ones, then "More…");
/// cover colour; page size; Create. A dialog with a live preview beside
/// the form on wide screens; a full-height sheet on phones, its preview
/// strip scrolling away with the form.
class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({super.key, this.wide = false, this.today, this.onImport});

  /// Offers "Scan document…", "Import PDF…" and "Import Len file…" as
  /// quiet links at the sheet's foot, under Create, which close the sheet and call this: where
  /// phones, which have no ⊕▾, find importing.
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
      maxHeight: 800,
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
  late final DateTime _today = widget.today ?? AppScope.read(context).clock.nowDate();
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

  /// The user's notebook styles.
  List<NotebookStyle> _styles = const [];

  /// Whether the form has taken its start: the default style, else what
  /// the last notebook was made as.
  bool _started = false;

  PageTemplate get _template => _selection.template;
  PaperStyle get _paper => _template.style;
  bool get _canvas => _kind == NotebookKind.canvas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.maybeRead(context);
    _recent = services?.preferences.recentPapers ?? const [];
    _styles = services?.notebookStyles.list() ?? const [];
    if (!_started && services != null) {
      _started = true;
      final start =
          services.notebookStyles.defaultStyle()?.choice ?? services.preferences.lastNotebookChoice;
      if (start != null) _apply(start);
    }
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

  /// What the form shows, as a style; null with a user's image template.
  NotebookChoice? get _choice =>
      NotebookChoice.of(kind: _kind, template: _template, coverColor: _cover);

  /// Fills in the form from [choice] (planners from today).
  void _apply(NotebookChoice choice) {
    final calendar = defaultPlannerCalendar();
    final paper = Paper.defaultFor(choice.paper, today: _today, calendar: calendar)!;
    _kind = choice.kind;
    _cover = choice.coverColor;
    _chosenPapers = null;
    _selection = initialSelection(
      PageTemplate(
        paper: paper.withLook(choice.look),
        color: choice.paperColor,
        format: choice.format,
        orientation: choice.orientation,
      ),
      _today,
      calendar: calendar,
    );
  }

  void _applyStyle(NotebookStyle style) => setState(() => _apply(style.choice));

  void _reloadStyles() {
    if (!mounted) return;
    setState(() => _styles = AppScope.read(context).notebookStyles.list());
  }

  Future<void> _saveStyle(NotebookChoice choice) async {
    final repo = AppScope.read(context).notebookStyles;
    final saved = await saveNotebookStyle(context, repo, choice, suggested: _paper.label);
    if (saved != null) _reloadStyles();
  }

  Future<void> _styleMenu(NotebookStyle style, Offset at) async {
    final repo = AppScope.read(context).notebookStyles;
    if (await showNotebookStyleMenu(context, repo, style, at: at)) _reloadStyles();
  }

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
        // Typing is for keyboards: on touch the soft keyboard would cover
        // the form when most just pick paper and write.
        autofocus: wide && !Targets.touchFirst,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        // The hint is the title an empty field gives: shown on every form
        // factor, focused or not.
        decoration: InputDecoration(
          labelText: 'Title',
          hintText: _defaultTitle,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
      ..._styleSection(),
      const SizedBox(height: Gaps.lg),
      RovingSegments(
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
      ..._saveStyleLink(),
    ];
  }
}

/// The form's notebook styles: pick one at the top (the Styles row, once
/// there are any), save the form as one at the end ("Save as style…"), so
/// a first notebook's form starts with what it makes (UX_AUDIT R12-5).
extension _NewNotebookStyles on _NewNotebookSheetState {
  /// The style the form matches, if any.
  String? get _matchingStyle {
    final choice = _choice;
    for (final style in _styles) {
      if (style.choice == choice) return style.id;
    }
    return null;
  }

  /// "Styles" and its row; nothing before the first style.
  List<Widget> _styleSection() {
    if (_styles.isEmpty) return const [];
    return [
      const SizedBox(height: Gaps.xl),
      const PickerLabel('Styles'),
      StyleRow(
        styles: _styles,
        selected: _matchingStyle,
        onApply: _applyStyle,
        onMenu: (style, at) => unawaited(_styleMenu(style, at)),
      ),
    ];
  }

  /// "Save as style…" under the form; nothing when the form is a style
  /// already or can't be one (a user's image template).
  List<Widget> _saveStyleLink() {
    final choice = _choice;
    if (choice == null || _matchingStyle != null || AppScope.maybeRead(context) == null) {
      return const [];
    }
    return [
      const SizedBox(height: Gaps.lg),
      SaveStyleButton(onPressed: () => unawaited(_saveStyle(choice))),
    ];
  }
}
