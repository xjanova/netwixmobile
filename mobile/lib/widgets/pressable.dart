import 'package:flutter/material.dart';

/// Gives a tappable surface a physical press: it dips slightly under the finger and springs back.
///
/// The cards were bare GestureDetectors, so a tap produced no acknowledgement at all until the next
/// screen appeared. On a slow connection that reads as an app that didn't register the tap, and
/// it's a large part of why a UI feels machine-assembled rather than made — real products answer
/// every touch immediately, even when the work behind it takes a moment.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.965,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// How far the surface dips. Deliberately shallow — a big scale reads as a toy.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        // Fast in, gentle out: the dip should feel instant, the release should settle.
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
