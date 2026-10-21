[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GameDirectory,[string]$OutputRoot='', [string]$MenuRouteDll='', [switch]$Continuous)
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
$revision=if ($Continuous) { 'r10' } else { 'r9' }
if (!$OutputRoot) { $OutputRoot=Join-Path $repo ('profiles\ac8-build25201480-'+$revision) }
if (!$MenuRouteDll) { $MenuRouteDll=Join-Path $repo 'build\menu-route-r9\ac8_menu_route_r9.dll' }
$output=[IO.Path]::GetFullPath($OutputRoot)
if ((Split-Path $output -Parent) -ne (Join-Path $repo 'profiles')) { throw 'OutputRoot must be directly inside profiles.' }
if (Test-Path -LiteralPath $output) { throw 'Profile already exists; choose a new output.' }
$base=Join-Path $repo 'profiles\ac8-build25201480-r8'
$manifest=Get-Content (Join-Path $base 'trial-manifest.json') -Raw|ConvertFrom-Json
if ($manifest.revision -ne 'r8') { throw 'Expected accepted r8 base.' }
foreach ($entry in $manifest.files) {
    $source=Join-Path $base $entry.path
    if ((Get-FileHash -LiteralPath $source).Hash -ne $entry.sha256) { throw "Base file changed: $($entry.path)" }
    $dest=Join-Path $output $entry.path
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    Copy-Item -LiteralPath $source -Destination $dest
}
$mod=Join-Path $output 'runtime\Mods\AC8CoopRecon\Scripts'
foreach ($name in @('main.lua','coop_main_menu.lua','coop_menu_session.lua','coop_menu_services.lua','coop_lobby_session.lua','coop_lobby_services.lua','coop_lobby_route.lua','plane_coop_probe.lua')) {
    Copy-Item -LiteralPath (Join-Path $repo ('probe\AC8CoopRecon\Scripts\'+$name)) -Destination $mod
}
$lobby=Join-Path $repo 'build\coop-lobby-r9\ac8_coop_lobby_r9.dll'
Copy-Item -LiteralPath $lobby -Destination (Join-Path $output 'runtime\ac8_coop_lobby_r9.dll')
Copy-Item -LiteralPath $MenuRouteDll -Destination (Join-Path $output 'runtime\ac8_menu_route_r9.dll')
foreach ($name in @('Launch-Recon.ps1','Remove-ReconLoader.ps1')) { Copy-Item (Join-Path $PSScriptRoot $name) $output }
foreach ($name in @('Start-Menu.ps1','Collect-CoopLogs.ps1')) { Copy-Item (Join-Path $repo ('coop\'+$name)) $output }
if ($Continuous) {
    Remove-Item -LiteralPath (Join-Path $output 'runtime\ac8_plane_coop_r8.dll')
    $flight=Join-Path $repo 'build\coop-flight-r10\ac8_plane_coop_r10.dll'
    Copy-Item -LiteralPath $flight -Destination (Join-Path $output 'runtime\ac8_plane_coop_r10.dll')
    $manifest.native_sha256=(Get-FileHash -LiteralPath $flight).Hash
}
$files=@(Get-ChildItem $output -Recurse -File|ForEach-Object { [ordered]@{path=$_.FullName.Substring($output.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
[ordered]@{revision=$revision;native_sha256=$manifest.native_sha256;game_sha256=$manifest.game_sha256;lobby_sha256=(Get-FileHash $lobby).Hash;menu_route_sha256=(Get-FileHash $MenuRouteDll).Hash;live_verified=$false;files=$files}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $output 'trial-manifest.json') -Encoding UTF8
New-Item -ItemType Directory -Force -Path (Join-Path $output 'state')|Out-Null
@{game_directory=[IO.Path]::GetFullPath($GameDirectory)}|ConvertTo-Json|Set-Content (Join-Path $output 'state\launcher-settings.json') -Encoding UTF8
& (Join-Path $output 'Start-Menu.ps1') -GameDirectory $GameDirectory -ValidateOnly
Write-Output "Prepared r9 common-lobby profile: $output"
