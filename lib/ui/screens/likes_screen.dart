import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/library_controller.dart';
import '../../app/search_index.dart';
import '../../app/ui_state.dart';
import '../../core/errors.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/interactive.dart';
import '../widgets/page_parts.dart';

class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key, this.query = ''});

  final String query;

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen> {
  final _scroll = ScrollController();
  int _likesLen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _preserveScroll(int newLen) {
    final added = newLen - _likesLen;
    _likesLen = newLen;
    if (added <= 0 || !_scroll.hasClients || _scroll.offset <= 1) return;
    final jump = _scroll.offset + added * Dp.row;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(jump);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lib = app.library;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final searching = widget.query.trim().isNotEmpty;
        final tracks = searching ? lib.search(widget.query) : lib.likes;
        if (!searching) _preserveScroll(tracks.length);
        final loadingFirst = lib.status == LibraryStatus.loading;
        final count = lib.totalLikes != null && loadingFirst
            ? lib.totalLikes!
            : lib.likesCount;
        String? counter;
        if (searching) {
          counter = tracks.isEmpty ? null : '${tracks.length}';
        } else if (count > 0) {
          counter = '$count';
        }

        Widget body;
        if (searching && tracks.isEmpty) {
          body = EmptyMessage(
            title: 'No results',
            body: 'Nothing in your library matches “${widget.query.trim()}”.',
          );
        } else if (!searching &&
            tracks.isEmpty &&
            lib.status == LibraryStatus.empty &&
            lib.error != null) {
          final e = lib.error!;
          body = e is ScNetworkError
              ? EmptyMessage(
                  title: 'No connection',
                  body: 'Check the network, then try again.',
                  onRetry: () => app.session.user == null
                      ? app.session.start()
                      : lib.refresh(),
                )
              : EmptyMessage(
                  title: 'SoundCloud changed something',
                  body: 'Nothing on this computer was lost.',
                  onRetry: lib.refresh,
                );
        } else if (!searching && tracks.isEmpty && !loadingFirst &&
            !lib.refreshing) {
          body = const EmptyMessage(
            title: 'No likes yet',
            body: 'Like tracks on SoundCloud — they will appear here.',
          );
        } else {
          body = TrackListView(
            tracks: tracks,
            controller: searching ? null : _scroll,
            skeletons: loadingFirst || (lib.refreshing && tracks.isEmpty) ? 3 : 0,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Likes',
              count: counter,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RefreshButton(
                    refreshing: lib.refreshing,
                    onTap: () => refreshWithFeedback(app),
                  ),
                  const SizedBox(width: 8),
                  PlayAllChip(
                    onTap: tracks.isEmpty
                        ? null
                        : () => app.player.playTracks(tracks, shuffle: false),
                  ),
                  const SizedBox(width: 8),
                  GlassChip(
                    label: 'Shuffle',
                    onTap: tracks.isEmpty
                        ? null
                        : () => app.player.playTracks(tracks, shuffle: true),
                  ),
                  const SizedBox(width: 8),
                  _SortControl(
                    value: lib.sort,
                    onChanged: (s) {
                      lib.sort = s;
                      SortPrefs.write(app.prefs, s);
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({required this.value, required this.onChanged});

  final LikesSort value;
  final ValueChanged<LikesSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Interactive(
      onTap: () => _open(context),
      semanticLabel: 'Sort',
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.rChip,
        child: Container(
          height: Dp.chipH,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: c.tile(radius: Dp.rChip),
          foregroundDecoration: s.pressed || s.hovered
              ? BoxDecoration(
                  color: s.pressed ? c.pressed : c.hover,
                  borderRadius: BorderRadius.circular(Dp.rChip))
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value.label, style: AgType.ui(12, c.ink, weight: 500)),
              const SizedBox(width: 4),
              RotatedBox(
                quarterTurns: 1,
                child: AgIcon(AgGlyph.chevron, color: c.muted, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(box.size.width, box.size.height + 6));
    final choice = await showGlassMenu<LikesSort>(
      context,
      position: RelativeRect.fromLTRB(at.dx - 168, at.dy, at.dx, at.dy),
      items: [
        for (final s in LikesSort.values)
          GlassMenuItem(s, s.label, checked: s == value),
      ],
    );
    if (choice != null) onChanged(choice);
  }
}
