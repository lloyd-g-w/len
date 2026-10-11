import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:len/data/blob_store.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/backends/audio_backends.dart';

/// Records "audio" without a microphone: [stop] returns [bytes].
class FakeCapture implements AudioCapture {
  FakeCapture(this.log, {this.allow = true, this.bytes});

  final List<String> log;
  final bool allow;
  final Uint8List? bytes;
  final StreamController<double> _levels = StreamController.broadcast(sync: true);
  final List<CapturedAudio> discarded = [];

  void emitLevel(double level) => _levels.add(level);

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> requestPermission() async {
    log.add('permission');
    return allow;
  }

  @override
  Future<void> start() async => log.add('start');

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> resume() async => log.add('resume');

  @override
  Future<CapturedAudio?> stop() async {
    log.add('stop');
    final data = bytes ?? Uint8List.fromList(List.generate(64, (i) => i));
    return (file: XFile.fromData(data, mimeType: 'audio/mp4'), mime: 'audio/mp4');
  }

  @override
  Future<void> discard(CapturedAudio audio) async => discarded.add(audio);

  @override
  Future<void> dispose() async => log.add('dispose');
}

/// Plays nothing; tests drive the position with [emit] / [finish].
class FakePlayback implements AudioPlayback {
  FakePlayback(this.log, {this.fail = false});

  final List<String> log;
  final bool fail;
  final StreamController<Duration> _positions = StreamController.broadcast(sync: true);
  final StreamController<void> _completed = StreamController.broadcast(sync: true);
  Recording? opened;

  void emit(int ms) => _positions.add(Duration(milliseconds: ms));
  void finish() => _completed.add(null);

  @override
  Future<void> open(
    Recording recording,
    BlobStore blobs,
    Future<bool> Function(String) fetch,
  ) async {
    log.add('open ${recording.title}');
    if (fail) throw const AudioUnavailable('Cannot play');
    opened = recording;
  }

  @override
  Future<void> play() async => log.add('play');

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> seek(Duration position) async => log.add('seek ${position.inMilliseconds}');

  @override
  Future<void> setRate(double rate) async => log.add('rate $rate');

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> dispose() async => log.add('dispose player');
}

/// Fake backends sharing one [log]; [captures] / [players] are the
/// instances handed out.
class FakeAudio {
  FakeAudio({this.allow = true, this.unavailable});

  final bool allow;
  final String? unavailable;
  final List<String> log = [];
  final List<FakeCapture> captures = [];
  final List<FakePlayback> players = [];

  FakeCapture get capture => captures.last;
  FakePlayback get player => players.last;

  late final AudioBackends backends = AudioBackends(
    capture: () {
      final capture = FakeCapture(log, allow: allow);
      captures.add(capture);
      return capture;
    },
    playback: () {
      final player = FakePlayback(log);
      players.add(player);
      return player;
    },
    unavailable: () async => unavailable,
  );
}
