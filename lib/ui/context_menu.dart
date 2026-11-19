// Sağ tık (Windows) / uzun basma (Android) bağlam menüsü.

import 'package:flutter/material.dart';

class MenuAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
  final String? shortcut;
  const MenuAction(this.label, this.icon, this.onTap, {this.destructive = false, this.shortcut});
}

const menuDivider = MenuAction('', Icons.remove, null);

Future<void> showContextMenuAt(BuildContext context, Offset globalPos, List<MenuAction> actions) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPos);
  final cb = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromLTRB(local.dx, local.dy, overlay.size.width - local.dx, overlay.size.height - local.dy),
    items: [
      for (final a in actions)
        if (identical(a, menuDivider))
          const PopupMenuDivider()
        else
          PopupMenuItem<VoidCallback>(
            value: a.onTap,
            enabled: a.onTap != null,
            height: 40,
            child: Row(children: [
              Icon(a.icon, size: 20, color: a.destructive ? Theme.of(context).colorScheme.error : null),
              const SizedBox(width: 12),
              Expanded(child: Text(a.label, style: a.destructive ? TextStyle(color: Theme.of(context).colorScheme.error) : null)),
              if (a.shortcut != null) Text(a.shortcut!, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
    ],
  );
  cb?.call();
}

/// Bir widget'a hem sağ tık hem uzun basma menüsü bağlar
class ContextMenuRegion extends StatelessWidget {
  final Widget child;
  final List<MenuAction> Function() actions;
  const ContextMenuRegion({super.key, required this.child, required this.actions});
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) => showContextMenuAt(context, d.globalPosition, actions()),
        onLongPressStart: (d) => showContextMenuAt(context, d.globalPosition, actions()),
        child: child,
      );
}
