import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:len/data/blob_store.dart';
import 'package:len/data/spool_storage.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/adts.dart';
import 'package:len/features/audio/backends/audio_backends.dart';
import 'package:len/platform/media_controls_api.dart';

/// Raw AAC: [count] ADTS frames of silence at [sampleRate] (16 kHz: 64 ms
/// per frame).
Uint8List adtsFrames(int count, {int sampleRate = 16000, int payload = 9}) {
  final index = AdtsReader.sampleRates.indexOf(sampleRate);
  final length = 7 + payload;
  final frame = [
    0xFF, 0xF1, (1 << 6) | (index << 2), (1 << 6) | (length >> 11), (length >> 3) & 0xFF, //
    ((length & 7) << 5) | 0x1F, 0xFC, ...List.filled(payload, 0),
  ];
  return Uint8List.fromList([for (var i = 0; i < count; i++) ...frame]);
}

/// Records "audio" without a microphone: [stop] returns [bytes] — or,
/// with an [adts] format and a [spool], what the test [write]s into the
/// spool file being captured (like the real recorder writing raw AAC).
class FakeCapture implements AudioCapture {
  FakeCapture(this.log, {this.allow = true, this.bytes, this.adts = false, this.spool});

  final List<String> log;
  final bool allow;
  final Uint8List? bytes;
  final bool adts;
  final MemorySpoolStorage? spool;
  final StreamController<double> _levels = StreamController.broadcast(sync: true);
  final List<CapturedAudio> discarded = [];

  /// The files captured into, in order.
  final List<String?> paths = [];

  void emitLevel(double level) => _levels.add(level);

  /// Appends [data] to the file being captured (spool files only).
  void write(Uint8List data) {
    final name = paths.last!.substring('spool/'.length);
    spool!.files[name] = Uint8List.fromList([...?spool!.files[name], ...data]);
  }

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> requestPermission() async {
    log.add('permission');
    return allow;
  }

  @override
  Future<CaptureFormat> format() async => adts
      ? (mime: Recording.adtsMime, extension: 'aac', recoverable: true)
      : (mime: 'audio/mp4', extension: 'm4a', recoverable: false);

  @override
  Future<void> start(String? path) async {
    log.add('start');
    paths.add(path);
  }

  /// Makes [pause] and [resume] throw (the recorder refused).
  bool failSwitch = false;

  @override
  Future<void> pause() async {
    if (failSwitch) throw StateError('pause refused');
    log.add('pause');
  }

  @override
  Future<void> resume() async {
    if (failSwitch) throw StateError('resume refused');
    log.add('resume');
  }

  /// A split waits for this (a recorder restarting, as on Linux).
  Future<void>? holdSplit;

  @override
  Future<CapturedAudio?> split(String? nextPath) async {
    log.add('split');
    await holdSplit;
    final finished = _finish();
    paths.add(nextPath);
    return finished;
  }

  /// A stop waits for this (saving a recording takes a while).
  Future<void>? holdStop;

  @override
  Future<CapturedAudio?> stop() async {
    log.add('stop');
    await holdStop;
    return _finish();
  }

  CapturedAudio _finish() {
    final path = paths.lastOrNull;
    if (path != null && spool != null) {
      final data = spool!.files[path.substring('spool/'.length)] ?? Uint8List(0);
      final frames = AdtsReader.readAll(data);
      return (
        file: XFile.fromData(frames.frames, mimeType: Recording.adtsMime, path: path),
        mime: Recording.adtsMime,
        durationMs: frames.durationMs,
      );
    }
    final data = bytes ?? Uint8List.fromList(List.generate(64, (i) => i));
    final mime = adts ? Recording.adtsMime : 'audio/mp4';
    return (file: XFile.fromData(data, mimeType: mime), mime: mime, durationMs: null);
  }

  @override
  Future<void> discard(CapturedAudio audio) async => discarded.add(audio);

  @override
  Future<void> dispose() async => log.add('dispose');
}

/// Plays nothing; tests drive the position with [emit] / [finish].
class FakePlayback implements AudioPlayback {
  FakePlayback(this.log, {this.fail = false, this.holds = const {}, this.missing = const {}});

  final List<String> log;
  final bool fail;
  final StreamController<Duration> _positions = StreamController.broadcast(sync: true);
  final StreamController<void> _completed = StreamController.broadcast(sync: true);
  Recording? opened;

  /// Opening a recording titled as a key waits for its future (a slow
  /// download).
  final Map<String, Future<void>> holds;

  /// Blobs that can't be had: opening audio with one of them fails, as
  /// the real player's does.
  final Set<String> missing;

  void emit(int ms) => _positions.add(Duration(milliseconds: ms));
  void finish() => _completed.add(null);

  @override
  Future<void> open(
    Recording recording,
    BlobStore blobs,
    Future<bool> Function(String) fetch,
  ) async {
    log.add('open ${recording.title}');
    await holds[recording.title];
    if (fail || recording.blobs.any(missing.contains)) {
      throw const AudioUnavailable('Cannot play');
    }
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
  Future<void> setVolume(double volume) async => log.add('volume $volume');

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

/// The system's media controls, logging what they show; tests send
/// what the user (or the system) asks for with [send].
class FakeMediaControls implements MediaControls {
  FakeMediaControls(this.log, {this.background = true});

  final List<String> log;

  /// Whether playback continues in the background once shown.
  bool background;
  NowPlaying? shown;
  final StreamController<MediaCommand> _commands = StreamController.broadcast(sync: true);

  void send(MediaEvent event, [int? positionMs]) =>
      _commands.add((event: event, positionMs: positionMs));

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<bool> show(NowPlaying now) async {
    final state = now.playing ? 'playing' : 'paused';
    log.add('controls ${now.title} · ${now.album} $state ${now.positionMs}/${now.durationMs}');
    shown = now;
    return background;
  }

  @override
  Future<void> hide() async {
    log.add('controls hide');
    shown = null;
  }

  @override
  Future<void> dispose() async => log.add('controls dispose');
}

/// Fake backends sharing one [log]; [captures] / [players] are the
/// instances handed out.
class FakeAudio {
  FakeAudio({
    this.allow = true,
    this.unavailable,
    this.background = false,
    this.canShow = true,
    this.adts = false,
    this.spool,
    this.mediaControls = false,
  });

  /// Whether the platform has media controls ([controls]) at all.
  final bool mediaControls;
  final List<FakeMediaControls> controls = [];

  /// Whether captures record raw AAC (as natively) rather than MP4.
  final bool adts;

  /// Where captures of recoverable audio are written (null: nowhere, as
  /// in browsers).
  final MemorySpoolStorage? spool;

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

  /// Players' opening of recordings by title waits for these (see
  /// [FakePlayback.holds]).
  final Map<String, Future<void>> holds = {};

  /// Blobs players can't open (see [FakePlayback.missing]).
  final Set<String> missingBlobs = {};

  FakeCapture get capture => captures.last;
  FakePlayback get player => players.last;

  late final AudioBackends backends = AudioBackends(
    capture: () {
      final capture = FakeCapture(log, allow: allow, adts: adts, spool: spool);
      captures.add(capture);
      return capture;
    },
    playback: () {
      final player = FakePlayback(log, holds: holds, missing: missingBlobs);
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
    mediaControls: mediaControls
        ? () {
            final created = FakeMediaControls(log);
            controls.add(created);
            return created;
          }
        : null,
    spool: () async => spool,
  );
}
