import 'dart:math' as math;

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

  static double side(Size window) {
    final base = (math.min(window.width, window.height) * 0.5).clamp(minSide, maxSide);
    return math.max(0.0, math.min(base, math.min(window.height - marginV, window.width - marginH)));
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
  static ImageProvider provider(String url) => ArtCache.override?.call(url) ?? CachedArt(url);
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
  String? _shownKey, _shownUrl, _shownLow, _shownArt;
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
    final raw = t?.artworkUrl;
    final url = FocusGeo.artUrlOf(t);
    final low = FocusGeo.lowUrlOf(t);
    final key = t == null ? null : '${t.id}|$url';
    if (key == _want) return;
    _want = key;
    if (url == null || low == null) {
      _shownKey = key;
      _shownUrl = null;
      _shownLow = null;
      _shownArt = raw;
      if (!building && mounted) setState(() {});
      return;
    }
    // Wait only for the small version the bar already shows, so the switch
    // starts at once; the large one fades in over it when it is decoded.
    // The halo is not waited on: it fades in later if the glow is still building.
    precacheImage(FocusGeo.provider(low), context, onError: (_, _) {}).then((_) {
      if (mounted && _want == key) {
        setState(() {
          _shownKey = key;
          _shownUrl = url;
          _shownLow = low;
          _shownArt = raw;
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
        if (scene != null) _Halo(art: scene.art, side: s, url: _shownArt),
        art,
      ],
    );
    out = RepaintBoundary(child: out);
    final pulse = scene?.pulse;
    if (pulse == null) return out;
    return ValueListenableBuilder<PulseFrame>(
      valueListenable: pulse,
      // The sharp cover follows the background beat at a third of its swing.
      builder: (context, f, child) => Transform.scale(scale: 1 + (f.scale - 1) / 3, child: child),
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
              errorBuilder: (context, _, _) => ArtPlaceholder(size: side, radius: FocusGeo.radius),
            ),
          ],
        ),
      ),
    );
  }
}

// A blurred copy of the cover, 15% larger and 60% opaque, built ahead of
// time with the track's art. Crossfades with the previous track's halo over
// 600 ms; if the new glow is not ready, the cover switches anyway and the
// halo fades in when it arrives.
class _Halo extends StatelessWidget {
  const _Halo({required this.art, required this.side, required this.url});

  final ValueListenable<CoverArt?> art;
  final double side;
  final String? url;

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
          builder: (context, a, _) {
            final glow = a != null && a.url == url ? a.glow : null;
            return AnimatedSwitcher(
              duration: FocusGeo.swap,
              switchInCurve: Curves.linear,
              switchOutCurve: const Threshold(0),
              child: glow == null
                  ? const SizedBox.shrink(key: ValueKey('halo-none'))
                  : RawImage(
                      key: ValueKey('halo|${a!.url}'),
                      image: glow,
                      width: d,
                      height: d,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                      color: Color.fromRGBO(255, 255, 255, FocusGeo.haloAlpha),
                      colorBlendMode: BlendMode.modulate,
                    ),
            );
          },
        ),
      ),
    );
  }
}
