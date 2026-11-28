import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/client_id_provider.dart';
import '../core/diag_log.dart';
import '../core/errors.dart';
import '../core/json_store.dart';
import '../core/models.dart';
import '../core/sc_api.dart';
import '../core/storage.dart';
import '../core/web_session.dart';
import '../platform/window_service.dart';
import '../player/audio_backend.dart';
import '../player/media_controls.dart';
import '../player/player_controller.dart';
import '../ui/cover_scene.dart' show WaveformCache;
import '../ui/widgets/art_image.dart';
import 'library_controller.dart';
import 'update_controller.dart';
import 'session_controller.dart';
import 'track_details.dart';
import 'ui_state.dart';

class AppServices {
  AppServices({
    required this.session,
    required this.library,
    required this.player,
    required this.details,
    required this.theme,
    required this.window,
    this.web,
    this.tray,
    this.prefs,
    this.onLogout,
    this.waveforms,
    this.waveformUrlOf,
    UpdateController? updates,
  }) : updates = updates ??
            UpdateController(
              player: player,
              window: window,
              prefs: prefs,
            );

  final SessionController session;
  final LibraryController library;
  final PlayerController player;
  final TrackDetailsController details;
  final ThemeController theme;
  final WindowService window;
  final WebSession? web;
  final TrayService? tray;
  final SharedPreferences? prefs;
  final Future<void> Function()? onLogout;

  final WaveformCache? waveforms;

  final Future<String?> Function(Track track)? waveformUrlOf;
  final AppNav nav = AppNav();
  final TrackPanel panel = TrackPanel();
  final FocusMode focus = FocusMode();
  late final TintController tint = TintController(prefs);
  late final PulseController pulse = PulseController(prefs);
  final Messages messages = Messages();

  final UpdateController updates;

  Future<void> logout() async {
    await player.stop();
    library.reset(clearCache: true);
    nav.reset();
    panel.close();
    focus.exit();
    await onLogout?.call();
    await session.logout();
  }

  void wire() {
    var lastState = session.state;
    int? lastUser;
    session.addListener(() {
      final state = session.state;
      final uid = session.user?.id;
      if (state == SessionState.ready && uid != null && uid != lastUser) {
        if (library.userId != null && library.userId != uid) library.reset();
        lastUser = uid;
        library.open(uid);
      }
      if (state == SessionState.ready &&
          lastState != SessionState.ready &&
          uid == null) {
        library.openCached().then((id) {
          if (id == null) library.markOffline();
        });
      }
      lastState = state;
    });
    final t = tray;
    if (t != null) {
      void sync() {
        final cur = player.current;
        t.update(
          playing: player.playing,
          hasTrack: cur != null,
          title: cur?.title ?? '',
          artist: cur?.artist ?? '',
        );
      }

      player.addListener(sync);
      sync();
      t.onAction = (a) {
        switch (a) {
          case 'toggle':
            player.togglePlay();
          case 'next':
            player.next();
          case 'show':
            window.showWindow();
          case 'quit':
            window.quit();
        }
      };
    }
    window.onFocus = () {
      if (session.state == SessionState.ready) {
        unawaited(library.refreshOnFocus());
      }
    };
    window.onShown = () =>
        unawaited(session.renewFromWeb('window shown', throttled: true));
    window.active.addListener(() {
      if (!window.active.value) unawaited(player.save());
    });
    window.beforeQuit = () async {
      await player.save();
      await player.pause();
      await player.shutdown();
    };
    if (Platform.isWindows) {
      updates.recoverFailedApply();
      updates.logStartup();
      unawaited(() async {
        if (!await updates.migrateToInstaller()) await updates.checkSilent();
      }());
    }
  }

  static Future<AppServices> create(SharedPreferences prefs) async {
    const secure = SecureKeyValueStore();
    final tokens = TokenStore(secure);
    final client = http.Client();
    final dir = await getApplicationSupportDirectory();
    final store = FileJsonStore(Directory('${dir.path}${Platform.pathSeparator}data'));
    ArtCache.dir = Directory('${dir.path}${Platform.pathSeparator}art');
    final waveformUrls = <int, Future<String?>>{};
    final web = WebSession();
    await web.init();
    final api = ScApi(
      client: client,
      clientId: ClientIdProvider(client: client, store: secure),
      readToken: tokens.read,
      webWriter: Platform.isWindows ? web : null,
      readBotCookie: Platform.isWindows ? web.readBotCookie : null,
    );

    final session = SessionController(
      api: api,
      tokens: tokens,
      store: store,
      web: web,
      warmBotCheck: Platform.isWindows ? web.warmUp : null,
      webToken: Platform.isWindows ? web.loadSiteToken : null,
    );
    late final AppServices services;
    void message(String text) => services.messages.show(text);
    final library = LibraryController(
      api: api,
      store: store,
      onAuthProblem: session.reportAuthProblem,
      onError: (e) => message(friendlyError(e)),
    );
    library.sort = SortPrefs.read(prefs);
    final player = PlayerController(
      backend: MediaKitBackend(),
      resolveStream: api.resolveStream,
      mediaControls: MediaControls(),
      onAuthProblem: session.reportAuthProblem,
      unavailableOf: library.unavailableOf,
      onUnavailable: library.markUnavailable,
      onMessage: message,
      store: store,
    );
    final details = TrackDetailsController(
        api: api, onAuthProblem: session.reportAuthProblem);
    final window = WindowService();
    services = AppServices(
      session: session,
      library: library,
      player: player,
      details: details,
      theme: ThemeController(prefs, ThemeController.read(prefs)),
      window: window,
      web: web,
      tray: TrayService(),
      prefs: prefs,
      updates: UpdateController(
        player: player,
        window: window,
        prefs: prefs,
        client: client,
      ),
      waveforms: WaveformCache((uri) async {
        try {
          final r = await client.get(uri).timeout(const Duration(seconds: 10));
          if (r.statusCode == 200) return r.body;
          DiagLog.write('waveform GET ${uri.host} -> ${r.statusCode}');
        } catch (e) {
          DiagLog.write('waveform GET ${uri.host} -> ${e.runtimeType}');
        }
        return null;
      }),
      waveformUrlOf: (t) {
        final known = library.trackById(t.id)?.waveformUrl;
        if (known != null) return Future.value(known);
        return waveformUrls[t.id] ??= api
            .track(t.id)
            .then((x) => x.waveformUrl, onError: (Object _) => null);
      },
      onLogout: () async {
        await store.delete(PlayerController.stateName);
        try {
          await ArtCache.dir?.delete(recursive: true);
        } catch (_) {}
      },
    );
    services.wire();
    return services;
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  static AppServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

// Double-clicking a track row: the first click already started it, so open
// Focus once it is the current track.
void openFocusFor(BuildContext context, Track track) {
  final app = AppScope.maybeOf(context);
  if (app == null || app.player.current?.id != track.id) return;
  app.focus.enter();
}

extension TrackListX on List<Track> {
  int indexOfId(int id) => indexWhere((t) => t.id == id);
}
