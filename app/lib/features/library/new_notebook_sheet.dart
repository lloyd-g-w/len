import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import 'cover_picker.dart';
import 'new_notebook/kind_selector.dart';
import 'new_notebook/notebook_preview.dart';
import 'new_notebook/paper_tab.dart';

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

/// Creates a notebook or an infinite canvas: a live preview (cover and
/// first page), title and kind, then Paper and Cover galleries. A dialog
/// with the preview beside the galleries on wide screens; a tall bottom
/// sheet on phones.
class NewNotebookSheet extends StatefulWidget {
  const NewNotebookSheet({super.key, this.wide = false});

  /// Two-pane dialog layout.
  final bool wide;

  static Future<NewNotebookRequest?> show(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width >= Breakpoints.medium && size.height >= 560) {
      return showDialog<NewNotebookRequest>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(Gaps.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
            child: const NewNotebookSheet(wide: true),
          ),
        ),
      );
    }
    return showModalBottomSheet<NewNotebookRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (context) =>
          FractionallySizedBox(heightFactor: 0.94, child: const NewNotebookSheet()),
    );
  }

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
        paper: _paper,
        coverColor: _cover,
        coverStyle: _coverStyle,
        template: _template,
      ),
    );
  }

  String get _defaultTitle => _canvas ? 'Untitled canvas' : 'Untitled notebook';

  void _setKind(NotebookKind kind) => setState(() {
    _kind = kind;
    if (_canvas && _paper.isRuled) _template = _template.copyWith(style: PaperStyle.dotted);
  });

  void _setTemplate(PageTemplate t) => setState(() => _template = t);

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
    child: NotebookPreview(
      kind: _kind,
      coverColor: _cover,
      coverStyle: _coverStyle,
      template: _template,
      height: height,
    ),
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
          template: _template,
          canvas: _canvas,
          tileWidth: tileWidth,
          onChanged: _setTemplate,
        ),
      ),
      SingleChildScrollView(
        padding: padding,
        child: CoverPicker(
          color: _cover,
          style: _coverStyle,
          kind: _kind,
          onColor: (c) => setState(() => _cover = c),
          onStyle: (s) => setState(() => _coverStyle = s),
        ),
      ),
    ],
  );

  Widget _footer(BuildContext context, {double bottomInset = 0}) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.xl, Gaps.md + bottomInset),
        child: Row(
          children: [
            // Alternative to a blank notebook: one page per PDF page.
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(const NewNotebookRequest.importPdf()),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Import PDF…', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(width: Gaps.md),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

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
