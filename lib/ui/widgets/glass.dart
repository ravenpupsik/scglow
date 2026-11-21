import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'track_row.dart';

class SmokeBackground extends StatefulWidget {
  const SmokeBackground({super.key, required this.active});

  final ValueListenable<bool> active;

  static const period = Duration(seconds: 24);
  static const _tick = Duration(milliseconds: 40);
  static const restPhase = 0.32;

  static const centre = Offset(0.60, 0.70);
  static const orbitX = 0.10, orbitY = 0.08;

  static const span = 1.0;

  @visibleForTesting
  static double? debugPhase;

  static (double, double, double) pose(double phase) {
    final a = 2 * math.pi * phase;
    return (
      centre.dx + orbitX * math.cos(a),
      centre.dy + orbitY * math.sin(a),
      1.01 - 0.05 * math.cos(a),
    );
  }

  @override
  State<SmokeBackground> createState() => _SmokeBackgroundState();
}

class _SmokeBackgroundState extends State<SmokeBackground> {
  final _phase = ValueNotifier<double>(SmokeBackground.restPhase);
  final _clock = Stopwatch();
  Timer? _timer;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    widget.active.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(SmokeBackground old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      old.active.removeListener(_sync);
      widget.active.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final fixed = SmokeBackground.debugPhase;
    final run = widget.active.value && !_reduce && fixed == null;
    if (run && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(SmokeBackground._tick, (_) {
        final ms = SmokeBackground.period.inMilliseconds;
        _phase.value =
            SmokeBackground.restPhase + (_clock.elapsedMilliseconds % ms) / ms;
      });
    } else if (!run && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _clock.stop();
    }
    if (fixed != null) {
      _phase.value = fixed;
    } else if (_reduce) {
      _phase.value = SmokeBackground.restPhase;
    }
  }

  @override
  void dispose() {
    widget.active.removeListener(_sync);
    _timer?.cancel();
    _phase.dispose();
    super.dispose();
  }

  Widget _image(String asset, BoxFit fit) => Image.asset(
    asset,
    fit: fit,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final blob = RepaintBoundary(child: _image(c.blobAsset, BoxFit.fill));
    return RepaintBoundary(
      child: ColoredBox(
        color: c.bg,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            final side = SmokeBackground.span * w;
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                RepaintBoundary(child: _image(c.smokeAsset, BoxFit.cover)),
                ValueListenableBuilder<double>(
                  valueListenable: _phase,
                  builder: (context, phase, child) {
                    final (x, y, s) = SmokeBackground.pose(phase);
                    return Transform(
                      transform: Matrix4.identity()
                        ..translateByDouble(x * w, y * h, 0, 1)
                        ..scaleByDouble(s, s, 1, 1)
                        ..translateByDouble(-side / 2, -side / 2, 0, 1),
                      child: child,
                    );
                  },
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: side,
                    maxWidth: side,
                    minHeight: side,
                    maxHeight: side,
                    child: blob,
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(painter: DotGridPainter(c.gridDot)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class DotGridPainter extends CustomPainter {
  DotGridPainter(this.color, {this.dot = 1.4});

  final Color color;

  final double dot;
  static const pitch = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[
      for (var y = pitch / 2; y < size.height; y += pitch)
        for (var x = pitch / 2; x < size.width; x += pitch) Offset(x, y),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = color
        ..strokeWidth = dot
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(DotGridPainter old) =>
      old.color != color || old.dot != dot;
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.contentHeight,
    required this.child,
    this.radius = Dp.rCard,
    this.maxHeight,
  });

  final double contentHeight;
  final Widget child;
  final double radius;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final h = math.min(contentHeight, maxHeight ?? box.maxHeight);
        final overflow = contentHeight > h + 0.5;
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: h,
            decoration: c.card(fill: c.cardGlass, radius: radius),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: _CardOverflow(
                overflow: overflow,
                child: overflow ? BottomFade(child: child) : child,
              ),
            ),
          ),
        );
      },
    );
  }

  static bool overflowOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardOverflow>()?.overflow ??
      false;

  static double bottomPad(BuildContext context) =>
      Dp.cardPadY + (overflowOf(context) ? Dp.fadeH : 0);
}

class _CardOverflow extends InheritedWidget {
  const _CardOverflow({required this.overflow, required super.child});

  final bool overflow;

  @override
  bool updateShouldNotify(_CardOverflow old) => old.overflow != overflow;
}

class BottomFade extends StatelessWidget {
  const BottomFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (rect) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [
        0,
        1 - Dp.fadeH / rect.height.clamp(Dp.fadeH, double.infinity),
        1,
      ],
    ).createShader(rect),
    child: child,
  );
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.count = 3, this.opacity});

  final int count;
  final double? opacity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Dp.hPad, 0, Dp.hPad, 20),
    child: GroupCard(
      contentHeight: count * Dp.row + Dp.cardPadY * 2 + 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dp.cardPadY),
        child: SkeletonRows(count: count, opacity: opacity),
      ),
    ),
  );
}

class CoverBezel extends StatelessWidget {
  const CoverBezel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: AgColors.of(context).card(radius: Dp.rBezel),
    child: child,
  );
}

class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    super.key,
    required this.radius,
    required this.child,
    this.padding,
    this.width,
  });

  final double radius;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;

  // Blur behind floating glass keeps list text underneath from hurting contrast.
  static const blur = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          padding: padding,
          decoration: c.card(fill: c.cardGlass, radius: radius),
          child: child,
        ),
      ),
    );
  }
}
