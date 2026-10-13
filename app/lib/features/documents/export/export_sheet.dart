import 'package:flutter/material.dart';

import '../../../domain/notebook_page.dart';
import '../../../platform/file_export.dart' as platform;
import '../../../ui/app_switch.dart';
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
  List<int>? initialPages,
  bool canvas = false,
}) {
  ExportSheet sheet({required bool wide}) => ExportSheet(
    title: title,
    pages: pages,
    currentPage: currentPage,
    initialRange: initialRange,
    initialPages: initialPages,
    wide: wide,
    canvas: canvas,
    offerSaveToDevice: platform.canSaveToDevice,
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
    this.initialPages,
    this.wide = false,
    this.canvas = false,
    this.offerSaveToDevice = false,
  });

  /// Offers "Save to device" beside "Share" (Android).
  final bool offerSaveToDevice;

  /// The notebook's title.
  final String title;
  final List<NotebookPage> pages;

  /// Zero-based index of the page shown in the editor.
  final int currentPage;
  final ExportRange initialRange;

  /// Zero-based pages to start the page range with (the overview's
  /// selection): the sheet then starts at [ExportRange.custom].
  final List<int>? initialPages;

  /// Dialog layout (else bottom sheet).
  final bool wide;

  /// An infinite canvas's drawing ([pages] is that one page): no page
  /// choice, and the pattern is the canvas's background.
  final bool canvas;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportFormat _format = ExportFormat.pdf;
  late ExportRange _range = widget.pages.length == 1
      ? ExportRange.all
      : widget.initialPages != null
      ? ExportRange.custom
      : widget.initialRange;
  late final _rangeText = TextEditingController(
    text: switch (widget.initialPages) {
      final pages? => formatPageRange(pages, separator: ', '),
      null => '${widget.currentPage + 1}',
    },
  );
  final _rangeFocus = FocusNode();
  bool _templates = true;
  bool _backgrounds = true;

  /// The options are scrolled under the header: a hairline divides them.
  bool _scrolled = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final scrolled = n.metrics.pixels > 0;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

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

  ExportOptions? _options({bool toDevice = false}) {
    final pages = _selection.pages;
    if (pages == null || pages.isEmpty) return null;
    return ExportOptions(
      format: _format,
      pages: pages,
      includeTemplates: _templates,
      includeBackgrounds: _backgrounds,
      canvas: widget.canvas,
      toDevice: toDevice,
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
    final options = _options();
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
        DecoratedBox(
          decoration: BoxDecoration(
            border: _scrolled
                ? Border(bottom: Surfaces.chromeEdge(Theme.of(context).colorScheme))
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(Gaps.xl, widget.wide ? Gaps.xl : 0, Gaps.xl, Gaps.md),
            child: SheetHeader(
              title: 'Export',
              subtitle: widget.title,
              // Dialogs close with Cancel (none beside Save to device);
              // sheets with the ✕ (DESIGN §6.3).
              onClose: widget.wide && !widget.offerSaveToDevice
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ),
        ),
        Flexible(
          child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: body),
        ),
        ExportSheetFooter(
          // A bad range says so in its field only.
          summary: options?.summary ?? '',
          onExport: options == null ? null : () => Navigator.of(context).pop(options),
          onSaveToDevice: !widget.offerSaveToDevice || options == null
              ? null
              : () => Navigator.of(context).pop(_options(toDevice: true)),
          offersSaveToDevice: widget.offerSaveToDevice,
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
      widget.canvas ? 'Background' : 'Page templates',
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
      AppSwitchTile(
        padding: EdgeInsets.zero,
        title: title,
        subtitle: subtitle,
        value: value,
        onChanged: (v) => setState(() => set(v)),
      );
}
