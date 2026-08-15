param(
    [string]$Manifest = (Join-Path $PSScriptRoot "..\..\ports\uwp\third_party\manifest.json")
)

$ErrorActionPreference = "Stop"

$manifestPath = (Resolve-Path $Manifest).Path
$thirdPartyRoot = Split-Path -Parent $manifestPath
$metadata = Get-Content -Raw $manifestPath | ConvertFrom-Json

function Get-Sha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$NormalizeLineEndings
    )

    if ($NormalizeLineEndings) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n")
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace("-", "")
        } finally {
            $sha256.Dispose()
        }
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString($sha256.ComputeHash($stream)).Replace("-", "")
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

foreach ($file in $metadata.files) {
    $path = Join-Path $thirdPartyRoot $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing UWP dependency: $($file.path)"
    }

    $normalize = $file.path.StartsWith("sdl2/include/", [System.StringComparison]::Ordinal)
    $actual = Get-Sha256 -Path $path -NormalizeLineEndings:$normalize
    if ($actual -ne $file.sha256) {
        throw "UWP dependency hash mismatch: $($file.path)"
    }
}

Write-Host "Verified $($metadata.files.Count) UWP dependency files."
