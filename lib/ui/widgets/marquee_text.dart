import 'package:flutter/material.dart';

// A one-line label that is ellipsized while it does not fit and, when enabled,
// scrolls slowly to its end and back while the pointer rests on it.
class MarqueeText extends StatefulWidget {
  const MarqueeText(this.text, {super.key, required this.style, this.enabled = true});

  final String text;
  final TextStyle style;
  final bool enabled;

  // Scroll speed in dp per second, and the share of each leg spent moving.
  static const speed = 30.0;
  static const _moving = 0.76;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _hover = false;
  double _overflow = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _enter(double overflow) {
    _overflow = overflow;
    final ms = (overflow / MarqueeText.speed * 1000 / MarqueeText._moving).round();
    _c.duration = Duration(milliseconds: ms.clamp(1500, 30000));
    _c.repeat(reverse: true);
    setState(() => _hover = true);
  }

  void _leave() {
    _c.stop();
    _c.value = 0;
    if (_hover) setState(() => _hover = false);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final plain = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final overflow = tp.width - box.maxWidth;
        tp.dispose();
        if (!widget.enabled || overflow <= 0.5) {
          if (_hover) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _leave();
            });
          }
          return plain;
        }
        return MouseRegion(
          onEnter: (_) => _enter(overflow),
          onExit: (_) => _leave(),
          child: _hover
              ? ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, child) {
                        final k = ((_c.value - (1 - MarqueeText._moving) / 2) /
                                MarqueeText._moving)
                            .clamp(0.0, 1.0);
                        return Transform.translate(
                          offset: Offset(-_overflow * k, 0),
                          child: child,
                        );
                      },
                      child: Text(widget.text, maxLines: 1, softWrap: false, style: style),
                    ),
                  ),
                )
              : plain,
        );
      },
    );
  }
}
