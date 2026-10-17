import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../../data/search/surface_text.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import '../../../ui/announce.dart';
import '../tools/text_box_semantics.dart';
import 'document_controller.dart';

/// Pages to a screen reader (the surface is painted): one node per page in
/// view, named "Page 3 of 12, bookmarked", whose value is the page's text
/// ([SurfaceText]: text boxes, recognised handwriting, the PDF's text);
/// scrolling forward or back, or its Next page / Previous page actions, go
/// to the next or previous page and say so. An infinite canvas is one
/// "Canvas" node with its text. The active surface's text boxes in view
/// are nodes of their own ([TextBoxSemantics]): its value leaves them out,
/// so they are not read twice (R25-23); other pages keep theirs.
///
/// Semantics only: the nodes take no pointers (ink and gestures go to the
/// surface below), and nothing is built, listened to or read while no
/// screen reader (or other semantics client) is on.
class PageSemantics extends StatefulWidget {
  /// The pages of [doc] in view.
  const PageSemantics.document({
    super.key,
    required DocumentController this.doc,
    required this.texts,
  }) : canvasId = null,
       canvas = null,
       viewport = null;

  /// The canvas [canvasId] ([canvas], seen through [viewport]) as one node
  /// over the whole surface.
  const PageSemantics.canvas({
    super.key,
    required String this.canvasId,
    required SurfaceModel this.canvas,
    required ViewportController this.viewport,
    required this.texts,
  }) : doc = null;

  final DocumentController? doc;
  final String? canvasId;
  final SurfaceModel? canvas;
  final ViewportController? viewport;

  /// Makes the text cache when semantics turn on (dropped when they go).
  final SurfaceTextCache Function() texts;

  /// The custom actions on a page's node.
  static const next = CustomSemanticsAction(label: 'Next page');
  static const previous = CustomSemanticsAction(label: 'Previous page');

  /// What page [index] of [pages] is called.
  static String labelOf(List<NotebookPage> pages, int index) =>
      'Page ${index + 1} of ${pages.length}${pages[index].bookmarked ? ', bookmarked' : ''}';

  @override
  State<PageSemantics> createState() => _PageSemanticsState();
}

class _PageSemanticsState extends State<PageSemantics> {
  SurfaceTextCache? _texts;

  @override
  void initState() {
    super.initState();
    SemanticsBinding.instance.addSemanticsEnabledListener(_onEnabled);
    _onEnabled();
  }

  void _onEnabled() {
    final enabled = SemanticsBinding.instance.semanticsEnabled;
    if (enabled == (_texts != null)) return;
    final texts = _texts;
    _texts = enabled ? widget.texts() : null;
    texts?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SemanticsBinding.instance.removeSemanticsEnabledListener(_onEnabled);
    _texts?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = _texts;
    if (texts == null) return const SizedBox.shrink();
    final doc = widget.doc;
    if (doc == null) {
      final view = widget.viewport!;
      return ListenableBuilder(
        listenable: Listenable.merge([texts, view]),
        builder: (context, _) => Semantics(
          container: true,
          label: 'Canvas',
          value: texts.of(widget.canvasId!, except: _nodes(widget.canvas!, view)),
          child: const SizedBox.expand(),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([doc, doc.viewport, texts]),
      builder: (context, _) => Stack(children: _pages(context, doc, texts)),
    );
  }

  /// The ids of [model]'s text boxes read as nodes of their own.
  static Set<String> _nodes(SurfaceModel model, ViewportController view) => {
    for (final e in TextBoxSemantics.shown(model, view)) e.id,
  };

  /// A node per page in view, over its part of the screen.
  List<Widget> _pages(BuildContext context, DocumentController doc, SurfaceTextCache texts) {
    final view = doc.viewport;
    if (view.size.isEmpty) return const [];
    final screen = Offset.zero & view.size;
    final pages = doc.pages;
    final layout = doc.layout;
    final active = doc.activePageData.id;
    final nodes = _nodes(doc.activeModel, doc.pageViewport);
    void go(int index) {
      doc.scrollToPage(index);
      announce(context, PageSemantics.labelOf(pages, index));
    }

    return [
      for (final index in layout.visiblePages(view.visibleWorld))
        if (layout.frameOf(index) case final frame?)
          Positioned.fromRect(
            key: ValueKey(pages[index].id),
            rect: Rect.fromPoints(
              view.toScreen(frame.topLeft),
              view.toScreen(frame.bottomRight),
            ).intersect(screen),
            child: Semantics(
              container: true,
              label: PageSemantics.labelOf(pages, index),
              value: texts.of(
                pages[index].id,
                except: pages[index].id == active ? nodes : const {},
              ),
              // Forward is the next page (content moving up), as in a list.
              onScrollUp: index + 1 < pages.length ? () => go(index + 1) : null,
              onScrollDown: index > 0 ? () => go(index - 1) : null,
              customSemanticsActions: {
                if (index + 1 < pages.length) PageSemantics.next: () => go(index + 1),
                if (index > 0) PageSemantics.previous: () => go(index - 1),
              },
              child: const SizedBox.expand(),
            ),
          ),
    ];
  }
}
