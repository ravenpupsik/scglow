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
    Future<void> Function(String setup, List<String> args)? launchSetup,
    bool? windows,
    this.onSilentOffer,
  })  : _prefs = prefs,
        _launchSetup = launchSetup,
        _windows = windows ?? Platform.isWindows,
        _client = client ?? http.Client(),
        current = current,
        _clock = clock ?? DateTime.now,
        _tempDir = tempDir,
        _installDir = installDir,
        _launchUpdater = launchUpdater;

  static const lastCheckKey = 'update_last_check';
  static const migrationKey = 'installer_migration_attempt';

  final PlayerController player;
  final WindowService window;
  final SharedPreferences? _prefs;
  final http.Client _client;
  final AppVersion current;
  final DateTime Function() _clock;
  final Future<Directory> Function()? _tempDir;
  final String? _installDir;
  final Future<void> Function(List<String> args)? _launchUpdater;
  final Future<void> Function(String setup, List<String> args)? _launchSetup;
  final bool _windows;
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

  String? get installDir => _installDir ??
      (_windows ? File(Platform.resolvedExecutable).parent.path : null);

  bool get isInstalledCopy {
    final dir = installDir;
    return dir != null && File('$dir${Platform.pathSeparator}$installerMarker').existsSync();
  }

  void logStartup() {
    final dir = installDir;
    if (dir == null) return;
    DiagLog.write('app: start ${current.label} '
        '(${isInstalledCopy ? 'installed' : 'portable'}) in $dir');
  }

  // A portable copy (zip, or updated by the old zip updater) moves itself to the
  // installer once per version; returns true when the setup was started.
  Future<bool> migrateToInstaller() async {
    final dir = installDir;
    if (dir == null) return false;
    final blocker = installerMigrationBlocker(
      installDir: dir,
      installed: isInstalledCopy,
      attempted: _prefs?.getString(migrationKey),
      current: current,
    );
    if (blocker != null) {
      if (!isInstalledCopy) _log('installer: not moving ($blocker)');
      return false;
    }
    await _prefs?.setString(migrationKey, current.label);
    final result = await checkLatestRelease(
      client: _client,
      current: current,
      allowSameVersion: true,
      installerOnly: true,
    );
    final next = result.offer;
    if (next == null || !next.isInstaller) {
      _log('installer: no setup in the latest release'
          '${result.error == null ? '' : ' (${result.error})'}');
      return false;
    }
    _log('installer: portable copy in $dir, installing ${next.version.label}');
    offer = next;
    phase = UpdatePhase.ready;
    notifyListeners();
    await apply();
    final started = phase == UpdatePhase.applying;
    // Retry on the next start when the download or launch failed; once the
    // setup ran, a failed install must not loop on every start.
    if (!started) await _prefs?.remove(migrationKey);
    return started;
  }

  void recoverFailedApply() {
    final install = installDir;
    if (install == null) return;
    final sep = Platform.pathSeparator;
    final stage = Directory('$install$sep.scglow_update');
    if (stage.existsSync()) {
      _log('previous apply did not run');
      try {
        stage.deleteSync(recursive: true);
      } catch (_) {}
    }
    final nested = Directory('$install${sep}data${sep}data');
    if (!nested.existsSync()) return;
    _log('removed nested data folder');
    try {
      nested.deleteSync(recursive: true);
    } catch (_) {}
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
    if (next.isInstaller) {
      await _runSetup(zip, dir);
      return;
    }
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
      final updaterArgs = [
        '$pid',
        stage.path,
        install,
        backup.path,
        exe,
      ];
      final launch = _launchUpdater;
      if (launch != null) {
        await launch(updaterArgs);
      } else if (Platform.isWindows) {
        await startWindowsUpdater(scriptPath: script.path, scriptArgs: updaterArgs);
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

  Future<void> _runSetup(File setup, Directory dir) async {
    try {
      await player.save();
      final args = windowsSetupArgs(
        waitPid: pid,
        logPath: '${dir.path}${Platform.pathSeparator}setup.log',
      );
      final launch = _launchSetup;
      if (launch != null) {
        await launch(setup.path, args);
      } else if (_windows) {
        await startHiddenWindowsProcess(windowsCommandLine(setup.path, args));
      } else {
        throw const DownloadException('Updates can only be installed on Windows.');
      }
      _log('setup launched, quitting');
      await window.quit();
    } on DownloadException catch (e) {
      phase = UpdatePhase.failed;
      message = e.message;
      _log('setup failed: ${e.message}');
      notifyListeners();
    } catch (e) {
      phase = UpdatePhase.failed;
      message = "Couldn't start the installer.";
      _log('setup failed: ${e.runtimeType}');
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

const installerMarker = 'scglow.installed';

// Why a portable copy should not move to the installer, or null when it should.
String? installerMigrationBlocker({
  required String installDir,
  required bool installed,
  required String? attempted,
  required AppVersion current,
}) {
  if (installed) return 'installed copy';
  final path = installDir.replaceAll('/', r'\').toLowerCase();
  if (path.contains(r'\build\windows\')) return 'development build';
  if (attempted == current.label) return 'already tried for ${current.label}';
  return null;
}

List<String> windowsSetupArgs({required int waitPid, required String logPath}) => [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/NOCANCEL',
      '/SP-',
      '/CLOSEAPPLICATIONS',
      '/WAITPID=$waitPid',
      '/RELAUNCH=1',
      '/LOG=$logPath',
    ];

String windowsCommandLine(String exe, List<String> args) {
  String q(String s) => '"${s.replaceAll('"', '\\"')}"';
  // Inno Setup reads /NAME=value switches whole, so quote only the value part.
  String arg(String a) {
    if (!a.startsWith('/')) return q(a);
    final eq = a.indexOf('=');
    if (eq < 0 || !a.contains(' ')) return a;
    return '${a.substring(0, eq + 1)}${q(a.substring(eq + 1))}';
  }

  return [q(exe), ...args.map(arg)].join(' ');
}

String windowsUpdaterCommand(String scriptPath, List<String> scriptArgs) {
  String q(String s) => '"${s.replaceAll('"', '\\"')}"';
  return [
    'powershell.exe',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    q(scriptPath),
    ...scriptArgs.map(q),
  ].join(' ');
}

Future<void> startWindowsUpdater({
  required String scriptPath,
  required List<String> scriptArgs,
  Future<ProcessResult> Function(String exe, List<String> args)? run,
}) =>
    startHiddenWindowsProcess(windowsUpdaterCommand(scriptPath, scriptArgs), run: run);

// WMI starts the process outside Flutter's job object, so TerminateProcess on
// quit does not kill it (Process.start(detached) stayed in the job), and
// ShowWindow=0 keeps any console hidden. The launcher itself runs detached so
// it gets no console window either.
Future<void> startHiddenWindowsProcess(
  String commandLine, {
  Future<ProcessResult> Function(String exe, List<String> args)? run,
}) async {
  final wrapped =
      '\$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly '
      '-Property @{ ShowWindow = [uint16]0 }; '
      '\$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create '
      '-Arguments @{ CommandLine = ${powershellSingleQuote(commandLine)}; '
      'ProcessStartupInformation = [CimInstance]\$si }; '
      'if (\$r.ReturnValue -ne 0) { [Console]::Error.WriteLine("Win32_Process.Create failed: \$(\$r.ReturnValue)"); exit 1 }; '
      '"started \$(\$r.ProcessId)"';
  final runFn = run ?? _runDetached;
  final result = await runFn('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    wrapped,
  ]);
  if (result.exitCode != 0) {
    final err = result.stderr.toString().trim();
    throw DownloadException(
        "Couldn't start the updater${err.isEmpty ? '' : ': $err'}.");
  }
  DiagLog.write('update: ${result.stdout.toString().trim()}');
}

// detachedWithStdio has no exit code, so success is the "started" line.
Future<ProcessResult> _runDetached(String exe, List<String> args) async {
  final p = await Process.start(exe, args, mode: ProcessStartMode.detachedWithStdio);
  final out = p.stdout.transform(const SystemEncoding().decoder).join();
  final err = p.stderr.transform(const SystemEncoding().decoder).join();
  final stdout = await out.timeout(const Duration(seconds: 60), onTimeout: () => '');
  final stderr = await err.timeout(const Duration(seconds: 5), onTimeout: () => '');
  final ok = RegExp(r'^started \d+', multiLine: true).hasMatch(stdout);
  return ProcessResult(p.pid, ok ? 0 : 1, stdout, ok || stderr.isNotEmpty ? stderr : 'no response');
}

String powershellSingleQuote(String value) =>
    "'${value.replaceAll("'", "''")}'";

const updaterScript = r'''
$ErrorActionPreference = 'Stop'
$appPid = [int]$args[0]
$stage  = $args[1]
$dest   = $args[2]
$backup = $args[3]
$exe    = $args[4]
$appLog = Join-Path $env:TEMP 'scglow.log'
$ownLog = Join-Path $env:TEMP 'scglow_update.log'
function Write-Log($msg) {
  $line = '{0} update: {1}' -f ([DateTime]::Now.ToString('o')), $msg
  try { Add-Content -LiteralPath $ownLog -Value $line -ErrorAction SilentlyContinue } catch {}
  try { Add-Content -LiteralPath $appLog -Value $line -ErrorAction SilentlyContinue } catch {}
}
# Copy a file, or merge a directory's contents into an existing destination
# (Copy-Item -Recurse of a folder into an existing folder nests it: data\data).
function Copy-Merge($src, $dst) {
  if (Test-Path -LiteralPath $src -PathType Container) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
      Copy-Merge $_.FullName (Join-Path $dst $_.Name)
    }
  } else {
    $parent = Split-Path -Parent $dst
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
}
function Test-SameFile($left, $right) {
  if (-not (Test-Path -LiteralPath $left) -or -not (Test-Path -LiteralPath $right)) { return $false }
  $a = Get-Item -LiteralPath $left
  $b = Get-Item -LiteralPath $right
  if ($a.Length -ne $b.Length) { return $false }
  $ha = (Get-FileHash -LiteralPath $left -Algorithm SHA256).Hash
  $hb = (Get-FileHash -LiteralPath $right -Algorithm SHA256).Hash
  return [bool]($ha -eq $hb)
}
function Test-Applied {
  $exeSrc = Join-Path $stage 'scglow.exe'
  if ((Test-Path -LiteralPath $exeSrc) -and -not (Test-SameFile $exeSrc $exe)) { return $false }
  $soSrc = Join-Path $stage 'data\app.so'
  $soDst = Join-Path $dest 'data\app.so'
  if ((Test-Path -LiteralPath $soSrc) -and -not (Test-SameFile $soSrc $soDst)) { return $false }
  return $true
}
function Restore-Backup {
  if (-not (Test-Path -LiteralPath $backup)) { return }
  Get-ChildItem -LiteralPath $backup -Force | ForEach-Object {
    Copy-Merge $_.FullName (Join-Path $dest $_.Name)
  }
  Write-Log 'apply: rolled back'
}
function Start-App {
  try { if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe } } catch { Write-Log ('apply: relaunch failed: ' + $_.Exception.Message) }
}
Write-Log ("apply: started, waiting for pid {0}" -f $appPid)
$deadline = (Get-Date).AddMinutes(2)
while (Get-Process -Id $appPid -ErrorAction SilentlyContinue) {
  if ((Get-Date) -gt $deadline) { Write-Log 'apply: timed out waiting for the app to exit'; break }
  Start-Sleep -Milliseconds 400
}
try {
  if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  Get-ChildItem -LiteralPath $dest -Force | Where-Object { $_.Name -ne '.scglow_update' } | ForEach-Object {
    Copy-Merge $_.FullName (Join-Path $backup $_.Name)
  }
  Write-Log 'apply: backup ready'
  Get-ChildItem -LiteralPath $stage -Force | ForEach-Object {
    Copy-Merge $_.FullName (Join-Path $dest $_.Name)
  }
  Write-Log 'apply: files copied'
  if (-not (Test-Applied)) {
    Write-Log 'apply: verify failed'
    Restore-Backup
    Start-App
    exit 1
  }
} catch {
  Write-Log ('apply failed, rolling back: ' + $_.Exception.Message)
  try { Restore-Backup } catch { Write-Log ('apply: rollback failed: ' + $_.Exception.Message) }
  Start-App
  exit 1
}
Start-App
Write-Log 'apply: relaunched'
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
'''
;
