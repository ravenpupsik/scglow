import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/ui_state.dart';
import '../../core/errors.dart';
import '../../core/models.dart';
import '../theme/tokens.dart';
import '../track_panel.dart';
import 'buttons.dart';
import 'glass.dart';
import 'icons.dart';
import 'interactive.dart';
import 'track_row.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.count, this.trailing});

  final String title;
  final String? count;
  final Widget? trailing;

  static const contentTop = Dp.titleRow;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return SizedBox(
      height: contentTop,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Dp.hPad, 10, Dp.hPad, 6),
        child: Row(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgType.ui(22, c.ink, weight: 600)),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 10),
                    Text(count!, style: AgType.tnum(20, c.ink2, weight: 500)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    super.key,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: onRetry != null ? 40 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AgType.ui(26, c.ink, weight: 600)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center, style: AgType.ui(13, c.ink2)),
            if (onRetry != null) ...[
              const SizedBox(height: 22),
              PrimaryButton(label: 'Retry', onTap: onRetry, width: 120),
            ],
          ],
        ),
      ),
    );
  }
}

class GlassMenuItem<T> {
  const GlassMenuItem(this.value, this.label,
      {this.enabled = true, this.checked = false});

  final T value;
  final String label;
  final bool enabled;
  final bool checked;
}

Future<T?> showGlassMenu<T>(
  BuildContext context, {
  required RelativeRect position,
  required List<GlassMenuItem<T>> items,
  double width = 168,
}) {
  return showMenu<T>(
    context: context,
    position: position,
    color: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    constraints: BoxConstraints.tightFor(width: width),
    menuPadding: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(),
    items: [_GlassMenuPanel<T>(items)],
  );
}

class _GlassMenuPanel<T> extends PopupMenuEntry<T> {
  const _GlassMenuPanel(this.items);

  final List<GlassMenuItem<T>> items;

  @override
  double get height => items.length * rowH + 16;

  static const rowH = 30.0;

  @override
  bool represents(T? value) => items.any((i) => i.value == value);

  @override
  State<_GlassMenuPanel<T>> createState() => _GlassMenuPanelState<T>();
}

class _GlassMenuPanelState<T> extends State<_GlassMenuPanel<T>> {
  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return FrostedGlass(
      radius: Dp.rSortMenu,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in widget.items)
            Interactive(
              enabled: it.enabled,
              onTap: () => Navigator.of(context).pop<T>(it.value),
              builder: (context, s) => Container(
                height: _GlassMenuPanel.rowH,
                padding: const EdgeInsets.only(left: 6, right: 4),
                decoration: it.checked || (it.enabled && (s.hovered || s.focused))
                    ? BoxDecoration(
                        color: s.pressed ? c.pressed : c.hover,
                        borderRadius: BorderRadius.circular(6))
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(it.label,
                          style: AgType.ui(12, it.enabled ? c.ink : c.disabled,
                              weight: 500)),
                    ),
                    if (it.checked) AgIcon(AgGlyph.check, color: c.ink, size: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showTrackMenu(BuildContext context, Offset at, Track track) async {
  final app = AppScope.of(context);
  final blocked = app.library.unavailableOf(track) != null;
  final liked = app.library.isLiked(track);
  final choice = await showGlassMenu<String>(
    context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
    items: [
      GlassMenuItem('next', 'Play next', enabled: !blocked),
      GlassMenuItem('queue', 'Add to queue', enabled: !blocked),
      const GlassMenuItem('open', 'Open track page'),
      GlassMenuItem('like', liked ? 'Unlike' : 'Like'),
    ],
  );
  switch (choice) {
    case 'next':
      app.player.playNext(track);
    case 'queue':
      app.player.addToQueue(track);
    case 'open':
      app.nav.go(TrackRoute(track));
    case 'like':
      app.library.toggleLike(track);
  }
}

class TrackListView extends StatefulWidget {
  const TrackListView({
    super.key,
    required this.tracks,
    this.skeletons = 0,
    this.controller,
    this.skeletonOpacity,
  });

  final List<Track> tracks;
  final int skeletons;
  final ScrollController? controller;
  final double? skeletonOpacity;

  @override
  State<TrackListView> createState() => _TrackListViewState();
}

class _TrackListViewState extends State<TrackListView> {
  ScrollController? _own;

  ScrollController get _scroll =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _jump(int i) {
    final s = _scroll;
    if (!s.hasClients) return;
    final view = s.position.viewportDimension;
    final target = (Dp.cardPadY + i * Dp.row - (view - Dp.row) / 2)
        .clamp(0.0, s.position.maxScrollExtent);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      s.jumpTo(target);
    } else {
      s.animateTo(target, duration: Dp.panelAnim, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tracks = widget.tracks;
    final skeletons = widget.skeletons;
    final n = tracks.length;
    final rows = n + skeletons;
    final contentH = rows * Dp.row + Dp.cardPadY * 2 + 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Dp.hPad, 0, Dp.hPad, 20),
      child: ListenableBuilder(
        listenable: Listenable.merge([app.player, app.library]),
        builder: (context, _) {
          final playingId = app.player.current?.id;
          final playingAt =
              playingId == null ? -1 : tracks.indexWhere((t) => t.id == playingId);
          final list = GroupCard(
            contentHeight: contentH,
            child: Builder(
              builder: (context) => ListView.builder(
                controller: _scroll,
                itemExtent: Dp.row,
                itemCount: n + (skeletons > 0 ? 1 : 0),
                padding: EdgeInsets.only(
                    top: Dp.cardPadY, bottom: GroupCard.bottomPad(context)),
                itemBuilder: (context, i) {
                  if (i == n) {
                    return OverflowBox(
                      alignment: Alignment.topCenter,
                      maxHeight: Dp.row * skeletons,
                      child: SkeletonRows(
                          count: skeletons, opacity: widget.skeletonOpacity),
                    );
                  }
                  final t = tracks[i];
                  final un = app.library.unavailableOf(t);
                  return TrackRow(
                    key: ValueKey(t.id),
                    track: t,
                    playing: t.id == playingId,
                    liked: app.library.isLiked(t),
                    unavailable: un,
                    preview: un == null && t.isPreviewOnly,
                    showLine: i < n - 1 || skeletons > 0,
                    edge: i == 0 || (i == n - 1 && skeletons == 0),
                    onTap: () {
                      if (un == null) app.player.playTracks(tracks, start: i);
                    },
                    onLike: () => app.library.toggleLike(t),
                    onContextMenu: (at) => showTrackMenu(context, at, t),
                  );
                },
              ),
            ),
          );
          if (playingAt < 0) return list;
          return LayoutBuilder(builder: (context, box) {
            final h = contentH < box.maxHeight ? contentH : box.maxHeight;
            final anim = PanelScope.of(context);
            Widget jump(double t) {
              var shift = 0.0;
              final size = MediaQuery.sizeOf(context);
              final g = PanelGeo(size, t);
              if (g.overlay && t > 0) {
                final cardRight = (size.width + box.maxWidth) / 2;
                shift = (cardRight - (g.panelLeft - 12)).clamp(0.0, box.maxWidth);
              }
              return Positioned(
                right: 6 + shift,
                top: h - 10 - 30,
                child: JumpToCurrent(onTap: () => _jump(playingAt)),
              );
            }

            return Stack(
              children: [
                Positioned.fill(child: list),
                if (anim == null)
                  jump(0)
                else
                  AnimatedBuilder(
                    animation: anim,
                    builder: (context, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [jump(anim.value)],
                    ),
                  ),
              ],
            );
          });
        },
      ),
    );
  }
}

Future<void> refreshWithFeedback(AppServices app) async {
  await app.library.refresh();
  final e = app.library.error;
  if (e != null) {
    app.messages.show(friendlyError(e),
        action: 'Retry', onAction: () => refreshWithFeedback(app));
  }
}
