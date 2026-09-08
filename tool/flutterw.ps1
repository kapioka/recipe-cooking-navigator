$ErrorActionPreference = 'Stop'

$flutterArgs = @($args)
if ($flutterArgs.Count -eq 0) {
    throw 'Pass Flutter arguments, for example: .\tool\flutterw.ps1 analyze'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workspaceDrive = 'R:'
$workspaceRoot = "$workspaceDrive\"

if (Test-Path -LiteralPath $workspaceRoot) {
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
try {
    & subst.exe $workspaceDrive $repoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to map $workspaceDrive to the repository."
    }
    $driveMapped = $true

    Push-Location -LiteralPath $workspaceRoot
    try {
        & $flutterPath @flutterArgs
        $flutterExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    if ($driveMapped) {
        & subst.exe $workspaceDrive /D
    }
}

exit $flutterExitCode
