[CmdletBinding()]
param([string]$GameDirectory = 'D:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64')
$ErrorActionPreference = 'Stop'
$target = Join-Path ([IO.Path]::GetFullPath($GameDirectory)) 'dwmapi.dll'
if (Get-Process -Name AceCombat8,start_protected_game -ErrorAction SilentlyContinue) { throw 'Close AC8 and its launcher first.' }
if (!(Test-Path -LiteralPath $target)) { Write-Output 'No research loader installed.'; return }
if ((Get-FileHash -LiteralPath $target).Hash -ne '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB') { throw 'Unknown DLL: refusing to delete it.' }
Remove-Item -LiteralPath $target
Write-Output 'Research loader removed; game launcher was not changed.'
