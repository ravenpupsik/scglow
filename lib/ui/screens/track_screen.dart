import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/marks.dart';
import '../../app/track_details.dart';
import '../../core/models.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/art_image.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/interactive.dart';
import '../widgets/page_parts.dart';
import '../widgets/progress.dart';
import '../widgets/track_row.dart';

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, required this.track, this.initialScroll});

  final Track track;

  final double? initialScroll;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  late final ScrollController _page =
      ScrollController(initialScrollOffset: widget.initialScroll ?? 0);
  final ScrollController _comments = ScrollController();
  final ValueNotifier<int> _current = ValueNotifier(-1);
  List<TrackComment>? _commentsRef;
  List<int> _times = const [];
  AppServices? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app != _app) {
      _app?.player.position.removeListener(_tick);
      _app = app..player.position.addListener(_tick);
    }
  }

  @override
  void didUpdateWidget(TrackScreen old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      _commentsRef = null;
      _times = const [];
      _current.value = -1;
      if (_page.hasClients) _page.jumpTo(0);
      if (_comments.hasClients) _comments.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _app?.player.position.removeListener(_tick);
    _page.dispose();
    _comments.dispose();
    _current.dispose();
    super.dispose();
  }

  bool get _isCurrent => _app?.player.current?.id == widget.track.id;

  void _tick() {
    if (!_isCurrent || _times.isEmpty) {
      if (_current.value != -1) _current.value = -1;
      return;
    }
    final i = currentCommentIndex(
        _times, _app!.player.position.value.inMilliseconds);
    if (i != _current.value) _current.value = i;
  }

  void _syncComments(List<TrackComment>? list) {
    if (identical(list, _commentsRef)) return;
    _commentsRef = list;
    _times = [
      for (final c in list ?? const <TrackComment>[])
        if (c.atMs != null) c.atMs!,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  Future<void> _seekTo(Track track, int ms) async {
    final app = AppScope.of(context);
    final to = Duration(milliseconds: ms);
    if (_isCurrent) {
      await app.player.seek(to);
      if (!app.player.playing) await app.player.play();
    } else if (app.library.unavailableOf(track) == null) {
      await app.player.playTracks([track], start: 0);
      await app.player.seek(to);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.details, app.library, app.player]),
      builder: (context, _) {
        final details = app.details.of(widget.track);
        _syncComments(details.comments);
        final wide = MediaQuery.sizeOf(context).width >= Dp.trackBreakpoint;
        return LayoutBuilder(builder: (context, box) {
          final layout = _Layout(wide: wide, width: box.maxWidth,
              otherPlaying: !_isCurrent);
          return wide
              ? _wide(context, details, layout, box)
              : _narrow(context, details, layout);
        });
      },
    );
  }

  void _scrollToComment(int index, _Layout l) {
    if (l.wide) {
      if (!_comments.hasClients) return;
      final max = _comments.position.maxScrollExtent;
      _comments.animateTo((index * Dp.commentRow).clamp(0.0, max),
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      if (!_page.hasClients) return;
      final max = _page.position.maxScrollExtent;
      _page.animateTo(
          (l.blockTop + _Layout.titleBox + _pad + index * Dp.commentRow)
              .clamp(0.0, max),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut);
    }
  }

  static const _pad = 4.0;

  Widget _header(BuildContext context, TrackDetails d, _Layout l) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final track = d.track;
    final liked = app.library.isLiked(track);
    final hx = l.hx;
    final barW = l.width - Dp.hPad - hx;
    final p = app.player;
    final other = l.otherPlaying;
    return SizedBox(
      height: l.blockTop,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: Dp.hPad - 6,
            top: Dp.pagePad - 6,
            child: CoverBezel(
              child: ArtImage(
                  url: track.artworkUrl,
                  size: l.cover,
                  artSize: ArtSize.t500,
                  radius: Dp.rCoverLarge),
            ),
          ),
          Positioned(
            left: hx,
            right: Dp.hPad,
            top: Dp.pagePad - 4,
            child: Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgType.ui(l.wide ? 32 : 28, c.ink, weight: 600)),
          ),
          Positioned(
            left: hx,
            right: Dp.hPad,
            top: Dp.pagePad + 38,
            child: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AgType.ui(14, c.ink2),
            ),
          ),
          Positioned(
            left: hx - 4,
            top: Dp.pagePad + 62,
            child: Interactive(
              onTap: () => app.library.toggleLike(track),
              builder: (context, s) => FocusRing(
                show: s.focused,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
                  decoration: BoxDecoration(
                    color: s.hovered ? c.hover : null,
                    borderRadius: BorderRadius.circular(Dp.rIconBtn),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AgIcon(liked ? AgGlyph.heart : AgGlyph.heartOutline,
                          color: liked ? c.accent : c.ink2, size: 16),
                      const SizedBox(width: 4),
                      Text(liked ? 'Liked' : 'Like',
                          style: AgType.ui(12, c.ink2, weight: 450)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: hx,
            width: barW,
            top: l.barY - 10,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ProgressLine(
                  position: other ? null : p.position,
                  duration: p.duration,
                  thickness: 3,
                  onSeek: other ? null : p.seek,
                ),
                CommentMarks(
                  timesMs: _times,
                  totalMs: track.durationMs,
                  onGroupTap: (i) => _scrollToComment(i, l),
                ),
              ],
            ),
          ),
          Positioned(
            left: hx,
            top: l.barY + 14,
            child: other
                ? Text('0:00', style: AgType.tnum(22, c.muted, weight: 600))
                : ValueListenableBuilder<Duration>(
                    valueListenable: p.position,
                    builder: (context, pos, _) => Text(formatDuration(pos),
                        style: AgType.tnum(22, c.ink, weight: 600)),
                  ),
          ),
          Positioned(
            right: Dp.hPad,
            top: l.barY + 14,
            child: Text(formatMs(track.durationMs),
                style: AgType.tnum(22, c.ink2, weight: 600)),
          ),
          if (other)
            Positioned(
              left: hx,
              top: l.barY + 44,
              child: Text('Playing a different track',
                  style: AgType.ui(11, c.muted)),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {String? note}) {
    final c = AgColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(text, style: AgType.ui(16, c.ink, weight: 600)),
        if (note != null) ...[
          const SizedBox(width: 10),
          Text(note, style: AgType.ui(11, c.muted)),
        ],
      ],
    );
  }

  Widget _relatedButtons(BuildContext context, List<Track>? related) {
    final app = AppScope.of(context);
    final has = related != null && related.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SecondaryButton.small(
          label: 'Shuffle',
          onTap: has ? () => app.player.playTracks(related, shuffle: true) : null,
        ),
        const SizedBox(width: 8),
        SecondaryButton.small(
          label: 'Play all',
          onTap:
              has ? () => app.player.playTracks(related, shuffle: false) : null,
        ),
      ],
    );
  }

  Widget _commentRow(BuildContext context, Track track, List<TrackComment> list,
      int i) {
    return ValueListenableBuilder<int>(
      valueListenable: _current,
      builder: (context, cur, _) => CommentRow(
        comment: list[i],
        current: cur == i,
        showLine: i < list.length - 1 && cur != i && cur != i + 1,
        onTimeTap: switch (list[i].atMs) {
          final int ms => () => _seekTo(track, ms),
          null => null,
        },
      ),
    );
  }

  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: AgType.ui(12, AgColors.of(context).muted)),
      );

  Widget _relatedRow(BuildContext context, List<Track> related, int i) {
    final app = AppScope.of(context);
    final t = related[i];
    final un = app.library.unavailableOf(t);
    return RelatedRow(
      track: t,
      unavailable: un,
      showLine: i < related.length - 1,
      onTap: () {
        if (un == null) app.player.playTracks(related, start: i);
      },
      onContextMenu: (at) => showTrackMenu(context, at, t),
    );
  }

  Widget _wide(BuildContext context, TrackDetails d, _Layout l, BoxConstraints box) {
    final comments = d.comments;
    final related = d.related;
    final leftW = ((l.width - Dp.hPad * 2 - 24) * 0.58).floorToDouble();
    final cx1 = Dp.hPad + leftW + 24;
    final listTop = l.blockTop + _Layout.titleBox;
    return Stack(
      children: [
        Positioned(left: 0, right: 0, top: 0, child: _header(context, d, l)),
        Positioned(
          left: Dp.hPad,
          top: l.blockTop,
          child: _sectionTitle(context, 'Comments', note: 'Read only'),
        ),
        Positioned(
          left: cx1,
          top: l.blockTop,
          child: _sectionTitle(context, 'Related'),
        ),
        Positioned(
          right: Dp.hPad,
          top: l.blockTop - 2,
          child: _relatedButtons(context, related),
        ),
        Positioned(
          left: Dp.hPad,
          width: leftW,
          top: listTop,
          bottom: 16,
          child: comments == null
              ? _note(context, 'Loading comments…')
              : comments.isEmpty
                  ? _note(context, 'No comments yet.')
                  : GroupCard(
                      radius: Dp.rPanel,
                      contentHeight:
                          comments.length * Dp.commentRow + _pad * 2 + 2,
                      child: ListView.builder(
                        controller: _comments,
                        itemExtent: Dp.commentRow,
                        itemCount: comments.length,
                        padding: const EdgeInsets.symmetric(vertical: _pad),
                        itemBuilder: (context, i) =>
                            _commentRow(context, d.track, comments, i),
                      ),
                    ),
        ),
        Positioned(
          left: cx1,
          right: Dp.hPad,
          top: listTop,
          bottom: 16,
          child: related == null
              ? _note(context, 'Loading…')
              : related.isEmpty
                  ? _note(context, 'Nothing related.')
                  : GroupCard(
                      radius: Dp.rPanel,
                      contentHeight:
                          related.length * Dp.relatedRow + _pad * 2 + 2,
                      child: ListView.builder(
                        itemExtent: Dp.relatedRow,
                        itemCount: related.length,
                        padding: const EdgeInsets.symmetric(vertical: _pad),
                        itemBuilder: (context, i) =>
                            _relatedRow(context, related, i),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context, TrackDetails d, _Layout l) {
    final c = AgColors.of(context);
    final comments = d.comments ?? const <TrackComment>[];
    final related = d.related ?? const <Track>[];
    Widget carded(Widget sliver) => SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Dp.hPad),
          sliver: DecoratedSliver(
            decoration: c.card(radius: Dp.rPanel),
            sliver: SliverPadding(
              padding: const EdgeInsets.all(_pad / 4).copyWith(top: _pad, bottom: _pad),
              sliver: sliver,
            ),
          ),
        );
    return CustomScrollView(
      controller: _page,
      slivers: [
        SliverToBoxAdapter(child: _header(context, d, l)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: Dp.hPad),
            child: SizedBox(
              height: d.comments == null || comments.isEmpty
                  ? _Layout.titleBox + 24
                  : _Layout.titleBox,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(context, 'Comments', note: 'Read only'),
                  if (d.comments == null || comments.isEmpty)
                    _note(context,
                        d.comments == null ? 'Loading comments…' : 'No comments yet.'),
                ],
              ),
            ),
          ),
        ),
        if (comments.isNotEmpty)
          carded(SliverFixedExtentList(
            itemExtent: Dp.commentRow,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _commentRow(context, d.track, comments, i),
              childCount: comments.length,
            ),
          )),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: Stack(
              children: [
                Positioned(
                  left: Dp.hPad,
                  top: 22,
                  child: _sectionTitle(context, 'Related'),
                ),
                Positioned(
                  right: Dp.hPad,
                  top: 20,
                  child: _relatedButtons(context, d.related),
                ),
              ],
            ),
          ),
        ),
        if (related.isNotEmpty)
          carded(SliverFixedExtentList(
            itemExtent: Dp.relatedRow,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _relatedRow(context, related, i),
              childCount: related.length,
            ),
          )),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _Layout {
  _Layout({required this.wide, required this.width, required this.otherPlaying});

  final bool wide;
  final double width;
  final bool otherPlaying;

  static const titleBox = 28.0;

  double get cover => wide ? 160 : 110;
  double get hx => Dp.hPad + cover + 20;
  double get barY => Dp.pagePad + 108;
  double get blockTop {
    final a = Dp.pagePad + cover + 16;
    final b = barY + (otherPlaying ? 64 : 56);
    return a > b ? a : b;
  }
}

class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.current,
    required this.showLine,
    required this.onTimeTap,
  });

  final TrackComment comment;
  final bool current;
  final bool showLine;
  final VoidCallback? onTimeTap;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return CustomPaint(
      painter: RowBackground(
        fill: current ? c.glassTile : null,
        line: showLine ? c.hairline : null,
        radius: Dp.rIconBtn,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 39,
            child: Align(
              alignment: Alignment.centerRight,
              child: MouseRegion(
                cursor: onTimeTap == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTimeTap,
                  child: Text(formatCommentTime(comment.atMs),
                      style: AgType.tnum(11, current ? c.ink : c.ink2,
                          weight: 600)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comment.user,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgType.ui(11, c.ink, weight: 600)),
                const SizedBox(height: 4),
                Text(comment.body.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgType.ui(12, c.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class RelatedRow extends StatelessWidget {
  const RelatedRow({
    super.key,
    required this.track,
    required this.showLine,
    required this.onTap,
    this.unavailable,
    this.onContextMenu,
  });

  final Track track;
  final bool showLine;
  final VoidCallback onTap;
  final Unavailable? unavailable;
  final void Function(Offset)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    final blocked = unavailable != null;
    return Interactive(
      onTap: onTap,
      onSecondaryTap: onContextMenu,
      tooltip: blocked ? unavailable!.label : null,
      builder: (context, s) => CustomPaint(
        painter: RowBackground(
          fill: blocked
              ? null
              : s.pressed
                  ? c.pressed
                  : s.hovered
                      ? c.hover
                      : null,
          line: showLine ? c.hairline : null,
          focus: s.focused ? c.focus : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 9),
            ArtImage(url: track.artworkUrl, size: 36, dimmed: blocked),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgType.ui(12.5, blocked ? c.disabled : c.ink,
                          weight: 600)),
                  const SizedBox(height: 3),
                  Text(
                    blocked
                        ? '${track.artist}   ·   Unavailable'
                        : '${track.artist}   ·   ${formatMs(track.durationMs)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgType.ui(11, blocked ? c.disabled : c.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
