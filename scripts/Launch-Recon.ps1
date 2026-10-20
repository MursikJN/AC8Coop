[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$ManualControl,
    [switch]$DummyLifecycle,
    [switch]$PlaneStaging,
    [switch]$PlaneFlight,
    [ValidateSet('state_probe.lua','network_lifecycle_probe.lua','steam_interface_probe.lua','plane_motion_probe.lua','plane_initialization_probe.lua','plane_configuration_probe.lua')]
    [string]$ReadOnlyProbe = 'state_probe.lua',
    [string]$GameDirectory = 'D:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64'
)
$ErrorActionPreference = 'Stop'
$profileRoot = $PSScriptRoot
$toolRoot = Split-Path (Split-Path $profileRoot -Parent) -Parent
$gameDir = [IO.Path]::GetFullPath($GameDirectory)
$gameExe = Join-Path $gameDir 'AceCombat8.exe'
$proxySource = Join-Path $toolRoot 'packages\ue4ss-3.0.1-1181-g83330635\dwmapi.dll'
$proxyTarget = Join-Path $gameDir 'dwmapi.dll'
$runtimeDll = Join-Path $profileRoot 'runtime\UE4SS.dll'
if ($ManualControl -and $PSBoundParameters.ContainsKey('ReadOnlyProbe')) {
    throw 'ManualControl and an explicit ReadOnlyProbe cannot be combined.'
}
if ($DummyLifecycle -and ($ManualControl -or $PSBoundParameters.ContainsKey('ReadOnlyProbe'))) {
    throw 'DummyLifecycle is a separate experiment; do not combine it with other probes.'
}
if ($PlaneStaging -and ($DummyLifecycle -or $ManualControl -or $PSBoundParameters.ContainsKey('ReadOnlyProbe'))) {
    throw 'PlaneStaging is a separate experiment; do not combine it with other probes.'
}
if ($PlaneFlight -and ($PlaneStaging -or $DummyLifecycle -or $ManualControl -or $PSBoundParameters.ContainsKey('ReadOnlyProbe'))) {
    throw 'PlaneFlight is a separate experiment; do not combine it with other probes.'
}
$extensionName = if ($PlaneFlight) { 'plane_flight_probe.lua' } elseif ($PlaneStaging) { 'plane_staging_probe.lua' } elseif ($DummyLifecycle) { 'dummy_lifecycle_probe.lua' } elseif ($ManualControl) { 'manual_control.lua' } else { $ReadOnlyProbe }
$extensionPath = Join-Path $profileRoot ('runtime\Mods\AC8CoopRecon\Scripts\' + $extensionName)
$expectedGame = '51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F'
$expectedProxy = '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'
$steamProbe = !$ManualControl -and $ReadOnlyProbe -eq 'steam_interface_probe.lua'
$motionProbe = !$ManualControl -and $ReadOnlyProbe -eq 'plane_motion_probe.lua'
$initializationProbe = !$ManualControl -and $ReadOnlyProbe -eq 'plane_initialization_probe.lua'
$configurationProbe = !$ManualControl -and $ReadOnlyProbe -eq 'plane_configuration_probe.lua'
$samplerEnabled = $motionProbe -or $initializationProbe -or $configurationProbe
$motionSampler = Join-Path $profileRoot 'scripts\sample_plane_motion.py'
$samplerDependency = $motionSampler
if ($initializationProbe) { $motionSampler = Join-Path $profileRoot 'scripts\sample_plane_initialization.py' }
if ($configurationProbe) { $motionSampler = Join-Path $profileRoot 'scripts\sample_plane_configuration.py' }
$motionLayout = Join-Path $profileRoot 'native\plane_motion_layout.json'
$motionPython = 'C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$nativeProbe = Join-Path $profileRoot 'runtime\ac8_steam_probe.dll'
$dummyProbeDll = Join-Path $profileRoot 'runtime\ac8_dummy_lifecycle_probe.dll'
$expectedDummyProbe = '9EF30DE4EB850B0D0881B4DADD43E0DBAAEBFE6C12B747920BC605BCAF35CFD7'
$planeStagingDll = Join-Path $profileRoot 'runtime\ac8_plane_staging_probe.dll'
$expectedPlaneStaging = '3370B68B216B025C0CFE0B3887C74EA1222752C0755CCD4392228D0211FC8AFF'
$planeFlightDll = Join-Path $profileRoot 'runtime\ac8_plane_flight_probe_r4.dll'
$expectedPlaneFlight = '261B7330D8DF536956CD877DF92A2701C93F5D5BEA11BB95B25287DD2BC21727'
$steamDll = [IO.Path]::GetFullPath((Join-Path $gameDir '..\..\..\Engine\Binaries\ThirdParty\Steamworks\Steamv157\Win64\steam_api64.dll'))
$expectedNativeProbe = '1A9A174FF311C965BE9A770483277F2F26CCF9A0FB87E043274617A581B355CF'
$expectedSteamDll = '4DF999C0C8CB12589F0864D52BE5D4C775577AEB27FEE28B49B188F9BA083EEA'
if ((Get-FileHash -LiteralPath $gameExe).Hash -ne $expectedGame) { throw 'Game build changed. Revalidate the profile first.' }
if ((Get-FileHash -LiteralPath $proxySource).Hash -ne $expectedProxy) { throw 'Proxy hash mismatch.' }
if (!(Test-Path -LiteralPath $runtimeDll)) { throw 'UE4SS runtime is missing.' }
if (!(Test-Path -LiteralPath $extensionPath)) { throw 'Requested extension is missing.' }
if ($samplerEnabled) {
    foreach ($required in @($motionSampler, $samplerDependency, $motionLayout, $motionPython)) {
        if (!(Test-Path -LiteralPath $required)) { throw "Flight sampler dependency missing: $required" }
    }
}
if ($steamProbe) {
    if ((Get-FileHash -LiteralPath $nativeProbe).Hash -ne $expectedNativeProbe) { throw 'Steam probe DLL hash mismatch.' }
    if ((Get-FileHash -LiteralPath $steamDll).Hash -ne $expectedSteamDll) { throw 'Steam DLL differs from the inspected build.' }
}
if ($DummyLifecycle) {
    if ((Get-FileHash -LiteralPath $dummyProbeDll).Hash -ne $expectedDummyProbe) { throw 'Dummy lifecycle probe DLL hash mismatch.' }
}
if ($PlaneStaging) {
    if ((Get-FileHash -LiteralPath $planeStagingDll).Hash -ne $expectedPlaneStaging) { throw 'Plane staging probe DLL hash mismatch.' }
}
if ($PlaneFlight) {
    if ((Get-FileHash -LiteralPath $planeFlightDll).Hash -ne $expectedPlaneFlight) { throw 'Plane flight probe DLL hash mismatch.' }
}
if (Test-Path -LiteralPath $proxyTarget) { throw 'Existing game proxy: refusing to overwrite it. Use cleanup after an interrupted research session.' }
if ($ValidateOnly) { Write-Output 'Profile paths, game hash and official proxy hash verified. No launch or game edits.'; return }
if (Get-Process -Name AceCombat8,start_protected_game,EasyAntiCheat_EOS -ErrorAction SilentlyContinue) { throw 'Close the game and its launcher before starting research.' }
if (!(Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Start Steam first.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDir = Join-Path $profileRoot "evidence\session-$stamp"
New-Item -ItemType Directory -Path $sessionDir | Out-Null
$record = [ordered]@{started=(Get-Date -Format o);game_sha256=$expectedGame;proxy_sha256=$expectedProxy;runtime=$runtimeDll;manual_control=[bool]$ManualControl;extension=$extensionName;extension_sha256=(Get-FileHash -LiteralPath $extensionPath).Hash;pid=$null;exit_code=$null;proxy_removed=$false}
if ($DummyLifecycle) { $record.experiment = 'dummy_lifecycle_single_owned_attempt'; $record.native_probe_sha256 = $expectedDummyProbe }
if ($PlaneStaging) { $record.experiment = 'plane_staging_no_finish_single_attempt'; $record.native_probe_sha256 = $expectedPlaneStaging }
if ($PlaneFlight) { $record.experiment = 'plane_flight_bounded_local_copy'; $record.native_probe_sha256 = $expectedPlaneFlight }
$ownedProxy = $false
$gameProcess = $null
$motionProcess = $null
try {
    # Only the loader is placed beside the game; all research data stays on D:.
    [System.IO.File]::Copy($proxySource, $proxyTarget, $false)
    $ownedProxy = $true
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gameExe
    $startInfo.WorkingDirectory = $gameDir
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = '-SaveToUserDir --ue4ss-path "' + $runtimeDll + '"'
    $startInfo.EnvironmentVariables['SteamAppId'] = '2288340'
    $startInfo.EnvironmentVariables['AC8_COOP_RECON'] = '1'
    $startInfo.EnvironmentVariables['AC8_COOP_RECON_OUTPUT'] = $sessionDir
    $startInfo.EnvironmentVariables['AC8_COOP_RECON_EXTENSION'] = $extensionPath
    foreach ($name in @('AC8_COOP_STEAM_PROBE','AC8_COOP_STEAM_PROBE_DLL','AC8_COOP_STEAM_DLL')) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
    foreach ($name in @('AC8_COOP_DUMMY_PROBE','AC8_COOP_DUMMY_PROBE_DLL')) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
    foreach ($name in @('AC8_COOP_PLANE_STAGING','AC8_COOP_PLANE_STAGING_DLL')) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
    foreach ($name in @('AC8_COOP_PLANE_FLIGHT','AC8_COOP_PLANE_FLIGHT_DLL')) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
    if ($PlaneFlight) {
        $startInfo.EnvironmentVariables['AC8_COOP_PLANE_FLIGHT'] = '25201480'
        $startInfo.EnvironmentVariables['AC8_COOP_PLANE_FLIGHT_DLL'] = $planeFlightDll
        Copy-Item -LiteralPath $planeFlightDll -Destination (Join-Path $sessionDir 'plane-flight-probe-used.dll')
    }
    if ($PlaneStaging) {
        $startInfo.EnvironmentVariables['AC8_COOP_PLANE_STAGING'] = '25201480'
        $startInfo.EnvironmentVariables['AC8_COOP_PLANE_STAGING_DLL'] = $planeStagingDll
        Copy-Item -LiteralPath $planeStagingDll -Destination (Join-Path $sessionDir 'plane-staging-probe-used.dll')
    }
    if ($DummyLifecycle) {
        $startInfo.EnvironmentVariables['AC8_COOP_DUMMY_PROBE'] = '25201480'
        $startInfo.EnvironmentVariables['AC8_COOP_DUMMY_PROBE_DLL'] = $dummyProbeDll
        Copy-Item -LiteralPath $dummyProbeDll -Destination (Join-Path $sessionDir 'dummy-probe-used.dll')
    }
    if ($steamProbe) {
        $startInfo.EnvironmentVariables['AC8_COOP_STEAM_PROBE'] = '25201480'
        $startInfo.EnvironmentVariables['AC8_COOP_STEAM_PROBE_DLL'] = $nativeProbe
        $startInfo.EnvironmentVariables['AC8_COOP_STEAM_DLL'] = $steamDll
        $record.native_probe_sha256 = $expectedNativeProbe
        $record.steam_dll_sha256 = $expectedSteamDll
    }
    $startInfo.EnvironmentVariables.Remove('AC8_COOP_MANUAL')
    if ($ManualControl) { $startInfo.EnvironmentVariables['AC8_COOP_MANUAL'] = '25201480' }
    Copy-Item -LiteralPath $extensionPath -Destination (Join-Path $sessionDir 'initial-extension.lua')
    $gameProcess = [System.Diagnostics.Process]::Start($startInfo)
    $record.pid = $gameProcess.Id
    if ($samplerEnabled) {
        $record.sampler_sha256 = (Get-FileHash -LiteralPath $motionSampler).Hash
        $record.sampler_dependency_sha256 = (Get-FileHash -LiteralPath $samplerDependency).Hash
        $record.motion_layout_sha256 = (Get-FileHash -LiteralPath $motionLayout).Hash
    }
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDir 'session.json') -Encoding UTF8
    Write-Output "Research process $($gameProcess.Id); evidence: $sessionDir"
    if ($samplerEnabled) {
        $motionArguments = '"' + $motionSampler + '" --session "' + $sessionDir + '" --wait-ticket 900'
        if (!$configurationProbe) { $motionArguments += ' --duration 30 --hz 10' }
        $motionProcess = Start-Process -FilePath $motionPython -ArgumentList $motionArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $sessionDir 'flight-sampler.stdout.log') -RedirectStandardError (Join-Path $sessionDir 'flight-sampler.stderr.log')
        if ($configurationProbe) {
            Write-Output 'Mission 6, F-14D, after refueling: pause, F8 once, keep paused. One read-only configuration snapshot; no maneuvers or new plane. Leave the game open for review. F7 has no handler in this profile.'
        } elseif ($initializationProbe) {
            Write-Output 'Mission 6, F-14D, after refueling: pause, F8 once, stay paused 3 seconds; then unpause and use stick/bumpers/throttle/brake for 25 seconds. Read-only sources; no aircraft creation. F6/F7 experiments disabled.'
        } else {
            Write-Output 'Mission 6, F-14D, after refueling: F8 once, then fly normally for 30 seconds. Read-only flight capture; F6/F7 control experiments are disabled.'
        }
    } elseif ($PlaneFlight) {
        Write-Output 'Mission 6, F-14D, after refueling: F8 preflight; wait for review before F7. One local copy at a fixed world offset for at most 15 seconds; actual pose and render-state observations are recorded. F9 cleanup. No peer connection, possession or camera change. If quarantine is reported, exit normally.'
    } elseif ($PlaneStaging) {
        Write-Output 'Mission 6, F-14D, after refueling: F8 preflight only. Wait for review before F7. One deferred plane/cache staging and rollback attempt. No FinishSpawning, possession, room or flight update release. F9 verifies cleanup.'
    } elseif ($DummyLifecycle) {
        Write-Output 'Mission 6, F-14D, after refueling: F8 preflight only. Wait for review before F7. One native-owned dummy controller spawn/destroy; no plane, possession or network session. F9 verifies owned cleanup.'
    } elseif ($steamProbe) {
        Write-Output 'Stay in the main menu. F8 checks Steam interfaces; no room or connection is created. Exit normally to remove the loader.'
    } else {
        Write-Output 'Stay in single-player. F8 captures objects. Exit the game normally to remove the loader.'
    }
    while (!$gameProcess.WaitForExit(1000)) { }
    $record.exit_code = $gameProcess.ExitCode
}
finally {
    if ($null -ne $motionProcess) {
        # Only our external read-only child, never the game or another Python process.
        try {
            if (!$motionProcess.HasExited) { $motionProcess.Kill(); $motionProcess.WaitForExit() }
            $record.motion_sampler_exit_code = $motionProcess.ExitCode
        } catch {
            $record.motion_sampler_cleanup_error = $_.Exception.Message
            Write-Warning 'Could not finish the flight sampler. Continuing loader cleanup.'
        }
    }
    # Never delete a foreign DLL or remove a loader from a running game.
    if ($ownedProxy -and !(Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue)) {
        if ((Test-Path -LiteralPath $proxyTarget) -and (Get-FileHash -LiteralPath $proxyTarget).Hash -eq $expectedProxy) {
            Remove-Item -LiteralPath $proxyTarget
            $record.proxy_removed = $true
        }
    }
    $log = Join-Path $profileRoot 'runtime\UE4SS.log'
    if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination (Join-Path $sessionDir 'UE4SS.log') }
    $record.finished = Get-Date -Format o
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDir 'session.json') -Encoding UTF8
    if (!$record.proxy_removed) { Write-Warning 'Loader remains. After the game exits, run Remove-ReconLoader.ps1 before ordinary play.' }
}
