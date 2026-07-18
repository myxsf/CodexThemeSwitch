[CmdletBinding()]
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
$version = (Get-Content -LiteralPath (Join-Path $windowsRoot 'VERSION') -Raw).Trim()
$release = Join-Path $windowsRoot 'release'
$stage = Join-Path $env:TEMP "codex-theme-wardrobe-$PID"
$bundle = Join-Path $stage 'Codex Theme Wardrobe'
$archive = Join-Path $release "codex-theme-wardrobe-windows-v$version.zip"
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $bundle, $release | Out-Null
try {
  if (-not $SkipTests) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $windowsRoot 'tests\run-tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Windows release tests failed.' }
  }
  $bundleWindows = Join-Path $bundle 'windows'
  New-Item -ItemType Directory -Force -Path $bundleWindows | Out-Null
  Get-ChildItem -LiteralPath $windowsRoot -Force | Where-Object { $_.Name -ne 'release' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $bundleWindows -Recurse -Force }
  Copy-Item -LiteralPath (Join-Path $repoRoot 'themes') -Destination (Join-Path $bundle 'themes') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'macos') | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot 'macos\themes') -Destination (Join-Path $bundle 'macos\themes') -Recurse -Force
  & (Join-Path $windowsRoot 'scripts\build-theme-switcher.ps1') -OutputPath (Join-Path $bundle 'Codex Theme Wardrobe.exe')
  Copy-Item -LiteralPath (Join-Path $windowsRoot 'README.md') -Destination (Join-Path $bundle 'README.md')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'release\README.zh-CN.md') -Destination (Join-Path $bundle 'README.zh-CN.md') -ErrorAction SilentlyContinue
  @(
    '@echo off',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\scripts\install-dream-skin.ps1"',
    'if errorlevel 1 pause'
  ) | Set-Content -LiteralPath (Join-Path $bundle 'Install Codex Theme Wardrobe.cmd') -Encoding ASCII
  Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
  Compress-Archive -LiteralPath $bundle -DestinationPath $archive -CompressionLevel Optimal
  $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt') -Value "$hash  $([IO.Path]::GetFileName($archive))" -Encoding ASCII
  Write-Host "Created $archive`nSHA-256 $hash"
} finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
