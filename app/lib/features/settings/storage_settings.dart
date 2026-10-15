import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/format.dart';
import '../../data/write_back.dart';
import '../../platform/browser_storage_api.dart';
import '../../ui/messages.dart';
import '../storage/storage_attention.dart';
import '../storage/storage_overview.dart';
import 'settings_section.dart';
import 'storage_rows.dart';

/// Settings → Storage (UX_AUDIT R16-7): the space Len uses here by kind,
/// the largest notebooks, "Free up" for copies of files the sync server
/// holds and the cached previews ([StorageOverview], measured again when
/// shown). In a browser also whether it keeps Len's data (persistent
/// storage) and how much of the site's quota it uses; while changes can't
/// be saved (storage full), says so, as the library's notice does.
class StorageSettings extends StatefulWidget {
  const StorageSettings({
    super.key,
    required this.overview,
    this.storage,
    this.filesKept = true,
    this.writes,
  });

  final StorageOverview overview;

  /// The browser's storage (web only).
  final BrowserStorage? storage;

  /// The app's storage writes, whose failures this shows.
  final StorageWrites? writes;

  /// False when the browser refused file storage (IndexedDB): PDFs, images
  /// and recordings then last only until the tab closes.
  final bool filesKept;

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  bool? _persisted;
  StorageUsage? _usage;
  bool _asking = false;
  WriteFailure? _failure;

  @override
  void initState() {
    super.initState();
    _failure = widget.writes?.failure;
    widget.writes?.addListener(_writesChanged);
    widget.overview.addListener(_overviewChanged);
    unawaited(widget.overview.refresh());
    _refresh();
  }

  @override
  void dispose() {
    widget.writes?.removeListener(_writesChanged);
    widget.overview.removeListener(_overviewChanged);
    super.dispose();
  }

  void _overviewChanged() {
    if (mounted) setState(() {});
  }

  void _writesChanged() {
    final failure = widget.writes?.failure;
    if (failure == _failure) return;
    final saved = failure == null;
    setState(() => _failure = failure);
    if (saved) _refresh(); // The usage grew.
  }

  Future<void> _refresh() async {
    final storage = widget.storage;
    if (storage == null) return;
    final persisted = await storage.isPersisted().catchError((Object _) => false);
    final usage = await storage.usage();
    if (!mounted) return;
    setState(() {
      _persisted = persisted;
      _usage = usage;
    });
  }

  Future<void> _request() async {
    setState(() => _asking = true);
    final granted = await widget.storage!.requestPersistence().catchError((Object _) => false);
    if (!mounted) return;
    setState(() => _asking = false);
    await _refresh();
    if (!mounted || granted) return;
    showMessage(
      context,
      'The browser declined. Installing Len as an app, or using it more often, usually helps',
    );
  }

  Future<void> _open(String id, {required bool recordings}) async {
    await openFromStorage(context, id, recordings: recordings);
    if (mounted) unawaited(widget.overview.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final overview = widget.overview;
    final browser = widget.storage != null;
    final largest = overview.survey?.largest ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Storage',
          description: browser
              ? 'Your notebooks are stored in this browser. Browsers may clear site data when '
                    'the device runs low on space, unless the site may keep its data. Clearing '
                    'site data yourself still deletes it, so back up your library (Backup) or '
                    'use sync.'
              : null,
          children: [
            ..._browserRows(context),
            SpaceUsedTile(
              overview: overview,
              where: browser ? 'in this browser' : 'on this device',
            ),
            if (overview.canFreeUp || overview.freeing) FreeUpTile(overview: overview),
            if ((overview.previews ?? 0) >= StorageOverview.significantPreviews)
              CachedPreviewsTile(overview: overview),
          ],
        ),
        if (largest.isNotEmpty)
          SettingsSection(
            title: 'Largest notebooks',
            children: [
              for (final n in largest)
                NotebookSizeTile(
                  key: ValueKey('storage-${n.id}'),
                  footprint: n,
                  onOpen: ({required recordings}) => unawaited(_open(n.id, recordings: recordings)),
                ),
            ],
          ),
      ],
    );
  }

  /// The browser's rows: storage failing, files not kept, persistence and
  /// the quota.
  List<Widget> _browserRows(BuildContext context) {
    if (widget.storage == null) return const [];
    final persisted = _persisted;
    return [
      if (_failure case final failure?)
        SettingsTile(
          icon: Symbols.save_sharp,
          title: StorageAttention.unsavedTitle,
          subtitle: StorageAttention.unsavedBody(failure),
          trailing: TextButton(
            onPressed: () => widget.writes?.flush(),
            child: const Text('Try again'),
          ),
        ),
      if (!widget.filesKept)
        SettingsTile(
          icon: Symbols.error_sharp,
          title: 'Files aren’t kept in this window',
          subtitle:
              'This browser doesn’t let Len store files, so PDFs, images and recordings '
              'are lost when the tab closes. Use a normal (not private) window, allow site '
              'data for Len, or turn on sync.',
        ),
      SettingsTile(
        icon: Symbols.verified_user_sharp,
        title: 'Keep data on this device',
        subtitle: switch (persisted) {
          null => 'Checking…',
          true => 'On: the browser keeps Len’s data until you clear it.',
          false => 'Off: the browser may clear Len’s data when storage runs low.',
        },
        trailing: persisted == false
            ? OutlinedButton(onPressed: _asking ? null : _request, child: const Text('Turn on'))
            : persisted == true
            ? Icon(
                Symbols.check_circle_sharp,
                fill: 1,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
      if (_usage case final usage?) _UsageTile(usage: usage),
    ];
  }
}

class _UsageTile extends StatelessWidget {
  const _UsageTile({required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final fraction = usage.quota <= 0 ? 0.0 : (usage.usage / usage.quota).clamp(0.0, 1.0);
    return SettingsTile(
      icon: Symbols.pie_chart_sharp,
      title: 'Browser storage',
      // Includes the app's own offline copy (service worker cache).
      subtitle:
          '${formatBytes(usage.usage)} of ${formatBytes(usage.quota)}, '
          'including the app itself for offline use',
      below: LinearProgressIndicator(value: fraction),
    );
  }
}
