import 'package:flutter/services.dart';

import '../core/models.dart';

enum MediaButton { play, pause, next, previous, stop }

class MediaControls {
  MediaControls({this.onButton, this.onSeek}) {
    _channel.setMethodCallHandler(_handle);
  }

  static const _channel = MethodChannel('scglow/smtc');

  void Function(MediaButton button)? onButton;
  void Function(Duration position)? onSeek;

  int _lastTimelineSecond = -1;

  Future<void> setTrack(Track track) => _call('setMetadata', {
        'title': track.title,
        'artist': track.artist,
        'artUrl': track.largeArtworkUrl ?? '',
      });

  Future<void> setPlaying(bool playing) =>
      _call('setStatus', {'status': playing ? 'playing' : 'paused'});

  Future<void> clear() => _call('setStatus', {'status': 'stopped'});

  Future<void> setTimeline(Duration position, Duration duration) async {
    final second = position.inSeconds;
    if (second == _lastTimelineSecond) return;
    _lastTimelineSecond = second;
    await _call('setTimeline', {
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
    });
  }

  Future<void> _call(String method, Map<String, Object> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Not running on Windows (e.g. tests).
    } on PlatformException {
      // SMTC is optional; playback must keep working without it.
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'button':
        final button = MediaButton.values
            .where((b) => b.name == call.arguments)
            .firstOrNull;
        if (button != null) onButton?.call(button);
      case 'seek':
        final ms = call.arguments;
        if (ms is int) onSeek?.call(Duration(milliseconds: ms));
    }
    return null;
  }
}
