#!/bin/bash
# Regression: a residual (burn/poison/weather) faint in a Platinum DOUBLE battle
# must fill the empty slot at the end of THAT turn, not the next one.
# Seed 58 (trainer 290) used to leave both player slots empty with a living
# (Revived) bench mon and sit in the command menu forever.
#   CACHE=<usa platinum cache> bash tools/gen4_double_residual_faint_check.sh
cd "$(dirname "$0")/.." || exit 2
out=$(bash tools/gen4_battle_fuzz/run.sh --seed 58 --count 1 --mode all 2>&1)
echo "$out" | grep -E "^\[|battles:"
echo "$out" | grep -q "battles: 1  ok=1 error=0 hang=0" || { echo "FAIL: seed 58 hangs"; exit 1; }
echo "ok: residual-faint replacement"
