import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import 'templates/page_setup.dart';
import 'templates/template_catalog.dart';
import 'templates/template_chooser.dart';

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
  TemplateChoice(this.template, {this.allPages = false, List<Paper>? papers})
    : papers = papers ?? [template.paper];

  final PageTemplate template;

  /// In [TemplatePickerMode.change]: apply to every page, not just one.
  final bool allPages;

  /// The pages to add ([TemplatePickerMode.addPage]; several for a
  /// generated planner), each in [template]'s colour and size.
  final List<Paper> papers;

  /// The papers for [count] existing pages getting this template: planners
  /// continue period by period (day after day, …), others repeat.
  List<Paper> papersForPages(int count) {
    final result = <Paper>[];
    var paper = template.paper;
    for (var i = 0; i < count; i++) {
      result.add(paper);
      paper = paper.next;
    }
    return result;
  }
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

/// The selection a chooser starts from: [initial], with planners dated
/// from [today] (or the initial page's date).
TemplateSelection initialSelection(PageTemplate initial, DateTime today) {
  final date = initial.paper.date ?? today;
  return TemplateSelection(initial, PlannerPlan(start: date));
}

/// Template gallery with live miniatures, paper colours, size and
/// orientation; the actions stay pinned below the scrolling gallery.
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({super.key, required this.initial, required this.mode, this.today});

  final PageTemplate initial;
  final TemplatePickerMode mode;

  /// Today's date, the default start of planners (tests fix it).
  final DateTime? today;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  late TemplateSelection _s = initialSelection(widget.initial, widget.today ?? DateTime.now());

  PageTemplate get _t => _s.template;

  bool get _generates =>
      widget.mode == TemplatePickerMode.create || widget.mode == TemplatePickerMode.addPage;

  void _set(TemplateSelection s) => setState(() => _s = s);

  void _done({bool allPages = false}) => Navigator.of(context)
      .pop(TemplateChoice(_t, allPages: allPages, papers: _generates ? _s.pagesToCreate() : null));

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
                  describeSelection(
                    _s,
                    canvas: widget.mode == TemplatePickerMode.canvas,
                    generate: _generates,
                  ),
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
              child: TemplateChooser(
                selection: _s,
                onChanged: _set,
                canvas: widget.mode == TemplatePickerMode.canvas,
                sizeEditable: _generates,
                generate: _generates,
                tileWidth: compact ? 72 : 80,
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
      final count = _generates ? _s.pagesToCreate().length : 1;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          cancel,
          const SizedBox(width: Gaps.sm),
          FilledButton.icon(
            onPressed: _done,
            icon: Icon(add ? Icons.note_add_outlined : Icons.check_rounded),
            label: Text(add ? (count == 1 ? 'Add page' : 'Add $count pages') : 'Use template'),
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
