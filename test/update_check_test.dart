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
import 'package:scglow/core/diag_log.dart';
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
          resolveStream: (t, {bool preferProgressive = false}) async => const ResolvedStream(url: 'u', isPreview: false),
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


  test('updater command quotes paths with spaces', () {
    final cmd = windowsUpdaterCommand(
      r'C:\Users\me\AppData\Local\Temp\scglow update\apply.ps1',
      [
        '1234',
        r'C:\Users\me\OneDrive\Desktop\Release\.scglow_update',
        r'C:\Users\me\OneDrive\Desktop\Release',
        r'C:\Temp\backup',
        r'C:\Users\me\OneDrive\Desktop\Release\scglow.exe',
      ],
    );
    expect(cmd, isNot(contains('Win32_Process')));
    expect(cmd, startsWith('powershell.exe '));
    expect(cmd, contains('-ExecutionPolicy Bypass'));
    expect(cmd, contains('-File "C:\\Users\\me\\AppData\\Local\\Temp\\scglow update\\apply.ps1"'));
    expect(cmd, contains('"C:\\Users\\me\\OneDrive\\Desktop\\Release"'));
  });

  test('the updater is started through WMI so it outlives TerminateProcess', () async {
    late String exe;
    late List<String> args;
    await startWindowsUpdater(
      scriptPath: r'C:\Temp\apply.ps1',
      scriptArgs: ['9', r'C:\Stage', r'C:\Dest', r'C:\Backup', r'C:\Dest\scglow.exe'],
      run: (e, a) async {
        exe = e;
        args = a;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(exe, 'powershell.exe');
    expect(args, contains('-Command'));
    final command = args.last;
    expect(command, contains('Win32_Process'));
    expect(command, contains('Create'));
    expect(command, contains('apply.ps1'));
  });

  test('leftover staging is logged and removed', () {
    final dir = Directory.systemTemp.createTempSync('upd3');
    addTearDown(() => dir.deleteSync(recursive: true));
    final stage = Directory('${dir.path}${Platform.pathSeparator}.scglow_update')
      ..createSync();
    File('${stage.path}${Platform.pathSeparator}x').writeAsStringSync('y');
    final logDir = Directory.systemTemp.createTempSync('upd3log');
    addTearDown(() => logDir.deleteSync(recursive: true));
    DiagLog.pathOverride = '${logDir.path}/scglow.log';
    final c = UpdateController(
      player: PlayerController(
        backend: FakeBackend(),
        resolveStream: (t, {bool preferProgressive = false}) async =>
            const ResolvedStream(url: 'u', isPreview: false),
        onAuthProblem: (_, _) {},
      ),
      window: WindowService(enabled: false),
      installDir: dir.path,
    );
    c.recoverFailedApply();
    expect(stage.existsSync(), isFalse);
    expect(File(DiagLog.path).readAsStringSync(), contains('previous apply did not run'));
    DiagLog.pathOverride = null;
  });


  test('updater script merge-copies folders and verifies exe and app.so', () {
    expect(updaterScript, contains('function Copy-Merge'));
    expect(updaterScript, contains(r"data\app.so"));
    expect(updaterScript, contains('Get-FileHash'));
    expect(updaterScript, contains("apply: verify failed"));
    expect(
      updaterScript,
      isNot(contains(
        r"Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Recurse -Force",
      )),
    );
    expect(
      updaterScript,
      isNot(contains(
        r"Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $backup $_.Name) -Recurse -Force",
      )),
    );
    expect(updaterScript, contains(r'Copy-Merge $_.FullName (Join-Path $dest $_.Name)'));
    expect(updaterScript, contains(r'Copy-Merge $_.FullName (Join-Path $backup $_.Name)'));
  });

  test('a nested data folder left by a bad apply is logged and removed', () {
    final dir = Directory.systemTemp.createTempSync('upd4');
    addTearDown(() => dir.deleteSync(recursive: true));
    final nested = Directory(
        '${dir.path}${Platform.pathSeparator}data${Platform.pathSeparator}data')
      ..createSync(recursive: true);
    File('${nested.path}${Platform.pathSeparator}app.so').writeAsStringSync('nested');
    final realSo = File(
        '${dir.path}${Platform.pathSeparator}data${Platform.pathSeparator}app.so')
      ..writeAsStringSync('real');
    final logDir = Directory.systemTemp.createTempSync('upd4log');
    addTearDown(() => logDir.deleteSync(recursive: true));
    DiagLog.pathOverride = '${logDir.path}/scglow.log';
    final c = UpdateController(
      player: PlayerController(
        backend: FakeBackend(),
        resolveStream: (t, {bool preferProgressive = false}) async =>
            const ResolvedStream(url: 'u', isPreview: false),
        onAuthProblem: (_, _) {},
      ),
      window: WindowService(enabled: false),
      installDir: dir.path,
    );
    c.recoverFailedApply();
    expect(nested.existsSync(), isFalse);
    expect(realSo.existsSync(), isTrue);
    expect(realSo.readAsStringSync(), 'real');
    expect(File(DiagLog.path).readAsStringSync(),
        contains('removed nested data folder'));
    DiagLog.pathOverride = null;
  });


  group('installer', () {
    const setupSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    Map<String, dynamic> both(String tag, String label) => _release(tag: tag, assets: [
          {
            'name': 'scglow-windows-$label.zip',
            'browser_download_url': 'https://example/scglow-windows-$label.zip',
            'digest': 'sha256:${'a' * 64}',
          },
          {
            'name': 'scglow-setup-$label.exe',
            'browser_download_url': 'https://example/scglow-setup-$label.exe',
            'digest': 'sha256:$setupSha',
          },
        ]);

    test('the setup is preferred over the zip; a zip-only release still works', () {
      const current = AppVersion(1, 6, 5, 31);
      final offer = offerFromRelease(
          GithubRelease.fromJson(both('v1.6.5+32', '1.6.5+32')), current)!;
      expect(offer.assetName, 'scglow-setup-1.6.5+32.exe');
      expect(offer.isInstaller, isTrue);
      expect(offer.sha256, setupSha);
      final zipOnly = offerFromRelease(GithubRelease.fromJson(_release()), current)!;
      expect(zipOnly.assetName, 'scglow-windows-1.7.0.zip');
      expect(zipOnly.isInstaller, isFalse);
    });

    test('the same version is offered only for a setup when asked', () async {
      const current = AppVersion(1, 6, 5, 31);
      final same = MockClient((req) async =>
          http.Response(jsonEncode(both('v1.6.5+31', '1.6.5+31')), 200));
      expect((await checkLatestRelease(client: same, current: current)).isLatest, isTrue);
      final r = await checkLatestRelease(
          client: same, current: current, allowSameVersion: true, installerOnly: true);
      expect(r.offer?.assetName, 'scglow-setup-1.6.5+31.exe');
      final zipOnly = MockClient((req) async => http.Response(
          jsonEncode(_release(tag: 'v1.6.5+31', assets: [
            {
              'name': 'scglow-windows-1.6.5+31.zip',
              'browser_download_url': 'https://example/z.zip',
              'digest': 'sha256:${'a' * 64}',
            }
          ])),
          200));
      final none = await checkLatestRelease(
          client: zipOnly, current: current, allowSameVersion: true, installerOnly: true);
      expect(none.isLatest, isTrue);
    });

    test('setup runs silently, waits for the app and relaunches it', () {
      final args = windowsSetupArgs(
          waitPid: 4321, logPath: r'C:\Users\Some One\AppData\Local\Temp\scglow_update\setup.log');
      expect(args, containsAll(['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/WAITPID=4321', '/RELAUNCH=1']));
      final cmd = windowsCommandLine(r'C:\Users\Some One\Temp\scglow-setup-1.6.5+31.exe', args);
      expect(cmd, startsWith(r'"C:\Users\Some One\Temp\scglow-setup-1.6.5+31.exe" /VERYSILENT'));
      expect(cmd, contains(r'/LOG="C:\Users\Some One\AppData\Local\Temp\scglow_update\setup.log"'));
      expect(cmd, contains(' /WAITPID=4321 '));
    });

    test('processes are started hidden through WMI', () async {
      late List<String> args;
      await startHiddenWindowsProcess('"C:\\x\\setup.exe" /VERYSILENT', run: (e, a) async {
        args = a;
        return ProcessResult(0, 0, 'started 77', '');
      });
      final command = args.last;
      expect(command, contains('Win32_ProcessStartup'));
      expect(command, contains('ShowWindow = [uint16]0'));
      expect(command, contains('ProcessStartupInformation'));
      expect(command, contains('Win32_Process -MethodName Create'));
      // A detached PowerShell opened its own console (shown by Windows
      // Terminal) and never answered; it must not wait on stdin either.
      expect(args, containsAllInOrder(['-InputFormat', 'None']));
      final src = File('lib/app/update_controller.dart').readAsStringSync();
      expect(src, isNot(contains('detachedWithStdio')));
      await expectLater(
        startHiddenWindowsProcess('x', run: (e, a) async => ProcessResult(0, 1, '', 'denied')),
        throwsA(isA<DownloadException>()),
      );
    });

    test('only a portable non-development copy moves to the installer, once per version', () {
      const v = AppVersion(1, 6, 5, 31);
      expect(installerMigrationBlocker(
          installDir: r'C:\Users\me\Downloads\scglow-windows-1.6.4+28',
          installed: false, attempted: null, current: v), isNull);
      expect(installerMigrationBlocker(
          installDir: r'C:\Users\me\AppData\Local\Programs\scglow',
          installed: true, attempted: null, current: v), 'installed copy');
      expect(installerMigrationBlocker(
          installDir: r'D:\androidproject\scdesk\build\windows\x64\runner\Release',
          installed: false, attempted: null, current: v), 'development build');
      expect(installerMigrationBlocker(
          installDir: r'C:\portable', installed: false, attempted: '1.6.5+31', current: v),
          contains('already tried'));
      expect(installerMigrationBlocker(
          installDir: r'C:\portable', installed: false, attempted: '1.6.5+30', current: v), isNull);
    });

    test('a portable copy downloads, verifies and starts the setup, then quits', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('upd5');
      addTearDown(() => dir.deleteSync(recursive: true));
      final install = Directory('${dir.path}${Platform.pathSeparator}portable')..createSync();
      final work = Directory('${dir.path}${Platform.pathSeparator}work');
      final body = utf8.encode('fake setup');
      final sha = sha256OfBytes(body);
      final release = _release(tag: 'v1.6.5+31', assets: [
        {
          'name': 'scglow-setup-1.6.5+31.exe',
          'browser_download_url': 'https://example/scglow-setup-1.6.5+31.exe',
          'digest': 'sha256:$sha',
        }
      ]);
      final client = MockClient((req) async => req.url.path.endsWith('.exe')
          ? http.Response.bytes(body, 200)
          : http.Response(jsonEncode(release), 200));
      String? setupPath;
      List<String>? setupArgs;
      var quit = false;
      final window = WindowService(enabled: false)..beforeQuit = () async => quit = true;
      final c = UpdateController(
        player: PlayerController(
          backend: FakeBackend(),
          resolveStream: (t, {bool preferProgressive = false}) async =>
              const ResolvedStream(url: 'u', isPreview: false),
          onAuthProblem: (_, _) {},
        ),
        window: window,
        prefs: prefs,
        client: client,
        current: const AppVersion(1, 6, 5, 31),
        installDir: install.path,
        tempDir: () async => work,
        windows: true,
        launchSetup: (path, args) async {
          setupPath = path;
          setupArgs = args;
        },
      );
      expect(c.isInstalledCopy, isFalse);
      expect(await c.migrateToInstaller(), isTrue);
      expect(setupPath, endsWith('scglow-setup-1.6.5+31.exe'));
      expect(File(setupPath!).readAsBytesSync(), body);
      expect(setupArgs, contains('/WAITPID=$pid'));
      expect(quit, isTrue);
      expect(prefs.getString(UpdateController.migrationKey), '1.6.5+31');
      // Second start of the same version does not try again.
      quit = false;
      expect(await c.migrateToInstaller(), isFalse);
      expect(quit, isFalse);
      // An installed copy never migrates.
      File('${install.path}${Platform.pathSeparator}$installerMarker').writeAsStringSync('1.6.5+31');
      expect(c.isInstalledCopy, isTrue);
      expect(c.offer, isNull, reason: 'the reinstall of the same version is never advertised');
    });

    test('a failed move to the installer leaves no same-version offer behind', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('upd6');
      addTearDown(() => dir.deleteSync(recursive: true));
      final install = Directory('${dir.path}${Platform.pathSeparator}portable')..createSync();
      final work = Directory('${dir.path}${Platform.pathSeparator}work');
      final body = utf8.encode('fake setup');
      final release = _release(tag: 'v1.6.5+32', assets: [
        {
          'name': 'scglow-setup-1.6.5+32.exe',
          'browser_download_url': 'https://example/scglow-setup-1.6.5+32.exe',
          'digest': 'sha256:${sha256OfBytes(body)}',
        }
      ]);
      final client = MockClient((req) async => req.url.path.endsWith('.exe')
          ? http.Response.bytes(body, 200)
          : http.Response(jsonEncode(release), 200));
      var quit = false;
      final c = UpdateController(
        player: PlayerController(
          backend: FakeBackend(),
          resolveStream: (t, {bool preferProgressive = false}) async =>
              const ResolvedStream(url: 'u', isPreview: false),
          onAuthProblem: (_, _) {},
        ),
        window: WindowService(enabled: false)..beforeQuit = () async => quit = true,
        prefs: prefs,
        client: client,
        current: const AppVersion(1, 6, 5, 32),
        installDir: install.path,
        tempDir: () async => work,
        windows: true,
        launchSetup: (path, args) async =>
            throw const DownloadException("Couldn't start the updater: no response."),
      );
      expect(await c.migrateToInstaller(), isFalse);
      expect(quit, isFalse);
      expect(c.offer, isNull);
      expect(c.phase, UpdatePhase.idle);
      expect(c.message, isNull);
      expect(prefs.getString(UpdateController.migrationKey), isNull);
      // A strictly newer release is still offered by a normal check.
      final newer = _release(tag: 'v1.6.6+33', assets: [
        {
          'name': 'scglow-setup-1.6.6+33.exe',
          'browser_download_url': 'https://example/scglow-setup-1.6.6+33.exe',
          'digest': 'sha256:${'a' * 64}',
        }
      ]);
      final c2 = UpdateController(
        player: PlayerController(
          backend: FakeBackend(),
          resolveStream: (t, {bool preferProgressive = false}) async =>
              const ResolvedStream(url: 'u', isPreview: false),
          onAuthProblem: (_, _) {},
        ),
        window: WindowService(enabled: false),
        prefs: prefs,
        client: MockClient((req) async => http.Response(jsonEncode(newer), 200)),
        current: const AppVersion(1, 6, 5, 32),
        installDir: install.path,
        windows: true,
      );
      await c2.check();
      expect(c2.offer?.version.label, '1.6.6+33');
    });
  });

  test('installer script keeps AppId, per-user install and data prompt', () {
    final iss = File('installer/installer.iss').readAsStringSync();
    expect(iss, contains('AppId={{C674E000-9041-45CB-B4FE-0AADB09D6D33}'));
    expect(iss, contains('PrivilegesRequired=lowest'));
    expect(iss, contains(r'DefaultDirName={localappdata}\Programs\scglow'));
    expect(iss, contains('OutputBaseFilename=scglow-setup-{#AppVersion}'));
    expect(iss, contains('MB_DEFBUTTON2'));
    expect(iss, contains('scglow.installed'));
    expect(iss, contains('{param:WAITPID|0}'));
    expect(iss, contains('{param:RELAUNCH|0}'));
    expect(iss, contains('procedure CloseStuckLaunchers'));
    expect(iss, contains('if WizardSilent then CloseStuckLaunchers;'));
    final identity = File('windows/runner/app_identity.h').readAsStringSync();
    final aumid = RegExp(r'#define AppUserModelId "([^"]+)"').firstMatch(iss)!.group(1)!;
    expect(identity, contains('L"$aumid"'));
  });
}
