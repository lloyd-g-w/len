import 'dart:async';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../domain/recording.dart';
import '../../../platform/audio_files.dart';
import '../adts.dart';
import 'audio_backends.dart';

/// [AudioCapture] with `package:record` (Android, Linux, Windows, web).
///
/// Natively it records AAC in ADTS frames (`.aac`, mono, 64 kbit/s ≈ 29 MB
/// per hour), which stays playable when cut off: on Android and Windows
/// the recorder streams the frames to Len, which writes them to the file
/// itself and splits files between two frames without stopping the
/// recorder (no audio lost); on Linux `ffmpeg` writes the file (`.aac`
/// selects ADTS) and a split restarts the recorder. Browsers record AAC in
/// MP4 where they can (Safari), else Opus in WebM, kept in memory until
/// stopped; a split restarts the recorder there too.
class RecordCapture implements AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  CaptureFormat? _format;
  AudioEncoder _encoder = AudioEncoder.aacLc;
  StreamSubscription<Amplitude>? _amplitude;
  final StreamController<double> _levels = StreamController.broadcast();

  /// Android and Windows: frames streamed to Len and written by [_Writer].
  bool get _streams =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);
  _Writer? _writer;
  Future<void>? _streamDone;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<CaptureFormat> format() async => _format ??= await _choose();

  Future<CaptureFormat> _choose() async {
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      _encoder = AudioEncoder.aacLc;
      return kIsWeb
          ? (mime: 'audio/mp4', extension: 'm4a', recoverable: false)
          : (mime: Recording.adtsMime, extension: 'aac', recoverable: true);
    }
    if (kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus)) {
      _encoder = AudioEncoder.opus;
      return (mime: 'audio/webm', extension: 'webm', recoverable: false);
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      _encoder = AudioEncoder.wav;
      return (mime: 'audio/wav', extension: 'wav', recoverable: false);
    }
    throw const AudioUnavailable('This device has no supported audio encoder.');
  }

  bool get _adts => _format?.mime == Recording.adtsMime;

  @override
  Future<void> start(String? path) async {
    final format = await this.format();
    final target = path ?? await newCaptureTarget(format.extension);
    final config = RecordConfig(encoder: _encoder, bitRate: 64000, numChannels: 1);
    try {
      if (_streams && _adts) {
        _writer = _Writer(target);
        final frames = await _recorder.startStream(config);
        final done = Completer<void>();
        _streamDone = done.future;
        frames.listen((bytes) => _writer?.add(bytes), onDone: done.complete, onError: (_) {});
      } else {
        await _recorder.start(config, path: target);
      }
    } on Object catch (e) {
      throw AudioUnavailable('Could not start recording ($e).');
    }
    _amplitude ??= _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) => _levels.add(levelOf(a.current)));
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
  Future<CapturedAudio?> split(String? nextPath) async {
    final writer = _writer;
    if (writer != null) {
      // Frames arrive whole: the next one goes to the new file.
      final format = await this.format();
      _writer = _Writer(nextPath ?? await newCaptureTarget(format.extension));
      return writer.close(format.mime);
    }
    final finished = await _stopRecorder();
    await start(nextPath);
    return finished;
  }

  @override
  Future<CapturedAudio?> stop() async {
    unawaited(_amplitude?.cancel());
    _amplitude = null;
    return _stopRecorder();
  }

  Future<CapturedAudio?> _stopRecorder() async {
    final mime = _format?.mime ?? 'audio/mp4';
    final stopped = await _recorder.stop();
    final writer = _writer;
    if (writer != null) {
      // The last frames still arrive after the recorder stopped.
      await _streamDone?.timeout(const Duration(seconds: 2), onTimeout: () {});
      _writer = null;
      return writer.close(mime);
    }
    if (stopped == null || stopped.isEmpty) return null;
    final file = XFile(stopped, mimeType: mime);
    final duration = _adts ? await AdtsReader.measure(file.openRead()) : null;
    return (file: file, mime: mime, durationMs: duration);
  }

  @override
  Future<void> discard(CapturedAudio audio) => deleteCapture(audio.file.path);

  @override
  Future<void> dispose() async {
    unawaited(_amplitude?.cancel());
    await _levels.close();
    await _recorder.dispose();
  }
}

/// Writes streamed ADTS frames to a file, counting their audio.
class _Writer {
  _Writer(this.path) : _sink = openCaptureSink(path);

  final String path;
  final StreamSink<List<int>> _sink;
  final AdtsReader _reader = AdtsReader();

  void add(Uint8List bytes) {
    final frames = _reader.add(bytes);
    if (frames.isNotEmpty) _sink.add(frames);
  }

  Future<CapturedAudio> close(String mime) async {
    await _sink.close();
    return (file: XFile(path, mimeType: mime), mime: mime, durationMs: _reader.durationMs);
  }
}
