import '../core/models.dart';

class SearchIndex {
  SearchIndex(Iterable<Track> tracks) {
    final seen = <int>{};
    for (final t in tracks) {
      if (!seen.add(t.id)) continue;
      _tracks.add(t);
      _hay.add(normalize('${t.title} ${t.artist}'));
    }
  }

  final List<Track> _tracks = [];
  final List<String> _hay = [];

  int get length => _tracks.length;

  static String normalize(String s) => s.toLowerCase().trim();

  List<Track> search(String query) {
    final words = normalize(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    final out = <Track>[];
    for (var i = 0; i < _hay.length; i++) {
      final h = _hay[i];
      var ok = true;
      for (final w in words) {
        if (!h.contains(w)) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(_tracks[i]);
    }
    return out;
  }
}

enum LikesSort {
  dateLiked('Date liked'),
  title('Title'),
  artist('Artist'),
  duration('Duration');

  const LikesSort(this.label);
  final String label;
}

List<LikedTrack> sortLikes(List<LikedTrack> items, LikesSort sort) {
  final list = [...items];
  int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  switch (sort) {
    case LikesSort.dateLiked:
      list.sort((a, b) => b.likedAt.compareTo(a.likedAt));
    case LikesSort.title:
      list.sort((a, b) {
        final c = byText(a.track.title, b.track.title);
        return c != 0 ? c : byText(a.track.artist, b.track.artist);
      });
    case LikesSort.artist:
      list.sort((a, b) {
        final c = byText(a.track.artist, b.track.artist);
        return c != 0 ? c : byText(a.track.title, b.track.title);
      });
    case LikesSort.duration:
      list.sort((a, b) => a.track.durationMs.compareTo(b.track.durationMs));
  }
  return list;
}
