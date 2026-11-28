import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/platform/taskbar_buttons.dart';
import 'package:scglow/ui/player_dock.dart';
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/widgets/art_image.dart';

import 'previews/preview_test.dart' as pv;

final _list = find.byKey(const ValueKey('list-column'));
final _panel = find.byType(TrackPanelView);
final _pending = find.byKey(const ValueKey('panel-list-pending'));

Future<pv.Harness> _boot(WidgetTester tester) async {
  final h = await pv.boot(tester, ThemeMode.dark, size: const Size(1920, 1080));
  await tester.runAsync(() => h.playHarbor(atSec: 40));
  await pv.settle(tester);
  return h;
}

// The size the list column is laid out at (the Positioned box), not where
// the transform paints it.
Size _listBox(WidgetTester tester) => tester.renderObject<RenderBox>(_list).size;

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

  testWidgets('panel slides by transform: no list relayout, lists built after the slide', (
    tester,
  ) async {
    final h = await _boot(tester);
    final closed = _listBox(tester);

    h.services.panel.show();
    await tester.pump();
    final first = _listBox(tester);
    expect(first.width, lessThan(closed.width), reason: 'the list takes its open width once');
    Size? panelSize;
    final lefts = <double>[];
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(_listBox(tester), first, reason: 'same layout size every frame');
      panelSize ??= tester.getSize(_panel);
      expect(tester.getSize(_panel), panelSize);
      expect(_pending, findsOneWidget, reason: 'no tab list while sliding');
      lefts.add(tester.getRect(_panel).left);
    }
    expect(lefts.first, greaterThan(lefts.last), reason: 'it moves');
    await pv.settle(tester);
    expect(_pending, findsNothing);
    expect(find.descendant(of: _panel, matching: find.byType(PanelTrackRow)), findsWidgets);
    final open = _listBox(tester);
    expect(open, first);

    h.services.panel.close();
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(_listBox(tester), open, reason: 'closing keeps the width until the end');
      expect(_pending, findsNothing, reason: 'the lists stay while it closes');
    }
    await pv.settle(tester);
    expect(_panel, findsNothing);
    expect(_listBox(tester), closed);
  });

  testWidgets('focus: the bar takes its wide width once, then only moves', (tester) async {
    final h = await _boot(tester);
    h.services.focus.enter();
    await tester.pump();
    final w = tester.getSize(find.byType(FloatingPlayer)).width;
    final tops = <double>[];
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(FloatingPlayer)).width, w);
      tops.add(tester.getRect(find.byType(FloatingPlayer)).top);
    }
    expect(tops.first, greaterThan(tops.last), reason: 'it lifts');
    expect(
      find.ancestor(of: find.byType(FloatingPlayer), matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    await pv.settle(tester);

    // Opening the panel in Focus sets the narrower width once as well.
    h.services.panel.show();
    await tester.pump();
    final narrow = tester.getSize(find.byType(FloatingPlayer)).width;
    expect(narrow, lessThanOrEqualTo(w));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(FloatingPlayer)).width, narrow);
    }
    await pv.settle(tester);
  });

  group('taskbar thumbnail buttons', () {
    test('previous, play/pause, next follow the player and are disabled without a track', () async {
      final sent = <List<TaskbarButton>>[];
      final clicks = <String>[];
      final tb = TaskbarButtons(
        onPrevious: () => clicks.add('prev'),
        onToggle: () => clicks.add('toggle'),
        onNext: () => clicks.add('next'),
        apply: (b) async => sent.add(b),
      );

      await tb.update(playing: false, hasTrack: false);
      expect(sent.single.map((b) => b.enabled), [false, false, false]);
      expect(sent.single.map((b) => b.icon), [
        TaskbarButtons.previousIcon,
        TaskbarButtons.playIcon,
        TaskbarButtons.nextIcon,
      ]);

      await tb.update(playing: true, hasTrack: true);
      expect(sent.last.map((b) => b.enabled), [true, true, true]);
      expect(sent.last[1].icon, TaskbarButtons.pauseIcon);
      expect(sent.last[1].tooltip, 'Pause');
      expect(sent.last.map((b) => b.tooltip), ['Previous', 'Pause', 'Next']);

      await tb.update(playing: true, hasTrack: true);
      expect(sent, hasLength(2), reason: 'no resend without a change');
      await tb.reapply();
      expect(sent, hasLength(3), reason: 'restore and show set them again');
      expect(sent.last[1].tooltip, 'Pause');

      await tb.update(playing: false, hasTrack: true);
      expect(sent.last[1].icon, TaskbarButtons.playIcon);
      expect(sent.last[1].tooltip, 'Play');

      for (final b in sent.last) {
        b.onClick();
      }
      expect(clicks, ['prev', 'toggle', 'next']);
    });

    test('icons: white .ico files with 16 and 32 px images', () {
      for (final path in [
        TaskbarButtons.previousIcon,
        TaskbarButtons.playIcon,
        TaskbarButtons.pauseIcon,
        TaskbarButtons.nextIcon,
      ]) {
        final bytes = File(path).readAsBytesSync();
        // ICONDIR: reserved 0, type 1, then one 16-byte entry per image.
        expect(bytes[0] | bytes[1] << 8, 0, reason: path);
        expect(bytes[2] | bytes[3] << 8, 1, reason: path);
        final count = bytes[4] | bytes[5] << 8;
        final sizes = {
          for (var i = 0; i < count; i++) bytes[6 + i * 16] == 0 ? 256 : bytes[6 + i * 16],
        };
        expect(sizes, containsAll([16, 32]), reason: path);
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/taskbar/'));
    });
  });
}
