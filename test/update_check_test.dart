import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scglow/core/app_version.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/core/update_check.dart';
import 'package:scglow/app/update_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'package:scglow/player/player_controller.dart';
import 'package:scglow/platform/window_service.dart';

Map<String, dynamic> _release({
  String tag = 'v1.7.0',
  String body = 'Fixes and improvements.',
  List<Map<String, dynamic>>? assets,
}) =>
    {
      'tag_name': tag,
      'body': body,
      'assets': assets ??
          [
            {
              'name': 'scglow-windows-1.7.0.zip',
              'browser_download_url': 'https://example/scglow-windows-1.7.0.zip',
              'digest': 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            }
          ],
    };

void main() {
  group('AppVersion', () {
    test('parses tags with or without v and build number', () {
      expect(AppVersion.tryParse('v1.6.4+25'), const AppVersion(1, 6, 4, 25));
      expect(AppVersion.tryParse('1.6.4'), const AppVersion(1, 6, 4));
      expect(AppVersion.tryParse('V1.7.0+1')!.label, '1.7.0+1');
      expect(AppVersion.tryParse('nope'), isNull);
      expect(AppVersion.tryParse('1.2'), isNull);
    });

    test('compares semver first, then the build number', () {
      const cur = AppVersion(1, 6, 4, 25);
      expect(AppVersion.tryParse('1.6.5')!.compareTo(cur), greaterThan(0));
      expect(AppVersion.tryParse('v1.6.4+26')!.compareTo(cur), greaterThan(0));
      expect(AppVersion.tryParse('v1.6.4+25')!.compareTo(cur), 0);
      expect(AppVersion.tryParse('1.6.4')!.compareTo(cur), lessThan(0));
      expect(AppVersion.tryParse('1.6.3+99')!.compareTo(cur), lessThan(0));
      expect(AppVersion.tryParse('2.0.0')!.compareTo(cur), greaterThan(0));
    });
  });

  group('asset selection and checksums', () {
    const current = AppVersion(1, 6, 4, 25);
    test('prefers scglow-windows-X.Y.Z.zip and the digest field', () {
      final offer = offerFromRelease(
        GithubRelease.fromJson(_release(assets: [
          {
            'name': 'scglow-1.7.0-windows-x64.zip',
            'browser_download_url': 'https://example/legacy.zip',
            'digest': 'sha256:${'b' * 64}',
          },
          {
            'name': 'scglow-windows-1.7.0.zip',
            'browser_download_url': 'https://example/preferred.zip',
            'digest': 'sha256:${'A' * 64}',
          },
        ])),
        current,
      )!;
      expect(offer.assetName, 'scglow-windows-1.7.0.zip');
      expect(offer.assetUrl, 'https://example/preferred.zip');
      expect(offer.sha256, 'a' * 64);
    });

    test('falls back to the older windows-x64 name and to a .sha256 asset', () {
      final offer = offerFromRelease(
        GithubRelease.fromJson(_release(tag: 'v1.7.0+1', assets: [
          {
            'name': 'scglow-1.7.0+1-windows-x64.zip',
            'browser_download_url': 'https://example/legacy.zip',
          },
          {
            'name': 'scglow-1.7.0+1-windows-x64.zip.sha256',
            'browser_download_url': 'https://example/legacy.zip.sha256',
          },
        ])),
        current,
      )!;
      expect(offer.assetName, 'scglow-1.7.0+1-windows-x64.zip');
      expect(offer.checksumUrl, 'https://example/legacy.zip.sha256');
      expect(offer.sha256, isEmpty);
    });

    test('refuses a newer release that has no checksum', () {
      expect(
        offerFromRelease(
          GithubRelease.fromJson(_release(assets: [
            {
              'name': 'scglow-windows-1.7.0.zip',
              'browser_download_url': 'https://example/x.zip',
            },
          ])),
          current,
        ),
        isNull,
      );
    });

    test('ignores a release that is not newer', () {
      expect(
        offerFromRelease(GithubRelease.fromJson(_release(tag: 'v1.6.4+25')), current),
        isNull,
      );
      expect(
        offerFromRelease(GithubRelease.fromJson(_release(tag: 'v1.6.3')), current),
        isNull,
      );
    });

    test('parses digest and .sha256 file contents', () {
      expect(sha256FromDigest('SHA256:${'Ab' * 32}'), 'ab' * 32);
      expect(sha256FromDigest('md5:abcd'), isNull);
      expect(sha256FromFile('${'c' * 64}  scglow-windows-1.7.0.zip\n'), 'c' * 64);
      expect(sha256FromFile('SHA256 (file.zip) = ${'D' * 64}'), 'd' * 64);
      expect(sha256FromFile('not a hash'), isNull);
    });
  });

  group('GitHub check', () {
    const current = AppVersion(1, 6, 4, 25);
    test('sends a User-Agent and reports the latest version or an update', () async {
      final agents = <String?>[];
      final client = MockClient((req) async {
        agents.add(req.headers['User-Agent']);
        expect(req.url.path, '/repos/ravenpupsik/scglow/releases/latest');
        return http.Response(jsonEncode(_release(tag: 'v1.6.4+25')), 200,
            headers: {'content-type': 'application/json'});
      });
      final latest = await checkLatestRelease(client: client, current: current);
      expect(latest.isLatest, isTrue);
      expect(agents.single, 'scglow/1.6.4+25');

      final older = MockClient((req) async => http.Response(jsonEncode(_release()), 200,
          headers: {'content-type': 'application/json'}));
      final available = await checkLatestRelease(client: older, current: current);
      expect(available.offer?.version.label, '1.7.0');
    });

    test('fetches a companion .sha256 when the digest is missing', () async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('.sha256')) {
          return http.Response('${'e' * 64}  scglow-windows-1.7.0.zip\n', 200);
        }
        return http.Response(
            jsonEncode(_release(assets: [
              {
                'name': 'scglow-windows-1.7.0.zip',
                'browser_download_url': 'https://example/scglow-windows-1.7.0.zip',
              },
              {
                'name': 'scglow-windows-1.7.0.zip.sha256',
                'browser_download_url': 'https://example/scglow-windows-1.7.0.zip.sha256',
              },
            ])),
            200,
            headers: {'content-type': 'application/json'});
      });
      final r = await checkLatestRelease(client: client, current: current);
      expect(r.offer?.sha256, 'e' * 64);
    });

    test('clear message on a network error and on a missing checksum', () async {
      final down = MockClient((req) async => throw const SocketException('offline'));
      final failed = await checkLatestRelease(client: down, current: current);
      expect(failed.error, contains("Couldn't check for updates"));

      final noSum = MockClient((req) async => http.Response(
          jsonEncode(_release(assets: [
            {
              'name': 'scglow-windows-1.7.0.zip',
              'browser_download_url': 'https://example/x.zip',
            },
          ])),
          200,
          headers: {'content-type': 'application/json'}));
      final refused = await checkLatestRelease(client: noSum, current: current);
      expect(refused.error, contains('no SHA-256'));
    });
  });

  group('download verify and extract', () {
    test('keeps a matching file and deletes a mismatch', () async {
      final bytes = Uint8List.fromList(utf8.encode('scglow-update-body'));
      final hash = sha256OfBytes(bytes);
      final dir = Directory.systemTemp.createTempSync('upd');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ok = MockClient((req) async => http.Response.bytes(bytes, 200));
      const offer = UpdateOffer(
        version: AppVersion(1, 7, 0),
        notes: '',
        assetName: 'scglow-windows-1.7.0.zip',
        assetUrl: 'https://example/scglow-windows-1.7.0.zip',
        sha256: 'will-set',
      );
      final good = UpdateOffer(
        version: offer.version,
        notes: '',
        assetName: offer.assetName,
        assetUrl: offer.assetUrl,
        sha256: hash,
      );
      final file = await downloadAndVerify(client: ok, offer: good, dir: dir);
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), bytes);

      final bad = UpdateOffer(
        version: offer.version,
        notes: '',
        assetName: 'bad.zip',
        assetUrl: offer.assetUrl,
        sha256: '0' * 64,
      );
      await expectLater(
        downloadAndVerify(client: ok, offer: bad, dir: dir),
        throwsA(isA<DownloadException>()),
      );
      expect(File('${dir.path}${Platform.pathSeparator}bad.zip').existsSync(), isFalse);
    });

    test('extracts a zip and unwraps a single root folder', () {
      final dir = Directory.systemTemp.createTempSync('upd2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final archive = Archive()
        ..addFile(ArchiveFile('Release/scglow.exe', 4, [1, 2, 3, 4]))
        ..addFile(ArchiveFile('Release/data/x.txt', 1, [9]));
      final zipFile = File('${dir.path}/app.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive)!);
      final dest = Directory('${dir.path}/stage');
      extractZip(zipFile, dest);
      expect(File('${dest.path}${Platform.pathSeparator}scglow.exe').existsSync(), isTrue);
      expect(File('${dest.path}${Platform.pathSeparator}data${Platform.pathSeparator}x.txt').existsSync(), isTrue);
    });
  });

  group('24h throttle', () {
    test('is due when never checked, or once 24 hours have passed', () {
      final now = DateTime.utc(2026, 11, 26, 12);
      expect(isCheckDue(now, null), isTrue);
      expect(isCheckDue(now, now.subtract(const Duration(hours: 23, minutes: 59))), isFalse);
      expect(isCheckDue(now, now.subtract(const Duration(hours: 24))), isTrue);
      expect(isCheckDue(now, now.add(const Duration(hours: 1))), isTrue);
    });

    test('the controller skips a silent check inside the 24h window', () async {
      SharedPreferences.setMockInitialValues({
        UpdateController.lastCheckKey: DateTime.utc(2026, 11, 26, 10).toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      var hits = 0;
      final client = MockClient((req) async {
        hits++;
        return http.Response('{}', 500);
      });
      final c = UpdateController(
        player: PlayerController(
          backend: FakeBackend(),
          resolveStream: (t) async => const ResolvedStream(url: 'u', isPreview: false),
          onAuthProblem: (_, _) {},
        ),
        window: WindowService(enabled: false),
        prefs: prefs,
        client: client,
        clock: () => DateTime.utc(2026, 11, 26, 12),
      );
      await c.checkSilent();
      expect(hits, 0);
      expect(c.due, isFalse);
      await c.check();
      expect(hits, 1);
    });
  });

  test('notes are trimmed to a sensible length', () {
    final long = List.generate(200, (i) => 'line $i').join('\n');
    final cut = truncateNotes(long, limit: 80);
    expect(cut.length, lessThan(long.length));
    expect(cut, endsWith('…'));
    expect(cut, isNot(contains('line 199')));
  });
}
