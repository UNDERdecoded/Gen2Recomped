# Build game data from a user-provided Pokemon Red/Blue/Yellow/Gold/Silver ROM and install LÖVE.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -Rom C:\path\red.gb
#   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -Rom C:\path\silver.gbc
#
# With no explicit path, the first *.gb / *.gbc file in the project root is used.

param(
    [string]$Rom = $env:ROM_PATH
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Venv = Join-Path $Root '.venv'

function Say($msg)  { Write-Host "==> $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

function Find-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try {
            if ((& py -3 --version 2>$null) -match '^Python 3') {
                return @('py', '-3')
            }
        } catch {}
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        try {
            if ((& python --version 2>$null) -match '^Python 3') {
                return @('python')
            }
        } catch {}
    }
    return $null
}

function Resolve-RomVersion([string]$sha1) {
    switch ($sha1.ToLowerInvariant()) {
        'ea9bcae617fdf159b045185467ae58b2e4a48b9a' { return 'red' }
        'd7037c83e1ae5b39bde3c30787637ba1d4c48ce2' { return 'blue' }
        'cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1' { return 'yellow' }
        'd8b8a3600a465308c9953dfa04f0081c05bdcb94' { return 'gold' }
        '49b163f7e57702bc939d642a18f591de55d92dae' { return 'silver' }
        default { return $null }
    }
}

if (-not $Rom) {
    $candidate = Get-ChildItem -Path $Root -File |
        Where-Object { $_.Extension -in '.gb', '.gbc' } |
        Sort-Object Name |
        Select-Object -First 1
    if ($candidate) { $Rom = $candidate.FullName }
}
if (-not $Rom -or -not (Test-Path -LiteralPath $Rom -PathType Leaf)) {
    Fail "Pokemon ROM not found. Put a .gb/.gbc in $Root or pass -Rom C:\path\file.gb[c]"
}
$Rom = (Resolve-Path -LiteralPath $Rom).Path

$ext = [IO.Path]::GetExtension($Rom).ToLowerInvariant()
if ($ext -ne '.gb' -and $ext -ne '.gbc') {
    Fail "Unsupported ROM extension '$ext'. Use a .gb or .gbc ROM file."
}

$romSha1 = (Get-FileHash -LiteralPath $Rom -Algorithm SHA1).Hash.ToLowerInvariant()
$romVersion = Resolve-RomVersion $romSha1
if (-not $romVersion) {
    Fail "Unsupported ROM SHA-1 $romSha1. Expected canonical Red/Blue/Yellow/Gold/Silver ROM hash."
}
Say "detected ROM version: $romVersion ($romSha1)"

$Python = @(Find-Python)
if (-not $Python) { Fail 'Python 3 is required to decode the ROM' }
$PyExe = $Python[0]
$PyArgs = @($Python | Select-Object -Skip 1)

$VenvPython = Join-Path $Venv 'Scripts\python.exe'
if (-not (Test-Path $VenvPython)) {
    Say 'creating Python environment'
    & $PyExe @PyArgs -m venv $Venv
    if ($LASTEXITCODE -ne 0) { Fail 'venv creation failed' }
}
Say 'installing Pillow'
& $VenvPython -m pip install --quiet --upgrade pip
& $VenvPython -m pip install --quiet pillow
if ($LASTEXITCODE -ne 0) { Fail 'Pillow installation failed' }

Say "decoding game data from $(Split-Path -Leaf $Rom)"
Push-Location $Root
try {
    if ($romVersion -in @('gold', 'silver')) {
        Say 'Gen2 ROM detected: extracting supported datasets with the original ROM pipeline.'
        $loveSave = Join-Path $env:APPDATA 'LOVE\pokemon-love2d'
        $outDir = Join-Path $loveSave (Join-Path $romVersion 'data\generated')
        $assetsDir = Join-Path $loveSave (Join-Path $romVersion 'assets\generated')
        & $VenvPython 'tools\build_data.py' --rom $Rom --version $romVersion --out $outDir --assets $assetsDir --clean --only constants --only charmap --only moves --only items --only text --only maps --only tilesets
    } else {
        & $VenvPython 'tools\build_data.py' --rom $Rom --version $romVersion --clean
    }
    if ($LASTEXITCODE -ne 0) { Fail 'ROM extraction failed' }
} finally {
    Pop-Location
}

function Find-Love {
    foreach ($name in 'lovec', 'love') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($dir in @(
        "$env:ProgramFiles\LOVE",
        "${env:ProgramFiles(x86)}\LOVE",
        "$env:LOCALAPPDATA\Programs\LOVE"
    )) {
        if ($dir) {
            $candidate = Join-Path $dir 'love.exe'
            if (Test-Path $candidate) { return $candidate }
        }
    }
    return $null
}

if (Find-Love) {
    Say 'LÖVE found'
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Say 'installing LÖVE via winget'
    winget install --exact --id Love2d.Love2d --accept-source-agreements --accept-package-agreements
} else {
    Fail 'LÖVE 11.x is not installed; install it from https://love2d.org'
}

Say 'setup complete. Start the game with: scripts\run.ps1'
exit 0
