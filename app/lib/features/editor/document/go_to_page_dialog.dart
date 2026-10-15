import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/pdf_page_numbers.dart';
import '../../../ink/images/element_images.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import 'go_to_page_strip.dart';
import 'page_backgrounds.dart';
import 'page_thumbnail.dart';

/// Asks which page to show (REDESIGN §2.4): a page number field above a
/// strip of thumbnails. Typing a number scrolls the strip to that page;
/// tapping a thumbnail goes there at once. In a notebook with PDF pages,
/// "s23" / "slide 23" names the page showing its PDF's page 23 (UX_AUDIT
/// R18-5); when several PDFs have one, the current page's PDF wins, else
/// the matches are offered. Returns the page's index, or null if cancelled.
Future<int?> showGoToPage(
  BuildContext context, {
  required List<NotebookPage> pages,
  required int current,
  required SurfaceCopier copier,
  ElementImages? images,
  PageBackgrounds? backgrounds,
}) => showDialog<int>(
  context: context,
  builder: (_) => GoToPageDialog(
    pages: pages,
    current: current,
    copier: copier,
    images: images,
    backgrounds: backgrounds,
  ),
);

class GoToPageDialog extends StatefulWidget {
  const GoToPageDialog({
    super.key,
    required this.pages,
    required this.current,
    required this.copier,
    this.images,
    this.backgrounds,
  });

  final List<NotebookPage> pages;
  final int current;
  final SurfaceCopier copier;
  final ElementImages? images;
  final PageBackgrounds? backgrounds;

  /// Height of a thumbnail in the strip; widths follow each page's shape.
  static const double thumbHeight = 96;

  /// Windows shorter than this show the field only.
  static const double stripFrom = 480;

  /// Space between thumbnails.
  static const double gap = Gaps.sm;

  /// Width of page [page]'s thumbnail (very wide or tall pages are clamped
  /// so every page stays a reasonable target).
  static double thumbWidth(NotebookPage page) =>
      (thumbHeight * page.width / page.height).clamp(48.0, 168.0);

  @override
  State<GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<GoToPageDialog> {
  late final ThumbnailCache _cache = ThumbnailCache(widget.copier, images: widget.images);
  late final TextEditingController _field = TextEditingController(text: '${widget.current + 1}')
    ..selection = TextSelection(baseOffset: 0, extentOffset: '${widget.current + 1}'.length);
  final ScrollController _strip = ScrollController();

  /// Left edge of each thumbnail in the strip.
  late final List<double> _starts = () {
    final starts = <double>[];
    var x = 0.0;
    for (final page in widget.pages) {
      starts.add(x);
      x += GoToPageDialog.thumbWidth(page) + GoToPageDialog.gap;
    }
    return starts;
  }();

  late final PdfPageNumbers _numbers = PdfPageNumbers(widget.pages);
  late final bool _hasPdf = widget.pages.any((p) => p.pdf != null);

  /// The page the field names, or null while it names none.
  int? _target;

  /// The pages the field's PDF page number could mean (in several PDFs),
  /// offered to pick from; empty unless ambiguous.
  List<int> _choices = const [];

  /// Why the field names no page, or null.
  String? _error;

  @override
  void initState() {
    super.initState();
    _target = widget.current;
    _field.addListener(_onTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(widget.current, animate: false));
  }

  @override
  void dispose() {
    _field.dispose();
    _strip.dispose();
    _cache.dispose();
    super.dispose();
  }

  int get _count => widget.pages.length;

  void _onTyped() {
    final text = _field.text.trim();
    final number = int.tryParse(text);
    final pdfNumber = _hasPdf && number == null ? PdfPageNumbers.parse(text) : null;
    var choices = const <int>[];
    int? target;
    String? error;
    if (pdfNumber != null) {
      choices = _numbers.find(pdfNumber, current: widget.current);
      if (choices.length == 1) target = choices.single;
      if (choices.isEmpty) {
        error = text.toLowerCase().startsWith('p')
            ? 'No PDF page $pdfNumber'
            : 'No slide $pdfNumber';
      }
      if (choices.length < 2) choices = const [];
    } else {
      target = number != null && number >= 1 && number <= _count ? number - 1 : null;
      if (target == null && text.isNotEmpty) error = 'Pages 1–$_count';
    }
    final changed = target != _target;
    setState(() {
      _target = target;
      _choices = choices;
      _error = error;
    });
    if (changed && target != null) _reveal(target);
    if (choices.isNotEmpty) _reveal(choices.first);
  }

  /// Scrolls the strip so page [index] is centred (as far as it goes).
  void _reveal(int index, {bool animate = true}) {
    if (!mounted || !_strip.hasClients) return;
    final position = _strip.position;
    final width = GoToPageDialog.thumbWidth(widget.pages[index]);
    final offset = (_starts[index] + width / 2 - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (animate) {
      _strip.animateTo(offset, duration: Motion.medium, curve: Motion.standard);
    } else {
      _strip.jumpTo(offset);
    }
  }

  void _go(int index) => Navigator.pop(context, index);

  /// The field's hint for PDF page numbers, from a page near the current one.
  String _example() {
    final labelled = [
      for (var i = 0; i < _count; i++)
        if (_numbers.labelOf(i) != null) i,
    ];
    final near = labelled.firstWhere((i) => i >= widget.current, orElse: () => labelled.last);
    final number = _numbers.pdfNumberOf(near);
    return '${_numbers.isSlide(near) ? 's' : 'pdf '}$number for ${_numbers.labelOf(near)}';
  }

  void _submit() {
    if (_target case final target?) _go(target);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Go to page',
      content: DialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _field,
              autofocus: true,
              // Letters only where "s23" can mean something.
              keyboardType: _numbers.hasLabels ? TextInputType.text : TextInputType.number,
              inputFormatters: [if (!_hasPdf) FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Page',
                suffixText: 'of $_count',
                helperText: _choices.isNotEmpty
                    ? 'In ${_choices.length} PDFs: which one?'
                    : (_numbers.hasLabels ? _example() : null),
                errorText: _error,
              ),
            ),
            if (_choices.isNotEmpty) _Choices(choices: _choices, onPick: _go),
            // A short window (a phone held sideways) has no room for the
            // strip; the number is enough.
            if (MediaQuery.sizeOf(context).height >= GoToPageDialog.stripFrom) ...[
              const SizedBox(height: Gaps.lg),
              SizedBox(
                height: GoToPageDialog.thumbHeight + 36,
                child: ListView.builder(
                  key: const ValueKey('go-to-page-strip'),
                  controller: _strip,
                  scrollDirection: Axis.horizontal,
                  itemCount: _count,
                  itemBuilder: (context, i) => Padding(
                    padding: EdgeInsets.only(right: i == _count - 1 ? 0 : GoToPageDialog.gap),
                    child: StripPage(
                      page: widget.pages[i],
                      number: i + 1,
                      pdfLabel: _numbers.labelOf(i),
                      target: i == _target || _choices.contains(i),
                      cache: _cache,
                      backgrounds: widget.backgrounds,
                      onTap: () => _go(i),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _target == null ? null : _submit, child: const Text('Go')),
      ],
    );
  }
}

/// The pages a PDF page number could mean when several PDFs have it: one
/// button per page, under the field's question.
class _Choices extends StatelessWidget {
  const _Choices({required this.choices, required this.onPick});

  final List<int> choices;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    // The buttons' labels line up with the field's text.
    padding: const EdgeInsets.only(left: Gaps.xs),
    child: Wrap(
      children: [
        for (final i in choices)
          TextButton(
            key: ValueKey('go-to-choice-${i + 1}'),
            onPressed: () => onPick(i),
            child: Text('Page ${i + 1}'),
          ),
      ],
    ),
  );
}
