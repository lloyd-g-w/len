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
  bool choosePages = true,
  bool resumeRange = true,
  String? whole,
}) {
  ExportSheet sheet({required bool wide}) => ExportSheet(
    title: title,
    pages: pages,
    currentPage: currentPage,
    initialRange: initialRange,
    initialPages: initialPages,
    wide: wide,
    canvas: canvas,
    choosePages: choosePages,
    resumeRange: resumeRange,
    whole: whole,
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
    this.choosePages = true,
    this.resumeRange = true,
    this.whole,
    this.offerSaveToDevice = false,
  });

  /// What is exported whole when it isn't one notebook ("3 notebooks",
  /// "Whole folder"), for the summary.
  final String? whole;

  /// Offers a page range; off when whole notebooks are exported (several
  /// from the library's selection: [pages] are all of theirs).
  final bool choosePages;

  /// Starts at the last export's Current page / All pages rather than
  /// [initialRange]; off where there is no page being read (the library).
  final bool resumeRange;

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

/// What the last export chose, for the app's run (UX_AUDIT R22-2): the
/// next sheet starts there. A typed range is not kept (the pages differ).
class ExportMemory {
  ExportMemory._();

  static ExportFormat format = ExportFormat.pdf;

  /// Current page or all pages; null after a typed range or none yet.
  static ExportRange? range;
  static bool templates = true;
  static bool backgrounds = true;

  /// Forgets the choices (tests).
  @visibleForTesting
  static void reset() {
    format = ExportFormat.pdf;
    range = null;
    templates = backgrounds = true;
  }

  static void _keep(ExportOptions options, ExportRange? range, {required bool choosePages}) {
    format = options.format;
    templates = options.includeTemplates;
    backgrounds = options.includeBackgrounds;
    if (choosePages && options.format != ExportFormat.len) {
      ExportMemory.range = range == ExportRange.custom ? null : range;
    }
  }
}

class _ExportSheetState extends State<ExportSheet> {
  ExportFormat _format = ExportMemory.format;
  late ExportRange _range = widget.pages.length == 1 || !widget.choosePages
      ? ExportRange.all
      : widget.initialPages != null
      ? ExportRange.custom
      : (widget.resumeRange ? ExportMemory.range : null) ?? widget.initialRange;
  late final _rangeText = TextEditingController(
    text: switch (widget.initialPages) {
      final pages? => formatPageRange(pages, separator: ', '),
      null => '${widget.currentPage + 1}',
    },
  );
  final _rangeFocus = FocusNode();
  bool _templates = ExportMemory.templates;
  bool _backgrounds = ExportMemory.backgrounds;

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
  ({List<int>? pages, String? error}) get _selection => _format == ExportFormat.len
      ? (pages: [for (var i = 0; i < _count; i++) i], error: null)
      : switch (_range) {
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
      whole: widget.whole,
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
    final kinds = {for (final i in selected) ?widget.pages[i].background?.kind};
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.xl, Gaps.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExportFormatPicker(format: _format, onChanged: (f) => setState(() => _format = f)),
          // A Len file is the whole notebook, as it is.
          if (_count > 1 && widget.choosePages && _format != ExportFormat.len) ...[
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
          if (_format != ExportFormat.len) ...[
            const SizedBox(height: Gaps.xl),
            ExportSection(title: 'Include', children: _includes(kinds)),
          ],
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
          onExport: options == null ? null : () => _done(options),
          onSaveToDevice: !widget.offerSaveToDevice || options == null
              ? null
              : () => _done(_options(toDevice: true)!),
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

  /// Closes with [options], remembering them for the next export.
  void _done(ExportOptions options) {
    ExportMemory._keep(options, _range, choosePages: widget.choosePages && _count > 1);
    Navigator.of(context).pop(options);
  }

  List<Widget> _includes(Set<PageBackgroundKind> kinds) => [
    _switch(
      widget.canvas ? 'Background' : 'Templates',
      _templates ? 'Lines, grid or dots and paper colour' : 'Plain white paper',
      _templates,
      (v) => _templates = v,
    ),
    if (kinds.isNotEmpty)
      _switch(
        switch (kinds.length) {
          2 => 'Backgrounds',
          _ => kinds.single == PageBackgroundKind.pdf ? 'PDF backgrounds' : 'Scans',
        },
        !_backgrounds
            ? 'Only your notes'
            : switch (kinds.length) {
                2 => 'PDF pages and scans under your notes',
                _ when kinds.single == PageBackgroundKind.pdf =>
                  'Imported PDF pages under your notes',
                _ => 'Scanned pages under your notes',
              },
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
