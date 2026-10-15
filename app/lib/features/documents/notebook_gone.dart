import '../../app_services.dart';

/// The notebook pages were to go into was deleted meanwhile (on another
/// device, while a scan or a PDF was prepared).
class NotebookGone implements Exception {
  const NotebookGone(this.notebookId);

  final String notebookId;

  /// Throws [NotebookGone] unless notebook [notebookId] is still there.
  static void check(AppServices services, String notebookId) {
    if (services.notebooks.get(notebookId) == null) throw NotebookGone(notebookId);
  }

  @override
  String toString() => 'Notebook $notebookId is gone';
}
