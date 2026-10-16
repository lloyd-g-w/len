import 'dart:ui';

import '../../domain/surface_element.dart';
import '../surface_model.dart';

/// A page of a paged notebook as text flows over it: the band between
/// [top] and [bottom] (page coordinates) that boxes continuing from the
/// page before fill, and that boxes reaching [bottom] continue beyond.
class FlowPage {
  const FlowPage({required this.id, required this.size, required this.top, required this.bottom});

  /// A page of [size] with the usual margins ([marginOf]), the top one at
  /// least [headerBottom] (paper with a header area).
  factory FlowPage.of(String? id, Size size, {double headerBottom = 0}) {
    final margin = marginOf(size);
    final top = headerBottom > 0 ? headerBottom + margin / 2 : margin;
    return FlowPage(id: id, size: size, top: top, bottom: size.height - margin);
  }

  /// Margin above and below the text on a page: 6 % of its height.
  static double marginOf(Size size) => size.height * 0.06;

  /// The page's id; null for a page that will be added for the text.
  final String? id;
  final Size size;
  final double top;
  final double bottom;

  /// Height of the band.
  double get room => bottom - top;
}

/// The pages of a paged notebook, for text boxes that flow across them
/// (`TextFlowChains`). Infinite canvases have none: boxes there grow.
abstract interface class TextFlowPages {
  /// Page [pageId] and the pages after it, in order; null when
  /// [pageId] is not a page of the notebook.
  List<FlowPage>? pagesFrom(String pageId);

  /// The page before [pageId], if any.
  String? pageBefore(String pageId);

  /// Where page `k` of [pagesFrom] ([pageId] itself is 0; pages not added
  /// yet follow the last one) lies from [pageId] in the view, when the
  /// view shows the pages together (continuous flow); null otherwise.
  Offset? offsetOf(String pageId, int k);

  /// Live elements on page [pageId], as stored.
  List<SurfaceElement> elementsOn(String pageId);

  /// The model of page [pageId], to commit edits to (and hide boxes on
  /// while they are edited).
  SurfaceModel modelOf(String pageId);

  /// Adds a page like the last one at the end of the notebook (an undo
  /// step, or part of the running [batch]) and returns its id.
  String addPage();

  /// Runs [edits] (commits on several pages, pages added) as one undo step.
  void batch(void Function() edits);

  /// Makes [pageId] the page receiving input (a chain is edited from the
  /// page of its first box).
  void activate(String pageId);
}
