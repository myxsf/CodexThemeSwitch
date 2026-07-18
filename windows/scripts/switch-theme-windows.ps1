[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Id,
  [int]$Port = 0,
  [switch]$RestartExisting
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
New-SkinStateRoot
$mutex = New-Object Threading.Mutex($false, 'Local\CodexDreamSkinThemeSwitch')
if (-not $mutex.WaitOne(15000)) { throw 'Another theme switch is still running.' }
try {
  $theme = Get-ThemeEntry -Id $Id
  if ($theme.enabled -eq $false) { throw "Theme is disabled: $Id" }
  $platforms = @($theme.platforms)
  if ($platforms.Count -gt 0 -and -not ($platforms -contains 'windows' -or $platforms -contains 'win32' -or $platforms -contains 'all')) {
    throw "Theme does not support Windows: $Id"
  }
  $package = Resolve-CodexPackage
  $node = Resolve-NodeRuntime -Package $package
  & $node $script:InjectorPath --check-payload --catalog $script:CatalogPath --theme-id $theme.id | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Theme validation failed before switching: $Id" }
  $previous = Read-SkinState
  if (-not $Port) { $Port = if ($previous -and $previous.port) { [int]$previous.port } else { 9335 } }
  try {
    & (Join-Path $PSScriptRoot 'start-dream-skin.ps1') -Port $Port -ThemeId ([string]$theme.id) -RestartExisting:$RestartExisting
    if ($LASTEXITCODE -ne 0) { throw "Theme start returned $LASTEXITCODE" }
  } catch {
    $failure = $_
    if ($previous -and $previous.activeThemeId -and $previous.activeThemeId -ne $theme.id) {
      try { & (Join-Path $PSScriptRoot 'start-dream-skin.ps1') -Port $Port -ThemeId ([string]$previous.activeThemeId) -RestartExisting:$RestartExisting | Out-Null } catch {}
    }
    throw "Theme switch failed and the previous state was restored: $($failure.Exception.Message)"
  }
} finally {
  $mutex.ReleaseMutex()
  $mutex.Dispose()
}
