[CmdletBinding()]
param(
    [string]$KeystorePath,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$KeyAlias = 'recipe-cooking-navigator',

    [switch]$PublicAiV2Ready
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'local-signing.ps1')
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ($PublicAiV2Ready) {
    & (Join-Path $PSScriptRoot 'validate-public-ai.ps1') -Repository $repoRoot
    if ($LASTEXITCODE -ne 0) { throw 'Public AI contract verification failed.' }
}
if (-not [string]::IsNullOrWhiteSpace($KeystorePath)) {
    throw 'Register the existing key with Setup-Signing.cmd, then use Build-Release.cmd without keystore arguments.'
}
$savedSigning = Read-LocalSigningProfile -App recipe -Repository $repoRoot
$KeystorePath = $savedSigning.StoreFile
$KeyAlias = $savedSigning.KeyAlias

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureValue
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

$resolvedKeystorePath = (Resolve-Path -LiteralPath $KeystorePath).Path
if (-not (Test-Path -LiteralPath $resolvedKeystorePath -PathType Leaf)) {
    throw "Keystore was not found: $resolvedKeystorePath"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedKeystorePath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The release keystore must be stored outside the repository.'
}
$flutterWrapper = Join-Path $PSScriptRoot 'flutterw.ps1'
$verifyScript = Join-Path $PSScriptRoot 'verify-release.ps1'
$apkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytoolCommand) {
    throw 'keytool was not found. Install or select a JDK before building the signed APK.'
}

& $flutterWrapper pub get
if ($LASTEXITCODE -ne 0) {
    throw "Flutter dependency resolution failed with exit code $LASTEXITCODE."
}

$previousEnvironment = @{
    StoreFile = $env:RCN_RELEASE_STORE_FILE
    StorePassword = $env:RCN_RELEASE_STORE_PASSWORD
    KeyAlias = $env:RCN_RELEASE_KEY_ALIAS
    KeyPassword = $env:RCN_RELEASE_KEY_PASSWORD
    GradleOpts = $env:GRADLE_OPTS
}

$password = $null
try {
    $securePassword = $savedSigning.StorePassword
    $password = ConvertTo-PlainText $securePassword
    if ([string]::IsNullOrWhiteSpace($password)) {
        throw 'The keystore password cannot be empty.'
    }

    $env:RCN_RELEASE_STORE_FILE = $resolvedKeystorePath
    $env:RCN_RELEASE_STORE_PASSWORD = $password
    $env:RCN_RELEASE_KEY_ALIAS = $KeyAlias
    $env:RCN_RELEASE_KEY_PASSWORD = Convert-SigningPassword $savedSigning.KeyPassword
    $env:GRADLE_OPTS = (($previousEnvironment.GradleOpts, '-Dorg.gradle.daemon=false -Dorg.gradle.configuration-cache=false') -join ' ').Trim()

    & $keytoolCommand.Source `
        -list `
        -keystore $resolvedKeystorePath `
        -alias $KeyAlias `
        '-storepass:env' RCN_RELEASE_STORE_PASSWORD |
        Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Keystore password or key alias verification failed. Check the saved release-signing information.'
    }

    $releaseArgs = @('build', 'apk', '--release')
    if ($PublicAiV2Ready) { $releaseArgs += '--dart-define=RCN_PUBLIC_AI_V2_READY=true' }
    & $flutterWrapper @releaseArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter release build failed with exit code $LASTEXITCODE."
    }

    Assert-RegisteredApkSigner -ApkPath $apkPath -Profile $savedSigning -Repository $repoRoot
    & $verifyScript -ApkPath $apkPath -WriteChecksum
    if ($LASTEXITCODE -ne 0) {
        throw "Release verification failed with exit code $LASTEXITCODE."
    }
} finally {
    $password = $null
    $environmentMap = @{
        RCN_RELEASE_STORE_FILE = $previousEnvironment.StoreFile
        RCN_RELEASE_STORE_PASSWORD = $previousEnvironment.StorePassword
        RCN_RELEASE_KEY_ALIAS = $previousEnvironment.KeyAlias
        RCN_RELEASE_KEY_PASSWORD = $previousEnvironment.KeyPassword
        GRADLE_OPTS = $previousEnvironment.GradleOpts
    }
    foreach ($entry in $environmentMap.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item -Path "Env:$($entry.Key)" -ErrorAction SilentlyContinue
        } else {
            Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
        }
    }
}
