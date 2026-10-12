import '../../../domain/paper.dart';

/// How many papers the new-notebook sheet offers before "All templates…".
const int recentPaperCount = 6;

/// Offered when there is no history yet (or to fill up the row).
const List<PaperStyle> defaultNotebookPapers = [
  PaperStyle.blank,
  PaperStyle.collegeRuled,
  PaperStyle.dotted,
  PaperStyle.gridSmall,
  PaperStyle.cornell,
  PaperStyle.todo,
];

/// Canvases tile their background: only tiling papers.
const List<PaperStyle> defaultCanvasPapers = [
  PaperStyle.blank,
  PaperStyle.dotted,
  PaperStyle.gridSmall,
  PaperStyle.collegeRuled,
  PaperStyle.gridLarge,
  PaperStyle.isometric,
];

/// The papers the sheet's row shows: the most recently used ([recent],
/// style names, most recent first) that suit a notebook or a [canvas],
/// filled up with the defaults, [recentPaperCount] in all.
List<PaperStyle> recentPapers(List<String> recent, {required bool canvas}) {
  final result = <PaperStyle>[];
  void add(PaperStyle style) {
    if (result.length >= recentPaperCount || result.contains(style)) return;
    if (style == PaperStyle.image || (canvas && !style.canvas)) return;
    result.add(style);
  }

  for (final name in recent) {
    for (final style in PaperStyle.values) {
      if (style.name == name) add(style);
    }
  }
  for (final style in canvas ? defaultCanvasPapers : defaultNotebookPapers) {
    add(style);
  }
  return result;
}
