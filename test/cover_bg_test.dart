import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/app/ui_state.dart';
import 'package:scglow/ui/cover_scene.dart';
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/theme/tokens.dart';
import 'package:scglow/ui/widgets/art_image.dart';
import 'package:scglow/ui/widgets/glass.dart';
import 'package:scglow/ui/widgets/track_row.dart';

import 'previews/preview_test.dart' as pv;

(int, int, int) rgb(Color c) =>
    ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

double sat(Color c) => HSLColor.fromColor(c).saturation;

String loudMaster() {
  final r = math.Random(7);
  const n = 1800, dur = 200000.0, beat = 480.0;
  return jsonEncode({
    'width': n,
    'height': 140,
    'samples': [
      for (var i = 0; i < n; i++)
        () {
          final t = i * dur / n;
          if (t > 182000) return 3 + r.nextInt(4);
          if (t >= 150000) return 137 + r.nextInt(3);
          final phase = (t % beat) / beat;
          final base = t < 20000 ? 70.0 : 132.0;
          final dip = phase > 0.75 ? base * (0.04 + 0.02 * r.nextDouble()) : 0;
          return (base - dip + r.nextInt(5) - 2).round().clamp(0, 140);
        }(),
    ],
  });
}

String spikyWave() => jsonEncode({
  'width': 1800,
  'height': 140,
  'samples': [
    for (var i = 0; i < 1800; i++) i > 1350 ? 2 : (i % 4 == 0 ? 140 : 42),
  ],
});

Finder washes() =>
    find.byWidgetPredicate((w) => w is CustomPaint && w.painter is WashPainter);

Finder spots() => find.descendant(
  of: find.descendant(
    of: find.byType(CoverBackground),
    matching: find.byType(ColorFiltered),
  ),
  matching: find.byType(RawImage),
);

double lum(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double contrast(Color a, Color b) {
  final x = lum(a), y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color worstUnderCard(AgColors c) {
  final night = c.isNight;
  final m = CoverBackground.tone(night);
  final px = night ? 255.0 : 0.0;
  final toned = (m[0] * px + m[4]).clamp(0.0, 255.0) / 255;
  final g = c.cardGlass;
  final v = g.r * g.a + toned * (1 - g.a);
  return Color.from(alpha: 1, red: v, green: v, blue: v);
}

void main() {
  setUpAll(() async {
    for (final f in Directory(
      'test/previews/covers',
    ).listSync().whereType<File>()) {
      pv.covers[f.uri.pathSegments.last.split('.').first] = f.readAsBytesSync();
    }
    ArtCache.override = (url) {
      final m = RegExp(r'artworks-([a-z]+)-').firstMatch(url);
      return MemoryImage(pv.covers[m?.group(1)] ?? pv.covers['harbor']!);
    };
  });

  group('window tint (tz_cover_bg_v5 §3)', () {
    test('matches the frames', () {
      const green = Color(0xFF41B448), red = Color(0xFFCF4831);
      const dark = Color(0xFF1B1C22);
      void near(Color got, (int, int, int) want) {
        final g = rgb(got);
        expect(
          (g.$1 - want.$1).abs(),
          lessThanOrEqualTo(1),
          reason: '$g vs $want',
        );
        expect(
          (g.$2 - want.$2).abs(),
          lessThanOrEqualTo(1),
          reason: '$g vs $want',
        );
        expect(
          (g.$3 - want.$3).abs(),
          lessThanOrEqualTo(1),
          reason: '$g vs $want',
        );
      }

      near(CoverColor.windowTint(green, night: true), (40, 69, 41));
      near(CoverColor.windowTint(red, night: false), (230, 218, 214));
      near(CoverColor.windowTint(dark, night: true), (41, 42, 48));
      near(CoverColor.windowTint(green, night: false), (204, 225, 204));
    });

    test('saturation <= 28 %, dark L* 11-35, light L* >= 80', () {
      final rnd = math.Random(5);
      for (var i = 0; i < 400; i++) {
        final c = Color.fromARGB(
          255,
          rnd.nextInt(256),
          rnd.nextInt(256),
          rnd.nextInt(256),
        );
        final d = CoverColor.windowTint(c, night: true);
        final l = CoverColor.windowTint(c, night: false);
        expect(sat(d), lessThanOrEqualTo(0.2801), reason: '$c');
        expect(sat(l), lessThanOrEqualTo(0.2801), reason: '$c');
        expect(AgColors.lstar(d), inInclusiveRange(10.5, 35.5), reason: '$c');
        expect(AgColors.lstar(l), greaterThanOrEqualTo(79.5), reason: '$c');
      }
    });

    test('dominant skips near-black and near-white pixels', () {
      const size = 64;
      final px = Uint8List(size * size * 4);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final i = (y * size + x) * 4;
          final v = x < 32 ? (y < 32 ? 0 : 255) : -1;
          px[i] = v >= 0 ? v : 200;
          px[i + 1] = v >= 0 ? v : 40;
          px[i + 2] = v >= 0 ? v : 60;
          px[i + 3] = 255;
        }
      }
      expect(rgb(CoverColor.dominant(px, size)!), (200, 40, 60));
    });

    test('wash: pure tint in the centre, base at the edge', () {
      expect(WashPainter.mixAt(0.1), 0);
      expect(WashPainter.mixAt(1.2), 1);
      expect(WashPainter.mixAt(0.675), closeTo(0.5, 1e-9));
    });
  });

  group('blur', () {
    test('64 px, radius 12, opaque, flattens detail', () {
      const size = 64;
      final px = Uint8List(size * size * 4);
      for (var i = 0; i < size * size; i++) {
        final on = (i % size) < 32;
        px[i * 4] = on ? 255 : 0;
        px[i * 4 + 3] = 255;
      }
      final out = CoverArt.blur(px, size);
      expect((CoverArt.sigma * 3).ceil(), 12, reason: 'kernel radius 12');
      expect(CoverArt.source, 64);
      int at(int x) => out[(32 * size + x) * 4];
      expect(at(31), inInclusiveRange(100, 170));
      expect(out[(32 * size + 31) * 4 + 3], 255);
      expect(at(24), greaterThan(at(31)));
      expect(at(31), greaterThan(at(38)));
    });

    test('card text keeps 4.5:1 over any cover pixel', () {
      for (final c in [AgColors.night, AgColors.light]) {
        final bg = worstUnderCard(c);
        expect(
          contrast(c.ink, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$c ink',
        );
        expect(
          contrast(c.artist, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$c artist',
        );
      }
      expect(AgColors.night.cardGlass.a, closeTo(0.55, 0.01));
      expect(AgColors.light.cardGlass.a, closeTo(0.50, 0.01));
    });
  });

  group('pulse (§2)', () {
    test('one nominal beat: 1.04 / +7 % at 80 ms, rest at 380 ms', () {
      final peak = PulseEnvelope.beatAt(80);
      expect(PulseEnvelope.beatAt(0), PulseFrame.rest);
      expect(peak.scale, closeTo(1.04, 1e-9));
      expect(peak.bright, closeTo(0.07, 1e-9));
      expect(PulseEnvelope.beatAt(40).scale, closeTo(1 + 0.04 * 0.875, 1e-9));
      expect(PulseEnvelope.beatAt(230).scale, closeTo(1.005, 1e-9));
      expect(PulseEnvelope.beatAt(380), PulseFrame.rest);
    });

    test('scale never above 1.06, brightness never above +8 %', () {
      final env = PulseEnvelope()..beat(0, 1.5);
      for (var t = 0.0; t < 400; t += 5) {
        final f = env.at(t);
        expect(f.scale, lessThanOrEqualTo(1.06 + 1e-12));
        expect(f.bright, lessThanOrEqualTo(0.08 + 1e-12));
      }
      final peak = (PulseEnvelope()..beat(0, 1.5)).at(80);
      expect(peak.scale, closeTo(1.06, 1e-9));
      expect(peak.bright, closeTo(0.08, 1e-9));
    });

    test('pause eases back to rest over 400 ms', () {
      final env = PulseEnvelope()..beat(0, 1);
      env.release(80);
      expect(env.at(80).scale, closeTo(1.04, 1e-9));
      expect(env.at(280).scale, inExclusiveRange(1.0, 1.01));
      expect(env.at(480), PulseFrame.rest);
      expect(env.isRest(500), isTrue);
    });

    test('beats from the waveform: spikes, spacing, quiet parts', () {
      final samples = WaveformCache.parse(spikyWave())!;
      const dur = 222000;
      final d = BeatDetector(samples, dur);
      final perSample = dur / samples.length;
      final hits = <double>[], strength = <double>[];
      for (var t = 2000.0; t < 12000; t += 16) {
        final i = d.step(t);
        if (i != null) {
          hits.add(t);
          strength.add(i);
        }
      }
      expect(hits.length, inInclusiveRange(18, 22));
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i] - hits[i - 1], closeTo(4 * perSample, 40));
      }
      expect(strength.every((s) => s > 1), isTrue, reason: 'strong spikes');
      var quiet = 0;
      for (var t = 170000.0; t < 180000; t += 16) {
        if (d.step(t) != null) quiet++;
      }
      expect(quiet, 0);
      expect(d.step(60000), isNull);
    });

    test('loudness-normalised master (real waveform JSON shape)', () {
      final body = loudMaster();
      final samples = WaveformCache.parse(body)!;
      expect(samples.length, 1800);
      const dur = 200000;
      final d = BeatDetector(samples, dur);
      double perMin(double from, double to) =>
          d.beats.where((b) => b.ms >= from && b.ms < to).length /
          ((to - from) / 60000);
      expect(perMin(20000, 150000), inInclusiveRange(90, 140));
      final detected = d.beats
          .where((b) => b.ms >= 20000 && b.ms < 150000)
          .where((b) => b.intensity != BeatDetector.fillIntensity);
      expect(detected.length / (130000 / 60000), greaterThan(80));
      final flat = d.beats.where((b) => b.ms >= 152000 && b.ms < 178000);
      expect(flat.length, greaterThan(30));
      expect(
        flat.where((b) => b.intensity == BeatDetector.fillIntensity).length,
        greaterThan(flat.length * 0.8),
      );
      expect(d.beats.where((b) => b.ms > 182000), isEmpty);
      for (var i = 1; i < d.beats.length; i++) {
        expect(
          d.beats[i].ms - d.beats[i - 1].ms,
          greaterThanOrEqualTo(BeatDetector.minGapMs - 1),
        );
      }
      for (final b in d.beats) {
        expect(b.intensity, inInclusiveRange(0.1, 1.2));
      }
    });

    test('waveform: json url, sndcdn only, bad data is no pulse', () async {
      expect(
        WaveformCache.jsonUri('https://wave.sndcdn.com/abc_m.png').toString(),
        'https://wave.sndcdn.com/abc_m.json',
      );
      expect(WaveformCache.jsonUri('http://wave.sndcdn.com/abc_m.png'), isNull);
      expect(WaveformCache.jsonUri('https://evil.example/abc_m.png'), isNull);
      expect(WaveformCache.jsonUri('https://evilsndcdn.com/abc_m.png'), isNull);
      expect(WaveformCache.jsonUri(null), isNull);
      expect(WaveformCache.parse('not json'), isNull);
      expect(WaveformCache.parse('{"samples": [1, 2]}'), isNull);
      expect(WaveformCache.parse(null), isNull);
      var calls = 0;
      final cache = WaveformCache((uri) async {
        calls++;
        return spikyWave();
      });
      final a = await cache.load('https://wave.sndcdn.com/x_m.png');
      final b = await cache.load('https://wave.sndcdn.com/x_m.png');
      expect(calls, 1);
      expect(identical(a, b), isTrue);
      final failing = WaveformCache((uri) async => throw Exception('offline'));
      expect(await failing.load('https://wave.sndcdn.com/y_m.png'), isNull);
    });
  });

  group('in the app', () {
    tearDown(() {
      pv.waves = null;
      pv.waveUrlOf = null;
      pv.noWaveUrl = false;
    });

    testWidgets('cover in the card, window wash, 600 ms crossfade', (
      tester,
    ) async {
      final h = await pv.boot(
        tester,
        ThemeMode.dark,
        size: const Size(1920, 1032),
      );
      expect(
        find.byType(SmokeBackground),
        findsOneWidget,
        reason: 'no track: the grey blob',
      );
      expect(spots(), findsNothing);
      await tester.runAsync(() => h.playHarbor());
      final scene = await pv.waitArt(tester);
      expect(washes(), findsOneWidget);
      expect(find.byType(SmokeBackground), findsNothing);
      expect(spots(), findsOneWidget);
      final square = tester.getRect(
        find.descendant(
          of: find.byType(CoverBackground),
          matching: find.byType(ColorFiltered),
        ),
      );
      const contentH = 1032 - Dp.topBar - Dp.contentBottom;
      expect(square.width, closeTo(contentH * 0.70, 0.5));
      expect(square.height, closeTo(square.width, 0.01));
      expect(square.center.dx, closeTo(960, 0.5));
      expect(square.center.dy, closeTo(Dp.topBar + contentH / 2, 0.5));

      final px = (await tester.runAsync(
        () => scene.art.value!.spot.toByteData(),
      ))!;
      int alpha(int x, int y) => px.getUint8((y * CoverArt.out + x) * 4 + 3);
      expect(alpha(128, 128), 255);
      expect(alpha(128, 40), 255);
      expect(alpha(4, 4), lessThan(10));
      expect(
        alpha(19, 19),
        lessThan(alpha(19, 128) - 80),
        reason: 'rounded corner',
      );
      expect(alpha(128, 15), inExclusiveRange(30, 230), reason: 'soft edge');

      final deco =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(GroupCard).first,
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(deco.color!.a, closeTo(0.55, 0.01));
      expect(
        find.descendant(
          of: find.byType(GroupCard),
          matching: find.byWidgetPredicate(
            (w) => w is RawImage && w.image?.width == CoverArt.out,
          ),
        ),
        findsNothing,
      );

      for (final r in <AppRoute>[
        const PlaylistsRoute(),
        const QueueRoute(),
        TrackRoute(h.services.player.current!),
        const LikesRoute(),
      ]) {
        h.services.nav.go(r);
        await pv.settle(tester);
        expect(spots(), findsOneWidget, reason: '$r');
      }

      Color tintOf(Element e) =>
          ((e.widget as CustomPaint).painter as WashPainter).tint;
      final oldTint = tintOf(washes().evaluate().single);
      unawaited(h.services.player.next());
      await tester.pump();
      for (
        var i = 0;
        i < 60 && scene.art.value?.url != h.services.player.current!.artworkUrl;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(spots(), findsNWidgets(2), reason: 'crossfading');
      // The wash is two ready layers, never an in-between colour per frame.
      final tints = washes().evaluate().map(tintOf).toList();
      expect(tints, hasLength(2));
      expect(tints.first, oldTint);
      expect(tints.last, isNot(oldTint));
      await tester.pump(const Duration(milliseconds: 350));
      expect(spots(), findsOneWidget);
      expect(washes(), findsOneWidget);
      expect(tintOf(washes().evaluate().single), tints.last);

      h.services.tint.set(false);
      await pv.settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(washes(), findsNothing);
      expect(find.byType(SmokeBackground), findsOneWidget);
      expect(spots(), findsNothing, reason: 'Tint from cover off: no cover');
    });

    testWidgets('pulses on beats, the list never rebuilds, freezes on pause', (
      tester,
    ) async {
      pv.waves = WaveformCache((uri) async => spikyWave());
      final h = await pv.boot(
        tester,
        ThemeMode.dark,
        size: const Size(1920, 1032),
      );
      await tester.runAsync(() => h.playHarbor(atSec: 10));
      final scene = await pv.waitArt(tester);
      expect(scene.wave.value, isNotNull);
      final rowsBefore = tester.widgetList(find.byType(TrackRow)).toList();
      h.services.window.active.value = true;
      var pos = 10000;
      var peak = 1.0, maxBright = 0.0;
      for (var i = 0; i < 60; i++) {
        pos += 16;
        if (i % 6 == 0) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 85)),
          );
          h.backend.emitPosition(Duration(milliseconds: pos));
        }
        await tester.pump(const Duration(milliseconds: 16));
        peak = math.max(peak, scene.pulse.value.scale);
        maxBright = math.max(maxBright, scene.pulse.value.bright);
      }
      expect(peak, greaterThan(1.02));
      expect(peak, lessThanOrEqualTo(1.06));
      expect(maxBright, inInclusiveRange(0.01, 0.08));
      final rowsAfter = tester.widgetList(find.byType(TrackRow)).toList();
      expect(rowsAfter.length, rowsBefore.length);
      for (var i = 0; i < rowsAfter.length; i++) {
        expect(
          identical(rowsAfter[i], rowsBefore[i]),
          isTrue,
          reason: 'the list must not rebuild on a beat',
        );
      }

      await tester.runAsync(() => h.services.player.pause());
      await tester.pump(const Duration(milliseconds: 16));
      for (var t = 0; t < 420; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(scene.pulse.value, PulseFrame.rest);
      await tester.pump(const Duration(milliseconds: 200));
      expect(scene.pulse.value, PulseFrame.rest);
      h.services.window.active.value = false;
      await tester.pump(const Duration(milliseconds: 500));
    });

    for (final (name, setup)
        in <(String, void Function(WidgetTester, pv.Harness))>[
          ('Pulse to beat off', (t, h) => h.services.pulse.set(false)),
          (
            'reduce motion',
            (t, h) {
              t.platformDispatcher.accessibilityFeaturesTestValue =
                  const FakeAccessibilityFeatures(disableAnimations: true);
              addTearDown(
                t.platformDispatcher.clearAccessibilityFeaturesTestValue,
              );
            },
          ),
          ('unfocused', (t, h) {}),
        ]) {
      testWidgets('no pulse: $name', (tester) async {
        pv.waves = WaveformCache((uri) async => spikyWave());
        final h = await pv.boot(
          tester,
          ThemeMode.dark,
          size: const Size(1920, 1032),
        );
        await tester.runAsync(() => h.playHarbor(atSec: 10));
        final scene = await pv.waitArt(tester);
        setup(tester, h);
        await tester.pump();
        if (name != 'unfocused') h.services.window.active.value = true;
        var pos = 10000;
        for (var i = 0; i < 40; i++) {
          pos += 16;
          if (i % 6 == 0) h.backend.emitPosition(Duration(milliseconds: pos));
          await tester.pump(const Duration(milliseconds: 16));
          expect(scene.pulse.value, PulseFrame.rest);
        }
        h.services.window.active.value = false;
        await tester.pump(const Duration(milliseconds: 500));
      });
    }

    testWidgets('queue saved without waveform_url: url looked up', (
      tester,
    ) async {
      pv.noWaveUrl = true;
      final asked = <int>[];
      pv.waveUrlOf = (t) async {
        asked.add(t.id);
        return 'https://wave.sndcdn.com/looked_m.json';
      };
      final fetched = <Uri>[];
      pv.waves = WaveformCache((uri) async {
        fetched.add(uri);
        return loudMaster();
      });
      final h = await pv.boot(
        tester,
        ThemeMode.dark,
        size: const Size(1920, 1032),
      );
      await tester.runAsync(() => h.playHarbor(atSec: 30));
      final scene = await pv.waitArt(tester);
      for (var i = 0; i < 20 && scene.wave.value == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(h.services.player.current!.waveformUrl, isNull);
      expect(asked, [h.services.player.current!.id]);
      expect(fetched.single.path, '/looked_m.json');
      expect(scene.wave.value, hasLength(1800));
    });

    testWidgets('queue cards use the list glass', (tester) async {
      final h = await pv.boot(
        tester,
        ThemeMode.dark,
        size: const Size(1920, 1032),
      );
      await tester.runAsync(() => h.playHarbor());
      h.services.nav.go(const QueueRoute());
      await pv.settle(tester);
      final split = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .where((p) => p.runtimeType.toString() == '_SplitCardPainter')
          .single;
      expect((split as dynamic).fill, AgColors.night.cardGlass);
      final now = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GroupCard).first,
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (now.decoration! as BoxDecoration).color,
        AgColors.night.cardGlass,
      );
    });

    for (final (name, size) in [
      ('docked', const Size(1920, 1032)),
      ('overlay', const Size(1280, 800)),
    ]) {
      testWidgets('track panel is list glass: $name', (tester) async {
        final h = await pv.boot(tester, ThemeMode.light, size: size);
        await tester.runAsync(() => h.playHarbor());
        h.services.panel.show();
        await pv.settle(tester);
        final panel = find.byType(TrackPanelView);
        final box = tester.widget<Container>(
          find.descendant(of: panel, matching: find.byType(Container)).first,
        );
        final deco = box.decoration! as BoxDecoration;
        expect(deco.color, AgColors.light.cardGlass);
        expect(deco.boxShadow, isNull);
        expect((deco.border! as Border).top.color, AgColors.light.rim);
        expect(
          find.descendant(of: panel, matching: find.byType(BackdropFilter)),
          name == 'overlay' ? findsOneWidget : findsNothing,
        );
        expect(spots(), findsOneWidget);
      });
    }

    testWidgets('missing or failing waveform: no pulse', (tester) async {
      pv.waves = WaveformCache((uri) async => throw Exception('offline'));
      final h = await pv.boot(
        tester,
        ThemeMode.dark,
        size: const Size(1920, 1032),
      );
      await tester.runAsync(() => h.playHarbor(atSec: 10));
      final scene = await pv.waitArt(tester);
      expect(scene.wave.value, isNull);
      h.services.window.active.value = true;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(scene.pulse.value, PulseFrame.rest);
      }
      h.services.window.active.value = false;
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
