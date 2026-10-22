[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Coop-AdapterEnvironment.ps1')
$checks=0
foreach($role in @('host','guest')){
 $info=New-Object Diagnostics.ProcessStartInfo;$info.UseShellExecute=$false
 foreach($name in @($info.EnvironmentVariables.Keys)){if($name -like 'AC8_*'){$info.EnvironmentVariables.Remove($name)}}
 $info.EnvironmentVariables['AC8_MENU_ROUTE']='wrong';$info.EnvironmentVariables['AC8_MISSION_SYNC']='wrong';$info.EnvironmentVariables['AC8_LOCAL_SCRIPTS']='wrong'
 Set-CoopAdapterEnvironment -Info $info -Root (Join-Path $repo 'build/fixture with spaces')
 foreach($name in @('AC8_MENU_ROUTE','AC8_MISSION_SYNC')){if($info.EnvironmentVariables[$name] -ne '25201480'){throw ('Missing gate for '+$role)};$checks++}
 if($info.EnvironmentVariables['AC8_LOCAL_SCRIPTS'] -ne [IO.Path]::GetFullPath((Join-Path $repo 'build/fixture with spaces/runtime/Mods/AC8CoopRecon/Scripts'))){throw 'Wrong script root'};$checks++
 if($info.EnvironmentVariables.ContainsKey('AC8_COOP_RECON') -or $info.EnvironmentVariables.ContainsKey('AC8_COOP_RECON_EXTENSION')){throw 'Research evaluator gates must not be enabled'};$checks++
 if(@($info.EnvironmentVariables.Keys|Where-Object {$_ -like 'AC8_*'}).Count -ne 3){throw 'Unexpected adapter gates'};$checks++
}
$bad=New-Object Diagnostics.ProcessStartInfo;$bad.UseShellExecute=$true;$refused=$false
try{Set-CoopAdapterEnvironment -Info $bad -Root $repo}catch{$refused=$true}
if(!$refused){throw 'Shell environment should refuse'};$checks++
Write-Output ('PASS: '+$checks+' adapter environment checks; ProcessStartInfo only, no process started.')
