import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/dialog_actions.dart';
import '../../../ui/dialog_or_sheet.dart';
import '../../../ui/mini_cover.dart';
import '../../../ui/sheet_parts.dart';
import '../../../ui/sidebar_item.dart' show MarginRulePainter;
import '../../../ui/text_prompt.dart';

/// Where [pickPageDestination] sends pages: [notebook], or a new notebook
/// named [title] if null; and whether they are copied (else moved).
typedef PageDestination = ({Notebook? notebook, String title, bool copy});

/// Asks which of [notebooks] pages go to (UX_AUDIT R7-9), [title] above
/// the list ("Move 3 pages"), each row captioned by [caption] (where it
/// lives), or a new notebook (with [cover], asking for its name): pick
/// one, then Move or Copy. Null if cancelled.
Future<PageDestination?> pickPageDestination(
  BuildContext context, {
  required String title,
  required List<Notebook> notebooks,
  required String Function(Notebook notebook) caption,
  required Color cover,
}) => showDialogOrSheet<PageDestination>(
  context: context,
  maxWidth: 480,
  maxHeight: 600,
  minHeight: 420,
  builder: (context, wide) => _DestinationPicker(
    title: title,
    notebooks: notebooks,
    caption: caption,
    cover: cover,
    wide: wide,
  ),
);

class _DestinationPicker extends StatefulWidget {
  const _DestinationPicker({
    required this.title,
    required this.notebooks,
    required this.caption,
    required this.cover,
    required this.wide,
  });

  final String title;
  final List<Notebook> notebooks;
  final String Function(Notebook notebook) caption;
  final Color cover;
  final bool wide;

  @override
  State<_DestinationPicker> createState() => _DestinationPickerState();
}

class _DestinationPickerState extends State<_DestinationPicker> {
  Notebook? _chosen;

  /// The new notebook's name, once given; chosen while [_chosen] is null.
  String? _newTitle;

  bool get _newChosen => _chosen == null && _newTitle != null;

  void _done({required bool copy}) => Navigator.pop<PageDestination>(context, (
    notebook: _chosen,
    title: _chosen?.title ?? _newTitle!,
    copy: copy,
  ));

  /// Asks for the new notebook's name and chooses it.
  Future<void> _chooseNew() async {
    final title = await showTextPrompt(
      context,
      title: 'New notebook',
      label: 'Name',
      initialValue: _newTitle ?? '',
    );
    if (title == null || title.isEmpty || !mounted) return;
    setState(() {
      _chosen = null;
      _newTitle = title;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = _chosen != null || _newChosen;
    final bottom = widget.wide ? 0.0 : MediaQuery.paddingOf(context).bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, widget.wide ? Gaps.xl : 0, Gaps.xl, Gaps.sm),
          // Dialogs close with Cancel; sheets with the ✕ (DESIGN §6.3).
          child: SheetHeader(
            title: widget.title,
            subtitle: 'They go after the last page',
            onClose: widget.wide ? null : () => Navigator.pop(context),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
            children: [
              _NotebookRow(
                key: const ValueKey('destination-new'),
                leading: _newTitle == null
                    ? Icon(Symbols.add_sharp, size: Glyphs.bar, color: theme.colorScheme.onSurface)
                    : MiniCover(color: widget.cover),
                title: _newTitle ?? 'New notebook…',
                caption: _newTitle == null
                    ? 'With this notebook’s paper and cover'
                    : 'New notebook',
                chosen: _newChosen,
                onTap: _chooseNew,
              ),
              for (final n in widget.notebooks)
                _NotebookRow(
                  key: ValueKey('destination-${n.id}'),
                  leading: MiniCover(color: Color(n.coverColor)),
                  title: n.title,
                  caption: widget.caption(n),
                  chosen: n.id == _chosen?.id,
                  onTap: () => setState(() => _chosen = n),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, Gaps.xl + bottom),
          child: DialogActions(
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              OutlinedButton(
                onPressed: chosen ? () => _done(copy: true) : null,
                child: const Text('Copy'),
              ),
              FilledButton(
                onPressed: chosen ? () => _done(copy: false) : null,
                child: const Text('Move'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A destination: its small cover ([leading]), title and where it lives;
/// the chosen one carries the margin rule and a bold title.
class _NotebookRow extends StatelessWidget {
  const _NotebookRow({
    super.key,
    required this.leading,
    required this.title,
    required this.caption,
    required this.chosen,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String caption;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: chosen,
      button: true,
      child: CustomPaint(
        foregroundPainter: chosen ? MarginRulePainter(scheme.primary) : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.xs),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: Targets.menuRowHeight(context) + Gaps.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: Glyphs.bar,
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: chosen ? FontWeight.w600 : null,
                          ),
                        ),
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
