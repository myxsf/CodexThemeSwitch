$ErrorActionPreference = 'Stop'

$script:WindowsRoot = Split-Path -Parent $PSScriptRoot
$script:RepositoryRoot = Split-Path -Parent $script:WindowsRoot
$script:StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkinStudio'
$script:StatePath = Join-Path $script:StateRoot 'state.json'
$script:ActiveThemePath = Join-Path $script:StateRoot 'active-theme-id'
$script:InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\CodexThemeWardrobe'
$script:CatalogPath = Join-Path $script:RepositoryRoot 'themes\catalog.json'
$script:InjectorPath = Join-Path $PSScriptRoot 'injector.mjs'
$script:InjectorLog = Join-Path $script:StateRoot 'injector.log'
$script:InjectorErrorLog = Join-Path $script:StateRoot 'injector-error.log'
$script:SkinVersion = '2.2.9'

function New-SkinStateRoot {
  New-Item -ItemType Directory -Force -Path $script:StateRoot | Out-Null
}

function Resolve-UserDesktopPath {
  $desktop = [Environment]::GetFolderPath('Desktop')
  if ([string]::IsNullOrWhiteSpace($desktop) -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $desktop = Join-Path $env:USERPROFILE 'Desktop'
  }
  if ([string]::IsNullOrWhiteSpace($desktop)) { throw 'The current user Desktop path could not be resolved.' }
  return $desktop
}

function Resolve-CodexPackage {
  $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
  if (-not $package) { throw 'The official OpenAI.Codex Store package is not installed for this user.' }
  if ($package.Status -and [string]$package.Status -ne 'Ok') { throw "The Codex package status is $($package.Status). Repair Codex first." }
  return $package
}

function Resolve-CodexExecutable {
  param($Package)
  if (-not $Package) { $Package = Resolve-CodexPackage }
  $manifestPath = Join-Path $Package.InstallLocation 'AppxManifest.xml'
  if (Test-Path -LiteralPath $manifestPath) {
    try {
      [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
      $application = $manifest.SelectSingleNode("//*[local-name()='Application']")
      $relative = [string]$application.Executable
      if ($relative) {
        $candidate = Join-Path $Package.InstallLocation ($relative -replace '/', '\')
        if (Test-Path -LiteralPath $candidate) { return (Get-Item -LiteralPath $candidate).FullName }
      }
    } catch {}
  }
  $fallback = Join-Path $Package.InstallLocation 'app\ChatGPT.exe'
  if (-not (Test-Path -LiteralPath $fallback)) { throw "Codex executable was not found under $($Package.InstallLocation)." }
  return (Get-Item -LiteralPath $fallback).FullName
}

function Resolve-NodeRuntime {
  param($Package)
  if (-not $Package) { $Package = Resolve-CodexPackage }
  $candidates = @(
    (Join-Path $Package.InstallLocation 'app\resources\cua_node\bin\node.exe'),
    (Join-Path $Package.InstallLocation 'app\Resources\cua_node\bin\node.exe'),
    (Join-Path $Package.InstallLocation 'resources\cua_node\bin\node.exe'),
    (Join-Path $Package.InstallLocation 'app\resources\cua_node\node.exe'),
    (Join-Path $Package.InstallLocation 'app\Resources\cua_node\node.exe')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      $version = & $candidate --version
      if ($LASTEXITCODE -eq 0 -and $version -match '^v(\d+)\.' -and [int]$Matches[1] -ge 20) { return (Get-Item $candidate).FullName }
    }
  }
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if ($command) {
    $version = & $command.Source --version
    if ($LASTEXITCODE -eq 0 -and $version -match '^v(\d+)\.' -and [int]$Matches[1] -ge 20) { return $command.Source }
  }
  throw 'Node.js 20+ was not found in the Codex package or PATH. Reinstall/update official Codex first.'
}

function Get-CodexProcesses {
  param([string]$Executable)
  if (-not $Executable) { $Executable = Resolve-CodexExecutable }
  $expected = [IO.Path]::GetFullPath($Executable).TrimEnd('\')
  @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath).TrimEnd('\').Equals($expected, [StringComparison]::OrdinalIgnoreCase)
  })
}

function Stop-CodexProcesses {
  param([string]$Executable, [switch]$Force)
  $processes = @(Get-CodexProcesses -Executable $Executable)
  foreach ($item in $processes) {
    try { [void](Get-Process -Id $item.ProcessId -ErrorAction Stop).CloseMainWindow() } catch {}
  }
  $deadline = (Get-Date).AddSeconds(12)
  while ((Get-Date) -lt $deadline -and @(Get-CodexProcesses -Executable $Executable).Count -gt 0) { Start-Sleep -Milliseconds 250 }
  $remaining = @(Get-CodexProcesses -Executable $Executable)
  if ($remaining.Count -gt 0 -and -not $Force) { throw 'Codex did not close. Retry from the wardrobe and allow restart.' }
  foreach ($item in $remaining) { Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Test-CodexCdp {
  param([int]$Port)
  try {
    $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 1
    return [bool]($targets | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' -and $_.webSocketDebuggerUrl })
  } catch { return $false }
}

function Find-AvailableSkinPort {
  param([int]$Preferred = 9335)
  for ($port = $Preferred; $port -le [Math]::Min(65535, $Preferred + 100); $port++) {
    try {
      $listener = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction Stop
      if (-not $listener) { return $port }
    } catch { return $port }
  }
  throw "No free port was found from $Preferred to $($Preferred + 100)."
}

function Read-SkinState {
  if (-not (Test-Path -LiteralPath $script:StatePath)) { return $null }
  try { return Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-SkinState {
  param([int]$Port, [int]$InjectorPid, [string]$ThemeId, [string]$NodePath, [string]$CodexExe, [string]$Session = 'active')
  New-SkinStateRoot
  $temporary = "$script:StatePath.$PID.tmp"
  [ordered]@{
    schemaVersion = 2; platform = 'windows'; skinVersion = $script:SkinVersion; session = $Session
    port = $Port; injectorPid = $InjectorPid; activeThemeId = $ThemeId; nodePath = $NodePath
    codexExe = $CodexExe; catalogPath = $script:CatalogPath; createdAt = (Get-Date).ToString('o')
  } | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
  Set-Content -LiteralPath $script:ActiveThemePath -Value $ThemeId -Encoding ASCII
}

function Test-InjectorProcess {
  param([int]$ProcessId)
  if (-not $ProcessId) { return $false }
  $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $process -or -not $process.CommandLine) { return $false }
  $expected = [IO.Path]::GetFullPath($script:InjectorPath)
  return $process.CommandLine.IndexOf($expected, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $process.CommandLine -match '--watch'
}

function Stop-RecordedInjector {
  $state = Read-SkinState
  if ($state -and $state.injectorPid -and (Test-InjectorProcess -ProcessId ([int]$state.injectorPid))) {
    Stop-Process -Id ([int]$state.injectorPid) -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 250
    if (Test-InjectorProcess -ProcessId ([int]$state.injectorPid)) { Stop-Process -Id ([int]$state.injectorPid) -Force -ErrorAction SilentlyContinue }
  }
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and $_.CommandLine.IndexOf([IO.Path]::GetFullPath($script:InjectorPath), [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -match '--watch'
  } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Get-ThemeCatalog {
  if (-not (Test-Path -LiteralPath $script:CatalogPath)) { throw "Theme catalog not found: $script:CatalogPath" }
  $catalog = Get-Content -LiteralPath $script:CatalogPath -Raw | ConvertFrom-Json
  if ($catalog.schemaVersion -ne 1 -or -not $catalog.themes) { throw 'Unsupported theme catalog schema.' }
  return $catalog
}

function Get-ThemeEntry {
  param([string]$Id)
  $catalog = Get-ThemeCatalog
  foreach ($theme in $catalog.themes) {
    if ($theme.id -eq $Id -or ($theme.aliases -and $theme.aliases -contains $Id)) { return $theme }
  }
  throw "Theme not found: $Id"
}

function Resolve-ThemePreview {
  param($Theme)
  if (-not $Theme.preview) { return '' }
  $candidate = Join-Path $script:RepositoryRoot ([string]$Theme.preview -replace '/', '\')
  if (Test-Path -LiteralPath $candidate) { return (Get-Item $candidate).FullName }
  return ''
}
