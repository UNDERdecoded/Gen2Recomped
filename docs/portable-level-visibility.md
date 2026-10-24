# Portable Pokémon level visibility

`pokemon.level_visible` lets a mod hide the native level label and digits
without replacing a battle, party or summary screen. It uses Gen1Recomp's
existing GB/GBA contract:

```lua
local mod = ...
if mod:supports("hooks", "pokemon.level_visible") then
  mod.hooks:wrap("pokemon.level_visible", function(next, mon, context)
    if context.where == "battle.enemy" then return false end
    return next(mon, context)
  end)
end
```

The default is `true`; only a first return value of literal `false` hides the
label. `nil`, `0` and other values leave it visible. A caller only asks where
the native screen would otherwise print a level. The decision can be queried
several times per frame and should be deterministic and free of side effects.
Unsubscribing or unloading the mod restores the native display.

`context.where` is one of `battle.enemy`, `battle.player`, `party`, or `summary`.
The native callback receives the actual Pokémon and `{where, game}`. Gen2's unified
API 2 and the common API 3 use their existing Pokémon/context record adapters, including
normal ID conversion, `next` forwarding, validation and failure recovery. API 3
is recommended for portable consumers. The Game value is an engine handle;
Gen1's unified context can expose a forwarding view while Gen2 retains the
native handle. Consumers should not inspect engine-private Game fields.

The native call sites cover Gen2Recomped's Gen1/2 games (including Prism and
Polished Crystal) and FireRed/Emerald. Classic and wide GB healthboxes, GBA
single/double healthboxes, party rows and summary variants use the same hook.
GB summaries also omit the printed next-level number and its `TO` word/arrow.
Status/faint labels, egg eligibility, names, HP, EXP values/bars, and historical
met-level text retain their native behavior. GBA move-detail pages retain their
existing level eligibility. The level, stats and progression are not changed by
hiding their display.

The DS renderers are outside this change. `supports` returns `false` for
Gen4/5; accepting the API-3 hook name alone is not a support claim.

## Validation

The unchanged example in `examples/portable_level_visible` is loaded by both
engines' actual SDKs. The checker pins a clean Gen1 reference at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36` and compares Red, Yellow, Gold,
FireRed and Emerald in native API 1/2 and API 3. Gen2's additional unified API 2
mode is compared against Gen1's native API 2: Gen1 does not implement the
`callback_format` manifest extension. API 3 is the common unified contract.
Workers compare
native battle level omission/restoration and all four predicate contexts. The
Gen1 GBA worker uses Healthbox's intact private level producer with a native
session context; GB and Gen2 GBA workers invoke native HUD methods. Only
font/tile leaves are recorded.

```sh
luajit tests/engine/level_visible.lua
luajit tests/engine/level_visible_contract.lua
luajit tests/engine/level_visible_renderers.lua
python3 tools/level-visible-contract-check/check.py --gen1 /path/to/gen1 \
  --api 3 --format unified --report /tmp/level-visible.json
```

Gen2 renderer tests exercise actual party/summary draw methods and native
healthbox variants across every supported version and SDK mode. They check
labels and digits together, status/egg eligibility, per-side hiding, level 100,
next-level arrows, native context, restoration, and a distinct doubles partner.
Leaf-spy tests disable JIT compilation only for the HUD function whose captured
leaf is replaced through debug upvalues. Predicate and SDK behavior remain
covered separately. CI also runs the pinned Gen1 Gen2/Gen3 native hook suites
unchanged. These are ROM-free draw-command and behavior tests, not GPU pixel
goldens or full cartridge playthroughs.
