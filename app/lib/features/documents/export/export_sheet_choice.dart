part of 'export_sheet.dart';

/// What the export sheet's choices come to: the pages and the options it
/// closes with.
extension _ExportChoice on _ExportSheetState {
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

  /// Closes with [options], remembering them for the next export.
  void _done(ExportOptions options) {
    ExportMemory.keep(
      options,
      _range,
      choosePages: widget.choosePages && _count > 1,
      print: widget.print,
    );
    Navigator.of(context).pop(options);
  }
}
