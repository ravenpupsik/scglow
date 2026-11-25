@Tags(['preview'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scglow/app/app_services.dart';
import 'package:scglow/app/library_controller.dart';
import 'package:scglow/app/session_controller.dart';
import 'package:scglow/app/track_details.dart';
import 'package:scglow/app/ui_state.dart';
import 'package:scglow/core/client_id_provider.dart';
import 'package:scglow/core/json_store.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/core/sc_api.dart';
import 'package:scglow/core/storage.dart';
import 'package:scglow/platform/window_service.dart';
import 'package:scglow/player/player_controller.dart';
import 'package:scglow/ui/app_root.dart';
import 'package:scglow/ui/cover_scene.dart';
import 'package:scglow/ui/player_dock.dart';
import 'package:scglow/ui/screens/login_screen.dart';
import 'package:scglow/ui/screens/queue_screen.dart';
import 'package:scglow/ui/shell.dart';
import 'package:scglow/ui/theme/tokens.dart';
import 'package:scglow/ui/top_bar.dart';
import 'package:scglow/ui/track_panel.dart';
import 'package:scglow/ui/widgets/glass.dart';
import 'package:scglow/ui/widgets/art_image.dart';
import 'package:scglow/ui/widgets/track_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/finders.dart';

final out = Platform.environment['PREVIEW_OUT'] ?? 'build/previews';

const catalogue = [
  (1, 'harbor', 'Glass Harbor', 'Mira Solen', 222, ''),
  (2, 'breakfast', 'Second Breakfast Protocol', 'The Analog Apricots', 258, ''),
  (3, 'kite', 'Kite Over Minsk', 'Yonder Lime', 185, 'preview'),
  (4, 'demo', 'Unpublished Demo 07', 'North Static', 171, 'blocked'),
  (5, 'copper', 'Copper Almanac', 'Fern & Voltage', 304, ''),
  (6, 'nightbus', 'Night Bus to Nowhere', 'Soft Radar', 207, ''),
  (7, 'moons', 'Paper Moons, Cheap Glue', 'Linen Choir', 241, ''),
  (8, 'violet', 'Violet Machinery', 'Cove Atlas', 276, ''),
  (21, 'salt', 'Salt Window', 'Low Antenna', 191, ''),
  (22, 'field', 'Blue Field Notes', 'Cove Atlas', 242, ''),
  (23, 'lights', 'Harbor Lights, Maybe', 'Mira Solen', 178, ''),
];

var bigLibrary = false;

const extraCatalogue = [
  (31, 'copper', 'Velvet Odometer', 'Tin Lantern', 195, ''),
  (32, 'field', 'Drift Ledger', 'Tin Lantern', 172, ''),
  (33, 'lights', 'Pocket Comet', 'Tin Lantern', 150, ''),
  (34, 'violet', 'Gravel Waltz', 'Tin Lantern', 173, ''),
  (35, 'salt', 'small hours', 'pale kettle', 94, ''),
  (36, 'nightbus', 'night bus', 'room tone', 138, ''),
  (37, 'moons', 'low tide', 'harbour', 221, ''),
  (38, 'breakfast', 'second floor', 'quietly', 125, ''),
  (39, 'kite', 'northbound', 'mirror lake', 167, ''),
  (40, 'copper', 'last light', 'room 204', 191, ''),
  (41, 'salt', 'quietly', 'harbour', 118, ''),
  (42, 'violet', 'Mossline', 'wave form', 142, ''),
  (43, 'field', 'Lantern Stairs', 'north line', 208, ''),
  (44, 'lights', 'Quiet Gull', 'field notes', 129, ''),
  (45, 'moons', 'Borrowed Weather', 'steel yard', 164, ''),
  (46, 'nightbus', 'room 204', 'after hours', 187, ''),
];

const bigLikes = [31, 32, 33, 34, 35, 36, 37, 38, 1, 2, 3, 5, 6, 7, 8, 39, 40,
    41, 42, 43, 44, 45, 46];

const playlistsData = [
  (101, 'Harbor Hours', 24, 'harbor'),
  (102, 'Night Buses', 12, 'nightbus'),
  (103, 'Paper Moons', 9, 'moons'),
  (104, 'Breakfast Radio', 15, 'breakfast'),
  (105, 'Kite Weather', 7, 'kite'),
  (106, 'Copper Almanacs', 18, 'copper'),
  (107, 'Field Notes', 11, 'field'),
  (108, 'Letters After Midnight', 6, 'lights'),
];

const harborComments = [
  (11, 'Nia Vale', 'The drop after this is unreal.'),
  (13, 'Rook Lin', 'Wait for the second bar.'),
  (15, 'Maribel K.', 'I always jump back here.'),
  (24, 'Cove Atlas', 'Tape hiss, and I love it.'),
  (32, 'Soft Radar', 'The room mic is so close.'),
  (47, 'Rook Lin', 'Anyone else hear the tape hiss?'),
  (49, 'Saffron Oe', 'Yes — left side.'),
  (58, 'Low Antenna', 'This verse is the whole record.'),
  (71, 'Fern Volt', 'The bass rounds off so gently.'),
  (84, 'Elk Park', 'The horn sits in the left channel.'),
  (93, 'Elk Park', 'This section reminds me of late trains.'),
  (102, 'Nia Vale', 'I play this on a loop.'),
  (110, 'Saffron Oe', 'Play this on a night drive.'),
  (112, 'Bracket Club', 'Window down, this bar.'),
  (114, 'Mira Solen', 'That was recorded at dusk.'),
  (117, 'Yonder Lime', 'The air changes here.'),
  (128, 'Saffron Oe', 'The last horn is the one.'),
  (139, 'Harbor Clock', 'I wait for this every time.'),
  (151, 'Linen Choir', 'Soft, then suddenly close.'),
  (160, 'Nia Vale', "Don't skip this ending."),
  (162, 'Rook Lin', 'The decay is perfect.'),
  (164, 'Elk Park', 'Let it ring.'),
  (176, 'Cove Atlas', "Four notes and I'm gone."),
  (188, 'Soft Radar', 'Hold this until the lights.'),
  (199, 'Maribel K.', 'Almost at the harbor.'),
  (210, 'Low Antenna', 'The last minute is the letter.'),
  (218, 'Saffron Oe', 'Quiet now.'),
];

final motifOverride = <int, String>{};
var emptyPlaylists = false;
WaveformCache? waves;
Future<String?> Function(Track)? waveUrlOf;
var noWaveUrl = false;

Map<String, dynamic> trackJson(int id) {
  final c = [...catalogue, ...extraCatalogue].firstWhere((e) => e.$1 == id);
  final motif = motifOverride[id] ?? c.$2;
  return {
    'id': c.$1,
    'title': c.$3,
    'duration': c.$6 == 'preview' ? 30000 : c.$5 * 1000,
    'full_duration': c.$5 * 1000,
    'artwork_url': 'https://i1.sndcdn.com/artworks-$motif-large.jpg',
    if (!noWaveUrl) 'waveform_url': 'https://wave.sndcdn.com/w${id}_m.png',
    'user': {'username': c.$4},
    'track_authorization': 'preview',
    if (c.$6 == 'preview') 'policy': 'SNIP',
    if (c.$6 == 'blocked') 'policy': 'BLOCK',
    'media': {
      'transcodings': [
        {
          'url': 'https://api-v2.soundcloud.com/media/$id',
          'format': {'protocol': 'hls', 'mime_type': 'audio/mpeg'},
          if (c.$6 == 'preview') 'snipped': true,
        }
      ]
    },
  };
}

http.Response handle(http.Request r) {
  http.Response json(Object o) => http.Response(jsonEncode(o), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
  final p = r.url.path;
  if (p == '/me') {
    return json({'id': 5, 'username': 'listener', 'likes_count': bigLibrary ? bigLikes.length : 7});
  }
  if (p == '/users/5/track_likes') {
    final ids = bigLibrary ? bigLikes : [1, 2, 3, 4, 5, 6, 7];
    return json({
      'collection': [
        for (var i = 0; i < ids.length; i++)
          {
            'created_at': DateTime.utc(2026, 11, 19 - i).toIso8601String(),
            'track': trackJson(ids[i]),
          }
      ],
      'next_href': null,
    });
  }
  if (p == '/users/5/playlists') {
    return json({
      'collection': [
        for (final pl in emptyPlaylists ? const <(int, String, int, String)>[] : playlistsData)
          {
            'id': pl.$1,
            'title': pl.$2,
            'track_count': pl.$3,
            'last_modified': 'x',
            'artwork_url': 'https://i1.sndcdn.com/artworks-${pl.$4}-large.jpg',
            'user': {'username': 'listener'},
          }
      ],
      'next_href': null,
    });
  }
  final single = RegExp(r'^/tracks/(\d+)$').firstMatch(p);
  if (single != null) return json(trackJson(int.parse(single.group(1)!)));
  if (p.startsWith('/media/')) return json({'url': 'https://cdn.example/x.m3u8'});
  if (p == '/users/5/playlist_likes') return json({'collection': [], 'next_href': null});
  if (p.startsWith('/playlists/')) {
    final id = int.parse(p.split('/').last);
    final pl = playlistsData.firstWhere((e) => e.$1 == id);
    return json({
      'id': id,
      'title': pl.$2,
      'track_count': 7,
      'last_modified': 'x',
      'artwork_url': 'https://i1.sndcdn.com/artworks-${pl.$4}-large.jpg',
      'tracks': [for (final t in [1, 2, 3, 4, 5, 6, 7]) trackJson(t)],
    });
  }
  if (p.endsWith('/comments')) {
    final id = int.parse(p.split('/')[2]);
    final list = id == 1 ? harborComments : const <(int, String, String)>[];
    return json({
      'collection': [
        for (var i = 0; i < list.length; i++)
          {
            'id': i + 1,
            'timestamp': list[i].$1 * 1000,
            'body': list[i].$3,
            'user': {'username': list[i].$2},
          },
        if (bigLibrary && id == 1)
          {
            'id': 99,
            'timestamp': null,
            'body': 'Need a longer cut of this.',
            'user': {'username': 'Night Owl'},
          },
      ],
      'next_href': null,
    });
  }
  if (p.endsWith('/related')) {
    return json({'collection': [trackJson(21), trackJson(22), trackJson(23)]});
  }
  return http.Response('', 404);
}

class Harness {
  late AppServices services;
  late FakeBackend backend;
  final key = GlobalKey();

  Future<void> setUp(ThemeMode mode) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient((r) async {
      if (r.url.host == 'api-v2.soundcloud.com') return handle(r);
      return http.Response('client_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"', 200);
    });
    final kv = MemoryKeyValueStore();
    await kv.write('client_id', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1');
    final tokens = TokenStore(kv);
    await tokens.save('preview');
    final store = MemoryJsonStore();
    await store.write('user', {'id': 5, 'username': 'listener'});
    final api = ScApi(
        client: client,
        clientId: ClientIdProvider(client: client, store: kv),
        readToken: tokens.read,
        minGap: Duration.zero);
    final session = SessionController(api: api, tokens: tokens, store: store);
    late final AppServices s;
    final library = LibraryController(
        api: api,
        store: store,
        onAuthProblem: (_, _) {},
        pageDelay: Duration.zero,
        onError: (e) => s.messages.show(e.message));
    backend = FakeBackend();
    final player = PlayerController(
      backend: backend,
      resolveStream: api.resolveStream,
      onAuthProblem: (_, _) {},
      unavailableOf: library.unavailableOf,
      onUnavailable: library.markUnavailable,
      onMessage: (m) => s.messages.show(m),
    );
    s = AppServices(
      session: session,
      library: library,
      player: player,
      details: TrackDetailsController(api: api, onAuthProblem: (_, _) {}),
      theme: ThemeController(prefs, mode),
      window: WindowService(enabled: false),
      prefs: prefs,
      waveforms: waves,
      waveformUrlOf: waveUrlOf,
    );
    s.wire();
    services = s;
    await session.start();
    await library.refresh();
  }

  Future<void> playHarbor(
      {int atSec = 84,
      bool shuffle = false,
      bool repeatOne = false,
      bool repeatOff = false}) async {
    await playId(1,
        atSec: atSec, shuffle: shuffle, repeatOne: repeatOne, repeatOff: repeatOff);
  }

  Future<void> playId(int id,
      {int atSec = 84,
      bool shuffle = false,
      bool repeatOne = false,
      bool repeatOff = false}) async {
    final p = services.player;
    final likes = services.library.likes;
    await p.playTracks(likes, start: likes.indexWhere((t) => t.id == id));
    if (shuffle) p.toggleShuffle();
    if (repeatOne) {
      p.cycleRepeat();
      p.cycleRepeat();
    } else if (!repeatOff) {
      p.cycleRepeat();
    }
    backend.emitDuration(Duration(milliseconds: p.current!.durationMs));
    backend.emitPosition(Duration(seconds: atSec));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    backend.emitPosition(Duration(seconds: atSec));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final Map<String, Uint8List> covers = {};

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Doto', ['Doto-900-ROND100.ttf']);
  await family('Inter', ['Inter-Variable.ttf']);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shoot(WidgetTester tester, Harness h, String name,
    {String prefix = 'glass_'}) async {
  debugDisableShadows = false;
  h.key.currentContext!.findRenderObject()!.markNeedsPaint();
  await settle(tester);
  final boundary =
      h.key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$prefix$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Future<void> shootRect(
    WidgetTester tester, Harness h, String name, Rect logical,
    {String prefix = 'glass_'}) async {
  debugDisableShadows = false;
  h.key.currentContext!.findRenderObject()!.markNeedsPaint();
  await settle(tester);
  final boundary =
      h.key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final src = Rect.fromLTWH(
        logical.left * 2, logical.top * 2, logical.width * 2, logical.height * 2);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
        image, src, Offset.zero & src.size, Paint());
    final cropped = await recorder.endRecording().toImage(
        src.width.round(), src.height.round());
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$prefix$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Future<void> shootStack(WidgetTester tester, Harness h, String path,
    List<Rect> crops, List<Future<void> Function()> setups, Color bg) async {
  final images = <ui.Image>[];
  for (var i = 0; i < crops.length; i++) {
    await setups[i]();
    debugDisableShadows = false;
    h.key.currentContext!.findRenderObject()!.markNeedsPaint();
    await settle(tester);
    final boundary =
        h.key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final r = crops[i];
      final src = Rect.fromLTWH(r.left * 2, r.top * 2, r.width * 2, r.height * 2);
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(image, src, Offset.zero & src.size, Paint());
      images.add(await rec.endRecording().toImage(src.width.round(), src.height.round()));
    });
    debugDisableShadows = true;
  }
  await tester.runAsync(() async {
    const gap = 24;
    final w = images.map((i) => i.width).reduce((a, b) => a > b ? a : b);
    final hgt = images.fold<int>(0, (a, i) => a + i.height) + gap * (images.length - 1);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)
      ..drawRect(Rect.fromLTWH(0, 0, w.toDouble(), hgt.toDouble()), Paint()..color = bg);
    var y = 0.0;
    for (final im in images) {
      canvas.drawImage(im, Offset(0, y), Paint());
      y += im.height + gap;
    }
    final out = await rec.endRecording().toImage(w, hgt);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<Harness> boot(WidgetTester tester, ThemeMode mode,
    {Size size = const Size(1280, 800), Widget? home, int? changedStatus}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final h = Harness();
  await tester.runAsync(() => h.setUp(mode));
  h.services.window.active.value = false;
  h.services.session.changedStatus = changedStatus;
  await tester.pumpWidget(RepaintBoundary(
    key: h.key,
    child: ScglowApp(services: h.services, home: home),
  ));
  await settle(tester);
  return h;
}

void main() {
  setUpAll(() async {
    Directory(out).createSync(recursive: true);
    for (final f in Directory('test/previews/covers').listSync().whereType<File>()) {
      covers[f.uri.pathSegments.last.split('.').first] = f.readAsBytesSync();
    }
    ArtCache.override = (url) {
      final m = RegExp(r'artworks-([a-z]+)-').firstMatch(url);
      return MemoryImage(covers[m?.group(1)] ?? covers['harbor']!);
    };
    await loadFonts();
  });

  tearDown(() => QueueScreen.debugDrag = null);

  for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'night')]) {
    testWidgets('likes $suffix', (tester) async {
      final h = await boot(tester, mode);
      await tester.runAsync(() => h.playHarbor());
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.text('Second Breakfast Protocol')));
      await shoot(tester, h, 'likes_$suffix');
      await gesture.moveTo(tester.getCenter(find.text('Unpublished Demo 07')));
      await shoot(tester, h, 'likes_hover_unavailable_$suffix');
      expect(find.byType(TipBox), findsOneWidget);
      final seek = tester.getRect(find.byType(SeekLine));
      await gesture.moveTo(Offset(seek.left + seek.width * 0.55, seek.center.dy));
      final player = tester.getRect(find.byType(FloatingPlayer));
      await shootRect(tester, h, 'player_seek_$suffix', player.inflate(24));
      await gesture.removePointer();
      h.services.nav.query.value = 'harbor';
      await shoot(tester, h, 'search_$suffix');
      h.services.nav.query.value = 'zzzz';
      await shoot(tester, h, 'search_empty_$suffix');
    });

    testWidgets('likes v131 $suffix', (tester) async {
      final sizes = mode == ThemeMode.dark
          ? const [Size(1024, 600), Size(1600, 900)]
          : const [Size(1024, 600)];
      for (final size in sizes) {
        final h = await boot(tester, mode, size: size);
        await tester.runAsync(() => h.playHarbor(atSec: 40));
        await shoot(tester, h,
            'likes_${suffix}_${size.width.round()}x${size.height.round()}',
            prefix: 'v131_');
      }
    });

    testWidgets('menus and dialog $suffix', (tester) async {
      final h = await boot(tester, mode);
      await tester.runAsync(() => h.playHarbor());
      await settle(tester);
      await tester.tap(find.text('Date liked'));
      await settle(tester);
      expect(find.text('Duration'), findsOneWidget);
      await shoot(tester, h, 'sort_menu_$suffix');
      await tester.tapAt(const Offset(100, 700));
      await settle(tester);
      await tester.tap(byLabel('Account'));
      await settle(tester);
      expect(find.text('Tint from cover'), findsOneWidget);
      await shoot(tester, h, 'avatar_menu_$suffix');
      await tester.tap(find.text('Log out…'));
      await settle(tester);
      expect(find.text('Log out?'), findsOneWidget);
      await shoot(tester, h, 'logout_$suffix');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });

    testWidgets('track $suffix', (tester) async {
      final h = await boot(tester, mode);
      await tester.runAsync(() => h.playHarbor());
      h.services.nav.go(TrackRoute(h.services.library.likes.first));
      await settle(tester);
      final ctrl = tester
          .widget<Scrollable>(find
              .ancestor(of: find.text('Nia Vale').first, matching: find.byType(Scrollable))
              .first)
          .controller!;
      ctrl.jumpTo(5 * 52);
      await shoot(tester, h, 'track_$suffix');
      h.services.nav.go(TrackRoute(h.services.library.likes[4]));
      await shoot(tester, h, 'track_other_$suffix');
    });

    testWidgets('track 960 $suffix', (tester) async {
      final h = await boot(tester, mode, size: const Size(960, 600));
      await tester.runAsync(() => h.playHarbor());
      h.services.nav.go(TrackRoute(h.services.library.likes.first));
      await shoot(tester, h, 'track_960_$suffix');
    });

    testWidgets('playlists $suffix', (tester) async {
      final h = await boot(tester, mode);
      await tester.runAsync(() => h.playHarbor());
      h.services.nav.go(const PlaylistsRoute());
      await shoot(tester, h, 'playlists_$suffix');
      h.services.nav.go(const PlaylistRoute(101));
      await shoot(tester, h, 'playlist_$suffix');
    });

    testWidgets('queue $suffix', (tester) async {
      final h = await boot(tester, mode);
      await tester.runAsync(() => h.playHarbor(shuffle: true, repeatOne: true));
      h.services.nav.go(const QueueRoute());
      await shoot(tester, h, 'queue_$suffix');
      QueueScreen.debugDrag = (3, 1, 47.0);
      h.services.nav.go(const LikesRoute());
      await tester.pump();
      h.services.nav.go(const QueueRoute());
      await shoot(tester, h, 'queue_drag_$suffix');
      QueueScreen.debugDrag = null;
      h.services.nav.go(const LikesRoute());
      await tester.pump();
      h.services.nav.go(const QueueRoute());
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await shoot(tester, h, 'queue_cleared_$suffix');
      h.services.messages.dismiss();
    });

    for (final kind in LoginKind.values) {
      testWidgets('login ${kind.name} $suffix', (tester) async {
        final h = await boot(tester, mode,
            home: LoginScreen(kind: kind), changedStatus: 403);
        await shoot(tester, h, 'login_${kind.name}_$suffix');
      });
    }

    testWidgets('empty states $suffix', (tester) async {
      final h = await boot(tester, mode);
      await tester.runAsync(() async {
        h.services.library.reset();
      });
      await shoot(tester, h, 'likes_loading_$suffix');
      await tester.runAsync(() async => h.services.library.markOffline());
      await shoot(tester, h, 'likes_offline_$suffix');
      h.services.nav.go(const QueueRoute());
      await shoot(tester, h, 'queue_empty_$suffix');
    });
  }

  group('v140 track panel', () {
    setUp(() => bigLibrary = true);
    tearDown(() => bigLibrary = false);

    for (final (mode, suffix) in [(ThemeMode.dark, 'dark'), (ThemeMode.light, 'light')]) {
      testWidgets('wide open $suffix', (tester) async {
        final h = await boot(tester, mode, size: const Size(1920, 1080));
        await tester.runAsync(() => h.playHarbor(atSec: 40, shuffle: true, repeatOff: true));
        h.services.panel.show();
        await settle(tester);
        expect(find.byType(TrackPanelView), findsOneWidget);
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(tester.getCenter(find.byWidgetPredicate(
            (w) => w is PanelTrackRow && w.index == 2)));
        await shoot(tester, h, 'wide_open_$suffix', prefix: 'v140_');
        if (mode == ThemeMode.dark) {
          await gesture.moveTo(Offset.zero);
          h.services.panel.select(PanelTab.comments);
          await shoot(tester, h, 'wide_open_comments_dark', prefix: 'v140_');
          h.services.panel.select(PanelTab.related);
          await shoot(tester, h, 'wide_open_related_dark', prefix: 'v140_');
          h.services.panel.close();
          await shoot(tester, h, 'wide_closed_dark', prefix: 'v140_');
        }
        await gesture.removePointer();
      });
    }

    testWidgets('narrow overlay dark', (tester) async {
      final h = await boot(tester, ThemeMode.dark, size: const Size(1280, 800));
      await tester.runAsync(() => h.playHarbor(atSec: 40, shuffle: true, repeatOff: true));
      h.services.panel.show();
      await shoot(tester, h, 'narrow_overlay_dark', prefix: 'v140_');
    });

    for (final (mode, suffix, bg) in [
      (ThemeMode.dark, 'dark', const Color(0xFF08090B)),
      (ThemeMode.light, 'light', const Color(0xFFE4E4EA)),
    ]) {
      testWidgets('capsule states $suffix', (tester) async {
        final h = await boot(tester, mode, size: const Size(1920, 1080));
        await tester.runAsync(() => h.playHarbor(atSec: 40, repeatOff: true));
        await settle(tester);
        final cap = tester.getRect(find.byType(FloatingPlayer));
        final crop = Rect.fromLTRB(cap.left - 24, cap.top - 44, cap.right + 24, cap.bottom + 12);
        final p = h.services.player;
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        Future<void> hover(Offset at) async {
          await gesture.moveTo(at);
          await tester.pump();
        }

        final seek = tester.getRect(find.byType(SeekLine));
        await shootStack(tester, h, '$out/v140_capsule_states_$suffix.png', [
          crop, crop, crop, crop,
        ], [
          () async {},
          () async {
            p.toggleShuffle();
            p.cycleRepeat();
            await settle(tester);
            await hover(tester.getCenter(find.byType(ModeToggle).first));
            await tester.pump(const Duration(milliseconds: 600));
          },
          () async {
            await hover(Offset.zero);
            p.cycleRepeat();
          },
          () async {
            await hover(Offset(seek.left + seek.width * 84 / 222, seek.center.dy));
          },
        ], bg);
        await gesture.removePointer();
      });
    }
  });

  for (final (colors, suffix) in [(AgColors.night, 'night'), (AgColors.light, 'light')]) {
    testWidgets('blob phases $suffix', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() => SmokeBackground.debugPhase = null);
      final key = GlobalKey();
      final active = ValueNotifier(false);
      for (final (phase, tag) in [(0.0, '000'), (0.32, '032'), (0.70, '070')]) {
        SmokeBackground.debugPhase = phase;
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(colors),
            home: SmokeBackground(key: ValueKey(phase), active: active),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/glass_blob_${suffix}_$tag.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    });
  }

  group('v154 glass menus', () {
    setUp(() => bigLibrary = true);
    tearDown(() {
      bigLibrary = false;
      motifOverride.clear();
    });
    for (final (theme, mode, motif) in [
      ('dark', ThemeMode.dark, 'sunset'),
      ('light', ThemeMode.light, 'lagoon'),
    ]) {
      testWidgets('menus $theme', (tester) async {
        motifOverride[37] = motif;
        final h = await boot(tester, mode, size: const Size(1920, 1032));
        await tester.runAsync(() => h.playId(37, atSec: 25));
        await waitArt(tester);
        final glass = mode == ThemeMode.dark ? AgColors.night : AgColors.light;
        void expectGlass(Finder of) {
          final f = find.descendant(of: of, matching: find.byType(FrostedGlass));
          expect(f, findsOneWidget);
          final box = tester.widget<Container>(
              find.descendant(of: f, matching: find.byType(Container)).first);
          final deco = box.decoration! as BoxDecoration;
          expect(deco.color, glass.cardGlass);
          expect(deco.boxShadow, isNull);
          expect(find.descendant(of: f, matching: find.byType(BackdropFilter)), findsOneWidget);
        }

        await tester.tap(byLabel('Account'));
        await settle(tester);
        expectGlass(find.byType(AvatarMenu));
        await shoot(tester, h, 'avatar_menu_$theme', prefix: 'v154_');
        await tester.tap(find.text('Log out…'));
        await settle(tester);
        expectGlass(find.byType(LogoutDialog));
        await shoot(tester, h, 'logout_$theme', prefix: 'v154_');
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        await tester.tap(find.text('Date liked'));
        await settle(tester);
        expectGlass(find.byType(Overlay).last);
        await shoot(tester, h, 'sort_menu_$theme', prefix: 'v154_');
        await tester.tapAt(const Offset(100, 900));
        await settle(tester);
      });
    }
  });

  group('v153 glass panel', () {
    setUp(() => bigLibrary = true);
    tearDown(() {
      bigLibrary = false;
      motifOverride.clear();
    });
    for (final (name, mode, motif, size) in [
      ('panel_dark', ThemeMode.dark, 'sunset', const Size(1920, 1080)),
      ('panel_light', ThemeMode.light, 'lagoon', const Size(1920, 1080)),
      ('panel_overlay_dark', ThemeMode.dark, 'citrus', const Size(1280, 800)),
    ]) {
      testWidgets(name, (tester) async {
        motifOverride[37] = motif;
        final h = await boot(tester, mode, size: size);
        await tester.runAsync(() => h.playId(37, atSec: 25));
        h.services.panel.show();
        await settle(tester);
        await waitArt(tester);
        await shoot(tester, h, name, prefix: 'v153_');
      });
    }
  });

  group('v151 cover square', () {
    setUp(() => bigLibrary = true);
    tearDown(() {
      bigLibrary = false;
      motifOverride.clear();
    });
    const size = Size(1920, 1032);

    for (final (name, mode, motif, route) in <(String, ThemeMode, String, AppRoute? Function(Harness))>[
      ('likes_dark', ThemeMode.dark, 'sunset', (_) => null),
      ('likes_light', ThemeMode.light, 'lagoon', (_) => null),
      ('playlists_dark', ThemeMode.dark, 'citrus', (_) => const PlaylistsRoute()),
      ('queue_light', ThemeMode.light, 'sunset', (_) => const QueueRoute()),
      ('track_dark', ThemeMode.dark, 'lagoon', (h) => TrackRoute(h.services.player.current!)),
    ]) {
      testWidgets(name, (tester) async {
        motifOverride[37] = motif;
        final h = await boot(tester, mode, size: size);
        await tester.runAsync(() => h.playId(37, atSec: 25));
        final r = route(h);
        if (r != null) h.services.nav.go(r);
        await settle(tester);
        await waitArt(tester);
        await shoot(tester, h, name, prefix: 'v151_');
      });
    }
  });
}

Future<CoverScene> waitArt(WidgetTester tester) async {
  final scene =
      tester.widget<CoverSceneScope>(find.byType(CoverSceneScope)).scene;
  for (var i = 0; i < 60; i++) {
    final want = scene.player.current?.artworkUrl;
    if (want != null && scene.art.value?.url == want) break;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  return scene;
}
