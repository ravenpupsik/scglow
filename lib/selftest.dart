import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

import 'core/client_id_provider.dart';
import 'core/sc_api.dart';
import 'core/storage.dart';
import 'player/audio_backend.dart';
import 'player/media_controls.dart';
import 'player/player_controller.dart';

Future<void> runSelfTest() async {
  final log = File('${Directory.systemTemp.path}${Platform.pathSeparator}scglow_selftest.log');
  final lines = <String>[];
  void write(String line) {
    lines.add('${DateTime.now().toIso8601String()} $line');
    log.writeAsStringSync('${lines.join('\n')}\n');
  }

  runApp(const MaterialApp(
    home: Scaffold(body: Center(child: Text('scglow self-test running...'))),
  ));

  try {
    final client = http.Client();
    final ids = ClientIdProvider(client: client, store: MemoryKeyValueStore());
    final id = await ids.refresh();
    write('client_id extracted (${id.length} chars)');
    final api = ScApi(client: client, clientId: ids, readToken: () async => null);
    final track = await api.resolveUrl('https://soundcloud.com/forss/flickermood');
    write('track: ${track.title} by ${track.artist}');

    final backend = MediaKitBackend(logLevel: MPVLogLevel.warn);
    final raw = backend.rawPlayer.stream;
    raw.log.listen((l) => write('mpv ${l.level} ${l.prefix}: ${l.text.trim()}'));
    raw.error.listen((e) => write('error: $e'));
    raw.buffering.listen((b) => write('buffering=$b'));
    raw.audioParams.listen((a) => write('audio: ${a.format} ${a.sampleRate}Hz ${a.channels}'));
    await backend.setVolume(0);
    final player = PlayerController(
      backend: backend,
      resolveStream: api.resolveStream,
      mediaControls: MediaControls(),
      onAuthProblem: (source, _) => write('auth problem from $source (unexpected)'),
      onMessage: (m) => write('message: $m'),
      onUnavailable: (t, r) => write('unavailable: ${r.label}'),
    );
    await player.setVolume(0);
    await player.playTracks([track], start: 0);
    write('opened, current=${player.current?.title}');
    for (var i = 1; i <= 4; i++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      write('t+${i * 5}s playing=${player.playing} position=${player.position.value.inMilliseconds}ms duration=${player.duration.value.inMilliseconds}ms');
    }
    await player.seek(const Duration(seconds: 120));
    await Future<void>.delayed(const Duration(seconds: 2));
    write('after seek to 120s: position=${player.position.value.inMilliseconds}ms');
    await player.togglePlay();
    await Future<void>.delayed(const Duration(seconds: 1));
    write('after pause: playing=${player.playing}');
    await player.shutdown();
    write('DONE');
  } catch (e, st) {
    write('FAILED: $e\n$st');
  }
  exit(0);
}
