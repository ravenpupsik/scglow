import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/diag_log.dart';
import '../core/errors.dart';
import '../core/json_store.dart';
import '../core/models.dart';
import '../core/sc_api.dart';
import '../core/storage.dart';
import '../core/web_session.dart';

enum SessionState { loading, signedOut, expired, changed, ready }

class SessionController extends ChangeNotifier {
  SessionController({
    required ScApi api,
    required TokenStore tokens,
    required JsonStore store,
    WebSession? web,
    Future<bool> Function()? warmBotCheck,
    Future<WebToken?> Function()? webToken,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  }) : _api = api,
       _tokens = tokens,
       _store = store,
       _web = web,
       _warmBotCheck = warmBotCheck,
       _webToken = webToken,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  static const _userKey = 'user';
  static const _tokenMetaKey = 'token_meta';

  static const renewEvery = Duration(hours: 6);

  static const renewOnShowGap = Duration(minutes: 5);

  static const recheckDelay = Duration(seconds: 30);

  static const quietAfterOk = Duration(seconds: 30);

  final ScApi _api;
  final TokenStore _tokens;
  final JsonStore _store;
  final WebSession? _web;
  final Future<bool> Function()? _warmBotCheck;
  final Future<WebToken?> Function()? _webToken;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;

  SessionState state = SessionState.loading;
  ScUser? user;

  bool offline = false;

  int? changedStatus;

  Future<void>? _check;
  DateTime? _okAt;
  int _generation = 0;
  Future<bool>? _renewing;
  DateTime? _renewedAt;
  Timer? _renewTimer;

  Future<void> start() async {
    _renewTimer ??= Timer.periodic(
        renewEvery, (_) => unawaited(renewFromWeb('every ${renewEvery.inHours}h')));
    _set(SessionState.loading);
    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      _set(SessionState.signedOut);
      return;
    }
    if (await _store.read(_tokenMetaKey) == null) {
      await _store.write(_tokenMetaKey, {
        'obtainedAt': _clock().toUtc().toIso8601String(),
        'firstSeen': true,
      });
      _log('token first seen; its age is counted from now');
    }
    final saved = await _store.read(_userKey);
    if (saved != null) {
      try {
        user = ScUser.fromJson(saved);
      } catch (_) {}
    }
    if (user != null) {
      _set(SessionState.ready);
      unawaited(_verify('startup', startup: true));
      return;
    }
    await _verify('startup', startup: true);
  }

  // Any 401 seen by a controller lands here; one shared `me` check decides whether to keep the token.
  Future<void> reportAuthProblem(String source, [ScAuthExpired? error]) {
    _log('problem from $source: ${error?.failure?.describe() ?? 'no details'}');
    if (state == SessionState.signedOut || state == SessionState.expired) {
      return Future.value();
    }
    final ok = _okAt;
    if (_check == null &&
        ok != null &&
        _clock().difference(ok) < quietAfterOk) {
      _log(
        'decision: kept ($source; me was ok ${_clock().difference(ok).inSeconds}s ago)',
      );
      return Future.value();
    }
    return _verify(source, startup: false);
  }

  Future<void> _verify(String source, {required bool startup}) {
    final running = _check;
    if (running != null) return running;
    final run = _runVerify(source, startup, _generation);
    _check = run;
    return run.whenComplete(() {
      if (identical(_check, run)) _check = null;
    });
  }

  Future<void> _runVerify(String source, bool startup, int gen) async {
    var r = await _me();
    if (gen != _generation) return;
    if (r is ScAuthExpired && !_bot(r)) {
      _log(
        'check ($source): ${_what(r)}; ${await _age()}; checking again in ${recheckDelay.inSeconds}s',
      );
      await _sleep(recheckDelay);
      if (gen != _generation) return;
      r = await _me();
      if (gen != _generation) return;
      if (r is ScAuthExpired && !_bot(r)) {
        _log('check ($source): ${_what(r)}');
        if (await _renewNow(source, gen)) {
          if (gen != _generation) return;
          r = await _me();
          if (gen != _generation) return;
        }
      }
      if (r is ScAuthExpired && !_bot(r)) {
        _log(
          'decision: wiped ($source; me 401 twice, ${recheckDelay.inSeconds}s apart, no bot check; ${await _age()})',
        );
        await _tokens.clear();
        _set(SessionState.expired);
        return;
      }
    }
    await _settle(source, startup, r);
  }

  // Proactive renewal (timer, window shown); skipped unless a session is in use.
  Future<bool> renewFromWeb(String source, {bool throttled = false}) {
    if (state != SessionState.ready && state != SessionState.changed) {
      return Future.value(false);
    }
    final last = _renewedAt;
    if (throttled &&
        last != null &&
        _clock().difference(last) < renewOnShowGap) {
      return Future.value(false);
    }
    return _renewNow(source, _generation);
  }

  Future<bool> _renewNow(String source, int gen) {
    final running = _renewing;
    if (running != null) return running;
    final run = _renew(source, gen);
    _renewing = run;
    return run.whenComplete(() {
      if (identical(_renewing, run)) _renewing = null;
    });
  }

  // Swaps in the site's newer token only if /me accepts it; otherwise the old one is put back.
  Future<bool> _renew(String source, int gen) async {
    final load = _webToken;
    if (load == null) return false;
    _renewedAt = _clock();
    WebToken? web;
    try {
      web = await load();
    } catch (_) {}
    if (gen != _generation) return false;
    final expires = web?.expires == null ? '' : '; cookie expires ${_date(web!.expires!)}';
    final old = await _tokens.read();
    if (web == null) {
      _log('renew ($source): no web token');
      return false;
    }
    if (web.value == old) {
      _log('renew ($source): web token unchanged (${await _age()}$expires)');
      return false;
    }
    await _tokens.save(web.value);
    final r = await _me();
    if (gen != _generation) return false;
    if (r is ScUser) {
      final age = await _age();
      await _markObtained();
      _okAt = _clock();
      _log('token renewed from web session ($source; old $age$expires)');
      return true;
    }
    if (old == null) {
      await _tokens.clear();
    } else {
      await _tokens.save(old);
    }
    _log('renew ($source): web token rejected (${r is ScException ? r.runtimeType : r})');
    return false;
  }

  Future<void> _markObtained() =>
      _store.write(_tokenMetaKey, {'obtainedAt': _clock().toUtc().toIso8601String()});

  Future<String> _age() async {
    final meta = await _store.read(_tokenMetaKey);
    final at = DateTime.tryParse('${meta?['obtainedAt']}');
    if (at == null) return 'token age unknown';
    final d = _clock().difference(at);
    final since = meta?['firstSeen'] == true ? ' since first seen' : '';
    return 'token age ${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}m$since';
  }

  static String _date(DateTime d) =>
      d.toUtc().toIso8601String().substring(0, 10);

  Future<void> _settle(String source, bool startup, Object r) async {
    switch (r) {
      case ScUser me:
        user = me;
        offline = false;
        changedStatus = null;
        _okAt = _clock();
        await _store.write(_userKey, me.toJson());
        _log('decision: kept ($source; me ok)');
        _set(SessionState.ready);
      case ScNetworkError():
        offline = true;
        _log('decision: kept ($source; network error)');
        if (startup || state == SessionState.loading) _set(SessionState.ready);
      case ScAuthExpired e:
        _log('check ($source): ${_what(e)}');
        final warmed = await _warm();
        _log(
          'decision: kept ($source; 401 with a bot check, warm-up ${warmed ? 'got' : 'no'} cookie)',
        );
        _keep(startup, 401);
      case ScChanged(status: final status):
        _log(
          'check ($source): me -> ${status ?? 'unexpected'}${status == 403 ? ' (bot check)' : ''}',
        );
        var note = '';
        if (status == 403) {
          note = ', warm-up ${await _warm() ? 'got' : 'no'} cookie';
        }
        _log('decision: kept ($source; me ${status ?? 'unexpected'}$note)');
        _keep(startup, status);
      default:
        _log('decision: kept ($source; ${r.runtimeType})');
        _keep(startup, null);
    }
  }

  void _keep(bool startup, int? status) {
    changedStatus = status;
    if (startup || state == SessionState.loading) {
      _set(user == null || startup ? SessionState.changed : SessionState.ready);
    }
  }

  Future<Object> _me() async {
    try {
      return await _api.me();
    } on ScException catch (e) {
      return e;
    }
  }

  Future<bool> _warm() async {
    final warm = _warmBotCheck;
    if (warm == null) return false;
    try {
      return await warm();
    } catch (_) {
      return false;
    }
  }

  static bool _bot(ScAuthExpired e) => e.failure?.botCheck ?? false;

  static String _what(ScAuthExpired e) =>
      'me ${e.failure?.describe() ?? '401'}';

  static void _log(String line) => DiagLog.write('auth: $line');

  Future<void> onSignedIn(String token) async {
    _generation++;
    _check = null;
    _okAt = null;
    await _tokens.save(token);
    await _markObtained();
    user = null;
    await start();
  }

  Future<void> logout() async {
    _generation++;
    _check = null;
    _okAt = null;
    await _tokens.clear();
    await _web?.clearCookies();
    await _store.delete(_userKey);
    await _store.delete(_tokenMetaKey);
    user = null;
    _set(SessionState.signedOut);
  }

  @override
  void dispose() {
    _renewTimer?.cancel();
    super.dispose();
  }

  void _set(SessionState s) {
    state = s;
    notifyListeners();
  }
}
