import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../documents/template_picker.dart';
import '../documents/templates/planner_options.dart';
import '../documents/templates/template_catalog.dart';
import 'cover_picker.dart';
import 'new_notebook/kind_selector.dart';
import 'new_notebook/new_notebook_request.dart';
import 'new_notebook/notebook_preview.dart';
import 'new_notebook/paper_tab.dart';
import 'new_notebook/sheet_footer.dart';

export 'new_notebook/new_notebook_request.dart';

/// Creates a notebook or an infinite canvas: a live preview (cover and
/// first page), title and kind, then Paper and Cover galleries. A dialog
/// with the preview beside the galleries on wide screens; a tall bottom
/// sheet on phones.
class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({super.key, this.wide = false, this.today});

  /// Two-pane dialog layout.
  final bool wide;

  /// Today's date, the default start of planners (tests fix it).
  final DateTime? today;

  static Future<NewNotebookRequest?> show(BuildContext context) {
    return showDialogOrSheet<NewNotebookRequest>(
      context: context,
      maxWidth: 960,
      maxHeight: 680,
      minHeight: 560,
      sheetDragHandle: false,
      sheetHeightFactor: 0.94,
      builder: (_, wide) => NewNotebookSheet(wide: wide),
    );
  }

  @override
  State<NewNotebookSheet> createState() => _NewNotebookSheetState();
}

class _NewNotebookSheetState extends State<NewNotebookSheet> {
  final _title = TextEditingController();
  NotebookKind _kind = NotebookKind.paged;
  late TemplateSelection _selection = initialSelection(
    PageTemplate.of(PaperStyle.collegeRuled),
    widget.today ?? DateTime.now(),
    calendar: defaultPlannerCalendar(),
  );
  PageTemplate get _template => _selection.template;
  PaperStyle get _paper => _template.style;
  int _cover = Palette.covers.first;

  bool get _canvas => _kind == NotebookKind.canvas;

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
        papers: !_canvas && _paper.isPlanner ? _selection.pagesToCreate() : const [],
      ),
    );
  }

  String get _defaultTitle => _canvas ? 'Untitled canvas' : 'Untitled notebook';

  void _setKind(NotebookKind kind) => setState(() {
    _kind = kind;
    if (_canvas && (_paper.isRuled || !_paper.canvas)) {
      _selection = _selection.copyWith(
        template: _template.copyWith(paper: const Paper(PaperStyle.dotted), clearCustomSize: true),
      );
    }
  });

  void _setSelection(TemplateSelection s) => setState(() => _selection = s);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: widget.wide
          ? theme.dialogTheme.backgroundColor
          : theme.colorScheme.surfaceContainerLow,
      child: DefaultTabController(
        length: 2,
        child: widget.wide ? _wideLayout(context) : _phoneLayout(context),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            _canvas ? 'New canvas' : 'New notebook',
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _preview(double height) => Center(
    child: NotebookPreview(kind: _kind, coverColor: _cover, template: _template, height: height),
  );

  Widget _titleField({required bool autofocus}) => TextField(
    controller: _title,
    autofocus: autofocus,
    textCapitalization: TextCapitalization.sentences,
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      hintText: _defaultTitle,
      labelText: 'Title',
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
  );

  Widget _tabs(BuildContext context) => TabBar(
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerColor: Theme.of(context).colorScheme.outlineVariant,
    tabs: const [
      Tab(text: 'Paper'),
      Tab(text: 'Cover'),
    ],
  );

  Widget _tabViews(EdgeInsets padding, {required double tileWidth}) => TabBarView(
    children: [
      SingleChildScrollView(
        padding: padding,
        child: PaperTab(
          selection: _selection,
          canvas: _canvas,
          tileWidth: tileWidth,
          onChanged: _setSelection,
        ),
      ),
      SingleChildScrollView(
        padding: padding,
        child: CoverPicker(color: _cover, onColor: (c) => setState(() => _cover = c)),
      ),
    ],
  );

  Widget _footer(BuildContext context, {double bottomInset = 0}) => SheetFooter(
    bottomInset: bottomInset,
    onImportPdf: () => Navigator.of(context).pop(const NewNotebookRequest.importPdf()),
    onCreate: _submit,
  );

  Widget _wideLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 360,
                color: scheme.surfaceContainer,
                padding: const EdgeInsets.all(Gaps.xl),
                child: LayoutBuilder(
                  builder: (context, c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KindSelector(kind: _kind, onChanged: _setKind),
                      Expanded(child: _preview((c.maxHeight - 190).clamp(120.0, 260.0))),
                      _titleField(autofocus: true),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.sm, 0),
                      child: _header(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
                      child: _tabs(context),
                    ),
                    Expanded(child: _tabViews(const EdgeInsets.all(Gaps.xl), tileWidth: 76)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _footer(context),
      ],
    );
  }

  Widget _phoneLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    // With the keyboard up, the preview yields its space to the form.
    final keyboard = media.viewInsets.bottom > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.sm, 0),
            child: _header(context),
          ),
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.standard,
            child: keyboard
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gaps.md),
                    child: _preview(150),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.xl, 0),
            child: Column(
              children: [
                _titleField(autofocus: false),
                const SizedBox(height: Gaps.md),
                KindSelector(kind: _kind, onChanged: _setKind),
              ],
            ),
          ),
          const SizedBox(height: Gaps.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
            child: _tabs(context),
          ),
          Expanded(
            child: _tabViews(
              const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, Gaps.xl),
              tileWidth: 64,
            ),
          ),
          _footer(context, bottomInset: keyboard ? 0 : media.padding.bottom),
        ],
      ),
    );
  }
}
