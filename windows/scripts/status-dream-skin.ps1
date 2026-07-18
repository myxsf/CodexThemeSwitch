[CmdletBinding()]
param([switch]$Json, [switch]$Deep)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
$state = Read-SkinState
$port = if ($state -and $state.port) { [int]$state.port } else { 9335 }
$themeId = if ($state -and $state.activeThemeId) { [string]$state.activeThemeId } else { 'original' }
$themeName = $themeId
try { $themeName = [string](Get-ThemeEntry -Id $themeId).name } catch { if ($themeId -eq 'original') { $themeName = '原皮' } }
$alive = $false
if ($state -and $state.injectorPid) { $alive = Test-InjectorProcess -ProcessId ([int]$state.injectorPid) }
$cdp = if ($Deep) { Test-CodexCdp -Port $port } else { $false }
$codex = $false
try { $codex = @(Get-CodexProcesses -Executable (Resolve-CodexExecutable)).Count -gt 0 } catch {}
$result = [ordered]@{
  session = if ($themeId -eq 'original') { 'off' } elseif ($alive) { 'active' } else { 'stale' }
  port = $port; injectorAlive = [bool]$alive; cdpOk = [bool]$cdp; codexRunning = [bool]$codex
  themeId = $themeId; themeName = $themeName; skinVersion = $script:SkinVersion
}
if ($Json) { $result | ConvertTo-Json -Compress; exit 0 }
$result.GetEnumerator() | ForEach-Object { Write-Output "$($_.Key)=$($_.Value)" }
