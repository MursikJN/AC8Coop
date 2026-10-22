[CmdletBinding()]
param([string]$Kit='')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$Kit){$Kit=Join-Path $repo 'profiles/ac8-steam-coop-r31'}
. (Join-Path $PSScriptRoot 'Coop-Kit.ps1')
$script:checks=0
function Assert-Kit([bool]$Ok,[string]$Why){$script:checks++;if(!$Ok){throw $Why}}
function Reject-Kit([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert-Kit $failed 'Expected refusal did not occur'}
$actual=Test-CoopKit $Kit;Assert-Kit ($actual.protocol -eq 8 -and $actual.pilot_protocol -eq 3) 'Wrong packet versions'
$scratch=Join-Path $repo ('build/r31-kit-fixture-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $scratch|Out-Null
$fixture=Join-Path $scratch 'kit';Copy-Item -LiteralPath $Kit -Destination $fixture -Recurse
$source=Join-Path $scratch 'source';$sourceBin=Join-Path $source 'Game/Binaries/Win64';$sourceSteam=Join-Path $source 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64'
foreach($dir in @($sourceBin,$sourceSteam,(Join-Path $source 'Game/Content/Paks'))){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
[IO.File]::WriteAllText((Join-Path $sourceBin 'AceCombat8.exe'),'FIXTURE ONLY, NOT AN EXECUTABLE')
[IO.File]::WriteAllText((Join-Path $sourceSteam 'steam_api64.dll'),'FIXTURE STEAM, NEVER LOADED')
[IO.File]::WriteAllText((Join-Path $source 'Game/Content/Paks/test.pak'),'FIXTURE RESOURCE')
$manifestPath=Join-Path $fixture 'lobby-manifest.json';$m=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$m.game_sha256=(Get-FileHash (Join-Path $sourceBin 'AceCombat8.exe')).Hash;$m.steam_sha256=(Get-FileHash (Join-Path $sourceSteam 'steam_api64.dll')).Hash
$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath -Encoding UTF8
$before=@(Get-ChildItem -LiteralPath $source -Recurse -File|ForEach-Object {(Get-FileHash $_.FullName).Hash}) -join '|'
& (Join-Path $fixture 'Prepare-CoopLab.ps1') -SourceGameDirectory $source -StorageMode Full|Out-Null
$bin=Test-CoopLab -Root $fixture -Manifest $m
Assert-Kit ($bin -eq (Join-Path $fixture 'lab-game/Game/Binaries/Win64')) 'Lab path mismatch'
$after=@(Get-ChildItem -LiteralPath $source -Recurse -File|ForEach-Object {(Get-FileHash $_.FullName).Hash}) -join '|'
Assert-Kit ($before -eq $after) 'Original fixture changed during copy'
Assert-Kit ([IO.File]::ReadAllText((Join-Path $fixture 'lab-game/Game/Content/Paks/test.pak')) -eq 'FIXTURE RESOURCE') 'Resource not copied'
Reject-Kit {Test-CoopLab -Root $fixture -Manifest $m -GameDirectory $sourceBin}
$markerPath=Join-Path $fixture 'lab-game/.ac8-coop-lab.json';$marker=[IO.File]::ReadAllText($markerPath);[IO.File]::WriteAllText($markerPath,$marker.Replace('complete','copying'))
Reject-Kit {Test-CoopLab -Root $fixture -Manifest $m};[IO.File]::WriteAllText($markerPath,$marker)
$file=Join-Path $bin 'AceCombat8.exe';[IO.File]::WriteAllText($file,'TAMPERED');Reject-Kit {Test-CoopLab -Root $fixture -Manifest $m};Copy-Item -LiteralPath (Join-Path $sourceBin 'AceCombat8.exe') -Destination $file -Force
$lua=Join-Path $fixture 'runtime/Mods/AC8CoopRecon/Scripts/guest_owner_preparation.lua';$original=[IO.File]::ReadAllBytes($lua);[IO.File]::AppendAllText($lua,'tamper');Reject-Kit {Test-CoopKit $fixture};[IO.File]::WriteAllBytes($lua,$original)
Assert-Kit ((Test-CoopKit $fixture).owner_native) 'Untampered kit not accepted'
$m.owner_world_readiness=0;$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath -Encoding UTF8
Reject-Kit {Test-CoopKit $fixture}
$m.owner_world_readiness=1;$m.kit_update='old-r31';$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath -Encoding UTF8
Reject-Kit {Test-CoopKit $fixture}
$m.kit_update='adapters-1'
$m.owner_native=$false;$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath -Encoding UTF8
Reject-Kit {& (Join-Path $fixture 'Start-SteamLobby.ps1') -ValidateOnly -Role host}
$m.owner_native=$true;$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $manifestPath -Encoding UTF8
& (Join-Path $fixture 'Start-SteamLobby.ps1') -ValidateOnly -Role host|Out-Null
Assert-Kit (!(Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll'))) 'Validation installed loader'
Assert-Kit (!(Test-Path -LiteralPath (Join-Path $fixture 'evidence'))) 'Validation created a game session'
Reject-Kit {& (Join-Path $fixture 'Start-SteamLobby.ps1') -ValidateOnly -Role host -GameDirectory $sourceBin}
Assert-Kit (@(Get-ChildItem (Join-Path $fixture 'reports') -Filter 'launch-failure-*.json').Count -gt 0) 'Refused launch did not save failure report'
$m.files=@($m.files|Where-Object {$_.path -ne 'runtime/Mods/AC8CoopRecon/Scripts/guest_owner_preparation.lua'});$m|ConvertTo-Json -Depth 8|Set-Content $manifestPath -Encoding UTF8
Reject-Kit {Test-CoopKit $fixture}
$scriptNames=@(Get-ChildItem -LiteralPath $Kit -Filter '*.ps1' -File)
foreach($script in $scriptNames){$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)|Out-Null;Assert-Kit (!$errors.Count) ('Syntax: '+$script.Name)}
Write-Output ("PASS: $script:checks R31 kit, clone, refusal and read-only checks; only fake game bytes copied, no game launched. Fixture: $scratch")
