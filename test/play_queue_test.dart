import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/player/play_queue.dart';

import 'support/fakes.dart';

List<int> ids(Iterable t) => [for (final x in t) x.id as int];

void main() {
  final five = [for (var i = 1; i <= 5; i++) track(i)];

  test('next / previous with repeat off, all, one', () {
    final q = PlayQueue()..setTracks(five, start: 0);
    expect(q.current!.id, 1);
    expect(q.previousIndex(), isNull);
    q.jumpTo(4);
    expect(q.nextIndex(), isNull);
    q.repeat = LoopMode.all;
    expect(q.nextIndex(), 0);
    q.jumpTo(0);
    expect(q.previousIndex(), 4);
    q.repeat = LoopMode.one;
    expect(q.nextIndex(auto: true), 0);
    expect(q.nextIndex(), 1, reason: 'Next button moves on even in repeat one');
  });

  test('cycleRepeat goes off → all → one → off', () {
    final q = PlayQueue();
    q.cycleRepeat();
    expect(q.repeat, LoopMode.all);
    q.cycleRepeat();
    expect(q.repeat, LoopMode.one);
    q.cycleRepeat();
    expect(q.repeat, LoopMode.off);
  });

  test('shuffle keeps current first and restores order when turned off', () {
    final q = PlayQueue(random: Random(1))..setTracks(five, start: 1);
    q.setShuffle(true);
    expect(q.current!.id, 2);
    expect(ids(q.items).toSet(), {1, 2, 3, 4, 5});
    expect(ids(q.items).sublist(0, 2), [1, 2]);
    q.setShuffle(false);
    expect(ids(q.items), [1, 2, 3, 4, 5]);
  });

  test('setTracks with shuffle starts at the chosen track', () {
    final q = PlayQueue(random: Random(3))..setTracks(five, start: 3, shuffle: true);
    expect(q.current!.id, 4);
    expect(q.index, 0);
    expect(ids(q.upNext).toSet(), {1, 2, 3, 5});
  });

  test('moveUpNext reorders inside Up next only', () {
    final q = PlayQueue()..setTracks(five, start: 0);
    q.moveUpNext(2, 0);
    expect(ids(q.items), [1, 4, 2, 3, 5]);
    q.moveUpNext(0, 4);
    expect(ids(q.items), [1, 2, 3, 5, 4]);
    q.moveUpNext(1, 1);
    expect(ids(q.items), [1, 2, 3, 5, 4]);
  });

  test('clear and restore up next', () {
    final q = PlayQueue()..setTracks(five, start: 1);
    final removed = q.clearUpNext();
    expect(ids(removed), [3, 4, 5]);
    expect(ids(q.items), [1, 2]);
    q.restoreUpNext(removed);
    expect(ids(q.items), [1, 2, 3, 4, 5]);
  });

  test('remove current keeps index on the following track', () {
    final q = PlayQueue()..setTracks(five, start: 2);
    expect(q.remove(3), isTrue);
    expect(q.current!.id, 4);
    expect(q.remove(1), isFalse);
    expect(q.current!.id, 4);
  });

  test('playNext and add', () {
    final q = PlayQueue()..setTracks(five.sublist(0, 2), start: 0);
    q.add(track(9));
    q.playNext(track(8));
    expect(ids(q.items), [1, 8, 2, 9]);
    q.playNext(track(9));
    expect(ids(q.items), [1, 9, 8, 2]);
  });
}
