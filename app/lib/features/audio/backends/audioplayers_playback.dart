import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../data/blob_store.dart';
import '../../../domain/recording.dart';
import '../../../platform/audio_files.dart';
import 'audio_backends.dart';

/// [AudioPlayback] with `package:audioplayers`: ExoPlayer on Android,
/// GStreamer on Linux, Media Foundation on Windows, an `<audio>` element in
/// browsers. Natively the player streams the blob's file; browsers play a
/// blob URL.
///
/// A recording in several parts plays as one: parts that join by
/// concatenation (raw AAC, see [Recording.joinable]) are joined into one
/// source, so playback and seeking are seamless; other parts (browser
/// recordings) are played one after the other, with positions mapped
/// across them.
class AudioplayersPlayback implements AudioPlayback {
  AudioplayersPlayback() {
    _player.onPositionChanged.listen((p) => _positions.add(p + _startOf(_index)));
    _player.onPlayerComplete.listen((_) => unawaited(_next()));
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Spoken audio; audio focus is the media session's (PlaybackFocus.kt),
      // which tells Dart to pause, so the plugin must not pause by itself.
      unawaited(
        _player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              contentType: AndroidContentType.speech,
              audioFocus: AndroidAudioFocus.none,
            ),
          ),
        ),
      );
    }
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<Duration> _positions = StreamController.broadcast();
  final StreamController<void> _completed = StreamController.broadcast();

  /// The sources: one per part, or one for all parts joined.
  List<({String uri, bool isFile})> _sources = const [];
  List<RecordingPart> _parts = const [];
  String _mime = '';
  int _index = 0;
  bool _playing = false;

  Duration _startOf(int index) =>
      Duration(milliseconds: _sources.length == 1 ? 0 : _parts.startOf(index));

  /// Why a recording can't play yet: its audio hasn't synced down.
  static const String notDownloaded =
      'The audio is not on this device yet. It downloads when you’re online.';

  @override
  Future<void> open(
    Recording recording,
    BlobStore blobs,
    Future<bool> Function(String) fetch,
  ) async {
    for (final sha in recording.blobs) {
      // Awaited apart: dart2wasm miscompiles `!await a && await b`.
      final here = await blobs.has(sha);
      if (!here && !await fetch(sha)) {
        throw const AudioUnavailable(notDownloaded);
      }
    }
    final groups = recording.joinable
        ? [recording.blobs.toList()]
        : [
            for (final sha in recording.blobs) [sha],
          ];
    _release();
    final sources = <({String uri, bool isFile})>[];
    for (final group in groups) {
      final source = await audioUriFor(blobs, group, recording.mime);
      if (source == null) {
        for (final s in sources) {
          releaseAudioUri(s.uri);
        }
        throw const AudioUnavailable(notDownloaded);
      }
      sources.add(source);
    }
    _sources = sources;
    _parts = recording.parts;
    _mime = recording.mime;
    _playing = false;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _load(0);
    } on Object catch (e) {
      debugPrint('Playback failed to load: $e');
      throw const AudioUnavailable('This recording cannot be played here');
    }
  }

  Future<void> _load(int index) async {
    _index = index;
    final source = _sources[index];
    await _player.setSource(
      source.isFile
          ? DeviceFileSource(source.uri, mimeType: _mime)
          : UrlSource(source.uri, mimeType: _mime),
    );
  }

  /// The end of a source: on to the next part, or the end.
  Future<void> _next() async {
    if (_index + 1 >= _sources.length) {
      _playing = false;
      _completed.add(null);
      return;
    }
    await _load(_index + 1);
    if (_playing) await _player.resume();
  }

  @override
  Future<void> play() {
    _playing = true;
    return _player.resume();
  }

  @override
  Future<void> pause() {
    _playing = false;
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_sources.length <= 1) return _player.seek(position);
    final at = _parts.partAt(position.inMilliseconds);
    if (at.index != _index) {
      await _load(at.index);
      if (_playing) await _player.resume();
    }
    await _player.seek(Duration(milliseconds: at.offsetMs));
  }

  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<void> get completed => _completed.stream;

  void _release() {
    for (final source in _sources) {
      releaseAudioUri(source.uri);
    }
    _sources = const [];
  }

  @override
  Future<void> dispose() async {
    _release();
    await _player.dispose();
    await _positions.close();
    await _completed.close();
  }
}
