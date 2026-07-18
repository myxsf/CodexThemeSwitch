[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$ThemeId,
  [string]$CatalogPath,
  [switch]$RestartExisting,
  [string]$ProfilePath,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
if ($CatalogPath) { $script:CatalogPath = [IO.Path]::GetFullPath($CatalogPath) }
New-SkinStateRoot

$package = Resolve-CodexPackage
$exe = Resolve-CodexExecutable -Package $package
$node = Resolve-NodeRuntime -Package $package
$state = Read-SkinState
if (-not $ThemeId) {
  if ($state -and $state.activeThemeId) { $ThemeId = [string]$state.activeThemeId }
  elseif (Test-Path -LiteralPath $script:ActiveThemePath) { $ThemeId = (Get-Content -LiteralPath $script:ActiveThemePath -Raw).Trim() }
  else { $ThemeId = 'skin-05' }
}
$theme = Get-ThemeEntry -Id $ThemeId

$debugReady = Test-CodexCdp -Port $Port
$mainProcesses = @(Get-CodexProcesses -Executable $exe)
if (-not $debugReady -and -not $ProfilePath -and $mainProcesses.Count -gt 0) {
  if (-not $RestartExisting) { throw "Codex is already running without the wardrobe debug port. Retry with -RestartExisting." }
  Stop-CodexProcesses -Executable $exe -Force
}

if (-not (Test-CodexCdp -Port $Port)) {
  try {
    $occupied = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
    if ($occupied) { $Port = Find-AvailableSkinPort -Preferred ($Port + 1) }
  } catch {}
  $arguments = @("--remote-debugging-address=127.0.0.1", "--remote-debugging-port=$Port")
  if ($ProfilePath) {
    New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
    $arguments += "--user-data-dir=$ProfilePath"
  }
  Start-Process -FilePath $exe -ArgumentList $arguments | Out-Null
}

$deadline = (Get-Date).AddSeconds(40)
while (-not (Test-CodexCdp -Port $Port)) {
  if ((Get-Date) -ge $deadline) { throw "Codex did not expose loopback CDP on port $Port within 40 seconds." }
  Start-Sleep -Milliseconds 400
}

Stop-RecordedInjector
if ($theme.kind -eq 'original' -or $theme.profile -eq 'off') {
  & $node $script:InjectorPath --remove --port $Port --timeout-ms 8000 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Original mode could not verify complete skin removal.' }
  Write-SkinState -Port $Port -InjectorPid 0 -ThemeId 'original' -NodePath $node -CodexExe $exe -Session 'off'
  Write-Host "Codex is using its original appearance on port $Port."
  exit 0
}

& $node $script:InjectorPath --check-payload --catalog $script:CatalogPath --theme-id $ThemeId | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Theme validation failed: $ThemeId" }

if ($ForegroundInjector) {
  & $node $script:InjectorPath --watch --port $Port --catalog $script:CatalogPath --theme-id $ThemeId
  exit $LASTEXITCODE
}

Set-Content -LiteralPath $script:InjectorLog -Value '' -Encoding UTF8
Set-Content -LiteralPath $script:InjectorErrorLog -Value '' -Encoding UTF8
$injectorArgs = @(
  "`"$script:InjectorPath`"", '--watch', '--port', "$Port",
  '--catalog', "`"$script:CatalogPath`"", '--theme-id', "`"$ThemeId`""
)
$daemon = Start-Process -FilePath $node -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput $script:InjectorLog -RedirectStandardError $script:InjectorErrorLog

Start-Sleep -Milliseconds 300
if (-not (Test-InjectorProcess -ProcessId $daemon.Id)) { throw "Theme injector exited early. See $script:InjectorErrorLog" }
& $node $script:InjectorPath --once --port $Port --catalog $script:CatalogPath --theme-id $ThemeId --timeout-ms 12000 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Stop-Process -Id $daemon.Id -Force -ErrorAction SilentlyContinue
  throw "Theme application failed: $ThemeId"
}
Write-SkinState -Port $Port -InjectorPid $daemon.Id -ThemeId $ThemeId -NodePath $node -CodexExe $exe
Write-Host "Codex theme '$($theme.name)' is active on port $Port."
