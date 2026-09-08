[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KeystorePath,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$KeyAlias = 'recipe-cooking-navigator',

    [ValidateRange(9125, 36500)]
    [int]$ValidityDays = 10000,

    [string]$DistinguishedName = 'CN=Recipe Cooking Navigator, OU=Android, O=kapioka, C=JP'
)

$ErrorActionPreference = 'Stop'

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

$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytoolCommand) {
    throw 'keytool was not found. Install or select a JDK before creating the signing key.'
}

$resolvedKeystorePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KeystorePath)
$resolvedKeystorePath = [IO.Path]::GetFullPath($resolvedKeystorePath)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedKeystorePath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'KeystorePath must be outside the repository.'
}
if (Test-Path -LiteralPath $resolvedKeystorePath) {
    throw "Refusing to overwrite an existing keystore: $resolvedKeystorePath"
}

$parentDirectory = Split-Path -Parent $resolvedKeystorePath
if ([string]::IsNullOrWhiteSpace($parentDirectory)) {
    throw 'KeystorePath must include a parent directory.'
}
[IO.Directory]::CreateDirectory($parentDirectory) | Out-Null

$password = $null
$confirmation = $null
$previousPassword = $env:RCN_KEYTOOL_PASSWORD
try {
    $securePassword = Read-Host 'New keystore password (16 or more characters)' -AsSecureString
    $secureConfirmation = Read-Host 'Confirm keystore password' -AsSecureString
    $password = ConvertTo-PlainText $securePassword
    $confirmation = ConvertTo-PlainText $secureConfirmation

    if ($password.Length -lt 16) {
        throw 'The keystore password must contain at least 16 characters.'
    }
    if (-not [StringComparer]::Ordinal.Equals($password, $confirmation)) {
        throw 'The keystore passwords do not match.'
    }

    $env:RCN_KEYTOOL_PASSWORD = $password
    & $keytoolCommand.Source `
        -genkeypair `
        -noprompt `
        -storetype PKCS12 `
        -keystore $resolvedKeystorePath `
        -alias $KeyAlias `
        -keyalg RSA `
        -keysize 3072 `
        -sigalg SHA256withRSA `
        -validity $ValidityDays `
        -dname $DistinguishedName `
        '-storepass:env' RCN_KEYTOOL_PASSWORD `
        '-keypass:env' RCN_KEYTOOL_PASSWORD
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed with exit code $LASTEXITCODE."
    }

    Write-Output "Created keystore: $resolvedKeystorePath"
    Write-Output "Key alias: $KeyAlias"
    & $keytoolCommand.Source `
        -list `
        -v `
        -keystore $resolvedKeystorePath `
        -alias $KeyAlias `
        '-storepass:env' RCN_KEYTOOL_PASSWORD |
        Select-String -Pattern 'Owner:|Valid from:|SHA256:'
    if ($LASTEXITCODE -ne 0) {
        throw "keytool could not verify the generated keystore (exit code $LASTEXITCODE)."
    }

    Write-Warning 'Back up the keystore and its password separately before publishing an APK.'
} finally {
    $password = $null
    $confirmation = $null
    if ($null -eq $previousPassword) {
        Remove-Item Env:RCN_KEYTOOL_PASSWORD -ErrorAction SilentlyContinue
    } else {
        $env:RCN_KEYTOOL_PASSWORD = $previousPassword
    }
}
