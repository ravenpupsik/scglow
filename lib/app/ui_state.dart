import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'search_index.dart';

enum Section { likes, playlists, queue }

sealed class AppRoute {
  const AppRoute();
}

class LikesRoute extends AppRoute {
  const LikesRoute();
}

class PlaylistsRoute extends AppRoute {
  const PlaylistsRoute();
}

class PlaylistRoute extends AppRoute {
  const PlaylistRoute(this.playlistId);
  final int playlistId;
}

class QueueRoute extends AppRoute {
  const QueueRoute();
}

class TrackRoute extends AppRoute {
  const TrackRoute(this.track);
  final Track track;
}

class AppNav extends ChangeNotifier {
  AppRoute route = const LikesRoute();
  Section section = Section.likes;
  final List<AppRoute> _back = [];

  final ValueNotifier<String> query = ValueNotifier('');

  void go(AppRoute r) {
    _back.add(route);
    if (_back.length > 30) _back.removeAt(0);
    route = r;
    section = switch (r) {
      LikesRoute() => Section.likes,
      PlaylistsRoute() || PlaylistRoute() => Section.playlists,
      QueueRoute() => Section.queue,
      TrackRoute() => section,
    };
    if (query.value.isNotEmpty && r is! TrackRoute) query.value = '';
    notifyListeners();
  }

  bool back() {
    if (_back.isEmpty) return false;
    route = _back.removeLast();
    notifyListeners();
    return true;
  }

  void reset() {
    _back.clear();
    route = const LikesRoute();
    section = Section.likes;
    query.value = '';
    notifyListeners();
  }
}

enum PanelTab { queue, related, comments }

class TrackPanel extends ChangeNotifier {
  bool _open = false;
  PanelTab _tab = PanelTab.queue;

  final ValueNotifier<int> focusRequests = ValueNotifier(0);

  bool get isOpen => _open;
  PanelTab get tab => _tab;

  void show() {
    focusRequests.value++;
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  void toggle() => _open ? close() : show();

  void select(PanelTab t) {
    if (t == _tab) return;
    _tab = t;
    notifyListeners();
  }
}

class FocusMode extends ChangeNotifier {
  bool _on = false;

  bool get isOn => _on;

  void enter() {
    if (_on) return;
    _on = true;
    notifyListeners();
  }

  void exit() {
    if (!_on) return;
    _on = false;
    notifyListeners();
  }

  void toggle() => _on ? exit() : enter();
}

class SnackMessage {
  SnackMessage(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;
}

class Messages extends ChangeNotifier {
  SnackMessage? current;
  Timer? _timer;

  void show(String text,
      {String? action, VoidCallback? onAction, Duration? duration}) {
    current = SnackMessage(text, action: action, onAction: onAction);
    _timer?.cancel();
    _timer = Timer(
        duration ?? Duration(seconds: action != null ? 6 : 4), dismiss);
    notifyListeners();
  }

  void dismiss() {
    _timer?.cancel();
    current = null;
    notifyListeners();
  }
}

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(this._prefs, super.value);

  static const key = 'theme_mode';
  final SharedPreferences? _prefs;

  static ThemeMode read(SharedPreferences prefs) =>
      switch (prefs.getString(key)) {
        'light' => ThemeMode.light,
        'night' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  void set(ThemeMode mode) {
    value = mode;
    _prefs?.setString(key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'night',
      ThemeMode.system => 'system',
    });
  }

  void cycle() => set(switch (value) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      });

  String get label => switch (value) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Night',
      };
}

class SortPrefs {
  static const key = 'likes_sort';

  static LikesSort read(SharedPreferences? prefs) =>
      LikesSort.values.where((s) => s.name == prefs?.getString(key)).firstOrNull ??
      LikesSort.dateLiked;

  static void write(SharedPreferences? prefs, LikesSort s) =>
      prefs?.setString(key, s.name);
}

class BoolPref extends ValueNotifier<bool> {
  BoolPref(this._prefs, this.prefKey, {bool fallback = true})
      : super(_prefs?.getBool(prefKey) ?? fallback);

  final String prefKey;
  final SharedPreferences? _prefs;

  void set(bool on) {
    value = on;
    _prefs?.setBool(prefKey, on);
  }
}

class TintController extends BoolPref {
  TintController(SharedPreferences? prefs) : super(prefs, key);

  static const key = 'tint_from_cover';
}

class PulseController extends BoolPref {
  PulseController(SharedPreferences? prefs) : super(prefs, key);

  static const key = 'pulse_to_beat';
}
