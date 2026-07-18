[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
$parseFailed = $false
Get-ChildItem -LiteralPath $windowsRoot -Recurse -Filter '*.ps1' | ForEach-Object {
  $tokens = $null; $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error "$($_.Extent.File):$($_.Extent.StartLineNumber) $($_.Message)" }; $parseFailed = $true }
}
if ($parseFailed) { throw 'PowerShell syntax validation failed.' }

$buildScript = Get-Content -LiteralPath (Join-Path $windowsRoot 'scripts\build-theme-switcher.ps1') -Raw
if ($buildScript -notmatch 'LoadWithPartialName' -or $buildScript -match "'WindowsBase\.dll'") {
  throw 'WPF build references must resolve installed assembly locations instead of relative DLL names.'
}

$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $nodeCommand) { $nodeCommand = Get-Command node -ErrorAction SilentlyContinue }
if (-not $nodeCommand) {
  try { . (Join-Path $windowsRoot 'scripts\common-windows.ps1'); $node = Resolve-NodeRuntime } catch { throw 'Node.js 20+ is required for tests.' }
} else { $node = $nodeCommand.Source }
& $node --check (Join-Path $windowsRoot 'scripts\injector.mjs')
& $node --check (Join-Path $windowsRoot 'assets\renderer-inject.js')
$resizeSelfTest = (& $node (Join-Path $windowsRoot 'scripts\injector.mjs') --resize-self-test | Out-String) | ConvertFrom-Json
if (-not $resizeSelfTest.pass -or $resizeSelfTest.cases.Count -lt 10) { throw 'Eight-direction window resize geometry self-test failed.' }
$renderer = Get-Content -LiteralPath (Join-Path $windowsRoot 'assets\renderer-inject.js') -Raw
if ($renderer -match 'setInterval\(ensure,\s*5000\)') { throw 'Periodic full renderer ensure regression.' }
if ($renderer -notmatch 'profile === "qq2007" \? null') { throw 'QQ2007 must not create visual extra cards.' }
if ($renderer -notmatch "!button\.closest\('#dream-extra-card'\)") { throw 'Synthetic extra card must not count as a native card.' }
if ($renderer -notmatch '\["n", "s", "e", "w", "ne", "nw", "se", "sw"\]') { throw 'All eight resize handles must be declared.' }
$qqCss = Get-Content -LiteralPath (Join-Path $windowsRoot 'assets\qq2007.css') -Raw
foreach ($direction in @('n','s','e','w','ne','nw','se','sw')) {
  if ($qqCss -notmatch "data-dream-resize-direction=`"$direction`"") { throw "Missing resize cursor rule: $direction" }
}
if ($qqCss -notmatch '-webkit-app-region:\s*no-drag' -or $qqCss -notmatch 'pointer-events:\s*auto') { throw 'Resize handles must remain interactive and outside the drag region.' }

$catalogPath = Join-Path $repoRoot 'themes\catalog.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
foreach ($theme in $catalog.themes) {
  if ($theme.enabled -eq $false) { continue }
  if ($theme.platforms -and -not ($theme.platforms -contains 'win32' -or $theme.platforms -contains 'windows' -or $theme.platforms -contains 'all')) { continue }
  & $node (Join-Path $windowsRoot 'scripts\injector.mjs') --check-payload --catalog $catalogPath --theme-id $theme.id | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Theme payload failed: $($theme.id)" }
}

if (-not $SkipBuild) {
  $temporary = Join-Path $env:TEMP "CodexThemeWardrobe-test-$PID.exe"
  try { & (Join-Path $windowsRoot 'scripts\build-theme-switcher.ps1') -OutputPath $temporary; if (-not (Test-Path $temporary)) { throw 'WPF build failed.' } }
  finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
Write-Host 'PASS: PowerShell syntax, all Windows catalog payloads, JavaScript syntax, and WPF build.'
