import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/models.dart';
import '../format.dart';
import '../theme/tokens.dart';
import 'art_image.dart';
import 'icons.dart';
import 'interactive.dart';

abstract final class RowGeo {
  static const hoverInset = 6.0;
  static const lineInset = 16.0;
  static const lead = 10.0;
  static const handle = 18.0;
  static const right = 16.0;
  static const coverGap = 10.0;
  static const fillRadius = 4.0;
  static const edgeRadius = 8.0;

  static const durCol = 26.0;

  static double cover({bool handle = false}) =>
      lead + (handle ? RowGeo.handle : 0) + Dp.dotCol;
}

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    this.playing = false,
    this.liked = false,
    this.unavailable,
    this.preview = false,
    this.showLine = true,
    this.edge = false,
    this.handle,
    this.onTap,
    this.onLike,
    this.onContextMenu,
    this.forceHover = false,
  });

  final Track track;
  final bool playing;
  final bool liked;
  final Unavailable? unavailable;
  final bool preview;
  final bool showLine;

  final bool edge;

  final Widget? handle;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final void Function(Offset globalPosition)? onContextMenu;
  final bool forceHover;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final blocked = unavailable != null;
    return Interactive(
      onTap: onTap,
      onDoubleClick: onTap == null || blocked ? null : () => openFocusFor(context, track),
      onSecondaryTap: onContextMenu,
      builder: (context, s) {
        final hovered = s.hovered || forceHover;
        Color? fill;
        if (s.pressed && !blocked) {
          fill = c.pressed;
        } else if (playing) {
          fill = c.playingFill;
        } else if (hovered && !blocked) {
          fill = c.hover;
        }
        return CustomPaint(
          painter: RowBackground(
            fill: fill,
            radius: edge ? RowGeo.edgeRadius : RowGeo.fillRadius,
            line: showLine ? c.hairline : null,
            focus: s.focused ? c.focus : null,
          ),
          child: SizedBox(
            height: Dp.row,
            child: _content(context, c, blocked, hovered),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, AgColors c, bool blocked, bool hovered) {
    final ink = blocked ? c.disabled : c.ink;
    final artist = blocked ? c.disabled : c.artist;
    final showHeart = liked || hovered;
    final label = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: RowGeo.durCol),
      child: Text(
        blocked
            ? 'Unavailable'
            : preview
                ? '0:30'
                : formatMs(track.durationMs),
        textAlign: TextAlign.right,
        style: AgType.ui(12, blocked ? c.disabled : c.ink2, weight: 500),
      ),
    );
    return Row(
      children: [
        const SizedBox(width: RowGeo.lead),
        if (handle != null) SizedBox(width: RowGeo.handle, child: handle),
        SizedBox(
          width: Dp.dotCol,
          child: playing ? Center(child: PlayingDot(color: c.accent)) : null,
        ),
        ArtImage(
            url: track.artworkUrl,
            size: Dp.rowCover,
            dimmed: blocked,
            radius: Dp.rRowCover),
        const SizedBox(width: RowGeo.coverGap),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgType.ui(13, ink, weight: 550)),
              const SizedBox(height: 2),
              Text(track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgType.ui(12, artist)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 16,
          height: 16,
          child: showHeart
              ? HeartButton(
                  liked: liked,
                  size: 16,
                  glyphSize: 22,
                  onTap: onLike,
                  color: liked
                      ? (hovered && !blocked ? c.accent : c.heartRest)
                      : c.ink2,
                )
              : null,
        ),
        const SizedBox(width: 8),
        if (preview && !blocked) ...[
          const PreviewBadge(),
          const SizedBox(width: 8),
        ],
        if (blocked)
          HoverTip(show: hovered, text: unavailable!.label, child: label)
        else
          label,
        const SizedBox(width: RowGeo.right),
      ],
    );
  }
}

class PlayingDot extends StatelessWidget {
  const PlayingDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class RowBackground extends CustomPainter {
  RowBackground({this.fill, this.line, this.focus, this.radius = 0});

  final Color? fill, line, focus;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTRB(
        RowGeo.hoverInset, 0, size.width - RowGeo.hoverInset, size.height);
    if (fill != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)),
          Paint()..color = fill!);
    }
    if (line != null) {
      canvas.drawRect(
          Rect.fromLTRB(RowGeo.lineInset, size.height - 1,
              size.width - RowGeo.lineInset, size.height),
          Paint()..color = line!);
    }
    if (focus != null) {
      const o = 2 + Dp.focus / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.deflate(o), const Radius.circular(6)),
        Paint()
          ..color = focus!
          ..style = PaintingStyle.stroke
          ..strokeWidth = Dp.focus,
      );
    }
  }

  @override
  bool shouldRepaint(RowBackground old) =>
      old.fill != fill || old.line != line || old.focus != focus;
}

class PreviewBadge extends StatelessWidget {
  const PreviewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: c.ink2, width: 1),
        borderRadius: BorderRadius.circular(Dp.rBadge),
      ),
      child: Text('Preview', style: AgType.ui(10, c.ink2, weight: 650)),
    );
  }
}

class HeartButton extends StatelessWidget {
  const HeartButton({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 16,
    this.color,
    this.glyphSize,
  });

  final bool liked;
  final VoidCallback? onTap;
  final double size;
  final Color? color;

  final double? glyphSize;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: OverflowBox(
            maxWidth: glyphSize ?? size,
            maxHeight: glyphSize ?? size,
            child: AgIcon(
              liked ? AgGlyph.heart : AgGlyph.heartOutline,
              color: color ?? (liked ? c.accent : c.ink2),
              size: glyphSize ?? size,
            ),
          ),
        ),
      ),
    );
  }
}

class HoverTip extends StatefulWidget {
  const HoverTip({
    super.key,
    required this.show,
    required this.text,
    required this.child,
  });

  final bool show;
  final String text;
  final Widget child;

  @override
  State<HoverTip> createState() => _HoverTipState();
}

class _HoverTipState extends State<HoverTip> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HoverTip old) {
    super.didUpdateWidget(old);
    if (old.show != widget.show) _sync();
  }

  void _sync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.show && !_portal.isShowing) _portal.show();
      if (!widget.show && _portal.isShowing) _portal.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(4, -10),
            child: IgnorePointer(child: TipBox(text: widget.text)),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class TipBox extends StatelessWidget {
  const TipBox({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final fill = c.tipFill;
    return CustomPaint(
      painter: _CaretPainter(fill),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: Color.alphaBlend(c.rim, c.bg)),
          borderRadius: BorderRadius.circular(Dp.rTooltip),
        ),
        child: Text(text, style: AgType.ui(11, c.ink, weight: 500)),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter(this.fill);

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width - 14;
    final y = size.height - 1;
    canvas.drawPath(
      Path()
        ..moveTo(x - 5, y)
        ..lineTo(x, y + 6)
        ..lineTo(x + 5, y)
        ..close(),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.fill != fill;
}

class SkeletonRows extends StatefulWidget {
  const SkeletonRows({super.key, this.count = 3, this.opacity});

  final int count;

  final double? opacity;

  @override
  State<SkeletonRows> createState() => _SkeletonRowsState();
}

class _SkeletonRowsState extends State<SkeletonRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _a = Tween(begin: 1.0, end: 0.55)
      .chain(CurveTween(curve: Curves.easeInOut))
      .animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.opacity == null) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final f = widget.opacity;
    return Column(
      children: [
        for (var j = 0; j < widget.count; j++)
          SizedBox(
            height: Dp.row,
            child: CustomPaint(
              painter: RowBackground(
                  line: j < widget.count - 1 ? c.hairline : null),
              child: f != null
                  ? CustomPaint(
                      painter: _SkeletonPainter(
                          c.skeleton.withValues(alpha: c.skeleton.a * f)),
                      size: const Size(double.infinity, Dp.row),
                    )
                  : FadeTransition(
                      opacity: _a,
                      child: CustomPaint(
                        painter: _SkeletonPainter(c.skeleton),
                        size: const Size(double.infinity, Dp.row),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final x = RowGeo.cover();
    final right = size.width - RowGeo.right;
    void rr(Rect r, double radius) =>
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), p);
    rr(Rect.fromLTWH(x, (Dp.row - Dp.rowCover) / 2, Dp.rowCover, Dp.rowCover),
        Dp.rRowCover);
    rr(Rect.fromLTRB(x + 42, 12, x + 216, 21), 3);
    rr(Rect.fromLTRB(x + 42, 26, x + 136, 34), 3);
    rr(Rect.fromLTRB(right - 32, 16, right, 28), 3);
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => old.color != color;
}
