import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../ink/lab/input_recording.dart';
import '../../ink/lab/recording_codec.dart';
import '../../platform/file_export.dart';

const _recordingTypes = [
  XTypeGroup(
    label: 'Ink Lab recording',
    extensions: [RecordingCodec.extension, 'json'],
    mimeTypes: [RecordingCodec.mime],
    // iOS needs UTIs; JSON covers `.leninput` files saved by the lab.
    uniformTypeIdentifiers: ['public.json', 'public.data'],
  ),
];

/// Saves (desktop), shares (mobile) or downloads (web) [recording] as a
/// `.leninput` file. Failures are shown in a SnackBar.
Future<void> saveRecording(BuildContext context, InputRecording recording) async {
  final messenger = ScaffoldMessenger.of(context);
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9T]'), '');
  try {
    await saveOrShare(
      RecordingCodec.encode(recording),
      name: 'inklab-$stamp.${RecordingCodec.extension}',
      mime: RecordingCodec.mime,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save the recording: $e')));
  }
}

/// Lets the user pick a `.leninput` file and decodes it. Returns null if
/// cancelled or unreadable (the user has then been told why).
Future<InputRecording?> openRecording(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await openFile(acceptedTypeGroups: _recordingTypes);
    if (file == null) return null;
    return RecordingCodec.decode(await file.readAsBytes());
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Not an Ink Lab recording: ${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open the recording: $e')));
  }
  return null;
}
