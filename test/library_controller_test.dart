import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scglow/app/library_controller.dart';
import 'package:scglow/app/search_index.dart';
import 'package:scglow/core/client_id_provider.dart';
import 'package:scglow/core/errors.dart';
import 'package:scglow/core/json_store.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/core/sc_api.dart';
import 'package:scglow/core/storage.dart';

Map<String, dynamic> trackJson(int id, {String? title}) => {
      'id': id,
      'title': title ?? 'Track $id',
      'duration': 180000 + id,
      'user': {'username': 'Artist $id'},
      'media': {
        'transcodings': [
          {
            'url': 'https://api-v2.soundcloud.com/media/$id',
            'format': {'protocol': 'hls', 'mime_type': 'audio/mpeg'}
          }
        ]
      },
    };

class FakeSc {
  final likes = <int>[for (var i = 1; i <= 230; i++) i];
  final writes = <String>[];
  int likeStatus = 200;
  int pagesServed = 0;

  http.Response handle(http.Request r) {
    final p = r.url.path;
    if (p == '/users/5/track_likes') {
      final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(r.url.queryParameters['limit'] ?? '100');
      pagesServed++;
      final slice = likes.skip(offset).take(limit).toList();
      final next = offset + limit < likes.length
          ? 'https://api-v2.soundcloud.com/users/5/track_likes?offset=${offset + limit}&limit=$limit'
          : null;
      return _json({
        'collection': [
          for (var i = 0; i < slice.length; i++)
            {
              'created_at': DateTime.utc(2026, 6, 1)
                  .subtract(Duration(minutes: offset + i))
                  .toIso8601String(),
              'track': trackJson(slice[i])
            }
        ],
        'next_href': next,
      });
    }
    if (p == '/users/5/playlists') {
      return _json({
        'collection': [
          {'id': 900, 'title': 'Night drive', 'track_count': 2, 'last_modified': 'a', 'user': {'username': 'me'}}
        ],
        'next_href': null,
      });
    }
    if (p == '/users/5/playlist_likes') return _json({'collection': [], 'next_href': null});
    if (p == '/playlists/900') {
      return _json({
        'id': 900,
        'title': 'Night drive',
        'track_count': 2,
        'last_modified': 'a',
        'tracks': [trackJson(1001, title: 'Copper Moon'), {'id': 1002}],
      });
    }
    if (p == '/tracks') {
      return _json([trackJson(1002, title: 'Paper Kites')]);
    }
    if (p.startsWith('/users/5/track_likes/')) {
      writes.add('${r.method} $p');
      return http.Response('', likeStatus);
    }
    return http.Response('', 404);
  }

  static http.Response _json(Object o) => http.Response(jsonEncode(o), 200);
}

void main() {
  late FakeSc sc;
  late MemoryJsonStore store;
  late List<ScException> errors;
  late DateTime now;
  Completer<void>? likesGate;
  var likeRequests = 0;

  LibraryController build() {
    final client = MockClient((r) async {
      if (r.url.host == 'api-v2.soundcloud.com') {
        if (r.url.path == '/users/5/track_likes') {
          likeRequests++;
          if (likesGate != null) await likesGate!.future;
        }
        return sc.handle(r);
      }
      if (r.url.host == 'soundcloud.com') {
        return http.Response('<script crossorigin src="https://a-v2.sndcdn.com/assets/1-y.js"></script>', 200);
      }
      return http.Response('client_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"', 200);
    });
    return LibraryController(
      api: ScApi(
        client: client,
        clientId: ClientIdProvider(client: client, store: MemoryKeyValueStore()),
        readToken: () async => 'tok',
        minGap: Duration.zero,
      ),
      store: store,
      onAuthExpired: () {},
      onError: errors.add,
      pageDelay: Duration.zero,
      clock: () => now,
    );
  }

  setUp(() {
    sc = FakeSc();
    store = MemoryJsonStore();
    errors = [];
    now = DateTime.utc(2026, 11, 20, 12);
    likesGate = null;
    likeRequests = 0;
  });

  test('loads all like pages, playlists and fills playlist stubs', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    expect(lib.likesCount, 230);
    expect(sc.pagesServed, 3);
    expect(lib.status, LibraryStatus.ready);
    expect(lib.playlists.single.title, 'Night drive');
    expect(lib.playlistTracks(900)!.map((t) => t.title), ['Copper Moon', 'Paper Kites']);
    expect(lib.search('paper').map((t) => t.id), [1002]);
  });

  test('cache round trip: second start shows everything before network', () async {
    final first = build();
    await first.open(5);
    await first.refresh();

    sc.likes.clear();
    final second = build();
    final uid = await second.openCached();
    expect(uid, 5);
    expect(second.likesCount, 230);
    expect(second.status, LibraryStatus.ready);
    expect(second.playlistTracks(900)!.length, 2);
    second.sort = LikesSort.title;
    expect(second.likes.first.title, 'Track 1');
  });

  test('like failure rolls back and reports', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    final t = lib.likes.first;
    sc.likeStatus = 500;
    final ok = await lib.toggleLike(t);
    expect(ok, isFalse);
    expect(lib.likedIds.contains(t.id), isTrue);
    expect(errors, hasLength(1));
    expect(sc.writes, ['DELETE /users/5/track_likes/${t.id}']);
  });

  test('re-like after unlike: failed PUT rolls back to unliked', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    final t = lib.likes.first;
    expect(await lib.toggleLike(t), isTrue);
    expect(lib.likedIds.contains(t.id), isFalse);
    sc.likeStatus = 403;
    expect(await lib.toggleLike(t), isFalse);
    expect(lib.likedIds.contains(t.id), isFalse);
    expect(errors.single, isA<ScChanged>().having((e) => e.status, 'status', 403));
    expect(sc.writes, [
      'DELETE /users/5/track_likes/${t.id}',
      'PUT /users/5/track_likes/${t.id}',
    ]);
  });

  test('unlike keeps the row until refresh but drops it from the cache', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    final t = lib.likes.first;
    expect(await lib.toggleLike(t), isTrue);
    expect(lib.likedIds.contains(t.id), isFalse);
    expect(lib.likes.first.id, t.id);
    final cached = (await store.read(LibraryController.cacheName))!;
    expect((cached['likes'] as List).length, 229);
  });

  test('runtime unavailable reasons survive restart', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    lib.markUnavailable(lib.likes.first, Unavailable.goPlusOnly);
    await Future<void>.delayed(Duration.zero);
    final again = build();
    await again.openCached();
    expect(again.unavailableOf(again.likes.first), Unavailable.goPlusOnly);
  });

  test('refresh prepends new likes and drops removed ones', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    expect(lib.likes.first.id, 1);
    expect(lib.likesCount, 230);

    sc.likes.insertAll(0, [900, 901]);
    sc.likes.remove(50);
    sc.pagesServed = 0;
    await lib.refresh();
    expect(lib.likes.map((t) => t.id).take(4).toList(), [900, 901, 1, 2]);
    expect(lib.likes.any((t) => t.id == 50), isFalse);
    expect(lib.likesCount, 231);
    expect(lib.likedIds.contains(50), isFalse);
    expect(lib.likedIds.contains(900), isTrue);
  });

  test('refreshOnFocus is throttled to once per two minutes', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    sc.likes.insert(0, 900);
    sc.pagesServed = 0;

    await lib.refreshOnFocus();
    expect(sc.pagesServed, 0);
    expect(lib.likes.first.id, 1);

    now = now.add(const Duration(minutes: 2) - const Duration(seconds: 1));
    await lib.refreshOnFocus();
    expect(sc.pagesServed, 0);

    now = now.add(const Duration(seconds: 1));
    await lib.refreshOnFocus();
    expect(sc.pagesServed, greaterThan(0));
    expect(lib.likes.first.id, 900);
  });

  test('refreshOnFocus does nothing while a refresh is running', () async {
    likesGate = Completer<void>();
    final lib = build();
    await lib.open(5);
    await Future<void>.delayed(Duration.zero);
    expect(lib.refreshing, isTrue);
    expect(likeRequests, 1);
    await lib.refreshOnFocus();
    expect(likeRequests, 1);
    likesGate!.complete();
    await lib.refresh();
    expect(lib.refreshing, isFalse);
    expect(lib.likesCount, 230);
  });

  test('manual refresh ignores the focus throttle', () async {
    final lib = build();
    await lib.open(5);
    await lib.refresh();
    sc.likes.insert(0, 900);
    sc.pagesServed = 0;
    await lib.refresh();
    expect(lib.likes.first.id, 900);
    expect(sc.pagesServed, greaterThan(0));
  });
}
