import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/app/ui_state.dart';
import 'package:scglow/ui/player_dock.dart';
import 'package:scglow/ui/screens/queue_screen.dart';
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/widgets/art_image.dart';
import 'package:scglow/ui/widgets/track_row.dart';

import 'previews/preview_test.dart' as pv;
import 'support/finders.dart';

Future<pv.Harness> bootBoth(WidgetTester tester) async {
  final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1920, 1080));
  await tester.runAsync(() => h.playHarbor(atSec: 1, repeatOff: true));
  h.services.nav.go(const QueueRoute());
  h.services.panel.show();
  await pv.settle(tester);
  return h;
}

int panelNow(WidgetTester tester) => tester
    .widgetList<PanelTrackRow>(find.descendant(
        of: find.byType(TrackPanelView), matching: find.byType(PanelTrackRow)))
    .singleWhere((r) => r.now)
    .track
    .id;

List<int> panelUpNext(WidgetTester tester) => tester
    .widgetList<PanelTrackRow>(find.descendant(
        of: find.byType(TrackPanelView), matching: find.byType(PanelTrackRow)))
    .where((r) => r.index != null)
    .map((r) => r.track.id)
    .toList();

int queueNow(WidgetTester tester) => tester
    .widgetList<TrackRow>(find.descendant(
        of: find.byType(QueueScreen), matching: find.byType(TrackRow)))
    .singleWhere((r) => r.playing)
    .track
    .id;

List<int> queueUpNext(WidgetTester tester) => tester
    .widgetList<TrackRow>(find.descendant(
        of: find.byType(UpNextList), matching: find.byType(TrackRow)))
    .map((r) => r.track.id)
    .toList();

String panelTitle(WidgetTester tester) => tester
    .widget<Text>(find
        .descendant(
            of: find.byType(TrackPanelView),
            matching: find.byWidgetPredicate(
                (w) => w is Text && w.style?.fontSize == 22))
        .first)
    .data!;

void expectInSync(WidgetTester tester, pv.Harness h) {
  final p = h.services.player;
  final want = p.upNext.map((t) => t.id).toList();
  expect(panelNow(tester), p.current!.id);
  expect(queueNow(tester), p.current!.id);
  expect(panelTitle(tester), p.current!.title);
  final panel = panelUpNext(tester);
  final queue = queueUpNext(tester);
  if (want.isEmpty) {
    expect(panel, isEmpty);
    expect(find.text('Nothing up next.'), findsOneWidget);
    return;
  }
  expect(panel, isNotEmpty);
  expect(queue, isNotEmpty);
  expect(panel, want.take(panel.length).toList());
  expect(queue, want.take(queue.length).toList());
}

void main() {
  setUpAll(() async {
    for (final f in Directory('test/previews/covers').listSync().whereType<File>()) {
      pv.covers[f.uri.pathSegments.last.split('.').first] = f.readAsBytesSync();
    }
    ArtCache.override = (url) => MemoryImage(pv.covers['harbor']!);
    await pv.loadFonts();
  });
  setUp(() => pv.bigLibrary = true);
  tearDown(() => pv.bigLibrary = false);

  testWidgets('Next ×3, Prev ×1, end of track: panel matches the Queue page',
      (tester) async {
    final h = await bootBoth(tester);
    expectInSync(tester, h);
    final start = h.services.player.current!.id;
    for (var i = 0; i < 3; i++) {
      await tester.tap(byLabel('Next'));
      await pv.settle(tester);
      expectInSync(tester, h);
    }
    expect(h.services.player.current!.id, isNot(start));
    final afterNext = h.services.player.queue.index;
    await tester.tap(byLabel('Previous'));
    await pv.settle(tester);
    expect(h.services.player.queue.index, afterNext - 1);
    expectInSync(tester, h);
    final length = Duration(milliseconds: h.services.player.current!.durationMs);
    h.backend.emitDuration(length);
    h.backend.emitPosition(length - const Duration(seconds: 1));
    await pv.settle(tester);
    h.backend.finish();
    await pv.settle(tester);
    expect(h.services.player.queue.index, afterNext);
    expectInSync(tester, h);
  });

  testWidgets('clicking a Next up row in the panel updates both at once',
      (tester) async {
    final h = await bootBoth(tester);
    final target = h.services.player.upNext[2].id;
    await tester.tap(find.byWidgetPredicate((w) => w is PanelTrackRow && w.index == 2));
    await pv.settle(tester);
    expect(h.services.player.current!.id, target);
    expectInSync(tester, h);
  });

  testWidgets('shuffle reorders both the same way', (tester) async {
    final h = await bootBoth(tester);
    final before = h.services.player.upNext.map((t) => t.id).toList();
    await tester.tap(byLabel('Shuffle off'));
    await pv.settle(tester);
    expect(h.services.player.shuffle, isTrue);
    expect(h.services.player.upNext.map((t) => t.id).toList(), isNot(before));
    expectInSync(tester, h);
    await tester.tap(byLabel('Shuffle on'));
    await pv.settle(tester);
    expect(h.services.player.upNext.map((t) => t.id).toList(), before);
    expectInSync(tester, h);
  });

  testWidgets('drag reorder from either place, then Clear', (tester) async {
    final h = await bootBoth(tester);
    final p = h.services.player;
    final ids = p.upNext.map((t) => t.id).toList();
    final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorderItem!(0, 2);
    await pv.settle(tester);
    expect(p.upNext.map((t) => t.id).take(3).toList(), [ids[1], ids[2], ids[0]]);
    expectInSync(tester, h);
    p.moveUpNext(3, 0);
    await pv.settle(tester);
    expectInSync(tester, h);
    await tester.tap(find.text('Clear'));
    await pv.settle(tester);
    expect(p.upNext, isEmpty);
    expectInSync(tester, h);
    h.services.messages.dismiss();
  });

  testWidgets('panel header follows the track, Liked is its real state',
      (tester) async {
    final h = await bootBoth(tester);
    final p = h.services.player;
    LikedPill pill() => tester.widget<LikedPill>(find.byType(LikedPill));
    expect(panelTitle(tester), p.current!.title);
    expect(pill().liked, isTrue);
    await tester.tap(byLabel('Next'));
    await pv.settle(tester);
    expect(panelTitle(tester), p.current!.title);
    expect(pill().liked, h.services.library.isLiked(p.current!));
    await tester.tap(byLabel('Previous'));
    await pv.settle(tester);
    h.services.panel.select(PanelTab.related);
    await pv.settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(TrackPanelView), matching: find.text('Salt Window')));
    await pv.settle(tester);
    expect(p.current!.title, 'Salt Window');
    expect(panelTitle(tester), 'Salt Window');
    expect(pill().liked, isFalse);
    expect(find.descendant(of: find.byType(LikedPill), matching: find.text('Like')),
        findsOneWidget);
  });

  testWidgets('Comments and Related follow the current track', (tester) async {
    final h = await bootBoth(tester);
    h.services.panel.select(PanelTab.comments);
    await pv.settle(tester);
    expect(find.text('Nia Vale'), findsWidgets);
    await tester.tap(byLabel('Next'));
    await pv.settle(tester);
    expect(find.text('Nia Vale'), findsNothing);
    expect(find.text('No comments yet.'), findsOneWidget);
    await tester.tap(byLabel('Previous'));
    await pv.settle(tester);
    expect(find.text('Nia Vale'), findsWidgets);
  });

  testWidgets('capsule cover toggles focus; empty capsule space and the title toggle the panel',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1920, 1080));
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    final cover = find.byKey(const ValueKey('capsule-cover'));
    BoxDecoration? rim() =>
        tester.widget<Container>(cover).foregroundDecoration as BoxDecoration?;
    expect(rim(), isNull);
    await tester.tap(cover);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isTrue);
    expect(h.services.panel.isOpen, isFalse);
    expect(rim()?.border, isNotNull);
    await tester.tap(cover);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);
    expect(rim(), isNull);

    final capsule = find.byType(FloatingPlayer);
    final title = find.descendant(of: capsule, matching: find.text('Glass Harbor'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(title));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click);
    await tester.tap(title);
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isTrue);
    expect(rim(), isNull, reason: 'the rim marks focus, not the panel');
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.services.panel.isOpen, isFalse);
    expect(find.byType(TrackPanelView), findsOneWidget, reason: 'closing animates');
    await pv.settle(tester);
    expect(find.byType(TrackPanelView), findsNothing);
    final box = tester.getRect(capsule);
    await tester.tapAt(Offset(box.right - 6, box.top + 4));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isTrue, reason: 'empty capsule space');
    h.services.panel.close();
    await pv.settle(tester);

    // Controls and the dead zones around them do their own thing only.
    final next = tester.getRect(byLabel('Next'));
    final prev = tester.getRect(byLabel('Previous'));
    final heart = tester.getRect(find.descendant(of: capsule, matching: find.byType(HeartButton)));
    final seek = tester.getRect(find.byType(SeekLine));
    final vol = tester.getRect(find.byType(VolumeLine));
    for (final at in [
      Offset((prev.right + next.left) / 2, next.center.dy),
      Offset(next.right + 4, next.center.dy),
      Offset(heart.right + 4, heart.center.dy),
      Offset(seek.left - 4, seek.center.dy),
      Offset(vol.right + 4, vol.center.dy),
    ]) {
      await tester.tapAt(at);
      await pv.settle(tester);
      expect(h.services.panel.isOpen, isFalse, reason: 'guard at $at');
      expect(h.services.library.isLiked(h.services.player.current!), isTrue,
          reason: 'like kept at $at');
    }
    for (final f in [
      byLabel('Next'),
      byLabel('Previous'),
      byLabel('Shuffle off'),
      byLabel('Mute'),
      find.byType(VolumeLine),
      find.byType(SeekLine),
      find.descendant(of: capsule, matching: find.byType(HeartButton)),
    ]) {
      await tester.tap(f);
      await pv.settle(tester);
      expect(h.services.panel.isOpen, isFalse, reason: '$f');
    }
    h.services.panel.show();
    await pv.settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
    // Let the unlike message expire.
    await tester.pump(const Duration(seconds: 5));
  });
}
