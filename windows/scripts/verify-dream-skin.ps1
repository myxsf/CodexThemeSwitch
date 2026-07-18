[CmdletBinding()]
param(
  [int]$Port = 0,
  [string]$ExpectedTheme,
  [string]$ScreenshotPath,
  [switch]$ExpectRemoved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
$state = Read-SkinState
if (-not $Port) { $Port = if ($state -and $state.port) { [int]$state.port } else { 9335 } }
$package = Resolve-CodexPackage
$node = Resolve-NodeRuntime -Package $package
$arguments = @($script:InjectorPath, '--port', "$Port", '--timeout-ms', '10000')
if ($ExpectRemoved) { $arguments += '--remove' } else { $arguments += '--verify' }
if ($ExpectedTheme -and -not $ExpectRemoved) { $arguments += @('--theme-id', $ExpectedTheme) }
if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
& $node @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($ExpectedTheme -and $state.activeThemeId -ne $ExpectedTheme) { throw "State theme '$($state.activeThemeId)' does not match '$ExpectedTheme'." }
if (-not $ExpectRemoved -and $state.injectorPid -and -not (Test-InjectorProcess -ProcessId ([int]$state.injectorPid))) { throw 'The recorded injector is not alive or does not match this installation.' }
exit 0
