import 'dart:math';
import 'package:flutter/material.dart';

/// Netflix style Loading: Red bars bouncing
class NetflixLoading extends StatefulWidget {
  final double height;
  final double barWidth;
  final Color color;
  final int size;

  const NetflixLoading({
    super.key,
    this.height = 40,
    this.barWidth = 6,
    this.color = const Color(0xFFE50914),
    this.size = 20,
  });

  @override
  State<NetflixLoading> createState() => _NetflixLoadingState();
}

class _NetflixLoadingState extends State<NetflixLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Staggered phase
              final phase = (_controller.value + index * 0.2) % 1.0;
              final scaleY = 0.4 + 0.6 * sin(phase * pi);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: Container(
                    width: widget.barWidth,
                    height: widget.height * scaleY,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
