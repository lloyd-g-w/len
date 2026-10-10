import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';
import '../editor_screen.dart';
import 'open_notebooks.dart';

/// Opens [notebook] in a tab and shows the editor: pushes the workspace if
/// it is not already showing, otherwise just switches tabs.
Future<void> openNotebook(BuildContext context, Notebook notebook) async {
  final services = AppScope.read(context);
  final tabs = services.openNotebooks;
  // Drop tabs whose notebooks were deleted or trashed meanwhile, and pick
  // up renames made elsewhere.
  for (final tab in tabs.tabs) {
    final current = services.notebooks.get(tab.id);
    if (current == null || current.isTrashed) {
      tabs.close(tab.id);
    } else {
      tabs.rename(tab.id, current.title);
    }
  }
  tabs.open(notebook);
  if (EditorWorkspace.isShowing) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: EditorWorkspace.routeName),
      builder: (_) => const EditorWorkspace(),
    ),
  );
}

/// The editor route: shows the active tab's notebook and swaps editors as
/// tabs change. Each editor saves its place when it closes and restores
/// it when its tab is shown again. Closing the last tab leaves.
class EditorWorkspace extends StatefulWidget {
  const EditorWorkspace({super.key});

  static const String routeName = '/editor';

  static int _mounted = 0;

  /// Whether a workspace is on the navigation stack.
  static bool get isShowing => _mounted > 0;

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  late final AppServices _services = AppScope.read(context);
  OpenNotebooks get _tabs => _services.openNotebooks;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    EditorWorkspace._mounted++;
    _tabs.addListener(_onTabs);
  }

  @override
  void dispose() {
    EditorWorkspace._mounted--;
    _tabs.removeListener(_onTabs);
    super.dispose();
  }

  void _onTabs() {
    if (!mounted) return;
    if (_tabs.isEmpty) {
      _leave();
      return;
    }
    setState(() {});
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route == null || !route.isActive) return;
    // Close anything open over the editor (sheets, menus) with it.
    navigator
      ..popUntil((r) => r == route)
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs.active;
    final notebook = tab == null ? null : _services.notebooks.get(tab.id);
    if (tab != null && (notebook == null || notebook.isTrashed)) {
      // Deleted or trashed while the tab was in the background.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.close(tab.id));
    }
    return AnimatedSwitcher(
      duration: Motion.fast,
      switchInCurve: Motion.standard,
      child: notebook == null || notebook.isTrashed
          ? const Scaffold(key: ValueKey('empty'))
          : EditorScreen(key: ValueKey(notebook.id), notebook: notebook),
    );
  }
}
