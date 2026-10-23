[CmdletBinding()]
param(
 [string]$KitRoot,
 [string]$ProfileRoot,
 [string]$PrivateRoot='C:/Users/Administrator/.codex/visualizations/2026/10/20/01a1584d-af0f-7d72-8611-ec65cbfc74e4/ac8-research/mission6-runtime',
 [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if(!$KitRoot){$KitRoot=Join-Path $repo 'ac8-steam-coop-r31-compact'}
if(!$ProfileRoot){$ProfileRoot=Join-Path $repo 'profiles/ac8-mission6-capture'}
. (Join-Path $PSScriptRoot 'Coop-Kit.ps1')
$KitRoot=[IO.Path]::GetFullPath($KitRoot);$ProfileRoot=[IO.Path]::GetFullPath($ProfileRoot);$PrivateRoot=[IO.Path]::GetFullPath($PrivateRoot)
foreach($p in @($KitRoot,$ProfileRoot,$PrivateRoot)){Assert-CoopPlainPath $p}
if(!$ProfileRoot.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Capture profile must be inside workspace'}
if($PrivateRoot -eq $repo -or $PrivateRoot.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Raw runtime data must be outside repository'}
$m=Get-Content -LiteralPath (Join-Path $KitRoot 'lobby-manifest.json') -Raw|ConvertFrom-Json
if($m.game_sha256 -ne '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'){throw 'Unsupported build'}
$gameDir=Test-CoopLab -Root $KitRoot -Manifest $m
$marker=Get-Content -LiteralPath (Join-Path $KitRoot 'lab-game/.ac8-coop-lab.json') -Raw|ConvertFrom-Json
foreach($p in @($ProfileRoot,$PrivateRoot)){
 foreach($forbidden in @($marker.source,$marker.destination)){
  $base=[IO.Path]::GetFullPath($forbidden).TrimEnd('\','/')
  if($p -eq $base -or $p.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Capture output overlaps game tree'}
 }
}
if($ValidateOnly){[ordered]@{lab=$gameDir;private_output=$PrivateRoot;game_started=$false;originals_written=$false}|ConvertTo-Json;return}
if(Test-Path -LiteralPath $ProfileRoot){throw 'Profile already exists; preserve it and specify a fresh ProfileRoot'}
$package=Join-Path $repo 'packages/ue4ss-3.0.1-1181-g83330635'
$files=@{
 'runtime/UE4SS.dll'=(Join-Path $package 'ue4ss/UE4SS.dll')
 'runtime/UE4SS-settings.ini'=(Join-Path $package 'ue4ss/UE4SS-settings.ini')
 'runtime/LICENSE'=(Join-Path $package 'ue4ss/LICENSE')
 'loader/dwmapi.dll'=(Join-Path $package 'dwmapi.dll')
 'runtime/Mods/Mission6Capture/Scripts/main.lua'=(Join-Path $repo 'probe/Mission6Capture/Scripts/main.lua')
 'runtime/Mods/Mission6Capture/Scripts/capture.lua'=(Join-Path $repo 'probe/Mission6Capture/Scripts/capture.lua')
 'runtime/Mods/Mission6Capture/Scripts/automation.lua'=(Join-Path $repo 'probe/Mission6Capture/Scripts/automation.lua')
 'runtime/Mods/Mission6Capture/Scripts/baxter.lua'=(Join-Path $repo 'probe/Mission6Capture/Scripts/baxter.lua')
 'runtime/Mods/Mission6Capture/Scripts/orders.lua'=(Join-Path $repo 'probe/Mission6Capture/Scripts/orders.lua')
 'Start-Mission6Capture.ps1'=(Join-Path $PSScriptRoot 'Start-Mission6Capture.ps1')
 'Coop-Kit.ps1'=(Join-Path $PSScriptRoot 'Coop-Kit.ps1')
 'Coop-LabStorage.ps1'=(Join-Path $PSScriptRoot 'Coop-LabStorage.ps1')
 'READ-ME-RU.md'=(Join-Path $repo 'docs/research/mission6-capture-guide-20261023.md')
}
foreach($p in $files.Values){if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw ('Missing dependency: '+$p)}}
New-Item -ItemType Directory -Path $ProfileRoot|Out-Null
foreach($rel in $files.Keys){$target=Join-Path $ProfileRoot $rel;New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)|Out-Null;Copy-Item -LiteralPath $files[$rel] -Destination $target}
[IO.File]::WriteAllText((Join-Path $ProfileRoot 'runtime/Mods/mods.txt'),"Mission6Capture : 1`r`n",[Text.Encoding]::ASCII)
$cmd='@echo off'+"`r`n"+'cd /d "%~dp0"'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Mission6Capture.ps1" -Launch'+"`r`n"+'pause'+"`r`n"
[IO.File]::WriteAllText((Join-Path $ProfileRoot 'Start-Mission6Capture.cmd'),$cmd,[Text.Encoding]::ASCII)
$manifestFiles=@(Get-ChildItem -LiteralPath $ProfileRoot -Recurse -File|ForEach-Object {[ordered]@{path=$_.FullName.Substring($ProfileRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
[ordered]@{format='ac8-mission6-capture-v1';build=25201480;kit_root=$KitRoot;private_root=$PrivateRoot;game_sha256=$m.game_sha256;steam_sha256=$m.steam_sha256;files=$manifestFiles;game_started=$false;originals_written=$false;runtime_verified=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $ProfileRoot 'capture-profile.json') -Encoding UTF8
Write-Output ('Prepared only: '+$ProfileRoot)
