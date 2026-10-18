import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/versions/versions.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import '../../ui/staggered_build.dart';
import 'version_labels.dart';
import 'version_row_text.dart';
import 'version_surface_view.dart';

/// What a version's ⋯ offers.
enum VersionAction { restore, copy, rename, delete, deleteOlder }

/// What a row of the history says, worked out once when the list is
/// (not with every build of the row as it scrolls into view).
class VersionRowLabels {
  VersionRowLabels(NotebookVersion v, {required bool first, required String thisDevice})
    : title = VersionLabels.title(v),
      time = VersionLabels.time(v),
      details = _details(v, first: first, thisDevice: thisDevice),
      semantics = _semantics(v, first: first, thisDevice: thisDevice);

  /// Its name, or what made it.
  final String title;

  /// The time of day.
  final String time;

  /// The device and what changed: `This device, 3 strokes added`.
  final String details;

  /// All of it, for screen readers.
  final String semantics;

  static String _details(NotebookVersion v, {required bool first, required String thisDevice}) {
    final summary = VersionLabels.summary(v, first: first);
    final device = VersionLabels.device(v, thisDevice: thisDevice);
    return '$device, ${summary[0].toLowerCase()}${summary.substring(1)}';
  }

  static String _semantics(NotebookVersion v, {required bool first, required String thisDevice}) =>
      '${VersionLabels.title(v)}, ${VersionLabels.time(v)}, '
      '${VersionLabels.device(v, thisDevice: thisDevice)}. '
      '${VersionLabels.summary(v, first: first)}';
}

/// One version: a thumbnail of the page it changed first, its name or
/// what made it, the time, the device and what changed.
///
/// Built a few at a time as the list scrolls (a screen of them in a frame
/// when it jumps), so kept small: labels come worked out ([labels]), the
/// ⋯ is completed after scrolling stops ([MenuIconButton.staggered]).
class VersionRow extends StatelessWidget {
  const VersionRow({
    super.key,
    required this.version,
    required this.labels,
    required this.hasOlder,
    required this.sheets,
    required this.services,
    required this.onOpen,
    required this.onAction,
  });

  final NotebookVersion version;
  final VersionRowLabels labels;
  final bool hasOlder;
  final VersionSheets sheets;
  final AppServices services;
  final VoidCallback onOpen;
  final ValueChanged<VersionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final v = version;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.xs, Gaps.sm),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: !v.isCanvas && v.summary.pages == 0
                ? null
                : VersionSurfaceView(sheets: sheets, version: v, images: services.images),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(child: _words(context)),
        ],
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: labels.semantics,
            onTap: onOpen,
            excludeSemantics: true,
            // The row's ink well (hover, focus, keys) over its content, so
            // it can come a little later without building that again.
            child: Stack(
              children: [
                content,
                Positioned.fill(
                  child: StaggeredBuild(
                    placeholder: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onOpen),
                    child: InkWell(onTap: onOpen),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: Gaps.lg),
          child: MenuIconButton<VersionAction>(
            tooltip: 'Version options',
            icon: const Icon(Symbols.more_horiz_sharp),
            onSelected: onAction,
            items: _items,
            staggered: true,
          ),
        ),
      ],
    );
  }

  /// The title, time and details: one render object ([VersionRowText])
  /// but for a named version's mark.
  Widget _words(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (version.kind != VersionKind.named) {
      return VersionRowText(
        title: labels.title,
        time: labels.time,
        details: labels.details,
        titleStyle: VersionRowText.styleOf(context, text.labelLarge),
        timeStyle: VersionRowText.styleOf(context, _timeStyle(text)),
        detailsStyle: VersionRowText.styleOf(context, text.bodySmall),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Icon(Symbols.bookmark_sharp, size: Glyphs.menu, fill: 1),
            const SizedBox(width: Gaps.xs),
            Flexible(
              child: Text(
                labels.title,
                style: text.labelLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Gaps.sm),
            Text(labels.time, style: _timeStyle(text)),
          ],
        ),
        Text(labels.details, style: text.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  static TextStyle? _timeStyle(TextTheme text) =>
      text.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures);

  List<PopupMenuEntry<VersionAction>> _items() => [
    const MenuRow(value: VersionAction.restore, icon: Symbols.restore_sharp, label: 'Restore…'),
    const MenuRow(
      value: VersionAction.copy,
      icon: Symbols.library_add_sharp,
      label: 'Copy as new notebook',
    ),
    const MenuRow(value: VersionAction.rename, icon: Symbols.edit_sharp, label: 'Rename…'),
    const PopupMenuDivider(),
    const MenuRow(
      value: VersionAction.delete,
      icon: Symbols.delete_sharp,
      label: 'Delete version',
      destructive: true,
    ),
    if (hasOlder)
      const MenuRow(
        value: VersionAction.deleteOlder,
        icon: Symbols.delete_sweep_sharp,
        label: 'Delete older versions…',
        destructive: true,
      ),
  ];
}
