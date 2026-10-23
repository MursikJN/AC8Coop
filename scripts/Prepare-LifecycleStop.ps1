[CmdletBinding()]
param([string]$OutputRoot,[string]$UE4SSRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $repo 'profiles/ac8-lifecycle-stop-v4'
if($OutputRoot){$profile=[IO.Path]::GetFullPath($OutputRoot)}
$ue=Join-Path $repo 'packages/ue4ss-3.0.1-1181-g83330635'
if($UE4SSRoot){$ue=[IO.Path]::GetFullPath($UE4SSRoot)}
foreach($file in @("$ue/ue4ss/UE4SS.dll","$ue/ue4ss/UE4SS-settings.ini","$ue/ue4ss/Mods/shared/UEHelpers/UEHelpers.lua","$repo/build/lifecycle-lab/ac8_lifecycle_lab.dll","$repo/build/lifecycle-disconnect-pause/ac8_mission_pause_r26.dll")){
 if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "Required build or dependency missing: $file"}
}
if(Test-Path $profile){throw 'Profile exists; preserve previous test evidence'}
$scripts=Join-Path $profile 'runtime/Mods/LifecycleLab/Scripts'
New-Item -ItemType Directory -Path $scripts -Force|Out-Null
Copy-Item "$ue/ue4ss/UE4SS.dll","$ue/ue4ss/UE4SS-settings.ini","$repo/build/lifecycle-lab/ac8_lifecycle_lab.dll" "$profile/runtime"
[IO.File]::WriteAllText("$profile/runtime/Mods/mods.txt","LifecycleLab : 1`r`n")
Copy-Item "$repo/probe/LifecycleLab/Scripts/*.lua" $scripts
Copy-Item "$repo/probe/AC8CoopRecon/Scripts/mission_sync_pause.lua" $scripts
Copy-Item "$repo/build/lifecycle-disconnect-pause/ac8_mission_pause_r26.dll" "$profile/runtime"
New-Item -ItemType Directory -Path "$profile/runtime/Mods/shared" -Force|Out-Null
Copy-Item "$ue/ue4ss/Mods/shared/UEHelpers" "$profile/runtime/Mods/shared" -Recurse
$manifest=@(Get-ChildItem "$profile/runtime" -File -Recurse|ForEach-Object {
 [ordered]@{path=$_.FullName.Substring($profile.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
})
$manifest|ConvertTo-Json|Set-Content "$profile/profile-manifest.json" -Encoding UTF8
Write-Output $profile
