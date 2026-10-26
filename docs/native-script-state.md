# Native numeric script state and session schemas

The source-facing session now exposes numeric `flags` and `vars` maps. These
are typed views over the existing native save, not a second script store.
Reading a missing value does not allocate native state. Writes run the native
flag commands and variable writer, preserving flag events, live visibility,
edition-specific league aliases and derived object-graphics slots. Context
variables stay outside persistent session maps and snapshots; the special
range ends at 0x8014 in Kanto and 0x8015 in Hoenn.

Whole-map replacements validate every key/value and conflicting numeric/string
alias before any command runs. They preserve native-only named flags and
context variables. Session enumeration includes its existing scalar schema,
numeric state, detached playtime and presentation fields. Recursive copy code
can obtain an isolated flags/vars snapshot without borrowing native tables.
The session retires its maps when its game data, maps, save, edition or mod
loader changes, and on explicit release.

LuaJIT's Lua-5.1 `pairs` and `next` do not consult `__pairs`. `TableIteration`
installs dispatchers before the mod mutation journals open. Only registered
views opt in; ordinary inputs go to the original host functions, including
the host's own treatment of metatables. `pairs(view)` uses an owned snapshot.
Numeric maps implement `next(view, key)` through a typed native cursor, without
quadratic snapshot reconstruction or lending the native table. Deleting the
current variable while iterating keeps the underlying native cursor semantics.
Registry callbacks do not capture their own weak key.

Mutation-journal iteration is captured independently of later global wrappers.
Failed entry wrappers unwind before rollback iterates registries or calls
optional resource services. Native mods may wrap the iteration functions in
the usual forwarding style; rollback and teardown retain the infrastructure
and take back the mod's wrapper.

## Validation

```
luajit tools/script-stores/check.lua
luajit tools/script-stores/session-check.lua
```

The backend suite exercises all five editions through the real native command
implementations, compiler and runner. The session suite verifies live reads,
numeric writes, replacements, aliases, special-variable exclusion, ordinary
table semantics, weak-key lifetime, recursive copies, direct cursor mutation
and real SDK entry rollback with a native iteration-wrapper peer.

## Remaining scripting integration

This adds session schemas used by the forthcoming scripting-space bridge.
It does not supply `src.core.game3.scripting.space`, a replacement VM, symbol
catalogues, complete party/bag/storage schemas, detached preview construction
or all source event/field/battle/UI/audio services. The unchanged original
package still stops at the scripting-space import. Full renderer, five-edition
gameplay, native-mod coexistence and performance acceptance remain open.
QA uses isolated identities, preserves player data and keeps 8 GiB free.
