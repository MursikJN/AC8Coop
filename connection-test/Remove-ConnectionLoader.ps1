[CmdletBinding()]
param([string]$GameDirectory)

$ErrorActionPreference = 'Stop'
$expectedProxy = '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'
$stateDirectory = Join-Path $PSScriptRoot 'state'
if (!$GameDirectory) { $GameDirectory = Read-Host 'Полный путь к папке ACE COMBAT 8, где запускался тест' }
if ([string]::IsNullOrWhiteSpace($GameDirectory)) { throw 'Папка игры не указана.' }
$full = [IO.Path]::GetFullPath($GameDirectory.Trim().Trim('"'))
if ([IO.File]::Exists($full) -and [IO.Path]::GetFileName($full) -ieq 'AceCombat8.exe') { $full = Split-Path $full -Parent }
$gameDir = $null
foreach ($relative in @('', 'Game\Binaries\Win64', 'Binaries\Win64')) {
    $candidate = if ($relative) { Join-Path $full $relative } else { $full }
    if ([IO.File]::Exists((Join-Path $candidate 'AceCombat8.exe'))) {
        $gameDir = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
        break
    }
}
if (!$gameDir) { throw 'В указанной папке не найден AceCombat8.exe.' }
if (Get-Process -Name AceCombat8,start_protected_game,EasyAntiCheat,EasyAntiCheat_EOS,EasyAntiCheat_EOS_Setup -ErrorAction SilentlyContinue) {
    throw 'Сначала штатно закройте игру и её защищённый запуск. Ничего не удалено.'
}
$proxyTarget = Join-Path $gameDir 'dwmapi.dll'
if (!(Test-Path -LiteralPath $proxyTarget)) { Write-Host 'Загрузчика рядом с игрой нет. Очистка не нужна.'; return }
if (![IO.File]::Exists($proxyTarget)) { throw 'dwmapi.dll не является обычным файлом. Ничего не удалено.' }
if ((Get-FileHash -LiteralPath $proxyTarget -Algorithm SHA256).Hash -ine $expectedProxy) {
    throw 'dwmapi.dll отличается от загрузчика теста. Чужой файл оставлен на месте.'
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($gameDir.ToLowerInvariant())))).Replace('-', '').ToLowerInvariant()
} finally { $sha.Dispose() }
$receiptPath = Join-Path $stateDirectory ("loader-ownership-$key.json")
if (![IO.File]::Exists($receiptPath)) { throw 'Нет записи установки из этой папки теста. Автоматическое удаление отменено: принадлежность загрузчика не подтверждена.' }
$receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($receipt.game_directory -ine $gameDir -or $receipt.proxy_path -ine $proxyTarget -or $receipt.proxy_sha256 -ine $expectedProxy) {
    throw 'Запись установки не совпадает с выбранной игрой. Ничего не удалено.'
}
# One verified file only: no recursive removal and no process termination.
Remove-Item -LiteralPath $proxyTarget
Remove-Item -LiteralPath $receiptPath
$result = [ordered]@{ game_directory = $gameDir; session_id = $receipt.session_id; proxy_sha256 = $expectedProxy; removed = $true; finished = (Get-Date -Format o) }
$resultPath = Join-Path $stateDirectory ('cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
$result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host 'Временный загрузчик теста удалён. Остальные файлы игры не изменены.'
