[CmdletBinding()]
param([string]$SessionDirectory)
$ErrorActionPreference='Stop'
if(!$SessionDirectory){
    $latest=Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'evidence') -Directory -Filter 'session-*'|Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'session.json')}|Sort-Object Name -Descending|Select-Object -First 1
    if(!$latest){throw 'No recorded session found.'};$SessionDirectory=$latest.FullName
}
$session=(Resolve-Path -LiteralPath $SessionDirectory).Path
if(!$session.StartsWith(([IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'evidence'))+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'Session is outside this profile evidence directory.'}
$record=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw|ConvertFrom-Json
if($record.role -notin @('host','guest')){throw 'Unknown session role.'}
$expected=if($record.role -eq 'host'){Join-Path $PSScriptRoot 'userdata'}else{Join-Path $session 'guest-userdata'}
if([IO.Path]::GetFullPath($record.user_directory) -ne [IO.Path]::GetFullPath($expected)){throw 'Recorded save directory does not belong to this session role.'}
. (Join-Path $PSScriptRoot 'Session-Diagnostics.ps1')
$output=Join-Path $session 'mod'
Copy-CoopDiagnosticLogs -UserSaved (Join-Path $record.user_directory 'Saved') -Output $output -Since ([DateTime]::Parse($record.started)) -RuntimeLog (Join-Path $PSScriptRoot 'runtime/UE4SS.log') -FallbackSaved (Join-Path $env:LOCALAPPDATA 'BANDAI NAMCO Entertainment/ACE COMBAT 8/Saved')
& (Join-Path $PSScriptRoot 'Collect-CoopLogs.ps1') -SessionDirectory $session -ReportsDirectory (Join-Path $PSScriptRoot 'reports')
