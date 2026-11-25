import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/core/errors.dart';
import 'package:scglow/core/json_store.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/player/play_queue.dart';
import 'package:scglow/player/player_controller.dart';

import 'support/fakes.dart';

PlayerController _player(FakeBackend backend,
    {Set<int> unplayable = const {},
    Set<int> knownUnavailable = const {},
    List<String>? messages,
    Map<int, Unavailable>? marked,
    JsonStore? store,
    void Function(String source, ScAuthExpired e)? onAuthProblem}) {
  return PlayerController(
    backend: backend,
    onAuthProblem: onAuthProblem ?? (_, _) {},
    store: store,
    onMessage: (m) => messages?.add(m),
    unavailableOf: (t) =>
        knownUnavailable.contains(t.id) ? Unavailable.removed : marked?[t.id],
    onUnavailable: (t, r) => marked?[t.id] = r,
    resolveStream: (t, {bool preferProgressive = false}) async {
      if (unplayable.contains(t.id)) {
        throw const ScUnplayable('encrypted', Unavailable.goPlusOnly);
      }
      return ResolvedStream(url: 'u${t.id}', isPreview: false);
    },
  );
}

void main() {
  test('unplayable track is skipped, marked and dropped from the queue',
      () async {
    final backend = FakeBackend();
    final marked = <int, Unavailable>{};
    final player = _player(backend, unplayable: {2}, marked: marked);
    await player.playTracks([track(1), track(2), track(3)], start: 0);
    await player.next();
    expect(backend.opened, ['u1', 'u3']);
    expect(player.current!.id, 3);
    expect(marked[2], Unavailable.goPlusOnly);
    expect(player.queue.items.map((t) => t.id), [1, 3]);
    await player.previous();
    expect(player.current!.id, 1);
  });

  test('known-unavailable rows never enter the queue', () async {
    final backend = FakeBackend();
    final player = _player(backend, knownUnavailable: {1, 3});
    await player.playTracks([track(1), track(2), track(3), track(4)], start: 1);
    expect(player.queue.items.map((t) => t.id), [2, 4]);
    expect(backend.opened, ['u2']);
  });

  test('nothing playable: message, queue untouched', () async {
    final backend = FakeBackend();
    final messages = <String>[];
    final player =
        _player(backend, knownUnavailable: {7, 8}, messages: messages);
    await player.playTracks([track(1)], start: 0);
    await player.playTracks([track(7), track(8)], shuffle: true);
    expect(messages, ['Nothing playable here']);
    expect(player.queue.items.map((t) => t.id), [1]);
  });

  test('whole queue unplayable does not crash', () async {
    final backend = FakeBackend();
    final messages = <String>[];
    final player =
        _player(backend, unplayable: {1, 2, 3}, messages: messages);
    await player.playTracks([track(1), track(2), track(3)], start: 0);
    expect(backend.opened, isEmpty);
    expect(messages, isNotEmpty);
  });

  test('a 401 during resolve is reported to the session and shown as a normal error',
      () async {
    final reported = <String>[];
    final messages = <String>[];
    final player = PlayerController(
      backend: FakeBackend(),
      onAuthProblem: (source, _) => reported.add(source),
      onMessage: messages.add,
      resolveStream: (t, {bool preferProgressive = false}) async => throw const ScAuthExpired(),
    );
    await player.playTracks([track(1)], start: 0);
    expect(reported, ['player.resolve']);
    expect(messages, ["Couldn't confirm sign-in"]);
  });

  test('completion: next, repeat one replays, repeat all wraps, off stops',
      () async {
    final backend = FakeBackend();
    final player = _player(backend);
    await player.playTracks([track(1), track(2)], start: 0);
    backend.finish();
    await pump();
    expect(backend.opened, ['u1', 'u2']);

    player.cycleRepeat();
    backend.finish();
    await pump();
    expect(backend.opened.last, 'u1');

    player.cycleRepeat();
    expect(player.repeat, LoopMode.one);
    backend.finish();
    await pump();
    expect(backend.opened.length, 3);
    expect(backend.seeks.last, Duration.zero);

    player.cycleRepeat();
    await player.next();
    backend.finish();
    await pump();
    expect(player.playing, isFalse);
    expect(backend.opened.length, 4);
  });

  test('backend error on start: one fresh retry, then stop in place without skipping',
      () async {
    final backend = FakeBackend();
    final marked = <int, Unavailable>{};
    final messages = <String>[];
    final player = _player(backend, marked: marked, messages: messages);
    await player.playTracks([track(1), track(2)], start: 0);
    backend.fail('decoder');
    await pump();
    expect(backend.opened, ['u1', 'u1']);
    backend.fail('decoder');
    await pump();
    expect(backend.opened, ['u1', 'u1']);
    expect(player.current!.id, 1);
    expect(player.queue.items.map((t) => t.id), [1, 2]);
    expect(player.playing, isFalse);
    expect(marked, isEmpty);
    expect(messages, ["Couldn't load this track"]);
  });

  test('a stream lookup failure shows an error and keeps the track', () async {
    final messages = <String>[];
    final backend = FakeBackend();
    final player = PlayerController(
      backend: backend,
      onAuthProblem: (_, _) {},
      onMessage: messages.add,
      resolveStream: (t, {bool preferProgressive = false}) async => throw const ScStreamFailed(),
    );
    await player.playTracks([track(1), track(2)], start: 0);
    expect(backend.opened, isEmpty);
    expect(player.current!.id, 1);
    expect(messages, ["Couldn't load this track"]);
  });

  test('completion long before the end counts as a failed start, not as finished',
      () async {
    final backend = FakeBackend();
    final player = _player(backend);
    await player.playTracks([track(1, ms: 200000), track(2, ms: 200000)], start: 0);
    backend.emitDuration(const Duration(seconds: 200));
    await pump();
    backend.finish();
    await pump();
    expect(backend.opened, ['u1', 'u1']);
    expect(player.current!.id, 1);
  });

  test('persisted state keeps ids, queue and position but no stream link', () async {
    final store = MemoryJsonStore();
    final player = PlayerController(
      backend: FakeBackend(),
      onAuthProblem: (_, _) {},
      store: store,
      resolveStream: (t, {bool preferProgressive = false}) async => const ResolvedStream(
          url: 'https://cf-hls-media.sndcdn.com/playlist/x.m3u8?Policy=SIGNED',
          isPreview: false),
    );
    final t = Track(
        id: 7, title: 't7', artist: 'a', durationMs: 200000, trackAuthorization: 'auth-secret');
    await player.playTracks([t], start: 0);
    await player.save();
    final saved = jsonEncode(await store.read(PlayerController.stateName));
    expect(saved, isNot(contains('Policy=SIGNED')));
    expect(saved, isNot(contains('sndcdn')));
    expect(saved, isNot(contains('auth-secret')));
    expect(saved, contains('"positionMs"'));
  });

  test('restored track that fails to start keeps its place and saved position', () async {
    final store = MemoryJsonStore();
    final b1 = FakeBackend();
    final first = _player(b1, store: store);
    await first.playTracks([track(1, ms: 200000), track(2, ms: 200000)], start: 0);
    b1.emitPosition(const Duration(seconds: 90));
    await pump();
    await first.save();

    final b2 = FakeBackend();
    final messages = <String>[];
    final p2 = _player(b2, store: store, messages: messages);
    await p2.restore();
    expect(b2.opened, isEmpty);
    await p2.togglePlay();
    expect(b2.starts.single, const Duration(seconds: 90));
    b2.fail('open failed');
    await pump();
    b2.fail('open failed');
    await pump();
    expect(b2.starts, [const Duration(seconds: 90), null]);
    expect(p2.current!.id, 1);
    expect(p2.position.value, const Duration(seconds: 90));
    expect(messages, ["Couldn't load this track"]);
    await p2.save();
    expect((await store.read(PlayerController.stateName))!['positionMs'], 90000);
  });

  test('resume after a long pause opens a fresh stream at the same position', () async {
    var now = DateTime.utc(2026, 11, 24, 20);
    final backend = FakeBackend();
    final player = PlayerController(
      backend: backend,
      onAuthProblem: (_, _) {},
      clock: () => now,
      resolveStream: (t, {bool preferProgressive = false}) async => ResolvedStream(url: 'u${t.id}', isPreview: false),
    );
    await player.playTracks([track(1, ms: 200000)], start: 0);
    backend.emitPosition(const Duration(seconds: 30));
    await pump();
    await player.togglePlay();
    await pump();
    expect(player.playing, isFalse);

    now = now.add(const Duration(minutes: 2));
    await player.togglePlay();
    await pump();
    expect(backend.opened, ['u1']);
    await player.togglePlay();
    await pump();

    now = now.add(PlayerController.stalePause);
    await player.togglePlay();
    await pump();
    expect(backend.opened, ['u1', 'u1']);
    expect(backend.starts.last, const Duration(seconds: 30));
  });

  test('mute zeroes volume and restores it', () async {
    final backend = FakeBackend();
    final player = _player(backend);
    await player.setVolume(40);
    await player.toggleMute();
    expect(backend.volume, 0);
    expect(player.muted, isTrue);
    await player.toggleMute();
    expect(backend.volume, 40);
  });

  test('resume: same track and position after restart', () async {
    final store = MemoryJsonStore();
    final b1 = FakeBackend();
    final p1 = _player(b1, store: store);
    await p1.playTracks([track(1, ms: 200000), track(2, ms: 200000), track(3, ms: 200000)], start: 1);
    b1.emitPosition(const Duration(seconds: 42));
    await pump();
    p1.cycleRepeat();
    await p1.save();

    final b2 = FakeBackend();
    final p2 = _player(b2, store: store);
    await p2.restore();
    expect(p2.current!.id, 2);
    expect(p2.playing, isFalse);
    expect(p2.position.value, const Duration(seconds: 42));
    expect(p2.repeat, LoopMode.all);
    expect(b2.opened, isEmpty);
    await p2.togglePlay();
    expect(b2.opened, ['u2']);
    expect(b2.starts.single, const Duration(seconds: 42));
  });

  test('clear up next and undo', () async {
    final player = _player(FakeBackend());
    await player.playTracks([track(1), track(2), track(3)], start: 0);
    final removed = player.clearUpNext();
    expect(player.upNext, isEmpty);
    player.restoreUpNext(removed);
    expect(player.upNext.map((t) => t.id), [2, 3]);
  });
}
