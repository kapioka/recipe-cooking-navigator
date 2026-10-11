$ErrorActionPreference = 'Stop'
$pocArgs = @($args)
if ($pocArgs.Count -eq 0) { throw 'Pass Flutter arguments for the isolated SIWC PoC.' }
$pocRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../poc/siwc_android')).Path
if (Test-Path -LiteralPath 'R:\') { throw 'Temporary drive R: is already in use.' }
$pocFlutter = (Get-Command flutter -ErrorAction Stop).Source
$pocMapped = $false
try {
    & subst.exe R: $pocRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not map isolated PoC.' }
    $pocMapped = $true
    Push-Location -LiteralPath 'R:\'
    try { & $pocFlutter @pocArgs; $pocExit = $LASTEXITCODE }
    finally { Pop-Location }
} finally {
    if ($pocMapped) { & subst.exe R: /D }
}
exit $pocExit
