import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../ui/sync_status_button.dart';
import '../../ui/text_prompt.dart';
import '../editor/editor_screen.dart';
import '../settings/settings_screen.dart';
import 'new_notebook_sheet.dart';
import 'notebook_card.dart';

/// Home screen: a grid of all notebooks and canvases.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  AppServices? _subscribedServices;
  StreamSubscription<Object?>? _remoteChanges;
  List<Notebook> _notebooks = const [];

  AppServices get _services => _subscribedServices!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services == _subscribedServices) return;
    _subscribedServices = services;
    unawaited(_remoteChanges?.cancel());
    _remoteChanges = _services.sync.remoteChanges
        .where((c) => c.notebooks)
        .listen((_) => _reload());
    _reload();
  }

  @override
  void dispose() {
    unawaited(_remoteChanges?.cancel());
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _notebooks = _services.notebooks.list());
  }

  Future<void> _create() async {
    final request = await NewNotebookSheet.show(context);
    if (request == null || !mounted) return;
    final notebook = _services.notebooks.create(
      title: request.title,
      kind: request.kind,
      paper: request.paper,
      coverColor: request.coverColor,
      firstPage: request.template,
    );
    _reload();
    await _open(notebook);
  }

  Future<void> _open(Notebook notebook) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => EditorScreen(notebook: notebook)));
    _reload();
  }

  Future<void> _onAction(Notebook notebook, NotebookAction action) async {
    switch (action) {
      case NotebookAction.rename:
        final title = await showTextPrompt(
          context,
          title: 'Rename',
          initialValue: notebook.title,
          confirmLabel: 'Rename',
        );
        if (title == null || title.isEmpty) return;
        // Re-read: it may have changed (or gone) while the dialog was open.
        final current = _services.notebooks.get(notebook.id);
        if (current == null) break;
        _services.notebooks.update(current.copyWith(title: title));
      case NotebookAction.delete:
        final confirmed = await _confirmDelete(notebook);
        if (!confirmed) return;
        _services.notebooks.delete(notebook.id);
    }
    _reload();
    unawaited(_services.sync.syncNow());
  }

  Future<bool> _confirmDelete(Notebook notebook) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${notebook.title}”?'),
        content: const Text('This removes it from all synced devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    return result ?? false;
  }

  void _openSettings() => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 32.0;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Notebooks'),
            actions: [
              SyncStatusButton(sync: _services.sync, onConfigure: _openSettings),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (_notebooks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: SafeArea(top: false, child: _EmptyState(onCreate: _create)),
            )
          else
            SliverPadding(
              // Bottom padding keeps the last row clear of the FAB.
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 120),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 20,
                  childAspectRatio: 0.64,
                ),
                itemCount: _notebooks.length,
                itemBuilder: (context, i) {
                  final notebook = _notebooks[i];
                  return NotebookCard(
                    key: ValueKey(notebook.id),
                    notebook: notebook,
                    onOpen: () => unawaited(_open(notebook)),
                    onAction: (a) => unawaited(_onAction(notebook, a)),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: _notebooks.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              tooltip: 'New notebook or canvas',
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.draw_outlined,
                size: 52,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text('Nothing here yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create a notebook or an infinite canvas to start writing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('New notebook'),
            ),
          ],
        ),
      ),
    );
  }
}
