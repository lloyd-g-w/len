import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import 'shared_notebook.dart';

export 'shared_notebook.dart';

/// The notebooks open in editors, one [SharedNotebook] each, however many
/// editors show it (a tab and the split view's second pane may show the
/// same notebook). Editors [acquire] theirs when they open and [release]
/// it when they close; the last one out disposes it.
///
/// Also keeps to one recording at a time: there is one microphone, so a
/// notebook can't start recording while another one records.
class SharedNotebooks {
  SharedNotebooks(this.services);

  final AppServices services;
  final Map<String, SharedNotebook> _open = {};
  final Map<String, int> _users = {};

  /// The shared state of [notebook], held until [release]d.
  SharedNotebook acquire(Notebook notebook) {
    final id = notebook.id;
    _users[id] = (_users[id] ?? 0) + 1;
    return _open[id] ??= SharedNotebook(
      services,
      notebook,
      microphoneBusy: () => _recordingElsewhere(id),
    );
  }

  /// The shared state of notebook [id] if an editor has it open.
  SharedNotebook? peek(String id) => _open[id];

  /// Gives up one editor's hold on [shared].
  void release(SharedNotebook shared) {
    final id = shared.id;
    if (!identical(_open[id], shared)) return;
    final users = (_users[id] ?? 1) - 1;
    if (users > 0) {
      _users[id] = users;
      return;
    }
    _users.remove(id);
    _open.remove(id)!.dispose();
  }

  String? _recordingElsewhere(String id) {
    for (final other in _open.values) {
      if (other.id != id && other.recording) {
        return 'Already recording in “${other.notebook.title}”: stop that recording first';
      }
    }
    return null;
  }

  /// Releases whatever is still open (the app is closing).
  void dispose() {
    for (final shared in _open.values) {
      shared.dispose();
    }
    _open.clear();
    _users.clear();
  }
}
