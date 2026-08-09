param(
  [string]$GoldRom = "Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
  [string]$SilverRom = "Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path $GoldRom)) {
  throw "Gold ROM not found: $GoldRom"
}
if (-not (Test-Path $SilverRom)) {
  throw "Silver ROM not found: $SilverRom"
}

$vendor = Join-Path $RepoRoot "tools\vendor"
$pokeRepo = Join-Path $vendor "pokegold"
$symbolsDir = Join-Path $vendor "symbols"

New-Item -ItemType Directory -Force -Path $vendor | Out-Null
New-Item -ItemType Directory -Force -Path $symbolsDir | Out-Null

if (-not (Test-Path $pokeRepo)) {
  git clone https://github.com/pret/pokegold.git $pokeRepo
}

Set-Location $pokeRepo
git fetch origin symbols
git checkout symbols
git pull --ff-only origin symbols

Copy-Item (Join-Path $pokeRepo "pokegold.sym") (Join-Path $symbolsDir "pokegold.sym") -Force
Copy-Item (Join-Path $pokeRepo "pokesilver.sym") (Join-Path $symbolsDir "pokesilver.sym") -Force

Set-Location $RepoRoot
python tools/make_gen2_manifest.py `
  --gold-rom "$GoldRom" `
  --silver-rom "$SilverRom" `
  --gold-symbols "tools\vendor\symbols\pokegold.sym" `
  --silver-symbols "tools\vendor\symbols\pokesilver.sym"

$verifyPy = @"
import json
from pathlib import Path

for f in ["tools/rom_manifest_gold.json", "tools/rom_manifest_silver.json"]:
  data = json.loads(Path(f).read_text(encoding="utf-8"))
  has_text = isinstance(data.get("text"), dict)
  print(
    f"{f} : symbols={len(data.get('symbols', {}))}, "
    f"embedded={'Embedded symbol addresses' in data.get('notes', '')}, "
    f"has_text={has_text}"
  )
"@

$verifyPath = Join-Path $env:TEMP "verify_gen2_manifest_symbols.py"
Set-Content -Path $verifyPath -Value $verifyPy -Encoding UTF8
python $verifyPath
Remove-Item $verifyPath -Force -ErrorAction SilentlyContinue

Write-Host "Gen2 symbol setup complete." -ForegroundColor Green
