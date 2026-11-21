import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/app/search_index.dart';
import 'package:scglow/core/models.dart';

import 'support/fakes.dart';

void main() {
  test('matches title and artist, every word, case-insensitive', () {
    final idx = SearchIndex([
      track(1, title: 'Glass Harbor', artist: 'Mira Solen'),
      track(2, title: 'Night Bus to Nowhere', artist: 'Soft Radar'),
      track(3, title: 'Harbor Lights, Maybe', artist: 'Mira Solen'),
    ]);
    expect(idx.search('harbor').map((t) => t.id), [1, 3]);
    expect(idx.search('mira glass').map((t) => t.id), [1]);
    expect(idx.search('RADAR').map((t) => t.id), [2]);
    expect(idx.search('kitee'), isEmpty);
    expect(idx.search('   '), isEmpty);
  });

  test('duplicates (liked and in a playlist) appear once', () {
    final t = track(1, title: 'Same');
    expect(SearchIndex([t, t, track(2, title: 'Same too')]).search('same').length, 2);
  });

  test('500 likes + playlists: build and query well under 100 ms', () {
    final words = ['glass', 'harbor', 'copper', 'night', 'moon', 'violet',
      'paper', 'salt', 'field', 'kite', 'bus', 'demo'];
    final tracks = <Track>[
      for (var i = 0; i < 2000; i++)
        track(i,
            title: '${words[i % 12]} ${words[(i * 7) % 12]} $i',
            artist: 'Artist ${i % 97}'),
    ];
    final sw = Stopwatch()..start();
    final idx = SearchIndex(tracks.take(500));
    sw.stop();
    final build = sw.elapsedMicroseconds;
    final times = <int>[];
    for (final q in ['har', 'copper moon', 'artist 42', 'zzz', 'k']) {
      final s = Stopwatch()..start();
      idx.search(q);
      s.stop();
      times.add(s.elapsedMicroseconds);
    }
    final big = SearchIndex(tracks);
    final s = Stopwatch()..start();
    big.search('night 1');
    s.stop();
    // ignore: avoid_print
    print('build 500: ${build}us, queries: $times us, 2000 tracks: ${s.elapsedMicroseconds}us');
    expect(build, lessThan(100000));
    for (final t in times) {
      expect(t, lessThan(100000));
    }
    expect(s.elapsedMicroseconds, lessThan(100000));
  });

  test('sort by date liked, title, artist, duration', () {
    final a = LikedTrack(track(1, title: 'b', artist: 'z', ms: 300), DateTime(2024));
    final b = LikedTrack(track(2, title: 'A', artist: 'y', ms: 100), DateTime(2025));
    final c = LikedTrack(track(3, title: 'c', artist: 'x', ms: 200), DateTime(2023));
    List<int> ids(LikesSort s) =>
        sortLikes([a, b, c], s).map((e) => e.track.id).toList();
    expect(ids(LikesSort.dateLiked), [2, 1, 3]);
    expect(ids(LikesSort.title), [2, 1, 3]);
    expect(ids(LikesSort.artist), [3, 2, 1]);
    expect(ids(LikesSort.duration), [2, 3, 1]);
  });
}
