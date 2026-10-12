import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/blob_store.dart';

/// A new temporary file for a capture with file [extension] (e.g. `m4a`).
Future<String> newCaptureTarget(String extension) async {
  final dir = await getTemporaryDirectory();
  await dir.create(recursive: true);
  return p.join(dir.path, 'len-recording-${DateTime.now().microsecondsSinceEpoch}.$extension');
}

/// Writes a capture streamed by the recorder to file [path].
StreamSink<List<int>> openCaptureSink(String path) => File(path).openWrite();

/// Deletes a finished capture's temporary file (after it became a blob).
Future<void> deleteCapture(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
}

/// Why recording cannot work on this device, or null. On Linux the
/// `record` package captures with PulseAudio's `parecord` (also provided
/// by PipeWire) and encodes with `ffmpeg`, both looked up on the `PATH`.
Future<String?> recordingUnavailableReason() async {
  if (!Platform.isLinux) return null;
  final missing = [
    for (final tool in ['parecord', 'ffmpeg'])
      if (!_onPath(tool)) tool,
  ];
  if (missing.isEmpty) return null;
  return 'Recording needs ${missing.join(' and ')} '
      '(packages pulseaudio-utils / pipewire-pulse and ffmpeg).';
}

bool _onPath(String tool) {
  final path = Platform.environment['PATH'] ?? '';
  return path.split(':').any((dir) => dir.isNotEmpty && File(p.join(dir, tool)).existsSync());
}

/// Where a player can read [blobs] joined into one stream (a single blob,
/// or parts in a format that joins by concatenation, see
/// `Recording.joinable`): a single blob's file, or a temporary file of the
/// parts joined (streamed, never loaded into memory here). Null if one is
/// not on the device.
Future<({String uri, bool isFile})?> audioUriFor(
  BlobStore blobs,
  List<String> shas,
  String mime,
) async {
  for (final sha in shas) {
    if (!await blobs.has(sha)) return null;
  }
  if (shas.length == 1) {
    final path = blobs.localPath(shas.single);
    return path == null ? null : (uri: path, isFile: true);
  }
  final dir = await getTemporaryDirectory();
  await dir.create(recursive: true);
  final joined = File(
    p.join(dir.path, 'len-play-${DateTime.now().microsecondsSinceEpoch}.${_extension(mime)}'),
  );
  final sink = joined.openWrite();
  try {
    for (final sha in shas) {
      await sink.addStream(blobs.openRead(sha));
    }
  } finally {
    await sink.close();
  }
  return (uri: joined.path, isFile: true);
}

String _extension(String mime) => mime == 'audio/aac' ? 'aac' : 'audio';

/// Frees what [audioUriFor] allocated: a joined temporary file.
void releaseAudioUri(String uri) {
  if (!p.basename(uri).startsWith('len-play-')) return;
  try {
    File(uri).deleteSync();
  } on FileSystemException {
    // Already gone.
  }
}
