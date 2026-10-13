import '../../../domain/notebook.dart';
import '../../../domain/paper.dart';

/// What the user chose in `NewNotebookSheet`.
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.kind,
    required this.paper,
    required this.coverColor,
    this.template = const PageTemplate(),
    this.papers = const [],
  });

  final String title;
  final NotebookKind kind;
  final PaperStyle paper;
  final int coverColor;

  /// First page of a paged notebook (its style equals [paper] unless that
  /// style needs parameters; [paper] is then blank).
  final PageTemplate template;

  /// The pages of a paged notebook when there are several (a generated
  /// planner), each made like [template]; empty for one page.
  final List<Paper> papers;
}
