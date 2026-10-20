. (Join-Path $PSScriptRoot 'rea-env.ps1')
& $reaNode $reaEntry @args
exit $LASTEXITCODE
