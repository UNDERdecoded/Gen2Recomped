# Run the LÖVE2D Pokemon recomp port (Windows).
#
# Assumes LÖVE is installed.  Extra arguments are passed through to LÖVE.
# If data/generated is missing, the in-app launcher/importer will prompt for
# ROM import at runtime.
#
# Link play is peer-to-peer over lua-enet (bundled with LÖVE): one player
# uses START > LINK > HOST A GAME, the other joins the shown address.
# UDP port defaults to 7777; override with $env:POKEPORT_LINK_PORT.

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot

function Fail($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path (Join-Path $Root 'data\generated\maps.lua'))) {
    Write-Host '==> generated data not found locally; launching importer/launcher flow' -ForegroundColor Yellow
}

# Prefer lovec.exe (console-attached) so print output lands in the terminal;
# love.exe is a GUI-subsystem binary that swallows stdout.
function Find-Love {
    foreach ($name in 'lovec', 'love') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $dirs = @(
        "$env:ProgramFiles\LOVE",
        "${env:ProgramFiles(x86)}\LOVE",
        "$env:LOCALAPPDATA\Programs\LOVE"
    )
    foreach ($d in $dirs) {
        foreach ($name in 'lovec.exe', 'love.exe') {
            $p = Join-Path $d $name
            if ($d -and (Test-Path $p)) { return $p }
        }
    }
    return $null
}

$LoveBin = Find-Love
if (-not $LoveBin) {
    Fail 'LÖVE not found,  run scripts\setup.ps1 (or install from https://love2d.org)'
}

& $LoveBin $Root @args
exit $LASTEXITCODE
