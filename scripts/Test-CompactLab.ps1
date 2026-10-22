[CmdletBinding()]
param([string]$Kit='')
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
if(!$Kit){$Kit=Join-Path $repo 'profiles/ac8-steam-coop-r31'}
. (Join-Path $PSScriptRoot 'Coop-Kit.ps1')
. (Join-Path $PSScriptRoot 'Repair-CompactLab.ps1')
$script:checks=0
function Check([bool]$Ok,[string]$Why){$script:checks++;if(!$Ok){throw $Why}}
function Refuse([scriptblock]$Action,[string]$Pattern=''){
 $errorFound=$null;try{& $Action|Out-Null}catch{$errorFound=$_}
 Check ([bool]$errorFound) 'Expected refusal did not occur'
 if($Pattern){Check ($errorFound.Exception.Message -like ('*'+$Pattern+'*')) ('Wrong refusal: '+$errorFound.Exception.Message)}
}
$scratch=Join-Path $repo ('build/compact2-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
$fixture=Join-Path $scratch 'kit';Copy-Item -LiteralPath $Kit -Destination $fixture -Recurse
$source=Join-Path $scratch 'source with spaces';$sourceBin=Join-Path $source 'Game/Binaries/Win64';$sourceSteam=Join-Path $source 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64';$paks=Join-Path $source 'Game/Content/Paks'
foreach($d in @($sourceBin,$sourceSteam,$paks)){New-Item -ItemType Directory -Force -Path $d|Out-Null}
[IO.File]::WriteAllText((Join-Path $sourceBin 'AceCombat8.exe'),'FAKE GAME, NEVER EXECUTED')
[IO.File]::WriteAllText((Join-Path $sourceSteam 'steam_api64.dll'),'FAKE STEAM, NEVER LOADED')
foreach($ext in @('pak','utoc','ucas','sig')){[IO.File]::WriteAllText((Join-Path $paks ('fixture.'+$ext)),('fixture bytes '+$ext))}
[IO.File]::WriteAllText((Join-Path $source 'ordinary.txt'),'ordinary independently copied file')
function Source-Snapshot {return (@(Get-ChildItem -LiteralPath $source -Recurse -File|Sort-Object FullName|ForEach-Object {$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash+'|'+$_.LastWriteTimeUtc.Ticks+'|'+[int]$_.Attributes+'|'+(Get-Acl -LiteralPath $_.FullName).Sddl}) -join "`n")}
$before=Source-Snapshot
$mp=Join-Path $fixture 'lobby-manifest.json';$m=Get-Content -LiteralPath $mp -Raw|ConvertFrom-Json
$m.game_sha256=(Get-FileHash -LiteralPath (Join-Path $sourceBin 'AceCombat8.exe')).Hash;$m.steam_sha256=(Get-FileHash -LiteralPath $sourceSteam/steam_api64.dll).Hash
$m|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $mp -Encoding UTF8
$plan=(& (Join-Path $fixture 'Prepare-CoopLab.ps1') -SourceGameDirectory $source -PlanOnly)|ConvertFrom-Json
Check ($plan.archive_count -eq 4 -and $plan.copy_bytes -lt $plan.source_bytes) 'Wrong compact plan'
Check (!(Test-Path -LiteralPath (Join-Path $fixture 'lab-game'))) 'PlanOnly wrote lab'
& (Join-Path $fixture 'Prepare-CoopLab.ps1') -SourceGameDirectory $source|Out-Null
$bin=Test-CoopLab -Root $fixture -Manifest $m
$markerPath=Join-Path $fixture 'lab-game/.ac8-coop-lab.json';$markerText=[IO.File]::ReadAllText($markerPath);$marker=$markerText|ConvertFrom-Json
Check ($marker.format -eq 'ac8-isolated-lab-v3' -and $marker.archive_layout -eq 'paks-junction-v1' -and $marker.archives.Count -eq 4) 'Wrong storage marker'
Check ((Source-Snapshot) -eq $before) 'Preparation changed original bytes/attributes/ACL/time'
$labPaks=Join-Path $fixture 'lab-game/Game/Content/Paks';$linked=Join-Path $labPaks 'fixture.pak';$original=Join-Path $paks 'fixture.pak'
Check ((Get-Item -LiteralPath $labPaks -Force).LinkType -eq 'Junction') 'Missing Paks junction'
foreach($entry in $marker.archives){Check ([Ac8CompactFiles]::MetadataSize((Join-Path (Join-Path $fixture 'lab-game') $entry.path)) -eq $entry.bytes) 'Win32 metadata regression'}
Check ([IO.File]::ReadAllText($linked) -eq [IO.File]::ReadAllText($original)) 'Cannot read shared bytes'
[IO.File]::WriteAllText((Join-Path $fixture 'lab-game/ordinary.txt'),'local writable copy')
Check ([IO.File]::ReadAllText((Join-Path $source 'ordinary.txt')) -eq 'ordinary independently copied file') 'Copied-file write reached original'
$guard=$null
try{
 $null=Test-CoopLab -Root $fixture -Manifest $m -ArchiveGuard ([ref]$guard)
 Check ($guard.ArchiveCount -eq 4 -and $guard.Streams.Count -eq 8 -and $guard.Directories.Count -eq 3) 'Guard did not retain handles'
 foreach($path in @($original,$linked)){Refuse {$f=[IO.File]::Open($path,'Open','Write','ReadWrite');$f.Dispose()}}
 Refuse {[IO.File]::Delete($original)}
 Refuse {[IO.Directory]::Delete($labPaks)}
 Refuse {[IO.Directory]::Move($paks,($paks+'-moved'))}
 $f=[IO.File]::Open($original,'Open','Read','ReadWrite');$f.Dispose();Check $true 'Compatible read failed'
 Check ([Ac8CompactFiles]::MetadataSize($linked) -eq (Get-Item -LiteralPath $original).Length) 'Guard blocked metadata'
}finally{Close-CoopArchiveGuard $guard}
$f=[IO.File]::Open($original,'Open','Write','ReadWrite');$f.Dispose();Check $true 'Guard failed to release'
Check ((Source-Snapshot) -eq $before) 'Guard changed original bytes/attributes/ACL/time'
& (Join-Path $fixture 'Start-SteamLobby.ps1') -ValidateOnly -Role host|Out-Null
& (Join-Path $fixture 'Start-SteamLobby.ps1') -ValidateOnly -Role guest|Out-Null
Check (!(Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll'))) 'Validation installed loader'
Check (!(Test-Path -LiteralPath (Join-Path $fixture 'evidence'))) 'Validation created session'
# All following writes/deletes concern artificial fixtures only.
$foreign=Join-Path $scratch 'foreign';New-Item -ItemType Directory -Path $foreign|Out-Null
[IO.Directory]::Delete($labPaks);New-CoopPaksJunction -Link $labPaks -Original $foreign
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'target mismatch'
[IO.Directory]::Delete($labPaks);New-CoopPaksJunction -Link $labPaks -Original $paks
$f=[IO.File]::Open($original,'Open','Write','ReadWrite');$f.Dispose();Check $true 'Target refusal leaked handles'
$extra=Join-Path $paks 'unexpected.txt';[IO.File]::WriteAllText($extra,'not allowed')
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Unexpected source Paks file'
[IO.File]::Delete($extra)
$unexpected=Join-Path $fixture 'lab-game/Game/Content/unexpected';New-CoopPaksJunction -Link $unexpected -Original $paks
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Unexpected link'
[IO.Directory]::Delete($unexpected)
$exe=Join-Path $bin 'AceCombat8.exe';[IO.File]::Delete($exe);New-Item -ItemType HardLink -Path $exe -Value (Join-Path $sourceBin 'AceCombat8.exe')|Out-Null
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Hardlink'
[IO.File]::Delete($exe);Copy-Item -LiteralPath (Join-Path $sourceBin 'AceCombat8.exe') -Destination $exe
$bad=$markerText|ConvertFrom-Json;$bad.archives[0].path='../../escape.pak';$bad|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $markerPath -Encoding UTF8
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'archive entry'
[IO.File]::WriteAllText($markerPath,$markerText)
$renamed=Join-Path $paks 'absent.pak';[IO.File]::Move($original,$renamed)
Refuse {Test-CoopLab -Root $fixture -Manifest $m}
[IO.File]::Move($renamed,$original)
# Reconstruct old zero-size file links, then test rollback and repair.
[IO.Directory]::Delete($labPaks);New-Item -ItemType Directory -Path $labPaks|Out-Null
foreach($entry in $marker.archives){New-Item -ItemType SymbolicLink -Path (Join-Path (Join-Path $fixture 'lab-game') $entry.path) -Value (Join-Path $source $entry.path)|Out-Null}
$legacy=$markerText|ConvertFrom-Json;$legacy.format='ac8-isolated-lab-v2';$legacy.directory_links_used=$false;$legacy.PSObject.Properties.Remove('archive_layout')
$legacy|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $markerPath -Encoding UTF8
Check ((Get-Item -LiteralPath $linked).Length -eq 0) 'Legacy fixture should have zero metadata size'
Refuse {Test-CoopLab -Root $fixture -Manifest $m} 'Repair-Lab.cmd'
$maker=${function:New-CoopPaksJunction}
try{
 function New-CoopPaksJunction {throw 'Injected junction failure'}
 Refuse {Repair-CoopCompactLab -Root $fixture -Manifest $m} 'Injected junction failure'
}finally{Set-Item -Path Function:New-CoopPaksJunction -Value $maker}
Check ((Get-Item -LiteralPath $linked).LinkType -eq 'SymbolicLink') 'Repair rollback lost legacy links'
Check ((Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json).format -eq 'ac8-isolated-lab-v2') 'Repair rollback lost marker'
& (Join-Path $fixture 'Prepare-CoopLab.ps1') -UpgradeCompact|Out-Null
Check ((Get-Item -LiteralPath $labPaks).LinkType -eq 'Junction') 'Repair did not create junction'
Check ([Ac8CompactFiles]::MetadataSize($linked) -eq (Get-Item -LiteralPath $original).Length) 'Repair did not fix metadata'
Check ([IO.File]::ReadAllText((Join-Path $fixture 'lab-game/ordinary.txt')) -eq 'local writable copy') 'Repair replaced ordinary files'
Check ((Source-Snapshot) -eq $before) 'Repair changed source'
& (Join-Path $fixture 'Prepare-CoopLab.ps1') -UpgradeCompact|Out-Null;Check $true 'Repair not idempotent'
Write-Output ('PASS: '+$script:checks+' compact-2 checks; fixtures only; game never launched; originals unchanged.')
