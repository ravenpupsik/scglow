import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app/app_services.dart';
import '../app/track_details.dart';
import '../app/ui_state.dart';
import '../core/models.dart';
import 'format.dart';
import 'theme/tokens.dart';
import 'widgets/art_image.dart';
import 'widgets/icons.dart';
import 'widgets/interactive.dart';
import 'widgets/page_parts.dart';

class PanelGeo {
  const PanelGeo(this.size, this.t, {this.maxColumn = Dp.column});

  final Size size;
  final double t;
  final double maxColumn;

  double get w => size.width;
  bool get wide => w > Dp.panelBreakpoint;
  bool get overlay => !wide;

  double get playerY => size.height - Dp.playerBottom - Dp.playerH;
  double get panelTop => Dp.panelTop;
  double get panelBottom => playerY - 16;

  double get _closedInner => math.min(maxColumn, w - 2 * Dp.hPad);
  double get _openInner => w * Dp.listOpenFrac;

  double get panelWidth => wide
      ? w - Dp.panelPad - (Dp.panelPad + _openInner + Dp.panelGutter)
      : Dp.panelNarrowW;

  double get panelOpenLeft => wide
      ? Dp.panelPad + _openInner + Dp.panelGutter
      : w - 16 - Dp.panelNarrowW;

  double get panelLeft => _lerp(w + 8, panelOpenLeft, t);

  // The list keeps one width for the whole slide (the open width whenever the
  // panel is on screen) and only moves, so it never relayouts per frame.
  double listInner({required bool open}) => wide && open ? _openInner : _closedInner;

  double listRestLeft(double inner) => (w - inner) / 2;

  double listLeft(double inner) =>
      wide ? _lerp(listRestLeft(inner), Dp.panelPad, t) : listRestLeft(inner);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class PanelScope extends InheritedWidget {
  const PanelScope({super.key, required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelScope>()?.animation;

  @override
  bool updateShouldNotify(PanelScope old) => old.animation != animation;
}

class TrackPanelView extends StatefulWidget {
  const TrackPanelView({super.key, required this.narrow});

  final bool narrow;

  @override
  State<TrackPanelView> createState() => _TrackPanelViewState();
}

class _TrackPanelViewState extends State<TrackPanelView> {
  final _focus = FocusNode(debugLabel: 'track panel');
  TrackPanel? _panel;
  Animation<double>? _slide;

  // The tab lists and the overlay blur come in once the slide has finished,
  // so the slide itself only moves an already painted card.
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = AppScope.of(context).panel;
    if (p != _panel) {
      _panel?.focusRequests.removeListener(_takeFocus);
      _panel = p..focusRequests.addListener(_takeFocus);
    }
    final a = PanelScope.of(context);
    if (a != _slide) {
      _slide?.removeStatusListener(_onSlide);
      _slide = a?..addStatusListener(_onSlide);
      if (_slideDone(a?.status)) _ready = true;
    }
  }

  bool _slideDone(AnimationStatus? status) =>
      _slide == null || _slide!.value >= 1 || status == AnimationStatus.completed;

  void _onSlide(AnimationStatus status) {
    if (!_ready && _slideDone(status) && mounted) setState(() => _ready = true);
  }

  void _takeFocus() {
    if (mounted) _focus.requestFocus();
  }

  @override
  void dispose() {
    _panel?.focusRequests.removeListener(_takeFocus);
    _slide?.removeStatusListener(_onSlide);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final narrow = widget.narrow;
    final pad = narrow ? 20.0 : 24.0;
    final body = Container(
        decoration: BoxDecoration(
          color: c.cardGlass,
          borderRadius: BorderRadius.circular(Dp.rPanelSide),
          border: Border.all(color: c.rim),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([app.player, app.panel]),
          builder: (context, _) {
            if (app.player.current == null) return const SizedBox.shrink();
            return LayoutBuilder(builder: (context, box) {
              final inner = box.maxWidth - 2 * pad;
              final cover =
                  math.min(narrow ? 132.0 : 200.0, inner).floorToDouble();
              return Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 16, pad, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(cover: cover, narrow: narrow),
                        _Tabs(
                          tab: app.panel.tab,
                          onSelect: app.panel.select,
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: !_ready
                              ? const SizedBox.shrink(key: ValueKey('panel-list-pending'))
                              : switch (app.panel.tab) {
                                  PanelTab.queue => const _QueueTab(),
                                  PanelTab.related => const _RelatedTab(),
                                  PanelTab.comments => const _CommentsTab(),
                                },
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 12,
                    child: _CloseButton(onTap: app.panel.close),
                  ),
                ],
              );
            });
          },
        ),
      );
    return Focus(
      focusNode: _focus,
      // As an overlay the panel floats over the list, so blur what is behind it.
      // The blur is switched on only once the panel rests: blurring a moving
      // backdrop would redo the blur every frame of the slide.
      child: narrow
          ? ClipRRect(
              borderRadius: BorderRadius.circular(Dp.rPanelSide),
              child: BackdropFilter(
                enabled: _ready,
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: body,
              ),
            )
          : body,
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: 'Close',
      builder: (context, s) => FocusRing(
        show: s.focused,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: s.pressed
                ? Color.alphaBlend(c.pressed, c.glassTile)
                : s.hovered
                    ? Color.alphaBlend(c.hover, c.glassTile)
                    : c.glassTile,
            border: Border.all(color: c.rim),
            borderRadius: BorderRadius.circular(Dp.rIconBtn),
          ),
          alignment: Alignment.center,
          child: AgIcon(AgGlyph.close, color: s.hovered ? c.ink : c.ink2, size: 24),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.cover, required this.narrow});

  final double cover;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.player, app.library]),
      builder: (context, _) {
        final track = app.player.current;
        if (track == null) return const SizedBox.shrink();
        return Column(
          key: ValueKey(track.id),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ArtImage(
                url: track.artworkUrl,
                size: cover,
                radius: 12,
                artSize: ArtSize.t500,
              ),
            ),
            const SizedBox(height: 14),
            _TitleBlock(track: track, narrow: narrow),
          ],
        );
      },
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.track, required this.narrow});

  final Track track;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final liked = app.library.isLiked(track);
    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 26,
                  child: Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgType.ui(narrow ? 20 : 22, c.ink, weight: 600)),
                ),
                Text(track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgType.ui(narrow ? 13 : 14, c.artist)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: LikedPill(
              liked: liked,
              onTap: () => app.library.toggleLike(track),
            ),
          ),
        ],
      ),
    );
  }
}

class LikedPill extends StatelessWidget {
  const LikedPill({super.key, required this.liked, required this.onTap});

  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      semanticLabel: liked ? 'Remove from Likes' : 'Add to Likes',
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: 14,
        child: Container(
          height: 28,
          padding: const EdgeInsets.only(left: 10, right: 12),
          decoration: BoxDecoration(
            color: liked ? c.likedFill : c.glassTile,
            border: Border.all(color: c.rim),
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundDecoration: s.hovered || s.pressed
              ? BoxDecoration(
                  color: s.pressed ? c.pressed : c.hover,
                  borderRadius: BorderRadius.circular(14))
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: OverflowBox(
                  maxWidth: 22,
                  maxHeight: 22,
                  child: AgIcon(liked ? AgGlyph.heart : AgGlyph.heartOutline,
                      color: liked ? c.ink : c.muted, size: 22),
                ),
              ),
              const SizedBox(width: 4),
              Text(liked ? 'Liked' : 'Like',
                  style: AgType.ui(12, liked ? c.ink : c.ink2, weight: 550)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onSelect});

  final PanelTab tab;
  final ValueChanged<PanelTab> onSelect;

  static const labels = {
    PanelTab.queue: 'Queue',
    PanelTab.related: 'Related',
    PanelTab.comments: 'Comments',
  };

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Container(
      height: 33,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          for (final e in labels.entries) ...[
            Interactive(
              onTap: () => onSelect(e.key),
              builder: (context, s) {
                final active = e.key == tab;
                return FocusRing(
                  show: s.focused,
                  child: Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: active
                        ? BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: c.ink, width: 1.5)))
                        : null,
                    child: Text(e.value,
                        style: AgType.ui(13, active || s.hovered ? c.ink : c.ink2,
                            weight: active ? 600 : 450)),
                  ),
                );
              },
            ),
            const SizedBox(width: 22),
          ],
        ],
      ),
    );
  }
}

Widget _caption(BuildContext context, String text) => SizedBox(
      height: 18,
      child: Text(text,
          style: AgType.ui(11, AgColors.of(context).muted, weight: 600)),
    );

Widget _quiet(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Text(text, style: AgType.ui(12, AgColors.of(context).muted)),
    );

class _QueueTab extends StatelessWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.player, app.library]),
      builder: (context, _) => _build(context, app),
    );
  }

  Widget _build(BuildContext context, AppServices app) {
    final player = app.player;
    final cur = player.current;
    if (cur == null) return const SizedBox.shrink();
    final upNext = player.upNext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _caption(context, 'Now playing'),
        PanelTrackRow(
          track: cur,
          now: true,
          unavailable: app.library.unavailableOf(cur) != null,
          onContextMenu: (at) => showTrackMenu(context, at, cur),
        ),
        const SizedBox(height: 8),
        _caption(context, 'Next up'),
        Expanded(
          child: upNext.isEmpty
              ? _quiet(context, 'Nothing up next.')
              : _UpNext(tracks: upNext),
        ),
      ],
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final n = tracks.length;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemExtent: Dp.queueRow,
      itemCount: n,
      padding: EdgeInsets.zero,
      onReorderItem: (from, to) =>
          app.player.moveUpNext(from, to > from ? to + 1 : to),
      proxyDecorator: (child, i, anim) => Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.pillFill,
            border: Border.all(color: c.rim),
            borderRadius: BorderRadius.circular(8),
            boxShadow: c.liftShadows,
          ),
          child: child,
        ),
      ),
      itemBuilder: (context, i) {
        final t = tracks[i];
        return PanelTrackRow(
          key: ValueKey('up-${t.id}-$i'),
          track: t,
          index: i,
          showLine: i < n - 1,
          unavailable: app.library.unavailableOf(t) != null,
          onTap: () => app.player.playAt(app.player.queue.index + 1 + i),
          onContextMenu: (at) => showTrackMenu(context, at, t),
        );
      },
    );
  }
}

class PanelTrackRow extends StatelessWidget {
  const PanelTrackRow({
    super.key,
    required this.track,
    this.now = false,
    this.index,
    this.showLine = false,
    this.unavailable = false,
    this.onTap,
    this.onContextMenu,
  });

  final Track track;
  final bool now;

  final int? index;
  final bool showLine;
  final bool unavailable;
  final VoidCallback? onTap;
  final void Function(Offset)? onContextMenu;

  static const lead = 18.0;
  static const cover = 40.0;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      onDoubleClick: onTap == null || unavailable ? null : () => openFocusFor(context, track),
      onSecondaryTap: onContextMenu,
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, s) {
        final hover = s.hovered && !now;
        Widget leadChild = const SizedBox.shrink();
        if (now) {
          leadChild = Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            ),
          );
        } else if (index != null) {
          leadChild = ReorderableDragStartListener(
            index: index!,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: hover
                  ? Center(child: AgIcon(AgGlyph.grip, color: c.ink2, size: 18))
                  : const SizedBox.expand(),
            ),
          );
        }
        return Container(
          height: Dp.queueRow,
          decoration: BoxDecoration(
            color: now ? c.playingFill : hover ? c.hover : null,
            borderRadius: BorderRadius.circular(8),
          ),
          foregroundDecoration: showLine && !hover
              ? _BottomLine(color: c.hairline, inset: 4 + lead + cover)
              : null,
          child: Row(
            children: [
              const SizedBox(width: 4),
              SizedBox(width: lead, height: Dp.queueRow, child: leadChild),
              ArtImage(
                url: track.artworkUrl,
                size: cover,
                radius: 7,
                dimmed: unavailable,
                artSize: ArtSize.large,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgType.ui(13, unavailable ? c.disabled : c.ink,
                            weight: 550)),
                    const SizedBox(height: 3),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgType.ui(12, c.artist)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(formatMs(track.durationMs), style: AgType.tnum(12, c.ink2)),
              const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

class _BottomLine extends Decoration {
  const _BottomLine({required this.color, required this.inset});

  final Color color;
  final double inset;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _BottomLinePainter(this);
}

class _BottomLinePainter extends BoxPainter {
  _BottomLinePainter(this.d);

  final _BottomLine d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    canvas.drawRect(
        Rect.fromLTWH(offset.dx + d.inset, offset.dy + size.height - 1,
            size.width - d.inset, 1),
        Paint()..color = d.color);
  }
}

Widget _followDetails(BuildContext context,
    Widget Function(AppServices app, TrackDetails details) build) {
  final app = AppScope.of(context);
  return ListenableBuilder(
    listenable: Listenable.merge([app.player, app.details, app.library]),
    builder: (context, _) {
      final track = app.player.current;
      if (track == null) return const SizedBox.shrink();
      return KeyedSubtree(
        key: ValueKey(track.id),
        child: build(app, app.details.of(track)),
      );
    },
  );
}

class _RelatedTab extends StatelessWidget {
  const _RelatedTab();

  @override
  Widget build(BuildContext context) =>
      _followDetails(context, (app, d) => _list(context, app, d));

  Widget _list(BuildContext context, AppServices app, TrackDetails details) {
    final related = details.related;
    if (related == null) {
      return details.error != null
          ? _quiet(context, "Related tracks aren't available right now.")
          : _quiet(context, 'Loading…');
    }
    if (related.isEmpty) {
      return _quiet(
          context,
          details.error != null
              ? "Related tracks aren't available right now."
              : 'No related tracks.');
    }
    return ListView.builder(
      itemExtent: Dp.queueRow,
      itemCount: related.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) {
        final t = related[i];
        final un = app.library.unavailableOf(t) != null;
        return PanelTrackRow(
          track: t,
          showLine: i < related.length - 1,
          unavailable: un,
          onTap: un ? null : () => app.player.playTracks(related, start: i),
          onContextMenu: (at) => showTrackMenu(context, at, t),
        );
      },
    );
  }
}

class _CommentsTab extends StatelessWidget {
  const _CommentsTab();

  @override
  Widget build(BuildContext context) =>
      _followDetails(context, (app, d) => _list(context, app, d));

  Widget _list(BuildContext context, AppServices app, TrackDetails details) {
    final list = details.comments;
    if (list == null) {
      return details.error != null
          ? _quiet(context, "Comments aren't available right now.")
          : _quiet(context, 'Loading comments…');
    }
    if (list.isEmpty) return _quiet(context, 'No comments yet.');
    final player = app.player;
    return ListView.builder(
      itemExtent: Dp.commentRow,
      itemCount: list.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) {
        final cm = list[i];
        final ms = cm.atMs;
        return PanelCommentRow(
          comment: cm,
          showLine: i < list.length - 1,
          onTap: ms == null || player.current?.id != details.track.id
              ? null
              : () async {
                  await player.seek(Duration(milliseconds: ms));
                  if (!player.playing) await player.play();
                },
        );
      },
    );
  }
}

class PanelCommentRow extends StatelessWidget {
  const PanelCommentRow({
    super.key,
    required this.comment,
    required this.showLine,
    this.onTap,
  });

  final TrackComment comment;
  final bool showLine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, s) => Container(
        height: Dp.commentRow,
        decoration: BoxDecoration(
          color: s.hovered && onTap != null ? c.hover : null,
          borderRadius: BorderRadius.circular(8),
        ),
        foregroundDecoration: showLine
            ? _BottomLine(color: c.hairline, inset: 4 + 28 + 10)
            : null,
        child: Row(
          children: [
            const SizedBox(width: 4),
            ArtImage(url: comment.avatarUrl, size: 28, radius: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comment.user,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgType.ui(12, c.ink, weight: 600)),
                  const SizedBox(height: 3),
                  Text(comment.body.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgType.ui(12, c.ink2)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(formatCommentTime(comment.atMs),
                style: AgType.tnum(12, c.muted)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class JumpToCurrent extends StatelessWidget {
  const JumpToCurrent({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: 15,
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 8, right: 14),
          decoration: BoxDecoration(
            color: c.pillFill,
            border: Border.all(color: c.rim),
            borderRadius: BorderRadius.circular(15),
            boxShadow: c.pillShadows,
          ),
          foregroundDecoration: s.hovered || s.pressed
              ? BoxDecoration(
                  color: s.pressed ? c.pressed : c.hover,
                  borderRadius: BorderRadius.circular(15))
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AgIcon(AgGlyph.jump, color: c.ink, size: 20),
              const SizedBox(width: 2),
              Text('Jump to current', style: AgType.ui(12, c.ink, weight: 550)),
            ],
          ),
        ),
      ),
    );
  }
}
