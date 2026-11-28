import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

enum AgGlyph {
  minimize,
  maximize,
  restore,
  close,
  search,
  heart,
  heartOutline,
  play,
  pause,
  prev,
  next,
  shuffle,
  repeat,
  repeatOne,
  volume,
  mute,
  list,
  queue,
  sort,
  cloud,
  grip,
  show,
  refresh,
  more,
  logout,
  sun,
  moon,
  check,
  chevron,
  note,
  jump,
}

class AgIcon extends StatelessWidget {
  const AgIcon(this.glyph, {super.key, required this.color, this.size = 24});

  final AgGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: AgIconPainter(glyph, color),
        ),
      );
}

class AgIconPainter extends CustomPainter {
  AgIconPainter(this.glyph, this.color);

  final AgGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    Paint stroke(double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..isAntiAlias = true;
    Offset p(double x, double y) => Offset(s * x, s * y);
    void line(double x0, double y0, double x1, double y1, double w) =>
        canvas.drawLine(p(x0, y0), p(x1, y1), stroke(w));
    void poly(List<Offset> pts) =>
        canvas.drawPath(Path()..addPolygon(pts, true), fill);

    switch (glyph) {
      case AgGlyph.minimize:
        line(0.22, 0.52, 0.78, 0.52, 1.2);
      case AgGlyph.maximize:
        canvas.drawRect(Rect.fromLTRB(s * .26, s * .26, s * .74, s * .74), stroke(1.2));
      case AgGlyph.restore:
        canvas.drawRect(Rect.fromLTRB(s * .26, s * .34, s * .66, s * .74), stroke(1.2));
        canvas.drawPath(
            Path()
              ..moveTo(s * .34, s * .34)
              ..lineTo(s * .34, s * .26)
              ..lineTo(s * .74, s * .26)
              ..lineTo(s * .74, s * .66)
              ..lineTo(s * .66, s * .66),
            stroke(1.2));
      case AgGlyph.close:
        line(0.30, 0.30, 0.70, 0.70, 1.2);
        line(0.70, 0.30, 0.30, 0.70, 1.2);
      case AgGlyph.search:
        canvas.drawOval(Rect.fromLTRB(s * .18, s * .18, s * .62, s * .62), stroke(1.3));
        line(0.58, 0.58, 0.78, 0.78, 1.3);
      case AgGlyph.heart:
      case AgGlyph.heartOutline:
        _heart(canvas, s, fill, stroke(1.3), glyph == AgGlyph.heart);
      case AgGlyph.play:
        poly([p(.36, .24), p(.36, .76), p(.76, .50)]);
      case AgGlyph.pause:
        final w = s * 0.14;
        canvas.drawRRect(
            RRect.fromLTRBR(s * .28, s * .24, s * .28 + w, s * .76, const Radius.circular(1)),
            fill);
        canvas.drawRRect(
            RRect.fromLTRBR(s * .58, s * .24, s * .58 + w, s * .76, const Radius.circular(1)),
            fill);
      case AgGlyph.prev:
        poly([p(.66, .26), p(.66, .74), p(.32, .50)]);
        canvas.drawRect(Rect.fromLTRB(s * .24, s * .26, s * .32, s * .74), fill);
      case AgGlyph.next:
        poly([p(.34, .26), p(.34, .74), p(.68, .50)]);
        canvas.drawRect(Rect.fromLTRB(s * .68, s * .26, s * .76, s * .74), fill);
      case AgGlyph.shuffle:
        line(.18, .32, .42, .32, 1.3);
        line(.58, .32, .78, .32, 1.3);
        line(.42, .32, .58, .68, 1.3);
        line(.18, .68, .42, .68, 1.3);
        line(.58, .68, .78, .68, 1.3);
        poly([p(.78, .32), p(.66, .24), p(.66, .40)]);
        poly([p(.78, .68), p(.66, .60), p(.66, .76)]);
      case AgGlyph.repeat:
      case AgGlyph.repeatOne:
        canvas.drawOval(Rect.fromLTRB(s * .22, s * .28, s * .78, s * .72), stroke(1.3));
        poly([p(.70, .22), p(.86, .22), p(.78, .36)]);
        poly([p(.30, .78), p(.14, .78), p(.22, .64)]);
        if (glyph == AgGlyph.repeatOne) {
          final tp = TextPainter(
            text: TextSpan(
              text: '1',
              style: AgType.ui(8, color, weight: 700).copyWith(height: 1),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, p(.50, .54) - Offset(tp.width / 2, tp.height / 2));
        }
      case AgGlyph.volume:
      case AgGlyph.mute:
        poly([p(.22, .38), p(.38, .38), p(.54, .24), p(.54, .76), p(.38, .62), p(.22, .62)]);
        _arc(canvas, Rect.fromLTRB(s * .42, s * .30, s * .78, s * .70), stroke(1.2));
        _arc(canvas, Rect.fromLTRB(s * .50, s * .22, s * .90, s * .78), stroke(1.2));
        if (glyph == AgGlyph.mute) line(.18, .80, .82, .20, 1.4);
      case AgGlyph.list:
        for (final yy in const [.26, .50, .74]) {
          canvas.drawRRect(
              RRect.fromLTRBR(s * .18, s * (yy - .05), s * .32, s * (yy + .05),
                  const Radius.circular(1)),
              fill);
          line(.42, yy, .82, yy, 1.3);
        }
      case AgGlyph.queue:
        for (var i = 0; i < 3; i++) {
          final yy = .26 + i * .22;
          line(.22, yy, .78, yy, 1.3);
        }
      case AgGlyph.sort:
        poly([p(.50, .70), p(.28, .40), p(.72, .40)]);
      case AgGlyph.cloud:
        canvas.drawOval(Rect.fromLTRB(s * .12, s * .38, s * .52, s * .78), fill);
        canvas.drawOval(Rect.fromLTRB(s * .32, s * .22, s * .72, s * .64), fill);
        canvas.drawOval(Rect.fromLTRB(s * .52, s * .40, s * .88, s * .80), fill);
        canvas.drawRRect(
            RRect.fromLTRBR(s * .18, s * .52, s * .82, s * .80, const Radius.circular(2)),
            fill);
      case AgGlyph.grip:
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 2; j++) {
            canvas.drawCircle(p(.32 + j * .36, .22 + i * .28), 1.15, fill);
          }
        }
      case AgGlyph.show:
        canvas.drawRect(Rect.fromLTRB(s * .26, s * .26, s * .74, s * .74), stroke(1.2));
        canvas.drawRect(Rect.fromLTRB(s * .26, s * .26, s * .74, s * .42), fill);
      case AgGlyph.refresh:
        const deg = math.pi / 180;
        canvas.drawArc(
            Rect.fromCenter(center: p(.50, .50), width: s * .56, height: s * .56),
            55 * deg,
            250 * deg,
            false,
            stroke(1.3));
        poly([p(.74, .18), p(.86, .34), p(.62, .34)]);
      case AgGlyph.more:
        for (final dx in const [.28, .50, .72]) {
          canvas.drawCircle(p(dx, .50), s * .06, fill);
        }
      case AgGlyph.logout:
        canvas.drawRRect(
            RRect.fromLTRBR(s * .22, s * .22, s * .58, s * .78, const Radius.circular(1.5)),
            stroke(1.3));
        line(.48, .50, .82, .50, 1.3);
        line(.70, .38, .82, .50, 1.3);
        line(.70, .62, .82, .50, 1.3);
      case AgGlyph.sun:
        final r = s * .16;
        canvas.drawCircle(p(.5, .5), r, stroke(1.3));
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(p(.5, .5) + d * (r * 1.6), p(.5, .5) + d * (r * 2.2), stroke(1.2));
        }
      case AgGlyph.moon:
        final r = s * .22;
        canvas.drawCircle(p(.5, .5), r, stroke(1.3));
        canvas.drawOval(
            Rect.fromLTRB(s * .5 - r * .05, s * .5 - r * .75, s * .5 + r * 1.05, s * .5 + r * .45),
            stroke(1.2));
      case AgGlyph.check:
        line(.22, .52, .42, .72, 1.6);
        line(.42, .72, .80, .28, 1.6);
      case AgGlyph.chevron:
        line(.38, .30, .62, .50, 1.3);
        line(.38, .70, .62, .50, 1.3);
      case AgGlyph.note:
        canvas.drawOval(Rect.fromLTRB(s * .24, s * .62, s * .48, s * .80), fill);
        canvas.drawRect(Rect.fromLTRB(s * .42, s * .22, s * .48, s * .71), fill);
        canvas.drawPath(
            Path()
              ..moveTo(s * .42, s * .22)
              ..lineTo(s * .74, s * .30)
              ..lineTo(s * .74, s * .42)
              ..lineTo(s * .48, s * .35)
              ..close(),
            fill);
      case AgGlyph.jump:
        _jump(canvas, s, stroke);
    }
  }

  void _jump(Canvas canvas, double s, Paint Function(double) stroke) {
    Offset p(double x, double y) => Offset(s * x, s * y);
    canvas.drawLine(p(.50, .20), p(.50, .62), stroke(1.4));
    canvas.drawPath(
        Path()
          ..moveTo(s * .34, s * .47)
          ..lineTo(s * .50, s * .63)
          ..lineTo(s * .66, s * .47),
        stroke(1.4)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(p(.26, .78), p(.74, .78), stroke(1.4)..strokeCap = StrokeCap.round);
  }

  void _arc(Canvas canvas, Rect r, Paint paint) {
    const deg = math.pi / 180;
    canvas.drawArc(r, -50 * deg, 100 * deg, false, paint);
  }

  void _heart(Canvas canvas, double s, Paint fill, Paint stroke, bool filled) {
    final pts = [
      Offset(s * .50, s * .82),
      Offset(s * .14, s * .46),
      Offset(s * .14, s * .34),
      Offset(s * .26, s * .20),
      Offset(s * .40, s * .20),
      Offset(s * .50, s * .32),
      Offset(s * .60, s * .20),
      Offset(s * .74, s * .20),
      Offset(s * .86, s * .34),
      Offset(s * .86, s * .46),
    ];
    if (filled) {
      canvas.drawPath(Path()..addPolygon(pts, true), fill);
      canvas.drawOval(Rect.fromLTRB(s * .16, s * .20, s * .52, s * .54), fill);
      canvas.drawOval(Rect.fromLTRB(s * .48, s * .20, s * .84, s * .54), fill);
    } else {
      canvas.drawPath(
          Path()..addPolygon(pts, true), stroke..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(AgIconPainter old) =>
      old.glyph != glyph || old.color != color;
}
