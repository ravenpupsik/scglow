import 'dart:io';

import 'package:flutter/services.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

class TaskbarButton {
  const TaskbarButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onClick,
  });

  // Flutter asset path of a .ico file.
  final String icon;
  final String tooltip;
  final bool enabled;
  final void Function() onClick;
}

typedef SetTaskbarButtons = Future<void> Function(List<TaskbarButton> buttons);

// Previous, play/pause and next in the window's taskbar thumbnail preview.
class TaskbarButtons {
  TaskbarButtons({
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    SetTaskbarButtons? apply,
  }) : _apply = apply ?? (Platform.isWindows ? _windows : null);

  static const previousIcon = 'assets/taskbar/previous.ico';
  static const playIcon = 'assets/taskbar/play.ico';
  static const pauseIcon = 'assets/taskbar/pause.ico';
  static const nextIcon = 'assets/taskbar/next.ico';

  final void Function() onPrevious, onToggle, onNext;
  final SetTaskbarButtons? _apply;

  bool _playing = false, _hasTrack = false;
  String? _last;

  // Windows drops the thumbnail toolbar in some show/hide paths, so [force]
  // sends the same buttons again after a restore or show.
  Future<void> update({
    required bool playing,
    required bool hasTrack,
    bool force = false,
  }) async {
    _playing = playing;
    _hasTrack = hasTrack;
    final key = '$playing|$hasTrack';
    if (!force && key == _last) return;
    _last = key;
    final apply = _apply;
    if (apply == null) return;
    try {
      await apply(buttons);
    } on MissingPluginException {
      // Not on Windows.
    } on PlatformException {
      // The toolbar is a convenience; playback works without it.
    }
  }

  Future<void> reapply() => update(playing: _playing, hasTrack: _hasTrack, force: true);

  List<TaskbarButton> get buttons => [
        TaskbarButton(
          icon: previousIcon,
          tooltip: 'Previous',
          enabled: _hasTrack,
          onClick: onPrevious,
        ),
        TaskbarButton(
          icon: _playing ? pauseIcon : playIcon,
          tooltip: _playing ? 'Pause' : 'Play',
          enabled: _hasTrack,
          onClick: onToggle,
        ),
        TaskbarButton(
          icon: nextIcon,
          tooltip: 'Next',
          enabled: _hasTrack,
          onClick: onNext,
        ),
      ];

  static Future<void> _windows(List<TaskbarButton> buttons) =>
      WindowsTaskbar.setThumbnailToolbar([
        for (final b in buttons)
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon(b.icon),
            b.tooltip,
            b.onClick,
            mode: b.enabled ? 0 : ThumbnailToolbarButtonMode.disabled,
          ),
      ]);
}
