import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/marks.dart';
import '../theme/tokens.dart';

class ProgressLine extends StatefulWidget {
  const ProgressLine({
    super.key,
    required this.position,
    required this.duration,
    this.thickness = 3,
    this.onSeek,
    this.enabled = true,
    this.height = 20,
    this.thumb = 4,
  });

  final ValueListenable<Duration>? position;
  final ValueListenable<Duration> duration;
  final double thickness;
  final ValueChanged<Duration>? onSeek;
  final bool enabled;
  final double height;

  final double thumb;

  @override
  State<ProgressLine> createState() => _ProgressLineState();
}

class _ProgressLineState extends State<ProgressLine> {
  double? _drag;

  void _seekTo(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    final d = widget.duration.value;
    widget.onSeek?.call(Duration(milliseconds: (d.inMilliseconds * f).round()));
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final pos = widget.position;
    final canSeek = widget.enabled && widget.onSeek != null && pos != null;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      Widget paint(double? f) => CustomPaint(
            size: Size(w, widget.height),
            painter: _LinePainter(
              fraction: f,
              rest: c.barRest,
              played: c.barPlayed,
              knob: c.ink,
              thickness: widget.thickness,
              thumb: widget.thumb,
            ),
          );
      Widget line = pos == null || !widget.enabled
          ? paint(null)
          : AnimatedBuilder(
              animation: Listenable.merge([pos, widget.duration]),
              builder: (context, _) {
                if (_drag != null) return paint(_drag);
                final d = widget.duration.value.inMilliseconds;
                final f = d <= 0 ? 0.0 : pos.value.inMilliseconds / d;
                return paint(f.clamp(0.0, 1.0));
              },
            );
      if (!canSeek) return line;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _seekTo(d.localPosition.dx, w),
          onHorizontalDragStart: (d) =>
              setState(() => _drag = (d.localPosition.dx / w).clamp(0.0, 1.0)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = (d.localPosition.dx / w).clamp(0.0, 1.0)),
          onHorizontalDragEnd: (_) {
            final f = _drag;
            setState(() => _drag = null);
            if (f != null) _seekTo(f * w, w);
          },
          child: line,
        ),
      );
    });
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.fraction,
    required this.rest,
    required this.played,
    required this.knob,
    required this.thickness,
    required this.thumb,
  });

  final double? fraction;
  final Color rest, played, knob;
  final double thickness, thumb;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final r = Radius.circular(thickness / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(0, mid - thickness / 2, size.width, mid + thickness / 2, r),
      Paint()..color = rest,
    );
    final f = fraction;
    if (f == null) return;
    final x = size.width * f;
    canvas.drawRRect(
      RRect.fromLTRBR(0, mid - thickness / 2, x, mid + thickness / 2, r),
      Paint()..color = played,
    );
    if (thumb > 0) canvas.drawCircle(Offset(x, mid), thumb, Paint()..color = knob);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.fraction != fraction ||
      old.rest != rest ||
      old.played != played ||
      old.thickness != thickness;
}

class CommentMarks extends StatefulWidget {
  const CommentMarks({
    super.key,
    required this.timesMs,
    required this.totalMs,
    this.onGroupTap,
    this.height = 20,
  });

  final List<int> timesMs;
  final int totalMs;
  final ValueChanged<int>? onGroupTap;
  final double height;

  @override
  State<CommentMarks> createState() => _CommentMarksState();
}

class _CommentMarksState extends State<CommentMarks> {
  double _width = -1;
  List<MarkGroup> _groups = const [];
  List<int>? _times;

  List<MarkGroup> _groupsFor(double w) {
    if (w != _width || !identical(_times, widget.timesMs)) {
      _width = w;
      _times = widget.timesMs;
      _groups = clusterMarks(widget.timesMs, widget.totalMs, w);
    }
    return _groups;
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final groups = _groupsFor(box.maxWidth);
      final mid = widget.height / 2;
      return SizedBox(
        width: box.maxWidth,
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final g in groups)
              Positioned(
                left: g.x - (g.count > 1 ? 7 : 3.5),
                top: mid - (g.count > 1 ? 7 : 3.5),
                child: _Mark(
                  group: g,
                  colors: c,
                  onTap: widget.onGroupTap == null
                      ? null
                      : () => widget.onGroupTap!(g.first),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.group, required this.colors, this.onTap});

  final MarkGroup group;
  final AgColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final big = group.count > 1;
    final d = big ? 14.0 : 7.0;
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.markFill,
            shape: BoxShape.circle,
            border: Border.all(color: colors.ink2, width: 1),
          ),
          child: big
              ? Text('${group.count}',
                  style: AgType.ui(9, colors.ink, weight: 700).copyWith(height: 1))
              : null,
        ),
      ),
    );
  }
}
