import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import 'templates/page_setup.dart';
import 'templates/template_gallery.dart';

/// What the template picker is used for.
enum TemplatePickerMode {
  /// Choosing the first page of a new notebook.
  create,

  /// Adding a page to a notebook.
  addPage,

  /// Changing the paper of existing pages (size is fixed).
  change,

  /// Choosing the background of an infinite canvas (no size).
  canvas,
}

/// The user's choice in [TemplatePicker].
class TemplateChoice {
  const TemplateChoice(this.template, {this.allPages = false});

  final PageTemplate template;

  /// In [TemplatePickerMode.change]: apply to every page, not just one.
  final bool allPages;
}

/// Opens the template picker as a bottom sheet.
Future<TemplateChoice?> showTemplatePicker(
  BuildContext context, {
  required PageTemplate initial,
  TemplatePickerMode mode = TemplatePickerMode.create,
}) => showModalBottomSheet<TemplateChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (_) => TemplatePicker(initial: initial, mode: mode),
);

/// Template gallery with live miniatures, paper colours, size and
/// orientation; the actions stay pinned below the scrolling gallery.
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({super.key, required this.initial, required this.mode});

  final PageTemplate initial;
  final TemplatePickerMode mode;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  late PageTemplate _t = widget.initial;

  bool get _sizeEditable =>
      widget.mode == TemplatePickerMode.create || widget.mode == TemplatePickerMode.addPage;

  void _set(PageTemplate t) => setState(() => _t = t);

  void _done({bool allPages = false}) =>
      Navigator.of(context).pop(TemplateChoice(_t, allPages: allPages));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final compact = media.size.width < Breakpoints.medium;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: Gaps.xxs),
                Text(
                  describeTemplate(_t, canvas: widget.mode == TemplatePickerMode.canvas),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xs, Gaps.xl, Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PickerLabel('Paper colour'),
                  PaperColorRow(template: _t, onChanged: _set),
                  if (_sizeEditable) ...[
                    const SizedBox(height: Gaps.lg),
                    const PickerLabel('Page size'),
                    PageSizeRow(template: _t, onChanged: _set),
                  ],
                  const SizedBox(height: Gaps.xl),
                  TemplateGallery(selected: _t, onSelect: _set, tileWidth: compact ? 72 : 80),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Gaps.xl,
                Gaps.md,
                Gaps.xl,
                Gaps.md + media.padding.bottom,
              ),
              child: _actions(),
            ),
          ),
        ],
      ),
    );
  }

  String get _title => switch (widget.mode) {
    TemplatePickerMode.create => 'Choose a template',
    TemplatePickerMode.canvas => 'Canvas background',
    TemplatePickerMode.addPage => 'Add page',
    TemplatePickerMode.change => 'Change template',
  };

  Widget _actions() {
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    if (widget.mode != TemplatePickerMode.change) {
      final add = widget.mode == TemplatePickerMode.addPage;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          cancel,
          const SizedBox(width: Gaps.sm),
          FilledButton.icon(
            onPressed: _done,
            icon: Icon(add ? Icons.note_add_outlined : Icons.check_rounded),
            label: Text(add ? 'Add page' : 'Use template'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _done(allPages: true),
            child: const Text('Apply to all pages', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: Gaps.md),
        Expanded(
          child: FilledButton(
            onPressed: _done,
            child: const Text('Apply to this page', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}
