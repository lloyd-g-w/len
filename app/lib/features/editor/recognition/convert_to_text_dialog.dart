import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ink/recognition/convert_to_text.dart';
import '../../../ink/recognition/handwriting_recognizer.dart';
import '../../../ink/recognition/recognition_languages.dart';
import '../../../ink/recognition/recognition_service.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/messages.dart';

/// What the user chose in the "Convert to text" dialog.
sealed class _Choice {
  const _Choice(this.text);
  final String text;
}

class _Replace extends _Choice {
  const _Replace(super.text);
}

class _Copy extends _Choice {
  const _Copy(super.text);
}

/// "Convert to text" for a lasso [selection]: makes sure the language
/// model is on the device (offering to download it), recognises the
/// selected strokes and shows the reading — editable, with alternatives —
/// to replace the ink with a text box (one undoable edit) or to copy.
Future<void> convertSelectionToText(
  BuildContext context, {
  required RecognitionService recognition,
  required SelectionController selection,
}) async {
  final strokes = selection.strokes;
  if (strokes.isEmpty || !recognition.isSupported) return;
  if (!await _ensureModel(context, recognition) || !context.mounted) return;
  final result = ConvertToText.recognize(
    strokes,
    (line, area) => recognition.recognize(line, writingArea: area),
  );
  final choice = await showDialog<_Choice>(
    context: context,
    builder: (context) => _ConvertDialog(result: result),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Copy(:final text):
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) _snack(context, 'Text copied');
    case _Replace(:final text):
      // Sync or undo may have changed the selection meanwhile.
      if (!identical(selection.strokes, strokes)) {
        _snack(context, 'The selection changed; nothing was converted');
        return;
      }
      final model = selection.model;
      final box = ConvertToText.textBox(
        strokes,
        text,
        id: selection.clock.newId(),
        surfaceId: model.surfaceId,
        z: model.topZ + 1,
        createdAt: selection.clock.nowMs(),
      );
      selection.replaceStrokesWith([box]);
  }
}

void _snack(BuildContext context, String message) => showMessage(context, message);

/// True when the model is (or has just been) downloaded.
Future<bool> _ensureModel(BuildContext context, RecognitionService recognition) async {
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

/// Shows the reading (editable) and its alternatives.
class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({required this.result});

  final Future<ConversionResult> result;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  final _text = TextEditingController();
  ConversionResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.result.then(
        (r) {
          if (!mounted) return;
          setState(() => _result = r);
          _text.text = r.text;
        },
        onError: (Object e) {
          if (mounted) setState(() => _error = e);
        },
      ),
    );
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    final text = _text.text.trim();
    // Copy / Replace only once there is a reading to use.
    final ready = result != null && !result.isEmpty && _error == null;
    return AppDialog(
      title: 'Convert to text',
      content: DialogBody(
        child: switch ((result, _error)) {
          (_, final Object _) => Text(
            'The handwriting could not be recognised.',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          (null, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: Gaps.lg),
            child: Center(heightFactor: 1, child: CircularProgressIndicator()),
          ),
          (final r?, _) when r.isEmpty => const Text('No text was found in the selection.'),
          (final r?, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('convert-text-field'),
                controller: _text,
                minLines: 1,
                maxLines: 6,
                autofocus: false,
                decoration: const InputDecoration(labelText: 'Recognised text'),
              ),
              if (r.alternatives.isNotEmpty) ...[
                const SizedBox(height: Gaps.md),
                Text('Alternatives', style: theme.textTheme.bodySmall),
                const SizedBox(height: Gaps.xs),
                Wrap(
                  spacing: Gaps.sm,
                  runSpacing: Gaps.xs,
                  children: [
                    for (final alt in [r.text, ...r.alternatives])
                      ChoiceChip(
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(alt, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        selected: _text.text == alt,
                        onSelected: (_) => _text.text = alt,
                      ),
                  ],
                ),
              ],
            ],
          ),
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ready || (result == null && _error == null) ? 'Cancel' : 'Close'),
        ),
        if (ready) ...[
          TextButton(
            onPressed: text.isEmpty ? null : () => Navigator.pop(context, _Copy(text)),
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: text.isEmpty ? null : () => Navigator.pop(context, _Replace(text)),
            child: const Text('Replace ink'),
          ),
        ],
      ],
    );
  }
}
