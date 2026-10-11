$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'local-signing.ps1')
Register-LocalSigningProfile -App recipe -Repository (Split-Path $PSScriptRoot -Parent) -DefaultAlias 'recipe-cooking-navigator'
