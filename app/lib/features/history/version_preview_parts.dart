part of 'version_preview.dart';

/// The preview's title on wide screens: when, then the version's name and
/// where it was made, each on one line (the full text in a tooltip).
class _Title extends StatelessWidget {
  const _Title(this.version, {required this.when, required this.madeOn});

  final NotebookVersion version;
  final String when;
  final String madeOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = '${VersionLabels.title(version)} $madeOn';
    return Tooltip(
      message: '$when\n$subtitle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            when,
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A phone's app bar: back and [title] alone, as tall as the title needs
/// at the user's text size.
class _CompactBar extends StatelessWidget implements PreferredSizeWidget {
  _CompactBar(BuildContext context, {required this.title}) : height = _height(context);

  final String title;
  final double height;

  static double _height(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    final line =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 24) * (style?.height ?? 1.2);
    return math.max(kToolbarHeight, line + Gaps.lg);
  }

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: height,
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// On phones, above the pages: the version's name (in full) and where it
/// was made.
class _Heading extends StatelessWidget {
  const _Heading(this.version, {required this.madeOn});

  final NotebookVersion version;
  final String madeOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, 0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: VersionLabels.title(version), style: theme.textTheme.labelLarge),
            TextSpan(text: ' $madeOn'),
          ],
        ),
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A phone's commands, docked at the bottom: a row when they fit, else
/// stacked full width, the primary (last) on top ([DialogActions]).
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Surfaces.chrome(scheme),
        border: Border(top: Surfaces.chromeEdge(scheme)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.sm),
          child: DialogActions(children: children),
        ),
      ),
    );
  }
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

/// A version's surface shown large, zoomable up to 8×; [child] gets the
/// zoom (a large sheet renders the part zoomed into sharp).
class _Zoomable extends StatefulWidget {
  const _Zoomable(this.child);

  final Widget Function(TransformationController zoom) child;

  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<_Zoomable> {
  final _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      InteractiveViewer(maxScale: 8, transformationController: _zoom, child: widget.child(_zoom));
}
