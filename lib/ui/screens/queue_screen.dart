import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/ui_state.dart';
import '../../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/page_parts.dart';
import '../widgets/track_row.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @visibleForTesting
  static (int, int, double)? debugDrag;

  static const _npTop = PageHeader.contentTop;
  static const _caption = 22.0;
  static const _cardH = Dp.row + Dp.cardPadY * 2 + 2;
  static const _upNextTop = _npTop + _caption + _cardH + 14;
  static const _listTop = _upNextTop + _caption;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final player = app.player;
    return ListenableBuilder(
      listenable: Listenable.merge([player, app.library]),
      builder: (context, _) {
        final cur = player.current;
        if (cur == null) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(title: 'Queue'),
              Expanded(
                child: EmptyMessage(
                  title: 'Queue is empty',
                  body: 'Play something from Likes or a playlist.',
                ),
              ),
            ],
          );
        }
        final upNext = player.upNext;
        Widget caption(String text) =>
            Text(text, style: AgType.ui(12, c.muted, weight: 600));
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: PageHeader(
                title: 'Queue',
                count: upNext.isEmpty ? null : '${upNext.length}',
                trailing: GlassChip(
                  label: 'Clear',
                  onTap: upNext.isEmpty
                      ? null
                      : () {
                          final removed = player.clearUpNext();
                          app.messages.show('Queue cleared',
                              action: 'Undo',
                              onAction: () => player.restoreUpNext(removed));
                        },
                ),
              ),
            ),
            Positioned(
                left: Dp.hPad + 2, top: _npTop, child: caption('Now playing')),
            Positioned(
              left: Dp.hPad,
              right: Dp.hPad,
              top: _npTop + _caption,
              height: _cardH,
              child: _NowPlaying(track: cur),
            ),
            Positioned(
                left: Dp.hPad + 2, top: _upNextTop, child: caption('Up next')),
            Positioned(
              left: Dp.hPad,
              right: Dp.hPad,
              top: _listTop,
              bottom: 20,
              child: upNext.isEmpty
                  ? const EmptyMessage(
                      title: 'Queue is empty',
                      body: 'Up next was cleared.',
                    )
                  : UpNextList(tracks: upNext, debugDrag: debugDrag),
            ),
          ],
        );
      },
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final un = app.library.unavailableOf(track);
    return GroupCard(
      contentHeight: QueueScreen._cardH,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dp.cardPadY),
        child: TrackRow(
          track: track,
          playing: true,
          edge: true,
          liked: app.library.isLiked(track),
          unavailable: un,
          preview: un == null && track.isPreviewOnly,
          showLine: false,
          onTap: () => app.nav.go(TrackRoute(track)),
          onLike: () => app.library.toggleLike(track),
          onContextMenu: (at) => showTrackMenu(context, at, track),
        ),
      ),
    );
  }
}

class UpNextList extends StatefulWidget {
  const UpNextList({super.key, required this.tracks, this.debugDrag});

  final List<Track> tracks;

  final (int, int, double)? debugDrag;

  @override
  State<UpNextList> createState() => _UpNextListState();
}

class _UpNextListState extends State<UpNextList> {
  final _scroll = ScrollController();
  int? _from;
  int _slot = 0;
  double _y = 0;

  @override
  void initState() {
    super.initState();
    final d = widget.debugDrag;
    if (d != null) {
      _from = d.$1;
      _slot = d.$2;
      _y = d.$3;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const _pad = Dp.cardPadY;

  static const _split = 28.0;

  static const _dragGap = _pad + _split + _pad;

  int _slotFor(double y) {
    final n = widget.tracks.length;
    final from = _from ?? 0;
    final c = ((y - _pad + _scroll.positionsOrZero + Dp.row / 2) / Dp.row)
        .floor()
        .clamp(0, n - 1);
    return c <= from ? c : c + 1;
  }

  int get _compactSlot {
    final from = _from ?? 0;
    return _slot > from ? _slot - 1 : _slot;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final tracks = widget.tracks;
    final from = _from;
    final n = tracks.length;

    Widget handleFor(int i) => MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) {
              final box = context.findRenderObject() as RenderBox;
              final local = box.globalToLocal(d.globalPosition);
              setState(() {
                _from = i;
                _y = local.dy - Dp.row / 2 - _pad;
                _slot = i;
              });
            },
            onVerticalDragUpdate: (d) {
              final box = context.findRenderObject() as RenderBox;
              final local = box.globalToLocal(d.globalPosition);
              setState(() {
                _y = local.dy - Dp.row / 2 - _pad;
                _slot = _slotFor(local.dy - Dp.row / 2);
              });
            },
            onVerticalDragEnd: (_) {
              final f = _from;
              final to = _slot;
              setState(() => _from = null);
              if (f != null && to != f && to != f + 1) {
                app.player.moveUpNext(f, to);
              }
            },
            onVerticalDragCancel: () => setState(() => _from = null),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AgIcon(AgGlyph.grip, color: c.muted, size: 16),
            ),
          ),
        );

    Widget row(int i, {bool lifted = false}) {
      final t = tracks[i];
      var last = n - 1;
      if (from != null) last = from == n - 1 ? n - 2 : n - 1;
      final beforeSplit = from != null && _compactSlot > 0 &&
          (i > from ? i - 1 : i) == _compactSlot - 1;
      return TrackRow(
        track: t,
        liked: app.library.isLiked(t),
        preview: t.isPreviewOnly,
        showLine: !lifted && i < last && !beforeSplit,
        edge: lifted || i == 0 || i == last,
        handle: handleFor(i),
        onTap: () => app.player.playAt(app.player.queue.index + 1 + i),
        onLike: () => app.library.toggleLike(t),
        onContextMenu: (at) => showTrackMenu(context, at, t),
      );
    }

    final rows = from == null ? n : n - 1;
    final content = rows * Dp.row + _pad * 2 + 2 + (from == null ? 0 : _dragGap);
    return LayoutBuilder(builder: (context, box) {
      final h = content < box.maxHeight ? content : box.maxHeight;
      final overflow = content > box.maxHeight;
      final splitAt = from == null
          ? null
          : _pad + 1 + _compactSlot * Dp.row - _scroll.positionsOrZero;
      return SizedBox(
        height: box.maxHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: h,
              child: CustomPaint(
                painter: _SplitCardPainter(
                  fill: c.cardGlass,
                  rim: c.rim,
                  splitAt: splitAt == null ? null : splitAt + _pad,
                  split: _split,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Dp.rCard - 1),
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: _maybeFade(overflow, ListView.builder(
                      controller: _scroll,
                      itemExtent: Dp.row,
                      itemCount: n,
                      padding: EdgeInsets.only(
                          top: _pad, bottom: _pad + (overflow ? Dp.fadeH : 0)),
                      itemBuilder: (context, i) {
                        var dy = 0.0;
                        if (from != null) {
                          final ci = i > from ? i - 1 : i;
                          dy = (ci - i) * Dp.row +
                              (ci >= _compactSlot ? _dragGap : 0);
                        }
                        return Transform.translate(
                          offset: Offset(0, dy),
                          // The dragged row stays mounted because it owns the gesture.
                          child: Visibility(
                            visible: from != i,
                            maintainState: true,
                            maintainAnimation: true,
                            maintainSize: true,
                            maintainInteractivity: true,
                            child: row(i),
                          ),
                        );
                      },
                    )),
                  ),
                ),
              ),
            ),
            if (from != null) ...[
              Positioned(
                left: 8,
                right: 8,
                top: splitAt! + _pad + _split / 2 - 1,
                child: Container(height: 2, color: c.ink),
              ),
              Positioned(
                left: 8,
                right: -4,
                top: _y,
                height: Dp.row + _pad * 2 + 2,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: _pad),
                    decoration: BoxDecoration(
                      color: c.pillFill,
                      border: Border.all(color: c.rim),
                      borderRadius: BorderRadius.circular(Dp.rCard),
                      boxShadow: c.liftShadows,
                    ),
                    child: OverflowBox(
                      maxHeight: Dp.row,
                      child: row(from, lifted: true),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _SplitCardPainter extends CustomPainter {
  _SplitCardPainter({
    required this.fill,
    required this.rim,
    required this.splitAt,
    required this.split,
  });

  final Color fill, rim;
  final double? splitAt;
  final double split;

  @override
  void paint(Canvas canvas, Size size) {
    final f = Paint()..color = fill;
    final r = Paint()
      ..color = rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void card(double top, double bottom) {
      if (bottom - top < 2) return;
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTRB(0.5, top + 0.5, size.width - 0.5, bottom - 0.5),
          Radius.circular(
              ((bottom - top) / 2).clamp(0.0, Dp.rCard).toDouble()));
      canvas.drawRRect(rr, f);
      canvas.drawRRect(rr, r);
    }

    final s = splitAt;
    if (s == null) {
      card(0, size.height);
    } else {
      if (s > Dp.cardPadY * 2) card(0, s);
      card(s + split, size.height);
    }
  }

  @override
  bool shouldRepaint(_SplitCardPainter old) =>
      old.fill != fill || old.rim != rim || old.splitAt != splitAt;
}

Widget _maybeFade(bool on, Widget child) =>
    on ? BottomFade(child: child) : child;

extension on ScrollController {
  double get positionsOrZero => hasClients ? offset : 0;
}
