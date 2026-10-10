import 'package:flutter/material.dart';

import '../../ui/floating_panel.dart';

/// "‹ 3 / 12 › +" control for paged notebooks.
class PageNavigator extends StatelessWidget {
  const PageNavigator({
    super.key,
    required this.index,
    required this.count,
    required this.onSelect,
    required this.onAddPage,
  });

  final int index;
  final int count;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddPage;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: index > 0 ? () => onSelect(index - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${index + 1} / $count', style: Theme.of(context).textTheme.labelLarge),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: index < count - 1 ? () => onSelect(index + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          IconButton(
            tooltip: 'Add page after this one',
            onPressed: onAddPage,
            icon: const Icon(Icons.note_add_outlined),
          ),
        ],
      ),
    );
  }
}
