import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/versions/versions.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_actions.dart';
import 'version_flows.dart';
import 'version_labels.dart';
import 'version_surface_view.dart';

part 'version_preview_parts.dart';

/// A version shown read-only: its pages as thumbnails (a page opens
/// larger) or its canvas, with Restore and Copy as new notebook; a page
/// opened offers Restore this page. [onRestored] runs after a restore
/// (the history closes, to show the notebook). On phones the title has the
/// bar to itself (the version's name heads the pages, in full) and the
/// commands sit in a bar at the bottom.
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
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final copy = TextButton(
      onPressed: () => unawaited(copyVersionFlow(message, services, v)),
      child: const Text('Copy as new notebook'),
    );
    final restore = FilledButton(
      onPressed: () => unawaited(_restore(context)),
      child: const Text('Restore'),
    );
    final heading = _Heading(v, madeOn: VersionLabels.madeOn(v, thisDevice: _thisDevice));
    // Short ("Today, 11:42"), so it keeps one line at large text (R25-7).
    final when = VersionLabels.at(v, now: services.clock.nowDate());
    return Scaffold(
      appBar: compact
          ? _CompactBar(context, title: when)
          : AppBar(
              title: _Title(
                v,
                when: when,
                madeOn: VersionLabels.madeOn(v, thisDevice: _thisDevice),
              ),
              actions: [
                copy,
                const SizedBox(width: Gaps.xs),
                restore,
                const SizedBox(width: Gaps.lg),
              ],
            ),
      bottomNavigationBar: compact ? _ActionBar(children: [copy, restore]) : null,
      body: v.isCanvas ? _canvas(compact ? heading : null) : _pages(compact ? heading : null),
    );
  }

  String get _thisDevice => services.strokes.deviceId;

  /// A canvas version, under [heading] (phones).
  Widget _canvas(Widget? heading) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?heading,
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xl),
          child: Center(
            child: _Zoomable(
              (zoom) => VersionSurfaceView(
                sheets: sheets,
                version: version,
                images: services.images,
                zoom: zoom,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  /// A paged version's pages, under [heading] (phones).
  Widget _pages(Widget? heading) => FutureBuilder<VersionBody?>(
    future: sheets.body(version),
    builder: (context, snapshot) {
      final body = snapshot.data;
      if (body == null) {
        return snapshot.connectionState == ConnectionState.done
            ? Column(
                children: [
                  ?heading,
                  const Expanded(child: _Unavailable()),
                ],
              )
            : const SizedBox.shrink();
      }
      final pages = body.pages;
      final pad = heading == null ? Gaps.xxl : Gaps.lg;
      return CustomScrollView(
        slivers: [
          if (heading != null) SliverToBoxAdapter(child: heading),
          SliverPadding(
            padding: EdgeInsets.all(pad),
            sliver: SliverGrid.builder(
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
                  version: version,
                  page: pages[i],
                  images: services.images,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _restore(BuildContext context) async {
    if (!await restoreVersionFlow(context, services, version, message: message)) return;
    if (context.mounted) Navigator.of(context).pop();
    onRestored?.call();
  }

  Future<void> _openPage(BuildContext context, VersionPage page, int index, int count) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (pageContext) {
            // Phones: Restore this page docks at the bottom, so the title
            // keeps its row at large text sizes (UX_AUDIT R25-7).
            final compact = MediaQuery.sizeOf(pageContext).width < Breakpoints.medium;
            final title = 'Page ${index + 1} of $count';
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
              appBar: compact
                  ? _CompactBar(pageContext, title: title)
                  : AppBar(
                      title: Text(title, style: Theme.of(pageContext).textTheme.titleMedium),
                      actions: [
                        restore,
                        const SizedBox(width: Gaps.lg),
                      ],
                    ),
              bottomNavigationBar: compact ? _ActionBar(children: [restore]) : null,
              body: Padding(
                padding: const EdgeInsets.all(Gaps.xl),
                child: Center(
                  child: _Zoomable(
                    (zoom) => VersionSurfaceView(
                      sheets: sheets,
                      version: version,
                      page: page,
                      images: services.images,
                      zoom: zoom,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}
