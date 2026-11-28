import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../player/player_controller.dart';
import 'cover_scene.dart';
import 'theme/tokens.dart';
import 'widgets/art_image.dart';
import 'widgets/icons.dart';
import 'widgets/interactive.dart';

abstract final class FocusGeo {
  static const minSide = 440.0, maxSide = 480.0;
  // Room kept free under the cover in height and around it in width.
  static const marginV = 260.0, marginH = 160.0;
  static const barGap = 112.0;
  static const radius = 12.0;
  static const zoom = 0.06;

  static const enter = Duration(milliseconds: 380);
  static const exit = Duration(milliseconds: 300);
  static const glow = Duration(milliseconds: 400);
  static const idle = Duration(milliseconds: 2500);
  static const hide = Duration(milliseconds: 300);
  static const show = Duration(milliseconds: 150);
  static const swap = Duration(milliseconds: 600);
  static const drift = Duration(seconds: 10);

  static double side(Size window) {
    final short = math.min(window.width, window.height);
    final base = (short * 0.44).clamp(minSide, maxSide);
    return math.max(
      0.0,
      math.min(base, math.min(window.height - marginV, window.width - marginH)),
    );
  }

  // The cover and the player capsule under it form one vertically centred group.
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

  static String? artUrlOf(Track? t) {
    final u = t?.artworkUrl;
    return isDefaultArt(u) ? null : artUrl(u, ArtSize.t500);
  }

  // Decoded at the source size, so the window size never stretches it.
  static ImageProvider provider(String url) =>
      ArtCache.override?.call(url) ?? CachedArt(url);
}

// Always follows the player's current track, not the one Focus opened with.
class FocusCover extends StatefulWidget {
  const FocusCover({super.key, required this.player, required this.side});

  final PlayerController player;
  final double side;

  @override
  State<FocusCover> createState() => _FocusCoverState();
}

class _FocusCoverState extends State<FocusCover> {
  String? _shownKey, _shownUrl;
  String? _want;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(building: true);
  }

  @override
  void didUpdateWidget(FocusCover old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      old.player.removeListener(_sync);
      widget.player.addListener(_sync);
      _sync(building: true);
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_sync);
    super.dispose();
  }

  void _sync({bool building = false}) {
    final t = widget.player.current;
    final url = FocusGeo.artUrlOf(t);
    final key = t == null ? null : '${t.id}|$url';
    if (key == _want) return;
    _want = key;
    if (url == null) {
      _shownKey = key;
      _shownUrl = null;
      if (!building && mounted) setState(() {});
      return;
    }
    // Swap only once the new art is decoded, so the crossfade never shows a
    // placeholder between two covers.
    precacheImage(FocusGeo.provider(url), context, onError: (_, _) {}).then((_) {
      if (mounted && _want == key) {
        setState(() {
          _shownKey = key;
          _shownUrl = url;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.side;
    final url = _shownUrl;
    final pulse = CoverSceneScope.maybeOf(context)?.pulse;
    Widget art = AnimatedSwitcher(
      duration: FocusGeo.swap,
      switchInCurve: Curves.linear,
      switchOutCurve: const Threshold(0),
      child: url == null
          ? ArtPlaceholder(
              key: ValueKey('focus-placeholder|$_shownKey'),
              size: s,
              radius: FocusGeo.radius,
            )
          : ClipRRect(
              key: ValueKey(_shownKey),
              borderRadius: BorderRadius.circular(FocusGeo.radius),
              child: Image(
                key: ValueKey('focus-image|$url'),
                image: FocusGeo.provider(url),
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
    art = RepaintBoundary(child: art);
    if (pulse == null) return art;
    return ValueListenableBuilder<PulseFrame>(
      valueListenable: pulse,
      // The sharp cover follows the background beat at a third of its swing.
      builder: (context, f, child) =>
          Transform.scale(scale: 1 + (f.scale - 1) / 3, child: child),
      child: art,
    );
  }
}

// Full-window Focus backdrop: a solid wash of the cover's darkest tone with two
// or three big soft spots of its palette drifting over one 10 s cycle. Each
// spot is painted once into its own layer and only moved by transforms; the
// beat only changes the opacity of a highlight layer.
class FocusGlow extends StatefulWidget {
  const FocusGlow({
    super.key,
    required this.art,
    required this.visible,
    this.pulse,
  });

  final CoverArt? art;
  final Animation<double> visible;
  final ValueListenable<PulseFrame>? pulse;

  static const highlight = 0.35;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: FocusGeo.drift,
  );

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_run);
    _run();
  }

  @override
  void didUpdateWidget(FocusGlow old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      old.visible.removeListener(_run);
      widget.visible.addListener(_run);
      _run();
    }
  }

  void _run() {
    final on = widget.visible.value > 0;
    if (on && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!on && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_run);
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final art = widget.art;
    final palette = art == null || art.palette.isEmpty
        ? [c.washBase, c.washBase]
        : art.palette;
    final night = c.isNight;
    final colors = [for (final p in palette) CoverColor.glow(p, night: night)];
    final base = CoverColor.glowBase(palette.last, night: night);
    final pulse = widget.pulse;
    return IgnorePointer(
      child: FadeTransition(
        opacity: widget.visible,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: FocusGeo.swap,
                  switchInCurve: Curves.linear,
                  switchOutCurve: const Threshold(0),
                  child: _GlowSpots(
                    key: ValueKey('glow|${art?.url}|$night'),
                    size: size,
                    base: base,
                    colors: colors,
                    drift: _drift,
                  ),
                ),
                if (pulse != null)
                  ValueListenableBuilder<PulseFrame>(
                    valueListenable: pulse,
                    builder: (context, f, child) => Opacity(
                      opacity: (f.bright / PulseEnvelope.brightMax).clamp(0.0, 1.0) *
                          FocusGlow.highlight,
                      child: child,
                    ),
                    child: RepaintBoundary(
                      child: _Spot2(
                        key: const ValueKey('glow-beat'),
                        color: Color.lerp(colors.first, Colors.white, 0.25)!,
                        size: size,
                        centre: const Offset(0.5, 0.45),
                        scale: 1.0,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlowSpots extends StatelessWidget {
  const _GlowSpots({
    super.key,
    required this.size,
    required this.base,
    required this.colors,
    required this.drift,
  });

  final Size size;
  final Color base;
  final List<Color> colors;
  final Animation<double> drift;

  static const _centres = [Offset(0.28, 0.34), Offset(0.74, 0.66), Offset(0.62, 0.18)];
  static const _scales = [1.0, 0.9, 0.7];

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('focus-glow'),
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: ColoredBox(color: base)),
        for (var i = 0; i < colors.length && i < _centres.length; i++)
          AnimatedBuilder(
            animation: drift,
            builder: (context, child) {
              final a = 2 * math.pi * drift.value + i * 2.1;
              return Transform.translate(
                offset: Offset(
                  math.cos(a) * size.width * 0.07,
                  math.sin(a * (i.isEven ? 1 : -1)) * size.height * 0.08,
                ),
                child: Transform.scale(scale: 1 + 0.08 * math.sin(a + 1.3), child: child),
              );
            },
            child: RepaintBoundary(
              child: _Spot2(
                key: ValueKey('glow-spot-$i'),
                color: colors[i],
                size: size,
                centre: _centres[i],
                scale: _scales[i],
              ),
            ),
          ),
      ],
    );
  }
}

class _Spot2 extends StatelessWidget {
  const _Spot2({
    super.key,
    required this.color,
    required this.size,
    required this.centre,
    required this.scale,
  });

  final Color color;
  final Size size;
  final Offset centre;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final d = math.max(size.width, size.height) * 0.95 * scale;
    return Stack(
      children: [
        Positioned(
          left: size.width * centre.dx - d / 2,
          top: size.height * centre.dy - d / 2,
          width: d,
          height: d,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
                stops: const [0, 0.42, 1],
              ),
            ),
          ),
        ),
      ],
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
