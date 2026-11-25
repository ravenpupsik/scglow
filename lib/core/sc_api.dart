import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'client_id_provider.dart';
import 'diag_log.dart';
import 'errors.dart';
import 'models.dart';

class ScApi {
  ScApi({
    required http.Client client,
    required ClientIdProvider clientId,
    required Future<String?> Function() readToken,
    Duration minGap = const Duration(milliseconds: 250),
    WebWriter? webWriter,
    Future<String?> Function()? readBotCookie,
  })  : _client = client,
        _clientId = clientId,
        _readToken = readToken,
        _minGap = minGap,
        _webWriter = webWriter,
        _readBotCookie = readBotCookie;

  static const _base = 'https://api-v2.soundcloud.com';

  final http.Client _client;
  final ClientIdProvider _clientId;
  final Future<String?> Function() _readToken;
  final Duration _minGap;
  final WebWriter? _webWriter;
  final Future<String?> Function()? _readBotCookie;

  String? _botCookie;

  Future<void> _gate = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<ScUser> me() async {
    final json = await _getJson(Uri.parse('$_base/me'));
    return _parse(() => ScUser.fromJson(json as Map<String, dynamic>));
  }

  Future<LikesPage> trackLikes(int userId,
      {String? nextHref, int limit = 100}) async {
    final uri = nextHref != null
        ? Uri.parse(nextHref)
        : Uri.parse('$_base/users/$userId/track_likes').replace(
            queryParameters: {'limit': '$limit', 'linked_partitioning': '1'});
    final json = await _getJson(uri);
    return _parse(() {
      final map = json as Map<String, dynamic>;
      final items = <LikedTrack>[];
      for (final item in (map['collection'] as List)) {
        final m = item as Map;
        final t = m['track'];
        if (t is! Map<String, dynamic>) continue;
        final at = DateTime.tryParse((m['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        items.add(LikedTrack(Track.fromJson(t), at));
      }
      return LikesPage(items: items, nextHref: map['next_href'] as String?);
    });
  }

  Future<List<Playlist>> playlists(int userId) async {
    final out = <int, Playlist>{};
    Future<void> collect(String path, Playlist? Function(Map) pick) async {
      String? next = Uri.parse('$_base$path').replace(queryParameters: {
        'limit': '50',
        'linked_partitioning': '1',
        'representation': 'mini',
      }).toString();
      var pages = 0;
      while (next != null && pages < 10) {
        final json = await _getJson(Uri.parse(next));
        final page = _parse(() {
          final map = json as Map<String, dynamic>;
          final list = <Playlist>[];
          for (final item in (map['collection'] as List).whereType<Map>()) {
            final p = pick(item);
            if (p != null) list.add(p);
          }
          return (list, map['next_href'] as String?);
        });
        for (final p in page.$1) {
          out.putIfAbsent(p.id, () => p);
        }
        next = page.$2;
        pages++;
      }
    }

    await collect('/users/$userId/playlists',
        (m) => Playlist.fromJson(m.cast<String, dynamic>()));
    await collect('/users/$userId/playlist_likes', (m) {
      final p = m['playlist'];
      return p is Map ? Playlist.fromJson(p.cast<String, dynamic>()) : null;
    });
    return out.values.toList();
  }

  Future<PlaylistPage> playlist(int id) async {
    final json = await _getJson(Uri.parse('$_base/playlists/$id'));
    final (pl, raw) = _parse(() {
      final map = json as Map<String, dynamic>;
      final tracks = ((map['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((t) => Track.fromJson(t.cast<String, dynamic>()))
          .toList();
      return (Playlist.fromJson(map), tracks);
    });
    final stubs = raw.where((t) => t.isStub).map((t) => t.id).toList();
    final filled = <int, Track>{for (final t in raw.where((t) => !t.isStub)) t.id: t};
    for (var i = 0; i < stubs.length; i += 50) {
      final chunk = stubs.sublist(i, i + 50 > stubs.length ? stubs.length : i + 50);
      for (final t in await tracksByIds(chunk)) {
        filled[t.id] = t;
      }
    }
    final tracks = [
      for (final t in raw)
        if (filled[t.id] != null) filled[t.id]! else t,
    ];
    return PlaylistPage(
      playlist: pl.copyWith(trackIds: raw.map((t) => t.id).toList()),
      tracks: tracks,
    );
  }

  Future<List<Track>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final json = await _getJson(Uri.parse('$_base/tracks')
        .replace(queryParameters: {'ids': ids.join(',')}));
    return _parse(() => (json as List)
        .whereType<Map>()
        .map((t) => Track.fromJson(t.cast<String, dynamic>()))
        .toList());
  }

  Future<Track> track(int id) async {
    final json = await _getJson(Uri.parse('$_base/tracks/$id'));
    return _parse(() => Track.fromJson(json as Map<String, dynamic>));
  }

  Future<List<Track>> related(int trackId, {int limit = 20}) async {
    final json = await _getJson(Uri.parse('$_base/tracks/$trackId/related')
        .replace(queryParameters: {'limit': '$limit'}));
    return _parse(() => ((json as Map)['collection'] as List)
        .whereType<Map>()
        .map((t) => Track.fromJson(t.cast<String, dynamic>()))
        .toList());
  }

  Future<List<TrackComment>> comments(int trackId, {int maxPages = 3}) async {
    final out = <TrackComment>[];
    String? next = Uri.parse('$_base/tracks/$trackId/comments').replace(
      queryParameters: {
        'sort': 'timestamp',
        'threaded': '0',
        'filter_replies': '1',
        'limit': '200',
        'linked_partitioning': '1',
      },
    ).toString();
    var pages = 0;
    while (next != null && pages < maxPages) {
      final json = await _getJson(Uri.parse(next));
      final page = _parse(() {
        final map = json as Map<String, dynamic>;
        final list = (map['collection'] as List)
            .whereType<Map>()
            .map((c) => TrackComment.fromJson(c.cast<String, dynamic>()))
            .toList();
        return (list, map['next_href'] as String?);
      });
      out.addAll(page.$1);
      next = page.$2;
      pages++;
    }
    final timed = out.where((c) => c.atMs != null).toList()
      ..sort((a, b) => a.atMs!.compareTo(b.atMs!));
    return [...timed, ...out.where((c) => c.atMs == null)];
  }

  Future<void> like(int userId, int trackId) =>
      _write('PUT', Uri.parse('$_base/users/$userId/track_likes/$trackId'));

  Future<void> unlike(int userId, int trackId) =>
      _write('DELETE', Uri.parse('$_base/users/$userId/track_likes/$trackId'));

  Future<Track> resolveUrl(String permalinkUrl) async {
    final json = await _getJson(Uri.parse('$_base/resolve')
        .replace(queryParameters: {'url': permalinkUrl}));
    return _parse(() => Track.fromJson(json as Map<String, dynamic>));
  }

  Future<ResolvedStream> resolveStream(Track track) async {
    var t = track;
    var fresh = false;
    if (t.transcodings.isEmpty || t.trackAuthorization == null) {
      t = await this.track(track.id);
      fresh = true;
    }
    final first = await _streamOf(t);
    if (first != null) return first;
    // track_authorization from an older listing may have expired; fetch the track once more.
    if (!fresh) {
      DiagLog.write('stream lookup failed for ${track.id}; refetching the track once');
      final again = await _streamOf(await this.track(track.id));
      if (again != null) return again;
    }
    DiagLog.write('stream lookup failed for ${track.id}');
    throw const ScStreamFailed();
  }

  Future<ResolvedStream?> _streamOf(Track t) async {
    if (t.isBlocked) {
      throw ScUnplayable('Not available', t.unavailable ?? Unavailable.removed);
    }
    final candidates = rankTranscodings(t.transcodings);
    if (candidates.isEmpty) {
      throw const ScUnplayable(
          'Encrypted or no playable stream', Unavailable.goPlusOnly);
    }
    for (final c in candidates) {
      try {
        final uri = Uri.parse(c.url).replace(queryParameters: {
          ...Uri.parse(c.url).queryParameters,
          if (t.trackAuthorization != null)
            'track_authorization': t.trackAuthorization!,
        });
        final json = await _getJson(uri, softFail: true);
        final url = (json as Map?)?['url'];
        if (url is String && url.isNotEmpty) {
          return ResolvedStream(url: url, isPreview: c.snipped);
        }
      } on _SoftFail {
        continue;
      }
    }
    return null;
  }

  static List<Transcoding> rankTranscodings(List<Transcoding> list) {
    int score(Transcoding t) {
      final mime = t.mimeType.toLowerCase();
      final base = switch (t.protocol) {
        'hls' when mime.contains('mp4a') || mime.contains('aac') => 0,
        'hls' when mime.startsWith('audio/mpeg') && !mime.contains('mpegurl') => 1,
        'progressive' => 2,
        'hls' => 3,
        _ => 99,
      };
      return base + (t.snipped ? 10 : 0);
    }

    final usable = list
        .where((t) => t.url.isNotEmpty && !t.isEncrypted && score(t) < 99)
        .toList();
    final indexed = usable.asMap().entries.toList()
      ..sort((a, b) {
        final s = score(a.value).compareTo(score(b.value));
        return s != 0 ? s : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  static ScException errorForStatus(int status) => switch (status) {
        401 => const ScAuthExpired(),
        403 => const ScChanged('HTTP 403', 403),
        429 => const ScChanged('too many requests, wait a bit', 429),
        _ => ScChanged('HTTP $status', status),
      };

  Future<Object?> _getJson(Uri uri, {bool softFail = false}) async {
    final res = await _withAuthRetry('GET', uri, (id) => _send('GET', uri, id));
    if (res.statusCode != 200) {
      if (softFail) throw const _SoftFail();
      throw errorForStatus(res.statusCode);
    }
    try {
      return jsonDecode(res.body);
    } on FormatException {
      throw const ScChanged('unexpected response');
    }
  }

  Future<void> _write(String method, Uri uri) async {
    final res = await _withAuthRetry(
        method, uri, (id) => _send(method, uri, id, write: true));
    if (_ok(res.statusCode)) return;
    // DataDome may block writes with 403; retry once through the signed-in web session.
    final web = _webWriter;
    if (web == null || res.statusCode != 403) {
      throw errorForStatus(res.statusCode);
    }
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      throw ScAuthExpired(AuthFailure(
          method: method, path: uri.path, status: 0, via: 'no token'));
    }
    final full = await _writeUri(uri, await _clientId.get());
    WebWriteResult r;
    try {
      r = await web.write(method, full, token);
    } catch (e) {
      DiagLog.write('$method ${uri.path} webview write failed: '
          '${DiagLog.scrub(e.runtimeType.toString())}');
      throw errorForStatus(res.statusCode);
    }
    if (_ok(r.status)) return;
    DiagLog.apiFailure(
        method: method, uri: uri, status: r.status, body: r.body, via: 'webview');
    if (r.status == 401) {
      throw ScAuthExpired(AuthFailure(
        method: method,
        path: uri.path,
        status: 401,
        botCheck: looksLikeBotCheck(401, const {}, r.body),
        excerpt: excerptOf(r.body),
        via: 'webview',
      ));
    }
    throw errorForStatus(r.status == 0 ? res.statusCode : r.status);
  }

  static bool _ok(int status) => status >= 200 && status < 300;

  static bool isBotCheck(http.Response res) =>
      res.statusCode == 403 &&
      (res.headers.containsKey('x-datadome') ||
          res.body.contains('captcha-delivery.com'));

  // Broader than isBotCheck: used to decide whether a 401 may be DataDome rather than an expired token.
  static bool looksLikeBotCheck(
          int status, Map<String, String> headers, String body) =>
      status == 403 || body.contains('captcha-delivery.com');

  static String excerptOf(String body) {
    final s = DiagLog.scrub(body);
    return s.length > 200 ? s.substring(0, 200) : s;
  }

  Future<Uri> _writeUri(Uri uri, String clientId) async {
    final version = await _clientId.appVersion();
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'client_id': clientId,
      'app_version': ?version,
      'app_locale': 'en',
    });
  }

  Future<String?> _currentBotCookie() async {
    if (_botCookie != null) return _botCookie;
    try {
      final v = await _readBotCookie?.call();
      if (v != null && v.isNotEmpty) _botCookie = v;
    } catch (_) {}
    return _botCookie;
  }

  void _takeBotCookie(http.Response res) {
    // api-v2 hands out a refreshed DataDome cookie in X-Set-Cookie.
    final raw = res.headers['x-set-cookie'];
    if (raw == null) return;
    final m = RegExp(r'datadome=([^;]+)').firstMatch(raw);
    if (m != null) _botCookie = m.group(1);
  }

  Future<http.Response> _withAuthRetry(String method, Uri uri,
      Future<http.Response> Function(String clientId) send) async {
    var res = await send(await _clientId.get());
    // A 401 first may be a stale client_id; the session decides whether a second one means expiry.
    if (res.statusCode == 401) {
      res = await send(await _clientId.refresh());
      if (res.statusCode == 401) {
        throw ScAuthExpired(AuthFailure(
          method: method,
          path: uri.path,
          status: 401,
          botCheck: looksLikeBotCheck(401, res.headers, res.body),
          excerpt: excerptOf(res.body),
          clientIdRefreshed: true,
        ));
      }
    }
    return res;
  }

  Future<http.Response> _send(String method, Uri uri, String clientId,
      {bool write = false}) async {
    await _throttle();
    final token = await _readToken();
    final full = write
        ? await _writeUri(uri, clientId)
        : uri.replace(queryParameters: {
            ...uri.queryParameters,
            'client_id': clientId,
          });
    final bot = write ? await _currentBotCookie() : null;
    final headers = {
      'User-Agent': browserUserAgent,
      'Accept': 'application/json',
      'Origin': 'https://soundcloud.com',
      'Referer': 'https://soundcloud.com/',
      if (token != null && token.isNotEmpty) 'Authorization': 'OAuth $token',
      'X-Datadome-ClientId': ?bot,
    };
    try {
      final req = http.Request(method, full)..headers.addAll(headers);
      final streamed =
          await _client.send(req).timeout(const Duration(seconds: 20));
      final res = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      _takeBotCookie(res);
      if (!_ok(res.statusCode)) {
        if (isBotCheck(res)) _botCookie = null;
        DiagLog.apiFailure(
            method: method, uri: uri, status: res.statusCode, body: res.body);
      }
      return res;
    } on SocketException {
      _logNetwork(method, uri, 'socket');
      throw const ScNetworkError();
    } on TimeoutException {
      _logNetwork(method, uri, 'timeout');
      throw const ScNetworkError();
    } on http.ClientException {
      _logNetwork(method, uri, 'client');
      throw const ScNetworkError();
    } on HandshakeException {
      _logNetwork(method, uri, 'tls');
      throw const ScNetworkError();
    }
  }

  static void _logNetwork(String method, Uri uri, String kind) =>
      DiagLog.write('$method ${uri.path} -> network error ($kind)');

  Future<void> _throttle() async {
    final previous = _gate;
    final done = Completer<void>();
    _gate = done.future;
    await previous;
    final wait = _minGap - DateTime.now().difference(_last);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _last = DateTime.now();
    done.complete();
  }

  T _parse<T>(T Function() fn) {
    try {
      return fn();
    } on ScException {
      rethrow;
    } catch (_) {
      throw const ScChanged('unexpected data format');
    }
  }
}

class _SoftFail implements Exception {
  const _SoftFail();
}

abstract class WebWriter {
  Future<WebWriteResult> write(String method, Uri url, String token);
}

class WebWriteResult {
  const WebWriteResult(this.status, [this.body = '']);

  final int status;
  final String body;
}
