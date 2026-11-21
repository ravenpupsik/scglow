import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/ui_state.dart';
import '../../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/art_image.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/interactive.dart';
import '../widgets/page_parts.dart';
import '../widgets/track_row.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lib = app.library;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final lists = lib.playlists;
        final n = lists.length;
        Widget body;
        if (n == 0 && !lib.playlistsLoaded) {
          body = const SkeletonCard();
        } else if (n == 0) {
          body = const EmptyMessage(
            title: 'No playlists yet',
            body: 'Playlists you make or like on SoundCloud will appear here.',
          );
        } else {
          body = Padding(
            padding: const EdgeInsets.fromLTRB(Dp.hPad, 0, Dp.hPad, 20),
            child: GroupCard(
              contentHeight: n * Dp.row + Dp.cardPadY * 2 + 2,
              child: Builder(
                builder: (context) => ListView.builder(
                itemExtent: Dp.row,
                itemCount: n,
                padding: EdgeInsets.only(
                    top: Dp.cardPadY, bottom: GroupCard.bottomPad(context)),
                itemBuilder: (context, i) => PlaylistRow(
                  key: ValueKey(lists[i].id),
                  playlist: lists[i],
                  showLine: i < n - 1,
                  edge: i == 0 || i == n - 1,
                  onTap: () => app.nav.go(PlaylistRoute(lists[i].id)),
                ),
              ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Playlists',
              count: n > 0 ? '$n' : null,
              trailing: RefreshButton(
                refreshing: lib.refreshing,
                onTap: () => refreshWithFeedback(app),
              ),
            ),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

class PlaylistRow extends StatelessWidget {
  const PlaylistRow({
    super.key,
    required this.playlist,
    required this.onTap,
    this.showLine = true,
    this.edge = false,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final bool showLine;
  final bool edge;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: onTap,
      builder: (context, s) => CustomPaint(
        painter: RowBackground(
          fill: s.pressed
              ? c.pressed
              : s.hovered
                  ? c.hover
                  : null,
          radius: edge ? RowGeo.edgeRadius : RowGeo.fillRadius,
          line: showLine ? c.hairline : null,
          focus: s.focused ? c.focus : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: RowGeo.lead + Dp.dotCol),
            ArtImage(
                url: playlist.artworkUrl,
                size: Dp.rowCover,
                radius: Dp.rRowCover),
            const SizedBox(width: RowGeo.coverGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgType.ui(13, c.ink, weight: 550)),
                  const SizedBox(height: 2),
                  Text('${playlist.trackCount} tracks',
                      style: AgType.ui(12, c.artist)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AgIcon(AgGlyph.chevron,
                color: s.hovered ? c.ink2 : c.muted, size: 16),
            const SizedBox(width: RowGeo.right - 2),
          ],
        ),
      ),
    );
  }
}

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).library.loadPlaylist(widget.playlistId);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app.library,
      builder: (context, _) {
        final pl = app.library.playlistById(widget.playlistId);
        if (pl == null) {
          return const EmptyMessage(
              title: 'Playlist not found', body: 'It may have been removed.');
        }
        final tracks = app.library.playlistTracks(pl.id);
        final list = tracks ?? const <Track>[];
        final has = list.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: pl.title,
              count: '${pl.trackCount}',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RefreshButton(
                    refreshing: app.library.refreshing,
                    onTap: () => refreshWithFeedback(app),
                  ),
                  const SizedBox(width: 8),
                  PlayAllChip(
                    onTap: has
                        ? () => app.player.playTracks(list, shuffle: false)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  GlassChip(
                    label: 'Shuffle',
                    onTap: has
                        ? () => app.player.playTracks(list, shuffle: true)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: tracks == null
                  ? const SkeletonCard()
                  : tracks.isEmpty
                      ? const EmptyMessage(
                          title: 'Empty playlist',
                          body: 'There are no tracks in this playlist.')
                      : TrackListView(tracks: tracks),
            ),
          ],
        );
      },
    );
  }
}
