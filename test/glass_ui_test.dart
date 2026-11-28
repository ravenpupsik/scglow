import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/app/session_controller.dart';
import 'package:scglow/app/ui_state.dart';
import 'package:scglow/ui/player_dock.dart';
import 'package:scglow/ui/screens/track_screen.dart';
import 'package:scglow/ui/theme/tokens.dart';
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/widgets/art_image.dart';
import 'package:scglow/ui/widgets/buttons.dart';
import 'package:scglow/ui/widgets/glass.dart';
import 'package:scglow/ui/widgets/icons.dart';
import 'package:scglow/ui/widgets/interactive.dart';
import 'package:scglow/ui/widgets/track_row.dart';

import 'previews/preview_test.dart' as pv;
import 'support/finders.dart';

Matrix4 smokeTransform(WidgetTester tester) => tester
    .widget<Transform>(find.descendant(
        of: find.byType(SmokeBackground), matching: find.byType(Transform)))
    .transform;

void main() {
  setUpAll(() async {
    for (final f in Directory('test/previews/covers').listSync().whereType<File>()) {
      pv.covers[f.uri.pathSegments.last.split('.').first] = f.readAsBytesSync();
    }
    ArtCache.override = (url) => MemoryImage(pv.covers['harbor']!);
  });

  testWidgets('floating capsule: 76 dp, 560 at 1280, centred, 16 dp up',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    expect(find.byType(BackdropFilter), findsNothing);
    final r = tester.getRect(find.byType(FloatingPlayer));
    expect(r.size, const Size(560, Dp.playerH));
    expect(r.center.dx, closeTo(640, 0.01));
    expect(800 - r.bottom, closeTo(Dp.playerBottom, 0.01));
    expect(find.byType(PlayDrop), findsOneWidget);
    expect(find.text('Log out…'), findsNothing);
    expect(find.text('Likes'), findsWidgets);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
  });

  test('capsule width: 560 at 1280, 720 at 1920, clamped', () {
    expect(PlayerGeo.width(960), 560);
    expect(PlayerGeo.width(1280), 560);
    expect(PlayerGeo.width(1600), 640);
    expect(PlayerGeo.width(1920), 720);
    expect(PlayerGeo.width(2560), 720);
  });

  testWidgets('seek row sits inside the capsule; times never overflow',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark, size: const Size(960, 600));
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    final player = tester.getRect(find.byType(FloatingPlayer));
    final seek = tester.getRect(find.byType(SeekLine));
    expect(seek.center.dy - player.top, closeTo(Dp.playerH - 14, 0.01));
    expect(seek.height, greaterThanOrEqualTo(12));
    for (final t in ['1:24', '3:42']) {
      final r = tester.getRect(find.descendant(
          of: find.byType(FloatingPlayer), matching: find.text(t)));
      expect(player.inflate(0.01).contains(r.topLeft), isTrue);
      expect(player.inflate(0.01).contains(r.bottomRight), isTrue);
    }
    expect(tester.getCenter(find.descendant(
            of: find.byType(FloatingPlayer), matching: find.text('1:24'))).dx,
        lessThan(seek.left));
    expect(tester.getCenter(find.descendant(
            of: find.byType(FloatingPlayer), matching: find.text('3:42'))).dx,
        greaterThan(seek.right));
  });

  testWidgets('list column: 24 dp margins at 960, 1140 dp max', (tester) async {
    await pv.boot(tester, ThemeMode.dark, size: const Size(960, 600));
    final card = tester.getRect(find.byType(GroupCard).first);
    expect(card.left, closeTo(24, 0.5));
    expect(card.right, closeTo(936, 0.5));
    await pv.boot(tester, ThemeMode.dark, size: const Size(1600, 900));
    expect(tester.getRect(find.byType(GroupCard).first).width, closeTo(1140, 0.5));
  });

  testWidgets('missing artwork shows the note tile', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AgColors.night),
      home: const Center(child: ArtImage(url: null, size: 32)),
    ));
    expect(find.byType(ArtPlaceholder), findsOneWidget);
    expect(isDefaultArt('https://a1.sndcdn.com/images/default_avatar_large.png'),
        isTrue);
  });

  testWidgets('refresh has a tooltip; Play all is primary', (tester) async {
    await pv.boot(tester, ThemeMode.dark);
    expect(byLabel('Refresh'), findsOneWidget);
    expect(find.byType(PlayAllChip), findsOneWidget);
  });

  testWidgets('panel button toggles the panel; × and Esc close it',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.light, size: const Size(1920, 1080));
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    final player = find.byType(FloatingPlayer);
    await tester.tap(find.descendant(of: player, matching: find.text('Mira Solen')));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse, reason: 'only the button opens it');
    await tester.tap(find.byKey(const ValueKey('panel-button')));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isTrue);
    expect(find.byType(TrackPanelView), findsOneWidget);
    expect(find.byType(TrackScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('panel-button')));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
    expect(find.byType(TrackPanelView), findsNothing);
    expect(player, findsOneWidget);
    h.services.panel.show();
    await pv.settle(tester);
    await tester.tap(byLabel('Close'));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
    expect(find.byType(TrackPanelView), findsNothing);
    h.services.panel.show();
    await pv.settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
  });

  testWidgets('wide panel: list 55 % at x 40, panel beside it, above capsule',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1920, 1080));
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    final closed = tester.getRect(find.byType(GroupCard).first);
    expect(closed.width, closeTo(1140, 0.5));
    expect(closed.center.dx, closeTo(960, 0.5));
    h.services.panel.show();
    await pv.settle(tester);
    final card = tester.getRect(find.byType(GroupCard).first);
    expect(card.left, closeTo(40, 0.5));
    expect(card.width, closeTo(1056, 0.5));
    final panel = tester.getRect(find.byType(TrackPanelView));
    const playerY = 1080 - 16 - Dp.playerH;
    expect(panel.left, closeTo(1124, 0.5));
    expect(panel.width, closeTo(756, 0.5));
    expect(panel.top, closeTo(60, 0.5));
    expect(panel.bottom, closeTo(playerY - 16, 0.5));
    expect(card.bottom, lessThanOrEqualTo(playerY - 20 + 0.5));
    final capsule = tester.getRect(find.byType(FloatingPlayer));
    expect(capsule.size, const Size(720, Dp.playerH));
    expect(capsule.top, closeTo(playerY, 0.01));
    for (final t in ['Queue', 'Related', 'Comments', 'Now playing', 'Next up']) {
      expect(find.descendant(of: find.byType(TrackPanelView), matching: find.text(t)),
          findsOneWidget);
    }
    expect(find.text('Liked'), findsOneWidget);
    expect(find.byType(JumpToCurrent), findsOneWidget);
  });

  testWidgets('narrow overlay: 420 dp panel, scrim closes, list stays',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1280, 800));
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    final before = tester.getRect(find.byType(GroupCard).first);
    h.services.panel.show();
    await pv.settle(tester);
    final after = tester.getRect(find.byType(GroupCard).first);
    expect(after, before);
    final panel = tester.getRect(find.byType(TrackPanelView));
    expect(panel.left, closeTo(844, 0.5));
    expect(panel.width, closeTo(420, 0.5));
    await tester.tapAt(const Offset(300, 300));
    await pv.settle(tester);
    expect(h.services.panel.isOpen, isFalse);
  });

  testWidgets('shuffle / repeat: dot when on, «1» for repeat one, no red',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    await tester.runAsync(() => h.playHarbor(shuffle: true, repeatOne: true));
    await pv.settle(tester);
    final toggles = tester.widgetList<ModeToggle>(find.byType(ModeToggle)).toList();
    expect(toggles.map((t) => t.on), [true, true]);
    expect(toggles.last.one, isTrue);
    expect(find.descendant(of: find.byType(ModeToggle).last, matching: find.text('1')),
        findsOneWidget);
    expect(byLabel('Shuffle on'), findsOneWidget);
    expect(byLabel('Repeat one'), findsOneWidget);
  });

  testWidgets('only the panel button has a hover tooltip', (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1920, 1080));
    await tester.runAsync(() => h.playHarbor());
    h.services.panel.show();
    await pv.settle(tester);
    expect(find.byType(Tooltip), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final buttons = find.byWidgetPredicate(
        (w) => w is Interactive && w.semanticLabel != null);
    final labels = tester
        .widgetList<Interactive>(buttons)
        .map((w) => w.semanticLabel!)
        .toSet();
    expect(labels, containsAll(['Shuffle off', 'Previous', 'Next', 'Mute',
        'Account', 'Minimize', 'Close to tray', 'Close', 'Hide track panel']));
    for (final l in labels) {
      await mouse.moveTo(tester.getCenter(byLabel(l).first));
      await tester.pump(const Duration(seconds: 2));
      if (l == 'Hide track panel') {
        expect(find.text(PanelButton.label), findsOneWidget);
      } else {
        expect(find.text(PanelButton.label), findsNothing, reason: l);
      }
    }
    await mouse.moveTo(Offset.zero);
    await pv.settle(tester);
  });

  testWidgets('comment marks: dots on the capsule bar, count on hover',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1920, 1080));
    await tester.runAsync(() => h.playHarbor(atSec: 40));
    await pv.settle(tester);
    final seek = tester.getRect(find.byType(SeekLine));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(Offset(seek.left + seek.width * 84 / 222, seek.center.dy));
    await tester.pump();
    expect(find.text('1 comment'), findsOneWidget);
    final tip = tester.getRect(find.byType(CountTip));
    expect(tip.bottom, lessThan(tester.getRect(find.byType(FloatingPlayer)).top));
    await gesture.moveTo(Offset(seek.left + seek.width * 13 / 222, seek.center.dy));
    await tester.pump();
    expect(find.text('3 comments'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('tabs switch sections', (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    await tester.tap(find.text('Queue'));
    await pv.settle(tester);
    expect(h.services.nav.section, Section.queue);
    await tester.tap(find.text('Playlists'));
    await pv.settle(tester);
    expect(h.services.nav.section, Section.playlists);
  });

  testWidgets('avatar menu sets the theme', (tester) async {
    final h = await pv.boot(tester, ThemeMode.light);
    await tester.tap(byLabel('Account'));
    await pv.settle(tester);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    await tester.tap(find.text('Night'));
    await pv.settle(tester);
    expect(h.services.theme.value, ThemeMode.dark);
    expect(h.services.prefs!.getString('theme_mode'), isNotNull);
  });

  testWidgets('tint from cover and pulse to beat: on by default, persisted',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    expect(h.services.tint.value, isTrue);
    expect(h.services.pulse.value, isTrue);
    await tester.tap(byLabel('Account'));
    await pv.settle(tester);
    expect(find.text('Off automatically if Windows\nreduce animations is on.'),
        findsOneWidget);
    await tester.tap(find.text('Tint from cover'));
    await pv.settle(tester);
    expect(h.services.tint.value, isFalse);
    expect(h.services.prefs!.getBool('tint_from_cover'), isFalse);
    await tester.tap(find.text('Pulse to beat'));
    await pv.settle(tester);
    expect(h.services.pulse.value, isFalse);
    expect(h.services.prefs!.getBool('pulse_to_beat'), isFalse);
    expect(PulseController(h.services.prefs).value, isFalse);
  });

  testWidgets('logout Cancel keeps the session', (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    await tester.tap(byLabel('Account'));
    await pv.settle(tester);
    await tester.tap(find.text('Log out…'));
    await pv.settle(tester);
    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pv.settle(tester);
    expect(find.text('Log out?'), findsNothing);
    expect(h.services.session.state, SessionState.ready);
  });

  testWidgets('sort chip persists the choice', (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    await tester.tap(find.text('Date liked'));
    await pv.settle(tester);
    await tester.tap(find.text('Title'));
    await pv.settle(tester);
    expect(find.text('Title'), findsOneWidget);
    expect(h.services.prefs!.get('likes_sort'), isNotNull);
  });

  testWidgets('liked hearts rest grey, turn red on row hover', (tester) async {
    await pv.boot(tester, ThemeMode.dark);
    final c = AgColors.night;
    Color heartOf(String title) => tester
        .widget<AgIcon>(find.descendant(
            of: find.ancestor(of: find.text(title), matching: find.byType(TrackRow)),
            matching: find.byType(AgIcon)))
        .color;
    expect(heartOf('Copper Almanac'), c.heartRest);
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    await g.moveTo(tester.getCenter(find.text('Copper Almanac')));
    await tester.pump();
    expect(heartOf('Copper Almanac'), c.accent);
    await g.removePointer();
  });

  testWidgets('close button hides to the tray', (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    h.services.window.active.value = true;
    await tester.tap(byLabel('Close to tray'));
    await tester.pump();
    expect(h.services.window.active.value, isFalse);
  });

  testWidgets('background drifts, but holds still with reduce motion',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    h.services.window.active.value = true;
    final a = smokeTransform(tester).clone();
    await pv.settle(tester);
    expect(smokeTransform(tester), isNot(equals(a)));
    h.services.window.active.value = false;

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    h.services.window.active.value = true;
    final b = smokeTransform(tester).clone();
    await pv.settle(tester);
    expect(smokeTransform(tester), equals(b));
  });

  test('blob orbit: visible ellipse, 24 s, scale 0.96-1.06', () {
    expect(SmokeBackground.period, const Duration(seconds: 24));
    final poses = [for (var i = 0; i < 96; i++) SmokeBackground.pose(i / 96)];
    final xs = poses.map((p) => p.$1), ys = poses.map((p) => p.$2);
    final ss = poses.map((p) => p.$3);
    double span(Iterable<double> v) =>
        v.reduce((a, b) => a > b ? a : b) - v.reduce((a, b) => a < b ? a : b);
    expect(span(xs), closeTo(0.20, 0.005));
    expect(span(ys), closeTo(0.16, 0.005));
    expect(ss.reduce((a, b) => a < b ? a : b), closeTo(0.96, 0.001));
    expect(ss.reduce((a, b) => a > b ? a : b), closeTo(1.06, 0.001));
    final a = SmokeBackground.pose(0), b = SmokeBackground.pose(0.25);
    final c = SmokeBackground.pose(0.5);
    expect((a.$2 - c.$2).abs(), lessThan(1e-9));
    expect((b.$2 - a.$2).abs(), closeTo(0.08, 1e-9));
  });

  testWidgets('player transport is symmetric around the Play drop',
      (tester) async {
    final h = await pv.boot(tester, ThemeMode.dark);
    await tester.runAsync(() => h.playHarbor());
    await pv.settle(tester);
    double x(Finder f) => tester.getCenter(f).dx;
    Finder btn(Set<AgGlyph> g) => find.descendant(
        of: find.byType(FloatingPlayer),
        matching: find.byWidgetPredicate((w) =>
            (w is PlainIcon && g.contains(w.glyph)) ||
            (w is ModeToggle && g.contains(w.glyph))));
    final shuffle = x(btn({AgGlyph.shuffle}));
    final prev = x(btn({AgGlyph.prev}));
    final play = x(find.byType(PlayDrop));
    final next = x(btn({AgGlyph.next}));
    final repeat = x(btn({AgGlyph.repeat, AgGlyph.repeatOne}));
    expect(play, closeTo(tester.getCenter(find.byType(FloatingPlayer)).dx, 1.01));
    expect(next - play, closeTo(play - prev, 0.01));
    expect(repeat - play, closeTo(play - shuffle, 0.01));
    expect(prev - shuffle, closeTo(repeat - next, 0.01));
    expect(prev - shuffle, lessThan(play - prev));
  });
}
