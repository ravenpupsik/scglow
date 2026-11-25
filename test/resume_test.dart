import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/core/diag_log.dart';
import 'package:scglow/core/json_store.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/core/web_session.dart';
import 'package:scglow/player/audio_backend.dart';
import 'package:scglow/player/player_controller.dart';

import 'support/fakes.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('resume');
    DiagLog.pathOverride = '${dir.path}/log.txt';
  });

  tearDown(() {
    DiagLog.pathOverride = null;
    dir.deleteSync(recursive: true);
  });

  String log() => File(DiagLog.path).readAsStringSync();

  ({
    StreamController<Duration> position,
    StreamController<bool> completed,
    List<String> steps,
    Future<ResumeResult> done,
  }) start({Duration confirm = const Duration(seconds: 8)}) {
    final position = StreamController<Duration>.broadcast();
    final completed = StreamController<bool>.broadcast();
    final steps = <String>[];
    final done = resumeAt(
      openPlaying: () async => steps.add('open'),
      position: position.stream,
      completed: completed.stream,
      seek: (d) async => steps.add('seek ${d.inSeconds}'),
      pause: () async => steps.add('pause'),
      setVolume: (v) async => steps.add('volume ${v.round()}'),
      volume: 70,
      start: const Duration(seconds: 45),
      autoplay: true,
      confirmTimeout: confirm,
    );
    return (position: position, completed: completed, steps: steps, done: done);
  }

  test('an optimistic position at the target right after the seek is not a confirmation', () async {
    final r = start();
    await pump();
    expect(r.steps, ['volume 0', 'open']);
    r.position.add(const Duration(milliseconds: 400));
    await pump();
    expect(r.steps, ['volume 0', 'open', 'seek 45']);
    r.position.add(const Duration(seconds: 45));
    await pump();
    var finished = false;
    unawaited(r.done.then((_) => finished = true));
    await pump();
    expect(finished, isFalse);
    r.position.add(const Duration(milliseconds: 46200));
    final result = await r.done;
    expect(result.ok, isTrue);
    expect(result.notes, contains('seek 45s confirmed'));
    expect(r.steps.last, 'volume 70');
  });

  test('an end right after the seek is a failed resume', () async {
    final r = start();
    await pump();
    r.position.add(const Duration(milliseconds: 400));
    await pump();
    r.position.add(const Duration(seconds: 45));
    r.completed.add(true);
    final result = await r.done;
    expect(result.ok, isFalse);
    expect(result.notes, contains('ended'));
    expect(result.notes, contains('after seek 45s'));
    expect(r.steps.last, 'volume 70');
  });

  test('no confirmation and no end within the limit still counts as resumed', () async {
    final r = start(confirm: const Duration(milliseconds: 50));
    await pump();
    r.position.add(const Duration(milliseconds: 400));
    final result = await r.done;
    expect(result.ok, isTrue);
    expect(result.notes, contains('not confirmed'));
  });

  test('the saved position belongs to the restored track only', () async {
    final store = MemoryJsonStore();
    final b1 = FakeBackend();
    final p1 = _player(b1, store: store);
    await p1.playTracks([track(1, ms: 200000), track(2, ms: 200000)], start: 0);
    b1.emitPosition(const Duration(seconds: 45));
    await pump();
    await p1.save();

    final b2 = FakeBackend();
    final p2 = _player(b2, store: store);
    await p2.restore();
    await p2.next();
    expect(b2.starts, [null]);
    await p2.playAt(0);
    expect(b2.starts, [null, null]);
  });

  test('a failed resume plays from 0; an early end after a resume retries from 0', () async {
    final store = MemoryJsonStore();
    final b1 = FakeBackend();
    final p1 = _player(b1, store: store);
    await p1.playTracks([track(1, ms: 169000), track(2, ms: 169000)], start: 0);
    b1.emitPosition(const Duration(seconds: 45));
    await pump();
    await p1.save();

    final b2 = FakeBackend()..resumeWorks = false;
    final p2 = _player(b2, store: store);
    await p2.restore();
    await p2.togglePlay();
    expect(b2.starts, [const Duration(seconds: 45)]);
    expect(p2.position.value, Duration.zero);
    expect(p2.current!.id, 1);

    final b3 = FakeBackend();
    final messages = <String>[];
    final p3 = _player(b3, store: store, messages: messages);
    await p3.restore();
    await p3.togglePlay();
    b3.emitDuration(const Duration(seconds: 169));
    b3.emitPosition(const Duration(seconds: 45));
    await pump();
    b3.finish();
    await pump();
    expect(b3.starts, [const Duration(seconds: 45), null]);
    expect(p3.current!.id, 1);
    expect(log(), contains('failed to start at 45s'));
    expect(log(), contains('fresh stream from 0, one retry'));
    b3.finish();
    await pump();
    expect(p3.current!.id, 1);
    expect(p3.position.value, const Duration(seconds: 45));
    expect(messages, ["Couldn't load this track"]);
    await p3.next();
    expect(b3.starts.last, isNull);
  });

  test('stream links are described by host, kind and expiry only', () {
    final policy = base64
        .encode(utf8.encode(
            '{"Statement":[{"Condition":{"DateLessThan":{"AWS:EpochTime":1795000100}}}]}'))
        .replaceAll('+', '-')
        .replaceAll('=', '_')
        .replaceAll('/', '~');
    final now = DateTime.fromMillisecondsSinceEpoch(1795000000 * 1000, isUtc: true);
    final text = PlayerController.describeStreamUrl(
        'https://cf-hls-media.sndcdn.com/playlist/abc/secret.m3u8?Policy=$policy&Signature=SIG&Key-Pair-Id=K',
        now);
    expect(text, 'cf-hls-media.sndcdn.com, hls, expires in 100s');
    expect(text, isNot(contains('SIG')));
  });

  test('an early cutoff logs the player state', () async {
    final backend = FakeBackend();
    final player = PlayerController(
      backend: backend,
      onAuthProblem: (_, _) {},
      resolveStream: (t, {bool preferProgressive = false}) async => const ResolvedStream(
          url: 'https://cf-hls-media.sndcdn.com/playlist/x.m3u8?Expires=1&Signature=SIG',
          isPreview: false),
    );
    await player.playTracks([track(1, ms: 162000)], start: 0);
    backend.emitDuration(const Duration(seconds: 162));
    backend.emitPosition(const Duration(seconds: 25));
    await pump();
    backend.fail('demuxer: https://cf-hls-media.sndcdn.com/x 403');
    await pump();
    backend.finish();
    await pump();
    final text = log();
    expect(text, contains('ended at 25s of 162s; opened at 0s, link age'));
    expect(text, contains('last error 0s ago: demuxer: [url] 403'));
    expect(text, isNot(contains('SIG')));
  });

  test('cookie expiry in seconds or milliseconds gives the same date', () {
    expect(WebSession.cookieExpiry(1798761600)!.toIso8601String().substring(0, 10), '2027-01-01');
    expect(WebSession.cookieExpiry(1798761600000)!.toIso8601String().substring(0, 10), '2027-01-01');
    expect(WebSession.cookieExpiry(null), isNull);
  });
}

PlayerController _player(FakeBackend backend,
        {JsonStore? store, List<String>? messages}) =>
    PlayerController(
      backend: backend,
      onAuthProblem: (_, _) {},
      store: store,
      onMessage: (m) => messages?.add(m),
      resolveStream: (t, {bool preferProgressive = false}) async => ResolvedStream(url: 'u${t.id}', isPreview: false),
    );
