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
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/widgets/art_image.dart';
import 'package:scglow/ui/widgets/track_row.dart';

import 'previews/preview_test.dart' as pv;
import 'support/finders.dart';

final _cover = find.byKey(const ValueKey('capsule-cover'));
final _x = find.byKey(const ValueKey('focus-close'));
final _sharp = find.byKey(const ValueKey('focus-cover'));

double _opacityAbove(WidgetTester tester, Finder f) => tester
    .widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first)
    .opacity;

double _barOpacity(WidgetTester tester) =>
    _opacityAbove(tester, find.byType(FloatingPlayer));

double _sharpOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
        find.ancestor(of: _sharp, matching: find.byType(FadeTransition)).first)
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

// Waits until the sharp cover and the backdrop art both show the current track.
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
  expect(_scene(tester).art.value?.url, t.artworkUrl, reason: '$step: backdrop art');
  final glow = tester.widget<FocusGlow>(find.byType(FocusGlow));
  expect(glow.art?.url, t.artworkUrl, reason: '$step: glow palette');
  expect(glow.art?.palette, isNotEmpty);
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

  testWidgets('cover click enters and leaves focus; Esc and × leave it', (tester) async {
    final h = await _boot(tester);
    expect(_sharpOpacity(tester), 0);
    await _enter(tester);
    expect(h.services.focus.isOn, isTrue);
    expect(_sharpOpacity(tester), 1);
    expect(_opacityAbove(tester, find.byType(NavTabs)), 0);
    expect(_opacityAbove(tester, _x), 1);

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

    await _enter(tester);
    await tester.tap(_x);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);
    expect(_opacityAbove(tester, _x), 0);
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

  testWidgets('focus hides the open panel and brings it back afterwards', (tester) async {
    final h = await _boot(tester);
    h.services.panel.show();
    await pv.settle(tester);
    await _enter(tester);
    expect(_opacityAbove(tester, find.byType(TrackPanelView)), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isTrue);
    expect(_opacityAbove(tester, find.byType(TrackPanelView)), 1);
  });

  testWidgets('empty capsule space in focus leaves focus and opens the panel', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    final box = tester.getRect(find.byType(FloatingPlayer));
    await tester.tapAt(Offset(box.right - 6, box.top + 4));
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);
    expect(h.services.panel.isOpen, isTrue);
  });

  testWidgets('bar and cursor hide after 2.5 s still, come back on movement', (tester) async {
    final h = await _boot(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(200, 300));
    await tester.pump();
    await _enter(tester);
    await mouse.moveTo(const Offset(220, 300));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(_barOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_barOpacity(tester), inExclusiveRange(0, 1), reason: 'fading over 300 ms');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_barOpacity(tester), 0);
    expect(_opacityAbove(tester, _x), 0, reason: '× hides with the bar');
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.none);

    await mouse.moveTo(const Offset(240, 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(_barOpacity(tester), 1);
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        isNot(SystemMouseCursors.none));

    await mouse.moveTo(tester.getCenter(find.byType(FloatingPlayer)));
    await tester.pump(const Duration(seconds: 4));
    expect(_barOpacity(tester), 1, reason: 'resting on the capsule keeps it up');

    final seek = tester.getRect(find.byType(SeekLine));
    await mouse.moveTo(seek.center);
    await mouse.down(seek.center);
    await tester.pump();
    await mouse.moveTo(seek.center + const Offset(40, -300));
    await tester.pump(const Duration(seconds: 4));
    expect(_barOpacity(tester), 1, reason: 'a slider drag keeps it up');
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(FocusGeo.hide);
    await tester.pump();
    expect(_barOpacity(tester), 0);
    expect(h.services.focus.isOn, isTrue);
  });

  testWidgets('cover 440–480, at most the window height minus 260; group centred', (tester) async {
    expect(FocusGeo.side(const Size(1920, 1080)), closeTo(475.2, 0.01));
    expect(FocusGeo.side(const Size(2560, 1440)), 480);
    expect(FocusGeo.side(const Size(1280, 800)), 440);
    expect(FocusGeo.side(const Size(1000, 600)), 340);
    expect(FocusGeo.side(const Size(400, 900)), 240);
    for (final size in const [Size(1920, 1080), Size(1000, 600)]) {
      await _boot(tester, size: size);
      await _enter(tester);
      final rect = tester.getRect(_sharp);
      final side = FocusGeo.side(size);
      expect(rect.width, closeTo(side, 0.5), reason: '$size');
      expect(rect.center.dx, closeTo(size.width / 2, 0.5));
      final bar = tester.getRect(find.byType(FloatingPlayer));
      expect(bar.top - rect.bottom, closeTo(FocusGeo.barGap, 0.5), reason: '$size');
      expect((rect.top + bar.bottom) / 2, closeTo(size.height / 2, 0.5),
          reason: 'cover and bar centred together, $size');
      expect(bar.bottom, lessThanOrEqualTo(size.height), reason: 'the bar always fits');
    }
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

  testWidgets('double click on a track plays it and opens focus; one click only plays',
      (tester) async {
    final h = await _boot(tester);
    final row = find.ancestor(of: find.text('Copper Almanac'), matching: find.byType(TrackRow));
    await tester.tap(row);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(h.services.player.current?.title, 'Copper Almanac', reason: 'no wait for a 2nd click');
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.services.focus.isOn, isFalse);

    final other = find.ancestor(of: find.text('Second Breakfast Protocol'), matching: find.byType(TrackRow));
    await tester.tap(other);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(other);
    await tester.pump();
    expect(h.services.player.current?.title, 'Second Breakfast Protocol');
    expect(h.services.focus.isOn, isTrue);
  });

  testWidgets('focus backdrop: the square spot dissolves, palette spots drift', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    await _waitInSync(tester, h);
    final spot = find.descendant(
        of: find.byType(CoverBackground), matching: find.byType(RawImage));
    for (final e in spot.evaluate()) {
      final fades = find.ancestor(of: find.byWidget(e.widget), matching: find.byType(FadeTransition));
      final min = tester
          .widgetList<FadeTransition>(fades)
          .map((f) => f.opacity.value)
          .reduce((a, b) => a < b ? a : b);
      expect(min, 0, reason: 'the blurred square is fully faded');
    }
    expect(find.byKey(const ValueKey('focus-glow')), findsOneWidget);
    Offset spotAt() => tester.getCenter(find.byKey(const ValueKey('glow-spot-0')));
    final a = spotAt();
    await tester.pump(const Duration(seconds: 2));
    final b = spotAt();
    expect((a - b).distance, greaterThan(4), reason: 'colours flow');
    await tester.pump(const Duration(seconds: 8));
    expect((spotAt() - a).distance, lessThan(1), reason: 'one cycle is 10 s');
  });

  testWidgets('regression: focus cover and backdrop follow every track change', (tester) async {
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
