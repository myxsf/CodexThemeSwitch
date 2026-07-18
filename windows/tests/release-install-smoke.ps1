[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ArchivePath)

$ErrorActionPreference = 'Stop'
$archive = [IO.Path]::GetFullPath($ArchivePath)
if (-not (Test-Path -LiteralPath $archive)) { throw "Release archive not found: $archive" }

$work = Join-Path $env:RUNNER_TEMP "codex-theme-release-smoke-$PID"
$oldLocalAppData = $env:LOCALAPPDATA
$oldAppData = $env:APPDATA
$oldUserProfile = $env:USERPROFILE
$oldSmokePackage = $env:CODEX_DREAM_SKIN_SMOKE_PACKAGE
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
  $expanded = Join-Path $work 'archive'
  Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
  $bundle = Get-ChildItem -LiteralPath $expanded -Directory | Select-Object -First 1
  if (-not $bundle) { throw 'Windows release bundle was not found.' }
  $installer = Join-Path $bundle.FullName 'windows\scripts\install-dream-skin.ps1'
  if (-not (Test-Path -LiteralPath $installer)) { throw 'Packaged Windows installer is missing.' }

  $userRoot = Join-Path $work 'user'
  $env:LOCALAPPDATA = Join-Path $userRoot 'AppData\Local'
  $env:APPDATA = Join-Path $userRoot 'AppData\Roaming'
  $env:USERPROFILE = $userRoot
  New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA, $env:APPDATA | Out-Null

  $fakePackage = Join-Path $work 'OpenAI.Codex'
  $fakeApp = Join-Path $fakePackage 'app'
  $fakeNode = Join-Path $fakeApp 'resources\cua_node\bin'
  New-Item -ItemType Directory -Force -Path $fakeNode | Out-Null
  $node = (Get-Command node.exe -ErrorAction Stop).Source
  Copy-Item -LiteralPath $node -Destination (Join-Path $fakeNode 'node.exe') -Force
  Copy-Item -LiteralPath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Destination (Join-Path $fakeApp 'ChatGPT.exe') -Force
  @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Applications><Application Id="Codex" Executable="app\ChatGPT.exe" EntryPoint="Windows.FullTrustApplication" /></Applications>
</Package>
'@ | Set-Content -LiteralPath (Join-Path $fakePackage 'AppxManifest.xml') -Encoding UTF8
  $env:CODEX_DREAM_SKIN_SMOKE_PACKAGE = $fakePackage

  $common = Join-Path $bundle.FullName 'windows\scripts\common-windows.ps1'
  @'

if ($env:CODEX_DREAM_SKIN_SMOKE_PACKAGE) {
  function Resolve-CodexPackage {
    [pscustomobject]@{
      InstallLocation = $env:CODEX_DREAM_SKIN_SMOKE_PACKAGE
      Status = 'Ok'
      Version = [version]'1.0.0.0'
    }
  }
}
'@ | Add-Content -LiteralPath $common -Encoding UTF8

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Port 19335 -NoShortcuts -NoLaunch
  if ($LASTEXITCODE -ne 0) { throw "Packaged installer exited with $LASTEXITCODE" }

  $installed = Join-Path $env:LOCALAPPDATA 'Programs\CodexThemeWardrobe'
  $wardrobe = Join-Path $installed 'Codex Theme Wardrobe.exe'
  $themeScript = Join-Path $installed 'windows\scripts\theme-windows.ps1'
  $statePath = Join-Path $env:LOCALAPPDATA 'CodexDreamSkinStudio\state.json'
  if (-not (Test-Path -LiteralPath $wardrobe)) { throw 'Installed WPF wardrobe executable is missing.' }
  if (-not (Test-Path -LiteralPath $statePath)) { throw 'Initial runtime state is missing.' }

  $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  if ($state.activeThemeId -ne 'original' -or $state.session -ne 'off' -or $state.port -ne 19335) {
    throw 'Fresh install did not initialize original/off state.'
  }

  $themes = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $themeScript list -Json | Out-String) | ConvertFrom-Json
  $ids = @($themes | ForEach-Object { $_.id })
  foreach ($id in @('original','skin-01','skin-02','skin-03','skin-04','skin-05','skin-06','skin-07','skin-08','qq2007')) {
    if ($ids -notcontains $id) { throw "Installed theme is missing: $id" }
  }

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installed 'windows\tests\run-tests.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'Installed Windows static/WPF suite failed.' }

  $process = Start-Process -FilePath $wardrobe -PassThru
  Start-Sleep -Seconds 3
  if ($process.HasExited) { throw "Installed WPF wardrobe exited during startup with $($process.ExitCode)." }
  Stop-Process -Id $process.Id -Force

  Set-Content -LiteralPath (Join-Path $installed 'reinstall-marker.txt') -Value 'must disappear'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Port 19335 -NoShortcuts -NoLaunch
  if ($LASTEXITCODE -ne 0) { throw 'Atomic reinstall failed.' }
  if (Test-Path -LiteralPath (Join-Path $installed 'reinstall-marker.txt')) { throw 'Atomic reinstall preserved stale files.' }

  $restore = Join-Path $installed 'windows\scripts\restore-dream-skin.ps1'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $restore -Port 19335
  if ($LASTEXITCODE -ne 0) { throw 'Original-mode restore failed.' }
  $restored = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  if ($restored.activeThemeId -ne 'original' -or $restored.session -ne 'off') { throw 'Restore state is not original/off.' }

  Write-Host 'PASS: Windows release ZIP, atomic install, WPF compile/start, all themes, reinstall, and original restore.'
} finally {
  $env:LOCALAPPDATA = $oldLocalAppData
  $env:APPDATA = $oldAppData
  $env:USERPROFILE = $oldUserProfile
  $env:CODEX_DREAM_SKIN_SMOKE_PACKAGE = $oldSmokePackage
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
