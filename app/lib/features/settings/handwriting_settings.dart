import 'dart:async';

import 'package:flutter/material.dart';

import '../../ink/recognition/handwriting_recognizer.dart';
import '../../ink/recognition/recognition_languages.dart';
import '../../ink/recognition/recognition_service.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import 'settings_section.dart';

/// Handwriting recognition: language, background indexing for search and
/// the language model (download / delete).
class HandwritingSettings extends StatelessWidget {
  const HandwritingSettings({super.key, required this.recognition});

  final RecognitionService recognition;

  static String _name(String tag) => RecognitionLanguages.byTag(tag)?.name ?? tag;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([recognition, recognition.indexer]),
      builder: (context, _) => SettingsSection(
        title: 'Handwriting',
        icon: Icons.draw_outlined,
        description:
            'Search your handwriting, and convert it to text: select it with the lasso, '
            'then tap Convert to text. Recognition runs on this device; nothing is sent anywhere.',
        children: recognition.isSupported
            ? [_language(context), _indexing(context), _model(context)]
            : [
                SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Not available here',
                  subtitle: recognition.unsupportedReason,
                ),
              ],
      ),
    );
  }

  Widget _language(BuildContext context) => SettingsTile(
    icon: Icons.translate_rounded,
    title: 'Language',
    subtitle: recognition.isAutomaticLanguage
        ? 'Same as the device · ${_name(recognition.language)}'
        : _name(recognition.language),
    onTap: () => unawaited(_pickLanguage(context)),
    trailing: const Icon(Icons.chevron_right_rounded),
  );

  Future<void> _pickLanguage(BuildContext context) async {
    const automatic = '';
    final current = recognition.isAutomaticLanguage ? automatic : recognition.language;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Handwriting language'),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: automatic,
                  title: Text('Same as the device · ${_name(recognition.automaticLanguage)}'),
                ),
                for (final l in RecognitionLanguages.all)
                  RadioListTile<String>(value: l.tag, title: Text(l.name)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await recognition.setLanguage(picked == automatic ? null : picked);
  }

  Widget _indexing(BuildContext context) {
    final indexer = recognition.indexer;
    final pending = indexer.pendingCount;
    final String status;
    if (!recognition.indexingEnabled) {
      status = 'Off: search finds typed text and PDFs only.';
    } else if (recognition.modelStatus != ModelStatus.downloaded) {
      status = 'Waits for the language model.';
    } else if (pending > 0) {
      status = indexer.isIndexing
          ? 'Recognising… $pending page${pending == 1 ? '' : 's'} to go.'
          : '$pending page${pending == 1 ? '' : 's'} waiting for a quiet moment.';
    } else {
      final lines = indexer.lineCount;
      status = 'Up to date: $lines line${lines == 1 ? '' : 's'} recognised.';
    }
    return SettingsTile(
      icon: Icons.manage_search_rounded,
      title: 'Search handwriting',
      subtitle: 'Recognises handwriting in the background while you are not writing. $status',
      onTap: () => unawaited(recognition.setIndexingEnabled(!recognition.indexingEnabled)),
      trailing: Switch(
        value: recognition.indexingEnabled,
        onChanged: (v) => unawaited(recognition.setIndexingEnabled(v)),
      ),
    );
  }

  Widget _model(BuildContext context) {
    final status = recognition.modelStatus;
    final name = _name(recognition.language);
    final failed = recognition.downloadError != null && status == ModelStatus.missing;
    return SettingsTile(
      icon: Icons.download_for_offline_outlined,
      title: 'Language model',
      subtitle: switch (status) {
        ModelStatus.downloaded => '$name is on this device.',
        ModelStatus.downloading => 'Downloading $name…',
        ModelStatus.missing when failed => 'The download failed. Check the connection.',
        ModelStatus.missing =>
          'Not downloaded (${RecognitionService.modelSize}). With search on, it downloads '
              'over Wi-Fi.',
        ModelStatus.unknown => 'Checking…',
      },
      trailing: switch (status) {
        ModelStatus.downloaded => TextButton(
          onPressed: () => unawaited(_delete(context, name)),
          child: const Text('Delete'),
        ),
        ModelStatus.missing => FilledButton.tonal(
          onPressed: () => unawaited(recognition.download()),
          child: const Text('Download'),
        ),
        _ => null,
      },
      below: status == ModelStatus.downloading
          ? const Padding(
              padding: EdgeInsets.only(bottom: Gaps.xs),
              child: LinearProgressIndicator(),
            )
          : null,
    );
  }

  Future<void> _delete(BuildContext context, String name) async {
    final ok = await confirmAction(
      context,
      title: 'Delete the $name model?',
      message:
          'Handwriting stays searchable as recognised so far; new writing is not '
          'recognised until the model is downloaded again.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await recognition.deleteModel();
  }
}
