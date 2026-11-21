import 'dart:async';

import 'package:scglow/core/models.dart';
import 'package:scglow/player/audio_backend.dart';

class FakeBackend implements AudioBackend {
  final opened = <String>[];
  final starts = <Duration?>[];
  final seeks = <Duration>[];
  double volume = 100;
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();

  void finish() => _completed.add(true);
  void fail(String e) => _error.add(e);
  void emitPosition(Duration d) => _position.add(d);
  void emitDuration(Duration d) => _duration.add(d);

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<String> get error => _error.stream;
  @override
  Future<void> open(String url, {Duration? start, bool play = true}) async {
    opened.add(url);
    starts.add(start);
    _playing.add(true);
  }

  @override
  Future<void> play() async => _playing.add(true);
  @override
  Future<void> pause() async => _playing.add(false);
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double percent) async => volume = percent;
  @override
  Future<void> dispose() async {}
}

Track track(int id,
        {String? title,
        String artist = 'a',
        int ms = 1000,
        String? policy,
        List<Transcoding> transcodings = const []}) =>
    Track(
      id: id,
      title: title ?? 't$id',
      artist: artist,
      durationMs: ms,
      policy: policy,
      transcodings: transcodings,
    );

Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
