import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../documents/pdf/pdf_background_cache.dart';
import '../document/document_controller.dart';

/// Says when a PDF the notebook's pages are drawn on can't be had (UX_AUDIT
/// #24), with Try again (it may arrive by sync) and Locate file… (pick it).
/// The pages themselves show a placeholder ([paintMissingPdf]). Dismissed,
/// it stays away for that PDF while the editor is open.
class MissingPdfNotice extends StatefulWidget {
  const MissingPdfNotice({
    super.key,
    required this.backgrounds,
    required this.doc,
    required this.onRelink,
  });

  final PdfBackgroundCache backgrounds;
  final DocumentController doc;

  /// Lets the user pick a file for the missing PDF (blob id).
  final Future<void> Function(String blob) onRelink;

  @override
  State<MissingPdfNotice> createState() => _MissingPdfNoticeState();
}

class _MissingPdfNoticeState extends State<MissingPdfNotice> {
  final Set<String> _dismissed = {};
  late Listenable _changes = _listen();

  Listenable _listen() => Listenable.merge([widget.backgrounds, widget.doc]);

  @override
  void didUpdateWidget(MissingPdfNotice old) {
    super.didUpdateWidget(old);
    if (old.backgrounds != widget.backgrounds || old.doc != widget.doc) _changes = _listen();
  }

  /// Missing PDFs that pages of this notebook use, first used first.
  List<String> _missing() {
    final missing = widget.backgrounds.missingBlobs;
    if (missing.isEmpty) return const [];
    return {
      for (final page in widget.doc.pages)
        if (page.background?.blob case final blob?)
          if (missing.contains(blob) && !_dismissed.contains(blob)) blob,
    }.toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final missing = _missing();
        return AnimatedSwitcher(
          duration: Motion.medium,
          child: missing.isEmpty
              ? const SizedBox.shrink()
              : _Card(
                  key: const ValueKey('missing-pdf'),
                  count: missing.length,
                  onRetry: widget.backgrounds.retryMissing,
                  onRelink: () => widget.onRelink(missing.first),
                  onDismiss: () => setState(() => _dismissed.addAll(missing)),
                ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.count,
    required this.onRetry,
    required this.onRelink,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onRetry;
  final VoidCallback onRelink;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: FloatingPanel(
          padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.xs, Gaps.xs, Gaps.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.picture_as_pdf_sharp, size: Glyphs.menu, color: scheme.error),
                  const SizedBox(width: Gaps.sm),
                  Expanded(
                    child: Text(
                      count == 1
                          ? 'The PDF for these pages isn’t on this device'
                          : 'The $count PDFs for these pages aren’t on this device',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    iconSize: Glyphs.menu,
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
                    icon: const Icon(Symbols.close_sharp),
                  ),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Gaps.xs,
                children: [
                  TextButton(onPressed: onRetry, child: const Text('Try again')),
                  TextButton(onPressed: onRelink, child: const Text('Locate file…')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
