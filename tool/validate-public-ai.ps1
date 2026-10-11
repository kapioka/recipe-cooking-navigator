[CmdletBinding()]
param([string]$Repository = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Repository).Path
$files = @(
    'ai/AGENTS.md', 'ai/workflows/generate.md', 'ai/workflows/improve.md',
    'schemas/recipe-v2.schema.json', 'schemas/feedback-v2.schema.json',
    'docs/chatgpt-integration.md', 'examples/recipe-v2-split-example.json'
)
$remote = 'https://github.com/kapioka/recipe-cooking-navigator.git'
$headLine = & git ls-remote $remote refs/heads/main
if ($LASTEXITCODE -ne 0 -or $headLine -notmatch '^([a-f0-9]{40})\s+refs/heads/main$') {
    throw 'Could not determine the public main revision.'
}
$publicCommit = $Matches[1]
foreach ($file in $files) {
    $local = [IO.File]::ReadAllText((Join-Path $root $file)).Replace("`r`n", "`n").TrimEnd("`n")
    $url = "https://raw.githubusercontent.com/kapioka/recipe-cooking-navigator/$publicCommit/$file"
    $response = Invoke-WebRequest -Uri $url -TimeoutSec 30
    $published = ([string]$response.Content).Replace("`r`n", "`n").TrimEnd("`n")
    if ($published -cne $local) { throw "Public AI contract differs from this app: $file" }
}
Write-Output "Public AI v2 contract matched at $publicCommit ($($files.Count) files)."
exit 0
