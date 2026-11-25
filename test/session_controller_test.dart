import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scglow/app/session_controller.dart';
import 'package:scglow/core/client_id_provider.dart';
import 'package:scglow/core/diag_log.dart';
import 'package:scglow/core/errors.dart';
import 'package:scglow/core/json_store.dart';
import 'package:scglow/core/sc_api.dart';
import 'package:scglow/core/storage.dart';
import 'package:scglow/core/web_session.dart';

const _token = '2-123456-7890123-AbCdEfGhIjKl';
const _newToken = '2-123456-7890123-NewNewNewNew';

class _FakeWeb extends WebSession {
  int cleared = 0;

  @override
  Future<void> clearCookies() async => cleared++;
}

http.Response _ok() => http.Response(
  jsonEncode({'id': 5, 'username': 'listener'}),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _plain401([String body = '{"error":"invalid_token"}']) =>
    http.Response(body, 401);

http.Response _bot401() =>
    http.Response('{"url":"https://geo.captcha-delivery.com/c"}', 401, headers: {'x-datadome': 'protected'});

http.Response _bot403() => http.Response(
  '{"url":"https://geo.captcha-delivery.com/captcha/?initialCid=x"}',
  403,
);

void main() {
  late List<Object> me;
  late int meRequests;
  late List<Duration> slept;
  late DateTime now;
  late int warmUps;
  late TokenStore tokens;
  late MemoryJsonStore store;
  late Directory logDir;
  Completer<void>? sleepGate;
  late _FakeWeb web;
  late List<WebToken?> webTokens;
  late int webLoads;
  late List<String?> meAuth;

  // One `me` attempt with a 401 makes two requests (the client_id refresh retry).
  void attempt(Object response) {
    if (response is http.Response && response.statusCode == 401) {
      me.addAll([response, response]);
    } else {
      me.add(response);
    }
  }

  SessionController build() {
    final client = MockClient((r) async {
      if (r.url.host == 'api-v2.soundcloud.com' && r.url.path == '/me') {
        meRequests++;
        meAuth.add(r.headers['Authorization']);
        final next = me.isEmpty ? _ok() : me.removeAt(0);
        if (next is Exception) throw next;
        return next as http.Response;
      }
      if (r.url.host == 'soundcloud.com') {
        return http.Response(
          '<script crossorigin src="https://a-v2.sndcdn.com/assets/1-y.js"></script>',
          200,
        );
      }
      return http.Response('client_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"', 200);
    });
    final api = ScApi(
      client: client,
      clientId: ClientIdProvider(client: client, store: MemoryKeyValueStore()),
      readToken: tokens.read,
      minGap: Duration.zero,
    );
    return SessionController(
      api: api,
      tokens: tokens,
      store: store,
      web: web,
      webToken: () async {
        webLoads++;
        return webTokens.isEmpty ? null : webTokens.removeAt(0);
      },
      warmBotCheck: () async {
        warmUps++;
        return true;
      },
      sleep: (d) async {
        slept.add(d);
        now = now.add(d);
        await sleepGate?.future;
      },
      clock: () => now,
    );
  }

  String log() => File(DiagLog.path).readAsStringSync();

  // Without a cached user, start() awaits its own `me` check before returning.
  Future<SessionController> ready() async {
    await store.delete('user');
    final s = build();
    await s.start();
    expect(s.state, SessionState.ready);
    meRequests = 0;
    now = now.add(SessionController.quietAfterOk + const Duration(seconds: 1));
    return s;
  }

  setUp(() async {
    me = [];
    meRequests = 0;
    slept = [];
    now = DateTime.utc(2026, 11, 23, 12);
    warmUps = 0;
    sleepGate = null;
    web = _FakeWeb();
    webTokens = [];
    webLoads = 0;
    meAuth = [];
    tokens = TokenStore(MemoryKeyValueStore());
    await tokens.save(_token);
    store = MemoryJsonStore();
    logDir = Directory.systemTemp.createTempSync('scglow_session');
    DiagLog.pathOverride = '${logDir.path}/log.txt';
  });

  tearDown(() {
    DiagLog.pathOverride = null;
    logDir.deleteSync(recursive: true);
  });

  test(
    'one 401 is not enough: me is checked again after 30 s and the token stays',
    () async {
      final s = await ready();
      attempt(_plain401());
      attempt(_ok());
      await s.reportAuthProblem('library.refresh', const ScAuthExpired());
      expect(slept, [SessionController.recheckDelay]);
      expect(s.state, SessionState.ready);
      expect(await tokens.read(), _token);
      expect(log(), contains('checking again in 30s'));
      expect(log(), contains('decision: kept (library.refresh; me ok)'));
    },
  );

  test(
    'two plain 401s 30 s apart wipe the token and show Session expired',
    () async {
      final s = await ready();
      attempt(_plain401());
      attempt(_plain401());
      await s.reportAuthProblem('player.resolve');
      expect(slept, [SessionController.recheckDelay]);
      expect(s.state, SessionState.expired);
      expect(await tokens.read(), isNull);
      expect(meRequests, 4);
      expect(log(), contains('decision: wiped (player.resolve'));
      expect(log(), contains('clientIdRefreshed=true'));
    },
  );

  test(
    'a 401 with DataDome signs keeps the token and warms the cookie once',
    () async {
      final s = await ready();
      attempt(_bot401());
      await s.reportAuthProblem('details.load');
      expect(slept, isEmpty);
      expect(warmUps, 1);
      expect(s.state, SessionState.ready);
      expect(await tokens.read(), _token);
      expect(log(), contains('botCheck=true'));
      expect(log(), isNot(contains('decision: wiped')));
    },
  );

  test('a plain 401 followed by a bot check keeps the token', () async {
    final s = await ready();
    attempt(_plain401());
    attempt(_bot401());
    await s.reportAuthProblem('library.like');
    expect(slept, hasLength(1));
    expect(warmUps, 1);
    expect(await tokens.read(), _token);
    expect(s.state, SessionState.ready);
  });

  test(
    '403 captcha, 429 and network errors never wipe; only 403 warms up',
    () async {
      for (final (response, warm) in [
        (_bot403(), 1),
        (http.Response('slow down', 429), 0),
        (const SocketException('down'), 0),
      ]) {
        warmUps = 0;
        slept = [];
        final s = await ready();
        attempt(response);
        await s.reportAuthProblem('library.refresh');
        expect(s.state, SessionState.ready, reason: '$response');
        expect(await tokens.read(), _token, reason: '$response');
        expect(slept, isEmpty, reason: '$response');
        expect(warmUps, warm, reason: '$response');
      }
      expect(log(), isNot(contains('decision: wiped')));
    },
  );

  test(
    'several reports at once lead to one check, and none right after it',
    () async {
      final s = await ready();
      attempt(_ok());
      await Future.wait([
        s.reportAuthProblem('library.refresh'),
        s.reportAuthProblem('details.load'),
        s.reportAuthProblem('player.resolve'),
      ]);
      expect(meRequests, 1);
      await s.reportAuthProblem('library.like');
      expect(meRequests, 1);
      expect(log(), contains('me was ok'));
    },
  );

  test('a missing token at startup still means signed out', () async {
    await tokens.clear();
    final s = build();
    await s.start();
    expect(s.state, SessionState.signedOut);
    expect(meRequests, 0);
  });

  test(
    'startup 403 keeps the token and shows the changed screen as before',
    () async {
      await store.write('user', {'id': 5, 'username': 'listener'});
      final s = build();
      attempt(_bot403());
      await s.start();
      await s.reportAuthProblem('startup-join');
      expect(s.state, SessionState.changed);
      expect(s.changedStatus, 403);
      expect(await tokens.read(), _token);
    },
  );

  test('logging out during the 30 s wait cancels the pending wipe', () async {
    final s = await ready();
    attempt(_plain401());
    attempt(_plain401());
    sleepGate = Completer<void>();
    final check = s.reportAuthProblem('library.refresh');
    await Future<void>.delayed(Duration.zero);
    await pumpUntil(() => slept.isNotEmpty);
    await s.logout();
    sleepGate!.complete();
    await check;
    expect(s.state, SessionState.signedOut);
    expect(meRequests, 2);
  });

  test('the logged body excerpt is short and has no token', () async {
    final s = await ready();
    final body = 'OAuth $_token ${'x' * 1000}';
    attempt(_plain401(body));
    attempt(_ok());
    await s.reportAuthProblem('library.refresh');
    expect(log(), isNot(contains(_token)));
    expect(log(), contains('[hidden]'));
    expect(ScApi.excerptOf(body).length, lessThanOrEqualTo(200));
  });

  test(
    'before wiping, a newer token from the web session is verified, saved and kept',
    () async {
      final s = await ready();
      webTokens = [WebToken(_newToken, expires: DateTime.utc(2027, 1, 5))];
      attempt(_plain401());
      attempt(_plain401());
      attempt(_ok());
      attempt(_ok());
      await s.reportAuthProblem('details.load', const ScAuthExpired());
      expect(s.state, SessionState.ready);
      expect(await tokens.read(), _newToken);
      expect(meAuth.last, 'OAuth $_newToken');
      expect(web.cleared, 0);
      expect(log(), contains('auth: token renewed from web session (details.load'));
      expect(log(), contains('cookie expires 2027-01-05'));
      expect(log(), isNot(contains('wiped')));
      expect(log(), isNot(contains(_newToken)));
    },
  );

  test(
    'a forced wipe keeps web cookies and logs the token age; logout clears them',
    () async {
      store = MemoryJsonStore();
      final s = build();
      attempt(_ok());
      await s.onSignedIn(_token);
      expect(s.state, SessionState.ready);
      now = now.add(const Duration(hours: 24, minutes: 3));
      webTokens = [const WebToken(_token)];
      attempt(_plain401());
      attempt(_plain401());
      await s.reportAuthProblem('details.load', const ScAuthExpired());
      expect(s.state, SessionState.expired);
      expect(await tokens.read(), isNull);
      expect(web.cleared, 0);
      expect(log(), contains('web token unchanged (token age 24h03m'));
      expect(log(), contains('no bot check; token age 24h03m)'));
      await s.logout();
      expect(web.cleared, 1);
    },
  );

  test('a rejected web token puts the old one back', () async {
    final s = await ready();
    webTokens = [const WebToken(_newToken)];
    attempt(_plain401());
    expect(await s.renewFromWeb('every 6h'), isFalse);
    expect(await tokens.read(), _token);
    expect(s.state, SessionState.ready);
    expect(log(), contains('renew (every 6h): web token rejected'));
  });

  test('an existing token without a record is dated from first sight', () async {
    final s = await ready();
    expect(log(), contains('auth: token first seen; its age is counted from now'));
    now = now.add(const Duration(hours: 2));
    webTokens = [const WebToken(_token)];
    await s.renewFromWeb('every 6h');
    expect(log(), contains('web token unchanged (token age 2h00m since first seen'));
  });

  test('renewal on window show is throttled to once per 5 minutes', () async {
    final s = await ready();
    await s.renewFromWeb('window shown', throttled: true);
    await s.renewFromWeb('window shown', throttled: true);
    expect(webLoads, 1);
    now = now.add(SessionController.renewOnShowGap);
    await s.renewFromWeb('window shown', throttled: true);
    expect(webLoads, 2);
    expect(log(), contains('renew (window shown): no web token'));
  });
}

Future<void> pumpUntil(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
