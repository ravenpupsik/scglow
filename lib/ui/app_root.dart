import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_services.dart';
import '../app/session_controller.dart';
import '../app/ui_state.dart';
import 'screens/likes_screen.dart';
import 'screens/login_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/track_screen.dart';
import 'shell.dart';
import 'theme/tokens.dart';

class ScglowApp extends StatelessWidget {
  const ScglowApp({super.key, required this.services, this.home});

  final AppServices services;

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: services.theme,
        builder: (context, mode, _) => MaterialApp(
          title: 'scglow',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(AgColors.light),
          darkTheme: buildTheme(AgColors.night),
          themeMode: mode,
          themeAnimationDuration: Duration.zero,
          home: Material(
            type: MaterialType.transparency,
            child: home ?? const _Root(),
          ),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app.session,
      builder: (context, _) => switch (app.session.state) {
        SessionState.loading => const WindowFrame(
            child: Column(children: [LoginBar()])),
        SessionState.signedOut => const LoginScreen(kind: LoginKind.signIn),
        SessionState.expired => const LoginScreen(kind: LoginKind.expired),
        SessionState.changed => const LoginScreen(kind: LoginKind.changed),
        SessionState.ready => const _Main(),
      },
    );
  }
}

class _Main extends StatelessWidget {
  const _Main();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Shortcuts(
      child: AppShell(
        child: ListenableBuilder(
          listenable: Listenable.merge([app.nav, app.nav.query]),
          builder: (context, _) => contentFor(app.nav),
        ),
      ),
    );
  }
}

Widget contentFor(AppNav nav) {
  final q = nav.query.value;
  if (q.trim().isNotEmpty) return LikesScreen(query: q);
  return switch (nav.route) {
    LikesRoute() => const LikesScreen(),
    PlaylistsRoute() => const PlaylistsScreen(),
    PlaylistRoute(:final playlistId) =>
      PlaylistScreen(key: ValueKey(playlistId), playlistId: playlistId),
    QueueRoute() => const QueueScreen(),
    TrackRoute(:final track) => TrackScreen(track: track),
  };
}

class _Shortcuts extends StatefulWidget {
  const _Shortcuts({required this.child});

  final Widget child;

  @override
  State<_Shortcuts> createState() => _ShortcutsState();
}

class _ShortcutsState extends State<_Shortcuts> {
  static const seekStep = Duration(seconds: 5);

  final _node = FocusNode(debugLabel: 'app keys');
  AppServices? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app == _app) return;
    _app?.focus.removeListener(_onFocusMode);
    _app = app;
    app.focus.addListener(_onFocusMode);
  }

  // Focus mode hides the search field, so its keys come back to the app.
  void _onFocusMode() {
    if (_app?.focus.isOn ?? false) _node.requestFocus();
  }

  @override
  void dispose() {
    _app?.focus.removeListener(_onFocusMode);
    _node.dispose();
    super.dispose();
  }

  void _seek(AppServices app, Duration by) {
    final p = app.player;
    final t = p.current;
    if (t == null) return;
    var to = p.position.value + by;
    if (to < Duration.zero) to = Duration.zero;
    final end = Duration(milliseconds: t.durationMs);
    if (t.durationMs > 0 && to > end) to = end;
    p.seek(to);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Listener(
      onPointerDown: (e) {
        if (e.buttons == kBackMouseButton) app.nav.back();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              SearchFocus.node?.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.f5): app.library.refresh,
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              app.library.refresh,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              app.focus.isOn ? app.focus.exit() : app.panel.close(),
        },
        child: Focus(
          focusNode: _node,
          autofocus: true,
          onKeyEvent: (node, e) {
            // Only when nothing else (a text field, a focused button) has focus.
            if (FocusManager.instance.primaryFocus != node) {
              return KeyEventResult.ignored;
            }
            final down = e is KeyDownEvent;
            final key = e.logicalKey;
            if (down && key == LogicalKeyboardKey.space) {
              app.player.togglePlay();
              return KeyEventResult.handled;
            }
            if ((down || e is KeyRepeatEvent) &&
                (key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight)) {
              _seek(app, key == LogicalKeyboardKey.arrowLeft ? -seekStep : seekStep);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: widget.child,
        ),
      ),
    );
  }
}
