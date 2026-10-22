# Pure filesystem policy helpers. Dot-sourcing this file never starts a game.
function Get-CoopUserDirectory {
 param([string]$Root,[string]$Session,[ValidateSet('host','guest')][string]$Role)
 if($Role -eq 'host'){return [IO.Path]::GetFullPath((Join-Path $Root 'userdata'))}
 $prefix=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@([char]92,[char]47))+[IO.Path]::DirectorySeparatorChar+'evidence'+[IO.Path]::DirectorySeparatorChar
 if(![IO.Path]::GetFullPath($Session).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Guest session is outside this profile'}
 return [IO.Path]::GetFullPath((Join-Path $Session 'guest-userdata'))
}
function ConvertFrom-CoopPolicyTsv {
 param([string]$Text,[int]$Limit=8192)
 if(!$Text -or $Text.Length -gt $Limit -or $Text.Contains([char]0)){throw 'Invalid policy record size'}
 $result=@{}
 foreach($line in $Text.TrimEnd("`n").Split("`n")){
  $pair=$line.TrimEnd([char]13).Split("`t");if($pair.Count -ne 2 -or $result.ContainsKey($pair[0])){throw 'Invalid policy record fields'}
  $result[$pair[0]]=$pair[1]
 }
 return $result
}
function Get-CoopRestartPlan {
 param([string]$Root,[string]$Session,[string]$Role,[int]$ExitCode,[ValidateSet(7,8)][int]$ExpectedProtocol=7)
 if($ExitCode -ne 0){return $null}
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]@([char]92,[char]47))
 $sessionPath=[IO.Path]::GetFullPath($Session)
 if(!$sessionPath.StartsWith($rootPath+[IO.Path]::DirectorySeparatorChar+'evidence'+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Restart record is outside this profile'}
 $ticket=Join-Path $sessionPath 'mod/session-restart.tsv'
 if(!(Test-Path -LiteralPath $ticket)){return $null}
 if((Get-Item -LiteralPath $ticket).Length -gt 2048){throw 'Oversized restart ticket'}
 $t=ConvertFrom-CoopPolicyTsv ([IO.File]::ReadAllText($ticket)) 2048
 $keys=@('format','config_token','role','host_id','mission','difficulty','restart_id','epoch','revision','sealed','created_unix')
 if($t.Count -ne $keys.Count){throw 'Unexpected restart fields'}
 foreach($key in $keys){if(!$t.ContainsKey($key)){throw 'Missing restart field'}}
 if($t.format -ne 'ac8-restart-r29' -or $t.role -ne $Role -or $t.sealed -ne '1' -or $t.mission -ne '6' -or $t.difficulty -ne '1' -or $t.host_id -notmatch '^[1-9][0-9]{16}$'){throw 'Restart policy mismatch'}
 foreach($key in @('config_token','restart_id','epoch','revision','created_unix')){if($t[$key] -notmatch '^[1-9][0-9]{0,15}$'){throw 'Invalid restart identity'}}
 if([Math]::Abs([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$t.created_unix) -gt 120){throw 'Expired restart ticket'}
 $status=Join-Path $sessionPath 'mod/shared-session-status.tsv';if((Get-Item -LiteralPath $status).Length -gt 8192){throw 'Oversized status'}
 $s=ConvertFrom-CoopPolicyTsv ([IO.File]::ReadAllText($status))
 if($s.format -ne 'ac8-session-status-v3' -or $s.protocol -ne [string]$ExpectedProtocol -or $s.session_policy -ne '1' -or $s.phase -ne '10' -or $s.restart_ack -ne '2' -or $s.role -ne $Role){throw 'Restart not confirmed by the native session'}
 foreach($key in @('config_token','restart_id','epoch','revision','mission','difficulty')){if($t[$key] -ne $s[$key]){throw 'Stale restart ticket'}}
 $hostId=if($Role -eq 'host'){$s.self}else{$s.peer};if($hostId -ne $t.host_id){throw 'Restart host mismatch'}
 [IO.File]::Move($ticket,$ticket+'.consumed')
 return [pscustomobject]@{HostId=$t.host_id;RestartId=$t.restart_id}
}
