import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../player/player_controller.dart';
import 'cover_scene.dart';
import 'theme/tokens.dart';
import 'widgets/art_image.dart';

abstract final class FocusGeo {
  static const minSide = 480.0, maxSide = 520.0;
  // Room kept free under the cover in height and around it in width.
  static const marginV = 240.0, marginH = 160.0;
  static const radius = 12.0;
  static const zoom = 0.06;

  // The soft halo under the sharp cover: a blurred copy this much larger.
  static const halo = 1.15, haloAlpha = 0.6;
  // The halo image is feathered inside its square; this is how much of the
  // image width the opaque body takes.
  static const haloBody = 0.76;

  static const barMax = 880.0;
  // Clear space between the cover or bar and an open track panel.
  static const panelClear = 32.0;

  static const enter = Duration(milliseconds: 380);
  static const exit = Duration(milliseconds: 300);
  static const glow = Duration(milliseconds: 400);
  static const idle = Duration(seconds: 3);
  static const hide = Duration(milliseconds: 300);
  static const show = Duration(milliseconds: 150);
  static const swap = Duration(milliseconds: 600);
  static const drift = Duration(seconds: 10);

  static double side(Size window) {
    final base = (math.min(window.width, window.height) * 0.5).clamp(minSide, maxSide);
    return math.max(
      0.0,
      math.min(base, math.min(window.height - marginV, window.width - marginH)),
    );
  }

  // Equal air above the cover and under the bar, with the bar one third of
  // the way from the cover's bottom edge to the window's bottom edge.
  static double coverTop(Size window) {
    final s = side(window);
    return math.max(0.0, (2 * (window.height - s) - 3 * Dp.playerH) / 5);
  }

  static Rect cover(Size window) {
    final s = side(window);
    return Rect.fromLTWH((window.width - s) / 2, coverTop(window), s, s);
  }

  static double barTop(Size window) {
    final bottom = cover(window).bottom;
    return bottom + (window.height - bottom) / 3;
  }

  static double barWidth(double windowWidth, double normal) =>
      math.min(barMax, math.max(normal, windowWidth * 0.46));

  // Where the free area ends when the track panel is open (panelLeft is the
  // panel's resting left edge), blended by the panel's progress t.
  static double freeWidth(double windowWidth, double panelLeft, double t) {
    final open = math.max(0.0, panelLeft - panelClear / 2);
    return windowWidth + (open - windowWidth) * t;
  }

  // Cover rect at its full size, centred in the free area, and the scale that
  // keeps it inside that area.
  static (Rect, double) stage(Size window, double panelLeft, double t) {
    final base = cover(window);
    final free = freeWidth(window.width, panelLeft, t);
    final scale = base.width == 0
        ? 1.0
        : math.min(1.0, math.max(0.3, (free - 2 * panelClear) / base.width));
    return (Rect.fromLTWH(free / 2 - base.width / 2, base.top, base.width, base.height), scale);
  }

  static String? artUrlOf(Track? t) {
    final u = t?.artworkUrl;
    return isDefaultArt(u) ? null : artUrl(u, ArtSize.t500);
  }

  // The size the bar already shows: usually cached, so the cover can switch at once.
  static String? lowUrlOf(Track? t) {
    final u = t?.artworkUrl;
    return isDefaultArt(u) ? null : artUrl(u, ArtSize.t300);
  }

  // Decoded at the source size, so the window size never stretches it.
  static ImageProvider provider(String url) =>
      ArtCache.override?.call(url) ?? CachedArt(url);
}

// Always follows the player's current track, not the one Focus opened with.
// The sharp cover switches over 600 ms (an AnimatedSwitcher keyed by track id)
// with a soft halo of its own colours under it.
class FocusCover extends StatefulWidget {
  const FocusCover({super.key, required this.player, required this.side});

  final PlayerController player;
  final double side;

  @override
  State<FocusCover> createState() => _FocusCoverState();
}

class _FocusCoverState extends State<FocusCover> {
  String? _shownKey, _shownUrl, _shownLow;
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
    final low = FocusGeo.lowUrlOf(t);
    final key = t == null ? null : '${t.id}|$url';
    if (key == _want) return;
    _want = key;
    if (url == null || low == null) {
      _shownKey = key;
      _shownUrl = null;
      _shownLow = null;
      if (!building && mounted) setState(() {});
      return;
    }
    // Wait only for the small version the bar already shows, so the switch
    // starts at once; the large one fades in over it when it is decoded.
    precacheImage(FocusGeo.provider(low), context, onError: (_, _) {}).then((_) {
      if (mounted && _want == key) {
        setState(() {
          _shownKey = key;
          _shownUrl = url;
          _shownLow = low;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.side;
    final url = _shownUrl;
    final scene = CoverSceneScope.maybeOf(context);
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
          : _SharpCover(key: ValueKey(_shownKey), url: url, low: _shownLow, side: s),
    );
    art = DecoratedBox(
      key: const ValueKey('focus-cover'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FocusGeo.radius),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: SizedBox.square(dimension: s, child: art),
    );
    Widget out = Stack(
      clipBehavior: Clip.none,
      children: [
        if (scene != null) _Halo(art: scene.art, side: s),
        art,
      ],
    );
    out = RepaintBoundary(child: out);
    final pulse = scene?.pulse;
    if (pulse == null) return out;
    return ValueListenableBuilder<PulseFrame>(
      valueListenable: pulse,
      // The sharp cover follows the background beat at a third of its swing.
      builder: (context, f, child) =>
          Transform.scale(scale: 1 + (f.scale - 1) / 3, child: child),
      child: out,
    );
  }
}

class _SharpCover extends StatelessWidget {
  const _SharpCover({super.key, required this.url, required this.low, required this.side});

  final String url;
  final String? low;
  final double side;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(FocusGeo.radius),
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (low != null)
              Image(
                image: FocusGeo.provider(low!),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) => const SizedBox.shrink(),
              ),
            Image(
              key: ValueKey('focus-image|$url'),
              image: FocusGeo.provider(url),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                opacity: sync || frame != null ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: child,
              ),
              errorBuilder: (context, _, _) =>
                  ArtPlaceholder(size: side, radius: FocusGeo.radius),
            ),
          ],
        ),
      ),
    );
  }
}

// A blurred copy of the cover, 15% larger and 60% opaque, built once per track
// with the rest of its art. Crossfades with the previous track's halo.
class _Halo extends StatelessWidget {
  const _Halo({required this.art, required this.side});

  final ValueListenable<CoverArt?> art;
  final double side;

  @override
  Widget build(BuildContext context) {
    final d = side * FocusGeo.halo / FocusGeo.haloBody;
    return Positioned(
      key: const ValueKey('focus-halo'),
      left: (side - d) / 2,
      top: (side - d) / 2,
      width: d,
      height: d,
      child: IgnorePointer(
        child: ValueListenableBuilder<CoverArt?>(
          valueListenable: art,
          builder: (context, a, _) => AnimatedSwitcher(
            duration: FocusGeo.swap,
            child: a == null
                ? const SizedBox.shrink(key: ValueKey('halo-none'))
                : RawImage(
                    key: ValueKey('halo|${a.url}'),
                    image: a.glow,
                    width: d,
                    height: d,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    color: Color.fromRGBO(255, 255, 255, FocusGeo.haloAlpha),
                    colorBlendMode: BlendMode.modulate,
                  ),
          ),
        ),
      ),
    );
  }
}

// Full-window Focus backdrop: a solid wash of the cover's darkest tone with two
// or three big soft spots of its palette drifting over one 10 s cycle. A track
// change builds the next layer from its already computed palette and fades the
// two ready layers over 600 ms. Each spot is painted once into its own layer
// and only moved by transforms; the beat only changes a highlight's opacity.
class FocusBackdrop extends StatefulWidget {
  const FocusBackdrop({
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
  State<FocusBackdrop> createState() => _FocusBackdropState();
}

class _FocusBackdropState extends State<FocusBackdrop>
    with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(FocusBackdrop old) {
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
                  // The outgoing layer stays opaque until removed, so no dip shows.
                  switchOutCurve: const Threshold(0),
                  child: _BackdropLayer(
                    key: ValueKey('backdrop|${art?.url}|$night'),
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
                          FocusBackdrop.highlight,
                      child: child,
                    ),
                    child: RepaintBoundary(
                      child: _Spot2(
                        key: const ValueKey('backdrop-beat'),
                        color: Color.lerp(colors.first, Colors.white, 0.25)!,
                        size: size,
                        centre: const Offset(0.5, 0.45),
                        scale: 1.0,
                      ),
                    ),
                  ),
                const FocusGrain(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BackdropLayer extends StatelessWidget {
  const _BackdropLayer({
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
      key: const ValueKey('focus-backdrop'),
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
                key: ValueKey('backdrop-spot-$i'),
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

// One soft circular spot. The alpha falls off along a squared cosine, so the
// gradient has no visible kinks between its stops.
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

  static const _steps = 12;
  static final _stops = [for (var i = 0; i <= _steps; i++) i / _steps];

  static List<Color> ramp(Color c) => [
    for (final t in _stops)
      c.withValues(alpha: c.a * math.pow(math.cos(t * math.pi / 2), 2).toDouble()),
  ];

  @override
  Widget build(BuildContext context) {
    final d = math.max(size.width, size.height) * 1.05 * scale;
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
              gradient: RadialGradient(colors: ramp(color), stops: _stops),
            ),
          ),
        ),
      ],
    );
  }
}

// A static noise tile, generated once, drawn tiled at ~3% alpha over the
// backdrop so the dark gradients never show banding rings.
abstract final class GrainTexture {
  static const size = 128, alpha = 8;
  static ui.Image? image;

  static Future<ui.Image> load() async {
    final hit = image;
    if (hit != null) return hit;
    final rnd = math.Random(11);
    final px = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      final v = rnd.nextInt(256);
      px[i * 4] = v;
      px[i * 4 + 1] = v;
      px[i * 4 + 2] = v;
      px[i * 4 + 3] = alpha;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, size, size, ui.PixelFormat.rgba8888, done.complete);
    return image = await done.future;
  }
}

class FocusGrain extends StatefulWidget {
  const FocusGrain({super.key});

  @override
  State<FocusGrain> createState() => _FocusGrainState();
}

class _FocusGrainState extends State<FocusGrain> {
  ui.Image? _tile = GrainTexture.image;

  @override
  void initState() {
    super.initState();
    if (_tile == null) {
      GrainTexture.load().then((i) {
        if (mounted) setState(() => _tile = i);
      });
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: const ValueKey('backdrop-grain'),
      painter: _GrainPainter(_tile),
      child: const SizedBox.expand(),
    ),
  );
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.tile);

  final ui.Image? tile;

  @override
  void paint(Canvas canvas, Size size) {
    final t = tile;
    if (t == null) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.ImageShader(
          t,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.none,
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.tile != tile;
}
