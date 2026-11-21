import 'dart:async';

import 'package:flutter/foundation.dart';

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
  })  : _api = api,
        _tokens = tokens,
        _store = store,
        _web = web;

  static const _userKey = 'user';

  final ScApi _api;
  final TokenStore _tokens;
  final JsonStore _store;
  final WebSession? _web;

  SessionState state = SessionState.loading;
  ScUser? user;

  bool offline = false;

  int? changedStatus;

  Future<void> start() async {
    _set(SessionState.loading);
    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      _set(SessionState.signedOut);
      return;
    }
    final saved = await _store.read(_userKey);
    if (saved != null) {
      try {
        user = ScUser.fromJson(saved);
      } catch (_) {}
    }
    if (user != null) {
      _set(SessionState.ready);
      unawaited(_verify());
      return;
    }
    await _verify();
  }

  Future<void> _verify() async {
    try {
      final me = await _api.me();
      user = me;
      offline = false;
      await _store.write(_userKey, me.toJson());
      _set(SessionState.ready);
    } on ScAuthExpired {
      await handleAuthExpired();
    } on ScNetworkError {
      offline = true;
      _set(SessionState.ready);
    } on ScChanged catch (e) {
      changedStatus = e.status;
      _set(SessionState.changed);
    }
  }

  Future<void> onSignedIn(String token) async {
    await _tokens.save(token);
    user = null;
    await start();
  }

  Future<void> logout() async {
    await _forget();
    await _store.delete(_userKey);
    user = null;
    _set(SessionState.signedOut);
  }

  Future<void> handleAuthExpired() async {
    if (state == SessionState.expired || state == SessionState.signedOut) {
      return;
    }
    await _forget();
    _set(SessionState.expired);
  }

  Future<void> _forget() async {
    await _tokens.clear();
    await _web?.clearCookies();
  }

  void _set(SessionState s) {
    state = s;
    notifyListeners();
  }
}
