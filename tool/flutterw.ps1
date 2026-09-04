$ErrorActionPreference = 'Stop'

$flutterArgs = @($args)
if ($flutterArgs.Count -eq 0) {
    throw 'Pass Flutter arguments, for example: .\tool\flutterw.ps1 analyze'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workspaceParent = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'FlutterWorkspaces'
$workspaceLink = Join-Path $workspaceParent 'recipe-cooking-navigator'

New-Item -ItemType Directory -Path $workspaceParent -Force | Out-Null

if (Test-Path -LiteralPath $workspaceLink) {
    $linkItem = Get-Item -LiteralPath $workspaceLink -Force
    if (-not $linkItem.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw "The Flutter workspace path exists but is not a junction: $workspaceLink"
    }

    $linkTarget = [IO.Path]::GetFullPath(@($linkItem.Target)[0])
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($linkTarget, $repoRoot)) {
        throw "The Flutter workspace junction points elsewhere: $linkTarget"
    }
} else {
    New-Item -ItemType Junction -Path $workspaceLink -Target $repoRoot | Out-Null
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

Push-Location -LiteralPath $workspaceLink
try {
    & $flutterPath @flutterArgs
    $flutterExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

exit $flutterExitCode
