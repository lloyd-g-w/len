import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/versions/versions.dart';
import '../../ui/app_theme.dart';
import 'version_flows.dart';
import 'version_labels.dart';
import 'version_surface_view.dart';

/// A version shown read-only: its pages as thumbnails (a page opens
/// larger) or its canvas, with Restore and Copy as new notebook; a page
/// opened offers Restore this page. [onRestored] runs after a restore
/// (the history closes, to show the notebook).
class VersionPreview extends StatelessWidget {
  const VersionPreview({
    super.key,
    required this.services,
    required this.version,
    required this.sheets,
    required this.message,
    this.onRestored,
  });

  final AppServices services;
  final NotebookVersion version;
  final VersionSheets sheets;

  /// Where snack bars show (the screen the history was opened from).
  final BuildContext message;
  final VoidCallback? onRestored;

  @override
  Widget build(BuildContext context) {
    final v = version;
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              VersionLabels.at(v, now: services.clock.nowDate()),
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${VersionLabels.title(v)} '
              '${VersionLabels.madeOn(v, thisDevice: services.strokes.deviceId)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => unawaited(copyVersionFlow(message, services, v)),
            child: Text(compact ? 'Copy' : 'Copy as new notebook'),
          ),
          const SizedBox(width: Gaps.xs),
          FilledButton(onPressed: () => unawaited(_restore(context)), child: const Text('Restore')),
          const SizedBox(width: Gaps.lg),
        ],
      ),
      body: v.isCanvas
          ? Padding(
              padding: const EdgeInsets.all(Gaps.xl),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 8,
                  child: VersionSurfaceView(sheets: sheets, version: v, images: services.images),
                ),
              ),
            )
          : FutureBuilder<VersionBody?>(
              future: sheets.body(v),
              builder: (context, snapshot) {
                final body = snapshot.data;
                if (body == null) {
                  return snapshot.connectionState == ConnectionState.done
                      ? const _Unavailable()
                      : const SizedBox.shrink();
                }
                final pages = body.pages;
                return GridView.builder(
                  padding: EdgeInsets.all(compact ? Gaps.lg : Gaps.xxl),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: Gaps.lg,
                    crossAxisSpacing: Gaps.lg,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: pages.length,
                  itemBuilder: (context, i) => _PageTile(
                    key: ValueKey('version-page-${pages[i].id}'),
                    index: i,
                    count: pages.length,
                    onTap: () => unawaited(_openPage(context, pages[i], i, pages.length)),
                    child: VersionSurfaceView(
                      sheets: sheets,
                      version: v,
                      page: pages[i],
                      images: services.images,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    if (!await restoreVersionFlow(context, services, version, message: message)) return;
    if (context.mounted) Navigator.of(context).pop();
    onRestored?.call();
  }

  Future<void> _openPage(BuildContext context, VersionPage page, int index, int count) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (pageContext) {
            // Phones: the action sits under the page, so the title keeps
            // its row at large text sizes (UX_AUDIT R25-7).
            final compact = MediaQuery.sizeOf(pageContext).width < Breakpoints.medium;
            final restore = FilledButton(
              onPressed: () async {
                if (!await restorePageFlow(
                  pageContext,
                  services,
                  version,
                  page.id,
                  message: message,
                )) {
                  return;
                }
                if (!pageContext.mounted) return;
                Navigator.of(pageContext)
                  ..pop()
                  ..pop();
                onRestored?.call();
              },
              child: const Text('Restore this page'),
            );
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  'Page ${index + 1} of $count',
                  style: Theme.of(pageContext).textTheme.titleMedium,
                ),
                actions: [
                  if (!compact) ...[restore, const SizedBox(width: Gaps.lg)],
                ],
              ),
              bottomNavigationBar: compact
                  ? SafeArea(
                      child: Padding(padding: const EdgeInsets.all(Gaps.lg), child: restore),
                    )
                  : null,
              body: Padding(
                padding: const EdgeInsets.all(Gaps.xl),
                child: Center(
                  child: InteractiveViewer(
                    maxScale: 8,
                    child: VersionSurfaceView(
                      sheets: sheets,
                      version: version,
                      page: page,
                      images: services.images,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

/// What a preview shows when the version's pages can't be had.
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.cloud_off_sharp,
              size: Glyphs.empty,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Gaps.md),
            Text(
              'This version is not on this device. Connect to sync to see it',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page's thumbnail with its number under it.
class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.count,
    required this.onTap,
    required this.child,
  });

  final int index;
  final int count;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Page ${index + 1} of $count',
    onTap: onTap,
    excludeSemantics: true,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => onTap())},
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(child: Center(child: child)),
            const SizedBox(height: Gaps.xs),
            Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontFeatures: AppTheme.tabularFigures),
            ),
          ],
        ),
      ),
    ),
  );
}
