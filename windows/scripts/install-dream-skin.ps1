[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$NoShortcuts,
  [switch]$NoLaunch,
  [switch]$InPlace
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
New-SkinStateRoot

if (-not $InPlace -and [IO.Path]::GetFullPath($script:RepositoryRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath($script:InstallRoot).TrimEnd('\')) {
  $staging = "$script:InstallRoot.installing.$PID"
  $previous = "$script:InstallRoot.previous.$PID"
  Remove-Item -LiteralPath $staging, $previous -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $staging | Out-Null
  $stagedWindows = Join-Path $staging 'windows'
  New-Item -ItemType Directory -Force -Path $stagedWindows | Out-Null
  Get-ChildItem -LiteralPath $script:WindowsRoot -Force | Where-Object { $_.Name -ne 'release' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stagedWindows -Recurse -Force }
  if (-not (Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'themes\catalog.json'))) { throw 'Shared themes/catalog.json is missing.' }
  Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'themes') -Destination (Join-Path $staging 'themes') -Recurse -Force
  if (Test-Path -LiteralPath (Join-Path $script:RepositoryRoot 'macos\themes')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $staging 'macos') | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'macos\themes') -Destination (Join-Path $staging 'macos\themes') -Recurse -Force
  }
  if (Test-Path -LiteralPath $script:InstallRoot) { Move-Item -LiteralPath $script:InstallRoot -Destination $previous }
  try { Move-Item -LiteralPath $staging -Destination $script:InstallRoot }
  catch {
    if (Test-Path -LiteralPath $previous) { Move-Item -LiteralPath $previous -Destination $script:InstallRoot }
    throw
  }
  Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction SilentlyContinue
  $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $script:InstallRoot 'windows\scripts\install-dream-skin.ps1'),'-Port',"$Port",'-InPlace')
  if ($NoShortcuts) { $arguments += '-NoShortcuts' }
  if ($NoLaunch) { $arguments += '-NoLaunch' }
  & powershell.exe @arguments
  exit $LASTEXITCODE
}

$script:CatalogPath = Join-Path $script:RepositoryRoot 'themes\catalog.json'
$package = Resolve-CodexPackage
$null = Resolve-CodexExecutable -Package $package
$node = Resolve-NodeRuntime -Package $package
& $node $script:InjectorPath --check-payload --catalog $script:CatalogPath --theme-id original | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'The installed theme catalog failed validation.' }

$wardrobeExe = Join-Path $script:RepositoryRoot 'Codex Theme Wardrobe.exe'
& (Join-Path $PSScriptRoot 'build-theme-switcher.ps1') -OutputPath $wardrobeExe

if (-not $NoShortcuts) {
  $shell = New-Object -ComObject WScript.Shell
  $desktop = [Environment]::GetFolderPath('Desktop')
  $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  @(
    (Join-Path $desktop 'Codex Dream Skin.lnk'),
    (Join-Path $desktop 'Codex Dream Skin - Restore.lnk'),
    (Join-Path $startMenu 'Codex Dream Skin.lnk')
  ) | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
  foreach ($folder in @($desktop, $startMenu)) {
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $shortcut = $shell.CreateShortcut((Join-Path $folder 'Codex Theme Wardrobe.lnk'))
    $shortcut.TargetPath = $wardrobeExe
    $shortcut.WorkingDirectory = $script:RepositoryRoot
    $shortcut.Description = 'Browse and apply Codex Desktop themes'
    $shortcut.Save()
  }
}

if (-not (Test-Path -LiteralPath $script:ActiveThemePath)) {
  Write-SkinState -Port $Port -InjectorPid 0 -ThemeId 'original' -NodePath $node -CodexExe (Resolve-CodexExecutable -Package $package) -Session 'off'
}
Write-Host "Codex Theme Wardrobe $script:SkinVersion installed at $script:RepositoryRoot"
if (-not $NoLaunch) { Start-Process -FilePath $wardrobeExe | Out-Null }
