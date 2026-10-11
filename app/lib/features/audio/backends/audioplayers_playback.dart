import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../../data/blob_store.dart';
import '../../../domain/recording.dart';
import '../../../platform/audio_files.dart';
import 'audio_backends.dart';

/// [AudioPlayback] with `package:audioplayers`: ExoPlayer on Android,
/// GStreamer on Linux, Media Foundation on Windows, an `<audio>` element in
/// browsers. Natively the player streams the blob's file; browsers play a
/// blob URL.
class AudioplayersPlayback implements AudioPlayback {
  final AudioPlayer _player = AudioPlayer();
  String? _uri;

  @override
  Future<void> open(
    Recording recording,
    BlobStore blobs,
    Future<bool> Function(String) fetch,
  ) async {
    var source = await audioUriFor(blobs, recording.blob, recording.mime);
    if (source == null && await fetch(recording.blob)) {
      source = await audioUriFor(blobs, recording.blob, recording.mime);
    }
    if (source == null) {
      throw const AudioUnavailable('The audio is not on this device yet. Sync and try again.');
    }
    _release();
    _uri = source.uri;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(
        source.isFile
            ? DeviceFileSource(source.uri, mimeType: recording.mime)
            : UrlSource(source.uri, mimeType: recording.mime),
      );
    } on Object catch (e) {
      throw AudioUnavailable('This recording cannot be played here ($e).');
    }
  }

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  void _release() {
    if (_uri case final uri?) releaseAudioUri(uri);
    _uri = null;
  }

  @override
  Future<void> dispose() async {
    _release();
    await _player.dispose();
  }
}
