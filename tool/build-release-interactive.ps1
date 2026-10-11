$ErrorActionPreference = 'Stop'

# Compatibility entry point: always use the registered automatic signing path.
& (Join-Path $PSScriptRoot 'build-release.ps1')
