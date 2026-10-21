[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$session=Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'evidence') -Directory -Filter 'session-*'|Sort-Object Name -Descending|Select-Object -First 1
if (!$session) { throw 'No diagnostic session found.' }
$runtimeLog=Join-Path $PSScriptRoot 'runtime\UE4SS.log'
if (Test-Path -LiteralPath $runtimeLog) { Copy-Item -LiteralPath $runtimeLog -Destination (Join-Path $session.FullName 'UE4SS.log') }
$reports=Join-Path $PSScriptRoot 'reports';New-Item -ItemType Directory -Force -Path $reports|Out-Null
$report=Join-Path $reports ($session.Name+'-native-'+(Get-Date -Format 'HHmmss')+'.zip')
Compress-Archive -LiteralPath $session.FullName -DestinationPath $report
Write-Output "Native connection report: $report"
