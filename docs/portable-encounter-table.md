# Portable encounter preview transforms

`encounter.table(next, dist, ctx)` transforms the distribution returned by
`mod.world:effectiveEncounters(mapId, terrain, opts)`. It is available on
Gen1–3 hosts. DS retains its existing query and reports this hook unavailable.

```lua
local mod = ...
if mod:supports("hooks", "encounter.table") then
  mod.hooks:wrap("encounter.table", function(next, dist, ctx)
    local result = next(dist, ctx)
    -- Report a custom distribution to this explicit-map preview.
    if ctx.preview and myOptions.showCustomTable then return { MEW = 7 } end
    return result
  end)
end
```

This is a **preview-only** contract, matching Gen1Recomp's existing native
producers. It does not change actual wild encounters. Their existing
`encounter.roll` and `encounter.species` seams remain separate. A future live
table-transform contract would need producers and tests on both engines.

`dist` maps public species IDs to raw weights. Weights are not percentages;
the native span is 256 on GB and 100 on Gold/GBA. Duplicate species are
aggregated before the hook. `ctx` contains the queried `mapId`, `terrain` and
`preview = true`. The GBA producer additionally forwards `opts`; GB/Gold do
not. There is no Game, overworld or RNG handle in the context. Map IDs retain
their dataset-specific identity.

A table return replaces the preview distribution; an empty table is a valid
replacement. Nil or any non-table result preserves the producer's detached
map. `next` returns a distribution, not the whole `{chance, dist}` record.
The native rate `chance` is independent and cannot be replaced by this hook.
A known map without a native table still calls the hook with `{}` and zero
chance. GBA includes native slot weights at zero rate; GB/Gold return empty
weights at zero rate, matching their respective reference producers.

The producer creates fresh distributions per query; changing callback weights
cannot persist into the imported encounter tables. The engine itself does not
roll RNG, load a map or change the save. Installed callbacks execute mod code
and can have their own side effects. Wrapper errors retain normal hook-bus
recovery; API 3 repeated `next` calls reuse downstream results. Unsubscribe and
failed-entry rollback remove the callback.

API 3 aliases `indoor` to `grass` before the native callback. Its only query
option is `daytime = "MORN" | "DAY" | "NITE" | "DARK"`, supported on Gen 2;
`DARK` selects night. Other generations accept nil/empty options. Invalid
API-3 options are rejected before callback dispatch. Legacy Gen2Recomped time
aliases and its additional legacy indoor query remain available; the pinned
Gen1 legacy Gold facade accepts grass/water, so portable legacy consumers use
those terrain names. Gen1 API 2 has no unified opt-in mode.

The shared ROM-free suite runs the unchanged public example through both
real SDKs and `mod.world` facades on Red/Blue/Yellow, Gold/Silver/Crystal,
FireRed/Emerald in four SDK modes. It covers base land/water/indoor queries,
time selection, replacement and in-place changes, empty/zero-rate tables,
non-table fallback, errors before/after next, unsubscribe, rollback and genuine
no-mod filesystems. Native tests also verify DS exclusion, preserved native
rolls and unchanged native data/save state. No fake Runtime dispatch or
replacement WorldAPI is used.

```sh
luajit tests/engine/encounter_table_preview.lua
python3 tools/encounter-table-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified \
  --report /tmp/encounter-table.json
```

The reference is pinned to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Gen1 also has LeafGreen, Ruby and
Sapphire profiles; Gen2Recomped currently does not register those versions.
The fixture refuses unregistered versions instead of silently testing Red.
These checks prove the public preview boundary, not full playthroughs,
identical native RNG algorithms or all encounter-mechanic parity.
