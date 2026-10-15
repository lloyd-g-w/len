import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ink/recognition/handwriting_recognizer.dart';
import '../../../ink/recognition/recognition_languages.dart';
import '../../../ink/recognition/recognition_service.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';

/// Makes sure the handwriting model for the recognition language is on the
/// device, offering to download it; true when it is (or has just been)
/// downloaded.
Future<bool> ensureRecognitionModel(BuildContext context, RecognitionService recognition) async {
  if (recognition.modelStatus != ModelStatus.downloaded) await recognition.refreshModel();
  if (recognition.modelStatus == ModelStatus.downloaded) return true;
  if (!context.mounted) return false;
  final name = RecognitionLanguages.byTag(recognition.language)?.name ?? recognition.language;
  return await showDialog<bool>(
        context: context,
        builder: (context) => _DownloadDialog(recognition: recognition, languageName: name),
      ) ??
      false;
}

/// Offers to download the model, showing progress and errors.
class _DownloadDialog extends StatelessWidget {
  const _DownloadDialog({required this.recognition, required this.languageName});

  final RecognitionService recognition;
  final String languageName;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: recognition,
    builder: (context, _) {
      final downloading = recognition.modelStatus == ModelStatus.downloading;
      final error = recognition.downloadError;
      return AppDialog(
        title: 'Download handwriting model?',
        content: DialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recognising $languageName handwriting needs its model on this device '
                '(${RecognitionService.modelSize}). Recognition then works offline.',
              ),
              if (downloading) ...[
                const SizedBox(height: Gaps.lg),
                const LinearProgressIndicator(),
              ],
              if (error != null && !downloading) ...[
                const SizedBox(height: Gaps.md),
                Text(
                  'The download failed. Check the connection and try again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: downloading
                ? null
                : () async {
                    final ok = await recognition.download();
                    if (ok && context.mounted) Navigator.pop(context, true);
                  },
            child: Text(
              downloading
                  ? 'Downloading…'
                  : error != null
                  ? 'Try again'
                  : 'Download',
            ),
          ),
        ],
      );
    },
  );
}
