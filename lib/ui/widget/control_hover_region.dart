import 'package:flutter/material.dart';

import '../../controller/player_controller.dart';

class ControlHoverRegion extends StatefulWidget {
  final PlayerController controller;
  final Widget child;
  final bool enabled;
  final MouseCursor cursor;

  const ControlHoverRegion({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
    this.cursor = MouseCursor.defer,
  });

  @override
  State<ControlHoverRegion> createState() => _ControlHoverRegionState();
}

class _ControlHoverRegionState extends State<ControlHoverRegion> {
  bool _isHovering = false;

  @override
  void didUpdateWidget(covariant ControlHoverRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isHovering &&
        (!widget.enabled || oldWidget.controller != widget.controller)) {
      _leave(oldWidget.controller);
    }
  }

  @override
  void dispose() {
    if (_isHovering) {
      _leave(widget.controller);
    }
    super.dispose();
  }

  void _enter() {
    if (_isHovering || !widget.enabled) return;
    _isHovering = true;
    widget.controller.handleMouseEnterControls();
  }

  void _leave(PlayerController controller) {
    if (!_isHovering) return;
    _isHovering = false;
    controller.handleMouseLeaveControls();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _enter(),
      onExit: (_) => _leave(widget.controller),
      child: widget.child,
    );
  }
}
