#!/bin/bash
# Run the Platinum battle fuzzer (see main.lua for the options).
#   bash tools/gen4_battle_fuzz/run.sh --seed 1 --count 200 --mode all
# CACHE  = the imported Platinum cache folder (the one holding assets/ and data/)
# LOVE   = lovec.exe
CACHE="${CACHE:-$APPDATA/LOVE/Gen2Recomp/platinum}"
LOVE="${LOVE:-C:/Program Files/LOVE/lovec.exe}"
export POKEPORT_DATA_DIR="$CACHE/data/generated"
export POKEPORT_ASSET_ROOT="$CACHE"
export POKEPORT_IDENTITY="${POKEPORT_IDENTITY:-pl_battle}"
cd "$(dirname "$0")/../.." || exit 2
"$LOVE" tools/gen4_battle_fuzz "$@" 2>&1 | grep --line-buffered -v -E "^\[(info|warn|debug)\] "
exit "${PIPESTATUS[0]}"
