# pack-windows.ps1
$ErrorActionPreference = "Stop"

# --- edit these if needed ---
$LoveDir    = "C:\Program Files\LOVE"
$ProjectDir = "G:\Github Desktop\0.7.0\Gen2Recomped"   # ← single source of truth
$ExeName    = "Gen2Recomped.exe"
$OutZip     = Join-Path $ProjectDir "Gen2Recomped-windows.zip"
# ----------------------------

Set-Location $ProjectDir

# =========================================================
# 1. Build game.love
# =========================================================
$stage = Join-Path $env:TEMP "g2love-pack"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item $stage -ItemType Directory | Out-Null

Copy-Item main.lua, conf.lua $stage
Copy-Item -Recurse src, data, assets $stage

# Strip generated ROM caches
Remove-Item "$stage\data\generated" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$stage\assets\generated" -Recurse -Force -ErrorAction SilentlyContinue

# Tools needed at runtime
New-Item "$stage\tools" -ItemType Directory | Out-Null
Copy-Item -Recurse tools\save-editor "$stage\tools\"

$manifests = @(
    "rom_manifest.json",
    "rom_manifest_blue.json",
    "rom_manifest_yellow.json",
    "rom_manifest_gold.json",
    "rom_manifest_silver.json"
    "rom_manifest_crystal.json"
)
foreach ($m in $manifests) {
    $src = "tools\$m"
    if (-not (Test-Path $src)) { throw "Missing $src" }
    Copy-Item $src "$stage\tools\"
}

$love = Join-Path $ProjectDir "game.love"
if (Test-Path $love) { Remove-Item $love -Force }

Compress-Archive -Path "$stage\*" -DestinationPath "$love.zip" -Force
Rename-Item "$love.zip" $love
Remove-Item $stage -Recurse -Force

Write-Host "Built: $love  ($((Get-Item $love).Length) bytes)"

# =========================================================
# 2. Fuse love.exe + game.love → Gen2Recomped.exe
# =========================================================
$LoveExe = Join-Path $LoveDir "love.exe"
$ExePath = Join-Path $ProjectDir $ExeName

if (-not (Test-Path $LoveExe)) { throw "love.exe not found: $LoveExe" }
if (-not (Test-Path $love))    { throw "game.love not found: $love" }

cmd /c "copy /b `"$LoveExe`" + `"$love`" `"$ExePath`""

if (-not (Test-Path $ExePath)) { throw "Fusion failed" }
Write-Host "Fused: $ExePath  ($((Get-Item $ExePath).Length) bytes)"

# =========================================================
# 3. Package with DLLs
# =========================================================
$packStage = Join-Path $env:TEMP "gen2recomp-win-pack"
if (Test-Path $packStage) { Remove-Item $packStage -Recurse -Force }
New-Item -ItemType Directory -Path $packStage | Out-Null

Copy-Item $ExePath -Destination (Join-Path $packStage $ExeName)
Copy-Item (Join-Path $LoveDir "*.dll") -Destination $packStage -Force

$license = Join-Path $LoveDir "license.txt"
if (Test-Path $license) {
    Copy-Item $license -Destination $packStage
}

if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
Compress-Archive -Path (Join-Path $packStage "*") -DestinationPath $OutZip -Force
Remove-Item $packStage -Recurse -Force

Write-Host "OK: $OutZip"
Write-Host "Contents:"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::OpenRead($OutZip).Entries | ForEach-Object { $_.FullName }