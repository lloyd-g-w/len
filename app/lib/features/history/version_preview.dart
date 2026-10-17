import 'dart:async';

import 'package:flutter/material.dart';

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
            Text(VersionLabels.when(v), style: theme.textTheme.titleLarge),
            Text(
              '${VersionLabels.title(v)}, '
              '${VersionLabels.device(v, thisDevice: services.strokes.deviceId)}',
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
      body: v.canvas != null
          ? Padding(
              padding: const EdgeInsets.all(Gaps.xl),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 8,
                  child: VersionSurfaceView(sheets: sheets, version: v, images: services.images),
                ),
              ),
            )
          : GridView.builder(
              padding: EdgeInsets.all(compact ? Gaps.lg : Gaps.xxl),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: Gaps.lg,
                crossAxisSpacing: Gaps.lg,
                childAspectRatio: 0.62,
              ),
              itemCount: v.pages.length,
              itemBuilder: (context, i) => _PageTile(
                key: ValueKey('version-page-${v.pages[i].id}'),
                index: i,
                count: v.pages.length,
                onTap: () => unawaited(_openPage(context, v.pages[i], i)),
                child: VersionSurfaceView(
                  sheets: sheets,
                  version: v,
                  page: v.pages[i],
                  images: services.images,
                ),
              ),
            ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    if (!await restoreVersionFlow(context, services, version, message: message)) return;
    if (context.mounted) Navigator.of(context).pop();
    onRestored?.call();
  }

  Future<void> _openPage(BuildContext context, VersionPage page, int index) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (pageContext) => Scaffold(
            appBar: AppBar(
              title: Text(
                'Page ${index + 1} of ${version.pages.length}',
                style: Theme.of(pageContext).textTheme.titleMedium,
              ),
              actions: [
                FilledButton(
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
                ),
                const SizedBox(width: Gaps.lg),
              ],
            ),
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
          ),
        ),
      );
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
    excludeSemantics: true,
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
  );
}
