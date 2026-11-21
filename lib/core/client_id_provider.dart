import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'storage.dart';

const browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class ClientIdProvider {
  ClientIdProvider({required http.Client client, required KeyValueStore store})
      : _client = client,
        _store = store;

  final http.Client _client;
  final KeyValueStore _store;
  static const _key = 'client_id';
  static const _versionKey = 'app_version';

  static final _scriptRe = RegExp(
      r'''<script[^>]+src=["'](https://a-v2\.sndcdn\.com/assets/[^"']+\.js)["']''');
  static final _clientIdRe = RegExp(r'client_id[:=]"?([a-zA-Z0-9]{32})');

  static final _versionRe = RegExp(r'__sc_version\s*=\s*"(\d+)"');

  String? _cached;
  String? _appVersion;

  Future<String?> appVersion() async {
    if (_appVersion != null) return _appVersion;
    final v = await _store.read(_versionKey);
    return (v == null || v.isEmpty) ? null : _appVersion = v;
  }

  Future<String> get() async {
    final cached = _cached ?? await _store.read(_key);
    if (cached != null && cached.isNotEmpty) return _cached = cached;
    return refresh();
  }

  Future<String> refresh() async {
    final id = await _extract();
    _cached = id;
    await _store.write(_key, id);
    return id;
  }

  static String? findAppVersion(String html) =>
      _versionRe.firstMatch(html)?.group(1);

  static List<String> findScriptUrls(String html) =>
      _scriptRe.allMatches(html).map((m) => m.group(1)!).toList();

  static String? findClientId(String js) => _clientIdRe.firstMatch(js)?.group(1);

  Future<String> _extract() async {
    final html = await _download('https://soundcloud.com/');
    final version = findAppVersion(html);
    if (version != null) {
      _appVersion = version;
      await _store.write(_versionKey, version);
    }
    final scripts = findScriptUrls(html);
    if (scripts.isEmpty) throw const ScChanged('no script bundles found');
    for (final url in scripts.reversed) {
      final id = findClientId(await _download(url));
      if (id != null) return id;
    }
    throw const ScChanged('client_id not found');
  }

  Future<String> _download(String url) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: {'User-Agent': browserUserAgent})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw ScChanged('HTTP ${res.statusCode} on page download');
      }
      return res.body;
    } on ScException {
      rethrow;
    } on SocketException {
      throw const ScNetworkError();
    } on TimeoutException {
      throw const ScNetworkError();
    } on http.ClientException {
      throw const ScNetworkError();
    }
  }
}
