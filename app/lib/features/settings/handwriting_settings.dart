import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ink/recognition/handwriting_recognizer.dart';
import '../../ink/recognition/recognition_languages.dart';
import '../../ink/recognition/recognition_service.dart';
import '../../ui/app_switch.dart';
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
      builder: (context, _) => recognition.isSupported
          ? SettingsSection(
              title: 'Handwriting',
              description:
                  'Search your handwriting and convert it to text: select it with the lasso, '
                  'then choose Convert to text. Recognition runs on this device in the '
                  'background while you aren’t writing; the text syncs with your notes, so your '
                  'other devices find your handwriting too.',
              children: [
                _indexing(context),
                _language(context),
                if (recognition.modelStatus != ModelStatus.downloaded) _model(context),
              ],
            )
          // Nothing recognises here: a caption, no row (nothing to do).
          : SettingsSection(title: 'Handwriting', description: _synced(), children: const []),
    );
  }

  /// Where nothing recognises: what came from devices that do.
  String _synced() {
    final indexer = recognition.indexer;
    final lines = indexer.lineCount;
    const base =
        'Handwriting written on Android is recognised there and synced, so search finds it here';
    if (indexer.isIndexing) return '$base. Adding handwriting from your other devices…';
    return lines == 0 ? base : '$base. $lines line${lines == 1 ? '' : 's'} so far';
  }

  Widget _language(BuildContext context) => SettingsTile(
    icon: Symbols.translate_sharp,
    title: 'Language',
    subtitle: recognition.isAutomaticLanguage
        ? 'Same as the device, ${_name(recognition.language)}'
        : _name(recognition.language),
    onTap: () => unawaited(_pickLanguage(context)),
    trailing: const Icon(Symbols.chevron_right_sharp),
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
        automaticLabel: 'Same as the device, ${_name(recognition.automaticLanguage)}',
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
      status = 'Off: search finds typed text and PDFs only';
    } else if (recognition.modelStatus != ModelStatus.downloaded) {
      status = 'Waits for the handwriting model';
    } else if (pending > 0) {
      status = indexer.isIndexing
          ? 'Recognising… $pending page${pending == 1 ? '' : 's'} to go'
          : '$pending page${pending == 1 ? '' : 's'} waiting for a quiet moment';
    } else {
      final lines = indexer.lineCount;
      status = lines == 0 ? 'Up to date' : 'Up to date, $lines line${lines == 1 ? '' : 's'}';
    }
    return SettingsTile(
      icon: Symbols.manage_search_sharp,
      title: 'Search handwriting',
      subtitle: status,
      onTap: () => unawaited(recognition.setIndexingEnabled(!recognition.indexingEnabled)),
      trailing: ExcludeFocus(
        // The row is the target and the focus stop.
        child: AppSwitch(
          padded: false,
          value: recognition.indexingEnabled,
          onChanged: (v) => unawaited(recognition.setIndexingEnabled(v)),
        ),
      ),
    );
  }

  Widget _model(BuildContext context) {
    final status = recognition.modelStatus;
    final name = _name(recognition.language);
    final failed = recognition.downloadError != null && status == ModelStatus.missing;
    return SettingsTile(
      icon: status == ModelStatus.downloaded
          ? Symbols.offline_pin_sharp
          : Symbols.download_for_offline_sharp,
      title: 'Handwriting model',
      subtitle: switch (status) {
        ModelStatus.downloaded => '$name is on this device',
        ModelStatus.downloading => 'Downloading $name…',
        ModelStatus.missing when failed => 'The download failed. Check the connection.',
        ModelStatus.missing =>
          'Not downloaded (${RecognitionService.modelSize}). With search on, it downloads '
              'over Wi-Fi.',
        ModelStatus.unknown => 'Checking…',
      },
      trailing: switch (status) {
        ModelStatus.missing => OutlinedButton(
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

/// The handwriting language: a task sheet listing the languages, opened at
/// the current one, with a scrollbar that shows the list goes on; choosing
/// one closes it, ✕ (or a swipe down) cancels.
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.current, required this.automaticLabel, required this.wide});

  /// The chosen tag; '' = the device's language.
  final String current;
  final String automaticLabel;
  final bool wide;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  final _scroll = ScrollController();
  final _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _currentKey.currentContext;
      if (current != null && current.mounted) {
        unawaited(Scrollable.ensureVisible(current, alignment: 0.3));
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _option(String tag, String name) => RadioListTile<String>(
    key: tag == widget.current ? _currentKey : null,
    value: tag,
    title: Text(name),
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.wide ? double.infinity : media.size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Gaps.xl, widget.wide ? Gaps.lg : 0, Gaps.xl, Gaps.sm),
            child: SheetHeader(
              title: 'Handwriting language',
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
          Flexible(
            child: RadioGroup<String>(
              groupValue: widget.current,
              onChanged: (v) => Navigator.pop(context, v),
              // A quiet, always-shown thumb: the list goes on below.
              child: ScrollbarTheme(
                data: ScrollbarTheme.of(context).copyWith(
                  thumbColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  crossAxisMargin: Gaps.xxs,
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  thickness: 4,
                  radius: const Radius.circular(Radii.pill),
                  // A few dozen rows: all built, so the current one can be
                  // scrolled to.
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.only(bottom: Gaps.md + media.padding.bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _option('', widget.automaticLabel),
                        for (final l in RecognitionLanguages.all) _option(l.tag, l.name),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
