[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$ExpectedPackage = 'com.kapioka.recipe_cooking_navigator',

    [switch]$WriteChecksum
)

$ErrorActionPreference = 'Stop'

$resolvedApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$apkToolPath = $resolvedApkPath
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedApkPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    $workspaceParent = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'FlutterWorkspaces'
    $workspaceLink = Join-Path $workspaceParent 'recipe-cooking-navigator'
    if (-not (Test-Path -LiteralPath $workspaceLink)) {
        throw "The ASCII workspace junction was not found: $workspaceLink"
    }

    $linkItem = Get-Item -LiteralPath $workspaceLink -Force
    if (-not $linkItem.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw "The ASCII workspace path is not a junction: $workspaceLink"
    }
    $linkTarget = [IO.Path]::GetFullPath(@($linkItem.Target)[0])
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($linkTarget, $repoRoot)) {
        throw "The ASCII workspace junction points elsewhere: $linkTarget"
    }

    $relativeApkPath = [IO.Path]::GetRelativePath($repoRoot, $resolvedApkPath)
    $apkToolPath = Join-Path $workspaceLink $relativeApkPath
    if (-not (Test-Path -LiteralPath $apkToolPath -PathType Leaf)) {
        throw "The APK was not reachable through the ASCII workspace junction: $apkToolPath"
    }
}

$localPropertiesPath = Join-Path $repoRoot 'android\local.properties'
if (-not (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf)) {
    throw "Android local.properties was not found: $localPropertiesPath"
}

$sdkLine =
    Get-Content -LiteralPath $localPropertiesPath |
    Where-Object { $_ -like 'sdk.dir=*' } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($sdkLine)) {
    throw 'sdk.dir is missing from android/local.properties.'
}

$sdkPath = ($sdkLine -replace '^sdk.dir=', '') -replace '\\:', ':' -replace '\\\\', '\'
$buildToolsRoot = Join-Path $sdkPath 'build-tools'
$buildTools =
    Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
    Sort-Object {
        try {
            [version]$_.Name
        } catch {
            [version]'0.0'
        }
    } -Descending |
    Select-Object -First 1
if ($null -eq $buildTools) {
    throw "No Android build-tools installation was found under $buildToolsRoot."
}

$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$zipalign = Join-Path $buildTools.FullName 'zipalign.exe'
foreach ($toolPath in @($apksigner, $aapt, $zipalign)) {
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        throw "Required Android build tool was not found: $toolPath"
    }
}

$signatureOutput = & $apksigner verify --verbose --print-certs $apkToolPath 2>&1
if ($LASTEXITCODE -ne 0) {
    $signatureOutput | Write-Output
    throw 'apksigner verification failed.'
}
$signatureOutput | Write-Output

$certificateLine = $signatureOutput | Where-Object { $_ -like 'Signer #1 certificate DN:*' } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($certificateLine)) {
    throw 'The APK signer certificate could not be identified.'
}
if ($certificateLine -match 'CN=Android Debug') {
    throw 'The APK is signed with the Android Debug certificate.'
}

& $zipalign -c -v 4 $apkToolPath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'zipalign verification failed.'
}

$badging = & $aapt dump badging $apkToolPath
if ($LASTEXITCODE -ne 0) {
    throw 'aapt could not read APK metadata.'
}
$packageLine = $badging | Where-Object { $_ -like 'package:*' } | Select-Object -First 1
if ($packageLine -notmatch "name='([^']+)'\s+versionCode='([^']+)'\s+versionName='([^']+)'") {
    throw 'The APK package metadata was not in the expected format.'
}
$packageName = $Matches[1]
$versionCode = $Matches[2]
$versionName = $Matches[3]
if (-not [StringComparer]::Ordinal.Equals($packageName, $ExpectedPackage)) {
    throw "Unexpected package name: $packageName"
}
if ($badging | Where-Object { $_ -like 'application-debuggable*' }) {
    throw 'The APK is marked debuggable.'
}

$hash = (Get-FileHash -LiteralPath $resolvedApkPath -Algorithm SHA256).Hash
$checksumPath = Join-Path (Split-Path -Parent $resolvedApkPath) 'SHA256SUMS.txt'
if ($WriteChecksum) {
    $checksumLine = "$hash  $(Split-Path -Leaf $resolvedApkPath)`r`n"
    [IO.File]::WriteAllText($checksumPath, $checksumLine, [Text.UTF8Encoding]::new($false))
}

[pscustomobject]@{
    Apk = $resolvedApkPath
    SignatureValid = $true
    ZipAligned = $true
    Debuggable = $false
    Package = $packageName
    VersionName = $versionName
    VersionCode = $versionCode
    Certificate = $certificateLine
    Sha256 = $hash
    ChecksumFile = if ($WriteChecksum) { $checksumPath } else { $null }
} | Format-List
