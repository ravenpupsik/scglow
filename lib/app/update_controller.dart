import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_version.dart';
import '../core/diag_log.dart';
import '../core/update_check.dart';
import '../platform/window_service.dart';
import '../player/player_controller.dart';

enum UpdatePhase { idle, checking, ready, downloading, applying, failed }

class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.player,
    required this.window,
    SharedPreferences? prefs,
    http.Client? client,
    AppVersion current = AppVersion.current,
    DateTime Function()? clock,
    Future<Directory> Function()? tempDir,
    String? installDir,
    Future<void> Function(List<String> args)? launchUpdater,
    this.onSilentOffer,
  })  : _prefs = prefs,
        _client = client ?? http.Client(),
        current = current,
        _clock = clock ?? DateTime.now,
        _tempDir = tempDir,
        _installDir = installDir,
        _launchUpdater = launchUpdater;

  static const lastCheckKey = 'update_last_check';

  final PlayerController player;
  final WindowService window;
  final SharedPreferences? _prefs;
  final http.Client _client;
  final AppVersion current;
  final DateTime Function() _clock;
  final Future<Directory> Function()? _tempDir;
  final String? _installDir;
  final Future<void> Function(List<String> args)? _launchUpdater;
  void Function(UpdateOffer offer)? onSilentOffer;

  UpdatePhase phase = UpdatePhase.idle;
  UpdateOffer? offer;
  String? message;
  int? receivedBytes;
  int? totalBytes;

  int? get percent {
    final t = totalBytes, r = receivedBytes;
    if (t == null || t <= 0 || r == null) return null;
    return ((r * 100) / t).floor().clamp(0, 100);
  }

  DateTime? get lastCheck {
    final raw = _prefs?.getString(lastCheckKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  bool get due => isCheckDue(_clock(), lastCheck);

  Future<void> checkSilent() async {
    if (!due) {
      final last = lastCheck;
      final ago = last == null ? '' : '; last ${ _clock().difference(last).inHours}h ago';
      _log('check skipped (once per 24h$ago)');
      return;
    }
    await check(silent: true);
  }

  Future<UpdateCheckResult> check({bool silent = false}) async {
    phase = UpdatePhase.checking;
    message = null;
    if (!silent) offer = null;
    notifyListeners();
    _log('checking (current ${current.label})');
    final result = await checkLatestRelease(client: _client, current: current);
    if (result.isFailed) {
      _log('check failed: ${result.error}');
      if (silent) {
        phase = UpdatePhase.idle;
        notifyListeners();
        return result;
      }
      phase = UpdatePhase.failed;
      message = result.error;
      notifyListeners();
      return result;
    }
    await _prefs?.setString(lastCheckKey, _clock().toUtc().toIso8601String());
    if (result.isLatest) {
      phase = UpdatePhase.idle;
      offer = null;
      message = 'You have the latest version';
      _log('check result: latest (${result.latestTag})');
    } else {
      offer = result.offer;
      phase = UpdatePhase.ready;
      message = 'Version ${result.offer!.version.label} available';
      _log('check result: ${result.offer!.version.label} available, '
          'asset ${result.offer!.assetName}');
      if (silent) onSilentOffer?.call(result.offer!);
    }
    notifyListeners();
    return result;
  }

  Future<void> apply() async {
    final next = offer;
    if (next == null || phase == UpdatePhase.downloading || phase == UpdatePhase.applying) {
      return;
    }
    Directory dir;
    try {
      dir = await _workDir();
    } catch (_) {
      phase = UpdatePhase.failed;
      message = "Couldn't prepare the update folder.";
      notifyListeners();
      return;
    }
    phase = UpdatePhase.downloading;
    receivedBytes = 0;
    totalBytes = null;
    message = 'Downloading…';
    notifyListeners();
    _log('download ${next.assetName}');
    File zip;
    try {
      zip = await downloadAndVerify(
        client: _client,
        offer: next,
        dir: dir,
        current: current,
        onProgress: (got, total) {
          receivedBytes = got;
          totalBytes = total;
          final p = percent;
          message = p == null ? 'Downloading…' : 'Downloading $p%';
          notifyListeners();
        },
      );
    } on DownloadException catch (e) {
      phase = UpdatePhase.failed;
      message = e.message;
      _log('download failed: ${e.message}');
      notifyListeners();
      return;
    } catch (_) {
      phase = UpdatePhase.failed;
      message = "Couldn't download the update.";
      _log('download failed');
      notifyListeners();
      return;
    }
    _log('verified SHA-256 of ${next.assetName}');
    phase = UpdatePhase.applying;
    message = 'Installing…';
    notifyListeners();
    try {
      await player.save();
      final install = _installDir ?? File(Platform.resolvedExecutable).parent.path;
      final stage = Directory('$install${Platform.pathSeparator}.scglow_update');
      extractZip(zip, stage);
      _log('apply staged in ${stage.path}');
      final script = File('${dir.path}${Platform.pathSeparator}apply.ps1');
      await script.writeAsString(updaterScript, flush: true);
      final backup = Directory('${dir.path}${Platform.pathSeparator}backup');
      final exe = '$install${Platform.pathSeparator}scglow.exe';
      final args = [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '$pid',
        stage.path,
        install,
        backup.path,
        exe,
      ];
      final launch = _launchUpdater;
      if (launch != null) {
        await launch(args);
      } else if (Platform.isWindows) {
        await Process.start('powershell.exe', args, mode: ProcessStartMode.detached);
      } else {
        throw const DownloadException('Updates can only be installed on Windows.');
      }
      _log('apply launched, quitting');
      await window.quit();
    } on DownloadException catch (e) {
      phase = UpdatePhase.failed;
      message = e.message;
      _log('apply failed: ${e.message}');
      notifyListeners();
    } catch (e) {
      phase = UpdatePhase.failed;
      message = "Couldn't install the update.";
      _log('apply failed: ${e.runtimeType}');
      notifyListeners();
    }
  }

  Future<Directory> _workDir() async {
    final base = _tempDir != null
        ? await _tempDir()
        : Directory('${Directory.systemTemp.path}${Platform.pathSeparator}scglow_update');
    await base.create(recursive: true);
    return base;
  }

  static void _log(String line) => DiagLog.write('update: $line');
}

void extractZip(File zip, Directory dest) {
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  dest.createSync(recursive: true);
  final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  for (final item in archive) {
    final name = item.name.replaceAll('\\', '/');
    if (name.isEmpty || name.contains('..')) {
      throw const DownloadException('The update archive has an unsafe path.');
    }
    final out = File('${dest.path}${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}');
    if (!item.isFile) {
      Directory(out.path).createSync(recursive: true);
    } else {
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(item.content as List<int>, flush: true);
    }
  }
  unwrapSingleRoot(dest);
  final exe = File('${dest.path}${Platform.pathSeparator}scglow.exe');
  if (!exe.existsSync()) {
    throw const DownloadException('The update archive does not contain scglow.exe.');
  }
}

void unwrapSingleRoot(Directory dest) {
  final kids = dest.listSync().where((e) => !e.path.endsWith('.DS_Store')).toList();
  if (kids.length != 1 || kids.first is! Directory) return;
  final root = kids.first as Directory;
  if (File('${root.path}${Platform.pathSeparator}scglow.exe').existsSync() &&
      !File('${dest.path}${Platform.pathSeparator}scglow.exe').existsSync()) {
    for (final item in root.listSync()) {
      final name = item.path.split(RegExp(r'[\\/]')).last;
      item.renameSync('${dest.path}${Platform.pathSeparator}$name');
    }
    root.deleteSync(recursive: true);
  }
}

const updaterScript = r'''
$ErrorActionPreference = 'Stop'
$appPid = [int]$args[0]
$stage  = $args[1]
$dest   = $args[2]
$backup = $args[3]
$exe    = $args[4]
$log    = Join-Path $env:TEMP 'scglow.log'
function Write-Log($msg) {
  $line = '{0} update: {1}' -f ([DateTime]::Now.ToString('o')), $msg
  Add-Content -Path $log -Value $line -ErrorAction SilentlyContinue
}
$deadline = (Get-Date).AddMinutes(2)
while (Get-Process -Id $appPid -ErrorAction SilentlyContinue) {
  if ((Get-Date) -gt $deadline) { Write-Log 'apply: timed out waiting for the app to exit'; break }
  Start-Sleep -Milliseconds 400
}
try {
  if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  Get-ChildItem -LiteralPath $dest -Force | Where-Object { $_.Name -ne '.scglow_update' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $backup $_.Name) -Recurse -Force
  }
  Write-Log 'apply: backup ready'
  Get-ChildItem -LiteralPath $stage -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Recurse -Force
  }
  Write-Log 'apply: files copied'
} catch {
  Write-Log ('apply failed, rolling back: ' + $_.Exception.Message)
  if (Test-Path $backup) {
    Get-ChildItem -LiteralPath $backup -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log 'apply: rolled back'
  }
  if (Test-Path $exe) { Start-Process -FilePath $exe }
  exit 1
}
if (Test-Path $exe) { Start-Process -FilePath $exe }
Write-Log 'apply: relaunched'
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
'''
;
