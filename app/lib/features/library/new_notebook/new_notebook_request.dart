import '../../../domain/cover_style.dart';
import '../../../domain/notebook.dart';
import '../../../domain/paper.dart';

/// What the user chose in `NewNotebookSheet`.
class NewNotebookRequest {
  const NewNotebookRequest({
    required this.title,
    required this.kind,
    required this.paper,
    required this.coverColor,
    this.coverStyle = CoverStyle.plain,
    this.template = const PageTemplate(),
    this.importPdf = false,
  });

  /// The user chose to create the notebook from a PDF instead (see
  /// `importPdfFlow`); the other fields are then irrelevant.
  const NewNotebookRequest.importPdf()
    : this(
        title: '',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
        importPdf: true,
      );

  final String title;
  final NotebookKind kind;
  final PaperStyle paper;
  final int coverColor;
  final CoverStyle coverStyle;

  /// First page of a paged notebook (its style equals [paper]).
  final PageTemplate template;
  final bool importPdf;
}
