import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/ui/focus_view.dart';
import 'package:scglow/ui/player_dock.dart';
import 'package:scglow/ui/top_bar.dart';
import 'package:scglow/ui/track_panel.dart';

import 'previews/preview_test.dart' as pv;
import 'support/finders.dart';

final _cover = find.byKey(const ValueKey('capsule-cover'));
final _x = find.byKey(const ValueKey('focus-close'));

double _opacityAbove(WidgetTester tester, Finder f) => tester
    .widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first)
    .opacity;

double _barOpacity(WidgetTester tester) =>
    _opacityAbove(tester, find.byType(FloatingPlayer));

Future<pv.Harness> _boot(WidgetTester tester, {Size size = const Size(1920, 1080)}) async {
  final h = await pv.boot(tester, ThemeMode.dark, size: size);
  await tester.runAsync(() => h.playHarbor(atSec: 40));
  await pv.settle(tester);
  return h;
}

Future<void> _enter(WidgetTester tester) async {
  await tester.tap(_cover);
  await tester.pump();
  await tester.pump(FocusGeo.enter);
  await tester.pump();
}

void main() {
  testWidgets('cover click enters and leaves focus; Esc and × leave it', (tester) async {
    final h = await _boot(tester);
    expect(find.byKey(const ValueKey('focus-cover')), findsNothing);
    await _enter(tester);
    expect(h.services.focus.isOn, isTrue);
    expect(find.byKey(const ValueKey('focus-cover')), findsOneWidget);
    expect(_opacityAbove(tester, find.byType(NavTabs)), 0);
    expect(_x, findsOneWidget);

    await tester.tap(_cover);
    await tester.pump();
    expect(h.services.focus.isOn, isFalse);
    expect(find.byKey(const ValueKey('focus-cover')), findsOneWidget,
        reason: 'the exit animates');
    await tester.pump(FocusGeo.exit);
    await tester.pump();
    expect(find.byKey(const ValueKey('focus-cover')), findsNothing);
    expect(_opacityAbove(tester, find.byType(NavTabs)), 1);

    await _enter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);

    await _enter(tester);
    await tester.tap(_x);
    await pv.settle(tester);
    expect(h.services.focus.isOn, isFalse);
    expect(_x, findsNothing);
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

  testWidgets('panel button in focus leaves focus and opens the panel', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    await tester.tap(find.byKey(const ValueKey('panel-button')));
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

    // Resting on the capsule keeps it up.
    await mouse.moveTo(tester.getCenter(find.byType(FloatingPlayer)));
    await tester.pump(const Duration(seconds: 4));
    expect(_barOpacity(tester), 1);

    // So does a slider drag that leaves the capsule.
    final seek = tester.getRect(find.byType(SeekLine));
    await mouse.moveTo(seek.center);
    await mouse.down(seek.center);
    await tester.pump();
    await mouse.moveTo(seek.center + const Offset(40, -300));
    await tester.pump(const Duration(seconds: 4));
    expect(_barOpacity(tester), 1);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(FocusGeo.hide);
    await tester.pump();
    expect(_barOpacity(tester), 0);
    expect(h.services.focus.isOn, isTrue);
  });

  testWidgets('cover size: 380–440, at most the window minus 160', (tester) async {
    expect(FocusGeo.side(const Size(1920, 1080)), 440);
    expect(FocusGeo.side(const Size(2560, 1440)), 440);
    expect(FocusGeo.side(const Size(1280, 800)), 380);
    expect(FocusGeo.side(const Size(1000, 500)), 340);
    expect(FocusGeo.side(const Size(400, 900)), 240);
    for (final size in const [Size(1920, 1080), Size(1000, 520)]) {
      await _boot(tester, size: size);
      await _enter(tester);
      final rect = tester.getRect(find.byKey(const ValueKey('focus-cover')));
      final side = FocusGeo.side(size);
      expect(rect.width, closeTo(side, 0.5), reason: '$size');
      expect(rect.center.dx, closeTo(size.width / 2, 0.5));
      final bar = tester.getRect(find.byType(FloatingPlayer));
      expect(bar.top - rect.bottom, closeTo(FocusGeo.barGap, 0.5), reason: '$size');
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

  testWidgets('track change keeps focus on', (tester) async {
    final h = await _boot(tester);
    await _enter(tester);
    await tester.tap(byLabel('Next'));
    await pv.settle(tester);
    expect(h.services.focus.isOn, isTrue);
    expect(find.byKey(const ValueKey('focus-cover')), findsOneWidget);
  });
}
