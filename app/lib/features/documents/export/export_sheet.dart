import 'package:flutter/material.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/dialog_or_sheet.dart';
import '../../../ui/sheet_parts.dart';
import 'export_options.dart';
import 'export_sheet_sections.dart';

/// Asks what to export from [pages] (format, pages, templates, PDF
/// backgrounds): a dialog on wide screens, a bottom sheet
/// on phones. Null if cancelled.
Future<ExportOptions?> showExportSheet(
  BuildContext context, {
  required String title,
  required List<NotebookPage> pages,
  required int currentPage,
  ExportRange initialRange = ExportRange.all,
}) {
  ExportSheet sheet({required bool wide}) => ExportSheet(
    title: title,
    pages: pages,
    currentPage: currentPage,
    initialRange: initialRange,
    wide: wide,
  );
  return showDialogOrSheet<ExportOptions>(
    context: context,
    maxWidth: 460,
    builder: (_, wide) => sheet(wide: wide),
  );
}

/// The export options: format, pages and what to draw under the ink, with
/// a summary and the Export button pinned below.
class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.title,
    required this.pages,
    required this.currentPage,
    this.initialRange = ExportRange.all,
    this.wide = false,
  });

  /// The notebook's title.
  final String title;
  final List<NotebookPage> pages;

  /// Zero-based index of the page shown in the editor.
  final int currentPage;
  final ExportRange initialRange;

  /// Dialog layout (else bottom sheet).
  final bool wide;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportFormat _format = ExportFormat.pdf;
  late ExportRange _range = widget.pages.length == 1 ? ExportRange.all : widget.initialRange;
  late final _rangeText = TextEditingController(text: '${widget.currentPage + 1}');
  final _rangeFocus = FocusNode();
  bool _templates = true;
  bool _backgrounds = true;

  @override
  void dispose() {
    _rangeText.dispose();
    _rangeFocus.dispose();
    super.dispose();
  }

  int get _count => widget.pages.length;

  /// The chosen pages (zero-based), or an error for a bad range.
  ({List<int>? pages, String? error}) get _selection => switch (_range) {
    ExportRange.current => (pages: [widget.currentPage], error: null),
    ExportRange.all => (pages: [for (var i = 0; i < _count; i++) i], error: null),
    ExportRange.custom => parsePageRange(_rangeText.text, _count),
  };

  ExportOptions? get _options {
    final pages = _selection.pages;
    if (pages == null || pages.isEmpty) return null;
    return ExportOptions(
      format: _format,
      pages: pages,
      includeTemplates: _templates,
      includeBackgrounds: _backgrounds,
    );
  }

  void _setRange(ExportRange range) {
    setState(() => _range = range);
    if (range == ExportRange.custom) {
      _rangeFocus.requestFocus();
      _rangeText.selection = TextSelection(baseOffset: 0, extentOffset: _rangeText.text.length);
    } else {
      _rangeFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final selection = _selection;
    final options = _options;
    final selected = selection.pages ?? const <int>[];
    final hasBackground = selected.any((i) => widget.pages[i].background != null);
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.xl, Gaps.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExportFormatPicker(format: _format, onChanged: (f) => setState(() => _format = f)),
          if (_count > 1) ...[
            const SizedBox(height: Gaps.xl),
            ExportSection(
              title: 'Pages',
              children: [
                ExportPagesPicker(
                  range: _range,
                  onRange: _setRange,
                  currentPage: widget.currentPage,
                  pageCount: _count,
                  rangeController: _rangeText,
                  rangeFocus: _rangeFocus,
                  onRangeText: (_) => setState(() {}),
                  rangeError: _range == ExportRange.custom ? selection.error : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: Gaps.xl),
          ExportSection(title: 'Include', children: _includes(hasBackground)),
        ],
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, widget.wide ? Gaps.xl : 0, Gaps.xl, Gaps.md),
          child: SheetHeader(
            title: 'Export',
            subtitle: widget.title,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
        Flexible(child: body),
        ExportSheetFooter(
          summary: options?.summary ?? 'Check the page range',
          onExport: options == null ? null : () => Navigator.of(context).pop(options),
          bottomInset: widget.wide ? 0 : media.padding.bottom,
        ),
      ],
    );
    if (widget.wide) return content;
    // Above the keyboard while the range is typed.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: content,
      ),
    );
  }

  List<Widget> _includes(bool hasBackground) => [
    _switch(
      'Page templates',
      _templates ? 'Lines, grid or dots and paper colour' : 'Plain white paper',
      _templates,
      (v) => _templates = v,
    ),
    if (hasBackground)
      _switch(
        'PDF backgrounds',
        _backgrounds ? 'Imported PDF pages under your notes' : 'Only your notes',
        _backgrounds,
        (v) => _backgrounds = v,
      ),
  ];

  Widget _switch(String title, String subtitle, bool value, void Function(bool) set) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: (v) => setState(() => set(v)),
      );
}
