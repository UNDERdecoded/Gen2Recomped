# tools/trailer/capture_all.ps1 -- record every trailer shot for every game.
#
#   powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 -Out G:\trailer-footage
#
# Each game is one LOVE run of a driver (default tools/trailer/capture.lua; see
# its header). The voxel mod must be installed in the identity's data folder
# and enabled for the Gen 2 / Gen 3 shots. Output: <Out>\<version>_<shot>.mp4,
# streamed straight into ffmpeg (-Format png writes image sequences instead).
#
# The second trailer (TRAILER_ONLINE.md) runs the same way with its own
# drivers and a scratch identity whose game-data folder is a scratch one, so
# the caches it reads are imported fresh from the ROMs in the repo root and the
# shared caches in G:\Gen2Recomped are never touched:
#
#   powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 `
#     -Identity trailer2_cap -ImportRom -Versions heartgold,soulsilver,black,white,platinum
#   ... -Driver tools/trailer/minigames.lua -Versions heartgold -Only pokeathlon
#
# -ImportRom passes the version's ROM (repo root) as POKEPORT_IMPORT_ROM, which
# the engine uses ONLY when that version's cache in the identity's data folder
# is missing or stale. Never combine it with an identity whose data folder is
# the shared G:\Gen2Recomped. -Timeout kills a stuck run (by its own PID).
# -SnapshotDir: playthrough snapshots the DS shots play on (capture.lua header).
# The Emerald 3DS shots: set $env:E3DS = "1" and run -Versions emerald.
#
# The trailer2_cap identity is %APPDATA%\LOVE\trailer2_cap\options.lua:
#   return { dataDir = "G:\\Gen2Recomped\\scratch_claude\\trailer2\\data",
#            secondScreenMode = "off", musicVol = 0, sfxVol = 0,
#            mods = { EMERALD_3DS_VOXEL = true, ["Gen2Recomped-DramaticShapes"] = false,
#                     HOENN_RELIEF = false, gen2online = false, pokemon_stats = false } }
# (the launcher and the Monster Walker: tools/trailer/launcher/main.lua)
param(
  [string]$Out = "G:\Gen2Recomped\trailer_footage",
  [string]$Identity = "trailer_cap",
  [string]$Love = "C:\Program Files\LOVE\love.exe",
  [string[]]$Versions = @("crystal", "firered", "emerald", "platinum"),
  [string]$Driver = "tools/trailer/capture.lua",
  [int]$Voxel = 4,
  [string]$Only = "",
  [string]$Ffmpeg = "G:\Tools\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe",
  [string]$Format = "mp4",
  [switch]$ImportRom,
  [string]$SnapshotDir = "",
  [int]$Timeout = 3600
)
$ErrorActionPreference = "Stop"
# `-File` hands "a,b" over as one string
$Versions = @($Versions | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
New-Item -ItemType Directory -Force $Out | Out-Null
$roms = @{
  heartgold  = "Pokemon - HeartGold Version (USA).nds"
  soulsilver = "Pokemon - SoulSilver Version (USA, Australia).nds"
  black      = "Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds"
  white      = "Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds"
  platinum   = "Pokemon - Platinum Version (USA) (Rev 1).nds"
  emerald    = "Pokemon - Emerald Version (USA, Europe).gba"
  firered    = "Pokemon - FireRed Version (USA, Europe).gba"
  crystal    = "Pokemon - Crystal Version (USA).gbc"
}

foreach ($v in $Versions) {
  Write-Host "=== $v ($Driver) ==="
  $env:OUT = $Out.Replace("\", "/")
  $env:VOXEL = "$Voxel"
  $env:ONLY = $Only
  $env:FFMPEG = $Ffmpeg
  $env:FORMAT = $Format
  $env:POKEPORT_IDENTITY = $Identity
  $env:POKEPORT_VERSION = $v
  $env:POKEPORT_DRIVER = $Driver
  $env:SNAPSHOT_DIR = $SnapshotDir.Replace("\", "/")
  Remove-Item Env:POKEPORT_NO_MODS -ErrorAction SilentlyContinue
  Remove-Item Env:POKEPORT_IMPORT_ROM -ErrorAction SilentlyContinue
  if ($ImportRom -and $roms[$v] -and (Test-Path (Join-Path $repo $roms[$v]))) {
    $env:POKEPORT_IMPORT_ROM = (Join-Path $repo $roms[$v]).ToString().Replace("\", "/")
  }
  $log = Join-Path $Out "$v.$([IO.Path]::GetFileNameWithoutExtension($Driver)).log"
  Push-Location $repo
  try {
    # love.exe is a GUI-subsystem program: `&` would not wait for it
    $p = Start-Process -FilePath $Love -ArgumentList "." -WorkingDirectory $repo -NoNewWindow -PassThru `
      -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    if (-not $p.WaitForExit($Timeout * 1000)) {
      Write-Host "timed out after $Timeout s: stopping PID $($p.Id)"
      Stop-Process -Id $p.Id -Force
    }
  } finally {
    Pop-Location
  }
  Select-String -Path $log -Pattern "\[driver\]|\[recorder\]|driver error|^ERROR" | ForEach-Object { $_.Line }
}
Write-Host "footage in $Out"
