import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ink/recognition/handwriting_recognizer.dart';
import '../../ink/recognition/recognition_languages.dart';
import '../../ink/recognition/recognition_service.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/sheet_parts.dart';
import 'settings_section.dart';

/// Handwriting recognition: background indexing for search, the language
/// and, until it is on the device, the language model's download.
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
        description:
            'Search your handwriting, and convert it to text: select it with the lasso, '
            'then tap Convert to text. Recognition runs on this device; nothing is sent anywhere.',
        children: recognition.isSupported
            ? [
                _indexing(context),
                _language(context),
                if (recognition.modelStatus != ModelStatus.downloaded) _model(context),
              ]
            : [
                SettingsTile(
                  icon: Symbols.info_rounded,
                  title: 'Not available here',
                  subtitle: recognition.unsupportedReason,
                ),
              ],
      ),
    );
  }

  Widget _language(BuildContext context) => SettingsTile(
    icon: Symbols.translate_rounded,
    title: 'Language',
    subtitle: recognition.isAutomaticLanguage
        ? 'Same as the device · ${_name(recognition.language)}'
        : _name(recognition.language),
    onTap: () => unawaited(_pickLanguage(context)),
    trailing: const Icon(Symbols.chevron_right_rounded),
  );

  Future<void> _pickLanguage(BuildContext context) async {
    const automatic = '';
    final current = recognition.isAutomaticLanguage ? automatic : recognition.language;
    final picked = await showDialogOrSheet<String>(
      context: context,
      maxWidth: 440,
      maxHeight: 640,
      builder: (context, wide) => _LanguageSheet(
        current: current,
        automaticLabel: 'Same as the device · ${_name(recognition.automaticLanguage)}',
        wide: wide,
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
      status = lines == 0
          ? 'Up to date: no handwriting yet.'
          : 'Up to date: $lines line${lines == 1 ? '' : 's'} recognised.';
    }
    return SettingsTile(
      icon: Symbols.manage_search_rounded,
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
      icon: status == ModelStatus.downloaded
          ? Symbols.offline_pin_rounded
          : Symbols.download_for_offline_rounded,
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
        ModelStatus.missing => FilledButton.tonal(
          onPressed: () => unawaited(recognition.download()),
          child: Text(failed ? 'Try again' : 'Download'),
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
}

/// The handwriting language: a task sheet listing the languages; choosing
/// one closes it.
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.current, required this.automaticLabel, required this.wide});

  /// The chosen tag; '' = the device's language.
  final String current;
  final String automaticLabel;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: wide ? double.infinity : media.size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Gaps.xl, wide ? Gaps.lg : 0, Gaps.md, Gaps.sm),
            child: SheetHeader(
              title: 'Handwriting language',
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
          Flexible(
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(bottom: Gaps.md + media.padding.bottom),
                children: [
                  RadioListTile<String>(value: '', title: Text(automaticLabel)),
                  for (final l in RecognitionLanguages.all)
                    RadioListTile<String>(value: l.tag, title: Text(l.name)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
