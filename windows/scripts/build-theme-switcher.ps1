[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $windowsRoot 'switcher\ThemeWardrobe.cs'
if (-not $OutputPath) {
  $release = Join-Path $windowsRoot 'release'
  New-Item -ItemType Directory -Force -Path $release | Out-Null
  $OutputPath = Join-Path $release 'Codex Theme Wardrobe.exe'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue

$references = @(
  'System.dll', 'System.Core.dll', 'System.Web.Extensions.dll',
  'WindowsBase.dll', 'PresentationCore.dll', 'PresentationFramework.dll'
)
Add-Type -Path $source -ReferencedAssemblies $references -OutputAssembly $OutputPath -OutputType WindowsApplication
if (-not (Test-Path -LiteralPath $OutputPath)) { throw 'The WPF wardrobe executable was not produced.' }
Write-Host "Created $OutputPath"
