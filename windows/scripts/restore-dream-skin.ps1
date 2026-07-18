[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Uninstall,
  [switch]$RestoreBaseTheme,
  [switch]$RestartCodex
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
New-SkinStateRoot
$state = Read-SkinState
if (-not $Port) { $Port = if ($state -and $state.port) { [int]$state.port } else { 9335 } }
$package = Resolve-CodexPackage
$exe = Resolve-CodexExecutable -Package $package
$node = Resolve-NodeRuntime -Package $package
Stop-RecordedInjector

if (Test-CodexCdp -Port $Port) {
  & $node $script:InjectorPath --remove --port $Port --timeout-ms 8000 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'The live skin could not be fully removed; state was preserved.' }
} elseif (@(Get-CodexProcesses -Executable $exe).Count -gt 0 -and -not $RestartCodex) {
  throw 'Codex is running but its saved CDP endpoint is unavailable. Use -RestartCodex for a complete restore.'
}

if ($RestoreBaseTheme) {
  $backup = Join-Path $script:StateRoot 'config.before-dream-skin.toml'
  $config = Join-Path $HOME '.codex\config.toml'
  if (Test-Path -LiteralPath $backup) { Copy-Item -LiteralPath $backup -Destination $config -Force }
}

if ($RestartCodex) {
  if (@(Get-CodexProcesses -Executable $exe).Count -gt 0) { Stop-CodexProcesses -Executable $exe -Force }
  Start-Process -FilePath $exe | Out-Null
}

Write-SkinState -Port $Port -InjectorPid 0 -ThemeId 'original' -NodePath $node -CodexExe $exe -Session 'off'
if ($Uninstall) {
  $desktop = Resolve-UserDesktopPath
  $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  @((Join-Path $desktop 'Codex Theme Wardrobe.lnk'), (Join-Path $startMenu 'Codex Theme Wardrobe.lnk')) |
    ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $script:InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'Codex original appearance was restored and verified.'
