[CmdletBinding()]
param(
    [ValidateSet('Host', 'Guest')][string]$Role,
    [string]$PeerSteamId,
    [string]$GameDirectory,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$expectedGame = '51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F'
$expectedProxy = '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'
$expectedSteam = '4DF999C0C8CB12589F0864D52BE5D4C775577AEB27FEE28B49B188F9BA083EEA'
$stateDirectory = Join-Path $packageRoot 'state'
$settingsPath = Join-Path $stateDirectory 'launcher-settings.json'

function Resolve-GameDirectory([string]$InputPath) {
    $clean = $InputPath.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($clean)) { throw 'Папка игры не указана.' }
    $full = [IO.Path]::GetFullPath($clean)
    if ([IO.File]::Exists($full) -and [IO.Path]::GetFileName($full) -ieq 'AceCombat8.exe') {
        $full = Split-Path $full -Parent
    }
    foreach ($relative in @('', 'Game\Binaries\Win64', 'Binaries\Win64')) {
        $candidate = if ($relative) { Join-Path $full $relative } else { $full }
        if ([IO.File]::Exists((Join-Path $candidate 'AceCombat8.exe'))) {
            return [IO.Path]::GetFullPath($candidate).TrimEnd('\')
        }
    }
    throw 'В выбранной папке не найден AceCombat8.exe. Укажите корень установленной игры.'
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Label) {
    if (![IO.File]::Exists($Path)) { throw "$Label отсутствует: $Path" }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Expected) {
        throw "$Label отличается от проверенной версии. Запуск остановлен: $Path"
    }
}

function Write-JsonFile([string]$Path, $Value) {
    $text = ($Value | ConvertTo-Json -Depth 8) + [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($true)))
}

function Get-OwnershipPath([string]$Directory) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Directory.ToLowerInvariant())
        $key = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
    return Join-Path $stateDirectory ("loader-ownership-$key.json")
}

# Validate the complete declared package before adding a loader to the game.
$manifestPath = Join-Path $packageRoot 'manifest.json'
if (![IO.File]::Exists($manifestPath)) { throw 'Нет manifest.json. Распакуйте полный архив теста.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Неподдерживаемая версия manifest.json.' }
if ($manifest.game_sha256 -ine $expectedGame -or $manifest.steam_dll_sha256 -ine $expectedSteam) {
    throw 'Манифест предназначен для другой версии игры.'
}
$listed = @{}
foreach ($entry in @($manifest.files)) {
    $relative = [string]$entry.path
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
        $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative.Contains(':')) {
        throw 'Недопустимый путь в manifest.json.'
    }
    $normalized = $relative.Replace('/', '\')
    if ($listed.ContainsKey($normalized)) { throw "Повторный путь в манифесте: $relative" }
    if ([string]$entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "Нет SHA256 для $relative" }
    $absolute = [IO.Path]::GetFullPath((Join-Path $packageRoot $normalized))
    if (!$absolute.StartsWith($packageRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Путь манифеста выходит за папку теста.'
    }
    Assert-Hash $absolute ([string]$entry.sha256) "Файл пакета $relative"
    $listed[$normalized] = [string]$entry.sha256
}
foreach ($required in @('Launch-ConnectionTest.ps1', 'Remove-ConnectionLoader.ps1',
    'loader\dwmapi.dll', 'runtime\UE4SS.dll', 'runtime\ac8_connection_test.dll',
    'runtime\Mods\AC8ConnectionTest\Scripts\main.lua')) {
    if (!$listed.ContainsKey($required)) { throw "Обязательный файл не включён в манифест: $required" }
}

$settings = $null
if ([IO.File]::Exists($settingsPath)) {
    try { $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Warning 'Сохранённые настройки не читаются; выберите параметры заново.' }
}
if (!$Role) { $Role = Read-Host 'Ваша роль: Host (ведущий) или Guest (друг)' }
if ($Role -notin @('Host', 'Guest')) { throw 'Роль должна быть Host или Guest.' }
if (!$GameDirectory -and $settings) { $GameDirectory = [string]$settings.game_directory }
if (!$GameDirectory) { $GameDirectory = Read-Host 'Вставьте полный путь к папке ACE COMBAT 8' }
$gameDir = Resolve-GameDirectory $GameDirectory

if (!$PeerSteamId -and $settings -and $settings.peer_by_role) {
    $PeerSteamId = [string]$settings.peer_by_role.$Role
}
$peersPath = Join-Path $packageRoot 'peers.json'
if (!$PeerSteamId -and [IO.File]::Exists($peersPath)) {
    if (!$listed.ContainsKey('peers.json')) { throw 'peers.json отсутствует в манифесте.' }
    $peers = Get-Content -LiteralPath $peersPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $PeerSteamId = if ($Role -eq 'Host') { [string]$peers.guest_steam_id } else { [string]$peers.host_steam_id }
}
if (!$PeerSteamId) { $PeerSteamId = Read-Host 'SteamID64 второго участника (17 цифр)' }
$PeerSteamId = $PeerSteamId.Trim()
$peerNumber = [UInt64]0
if ($PeerSteamId -notmatch '^[0-9]{17}$' -or ![UInt64]::TryParse($PeerSteamId, [ref]$peerNumber)) {
    throw 'Нужен SteamID64 второго участника: ровно 17 цифр.'
}

$gameExe = Join-Path $gameDir 'AceCombat8.exe'
$proxySource = Join-Path $packageRoot 'loader\dwmapi.dll'
$proxyTarget = Join-Path $gameDir 'dwmapi.dll'
$runtimeDll = Join-Path $packageRoot 'runtime\UE4SS.dll'
$nativeDll = Join-Path $packageRoot 'runtime\ac8_connection_test.dll'
$steamDll = [IO.Path]::GetFullPath((Join-Path $gameDir '..\..\..\Engine\Binaries\ThirdParty\Steamworks\Steamv157\Win64\steam_api64.dll'))
Assert-Hash $gameExe $expectedGame 'Игра'
Assert-Hash $proxySource $expectedProxy 'Загрузчик'
Assert-Hash $steamDll $expectedSteam 'Steam DLL игры'
if (Test-Path -LiteralPath $proxyTarget) {
    throw 'Рядом с игрой уже есть dwmapi.dll. Файл не изменён. Если он остался от этого теста, запустите Remove-ConnectionLoader.ps1 после закрытия игры.'
}
$blockedProcesses = @('AceCombat8', 'start_protected_game', 'EasyAntiCheat', 'EasyAntiCheat_EOS', 'EasyAntiCheat_EOS_Setup')
if (Get-Process -Name $blockedProcesses -ErrorAction SilentlyContinue) {
    throw 'Сначала штатно закройте AC8 и её защищённый запуск Easy Anti-Cheat.'
}
if (!(Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Сначала запустите Steam и войдите в свой аккаунт.' }
Write-Host "Роль: $Role. Второй участник: $PeerSteamId"
Write-Host "Игра: $gameDir"
if ($ValidateOnly) {
    Write-Host 'Проверка пройдена. Игра не запущена; файлы и настройки не изменены.'
    return
}

[IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
$savedPeers = [ordered]@{ Host = ''; Guest = '' }
if ($settings -and $settings.peer_by_role) {
    $savedPeers.Host = [string]$settings.peer_by_role.Host
    $savedPeers.Guest = [string]$settings.peer_by_role.Guest
}
$savedPeers[$Role] = $PeerSteamId
Write-JsonFile $settingsPath ([ordered]@{ game_directory = $gameDir; role = $Role; peer_by_role = $savedPeers })
$sessionId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$sessionDir = Join-Path $packageRoot ('sessions\' + $sessionId)
[IO.Directory]::CreateDirectory($sessionDir) | Out-Null
$recordPath = Join-Path $sessionDir 'session.json'
$receiptPath = Get-OwnershipPath $gameDir
$record = [ordered]@{
    schema_version = 1; session_id = $sessionId; started = (Get-Date -Format o)
    role = $Role.ToLowerInvariant(); peer_steam_id = $PeerSteamId; game_directory = $gameDir
    game_sha256 = $expectedGame; proxy_sha256 = $expectedProxy; steam_dll_sha256 = $expectedSteam
    native_dll_sha256 = $listed['runtime\ac8_connection_test.dll']; runtime_dll_sha256 = $listed['runtime\UE4SS.dll']
    package_manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    pid = $null; exit_code = $null; proxy_installed = $false; proxy_removed = $false
    cleanup_status = 'not_started'; error = $null; finished = $null
}
Write-JsonFile $recordPath $record
$ownedProxy = $false
$gameProcess = $null
$lastStatus = $null
try {
    # Exclusive copy never replaces an existing file, including a racing launch.
    [IO.File]::Copy($proxySource, $proxyTarget, $false)
    $ownedProxy = $true
    $record.proxy_installed = $true
    Write-JsonFile $receiptPath ([ordered]@{ game_directory = $gameDir; proxy_path = $proxyTarget; proxy_sha256 = $expectedProxy; session_id = $sessionId; created = (Get-Date -Format o) })
    Write-JsonFile $recordPath $record
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gameExe
    $startInfo.WorkingDirectory = $gameDir
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = '-SaveToUserDir --ue4ss-path "' + $runtimeDll + '"'
    foreach ($name in @($startInfo.EnvironmentVariables.Keys)) {
        if ($name -like 'AC8_COOP_*' -or $name -like 'AC8_CONNECTION_*') { $startInfo.EnvironmentVariables.Remove($name) }
    }
    $startInfo.EnvironmentVariables['SteamAppId'] = '2288340'
    $startInfo.EnvironmentVariables['AC8_CONNECTION_TEST'] = '25201480'
    $startInfo.EnvironmentVariables['AC8_CONNECTION_ROLE'] = $Role.ToLowerInvariant()
    $startInfo.EnvironmentVariables['AC8_CONNECTION_PEER'] = $PeerSteamId
    $startInfo.EnvironmentVariables['AC8_CONNECTION_OUTPUT'] = $sessionDir
    $startInfo.EnvironmentVariables['AC8_CONNECTION_DLL'] = $nativeDll
    $startInfo.EnvironmentVariables['AC8_CONNECTION_STEAM_DLL'] = $steamDll
    $gameProcess = [Diagnostics.Process]::Start($startInfo)
    $record.pid = $gameProcess.Id
    Write-JsonFile $recordPath $record
    Write-Host 'Игра запущена. Останьтесь в главном меню. Это проверка соединения, не кооперативная миссия.'
    Write-Host 'F8 — начать соединение; F6 — записать состояние; F9 — отключиться.'
    Write-Host 'Оставьте это окно открытым. После штатного выхода из игры оно удалит временный загрузчик.'
    Write-Host "Результаты: $sessionDir"
    $statusPath = Join-Path $sessionDir 'status.txt'
    while ($true) {
        $exited = $gameProcess.WaitForExit(1000)
        if ([IO.File]::Exists($statusPath)) {
            try {
                $status = [IO.File]::ReadAllText($statusPath, [Text.Encoding]::UTF8).Trim()
                if ($status -and $status -ne $lastStatus) { Write-Host $status; $lastStatus = $status }
            } catch [IO.IOException] { }
        }
        if ($exited -and !(Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue)) { break }
        if ($exited) { Start-Sleep -Milliseconds 1000 }
    }
    $record.exit_code = $gameProcess.ExitCode
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    if ($ownedProxy) {
        try {
            if (Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue) {
                $record.cleanup_status = 'retained_game_running'
            } elseif (![IO.File]::Exists($proxyTarget)) {
                $record.proxy_removed = $true
                $record.cleanup_status = 'already_absent'
            } elseif ((Get-FileHash -LiteralPath $proxyTarget -Algorithm SHA256).Hash -ieq $expectedProxy) {
                Remove-Item -LiteralPath $proxyTarget
                $record.proxy_removed = $true
                $record.cleanup_status = 'removed'
            } else { $record.cleanup_status = 'retained_hash_mismatch' }
            if ($record.proxy_removed -and [IO.File]::Exists($receiptPath)) { Remove-Item -LiteralPath $receiptPath }
        } catch {
            $record.cleanup_status = 'cleanup_error'
            Write-Warning ("Не удалось завершить очистку: " + $_.Exception.Message)
        }
    }
    $log = Join-Path $packageRoot 'runtime\UE4SS.log'
    if ([IO.File]::Exists($log)) {
        try { Copy-Item -LiteralPath $log -Destination (Join-Path $sessionDir 'UE4SS.log') }
        catch { Write-Warning 'UE4SS.log сейчас недоступен для копирования.' }
    }
    $record.finished = Get-Date -Format o
    Write-JsonFile $recordPath $record
    if ($record.proxy_removed) { Write-Host 'Временный загрузчик удалён. Можно запускать игру обычным способом.' }
    elseif ($ownedProxy) { Write-Warning 'Загрузчик остался. После закрытия игры запустите Remove-ConnectionLoader.ps1 из этой же папки теста.' }
    if ($gameProcess) { $gameProcess.Dispose() }
}
