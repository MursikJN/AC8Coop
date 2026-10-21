[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GameDirectory,[string]$OutputRoot='', [string]$FlightDll='', [switch]$Menu)
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
$revision=if ($Menu) { 'r8' } else { 'r7' }
if (!$OutputRoot) { $OutputRoot=Join-Path $repo "profiles\ac8-build25201480-$revision" }
if (!$FlightDll) { $FlightDll=Join-Path $repo "build\coop-flight-$revision\ac8_plane_coop_$revision.dll" }
$output=[IO.Path]::GetFullPath($OutputRoot)
if ((Split-Path $output -Parent) -ne (Join-Path $repo 'profiles')) { throw 'OutputRoot must be directly inside profiles.' }
if (Test-Path -LiteralPath $output) { throw 'Profile exists; use a new OutputRoot instead of overwriting a trial.' }
$gameDir=[IO.Path]::GetFullPath($GameDirectory)
$expectedGame='51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F'
if ((Get-FileHash -LiteralPath (Join-Path $gameDir 'AceCombat8.exe')).Hash -ne $expectedGame) { throw 'Unsupported EXE.' }
$package=Join-Path $repo 'packages\ue4ss-3.0.1-1181-g83330635'
if ((Get-FileHash -LiteralPath (Join-Path $package 'dwmapi.dll')).Hash -ne '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB') { throw 'Unexpected proxy.' }
$nativeHash=(Get-FileHash -LiteralPath $FlightDll).Hash
$runtime=Join-Path $output 'runtime';$mod=Join-Path $runtime 'Mods\AC8CoopRecon\Scripts'
New-Item -ItemType Directory -Force -Path $mod | Out-Null
foreach ($name in @('UE4SS.dll','UE4SS-settings.ini','LICENSE')) { Copy-Item -LiteralPath (Join-Path $package ('ue4ss\'+$name)) -Destination $runtime }
Copy-Item -LiteralPath (Join-Path $package 'ue4ss\Mods\shared') -Destination (Join-Path $runtime 'Mods') -Recurse
Copy-Item -LiteralPath $FlightDll -Destination (Join-Path $runtime "ac8_plane_coop_$revision.dll")
foreach ($name in @('main.lua','plane_coop_probe.lua')) { Copy-Item -LiteralPath (Join-Path $repo ('probe\AC8CoopRecon\Scripts\'+$name)) -Destination $mod }
if ($Menu) {
    foreach ($name in @('coop_main_menu.lua','coop_menu_session.lua','coop_menu_services.lua')) { Copy-Item -LiteralPath (Join-Path $repo ('probe\AC8CoopRecon\Scripts\'+$name)) -Destination $mod }
    foreach ($name in @('Start-Menu.ps1','Collect-CoopLogs.ps1')) { Copy-Item -LiteralPath (Join-Path $repo ('coop\'+$name)) -Destination $output }
    [IO.File]::WriteAllText((Join-Path $output 'Start-Coop.cmd'),"@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Start-Menu.ps1`"`r`npause`r`n",[Text.Encoding]::ASCII)
}
[IO.File]::WriteAllText((Join-Path $runtime 'Mods\mods.txt'),"AC8CoopRecon : 1`r`n",[Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $runtime 'Mods\mods.json'),'[{"mod_name":"AC8CoopRecon","mod_enabled":true}]',[Text.Encoding]::ASCII)
foreach ($name in @('Launch-Recon.ps1','Remove-ReconLoader.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $output }
if (!$Menu) {
    foreach ($name in @('Start-Coop.ps1','Review-And-Arm.ps1')) { Copy-Item -LiteralPath (Join-Path $repo ('coop\'+$name)) -Destination $output }
    foreach ($role in @('Host','Guest')) { [IO.File]::WriteAllText((Join-Path $output ('Start-'+$role+'.cmd')),"@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Start-Coop.ps1`" -Role $($role.ToLowerInvariant())`r`npause`r`n",[Text.Encoding]::ASCII) }
    [IO.File]::WriteAllText((Join-Path $output 'Review-And-Arm.cmd'),"@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Review-And-Arm.ps1`"`r`npause`r`n",[Text.Encoding]::ASCII)
}
$files=@(Get-ChildItem -LiteralPath $output -Recurse -File | ForEach-Object { [ordered]@{path=$_.FullName.Substring($output.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
[ordered]@{revision=$revision;native_sha256=$nativeHash;game_sha256=$expectedGame;live_verified=$false;files=$files} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'trial-manifest.json') -Encoding UTF8
New-Item -ItemType Directory -Force -Path (Join-Path $output 'state') | Out-Null
@{game_directory=$gameDir} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'state\launcher-settings.json') -Encoding UTF8
if ($Menu) { & (Join-Path $output 'Start-Menu.ps1') -GameDirectory $gameDir -ValidateOnly }
else { & (Join-Path $output 'Start-Coop.ps1') -Role host -PeerSteamId '76561198000000002' -GameDirectory $gameDir -ValidateOnly }
Write-Output "Prepared $revision profile: $output. No game launch or installation."
