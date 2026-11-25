# Packages the Release build as scglow-windows-<version>.zip plus a .sha256 file.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\S+)') {
  throw 'version not found in pubspec.yaml'
}
$ver = $Matches[1]
$src = Join-Path $root 'build\windows\x64\runner\Release'
$exe = Join-Path $src 'scglow.exe'
if (-not (Test-Path $exe)) {
  throw "Build first: $exe is missing. Run: flutter build windows --release"
}
$outDir = Join-Path $root 'release'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$name = "scglow-windows-$ver"
$zip = Join-Path $outDir "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
  $src,
  $zip,
  [IO.Compression.CompressionLevel]::Optimal,
  $false
)
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Set-Content -Path "$zip.sha256" -Value "$hash  $name.zip`n" -Encoding ascii -NoNewline
Write-Host "Wrote $zip"
Write-Host "SHA-256 $hash"
Write-Host "Upload both files to a GitHub Release tagged v$ver."
