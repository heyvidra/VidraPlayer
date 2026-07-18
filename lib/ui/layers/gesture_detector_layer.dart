import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../controller/player_controller.dart';
import '../../core/state/states.dart';

/// 手势检测层
class GestureDetectorLayer extends StatelessWidget {
  final PlayerController controller;
  final Function(Offset)? onDoubleTap;

  const GestureDetectorLayer({
    super.key,
    required this.controller,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UIVisibilityState>(
      stream: controller.visibilityStream,
      initialData: controller.visibility,
      builder: (context, snapshot) {
        final ui = snapshot.data ?? const UIVisibilityState();

        // 调整层级: Listener 在最外层，确保能捕获所有指针事件，
        // 即使 MouseRegion 将 cursor 设置为 none。
        return Listener(
          behavior: HitTestBehavior.opaque,
          // Mouse-only: touch jitter during a tap must NOT drive the
          // hover-show path — the hover-show would race the (double-tap
          // delayed) onTap toggle and hide the controls the same instant
          // they appear, making them unreachable on touch devices.
          onPointerHover: (event) {
            if (event.kind == PointerDeviceKind.mouse) {
              controller.handleMouseMove(event.localPosition);
            }
          },
          onPointerMove: (event) {
            if (event.kind == PointerDeviceKind.mouse) {
              controller.handleMouseMove(event.localPosition);
            }
          },
          onPointerDown: (event) => controller.handleMouseEnterVideo(),
          child: MouseRegion(
            cursor: ui.showMouseCursor
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            onEnter: (_) => controller.handleMouseEnterVideo(),
            onExit: (_) => controller.handleMouseLeaveVideo(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.toggleControls(),
              onDoubleTapDown: (details) =>
                  onDoubleTap?.call(details.localPosition),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}
