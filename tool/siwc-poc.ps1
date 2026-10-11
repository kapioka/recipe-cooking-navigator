$ErrorActionPreference = 'Stop'
$pocArgs = @($args)
if ($pocArgs.Count -eq 0) { throw 'Pass Flutter arguments for the isolated SIWC PoC.' }
$pocRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../poc/siwc_android')).Path
$pocFlutter = (Get-Command flutter -ErrorAction Stop).Source
$pocMapped = $false
$pocWorkingPath = $pocRoot
$pocPreviousGradleOpts = $env:GRADLE_OPTS
try {
    # A reused daemon can retain paths from a previous R: checkout. Keep disk
    # build caches but isolate the process that resolves this build's sources.
    $env:GRADLE_OPTS = ($pocPreviousGradleOpts + ' -Dorg.gradle.daemon=false -Dorg.gradle.vfs.watch=false').Trim()
    # Keep an ASCII worktree's stable path. Reusing R: for different checkouts
    # can leave Gradle's daemon holding stale native-source path information.
    if ($pocRoot -match '[^\x00-\x7F]') {
        if (Test-Path -LiteralPath 'R:\') { throw 'Temporary drive R: is already in use.' }
        $pocRepository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        & subst.exe R: $pocRepository
        if ($LASTEXITCODE -ne 0) { throw 'Could not map isolated PoC.' }
        $pocMapped = $true
        $pocWorkingPath = 'R:\poc\siwc_android'
    }
    Push-Location -LiteralPath $pocWorkingPath
    try { & $pocFlutter @pocArgs; $pocExit = $LASTEXITCODE }
    finally { Pop-Location }
} finally {
    $env:GRADLE_OPTS = $pocPreviousGradleOpts
    if ($pocMapped) { & subst.exe R: /D }
}
exit $pocExit
