part of 'playback_controller.dart';

/// Playing a recording whose parts are not all on this device yet (R17-3):
/// the missing parts download a few at a time ([PartDownloads]) while the
/// player plays one part at a time, each from its own blob file, starting
/// as soon as the first one needed is here. At a part's end the next one
/// is loaded (a short gap, as for browser recordings, only while it is
/// played this way); a part not here yet is waited for — [downloading]
/// says so — and fetched before the others when playback (or a seek)
/// needs it. A part that can't be had stops playback ([partMissing]);
/// Play asks for it again. The recording plays as one source again when
/// it is next opened.
extension _PlaybackParts on PlaybackController {
  /// Starts the downloads and loads the part holding the kept start.
  Future<void> _openPartByPart(Recording recording, Set<int> missing, int open) async {
    _downloads = PartDownloads(
      recording.parts,
      missing: missing,
      fetch: fetch,
      parallel: PlaybackController.parallelFetches,
      onChange: () {
        if (open == _opens) _changed();
      },
    );
    final first = recording.parts.partAt(recording.trimStartMs).index;
    if (!await _loadPart(first, open) && open == _opens) {
      throw const AudioUnavailable(PlaybackController.notDownloaded);
    }
  }

  /// Loads part [index] into the player once it is here; false if it
  /// can't be had, or another load (a seek, close) came first.
  Future<bool> _loadPart(int index, int open, {bool retry = false}) async {
    final downloads = _downloads, recording = _recording, player = _player;
    if (downloads == null || recording == null || player == null) return false;
    final load = ++_partLoads;
    bool current() => open == _opens && load == _partLoads;
    _partMissing = false;
    if (downloads.resultOf(index) != true || retry) {
      _waiting = true;
      _changed();
    }
    await downloads.ready(index, retry: retry);
    if (!current()) return false;
    // Not fetched: the player reports it missing (it won't fetch again).
    var here = true;
    _partIndex = index;
    _partStart = recording.parts.startOf(index);
    try {
      await player.open(_partOf(recording, index), blobs, (_) async => false);
      if (current() && _rate != 1) await player.setRate(_rate);
    } on Object catch (e) {
      if (e is! AudioUnavailable) debugPrint('Playback failed to load a part: $e');
      here = false;
    }
    if (!current()) return false;
    _waiting = false;
    if (!here) {
      _partIndex = -1;
      _partMissing = true;
      _playing = false;
      lastError = PlaybackController.notDownloaded;
    }
    _changed();
    return here;
  }

  /// Part [index] of [recording] as a recording of its own.
  Recording _partOf(Recording recording, int index) {
    if (recording.parts.length == 1) return recording;
    final part = recording.parts[index];
    return Recording(
      id: recording.id,
      notebookId: recording.notebookId,
      parts: [part],
      durationMs: part.durationMs,
      startedAt: recording.startedAt,
      title: recording.title,
      mime: recording.mime,
      updatedAt: recording.updatedAt,
    );
  }

  /// [seek] part by part: within the loaded part the player seeks; another
  /// part is loaded (waited for) first.
  Future<void> _seekPart(int positionMs) async {
    final recording = _recording, player = _player;
    if (recording == null || player == null) return;
    final at = recording.parts.partAt(positionMs);
    final offset = Duration(milliseconds: at.offsetMs);
    if (at.index == _partIndex) {
      // Back into the loaded part: a load under way gives up.
      _partLoads++;
      final waited = _waiting;
      _waiting = false;
      await player.seek(offset);
      if (waited) {
        _changed();
        if (_playing) await player.play();
      }
      return;
    }
    final open = _opens;
    _waiting = true; // Positions of the part being left are stale.
    await player.pause();
    if (!await _loadPart(at.index, open)) return;
    await player.seek(offset);
    if (_playing) await player.play();
  }

  /// [play] part by part: a missing part is asked for again; while one is
  /// awaited, it plays once it is here.
  Future<void> _playPart() async {
    final recording = _recording, player = _player;
    if (recording == null || player == null || _waiting) return;
    if (!_partMissing) return player.play();
    final at = recording.parts.partAt(_positionMs);
    if (!await _loadPart(at.index, _opens, retry: true)) return;
    await player.seek(Duration(milliseconds: at.offsetMs));
    if (_playing) await player.play();
  }

  /// The loaded part ended: on to the next one (true), or this is the end
  /// of the recording (false).
  bool _nextPart() {
    final recording = _recording;
    if (_downloads == null || recording == null) return false;
    if (_waiting) return true; // Leaving it anyway.
    final next = _partIndex + 1;
    if (_partIndex < 0 || next >= recording.parts.length) return false;
    _positionMs = recording.parts.startOf(next);
    if (_positionMs >= endMs) return false;
    final open = _opens;
    unawaited(() async {
      if (await _loadPart(next, open) && _playing) await _player?.play();
    }());
    _changed();
    return true;
  }

  /// Back to playing whole recordings (opened afresh, or closed).
  void _endPartByPart() {
    _downloads?.cancel();
    _downloads = null;
    _partIndex = -1;
    _partStart = 0;
    _waiting = false;
    _partMissing = false;
    _partLoads++;
  }
}
