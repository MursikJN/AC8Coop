# Offline tests only: fake save directories and restart records, no processes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Session-Policy.ps1')
$repo=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path $repo ('build/session-policy-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force|Out-Null
$script:checks=0
function Assert-Policy([bool]$Condition,[string]$Why){$script:checks++;if(!$Condition){throw $Why}}
function Assert-Rejected([scriptblock]$Action){$threw=$false;try{& $Action|Out-Null}catch{$threw=$true};Assert-Policy $threw 'Invalid restart was accepted'}
function New-TestRun([string]$Role='host'){
 $session=Join-Path $scratch ('evidence/session-'+[Guid]::NewGuid().ToString('N'));$mod=Join-Path $session 'mod';New-Item -ItemType Directory -Path $mod -Force|Out-Null
 $hostId=if($Role -eq 'host'){'76561198000000001'}else{'76561198000000002'}
 $ticket="format`tac8-restart-r29`nconfig_token`t12345678901`nrole`t$Role`nhost_id`t$hostId`nmission`t6`ndifficulty`t1`nrestart_id`t1`nepoch`t8`nrevision`t5`nsealed`t1`ncreated_unix`t$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())`n"
 $status="format`tac8-session-status-v3`r`nprotocol`t7`r`nsession_policy`t1`r`nconfig_token`t12345678901`r`nrole`t$Role`r`nmission`t6`r`ndifficulty`t1`r`nrestart_id`t1`r`nepoch`t8`r`nrevision`t5`r`nphase`t10`r`nrestart_ack`t2`r`nself`t76561198000000001`r`npeer`t76561198000000002`r`n"
 $t=Join-Path $mod 'session-restart.tsv';$s=Join-Path $mod 'shared-session-status.tsv'
 [IO.File]::WriteAllText($t,$ticket);[IO.File]::WriteAllText($s,$status)
 return [pscustomobject]@{Session=$session;Ticket=$t;Status=$s}
}
$run=New-TestRun
$plan=Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role host -ExitCode 0
Assert-Policy ($plan.HostId -eq '76561198000000001') 'Wrong restart host'
Assert-Policy (Test-Path -LiteralPath ($run.Ticket+'.consumed')) 'Restart ticket not consumed'
Assert-Policy ($null -eq (Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role host -ExitCode 0)) 'Restart replay'
$run=New-TestRun guest
Assert-Policy ((Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role guest -ExitCode 0).HostId -eq '76561198000000002') 'Guest used its own SteamID as host'
$run=New-TestRun
Assert-Policy ($null -eq (Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role host -ExitCode 1)) 'Crash triggered relaunch'
foreach($edit in @(@('phase','10','8'),@('restart_ack','2','0'),@('protocol','7','6'),@('config_token','12345678901','999'),@('epoch','8','7'))){
 $run=New-TestRun
 $text=[IO.File]::ReadAllText($run.Status).Replace(($edit[0]+"`t"+$edit[1]+"`r`n"),($edit[0]+"`t"+$edit[2]+"`r`n"));[IO.File]::WriteAllText($run.Status,$text)
 Assert-Rejected {Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role host -ExitCode 0}
}
$run=New-TestRun
Assert-Rejected {Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role guest -ExitCode 0}
Assert-Rejected {Get-CoopRestartPlan -Root $scratch -Session (Split-Path $scratch -Parent) -Role host -ExitCode 0}
Assert-Rejected {ConvertFrom-CoopPolicyTsv "format`ta`nformat`tb`n"}
$a=New-TestRun guest;$b=New-TestRun guest
$guestA=Get-CoopUserDirectory -Root $scratch -Session $a.Session -Role guest
$guestB=Get-CoopUserDirectory -Root $scratch -Session $b.Session -Role guest
$hostA=Get-CoopUserDirectory -Root $scratch -Session $a.Session -Role host
$hostB=Get-CoopUserDirectory -Root $scratch -Session $b.Session -Role host
Assert-Policy ($guestA -ne $guestB -and $hostA -eq $hostB -and $guestA -ne $hostA) 'Guest progress was reused or host progress lost'
$personal=Join-Path $scratch 'personal/Saved/SaveGames';New-Item -ItemType Directory -Force -Path $personal|Out-Null
[IO.File]::WriteAllText((Join-Path $personal 'slot.sav'),'original')
foreach($dest in @($guestA,$guestB,$hostA)){New-Item -ItemType Directory -Force -Path (Join-Path $dest 'Saved')|Out-Null;Copy-Item -LiteralPath $personal -Destination (Join-Path $dest 'Saved/SaveGames') -Recurse}
[IO.File]::WriteAllText((Join-Path $guestA 'Saved/SaveGames/slot.sav'),'guest progress')
[IO.File]::WriteAllText((Join-Path $hostA 'Saved/SaveGames/slot.sav'),'host progress')
Assert-Policy ([IO.File]::ReadAllText((Join-Path $personal 'slot.sav')) -eq 'original') 'Guest overwrote personal save'
Assert-Policy ([IO.File]::ReadAllText((Join-Path $guestB 'Saved/SaveGames/slot.sav')) -eq 'original') 'Guest progress leaked into next run'
Assert-Policy ([IO.File]::ReadAllText((Join-Path $hostB 'Saved/SaveGames/slot.sav')) -eq 'host progress') 'Host save did not persist'
foreach($name in @('Start-SteamLobby.ps1','Session-Policy.ps1')){
 $tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)|Out-Null
 Assert-Policy ($errors.Count -eq 0) ('PowerShell syntax: '+$name)
}
Write-Output ($script:checks.ToString()+' save isolation, restart ticket and launcher syntax checks passed; game not launched')
$run=New-TestRun
[IO.File]::WriteAllText($run.Status,[IO.File]::ReadAllText($run.Status).Replace("protocol`t7","protocol`t8"))
Assert-Rejected {Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role host -ExitCode 0}
Assert-Policy ((Get-CoopRestartPlan -Root $scratch -Session $run.Session -Role host -ExitCode 0 -ExpectedProtocol 8).HostId -eq '76561198000000001') 'R31 restart protocol 8 rejected'
Write-Output ($script:checks.ToString()+' total policy checks including protocol 8; no game launched')
