import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ink/lab/flicker_log.dart';
import '../../platform/file_export.dart';
import '../../ui/app_switch.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/messages.dart';
import '../../ui/sheet_parts.dart';

/// The flicker log of the low-latency ink ([FlickerLog], docs/INK_LAB.md
/// *Flicker log*): record it, read it, share it, clear it. Recording
/// carries on in the editor once switched on (until the app restarts).
Future<void> showFlickerLog(BuildContext context) => showDialogOrSheet<void>(
  context: context,
  maxWidth: 640,
  maxHeight: 720,
  sheetHeightFactor: 0.85,
  builder: (context, wide) => _FlickerSheet(wide: wide),
);

class _FlickerSheet extends StatelessWidget {
  const _FlickerSheet({required this.wide});

  final bool wide;

  Future<void> _share(BuildContext context, FlickerLog log) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9T]'), '');
    try {
      await saveOrShare(
        utf8.encode(log.toText()),
        name: 'len-flicker-$stamp.txt',
        mime: 'text/plain',
      );
    } catch (e) {
      if (context.mounted) showMessage(context, 'Couldn’t share the log: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = FlickerLog.instance;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final entries = log.entries.reversed.toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Gaps.xl, wide ? Gaps.lg : 0, Gaps.xl, Gaps.sm),
              child: SheetHeader(
                title: 'Flicker log',
                subtitle: log.summary,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            AppSwitchTile(
              title: 'Record',
              subtitle: 'Hand-over timing, predicted tips and geometry of the low-latency ink',
              value: log.enabled,
              onChanged: (on) => log.enabled = on,
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
            ),
            Flexible(
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Gaps.xl),
                      child: Text('Nothing logged', style: text.bodySmall),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.sm, Gaps.xl, Gaps.lg),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
                        child: Text(
                          '${entries[i].kind} · ${entries[i].detail}',
                          style: text.bodySmall,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.lg),
              child: SheetActions(
                primary: FilledButton(
                  onPressed: () => _share(context, log),
                  child: const Text('Share'),
                ),
                cancelLabel: 'Clear',
                onCancel: log.clear,
              ),
            ),
          ],
        );
      },
    );
  }
}
