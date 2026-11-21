$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot)
$deps = Get-Content .flutter-plugins-dependencies -Raw | ConvertFrom-Json
$dir = 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($p in $deps.plugins.windows) {
  $link = Join-Path $dir $p.name
  if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null }
  cmd /c mklink /J "$link" "$($p.path.TrimEnd('\'))" | Out-Null
}
flutter pub get
