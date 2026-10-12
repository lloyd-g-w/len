import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/images/element_images.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import 'page_backgrounds.dart';
import 'page_thumbnail.dart';

/// Asks which page to show (REDESIGN §2.4): a page number field above a
/// strip of thumbnails. Typing a number scrolls the strip to that page;
/// tapping a thumbnail goes there at once. Returns the page's index, or
/// null if cancelled.
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

  /// The page the field names, or null while it names none.
  int? _target;

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
    final number = int.tryParse(_field.text.trim());
    final target = number != null && number >= 1 && number <= _count ? number - 1 : null;
    if (target == _target) return;
    setState(() => _target = target);
    if (target != null) _reveal(target);
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
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Page',
                suffixText: 'of $_count',
                errorText: _target == null && _field.text.isNotEmpty ? 'Pages 1–$_count' : null,
              ),
            ),
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
                  child: _StripPage(
                    page: widget.pages[i],
                    number: i + 1,
                    target: i == _target,
                    cache: _cache,
                    backgrounds: widget.backgrounds,
                    onTap: () => _go(i),
                  ),
                ),
              ),
            ),
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

/// One page in the strip: its thumbnail (ringed while the field names it)
/// and its number.
class _StripPage extends StatelessWidget {
  const _StripPage({
    required this.page,
    required this.number,
    required this.target,
    required this.cache,
    required this.backgrounds,
    required this.onTap,
  });

  final NotebookPage page;
  final int number;
  final bool target;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = GoToPageDialog.thumbWidth(page);
    return Semantics(
      button: true,
      selected: target,
      label: 'Page $number${page.bookmarked ? ', bookmarked' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('go-to-page-$number'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xxs),
          child: Column(
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: width,
                height: GoToPageDialog.thumbHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: target ? scheme.primary : scheme.outlineVariant,
                    width: target ? 2.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm - 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        child: SizedBox(
                          width: width,
                          height: width * page.height / page.width,
                          child: PageThumbnail(page: page, cache: cache, backgrounds: backgrounds),
                        ),
                      ),
                      if (page.bookmarked)
                        Positioned(
                          top: 0,
                          right: Gaps.xs,
                          child: Icon(
                            Symbols.bookmark_rounded,
                            fill: 1,
                            size: 16,
                            color: Palette.bookmark,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gaps.xs),
              Text(
                '$number',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: target ? scheme.primary : null,
                  fontWeight: target ? FontWeight.w600 : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
