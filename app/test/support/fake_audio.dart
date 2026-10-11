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

/// A background keep-alive (Android's foreground service) that only logs;
/// tests press its notification buttons with [press].
class FakeKeepAlive implements RecordingKeepAlive {
  FakeKeepAlive(this.log, {this.canShow = true});

  final List<String> log;
  bool canShow;
  bool shown = false;
  final StreamController<KeepAliveAction> _actions = StreamController.broadcast(sync: true);

  void press(KeepAliveAction action) => _actions.add(action);

  @override
  Stream<KeepAliveAction> get actions => _actions.stream;

  @override
  Future<void> prepare() async => log.add('keepalive prepare');

  @override
  Future<bool> show({required String title, required bool paused, required int elapsedMs}) async {
    log.add('keepalive show $title ${paused ? 'paused' : 'recording'} $elapsedMs');
    shown = canShow;
    return canShow;
  }

  @override
  Future<void> hide() async {
    log.add('keepalive hide');
    shown = false;
  }

  @override
  Future<void> dispose() async => log.add('keepalive dispose');
}

/// Fake backends sharing one [log]; [captures] / [players] are the
/// instances handed out.
class FakeAudio {
  FakeAudio({this.allow = true, this.unavailable, this.background = false, this.canShow = true});

  final bool allow;
  final String? unavailable;

  /// Whether the platform has a keep-alive ([keepAlives]) at all.
  final bool background;

  /// Whether the keep-alive manages to start.
  final bool canShow;
  final List<FakeKeepAlive> keepAlives = [];
  FakeKeepAlive get keepAlive => keepAlives.last;
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
    keepAlive: background
        ? () {
            final keepAlive = FakeKeepAlive(log, canShow: canShow);
            keepAlives.add(keepAlive);
            return keepAlive;
          }
        : null,
  );
}
