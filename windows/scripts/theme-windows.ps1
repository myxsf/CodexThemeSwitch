[CmdletBinding()]
param(
  [Parameter(Position=0)][ValidateSet('list','status','switch')][string]$Action = 'status',
  [Parameter(Position=1)][string]$Id,
  [switch]$Json,
  [switch]$Deep,
  [switch]$RestartExisting
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
if ($Json) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding -ArgumentList $false }
switch ($Action) {
  'status' {
    & (Join-Path $PSScriptRoot 'status-dream-skin.ps1') -Json:$Json -Deep:$Deep
  }
  'switch' {
    if (-not $Id) { throw 'Usage: theme-windows.ps1 switch <theme-id>' }
    & (Join-Path $PSScriptRoot 'switch-theme-windows.ps1') -Id $Id -RestartExisting:$RestartExisting
  }
  'list' {
    $state = Read-SkinState
    $active = if ($state -and $state.activeThemeId) { [string]$state.activeThemeId } else { 'original' }
    $items = @()
    foreach ($theme in (Get-ThemeCatalog).themes | Sort-Object order, name) {
      if ($theme.enabled -eq $false) { continue }
      $platforms = @($theme.platforms)
      if ($platforms.Count -gt 0 -and -not ($platforms -contains 'windows' -or $platforms -contains 'win32' -or $platforms -contains 'all')) { continue }
      $items += [pscustomobject][ordered]@{
        id = [string]$theme.id; kind = [string]$theme.kind; name = [string]$theme.name
        subtitle = if ($theme.subtitle) { [string]$theme.subtitle } else { [string]$theme.description }
        tagline = [string]$theme.tagline
        profile = [string]$theme.profile; preview = Resolve-ThemePreview -Theme $theme
        colors = $theme.colors
        order = [int]$theme.order; active = ([string]$theme.id -eq $active)
        experimental = [bool]$theme.experimental
      }
    }
    if ($Json) { @($items) | ConvertTo-Json -Depth 4 -Compress }
    else { $items | Format-Table -AutoSize id, name, profile, active }
  }
}
