import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'cover_scene.dart';
import 'theme/tokens.dart';
import 'widgets/art_image.dart';
import 'widgets/icons.dart';
import 'widgets/interactive.dart';

abstract final class FocusGeo {
  static const minSide = 380.0, maxSide = 440.0, margin = 160.0;
  static const barGap = 24.0;
  static const radius = 12.0;
  static const haloShare = 1.6;
  static const zoom = 0.06;

  static const enter = Duration(milliseconds: 380);
  static const exit = Duration(milliseconds: 300);
  static const idle = Duration(milliseconds: 2500);
  static const hide = Duration(milliseconds: 300);
  static const show = Duration(milliseconds: 150);
  static const swap = Duration(milliseconds: 600);

  static double side(Size window) {
    final short = math.min(window.width, window.height);
    final base = (short * 0.42).clamp(minSide, maxSide);
    return math.max(0.0, math.min(base, short - margin));
  }

  // The cover and the player capsule under it form one centred group.
  static Rect cover(Size window) {
    final s = side(window);
    final group = s + barGap + Dp.playerH;
    return Rect.fromLTWH(
      (window.width - s) / 2,
      math.max(0.0, (window.height - group) / 2),
      s,
      s,
    );
  }

  static double barTop(Size window) => cover(window).bottom + barGap;

  static Rect halo(Size window) {
    final r = cover(window);
    return Rect.fromCenter(
      center: r.center,
      width: r.width * haloShare,
      height: r.height * haloShare,
    );
  }
}

class FocusCover extends StatefulWidget {
  const FocusCover({super.key, required this.track, required this.side});

  final Track? track;
  final double side;

  @override
  State<FocusCover> createState() => _FocusCoverState();
}

class _FocusCoverState extends State<FocusCover> {
  String? _shown;
  String? _want;

  static String? _url(Track? t) {
    final u = t?.artworkUrl;
    return isDefaultArt(u) ? null : artUrl(u, ArtSize.t500);
  }

  // Decoded at the source size, so the window size never stretches it.
  static ImageProvider _provider(String url) =>
      ArtCache.override?.call(url) ?? CachedArt(url);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load(_url(widget.track));
  }

  @override
  void didUpdateWidget(FocusCover old) {
    super.didUpdateWidget(old);
    _load(_url(widget.track));
  }

  void _load(String? url) {
    if (url == _want) return;
    _want = url;
    if (url == null) {
      // Both callers are followed by a build.
      _shown = null;
      return;
    }
    // Swap only once the new art is decoded, so the crossfade never shows a
    // placeholder between two covers.
    precacheImage(_provider(url), context, onError: (_, _) {}).then((_) {
      if (mounted && _want == url) setState(() => _shown = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.side;
    final url = _shown;
    final pulse = CoverSceneScope.maybeOf(context)?.pulse;
    Widget art = AnimatedSwitcher(
      duration: FocusGeo.swap,
      switchInCurve: Curves.linear,
      switchOutCurve: const Threshold(0),
      child: url == null
          ? ArtPlaceholder(
              key: const ValueKey('focus-placeholder'),
              size: s,
              radius: FocusGeo.radius,
            )
          : ClipRRect(
              key: ValueKey(url),
              borderRadius: BorderRadius.circular(FocusGeo.radius),
              child: Image(
                image: _provider(url),
                width: s,
                height: s,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) =>
                    ArtPlaceholder(size: s, radius: FocusGeo.radius),
              ),
            ),
    );
    art = DecoratedBox(
      key: const ValueKey('focus-cover'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FocusGeo.radius),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 48, offset: Offset(0, 18)),
          BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: SizedBox.square(dimension: s, child: art),
    );
    if (pulse == null) return RepaintBoundary(child: art);
    return ValueListenableBuilder<PulseFrame>(
      valueListenable: pulse,
      // The sharp cover follows the background beat at a third of its swing.
      builder: (context, f, child) =>
          Transform.scale(scale: 1 + (f.scale - 1) / 3, child: child),
      child: RepaintBoundary(child: art),
    );
  }
}

class FocusCloseButton extends StatelessWidget {
  const FocusCloseButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: 'Exit focus mode',
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: 18,
        child: Container(
          key: const ValueKey('focus-close'),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.pillFill,
            shape: BoxShape.circle,
            border: Border.all(color: c.rim),
          ),
          alignment: Alignment.center,
          child: AgIcon(AgGlyph.close, color: s.hovered ? c.ink : c.ink2, size: 24),
        ),
      ),
    );
  }
}
