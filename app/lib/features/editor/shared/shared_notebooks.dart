import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../audio/recording_controller.dart';
import 'shared_notebook.dart';

export 'shared_notebook.dart';

/// The notebooks open in editors, one [SharedNotebook] each, however many
/// editors show it (a tab and the split view's second pane may show the
/// same notebook). Editors [acquire] theirs when they open and [release]
/// it when they close; the last one out disposes it.
///
/// A notebook that is recording stays open when its last editor closes
/// (another tab shown, Back to the library) until the recording stops:
/// a lecture goes on being recorded while the student looks something up
/// elsewhere ([unattended], shown with Show and Stop by
/// `RecordingElsewhereNotice` and the library).
///
/// Also keeps to one recording at a time: there is one microphone, so a
/// notebook can't start recording while another one records, or while the
/// recording of a notebook just closed is still being saved.
class SharedNotebooks {
  SharedNotebooks(this.services);

  final AppServices services;
  final Map<String, SharedNotebook> _open = {};
  final Map<String, int> _users = {};

  /// Titles of notebooks closed while recording, by id, until their
  /// recordings are saved.
  final Map<String, String> _saving = {};

  /// The notebook recording while no editor shows it, or null. Updated
  /// just after editors open and close (they do while the widget tree is
  /// being built or torn down).
  final ValueNotifier<SharedNotebook?> unattended = ValueNotifier(null);

  /// What [unattended] is about to say.
  SharedNotebook? _kept;
  bool _disposed = false;

  void _publish() => scheduleMicrotask(() {
    if (!_disposed) unattended.value = _kept;
  });

  /// Stops watching the [unattended] notebook's recording.
  VoidCallback? _stopWatching;

  /// The shared state of [notebook], held until [release]d.
  SharedNotebook acquire(Notebook notebook) {
    final id = notebook.id;
    _users[id] = (_users[id] ?? 0) + 1;
    if (_kept?.id == id) _attend();
    return _open[id] ??= SharedNotebook(
      services,
      notebook,
      microphoneBusy: () => _recordingElsewhere(id),
    );
  }

  /// The shared state of notebook [id] if an editor has it open.
  SharedNotebook? peek(String id) => _open[id];

  /// Notebooks open in editors, or closed while their recordings are
  /// still being saved.
  Set<String> get ids => {..._open.keys, ..._saving.keys};

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
    if (shared.loadedAudio?.recorder.state.isActive ?? false) return _leaveRecording(shared);
    _close(shared);
  }

  /// Disposes [shared] (no editor holds it), which stops and saves a
  /// running recording; until that is saved the microphone stays busy and
  /// blob garbage collection keeps the notebook's files ([ids]).
  void _close(SharedNotebook shared) {
    final id = shared.id;
    _open.remove(id)!.dispose(); // Saves a running recording.
    final saving = shared.loadedAudio?.saving;
    if (saving == null) return;
    _saving[id] = shared.notebook.title;
    unawaited(
      saving.whenComplete(() {
        _saving.remove(id);
        // Deleted forever meanwhile: the recording goes with it.
        if (services.notebooks.get(id) == null) services.recordings.deleteAllOf(id);
        // Reopened meanwhile: its list gains the recording just saved.
        _open[id]?.loadedAudio?.reload();
      }),
    );
  }

  /// Notebooks were trashed or deleted on this device (the library calls
  /// this after its changes): the [unattended] notebook, if among them, is
  /// let go at once — its recording stopped and saved into it, so it goes
  /// to the trash with the notebook and Undo (or Restore) brings back both;
  /// no notice is left to Show an empty view.
  void notebooksChanged() {
    final kept = _kept;
    if (kept == null || _users[kept.id] != null || !identical(_open[kept.id], kept)) return;
    final current = services.notebooks.get(kept.id);
    if (current != null && !current.isTrashed) return;
    _attend();
    _close(kept);
  }

  /// Whether notebook [id] is recording with no editor showing it.
  bool recordsUnattended(String id) => _kept?.id == id;

  /// Keeps [shared] open while it records with no editor; once the
  /// recording is stopped (from the notice, the notification, or because
  /// the notebook went away) it is released.
  void _leaveRecording(SharedNotebook shared) {
    _attend();
    final recorder = shared.loadedAudio!.recorder;
    void check() {
      if (shared.gone != null && recorder.state.isActive) unawaited(recorder.stop());
      if (recorder.state != RecorderState.idle) return;
      _attend();
      // Not while the recorder is telling its listeners.
      scheduleMicrotask(() {
        if (_users[shared.id] == null && identical(_open[shared.id], shared)) {
          _open.remove(shared.id)!.dispose();
        }
      });
    }

    recorder.addListener(check);
    shared.addListener(check);
    _stopWatching = () {
      recorder.removeListener(check);
      shared.removeListener(check);
    };
    _kept = shared;
    _publish();
  }

  /// The [unattended] notebook is shown again (or done recording).
  void _attend() {
    _stopWatching?.call();
    _stopWatching = null;
    if (_kept == null) return;
    _kept = null;
    _publish();
  }

  String? _recordingElsewhere(String id) {
    if (_saving.values.firstOrNull case final title?) {
      return 'Still saving the recording in “$title”: try again in a moment';
    }
    for (final other in _open.values) {
      if (other.id != id && other.recording) {
        return 'Already recording in “${other.notebook.title}”: stop that recording first';
      }
    }
    return null;
  }

  /// Releases whatever is still open (the app is closing).
  void dispose() {
    _attend();
    _disposed = true;
    unattended.dispose();
    for (final shared in _open.values) {
      shared.dispose();
    }
    _open.clear();
    _users.clear();
  }
}
