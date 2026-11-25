import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/diag_log.dart';

class WindowService with WindowListener {
  WindowService({this.enabled = true});

  final bool enabled;
  final ValueNotifier<bool> maximized = ValueNotifier(false);

  final ValueNotifier<bool> active = ValueNotifier(true);

  Future<void> Function()? beforeQuit;

  VoidCallback? onFocus;

  VoidCallback? onShown;

  Future<void> init({required Color background}) async {
    if (!enabled) return;
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      backgroundColor: background,
      size: Size(1280, 800),
      minimumSize: Size(960, 600),
      center: true,
      title: 'scglow',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
    maximized.value = await windowManager.isMaximized();
  }

  void startDrag() {
    if (enabled) windowManager.startDragging();
  }

  Future<void> minimize() async {
    if (enabled) await windowManager.minimize();
  }

  Future<void> toggleMaximize() async {
    if (!enabled) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> hideToTray() async {
    active.value = false;
    if (enabled) await windowManager.hide();
  }

  Future<void> showWindow() async {
    if (!enabled) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    active.value = true;
    onShown?.call();
  }

  Future<void> quit() async {
    try {
      await beforeQuit?.call();
    } catch (e, st) {
      DiagLog.error('quit', e, st);
    }
    DiagLog.write('app: quit');
    if (!enabled) return;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowFocus() {
    active.value = true;
    onFocus?.call();
  }

  @override
  void onWindowBlur() => active.value = false;

  @override
  void onWindowMinimize() => active.value = false;

  @override
  void onWindowClose() => hideToTray();

  @override
  void onWindowMaximize() => maximized.value = true;

  @override
  void onWindowUnmaximize() => maximized.value = false;

  @override
  void onWindowRestore() async {
    onShown?.call();
    maximized.value = await windowManager.isMaximized();
  }
}

class TrayService {
  TrayService({this.onAction}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        onAction?.call(call.arguments as String);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('scglow/tray');

  void Function(String action)? onAction;

  String _last = '';

  Future<void> update({
    required bool playing,
    required bool hasTrack,
    String title = '',
    String artist = '',
  }) async {
    final key = '$playing|$hasTrack|$title|$artist';
    if (key == _last) return;
    _last = key;
    try {
      await _channel.invokeMethod<void>('update', {
        'playing': playing,
        'hasTrack': hasTrack,
        'title': title,
        'artist': artist,
      });
    } on MissingPluginException {
      // Not on Windows.
    } on PlatformException {
      // The tray is a convenience; the app works without it.
    }
  }
}
