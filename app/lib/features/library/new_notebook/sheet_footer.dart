import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';

/// The pinned bottom row of the new-notebook sheet: "Import PDF…" (one
/// page per PDF page, instead of blank pages) and "Create".
class SheetFooter extends StatelessWidget {
  const SheetFooter({
    super.key,
    required this.onImportPdf,
    required this.onCreate,
    this.bottomInset = 0,
  });

  final VoidCallback onImportPdf;
  final VoidCallback onCreate;

  /// Extra bottom padding (system navigation bar).
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.xl, Gaps.md + bottomInset),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onImportPdf,
                  icon: const Icon(Symbols.picture_as_pdf_rounded),
                  label: const Text('Import PDF…', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(width: Gaps.md),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Symbols.add_rounded),
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
