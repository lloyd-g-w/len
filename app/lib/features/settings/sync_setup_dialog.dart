import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_setup_link.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../../ui/qr_code_view.dart';

/// "Set up another device": [link] as a QR code to scan with the other
/// device's camera, and as a link to copy and paste into its Server URL
/// field. Warns that the link holds the access token.
Future<void> showSyncSetupDialog(BuildContext context, SyncSetupLink link) async {
  final copied = await showDialog<bool>(
    context: context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      return AppDialog(
        title: 'Set up another device',
        scrollable: true,
        content: DialogBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan this code with the other device’s camera, or copy the link and paste '
                'it into Server URL there',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Gaps.lg),
              Center(
                child: QrCodeView(data: link.link, semanticLabel: 'QR code of the setup link'),
              ),
              const SizedBox(height: Gaps.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.key_sharp, size: Glyphs.menu, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Gaps.sm),
                  Expanded(
                    child: Text(
                      'The link includes your access token: share it only with your own '
                      'devices',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Symbols.content_copy_sharp, size: Glyphs.menu),
            label: const Text('Copy link'),
          ),
        ],
      );
    },
  );
  if (copied != true) return;
  await Clipboard.setData(ClipboardData(text: link.link));
  if (!context.mounted) return;
  showMessage(context, 'Setup link copied: paste it into Server URL on the other device');
}
