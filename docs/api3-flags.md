# API-3 native and private flags

`mod.world:getFlag(reference)` returns a boolean or `nil, reason`.
`setFlag(reference, boolean)` returns `true` or `nil, reason`. Real booleans are
required. The facade follows the current Game/save without bootstrapping one.
Flag reads/writes require a save but can run during menus/scripts; they do not
start an idle-world action. Writes from a rolled-back/reloaded/unloaded owner
are retired. Gen4/5 remain outside the shared API-3 world surface.

## Private flags

`mod:<key>` and `mod.<this-mod-id>.<key>` address the same private flag in
`save.modData[modId].worldFlags`. A foreign `mod.<other-id>.*` reference is
refused. Keys are nonempty strings up to 256 bytes without control characters.
A read does not create storage. A clear removes the key. Malformed stores are
refused without overwriting them. The existing change-only `flag.changed`
payload remains `{name="mod.<modId>.<key>", value=boolean}`.

## Cartridge flags

| Version | Public references | Host storage |
| --- | --- | --- |
| Red/Blue | Known event symbol or its named bit index | Existing `EVENT_*` save.flags key |
| Yellow | Yellow event symbol or its named bit index | Existing `EVENT_*` save.flags key, with Yellow's own bit catalog |
| Gold/Silver | EVENT symbol or whole bit index 0–2047 | `EVENT_G2_%04d`, as used by the VM/save converter |
| Crystal | Whole bit index 0–2047 | Same native numbered namespace; symbolic references explicitly decline, matching the pinned Gen1 API |
| FireRed/Emerald | Known native flag symbol/alias, or a named numeric flag in that version's range | `FLAG_G3_%04X`, as used by the VM/save converter |

Native IDs/symbols are cartridge-specific; no equivalence between the same bit
number in different games is invented. Unknown, fractional, non-finite,
negative, malformed or out-of-range references decline before writes. Special
variables are not a new flag namespace. Prism/Polished Crystal native mappings
are not guessed from Gold; private flags remain available there.

Clearing a native host flag retains `false`, matching native object visibility's
distinction between "cleared" and "untouched". Gen3 synchronizes active object
templates carrying that exact native flag through the host's targeted native
visibility entry; unrelated actors/templates are left alone. Native failures
there can happen after the flag write and are not transactional rollback.

Native `flag.changed` fires only on a true boolean transition. Its name is the
Gen1 symbol, Gen2 bit number, or Gen3 version-catalog name (falling back to the
numeric ID); Gen3 also provides `id`. For Gen3 cross-engine listeners, use
`event.id` for native identity: the pinned Gen1 implementation's native emitter
uses its base FireRed name catalog even on Emerald, so `event.name` is not a
portable label there. The shared fixture consumes `event.id or event.name` on
both engines. This preserves meaningful native identity rather than claiming
all label strings are identical. Reentrant writes from an API-3 flag event or
native visibility callback decline with "world is busy"; reads remain usable.

## Catalog provenance and verification

Generated Red/Yellow/FireRed/Emerald identifier catalogs contain names/numbers
only. No Gen1 engine implementation or ROM is vendored. Gold/Silver reuse the
host's existing Gen2Flags table. The reference is pinned to clean
`bryanthaboi/gen1recomp@79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.

```sh
luajit tests/engine/api3_flags.lua
python3 tools/flag-catalog-check/generate.py --gen1 /clean/pinned/gen1 --lua luajit
# Add --write to regenerate the deterministic catalogs.
```

The provenance checker verifies every generated row and all 1235 pinned Gold
symbol mappings against the host. CI checks provenance alongside the shared
mod suite. Eight identical public-only mod cases bring that suite to
72 comparisons / 144 isolated loader runs; compare preflight, numeric/symbolic
aliases, booleans, no-op event suppression, public event identity/value and
private ownership. The reference uses actual flag backends with synthetic
world/store setup.

Local checks cover every shipped catalog alias/named numeric entry, the Gen3
VM key conversion and all 2048 Gen2 bits, plus malformed inputs/stores,
owner retirement, reentry and scoped visibility dispatch. These are ROM-free
runtime/store tests, not cartridge story progression or visual gameplay tests.
