import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'diag_log.dart';
import 'sc_api.dart';

class WebToken {
  const WebToken(this.value, {this.expires});

  final String value;
  final DateTime? expires;
}

class WebSession implements WebWriter {
  WebViewEnvironment? environment;

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _page;
  WebUri? _pageUrl;
  Timer? _idle;
  Future<void> _queue = Future.value();

  static final _lightUrl = WebUri('https://soundcloud.com/robots.txt');

  static final soundCloudUrl = WebUri('https://soundcloud.com');
  static final signInUrl = WebUri('https://soundcloud.com/signin');

  Future<void> init() async {
    if (!Platform.isWindows) return;
    final dir = await getApplicationSupportDirectory();
    environment = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: '${dir.path}${Platform.pathSeparator}webview',
      ),
    );
  }

  CookieManager get _cookies =>
      CookieManager.instance(webViewEnvironment: environment);

  Future<String?> readOAuthToken() async {
    final cookie =
        await _cookies.getCookie(url: soundCloudUrl, name: 'oauth_token');
    final value = cookie?.value?.toString();
    return (value == null || value.isEmpty) ? null : value;
  }

  // Opens the full site so its scripts can refresh the session, then reads the oauth_token cookie.
  Future<WebToken?> loadSiteToken() {
    final run = _queue.then((_) => _loadSiteTokenNow());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<WebToken?> _loadSiteTokenNow() async {
    _idle?.cancel();
    try {
      await _close();
      await _open(soundCloudUrl);
      await Future<void>.delayed(const Duration(seconds: 3));
      final cookie =
          await _cookies.getCookie(url: soundCloudUrl, name: 'oauth_token');
      final value = cookie?.value?.toString();
      if (value == null || value.isEmpty) return null;
      return WebToken(value, expires: cookieExpiry(cookie?.expiresDate));
    } catch (_) {
      return null;
    } finally {
      _idle = Timer(const Duration(minutes: 3), () => unawaited(_close()));
    }
  }

  // WebView2 reports cookie expiry in seconds, other platforms in milliseconds.
  static DateTime? cookieExpiry(int? raw) {
    if (raw == null || raw <= 0) return null;
    final ms = raw < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static String? tokenFromDocumentCookie(String? documentCookie) {
    if (documentCookie == null) return null;
    for (final part in documentCookie.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length >= 2 && kv.first == 'oauth_token' && kv[1].isNotEmpty) {
        return kv.sublist(1).join('=');
      }
    }
    return null;
  }

  static const _googleBlockSigns = [
    'disallowed_useragent',
    '/signin/rejected',
    'this browser or app may not be secure',
    'браузер или приложение могут быть небезопасными',
  ];

  // Google refuses sign-in inside embedded browsers; detect its block page by URL or page text.
  static bool isGoogleEmbedBlock(String? url, [String? pageText]) {
    final u = url == null ? null : Uri.tryParse(url);
    if (u == null || u.host.toLowerCase() != 'accounts.google.com') return false;
    final hay = '${url!.toLowerCase()}\n${(pageText ?? '').toLowerCase()}';
    return _googleBlockSigns.any(hay.contains);
  }

  Future<String?> readBotCookie() async {
    final cookie =
        await _cookies.getCookie(url: soundCloudUrl, name: 'datadome');
    final value = cookie?.value?.toString();
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<WebWriteResult> write(String method, Uri url, String token) {
    final run = _queue.then((_) => _writeNow(method, url, token));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<WebWriteResult> _writeNow(
      String method, Uri url, String token) async {
    _idle?.cancel();
    try {
      var r = await _fetchFrom(_lightUrl, method, url, token);
      if (r.status == 403) {
        DiagLog.write('$method ${url.path} webview 403 on light page, '
            'retrying from the full site');
        r = await _fetchFrom(soundCloudUrl, method, url, token);
      }
      return r;
    } finally {
      _idle = Timer(const Duration(minutes: 3), () => unawaited(_close()));
    }
  }

  // Loads the light page once so DataDome can set a fresh cookie; returns whether one is present.
  Future<bool> warmUp() {
    final run = _queue.then((_) => _warmUpNow());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<bool> _warmUpNow() async {
    _idle?.cancel();
    try {
      await _close();
      await _open(_lightUrl);
      return await readBotCookie() != null;
    } catch (_) {
      return false;
    } finally {
      _idle = Timer(const Duration(minutes: 3), () => unawaited(_close()));
    }
  }

  static const _fetchJs = '''
const headers = {'Accept': 'application/json', 'Authorization': 'OAuth ' + token};
const m = document.cookie.match(/(?:^|;\\s*)datadome=([^;]+)/);
if (m) headers['X-Datadome-ClientId'] = m[1];
try {
  const r = await fetch(url, {method: method, headers: headers, credentials: 'include', mode: 'cors'});
  const body = await r.text();
  return {status: r.status, body: body.slice(0, 300)};
} catch (e) {
  return {status: 0, body: String(e)};
}
''';

  Future<WebWriteResult> _fetchFrom(
      WebUri page, String method, Uri url, String token) async {
    final c = await _open(page);
    final res = await c.callAsyncJavaScript(
      functionBody: _fetchJs,
      arguments: {'method': method, 'url': url.toString(), 'token': token},
    ).timeout(const Duration(seconds: 25));
    final value = res?.value;
    if (value is Map) {
      final status = value['status'];
      return WebWriteResult(
        status is num ? status.toInt() : 0,
        (value['body'] ?? '').toString(),
      );
    }
    return WebWriteResult(0, res?.error ?? 'no result');
  }

  Future<InAppWebViewController> _open(WebUri url) async {
    final current = _page;
    if (current != null && _pageUrl == url) return current;
    await _close();
    final loaded = Completer<InAppWebViewController>();
    final view = HeadlessInAppWebView(
      webViewEnvironment: environment,
      initialSize: const Size(1024, 768),
      initialUrlRequest: URLRequest(url: url),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: true,
        isInspectable: false,
      ),
      onLoadStop: (c, _) {
        if (!loaded.isCompleted) loaded.complete(c);
      },
      onReceivedError: (c, request, error) {
        if ((request.isForMainFrame ?? true) && !loaded.isCompleted) {
          loaded.completeError(StateError('page load failed'));
        }
      },
    );
    _headless = view;
    await view.run();
    try {
      final c = await loaded.future.timeout(const Duration(seconds: 30));
      _page = c;
      _pageUrl = url;
      return c;
    } catch (_) {
      await _close();
      rethrow;
    }
  }

  Future<void> _close() async {
    final view = _headless;
    _headless = null;
    _page = null;
    _pageUrl = null;
    try {
      await view?.dispose();
    } catch (_) {}
  }

  Future<void> clearCookies() async {
    await _close();
    try {
      await _cookies.deleteAllCookies();
    } catch (_) {}
  }
}
