import 'dart:async';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../platform/audio_files.dart';
import 'audio_backends.dart';

/// [AudioCapture] with `package:record` (Android, Linux, Windows, web).
///
/// Records AAC in MP4 (`.m4a`) where the platform can — everywhere except
/// browsers without an AAC encoder (Chrome, Firefox), which record Opus in
/// WebM — mono at 64 kbit/s (≈ 29 MB per hour).
class RecordCapture implements AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  String _mime = 'audio/mp4';
  StreamSubscription<Amplitude>? _amplitude;
  final StreamController<double> _levels = StreamController.broadcast();

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final (encoder, mime, extension) = await _format();
    _mime = mime;
    try {
      await _recorder.start(
        RecordConfig(encoder: encoder, bitRate: 64000, numChannels: 1),
        path: await newCaptureTarget(extension),
      );
    } on Object catch (e) {
      throw AudioUnavailable('Could not start recording ($e).');
    }
    _amplitude = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) => _levels.add(levelOf(a.current)));
  }

  Future<(AudioEncoder, String, String)> _format() async {
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return (AudioEncoder.aacLc, 'audio/mp4', 'm4a');
    }
    if (kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus)) {
      return (AudioEncoder.opus, 'audio/webm', 'webm');
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      return (AudioEncoder.wav, 'audio/wav', 'wav');
    }
    throw const AudioUnavailable('This device has no supported audio encoder.');
  }

  /// Maps a level in dBFS (−160…0) to 0…1 over the audible −50…0 dB.
  @visibleForTesting
  static double levelOf(double dbfs) =>
      dbfs.isFinite ? math.max(0, math.min(1, (dbfs + 50) / 50)) : 0;

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<CapturedAudio?> stop() async {
    await _amplitude?.cancel();
    _amplitude = null;
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) return null;
    return (file: XFile(path, mimeType: _mime), mime: _mime);
  }

  @override
  Future<void> discard(CapturedAudio audio) => deleteCapture(audio.file.path);

  @override
  Future<void> dispose() async {
    await _amplitude?.cancel();
    await _levels.close();
    await _recorder.dispose();
  }
}
