import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/ui/cover_scene.dart';
import 'package:scglow/ui/focus_view.dart';
import 'package:scglow/ui/player_dock.dart';
import 'package:scglow/ui/top_bar.dart';
import 'package:scglow/ui/theme/tokens.dart';
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/widgets/art_image.dart';
import 'package:scglow/ui/widgets/track_row.dart';

import 'previews/preview_test.dart' as pv;
import 'support/finders.dart';

Finder _washes() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is WashPainter);

final _cover = find.byKey(const ValueKey('capsule-cover'));
final _sharp = find.byKey(const ValueKey('focus-cover'));

double _opacityAbove(WidgetTester tester, Finder f) =>
    tester.widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first).opacity;

double _barOpacity(WidgetTester tester) => _opacityAbove(tester, find.byType(FloatingPlayer));

double _sharpOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.ancestor(of: _sharp, matching: find.byType(FadeTransition)).first)
    .opacity
    .value;

Future<pv.Harness> _boot(WidgetTester tester, {Size size = const Size(1920, 1080)}) async {
  final h = await pv.boot(tester, ThemeMode.dark, size: size);
  await tester.runAsync(() => h.playHarbor(atSec: 40));
  await pv.settle(tester);
  return h;
}

Future<void> _enter(WidgetTester tester) async {
  await tester.tap(_cover);
  await tester.pump();
  await tester.pump(FocusGeo.glow);
  await tester.pump();
}

String? _shownSharpUrl(WidgetTester tester) {
  final img = find.descendant(of: _sharp, matching: find.byType(Image));
  if (img.evaluate().isEmpty) return null;
  final key = tester.widget<Image>(img.last).key;
  return key is ValueKey<String> ? key.value.replaceFirst('focus-image|', '') : null;
}

CoverScene _scene(WidgetTester tester) =>
    tester.widget<CoverSceneScope>(find.byType(CoverSceneScope)).scene;

// Waits until the sharp cover and its halo both show the current track.
Future<void> _waitInSync(WidgetTester tester, pv.Harness h) async {
  for (var i = 0; i < 80; i++) {
    final t = h.services.player.current!;
    if (_shownSharpUrl(tester) == artUrl(t.artworkUrl, ArtSize.t500) &&
        _scene(tester).art.value?.url == t.artworkUrl) {
      break;
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(FocusGeo.swap);
  await tester.pump();
}

void _expectInSync(WidgetTester tester, pv.Harness h, String step) {
  final t = h.services.player.current!;
  final bar = find.descendant(of: find.byType(FloatingPlayer), matching: find.text(t.title));
  expect(bar, findsOneWidget, reason: '$step: bar shows ${t.title}');
  expect(_shownSharpUrl(tester), artUrl(t.artworkUrl, ArtSize.t500), reason: '$step: sharp cover');
  expect(_scene(tester).art.value?.url, t.artworkUrl, reason: '$step: halo art');
  final halo = tester.widget<RawImage>(
    find
        .descendant(of: find.byKey(const ValueKey('focus-halo')), matching: find.byType(RawImage))
        .last,
  );
  expect(
    halo.image,
    same(_scene(tester).art.value!.glow),
    reason: '$step: halo is the current track\'s',
  );
  expect(h.services.focus.isOn, isTrue, reason: '$step: focus stays open');
}

void main() {
  setUpAll(() async {
    for (final f in Directory('test/previews/covers').listSync().whereType<File>()) {
      pv.covers[f.uri.pathSegments.last.split('.').first] = f.readAsBytesSync();
    }
    ArtCache.override = (url) {
      final m = RegExp(r'artworks-([a-z]+)-').firstMatch(url);
      return MemoryImage(pv.covers[m?.group(1)] ?? pv.covers['harbor']!);
    };
    await pv.loadFonts();
  });

  testWidgets('cover click enters and leaves focus; Esc leaves it; there is no ✕', (tester) async {
    final h = await _boot(tester);
    expect(_sharpOpacity(tester), 0);
    await _enter(tester);
    expect(h.services.focus.isOn, isTrue);
    expect(_sharpOpacity(tester), 1);
    expect(_opacityAbove(tester, find.byType(NavTabs)), 0);
    expect(find.byKey(const ValueKey('focus-close')), findsNothing);
    expect(find.byKey(const ValueKey('focus-x')), findsNothing);

    await tester.tap(_cover);
    await tester.pump();
    expect(h.services.focus.isOn, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_sharpOpacity(tester), inExclusiveRange(0, 1), reason: 'the exit animates');
    await tester.pump(FocusGeo.glow);
    await tester.pump();
    expect(_sharpOpacity(tester), 0);
    expect(_opacityAbove(tester, find.byType(NavTabs)), 1);

    await _enter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);
  });

  testWidgets('enter and leave 10 times in a row, mid-animation too', (tester) async {
    final h = await _boot(tester);
    final rest = tester.getRect(find.byType(FloatingPlayer));
    for (var i = 0; i < 10; i++) {
      await tester.tap(_cover);
      await tester.pump(Duration(milliseconds: i.isEven ? 120 : 420));
      await tester.tap(_cover);
      await tester.pump(Duration(milliseconds: i.isEven ? 90 : 420));
    }
    await tester.pump(FocusGeo.glow);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(h.services.focus.isOn, isFalse);
    expect(_sharpOpacity(tester), 0);
    expect(tester.getRect(find.byType(FloatingPlayer)), rest);
    expect(_opacityAbove(tester, find.byType(NavTabs)), 1);
  });

  testWidgets(
    'panel open in focus: cover and bar centre in the free area; Esc closes the panel first',
    (tester) async {
      const size = Size(1920, 1080);
      final h = await _boot(tester);
      await _enter(tester);
      expect(tester.getRect(_sharp).center.dx, closeTo(size.width / 2, 0.5));
      expect(tester.getRect(find.byType(FloatingPlayer)).center.dx, closeTo(size.width / 2, 0.5));

      // Open the panel from the bar: Focus stays.
      final box = tester.getRect(find.byType(FloatingPlayer));
      await tester.tapAt(Offset(box.right - 6, box.top + 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.getRect(_sharp).center.dx;
      expect(mid, lessThan(size.width / 2), reason: 'it glides, not jumps');
      await pv.settle(tester);
      expect(h.services.focus.isOn, isTrue);
      expect(h.services.panel.isOpen, isTrue);
      final panelLeft = PanelGeo(size, 1).panelLeft;
      final free = FocusGeo.freeWidth(size.width, panelLeft, 1);
      expect(free, lessThan(size.width));
      final cover = tester.getRect(_sharp);
      final bar = tester.getRect(find.byType(FloatingPlayer));
      expect(cover.center.dx, closeTo(free / 2, 0.5));
      expect(bar.center.dx, closeTo(free / 2, 0.5));
      expect(cover.right, lessThan(panelLeft), reason: 'clear of the panel');
      expect(bar.right, lessThan(panelLeft));
      final panel = tester.getRect(find.byType(TrackPanelView));
      expect(panel.left, greaterThanOrEqualTo(cover.right));
      expect(find.byType(TrackPanelView), findsOneWidget, reason: 'the panel stays in focus');

      // Esc: the panel first, Focus second.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pv.settle(tester);
      expect(h.services.panel.isOpen, isFalse);
      expect(h.services.focus.isOn, isTrue, reason: 'one Esc is one step');
      expect(tester.getRect(_sharp).center.dx, closeTo(size.width / 2, 0.5));
      expect(tester.getRect(find.byType(FloatingPlayer)).center.dx, closeTo(size.width / 2, 0.5));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pv.settle(tester);
      expect(h.services.focus.isOn, isFalse);
      expect(h.services.panel.isOpen, isFalse);
    },
  );

  testWidgets('Esc with the panel open and Focus on: panel, then Focus, in two presses', (
    tester,
  ) async {
    final h = await _boot(tester);
    h.services.panel.show();
    await pv.settle(tester);
    await _enter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
    expect(h.services.focus.isOn, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);
  });

  testWidgets('empty capsule space in focus opens the panel and stays in focus', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    final box = tester.getRect(find.byType(FloatingPlayer));
    await tester.tapAt(Offset(box.right - 6, box.top + 4));
    await pv.settle(tester);
    expect(h.services.focus.isOn, isTrue);
    expect(h.services.panel.isOpen, isTrue);
    final moved = tester.getRect(find.byType(FloatingPlayer));
    await tester.tapAt(Offset(moved.right - 6, moved.top + 4));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
    expect(h.services.focus.isOn, isTrue);
  });

  testWidgets('bar and cursor hide after 3 s still, come back on movement', (tester) async {
    final h = await _boot(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(200, 300));
    await tester.pump();
    await _enter(tester);
    await mouse.moveTo(const Offset(220, 300));
    await tester.pump(const Duration(milliseconds: 2900));
    expect(_barOpacity(tester), 1, reason: 'still up before 3 s');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_barOpacity(tester), inExclusiveRange(0, 1), reason: 'fading over 300 ms');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_barOpacity(tester), 0);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.none,
    );

    await mouse.moveTo(const Offset(240, 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(_barOpacity(tester), 1);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      isNot(SystemMouseCursors.none),
    );

    // A pointer resting on the bar hides it too, and the cursor goes with it.
    await mouse.moveTo(tester.getCenter(find.byType(FloatingPlayer)));
    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump(FocusGeo.hide);
    await tester.pump();
    expect(_barOpacity(tester), 0, reason: 'resting on the capsule does not keep it up');
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.none,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(_barOpacity(tester), 0, reason: 'it stays hidden, no flicker');

    await mouse.moveTo(tester.getCenter(find.byType(FloatingPlayer)) + const Offset(3, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_barOpacity(tester), 1);

    final seek = tester.getRect(find.byType(SeekLine));
    await mouse.moveTo(seek.center);
    await mouse.down(seek.center);
    await tester.pump();
    await mouse.moveTo(seek.center + const Offset(40, -300));
    await tester.pump(const Duration(seconds: 4));
    expect(_barOpacity(tester), 1, reason: 'a slider drag keeps it up');
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump(FocusGeo.hide);
    await tester.pump();
    expect(_barOpacity(tester), 0);
    expect(h.services.focus.isOn, isTrue);
  });

  testWidgets('cover 480–520, at most the window height minus 240; bar a third of the way down', (
    tester,
  ) async {
    expect(FocusGeo.side(const Size(1920, 1080)), 520);
    expect(FocusGeo.side(const Size(2560, 1440)), 520);
    expect(FocusGeo.side(const Size(1280, 800)), 480);
    expect(FocusGeo.side(const Size(1000, 600)), 360);
    expect(FocusGeo.side(const Size(400, 900)), 240);
    for (final size in const [Size(1920, 1080), Size(1280, 800), Size(1000, 600)]) {
      await _boot(tester, size: size);
      await _enter(tester);
      final rect = tester.getRect(_sharp);
      final side = FocusGeo.side(size);
      expect(rect.width, closeTo(side, 0.5), reason: '$size');
      expect(side, lessThanOrEqualTo(size.height - 240), reason: '$size');
      expect(rect.center.dx, closeTo(size.width / 2, 0.5));
      final bar = tester.getRect(find.byType(FloatingPlayer));
      expect(
        bar.top - rect.bottom,
        closeTo((size.height - rect.bottom) / 3, 0.5),
        reason: 'the bar is a third of the way down, $size',
      );
      expect(
        rect.top,
        closeTo(size.height - bar.bottom, 0.5),
        reason: 'equal air above the cover and under the bar, $size',
      );
      expect(bar.bottom, lessThanOrEqualTo(size.height), reason: 'the bar always fits');
      expect(bar.width, closeTo(FocusGeo.barWidth(size.width, PlayerGeo.width(size.width)), 0.01));
      expect(bar.width, greaterThanOrEqualTo(PlayerGeo.width(size.width)));
    }
    expect(FocusGeo.barWidth(1920, 720), 880, reason: 'wider than the 720 dp bar outside Focus');
  });

  testWidgets('Space and arrows work in focus, not inside the search field', (tester) async {
    final h = await _boot(tester);
    final p = h.services.player;
    await _enter(tester);
    final start = p.position.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(p.position.value - start, const Duration(seconds: 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(start - p.position.value, const Duration(seconds: 5));
    final playing = p.playing;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pv.settle(tester);
    expect(p.playing, !playing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pv.settle(tester);
    expect(p.playing, playing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    await tester.tap(find.byType(SearchField));
    await tester.pump();
    final before = p.position.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await pv.settle(tester);
    expect(p.position.value, before);
    expect(p.playing, playing);
  });

  testWidgets('double click on a track plays it and opens focus; one click only plays', (
    tester,
  ) async {
    final h = await _boot(tester);
    final row = find.ancestor(of: find.text('Copper Almanac'), matching: find.byType(TrackRow));
    await tester.tap(row);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(h.services.player.current?.title, 'Copper Almanac', reason: 'no wait for a 2nd click');
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.services.focus.isOn, isFalse);

    final other = find.ancestor(
      of: find.text('Second Breakfast Protocol'),
      matching: find.byType(TrackRow),
    );
    await tester.tap(other);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(other);
    await tester.pump();
    expect(h.services.player.current?.title, 'Second Breakfast Protocol');
    expect(h.services.focus.isOn, isTrue);
  });

  testWidgets('focus: a static dark base, no orbs or wash, only the cover halo', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    await _waitInSync(tester, h);
    expect(_washes(), findsNothing, reason: 'the main wash is not built');
    expect(find.byKey(const ValueKey('focus-backdrop')), findsNothing);
    expect(find.byKey(const ValueKey('backdrop-beat')), findsNothing);
    expect(find.byKey(const ValueKey('backdrop-spot-0')), findsNothing);
    final base = find.byKey(const ValueKey('focus-base'));
    expect(base, findsOneWidget);
    expect(tester.widget<ColoredBox>(base).color, AgColors.nightWash);
    expect(tester.getTopLeft(base), Offset.zero);
    expect(tester.getSize(base), const Size(1920, 1080));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('focus-halo')),
        matching: find.byType(RawImage),
      ),
      findsOneWidget,
    );

    // A track change must not rebuild or recolour the base.
    await tester.tap(byLabel('Next'));
    await pv.settle(tester);
    await _waitInSync(tester, h);
    expect(tester.widget<ColoredBox>(base).color, AgColors.nightWash);
    expect(_washes(), findsNothing);
    expect(find.byKey(const ValueKey('focus-backdrop')), findsNothing);
  });

  testWidgets('halo: a blurred copy 15% larger at 60%, under the sharp cover', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    await _waitInSync(tester, h);
    final side = tester.getRect(_sharp).width;
    final halo = find.descendant(
      of: find.byKey(const ValueKey('focus-halo')),
      matching: find.byType(RawImage),
    );
    expect(halo, findsOneWidget);
    final raw = tester.widget<RawImage>(halo);
    expect(raw.color?.a, closeTo(FocusGeo.haloAlpha, 0.01));
    expect(raw.colorBlendMode, BlendMode.modulate);
    expect(
      raw.image,
      same(_scene(tester).art.value!.glow),
      reason: 'built once with the track art',
    );
    final body = tester.getSize(halo).width * FocusGeo.haloBody;
    expect(body / side, closeTo(FocusGeo.halo, 0.01));
    expect(tester.getRect(halo).center, tester.getRect(_sharp).center);
    // Painted first, so the cover stays sharp on top of it.
    final stack = find.ancestor(of: _sharp, matching: find.byType(Stack)).first;
    final kids = tester.widget<Stack>(stack).children;
    expect(kids.first.runtimeType.toString(), '_Halo');
  });

  testWidgets('cover switch: two covers cross-fade over 600 ms, keyed by track', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    await _waitInSync(tester, h);
    final first = _shownSharpUrl(tester);
    expect(FocusGeo.swap, const Duration(milliseconds: 600));
    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(of: _sharp, matching: find.byType(AnimatedSwitcher)).first,
    );
    expect(switcher.duration, FocusGeo.swap);

    final id = h.services.player.current!.id;
    await tester.tap(byLabel('Next'));
    // Step in small slices so the check lands inside the 600 ms switch.
    var want = first;
    for (var i = 0; i < 400 && want == first; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
      final cur = h.services.player.current!;
      if (cur.id != id && _shownSharpUrl(tester) == artUrl(cur.artworkUrl, ArtSize.t500)) {
        want = _shownSharpUrl(tester);
      }
    }
    expect(want, isNot(first));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final images = find.descendant(
      of: _sharp,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Image && (w.key as ValueKey?)?.value.toString().startsWith('focus-image|') == true,
      ),
    );
    expect(images, findsNWidgets(2), reason: 'old and new cover are both up mid-switch');
    final fades = find
        .descendant(of: _sharp, matching: find.byType(FadeTransition))
        .evaluate()
        .map((e) => (e.widget as FadeTransition).opacity.value)
        .toList();
    expect(fades.any((v) => v > 0 && v < 1), isTrue, reason: 'the new cover fades in: $fades');
    await tester.pump(FocusGeo.swap);
    await tester.pump();
    expect(images, findsOneWidget);
    expect(_shownSharpUrl(tester), want);
  });

  testWidgets('regression: focus cover and halo follow every track change', (tester) async {
    final h = await _boot(tester);
    final p = h.services.player;
    await _enter(tester);
    await _waitInSync(tester, h);
    _expectInSync(tester, h, 'open');
    for (var i = 0; i < 3; i++) {
      await tester.tap(byLabel('Next'));
      await pv.settle(tester);
      await _waitInSync(tester, h);
      _expectInSync(tester, h, 'next ${i + 1}');
    }
    await tester.tap(byLabel('Previous'));
    await pv.settle(tester);
    await _waitInSync(tester, h);
    _expectInSync(tester, h, 'previous');
    final before = p.current!.id;
    final length = Duration(milliseconds: p.current!.durationMs);
    h.backend.emitDuration(length);
    h.backend.emitPosition(length - const Duration(seconds: 1));
    await pv.settle(tester);
    h.backend.finish();
    await pv.settle(tester);
    await _waitInSync(tester, h);
    expect(p.current!.id, isNot(before), reason: 'the track ended by itself');
    _expectInSync(tester, h, 'natural end');
    await tester.runAsync(() => p.playAt(p.queue.index + 2));
    await pv.settle(tester);
    await _waitInSync(tester, h);
    _expectInSync(tester, h, 'from the queue');
  });
}
