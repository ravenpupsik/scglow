import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_services.dart';
import '../app/marks.dart';
import '../core/models.dart';
import '../player/play_queue.dart';
import '../player/player_controller.dart';
import 'format.dart';
import 'theme/tokens.dart';
import 'widgets/art_image.dart';
import 'widgets/icons.dart';
import 'widgets/interactive.dart';
import 'widgets/track_row.dart';

abstract final class PlayerGeo {
  static const coverX = 12.0;
  static const coverY = 8.0;
  static const transportY = 28.0;
  static const panelBtn = 24.0;
  static const panelX = coverX + Dp.playerCover + 4;
  static const textX = panelX + panelBtn + 6;

  static const offsets = [-84.0, -47.0, 0.0, 47.0, 84.0];

  static const seekY = Dp.playerH - 14;
  static const timeX = 14.0;
  static const timeGap = 8.0;
  static const volRight = 16.0;

  static double width(double window) =>
      (Dp.playerMinW + (window - 1280) * (Dp.playerMaxW - Dp.playerMinW) / 640)
          .clamp(Dp.playerMinW, Dp.playerMaxW);

  static double timeW(int durationMs) {
    final t = formatMs(durationMs).replaceAll(RegExp(r'\d'), '0');
    final tp = TextPainter(
      text: TextSpan(text: t, style: AgType.tnum(11, const Color(0xFF000000))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width.ceilToDouble();
  }
}

class FloatingPlayer extends StatelessWidget {
  const FloatingPlayer({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final player = app.player;
    final w = width;
    return RepaintBoundary(
      child: Container(
        width: w,
        height: Dp.playerH,
        decoration: BoxDecoration(
          color: c.pillFill,
          borderRadius: BorderRadius.circular(Dp.rPlayer),
          boxShadow: c.pillShadows,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Dp.rPlayer),
          border: Border.all(color: c.rim),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge(
              [player, app.library, app.details, app.panel, app.focus]),
          builder: (context, _) {
            final track = player.current;
            final idle = track == null;
            final mid = w / 2;
            const ty = PlayerGeo.transportY;
            Widget at(int i, double size, Widget child) => Positioned(
                left: mid + PlayerGeo.offsets[i] - size / 2,
                top: ty - size / 2,
                child: child);
            final textRight = mid + PlayerGeo.offsets.first - _btn / 2 - 12;
            final volX = w - PlayerGeo.volRight - Dp.volW;
            final timeW = PlayerGeo.timeW(track?.durationMs ?? 0);
            final seekX = PlayerGeo.timeX + timeW + PlayerGeo.timeGap;
            final marks = idle ? const <int>[] : commentTimes(app, track);
            return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: PlayerGeo.coverX,
                      top: PlayerGeo.coverY,
                      child: idle
                          ? const ArtPlaceholder(size: Dp.playerCover)
                          : _CoverToggle(track: track, on: app.focus.isOn),
                    ),
                    Positioned(
                      left: PlayerGeo.panelX,
                      top: PlayerGeo.coverY + (Dp.playerCover - PlayerGeo.panelBtn) / 2,
                      child: PanelButton(
                        open: app.panel.isOpen && !app.focus.isOn,
                        onTap: idle
                            ? null
                            : () {
                                if (app.focus.isOn) {
                                  app.focus.exit();
                                  app.panel.show();
                                } else {
                                  app.panel.toggle();
                                }
                              },
                      ),
                    ),
                    Positioned(
                      left: PlayerGeo.textX,
                      top: 9,
                      height: 36,
                      width: math.max(0.0, textRight - PlayerGeo.textX),
                      child: _NowPlaying(track: track),
                    ),
                    at(
                        0,
                        _btn,
                        ModeToggle(
                          glyph: AgGlyph.shuffle,
                          on: !idle && player.shuffle,
                          onTap: idle ? null : player.toggleShuffle,
                          semanticLabel: idle
                              ? null
                              : (player.shuffle ? 'Shuffle on' : 'Shuffle off'),
                        )),
                    at(
                        1,
                        _btn,
                        PlainIcon(
                          glyph: AgGlyph.prev,
                          color: c.ink,
                          onTap: idle ? null : player.previous,
                          semanticLabel: idle ? null : 'Previous',
                        )),
                    at(
                        2,
                        Dp.playBtn,
                        PlayDrop(
                          playing: !idle && player.playing,
                          onTap: idle ? null : player.togglePlay,
                        )),
                    at(
                        3,
                        _btn,
                        PlainIcon(
                          glyph: AgGlyph.next,
                          color: c.ink,
                          onTap: idle ? null : player.next,
                          semanticLabel: idle ? null : 'Next',
                        )),
                    at(
                        4,
                        _btn,
                        ModeToggle(
                          glyph: AgGlyph.repeat,
                          on: !idle && player.repeat != LoopMode.off,
                          one: !idle && player.repeat == LoopMode.one,
                          onTap: idle ? null : player.cycleRepeat,
                          semanticLabel: idle
                              ? null
                              : switch (player.repeat) {
                                  LoopMode.off => 'Repeat off',
                                  LoopMode.all => 'Repeat all',
                                  LoopMode.one => 'Repeat one',
                                },
                        )),
                    Positioned(
                      left: volX - 22 - 6,
                      top: ty - 15,
                      child: PlainIcon(
                        glyph: player.muted ? AgGlyph.mute : AgGlyph.volume,
                        color: c.ink2,
                        size: 30,
                        iconSize: 18,
                        onTap: idle ? null : player.toggleMute,
                        semanticLabel:
                            idle ? null : (player.muted ? 'Unmute' : 'Mute'),
                      ),
                    ),
                    Positioned(
                      left: volX,
                      top: ty - 10,
                      width: Dp.volW,
                      height: 20,
                      child: VolumeLine(
                        value: idle || player.muted ? 0 : player.volume / 100,
                        enabled: !idle,
                        onChanged: (v) => player.setVolume(v * 100),
                      ),
                    ),
                    Positioned(
                      left: PlayerGeo.timeX,
                      width: timeW + 2,
                      top: PlayerGeo.seekY - 8,
                      height: 16,
                      child: _TimeText(
                          player: player, idle: idle, position: true),
                    ),
                    Positioned(
                      left: seekX,
                      right: seekX,
                      top: PlayerGeo.seekY - SeekLine.zone / 2,
                      height: SeekLine.zone,
                      child: SeekLine(
                        player: player,
                        enabled: !idle,
                        marksMs: marks,
                        fallbackMs: track?.durationMs ?? 0,
                        tipLift: PlayerGeo.seekY - SeekLine.zone / 2,
                      ),
                    ),
                    Positioned(
                      right: PlayerGeo.timeX,
                      width: timeW + 2,
                      top: PlayerGeo.seekY - 8,
                      height: 16,
                      child: _TimeText(
                          player: player, idle: idle, position: false),
                    ),
                  ],
            );
          },
        ),
      ),
    );
  }

  static const _btn = 30.0;
}

class _CoverToggle extends StatelessWidget {
  const _CoverToggle({required this.track, required this.on});

  final Track track;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    return Interactive(
      onTap: app.focus.toggle,
      semanticLabel: on ? 'Exit focus mode' : 'Focus mode',
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.rCover,
        child: Container(
          key: const ValueKey('capsule-cover'),
          foregroundDecoration: on
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(Dp.rCover),
                  border: Border.all(color: c.coverRim, width: 1.5),
                )
              : null,
          child: ArtImage(
              url: track.artworkUrl,
              size: Dp.playerCover,
              radius: Dp.rCover,
              artSize: ArtSize.t300),
        ),
      ),
    );
  }
}

class PanelButton extends StatelessWidget {
  const PanelButton({super.key, required this.open, required this.onTap});

  static const label = 'Track panel';

  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      tooltip: onTap == null ? null : label,
      semanticLabel: onTap == null ? null : (open ? 'Hide track panel' : 'Show track panel'),
      builder: (context, s) {
        final col = onTap == null
            ? c.disabled
            : open || s.hovered
                ? c.ink
                : c.offIcon;
        return FocusRing(
          show: s.focused,
          radius: Dp.rIconBtn,
          child: SizedBox.square(
            key: const ValueKey('panel-button'),
            dimension: PlayerGeo.panelBtn,
            child: Center(child: AgIcon(AgGlyph.panel, color: col, size: 20)),
          ),
        );
      },
    );
  }
}

List<int> commentTimes(AppServices app, Track track) {
  final list = app.details.of(track).comments;
  if (list == null) return const [];
  return [
    for (final c in list)
      if (c.atMs != null) c.atMs!,
  ];
}

class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.glyph,
    required this.on,
    required this.onTap,
    this.one = false,
    this.semanticLabel,
  });

  final AgGlyph glyph;
  final bool on;
  final bool one;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const size = 30.0;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, s) {
        final col = onTap == null
            ? c.disabled
            : on || s.hovered
                ? c.ink
                : c.offIcon;
        return FocusRing(
          show: s.focused,
          radius: Dp.rIconBtn,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: AgIcon(glyph, color: col, size: Dp.transportIcon)),
                if (one)
                  Positioned(
                    left: size / 2 + Dp.transportIcon / 2 - 1 - 4,
                    top: 5,
                    width: 8,
                    child: Text('1',
                        textAlign: TextAlign.center,
                        style: AgType.ui(9, col, weight: 700).copyWith(height: 1)),
                  ),
                if (on && onTap != null)
                  Positioned(
                    left: size / 2 - 2,
                    top: size / 2 + 14,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final track = this.track;
    if (track == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: 18,
          child: Text('Nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AgType.ui(13, c.disabled, weight: 600)),
        ),
      );
    }
    final liked = app.library.isLiked(track);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            children: [
              Flexible(
                child: Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgType.ui(13, c.ink, weight: 600)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                height: 16,
                child: HeartButton(
                  liked: liked,
                  size: 16,
                  glyphSize: 22,
                  onTap: () => app.library.toggleLike(track),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 18,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgType.ui(12, c.artist)),
          ),
        ),
      ],
    );
  }
}

class PlainIcon extends StatelessWidget {
  const PlainIcon({
    super.key,
    required this.glyph,
    required this.color,
    required this.onTap,
    this.size = 30,
    this.iconSize = Dp.transportIcon,
    this.semanticLabel,
  });

  final AgGlyph glyph;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.rIconBtn,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AgIcon(glyph,
                color: onTap == null
                    ? c.disabled
                    : s.pressed
                        ? c.ink2
                        : s.hovered
                            ? c.ink
                            : color,
                size: iconSize),
          ),
        ),
      ),
    );
  }
}

class PlayDrop extends StatelessWidget {
  const PlayDrop({super.key, required this.playing, this.onTap});

  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final enabled = onTap != null;
    return Interactive(
      onTap: onTap,
      semanticLabel: enabled ? (playing ? 'Pause' : 'Play') : null,
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.playBtn / 2,
        child: RepaintBoundary(
          child: CustomPaint(
            size: const Size.square(Dp.playBtn),
            painter: PlayDropPainter(
              colors: c,
              playing: playing,
              strength: enabled ? 1.0 : 0.45,
              shade: s.pressed
                  ? -1
                  : s.hovered
                      ? 1
                      : 0,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayDropPainter extends CustomPainter {
  PlayDropPainter({
    required this.colors,
    required this.playing,
    this.strength = 1,
    this.shade = 0,
  });

  final AgColors colors;
  final bool playing;

  final double strength;

  final int shade;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final d = size.width;
    final rect = Offset.zero & size;
    Color a(Color col) => col.withValues(alpha: col.a * strength);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [a(c.dropTop), a(c.dropMid), a(c.dropBottom)],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
    if (shade != 0) {
      canvas.drawOval(
          rect,
          Paint()
            ..color = (shade > 0 ? Colors.white : Colors.black)
                .withValues(alpha: 0.08 * strength));
    }
    canvas.drawOval(
      Rect.fromLTRB(d * 0.16, d * 0.10, d * 0.58, d * 0.40),
      Paint()..color = a(c.dropHighlight),
    );
    canvas.drawOval(
      rect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = a(c.dropRim),
    );
    final glyph = Paint()..color = a(c.dropGlyph);
    final s = d * 0.95;
    final cx = d / 2, cy = d / 2;
    if (playing) {
      final bw = s * 0.14, gap = s * 0.12, h = s * 0.42;
      for (final x in [cx - gap / 2 - bw, cx + gap / 2]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, cy - h / 2, bw, h), Radius.circular(bw * 0.3)),
            glyph);
      }
    } else {
      final h = s * 0.42, w = h * 0.9;
      final x0 = cx - w * 0.38;
      final path = Path()
        ..moveTo(x0, cy - h / 2)
        ..lineTo(x0 + w, cy)
        ..lineTo(x0, cy + h / 2)
        ..close();
      canvas.drawPath(
          path,
          glyph
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = glyph.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(PlayDropPainter old) =>
      old.playing != playing ||
      old.strength != strength ||
      old.shade != shade ||
      old.colors != colors;
}

class SeekLine extends StatefulWidget {
  const SeekLine({
    super.key,
    required this.player,
    required this.enabled,
    this.marksMs = const [],
    this.fallbackMs = 0,
    this.tipLift = 0,
  });

  final PlayerController player;
  final bool enabled;

  final List<int> marksMs;

  final int fallbackMs;

  final double tipLift;

  static const zone = 14.0;

  static const mergeDp = 8.0;

  @override
  State<SeekLine> createState() => _SeekLineState();
}

class _SeekLineState extends State<SeekLine> {
  bool _hover = false;
  double? _hoverX;
  double? _drag;

  List<MarkGroup> _groups = const [];
  List<int>? _groupsTimes;
  double _groupsW = -1;
  int _groupsTotal = -1;

  List<MarkGroup> _groupsFor(double w, int total) {
    if (!identical(_groupsTimes, widget.marksMs) ||
        w != _groupsW ||
        total != _groupsTotal) {
      _groupsTimes = widget.marksMs;
      _groupsW = w;
      _groupsTotal = total;
      _groups = clusterMarks(widget.marksMs, total, w,
          merge: SeekLine.mergeDp, maxGroups: 1 << 20);
    }
    return _groups;
  }

  MarkGroup? _hit(List<MarkGroup> groups, double? x) {
    if (x == null) return null;
    MarkGroup? best;
    var bestD = 6.0;
    for (final g in groups) {
      final d = (g.x - x).abs();
      if (d <= bestD) {
        best = g;
        bestD = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final p = widget.player;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double frac(double x) => (x / w).clamp(0.0, 1.0);
      void seek(double f) => p.seek(
          Duration(milliseconds: (p.duration.value.inMilliseconds * f).round()));
      final active = widget.enabled && (_hover || _drag != null);
      return MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (e) => setState(() {
          _hover = true;
          _hoverX = e.localPosition.dx;
        }),
        onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
        onExit: (_) => setState(() {
          _hover = false;
          _hoverX = null;
        }),
        child: ValueListenableBuilder<Duration>(
          valueListenable: p.duration,
          builder: (context, dur, _) {
            final d = dur.inMilliseconds;
            final total = d > 0 ? d : widget.fallbackMs;
            final groups =
                widget.enabled ? _groupsFor(w, total) : const <MarkGroup>[];
            final mark = _drag == null && _hover ? _hit(groups, _hoverX) : null;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.enabled
                  ? (e) {
                      final m = _hit(groups, e.localPosition.dx);
                      if (m != null) {
                        p.seek(Duration(milliseconds: widget.marksMs[m.first]));
                      } else {
                        seek(frac(e.localPosition.dx));
                      }
                    }
                  : null,
              onHorizontalDragStart: widget.enabled
                  ? (e) => setState(() => _drag = frac(e.localPosition.dx))
                  : null,
              onHorizontalDragUpdate: widget.enabled
                  ? (e) => setState(() => _drag = frac(e.localPosition.dx))
                  : null,
              onHorizontalDragEnd: widget.enabled
                  ? (_) {
                      final f = _drag;
                      setState(() => _drag = null);
                      if (f != null) seek(f);
                    }
                  : null,
              child: ValueListenableBuilder<Duration>(
                valueListenable: p.position,
                builder: (context, pos, _) {
                  final f = (_drag ?? (d <= 0 ? 0.0 : pos.inMilliseconds / d))
                      .clamp(0.0, 1.0);
                  final tipF = _drag ?? (_hoverX == null ? f : frac(_hoverX!));
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: SeekPainter(
                            fraction: widget.enabled ? f : 0,
                            hover: active,
                            rest: c.barRest,
                            played: c.barPlayed,
                            knob: c.ink,
                            band: c.hitZone,
                            marks: [for (final g in groups) g.x],
                            markColor: c.ink2,
                          ),
                        ),
                      ),
                      if (active && mark == null)
                        Positioned(
                          left: (tipF * w - 30).clamp(-12.0, w - 48),
                          width: 60,
                          bottom: SeekLine.zone / 2 + 8,
                          child: IgnorePointer(
                            child: Center(
                                child: SeekTip(ms: (d * tipF).round())),
                          ),
                        ),
                      if (mark != null)
                        Positioned(
                          left: mark.x - 60,
                          width: 120,
                          bottom: SeekLine.zone + widget.tipLift + 4,
                          child: IgnorePointer(
                            child: Center(
                              child: CountTip(
                                  text: mark.count == 1
                                      ? '1 comment'
                                      : '${mark.count} comments'),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      );
    });
  }
}

class CountTip extends StatelessWidget {
  const CountTip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return CustomPaint(
      painter: _CaretPainter(fill: c.menuFill, rim: c.rim),
      child: Container(
        height: 21,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.menuFill,
          border: Border.all(color: c.rim),
          borderRadius: BorderRadius.circular(Dp.rTooltip),
          boxShadow: c.menuShadows,
        ),
        child: Text(text,
            maxLines: 1, style: AgType.ui(11, c.ink, weight: 550)),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter({required this.fill, required this.rim});

  final Color fill, rim;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final path = Path()
      ..moveTo(cx - 5, size.height - 1)
      ..lineTo(cx + 5, size.height - 1)
      ..lineTo(cx, size.height + 4)
      ..close();
    canvas.drawPath(path, Paint()..color = Color.alphaBlend(fill, rim));
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.fill != fill || old.rim != rim;
}

class SeekTip extends StatelessWidget {
  const SeekTip({super.key, required this.ms});

  final int ms;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.tipFill,
        border: Border.all(color: c.rim),
        borderRadius: BorderRadius.circular(Dp.rTooltip),
      ),
      child: Text(formatMs(ms), style: AgType.ui(11, c.ink, weight: 600)),
    );
  }
}

class SeekPainter extends CustomPainter {
  SeekPainter({
    required this.fraction,
    required this.hover,
    required this.rest,
    required this.played,
    required this.knob,
    required this.band,
    this.marks = const [],
    this.markColor = const Color(0x00000000),
  });

  final double fraction;
  final bool hover;
  final Color rest, played, knob, band;

  final List<double> marks;
  final Color markColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    if (hover) {
      canvas.drawRRect(
          RRect.fromLTRBR(0, cy - Dp.seekHit / 2, size.width, cy + Dp.seekHit / 2,
              const Radius.circular(4)),
          Paint()..color = band);
    }
    final t = hover ? Dp.seekHover : Dp.seek;
    final r = Radius.circular(t / 2);
    canvas.drawRRect(
        RRect.fromLTRBR(0, cy - t / 2, size.width, cy + t / 2, r),
        Paint()..color = rest);
    final x = size.width * fraction;
    if (x > 0) {
      canvas.drawRRect(
          RRect.fromLTRBR(0, cy - t / 2, x, cy + t / 2, r), Paint()..color = played);
    }
    if (marks.isNotEmpty) {
      final mp = Paint()..color = markColor;
      for (final mx in marks) {
        canvas.drawCircle(Offset(mx, cy), 3, mp);
      }
    }
    if (hover) {
      canvas.drawCircle(Offset(x, cy), Dp.seekThumb / 2, Paint()..color = knob);
    }
  }

  @override
  bool shouldRepaint(SeekPainter old) =>
      old.fraction != fraction ||
      old.hover != hover ||
      old.rest != rest ||
      old.played != played ||
      old.knob != knob ||
      old.band != band ||
      old.markColor != markColor ||
      !listEquals(old.marks, marks);
}

class _TimeText extends StatelessWidget {
  const _TimeText(
      {required this.player, required this.idle, required this.position});

  final PlayerController player;
  final bool idle;
  final bool position;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final align = position ? Alignment.centerLeft : Alignment.centerRight;
    Widget text(String t, Color col) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align,
          child: Text(t, maxLines: 1, softWrap: false, style: AgType.tnum(11, col)),
        );
    if (idle) return Align(alignment: align, child: text('0:00', c.disabled));
    return Align(
      alignment: align,
      child: ValueListenableBuilder<Duration>(
        valueListenable: position ? player.position : player.duration,
        builder: (context, d, _) => text(formatDuration(d), c.ink2),
      ),
    );
  }
}

class VolumeLine extends StatelessWidget {
  const VolumeLine({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      void set(double dx) => onChanged((dx / w).clamp(0.0, 1.0));
      return MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: enabled ? (d) => set(d.localPosition.dx) : null,
          onHorizontalDragUpdate: enabled ? (d) => set(d.localPosition.dx) : null,
          child: CustomPaint(
            size: Size(w, box.maxHeight),
            painter: SeekPainter(
              fraction: value,
              hover: false,
              rest: c.barRest,
              played: enabled ? c.barPlayed : c.disabled,
              knob: c.ink,
              band: c.hitZone,
            ),
          ),
        ),
      );
    });
  }
}
