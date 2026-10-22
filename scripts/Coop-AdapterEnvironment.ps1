# Build the child-process contract without launching or modifying the game.
function Set-CoopAdapterEnvironment {
 param([Diagnostics.ProcessStartInfo]$Info,[string]$Root)
 if($Info.UseShellExecute){throw 'Adapter environment requires an explicit child process environment'}
 $Info.EnvironmentVariables['AC8_MENU_ROUTE']='25201480'
 $Info.EnvironmentVariables['AC8_MISSION_SYNC']='25201480'
 $Info.EnvironmentVariables['AC8_LOCAL_SCRIPTS']=[IO.Path]::GetFullPath((Join-Path $Root 'runtime/Mods/AC8CoopRecon/Scripts'))
}
