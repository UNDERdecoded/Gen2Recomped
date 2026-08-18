# Windows double-click bootstrap for the LÖVE2D Pokemon recomp port.
# Launched by Play-Windows.bat. Prompts to install any missing tools
# (Python 3 and LÖVE via winget), runs first-time setup, then
# starts the game. Later runs launch the game straight away.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Say($msg)  { Write-Host "==> $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host " !! $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "error: $msg" -ForegroundColor Red }

function Pause-Exit([int]$code = 0) {
    Write-Host ''
    Read-Host 'Press Enter to close this window' | Out-Null
    exit $code
}

function Ask($question) { # yes by default
    $a = Read-Host "$question [Y/n]"
    return ($a -notmatch '^(n|no)$')
}

# winget installs update the registry PATH but not this process's copy;
# re-read it so freshly installed tools are usable without a new window.
function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Find-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try { if ((& py -3 --version 2>$null) -match '^Python 3') { return $true } } catch {}
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        try { if ((& python --version 2>$null) -match '^Python 3') { return $true } } catch {}
    }
    return $false
}

function Find-Love {
    foreach ($name in 'lovec', 'love') {
        if (Get-Command $name -ErrorAction SilentlyContinue) { return $true }
    }
    foreach ($d in @("$env:ProgramFiles\LOVE", "${env:ProgramFiles(x86)}\LOVE", "$env:LOCALAPPDATA\Programs\LOVE")) {
        if ($d -and (Test-Path (Join-Path $d 'love.exe'))) { return $true }
    }
    return $false
}

function Resolve-RomVersion([string]$sha1) {
    switch ($sha1.ToLowerInvariant()) {
        'ea9bcae617fdf159b045185467ae58b2e4a48b9a' { return 'red' }
        'd7037c83e1ae5b39bde3c30787637ba1d4c48ce2' { return 'blue' }
        'cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1' { return 'yellow' }
        'd8b8a3600a465308c9953dfa04f0081c05bdcb94' { return 'gold' }
        '49b163f7e57702bc939d642a18f591de55d92dae' { return 'silver' }
        'f2f52230b536214ef7c9924f483392993e226cfb' { return 'crystal' }
        'f4cd194bdee0d04ca4eac29e09b8e4e9d818c133' { return 'crystal' }
        # Pokemon Prism (Gold hack). Recognised so setup stops calling the
        # cartridge unknown; it has no manifest yet.
        '752076692ae3387cf426ce5f51a98c6b60e8df6a' { return 'prism' }
        default { return $null }
    }
}

function Get-RomContext {
    $romPath = $env:ROM_PATH
    if ([string]::IsNullOrWhiteSpace($romPath)) { return $null }
    if (-not (Test-Path -LiteralPath $romPath -PathType Leaf)) {
        Warn "ROM_PATH is set but file does not exist: $romPath"
        return $null
    }
    $sha = (Get-FileHash -LiteralPath $romPath -Algorithm SHA1).Hash.ToLowerInvariant()
    $version = Resolve-RomVersion $sha
    if (-not $version) {
        Warn "ROM_PATH hash is not a supported canonical ROM: $sha"
        return $null
    }
    return [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $romPath).Path; Sha1 = $sha; Version = $version }
}

Write-Host ''
Write-Host '  Pokemon Recomp - LOVE2D port' -ForegroundColor Cyan
Write-Host ''

$ForceSetup = -not [string]::IsNullOrWhiteSpace($env:ROM_PATH)
$RomCtx = Get-RomContext

# ---------------------------------------------------------------- fast path
# A Gen1 import lands in data\generated; a Gen2/Crystal one lands in the LOVE
# save folder instead, so testing for data\generated\maps.lua reported "not set
# up" forever on a Gen2-only install and re-ran setup at every launch.  The
# stamp setup.ps1 writes covers both.
$SetupStamp = Join-Path $Root '.setup-complete'
$AlreadySetUp = (Test-Path $SetupStamp) -or
                (Test-Path (Join-Path $Root 'data\generated\maps.lua'))
if ($AlreadySetUp -and (Find-Love) -and -not $ForceSetup) {
    Say 'already set up - launching the game'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'scripts\run.ps1')
    if ($LASTEXITCODE -ne 0) { Err 'the game failed to start'; Pause-Exit 1 }
    exit 0
}

if ($ForceSetup) {
    Say 'ROM_PATH detected - running setup to rebuild generated data for that ROM'
}

Say 'first-time setup'

# ------------------------------------------------------------------- winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err 'winget (Windows package manager) is not available.'
    Warn 'Install "App Installer" from the Microsoft Store, then run this again.'
    Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction SilentlyContinue
    Pause-Exit 1
}

# ------------------------------------------------------------------- python
if (-not (Find-Python)) {
    Warn 'Python 3 is missing (needed to build the game data)'
    if (Ask 'Install Python 3 now via winget?') {
        winget install --exact --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
        Refresh-Path
        if (-not (Find-Python)) {
            Err 'Python still not found after install - close this window and double-click again'
            Pause-Exit 1
        }
    } else { Err 'cannot continue without Python 3'; Pause-Exit 1 }
}

# --------------------------------------------------------------------- LOVE
if (-not (Find-Love)) {
    Warn 'LOVE (the game engine) is missing'
    if (Ask 'Install LOVE now via winget?') {
        winget install --exact --id Love2d.Love2d --accept-source-agreements --accept-package-agreements
        Refresh-Path
        if (-not (Find-Love)) {
            Err 'LOVE still not found after install - close this window and double-click again'
            Pause-Exit 1
        }
    } else { Err 'cannot continue without LOVE'; Pause-Exit 1 }
}

# -------------------------------------------------------------------- build
Write-Host ''
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'scripts\setup.ps1')
if ($LASTEXITCODE -ne 0) { Err 'setup failed - see the messages above'; Pause-Exit 1 }

Say 'setup done - launching the game'
if ($RomCtx) {
    $env:POKEPORT_VERSION = $RomCtx.Version
    if ($RomCtx.Version -in @('gold', 'silver', 'crystal', 'prism')) {
        Say "launching $($RomCtx.Version) with extracted datasets (no forced runtime scaffold import)"
        Remove-Item Env:POKEPORT_IMPORT_ROM -ErrorAction SilentlyContinue
        Remove-Item Env:POKEPORT_FORCE_IMPORT -ErrorAction SilentlyContinue
    } else {
        Say "launching runtime importer for $($RomCtx.Version) ROM"
        $env:POKEPORT_IMPORT_ROM = $RomCtx.Path
        $env:POKEPORT_FORCE_IMPORT = '1'
    }
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'scripts\run.ps1')
if ($LASTEXITCODE -ne 0) { Err 'the game failed to start'; Pause-Exit 1 }
exit 0
