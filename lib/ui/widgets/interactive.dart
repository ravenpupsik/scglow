import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

class InteractState {
  const InteractState(this.hovered, this.pressed, this.focused);

  final bool hovered, pressed, focused;
}

class Interactive extends StatefulWidget {
  const Interactive({
    super.key,
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.enabled = true,
    this.cursor = SystemMouseCursors.click,
    this.tooltip,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, InteractState state) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final bool enabled;
  final MouseCursor cursor;
  final String? tooltip;

  final String? semanticLabel;

  @override
  State<Interactive> createState() => _InteractiveState();
}

class _InteractiveState extends State<Interactive> {
  bool _hover = false, _pressed = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    Widget child = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? widget.cursor : SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled ? widget.onTap : null,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: widget.onSecondaryTap == null
              ? null
              : (d) => widget.onSecondaryTap!(d.globalPosition),
          child: widget.builder(
            context,
            InteractState(_hover && enabled, _pressed, _focus),
          ),
        ),
      ),
    );
    if (widget.semanticLabel != null) {
      child = Semantics(button: true, label: widget.semanticLabel, child: child);
    }
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.show,
    required this.child,
    this.inset = false,
    this.radius = Dp.rIconBtn,
  });

  final bool show;
  final bool inset;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return CustomPaint(
      foregroundPainter: _RingPainter(
        AgColors.of(context).focus,
        inset,
        radius,
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.inset, this.radius);

  final Color color;
  final bool inset;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const o = 2 + Dp.focus / 2;
    final rect = Offset.zero & size;
    final r = inset ? rect.deflate(o) : rect.inflate(o);
    final rr = inset ? (radius - o).clamp(0.0, 99.0) : radius + o;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(rr)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = Dp.focus,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.inset != inset || old.radius != radius;
}
