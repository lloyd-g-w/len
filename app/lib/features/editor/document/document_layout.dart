import 'dart:math' as math;
import 'dart:ui';

/// How a paged notebook is presented.
enum PageFlow {
  /// All pages stacked vertically with gaps (GoodNotes-style scrolling).
  continuous,

  /// One page at a time; swipe or use the arrows to turn pages.
  single;

  static PageFlow parse(String? value) =>
      values.firstWhere((f) => f.name == value, orElse: () => continuous);
}

/// Positions of pages in "document space": the world in which the editor's
/// viewport pans and zooms. Each page keeps its own local coordinates
/// (strokes are stored relative to the page); its frame here only says
/// where it is shown.
class DocumentLayout {
  DocumentLayout._(this.frames, this.indices);

  /// Stacks pages of the given [sizes] vertically, centred on a common axis.
  factory DocumentLayout.continuous(List<Size> sizes, {double gap = defaultGap}) {
    final width = sizes.fold<double>(0, (w, s) => math.max(w, s.width));
    final frames = <Rect>[];
    var y = 0.0;
    for (final s in sizes) {
      frames.add(Rect.fromLTWH((width - s.width) / 2, y, s.width, s.height));
      y += s.height + gap;
    }
    return DocumentLayout._(frames, [for (var i = 0; i < sizes.length; i++) i]);
  }

  /// Shows only page [index] (of the given [size]) at the origin.
  factory DocumentLayout.single(int index, Size size) =>
      DocumentLayout._([Offset.zero & size], [index]);

  /// Space between pages, in world units.
  static const double defaultGap = 28;

  /// The area around [visible] whose pages are loaded and rendered ahead
  /// of scrolling into view: half a screen above and below.
  static Rect lookahead(Rect visible) => Rect.fromLTRB(
    visible.left,
    visible.top - visible.height / 2,
    visible.right,
    visible.bottom + visible.height / 2,
  );

  /// Frames of the laid-out pages, in document coordinates.
  final List<Rect> frames;

  /// Page index (in the notebook) of each frame.
  final List<int> indices;

  bool get isEmpty => frames.isEmpty;

  /// Union of all frames.
  Rect get bounds => frames.isEmpty
      ? Rect.zero
      : frames.skip(1).fold(frames.first, (r, f) => r.expandToInclude(f));

  /// Frame of page [pageIndex], or null if it is not laid out.
  Rect? frameOf(int pageIndex) {
    final i = indices.indexOf(pageIndex);
    return i == -1 ? null : frames[i];
  }

  /// The page under [point], or null in a gap or outside.
  int? pageAt(Offset point) {
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].contains(point)) return indices[i];
    }
    return null;
  }

  /// The page closest to [point] (e.g. for a touch in a gap).
  int? nearestPage(Offset point) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      final dx = math.max(0.0, math.max(f.left - point.dx, point.dx - f.right));
      final dy = math.max(0.0, math.max(f.top - point.dy, point.dy - f.bottom));
      final d = dx * dx + dy * dy;
      if (d < bestDistance) {
        bestDistance = d;
        best = indices[i];
      }
    }
    return best;
  }

  /// Pages whose frames intersect [area], in order.
  List<int> visiblePages(Rect area) => [
    for (var i = 0; i < frames.length; i++)
      if (frames[i].overlaps(area)) indices[i],
  ];

  /// The page that best represents what is on screen: the one crossing the
  /// upper third of [visible] (where the eye reads), else the nearest.
  int? currentPage(Rect visible) {
    final probe = Offset(visible.center.dx, visible.top + visible.height / 3);
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      if (probe.dy >= f.top && probe.dy <= f.bottom + defaultGap) return indices[i];
    }
    return nearestPage(probe);
  }
}
