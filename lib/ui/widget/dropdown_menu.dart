import 'package:flutter/material.dart';
import 'package:vidra_player/ui/widget/blur.dart';
import 'package:vidra_player/ui/widget/animation_button.dart';
import 'package:vidra_player/utils/no_scrollbar_behavior.dart';

import '../../utils/screen.dart';
import '../../core/model/player_ui_theme.dart';

/// Smooth dropdown menu component, based on PlayerOverlayPanel style
class VDropdownMenu extends StatefulWidget {
  /// Trigger button
  final Widget child;

  /// Menu item builder
  final List<Widget> Function(BuildContext context, VoidCallback close)
  menuBuilder;

  /// Menu width
  final double menuWidth;

  /// Whether to use blur effect
  final bool useBlur;

  /// Menu title (optional)
  final String? title;

  /// Alignment
  final Alignment alignment;

  /// Offset
  final Offset offset;

  /// Theme configuration
  final PlayerUITheme theme;

  /// Menu open/close callbacks
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// Whether to use animation for trigger
  final bool useAnimation;

  const VDropdownMenu({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.menuWidth = 200,
    this.useBlur = true,
    this.title,
    this.alignment = Alignment.bottomRight,
    this.offset = const Offset(0, 8),
    this.theme = const PlayerUITheme.dark(),
    this.onOpen,
    this.onClose,
    this.useAnimation = false,
  });

  @override
  State<VDropdownMenu> createState() => _DropdownMenuState();
}

class _DropdownMenuState extends State<VDropdownMenu>
    with TickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _closeMenuImmediate();
    _animationController.dispose();
    super.dispose();
  }

  void _closeMenuImmediate() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      widget.onClose?.call();
    }
  }

  void _toggleMenu() {
    if (_overlayEntry == null) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _openMenu() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();

    // Call onOpen after menu is shown
    widget.onOpen?.call();
  }

  void _closeMenu() {
    if (_overlayEntry == null) return;

    // If already disposed or not mounted, just remove immediately
    if (!mounted) {
      _closeMenuImmediate();
      return;
    }

    _animationController.reverse().then((_) {
      if (mounted && _overlayEntry != null) {
        _overlayEntry?.remove();
        _overlayEntry = null;

        // Call onClose after menu is hidden
        widget.onClose?.call();
      }
    });
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) {
        if (!mounted) return const SizedBox.shrink();

        // Trigger rebuild of overlay when screen size changes
        MediaQuery.of(this.context);

        return Stack(
          children: [
            // Close on click outside
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Menu content
            Positioned(
              width: widget.menuWidth,
              child: CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: _getTargetAnchor(),
                followerAnchor: _getFollowerAnchor(),
                offset: widget.offset,
                child: FadeTransition(
                  opacity: _opacityAnimation,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _buildMenuPanel(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuPanel() {
    final screenSize = ScreenHelper.getScreenSize(context);
    final theme = widget.theme;

    Widget panelContent = Container(
      constraints: BoxConstraints(maxHeight: screenSize.height * 0.6),
      decoration: BoxDecoration(
        color: widget.useBlur
            ? theme.dialogBackgroundColor.withValues(alpha: 0.6)
            : theme.dialogBackgroundColor.withValues(alpha: 0.95),
        borderRadius: widget.theme.borderRadius != BorderRadius.zero
            ? widget.theme.borderRadius
            : BorderRadius.circular(12),
        border: Border.all(
          color: theme.dialogBackgroundColor.withValues(alpha: 0.5),
        ),
        // boxShadow: [
        //   BoxShadow(
        //     // color: theme.dialogBackgroundColor.withValues(alpha: 0.4),
        //     // blurRadius: 10,
        //     // spreadRadius: 5,
        //   ),
        // ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Optional title
          if (widget.title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title!,
                  style: TextStyle(
                    color: theme.dialogTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Divider(color: theme.textColor.withValues(alpha: 0.1), height: 1),
          ],
          // Menu items
          Flexible(
            child: ScrollConfiguration(
              behavior: NoScrollbarBehavior(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.menuBuilder(context, _closeMenu),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.useBlur) {
      return BlurPanel(child: panelContent);
    }

    return panelContent;
  }

  Alignment _getTargetAnchor() {
    return switch (widget.alignment) {
      Alignment.topLeft => Alignment.topLeft,
      Alignment.topCenter => Alignment.topCenter,
      Alignment.topRight => Alignment.topRight,
      Alignment.centerLeft => Alignment.centerLeft,
      Alignment.centerRight => Alignment.centerRight,
      Alignment.bottomLeft => Alignment.bottomLeft,
      Alignment.bottomCenter => Alignment.bottomCenter,
      _ => Alignment.bottomRight,
    };
  }

  Alignment _getFollowerAnchor() {
    return switch (widget.alignment) {
      // Top anchor → bottom follower
      Alignment.topLeft => Alignment.bottomLeft,
      Alignment.topCenter => Alignment.bottomCenter,
      Alignment.topRight => Alignment.bottomRight,
      // Bottom anchor → top follower
      Alignment.bottomLeft => Alignment.topLeft,
      Alignment.bottomCenter => Alignment.topCenter,
      Alignment.bottomRight => Alignment.topRight,
      // Left anchor → right follower
      Alignment.centerLeft => Alignment.centerRight,
      // Right anchor → left follower
      Alignment.centerRight => Alignment.centerLeft,
      _ => Alignment.topRight,
    };
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: widget.useAnimation
            ? AnimationButton(onTap: _toggleMenu, child: widget.child)
            : GestureDetector(onTap: _toggleMenu, child: widget.child),
      ),
    );
  }
}

/// Menu item component
class PlayerMenuItem extends StatefulWidget {
  final Widget? leading;
  final String text;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? textColor;
  final PlayerUITheme? theme;

  const PlayerMenuItem({
    super.key,
    this.leading,
    required this.text,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.textColor,
    this.theme,
  });

  @override
  State<PlayerMenuItem> createState() => _PlayerMenuItemState();
}

class _PlayerMenuItemState extends State<PlayerMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playerTheme = widget.theme ?? const PlayerUITheme.dark();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: playerTheme.animationDuration,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered && widget.enabled
                ? playerTheme.hoverColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                IconTheme(
                  data: IconThemeData(
                    color: widget.enabled
                        ? (widget.textColor ?? playerTheme.iconColor)
                        : playerTheme.iconColorDisabled,
                    size: 20,
                  ),
                  child: widget.leading!,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: widget.enabled
                        ? (widget.textColor ?? playerTheme.dialogTextColor)
                        : playerTheme.iconColorDisabled,
                    fontSize: 14,
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                IconTheme(
                  data: IconThemeData(
                    color: widget.enabled
                        ? (widget.textColor ??
                              playerTheme.iconColor.withValues(alpha: 0.7))
                        : playerTheme.iconColorDisabled,
                    size: 18,
                  ),
                  child: widget.trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Menu divider
class PlayerMenuDivider extends StatelessWidget {
  final PlayerUITheme? theme;

  const PlayerMenuDivider({super.key, this.theme});

  @override
  Widget build(BuildContext context) {
    final playerTheme = theme ?? const PlayerUITheme.dark();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        color: playerTheme.textColor.withValues(alpha: 0.1),
        height: 1,
      ),
    );
  }
}

/// Menu toggle item
class PlayerMenuToggleItem extends StatelessWidget {
  final Widget? leading;
  final String text;
  final bool value;
  final ValueChanged<bool> onChanged;
  final PlayerUITheme? theme;

  const PlayerMenuToggleItem({
    super.key,
    this.leading,
    required this.text,
    required this.value,
    required this.onChanged,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final playerTheme = theme ?? const PlayerUITheme.dark();
    return PlayerMenuItem(
      leading: leading,
      text: text,
      theme: playerTheme,
      trailing: Transform.scale(
        scale: 0.8,
        child: Switch(
          padding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          activeThumbColor: playerTheme.iconColor,
          activeTrackColor: playerTheme.primaryColor.withValues(alpha: 0.5),
          inactiveThumbColor: playerTheme.iconColorDisabled,
          inactiveTrackColor: playerTheme.textColor.withValues(alpha: 0.1),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// Menu adjustment item (increment/decrement)
class PlayerMenuAdjustmentItem extends StatelessWidget {
  final Widget? leading;
  final String text;
  final num value;
  final String suffix;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final PlayerUITheme? theme;

  const PlayerMenuAdjustmentItem({
    super.key,
    this.leading,
    required this.text,
    required this.value,
    this.suffix = '',
    required this.onIncrement,
    required this.onDecrement,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final playerTheme = theme ?? const PlayerUITheme.dark();

    return PlayerMenuItem(
      leading: leading,
      text: text,
      theme: playerTheme,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdjustmentButton(
            icon: Icons.remove,
            onPressed: onDecrement,
            color: playerTheme.iconColor,
          ),
          Container(
            width: 50,
            alignment: Alignment.center,
            child: Text(
              '$value$suffix',
              style: TextStyle(
                color: playerTheme.dialogTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _AdjustmentButton(
            icon: Icons.add,
            onPressed: onIncrement,
            color: playerTheme.iconColor,
          ),
        ],
      ),
    );
  }
}

class _AdjustmentButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  const _AdjustmentButton({
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimationButton(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

/// Generic menu selector button
class VMenuSelector extends StatelessWidget {
  final Widget child;
  final List<Widget> Function(BuildContext context, VoidCallback close)
  menuBuilder;
  final String? tooltip;
  final double menuWidth;
  final Alignment alignment;
  final Offset offset;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final bool useAnimation;

  const VMenuSelector({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.tooltip,
    this.menuWidth = 200,
    this.alignment = Alignment.topRight,
    this.offset = const Offset(0, -10),
    this.onOpen,
    this.onClose,
    this.useAnimation = false,
  });

  @override
  Widget build(BuildContext context) {
    final childWidget = child; // Tooltip removed for debugging
    // tooltip != null
    // ? Tooltip(message: tooltip!, child: child)
    // : child;

    return VDropdownMenu(
      menuWidth: menuWidth,
      alignment: alignment,
      offset: offset,
      onOpen: onOpen,
      onClose: onClose,
      menuBuilder: menuBuilder,
      useAnimation: useAnimation,
      child: childWidget,
    );
  }
}

/// Generic option selector for selecting a single value from a list
class VOptionSelector<T> extends StatelessWidget {
  final String? tooltip;
  final String currentLabel;
  final T currentValue;
  final List<T> items;
  final String Function(T item) itemLabelBuilder;
  final ValueChanged<T> onSelected;
  final double menuWidth;
  final Alignment alignment;
  final Offset offset;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final Widget Function(BuildContext context, T currentValue)? triggerBuilder;
  final Color? textColor; // for theme color support
  final Color? checkmarkColor; // NEW: for checkmark color
  final bool useAnimation;

  const VOptionSelector({
    super.key,
    this.tooltip,
    required this.currentLabel,
    required this.currentValue,
    required this.items,
    required this.itemLabelBuilder,
    required this.onSelected,
    this.menuWidth = 140,
    this.alignment = Alignment.topRight,
    this.offset = const Offset(0, -10),
    this.onOpen,
    this.onClose,
    this.triggerBuilder,
    this.textColor, // NEW
    this.checkmarkColor, // NEW
    this.useAnimation = false,
  });

  @override
  Widget build(BuildContext context) {
    final trigger =
        triggerBuilder?.call(context, currentValue) ??
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            currentLabel,
            style: TextStyle(
              color: textColor ?? Colors.white, // Use theme color if provided
              fontWeight: FontWeight.bold,
            ),
          ),
        );

    final wrappedTrigger = trigger; // Tooltip removed for debugging
    // tooltip != null
    // ? Tooltip(message: tooltip!, child: trigger)
    // : trigger;

    return VMenuSelector(
      tooltip: null, // Tooltip is now handled above
      menuWidth: menuWidth,
      alignment: alignment,
      offset: offset,
      onOpen: onOpen,
      onClose: onClose,
      menuBuilder: (context, close) {
        return items.map((item) {
          final label = itemLabelBuilder(item);
          return PlayerMenuItem(
            text: label,
            trailing: item == currentValue
                ? Icon(
                    Icons.check,
                    color: checkmarkColor ?? Colors.blue,
                    size: 16,
                  )
                : null,
            onTap: () {
              onSelected(item);
              close();
            },
          );
        }).toList();
      },
      useAnimation: useAnimation,
      child: wrappedTrigger,
    );
  }
}
