$ErrorActionPreference = 'Stop'

$flutterArgs = @($args)
if ($flutterArgs.Count -eq 0) {
    throw 'Pass Flutter arguments, for example: .\tool\flutterw.ps1 analyze'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workspaceDrive = 'R:'
$workspaceRoot = "$workspaceDrive\"

if ($repoRoot -match '[^\x00-\x7F]' -and (Test-Path -LiteralPath $workspaceRoot)) {
    throw "The temporary Flutter workspace drive is already in use: $workspaceDrive"
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -ne $flutterCommand) {
    $flutterPath = $flutterCommand.Source
} else {
    $flutterPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'develop\flutter\bin\flutter.bat'
    if (-not (Test-Path -LiteralPath $flutterPath)) {
        throw 'Flutter was not found on PATH or in the default user installation directory.'
    }
}

$flutterBin = Split-Path -Parent $flutterPath
if (($env:Path -split ';') -notcontains $flutterBin) {
    $env:Path = "$flutterBin;$env:Path"
}

$driveMapped = $false
$previousGradleOptions = $env:GRADLE_OPTS
try {
    $env:GRADLE_OPTS = ($previousGradleOptions + ' -Dorg.gradle.daemon=false -Dorg.gradle.vfs.watch=false').Trim()
    if ($repoRoot -match '[^\x00-\x7F]') {
        & subst.exe $workspaceDrive $repoRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to map $workspaceDrive to the repository."
        }
        $driveMapped = $true
    } else {
        $workspaceRoot = $repoRoot
    }

    Push-Location -LiteralPath $workspaceRoot
    try {
        & $flutterPath @flutterArgs
        $flutterExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    $env:GRADLE_OPTS = $previousGradleOptions
    if ($driveMapped) {
        & subst.exe $workspaceDrive /D
    }
}

exit $flutterExitCode
