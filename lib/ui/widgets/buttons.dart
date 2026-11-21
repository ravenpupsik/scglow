import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'icons.dart';
import 'interactive.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.width,
    this.height = 36,
    this.fontSize = 13,
    this.glyph,
  });

  final String label;
  final VoidCallback? onTap;
  final double? width;
  final double height;
  final double fontSize;

  final AgGlyph? glyph;

  double get _radius => height <= Dp.chipH ? Dp.rChip : Dp.rButton;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: _radius,
        child: Container(
          width: width,
          height: height,
          padding: width == null
              ? EdgeInsets.only(
                  left: glyph != null ? (height <= Dp.chipH ? 7 : 18) : 24,
                  right: height <= Dp.chipH ? 12 : 24)
              : EdgeInsets.zero,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null
                ? c.ink.withValues(alpha: 0.35)
                : s.pressed
                    ? c.primaryPressed
                    : s.hovered
                        ? c.primaryHover
                        : c.ink,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                AgIcon(glyph!, color: c.bg, size: fontSize + 6),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(label,
                    style: AgType.ui(fontSize, c.bg, weight: 600),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.width,
    this.height = 36,
    this.fontSize = 13,
    this.weight = 600,
    this.hPad = 10,
  });

  const SecondaryButton.small({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 24,
  })  : width = null,
        fontSize = 11,
        weight = 650,
        hPad = 10;

  final String label;
  final VoidCallback? onTap;
  final double? width;
  final double height;
  final double fontSize;
  final int weight;
  final double hPad;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final radius = height <= Dp.chipH ? Dp.rChip : Dp.rButton;
    return Interactive(
      onTap: onTap,
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: radius,
        child: Container(
          width: width,
          height: height,
          padding: width == null
              ? EdgeInsets.symmetric(horizontal: hPad)
              : EdgeInsets.zero,
          alignment: Alignment.center,
          decoration: c.tile(radius: radius),
          foregroundDecoration: s.pressed || s.hovered
              ? BoxDecoration(
                  color: s.pressed ? c.pressed : c.hover,
                  borderRadius: BorderRadius.circular(radius),
                )
              : null,
          child: Text(label,
              style: AgType.ui(fontSize, onTap == null ? c.disabled : c.ink,
                  weight: weight),
              maxLines: 1),
        ),
      ),
    );
  }
}

class PlayAllChip extends StatelessWidget {
  const PlayAllChip({super.key, required this.onTap, this.label = 'Play all'});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => PrimaryButton(
        label: label,
        onTap: onTap,
        height: Dp.chipH,
        fontSize: 12,
        glyph: AgGlyph.play,
      );
}

class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, required this.onTap, this.width});

  final String label;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) => SecondaryButton(
        label: label,
        onTap: onTap,
        width: width,
        height: Dp.chipH,
        fontSize: 12,
        weight: 500,
        hPad: 10,
      );
}

class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.glyph,
    required this.color,
    required this.onTap,
    this.size = Dp.iconBtn,
    this.iconSize = 24,
    this.semanticLabel,
    this.tile = false,
  });

  final AgGlyph glyph;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String? semanticLabel;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final overlay = hoverOverlay(c);
    return Interactive(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.rIconBtn,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: tile ? c.tile(radius: Dp.rIconBtn) : null,
          foregroundDecoration: overlay(s),
          child: AgIcon(glyph, color: color, size: iconSize),
        ),
      ),
    );
  }

  static BoxDecoration? Function(InteractState) hoverOverlay(AgColors c) =>
      (s) => s.pressed || s.hovered
          ? BoxDecoration(
              color: s.pressed ? c.pressed : c.hover,
              borderRadius: BorderRadius.circular(Dp.rIconBtn),
            )
          : null;
}

class RefreshButton extends StatefulWidget {
  const RefreshButton({
    super.key,
    required this.refreshing,
    required this.onTap,
  });

  final bool refreshing;
  final VoidCallback onTap;

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(RefreshButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.refreshing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.refreshing && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final busy = widget.refreshing;
    return Interactive(
      onTap: busy ? null : widget.onTap,
      cursor: busy ? MouseCursor.defer : SystemMouseCursors.click,
      semanticLabel: 'Refresh',
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.rIconBtn,
        child: Container(
          width: Dp.pageIconBtn,
          height: Dp.pageIconBtn,
          alignment: Alignment.center,
          decoration: c.tile(radius: Dp.rIconBtn),
          foregroundDecoration: busy ? null : IconBtn.hoverOverlay(c)(s),
          child: RotationTransition(
            turns: _spin,
            child: AgIcon(AgGlyph.refresh,
                color: busy ? c.muted : c.ink2, size: 20),
          ),
        ),
      ),
    );
  }
}
