import 'dart:async';

import 'package:media_kit/media_kit.dart';

abstract class AudioBackend {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<String> get error;

  Future<void> open(String url, {Duration? start, bool play = true});
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

  @override
  Future<void> open(String url, {Duration? start, bool play = true}) =>
      _player.open(Media(url, start: start), play: play);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);
  @override
  Future<void> dispose() => _player.dispose();
}
