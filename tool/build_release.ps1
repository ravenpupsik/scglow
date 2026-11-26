# Builds scglow and writes the release files to dist\:
#   scglow-setup-<version>.exe (+ .sha256)  installer, used by the in-app updater
#   scglow-windows-<version>.zip (+ .sha256) portable zip, kept for older app versions
# Usage: powershell -ExecutionPolicy Bypass -File .\tool\build_release.ps1 [-SkipBuild] [-Iscc <path to ISCC.exe>]
param(
  [switch]$SkipBuild,
  [string]$Iscc
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\S+)') { throw 'version not found in pubspec.yaml' }
$ver = $Matches[1]
if ($ver -notmatch '^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$') { throw "unsupported version '$ver'" }
$build = if ($Matches[4]) { $Matches[4] } else { '0' }
$numeric = "$($Matches[1]).$($Matches[2]).$($Matches[3]).$build"
$appVersion = Get-Content -LiteralPath (Join-Path $root 'lib\core\app_version.dart') -Raw
$parts = $numeric -split '\.'
if ($appVersion -notmatch "AppVersion\($($parts[0]), $($parts[1]), $($parts[2]), $($parts[3])\)") {
  throw "lib\core\app_version.dart does not match pubspec version $ver"
}

Push-Location $root
try {
  if (-not $SkipBuild) {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }
  }
} finally { Pop-Location }

$rel = Join-Path $root 'build\windows\x64\runner\Release'
$exe = Join-Path $rel 'scglow.exe'
foreach ($f in @('scglow.exe', 'data\app.so', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  if (-not (Test-Path -LiteralPath (Join-Path $rel $f))) {
    throw "missing $f in $rel (the MSVC runtime DLLs come from Visual Studio's C++ redistributable folder)"
  }
}
$fileVersion = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
if ($fileVersion -ne $ver) { throw "scglow.exe is $fileVersion, expected $ver; rebuild" }
$stale = Join-Path $rel '.scglow_update'
if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force }

if (-not $Iscc) {
  $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
  $candidates = @(
    $(if ($cmd) { $cmd.Source }),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  $Iscc = $candidates | Select-Object -First 1
}
if (-not $Iscc) { throw 'ISCC.exe not found; install Inno Setup 6.3+ or pass -Iscc' }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
& $Iscc "/DAppVersion=$ver" "/DAppVersionNumeric=$numeric" "/DReleaseDir=$rel" "/DOutputDir=$dist" (Join-Path $root 'installer\installer.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
$setup = Join-Path $dist "scglow-setup-$ver.exe"
if (-not (Test-Path -LiteralPath $setup)) { throw "ISCC did not write $setup" }

$zip = Join-Path $dist "scglow-windows-$ver.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($rel, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

foreach ($file in @($setup, $zip)) {
  $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
  $name = Split-Path -Leaf $file
  Set-Content -LiteralPath "$file.sha256" -Value "$hash  $name`n" -Encoding ascii -NoNewline
  Write-Host "$name  SHA-256 $hash"
}
Write-Host "Upload the files in $dist to a GitHub Release tagged v$ver."
