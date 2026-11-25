import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../core/diag_log.dart';

abstract class AudioBackend {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<String> get error;

  // Returns false when the stream could not start at [start] and plays from the beginning instead.
  Future<bool> open(String url, {Duration? start, bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setVolume(double percent);
  Future<void> dispose();
}

class MediaKitBackend implements AudioBackend {
  MediaKitBackend({MPVLogLevel logLevel = MPVLogLevel.error})
      : _player = Player(configuration: PlayerConfiguration(logLevel: logLevel));

  final Player _player;
  double _volume = 100;
  int _opens = 0;
  bool _seekableReady = false;

  Player get rawPlayer => _player;

  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<String> get error => _player.stream.error;

  Future<void> _enableSeekable() async {
    if (_seekableReady) return;
    final platform = _player.platform;
    try {
      // ignore: avoid_dynamic_calls
      await (platform as dynamic).setProperty('force-seekable', 'yes');
      await (platform as dynamic).setProperty('cache', 'yes');
      await (platform as dynamic).setProperty('demuxer-seekable-cache', 'yes');
      await (platform as dynamic).setProperty('hr-seek', 'yes');
      _seekableReady = true;
      DiagLog.write('player: mpv seekable cache enabled');
    } catch (_) {}
  }

  @override
  Future<bool> open(String url, {Duration? start, bool play = true}) async {
    final id = ++_opens;
    await _enableSeekable();
    if (start == null || start <= const Duration(seconds: 1)) {
      await _player.open(Media(url), play: play);
      return true;
    }
    final r = await resumeAt(
      openPlaying: () => _player.open(Media(url), play: true),
      position: _player.stream.position,
      completed: _player.stream.completed,
      seek: _player.seek,
      pause: _player.pause,
      setVolume: _player.setVolume,
      volume: _volume,
      start: start,
      autoplay: play,
      cancelled: () => id != _opens,
    );
    DiagLog.write('player: resume at ${start.inSeconds}s: ${r.notes}');
    if (r.ok || id != _opens) return r.ok;
    DiagLog.write('player: resume at ${start.inSeconds}s failed; playing from 0');
    await _player.open(Media(url), play: play);
    await _player.setVolume(_volume);
    return false;
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() {
    _opens++;
    return _player.stop();
  }

  @override
  Future<void> setVolume(double percent) {
    _volume = percent;
    return _player.setVolume(percent);
  }

  @override
  Future<void> dispose() => _player.dispose();
}

class ResumeResult {
  const ResumeResult(this.ok, this.notes);

  final bool ok;
  final String notes;
}

// mpv reports the seek target as the position right away, and an HLS seek before any data has
// played can hit the end instead. So: play muted from 0 until audio really advances, seek,
// and only call it done once the position moves past the target; an end before that is a failure.
Future<ResumeResult> resumeAt({
  required Future<void> Function() openPlaying,
  required Stream<Duration> position,
  required Stream<bool> completed,
  required Future<void> Function(Duration) seek,
  required Future<void> Function() pause,
  required Future<void> Function(double) setVolume,
  required double volume,
  required Duration start,
  required bool autoplay,
  bool Function()? cancelled,
  Duration warmTimeout = const Duration(seconds: 10),
  Duration confirmTimeout = const Duration(seconds: 8),
}) async {
  var pos = Duration.zero;
  var ended = false;
  final changed = StreamController<void>.broadcast();
  final subs = [
    position.listen((p) {
      pos = p;
      changed.add(null);
    }),
    completed.listen((c) {
      if (c) ended = true;
      changed.add(null);
    }),
  ];
  Future<bool> until(bool Function() ok, Duration limit) async {
    if (ok() || ended) return ok();
    try {
      await changed.stream.firstWhere((_) => ok() || ended).timeout(limit);
    } on TimeoutException {
      return false;
    } on StateError {
      // closed
    }
    return ok();
  }

  final watch = Stopwatch()..start();
  final notes = <String>[];
  bool stop() => cancelled?.call() ?? false;
  try {
    await setVolume(0);
    await openPlaying();
    final warm = await until(() => pos >= const Duration(milliseconds: 300), warmTimeout);
    if (stop()) return ResumeResult(false, 'superseded');
    if (ended) {
      return ResumeResult(false, 'ended while warming up after ${watch.elapsedMilliseconds}ms');
    }
    notes.add(warm
        ? 'playing from 0 after ${watch.elapsedMilliseconds}ms'
        : 'no playback after ${watch.elapsedMilliseconds}ms');
    watch.reset();
    final target = start;
    pos = Duration.zero;
    await seek(target);
    final moved = await until(() => pos >= target + const Duration(seconds: 1), confirmTimeout);
    if (stop()) return ResumeResult(false, 'superseded');
    if (ended) {
      notes.add('ended ${watch.elapsedMilliseconds}ms after seek ${target.inSeconds}s');
      return ResumeResult(false, notes.join('; '));
    }
    notes.add(moved
        ? 'seek ${target.inSeconds}s confirmed in ${watch.elapsedMilliseconds}ms'
        : 'seek ${target.inSeconds}s not confirmed after ${watch.elapsedMilliseconds}ms (at ${pos.inSeconds}s)');
    if (!autoplay) await pause();
    return ResumeResult(true, notes.join('; '));
  } finally {
    if (!stop()) await setVolume(volume);
    for (final s in subs) {
      await s.cancel();
    }
    await changed.close();
  }
}
