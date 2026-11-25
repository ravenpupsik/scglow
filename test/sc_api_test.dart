import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:io';

import 'package:scglow/core/client_id_provider.dart';
import 'package:scglow/core/diag_log.dart';
import 'package:scglow/core/errors.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/core/sc_api.dart';
import 'package:scglow/core/storage.dart';

const _id1 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1';
const _id2 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2';

void main() {
  late List<String> calls;
  late int siteVersion;

  http.Response site(http.Request r) {
    if (r.url.host == 'soundcloud.com') {
      return http.Response(
          '<script>window.__sc_version="1795109958"</script>'
          '<script crossorigin src="https://a-v2.sndcdn.com/assets/0-x.js"></script>'
          '<script crossorigin src="https://a-v2.sndcdn.com/assets/1-y.js"></script>',
          200);
    }
    if (r.url.path.endsWith('1-y.js')) {
      return http.Response(
          'foo({client_id:"${siteVersion == 1 ? _id1 : _id2}"})', 200);
    }
    return http.Response('nothing here', 200);
  }

  ScApi build(http.Response Function(http.Request r) api,
      {WebWriter? web, Future<String?> Function()? botCookie}) {
    final client = MockClient((r) async {
      if (r.url.host != 'api-v2.soundcloud.com') return site(r);
      calls.add('${r.url.path}?cid=${r.url.queryParameters['client_id']}');
      return api(r);
    });
    return ScApi(
      client: client,
      clientId: ClientIdProvider(client: client, store: MemoryKeyValueStore()),
      readToken: () async => 'tok',
      minGap: Duration.zero,
      webWriter: web,
      readBotCookie: botCookie,
    );
  }

  late Directory logDir;

  setUp(() {
    calls = [];
    siteVersion = 1;
    logDir = Directory.systemTemp.createTempSync('scglow_log');
    DiagLog.pathOverride = '${logDir.path}/scglow.log';
  });

  tearDown(() {
    DiagLog.pathOverride = null;
    logDir.deleteSync(recursive: true);
  });

  String log() {
    final f = File('${logDir.path}/scglow.log');
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  http.Response botWall() => http.Response(
      '{"url":"https://geo.captcha-delivery.com/captcha/?initialCid=x"}', 403,
      headers: {'x-datadome': 'protected'});

  group('like writes', () {
    test('PUT is shaped like the site: app_version, locale, DataDome id',
        () async {
      late http.Request seen;
      final api = build((r) {
        seen = r;
        return http.Response('', 201);
      }, botCookie: () async => 'dd-cookie');
      await api.like(5, 42);
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/users/5/track_likes/42');
      expect(seen.url.queryParameters['client_id'], _id1);
      expect(seen.url.queryParameters['app_version'], '1795109958');
      expect(seen.url.queryParameters['app_locale'], 'en');
      expect(seen.headers['Authorization'], 'OAuth tok');
      expect(seen.headers['X-Datadome-ClientId'], 'dd-cookie');
      expect(seen.contentLength, 0);
    });

    test('DataDome 403 is retried through the web session', () async {
      final web = _FakeWeb(const WebWriteResult(200));
      final api = build((r) => botWall(), web: web);
      await api.like(5, 42);
      expect(web.calls, hasLength(1));
      final (method, url, token) = web.calls.single;
      expect(method, 'PUT');
      expect(url.path, '/users/5/track_likes/42');
      expect(url.queryParameters['client_id'], _id1);
      expect(url.queryParameters['app_version'], '1795109958');
      expect(token, 'tok');
      expect(log(), contains('PUT /users/5/track_likes/42 -> 403 [direct]'));
      expect(log(), contains('captcha-delivery'));
    });

    test('web session failure keeps the status for the UI', () async {
      final web = _FakeWeb(const WebWriteResult(403, 'blocked'));
      final api = build((r) => botWall(), web: web);
      await expectLater(
          api.like(5, 42),
          throwsA(isA<ScChanged>()
              .having((e) => e.status, 'status', 403)));
      expect(log(), contains('-> 403 [webview] blocked'));
    });

    test('web session 401 means the session expired', () async {
      final api = build((r) => botWall(),
          web: _FakeWeb(const WebWriteResult(401)));
      await expectLater(api.like(5, 42), throwsA(isA<ScAuthExpired>()));
    });

    test('web session crash falls back to the direct status', () async {
      final api = build((r) => botWall(), web: _FakeWeb(null));
      await expectLater(api.like(5, 42),
          throwsA(isA<ScChanged>().having((e) => e.status, 'status', 403)));
    });

    test('other statuses are not sent to the web session', () async {
      final web = _FakeWeb(const WebWriteResult(200));
      final api = build((r) => http.Response('nope', 422), web: web);
      await expectLater(api.like(5, 42),
          throwsA(isA<ScChanged>().having((e) => e.status, 'status', 422)));
      expect(web.calls, isEmpty);
      expect(friendlyError(const ScChanged('HTTP 422', 422)),
          'SoundCloud changed something · 422');
    });

    test('unlike stays a plain DELETE', () async {
      late http.Request seen;
      final api = build((r) {
        seen = r;
        return http.Response('', 200);
      });
      await api.unlike(5, 42);
      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/users/5/track_likes/42');
    });

    test('refreshed DataDome cookie from X-Set-Cookie is used next', () async {
      final seen = <String?>[];
      final api = build((r) {
        seen.add(r.headers['X-Datadome-ClientId']);
        return http.Response('', 200,
            headers: {'x-set-cookie': 'datadome=fresh; Max-Age=31536000; Path=/'});
      }, botCookie: () async => 'old');
      await api.like(5, 1);
      await api.like(5, 2);
      expect(seen, ['old', 'fresh']);
    });
  });

  test('failure log has path and status only, never secrets', () async {
    final api = build((r) =>
        http.Response('{"error":"bad OAuth 2-123456-789012-AbCdEfGh"}', 500));
    await expectLater(api.me(), throwsA(isA<ScChanged>()));
    final text = log();
    expect(text, contains('GET /me -> 500 [direct]'));
    expect(text, isNot(contains('client_id')));
    expect(text, isNot(contains(_id1)));
    expect(text, isNot(contains('tok')));
    expect(text, isNot(contains('AbCdEfGh')));
  });

  test('extracts client_id from the site bundles', () {
    expect(ClientIdProvider.findClientId('x,client_id:"$_id1",y'), _id1);
    expect(ClientIdProvider.findClientId('?client_id=$_id2&a'), _id2);
    expect(ClientIdProvider.findClientId('client_id:"short"'), isNull);
  });

  test('sends OAuth header and client_id', () async {
    late http.Request seen;
    final api = build((r) {
      seen = r;
      return http.Response(jsonEncode({'id': 7, 'username': 'me'}), 200);
    });
    final me = await api.me();
    expect(me.id, 7);
    expect(seen.headers['Authorization'], 'OAuth tok');
    expect(seen.url.queryParameters['client_id'], _id1);
  });

  test('401 refetches client_id once and retries', () async {
    final api = build((r) {
      if (r.url.queryParameters['client_id'] == _id1) {
        siteVersion = 2;
        return http.Response('', 401);
      }
      return http.Response(jsonEncode({'id': 1, 'username': 'u'}), 200);
    });
    await api.me();
    expect(calls, ['/me?cid=$_id1', '/me?cid=$_id2']);
  });

  test('401 twice means expired token', () async {
    final api = build((r) => http.Response('', 401));
    await expectLater(api.me(), throwsA(isA<ScAuthExpired>()));
    expect(calls.length, 2);
  });

  test('403 and broken shapes become ScChanged', () async {
    expect(build((r) => http.Response('', 403)).me(),
        throwsA(isA<ScChanged>()));
    expect(build((r) => http.Response('<html>', 200)).me(),
        throwsA(isA<ScChanged>()));
    expect(build((r) => http.Response('{"collection": 5}', 200)).trackLikes(1),
        throwsA(isA<ScChanged>()));
  });

  test('likes page parses tracks and next_href', () async {
    final api = build((r) => http.Response(
        jsonEncode({
          'collection': [
            {'track': _trackJson(1)},
            {'playlist': {}},
            {'track': _trackJson(2)},
          ],
          'next_href': 'https://api-v2.soundcloud.com/users/5/track_likes?offset=abc',
        }),
        200));
    final page = await api.trackLikes(5);
    expect(page.tracks.map((t) => t.id), [1, 2]);
    expect(page.nextHref, contains('offset=abc'));
  });

  test('ranks transcodings: aac hls first, encrypted skipped', () {
    Transcoding t(String protocol, String mime, {bool snipped = false}) =>
        Transcoding(
            url: 'u/$protocol/$mime',
            protocol: protocol,
            mimeType: mime,
            snipped: snipped);
    final ranked = ScApi.rankTranscodings([
      t('ctr-encrypted-hls', 'audio/mp4; codecs="mp4a.40.2"'),
      t('cbc-encrypted-hls', 'audio/mp4'),
      t('progressive', 'audio/mpeg'),
      t('hls', 'audio/mpegurl'),
      t('hls', 'audio/mpeg'),
      t('hls', 'audio/mp4; codecs="mp4a.40.2"'),
    ]);
    expect(ranked.map((e) => '${e.protocol} ${e.mimeType}'), [
      'hls audio/mp4; codecs="mp4a.40.2"',
      'hls audio/mpeg',
      'progressive audio/mpeg',
      'hls audio/mpegurl',
    ]);
    final resume = ScApi.rankTranscodings(ranked, preferProgressive: true);
    expect(resume.first.protocol, 'progressive');
  });

  test('resolveStream prefers a progressive transcoding when asked', () async {
    final api = build((r) {
      if (r.url.path.contains('/media/prog')) {
        return http.Response(jsonEncode({'url': 'https://cdn/x.mp3'}), 200);
      }
      if (r.url.path.contains('/media/aac')) {
        return http.Response(jsonEncode({'url': 'https://cdn/x.m3u8'}), 200);
      }
      return http.Response('', 500);
    });
    final track = Track.fromJson(_trackJson(1));
    final hls = await api.resolveStream(track);
    expect(hls.protocol, 'hls');
    expect(hls.url, 'https://cdn/x.m3u8');
    final prog = await api.resolveStream(track, preferProgressive: true);
    expect(prog.protocol, 'progressive');
    expect(prog.url, 'https://cdn/x.mp3');
  });

  test('resolveStream falls back to the next transcoding', () async {
    final api = build((r) {
      if (r.url.path.contains('/media/aac')) return http.Response('', 404);
      if (r.url.path.contains('/media/mp3')) {
        expect(r.url.queryParameters['track_authorization'], 'auth');
        return http.Response(jsonEncode({'url': 'https://cdn/x.m3u8'}), 200);
      }
      return http.Response('', 500);
    });
    final stream = await api.resolveStream(Track.fromJson(_trackJson(1)));
    expect(stream.url, 'https://cdn/x.m3u8');
  });

  test('stale track_authorization: the track is fetched once more, then the stream opens',
      () async {
    final fresh = _trackJson(1)..['track_authorization'] = 'fresh';
    final api = build((r) {
      if (r.url.path == '/tracks/1') return http.Response(jsonEncode(fresh), 200);
      if (r.url.path.startsWith('/media/')) {
        return r.url.queryParameters['track_authorization'] == 'fresh'
            ? http.Response(jsonEncode({'url': 'https://cdn/y.m3u8'}), 200)
            : http.Response('', 403);
      }
      return http.Response('', 500);
    });
    final stream = await api.resolveStream(Track.fromJson(_trackJson(1)));
    expect(stream.url, 'https://cdn/y.m3u8');
    expect(calls.where((c) => c.startsWith('/tracks/1?')), hasLength(1));
  });

  test('a stream that never resolves is a load failure, not an unplayable track',
      () async {
    final api = build((r) {
      if (r.url.path == '/tracks/1') {
        return http.Response(jsonEncode(_trackJson(1)), 200);
      }
      return http.Response('', 404);
    });
    await expectLater(api.resolveStream(Track.fromJson(_trackJson(1))),
        throwsA(isA<ScStreamFailed>()));
    expect(friendlyError(const ScStreamFailed()), "Couldn't load this track");
  });

  test('encrypted-only track is unplayable', () async {
    final json = _trackJson(1);
    json['media'] = {
      'transcodings': [
        {
          'url': 'https://api-v2.soundcloud.com/media/enc',
          'format': {'protocol': 'ctr-encrypted-hls', 'mime_type': 'audio/mp4'}
        }
      ]
    };
    final api = build((r) => http.Response('', 500));
    expect(api.resolveStream(Track.fromJson(json)),
        throwsA(isA<ScUnplayable>()));
  });

  test('status mapping and friendly texts', () {
    expect(ScApi.errorForStatus(401), isA<ScAuthExpired>());
    expect(ScApi.errorForStatus(403), isA<ScChanged>());
    expect(ScApi.errorForStatus(429), isA<ScChanged>());
    expect(const ScAuthExpired().message, 'Session expired');
    expect(const ScChanged().message, 'SoundCloud changed something');
    expect(const ScNetworkError().message, 'No connection');
  });

  test('network failure becomes ScNetworkError', () async {
    final client = MockClient((r) async => throw http.ClientException('down'));
    final api = ScApi(
      client: client,
      clientId: ClientIdProvider(client: client, store: MemoryKeyValueStore()),
      readToken: () async => 'tok',
      minGap: Duration.zero,
    );
    expect(api.me(), throwsA(isA<ScNetworkError>()));
  });

  test('unavailable reasons and preview detection', () {
    final blocked = _trackJson(1)..['policy'] = 'BLOCK';
    expect(Track.fromJson(blocked).unavailable, Unavailable.removed);
    final goPlus = _trackJson(2)
      ..['policy'] = 'BLOCK'
      ..['monetization_model'] = 'SUB_HIGH_TIER';
    expect(Track.fromJson(goPlus).unavailable, Unavailable.goPlusOnly);
    final encrypted = _trackJson(3)
      ..['media'] = {
        'transcodings': [
          {'url': 'x', 'format': {'protocol': 'ctr-encrypted-hls', 'mime_type': 'audio/mp4'}}
        ]
      };
    expect(Track.fromJson(encrypted).unavailable, Unavailable.goPlusOnly);
    final snip = _trackJson(4)..['policy'] = 'SNIP';
    expect(Track.fromJson(snip).isPreviewOnly, isTrue);
    expect(Track.fromJson(snip).unavailable, isNull);
    expect(Track.fromJson(_trackJson(5)).unavailable, isNull);
  });
}

Map<String, dynamic> _trackJson(int id) => {
      'id': id,
      'title': 'Track $id',
      'duration': 1000,
      'track_authorization': 'auth',
      'user': {'username': 'artist'},
      'media': {
        'transcodings': [
          {
            'url': 'https://api-v2.soundcloud.com/media/aac',
            'format': {
              'protocol': 'hls',
              'mime_type': 'audio/mp4; codecs="mp4a.40.2"'
            }
          },
          {
            'url': 'https://api-v2.soundcloud.com/media/mp3',
            'format': {'protocol': 'hls', 'mime_type': 'audio/mpeg'}
          },
          {
            'url': 'https://api-v2.soundcloud.com/media/prog',
            'format': {'protocol': 'progressive', 'mime_type': 'audio/mpeg'}
          },
        ]
      },
    };

class _FakeWeb implements WebWriter {
  _FakeWeb(this.result);

  final WebWriteResult? result;
  final calls = <(String, Uri, String)>[];

  @override
  Future<WebWriteResult> write(String method, Uri url, String token) async {
    calls.add((method, url, token));
    final r = result;
    if (r == null) throw StateError('webview gone');
    return r;
  }
}
