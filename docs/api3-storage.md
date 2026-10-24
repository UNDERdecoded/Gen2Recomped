# API-3 playthrough storage

API 3 uses the Gen1Recomp public `mod.storage` contract: data-only records and
opaque bytes belong to a mod, a game version and an opaque playthrough identity.
The handle contains only `context`, `selected`, `read`, `write`, `readBytes`,
`writeBytes`, `list` and `delete`; private paths and mutable engine objects are
not exposed. The transactional implementation follows the pinned Gen1Recomp
`Storage.lua` at `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.

```lua
local mod = ...
local context, code = mod.storage:context(mod.game)
if context then
  local state, reason = mod.storage:read(mod.game, "progress/visited")
  if not state and reason == "not_found" then state = { maps = {} } end
  -- Other errors require handling; they do not mean an empty namespace.
end
```

`context(game)` returns `engineVersion`, `gameVersion` and `playthroughId`.
The identity is opaque, stable across normal save/load and independent of
slot names. A new game has a distinct requested identity; duplicate imported
slots receive distinct scopes. The engine allocates it lazily without consuming
gameplay RNG. Unused vanilla saves remain identity-free. Legacy backfill writes
routing metadata to options; requesting storage alone does not rewrite normal
progress. The next ordinary save stamps the identity into its metadata.

Records must be serializable data tables. Bytes are strings, including empty
strings and NULs, up to 512 MiB per key. Keys use nonempty letters/numbers/dash/
underscore segments separated by `/`. Absolute paths, `..`, dots, empty segments
and backslashes are rejected. A key cannot change between records and bytes
until explicitly deleted. Lists are sorted, de-duplicated logical keys; a prefix
selects an exact key or a directory. Reads return decoded copies.

Writes stage and verify data, retain a verified backup, replace and verify the
main copy, then remove the staging file. Reads recover from valid staging or
backup data. Reads return `nil, code, message` on failure; writes/deletes return
`false, code, message`. Important codes include `not_found`, `invalid_key`,
`encode_failed`, `type_conflict`, `type_mismatch`, `write_failed`, `verify_failed`,
`storage_unavailable` and `not_in_playthrough`. Recovery is best-effort; this is
not a multi-key transaction or a concurrent-writer database.

## Selected storage at the title

`mod.storage:selected(mod.game)` is available only while a native TitleState is
in the stack. It resolves the engine-selected durable playthrough without
allocating a new identity. The returned handle binds that scope:

```lua
local selected, reason = mod.storage:selected(mod.game)
if selected then
  local context = selected:context() -- may include normalSavedAt
  local state = selected:read("progress/visited") -- no game argument
end
```

The title handle offers the same read/write/list/delete methods without a game
argument. Returned contexts are detached copies; callers cannot reroute the
bound handle by changing them. Init-time reads against a fresh boot skeleton
cannot replace an existing real save's selection. A successfully committed
normal save is authoritative if a later options update fails. Merely browsing
a fresh title without durable state reports `no_selected_playthrough`.

## Existing Gen2 mods and cache data

API 1/2 retain the existing `src.mods.Storage` behavior and `modstorage/` data
unchanged. API 3 uses a separate playthrough namespace. No automatic copy guesses
which save owns an old installation-wide payload. ROM-derived, reproducible
assets belong in the existing `mod.cache` service. Authors upgrading a legacy
mod must explicitly export/migrate authored bulk state while using its old API,
or rebuild derived caches through their dedicated cache/import service. Changing
the manifest to API 3 does not automatically assign old shared records to a save.

## Verification

The unchanged API-3 example runs through real SDKs for the eight games both
engines support: Red/Blue/Yellow, Gold/Silver/Crystal, FireRed and Emerald.
Shared checks cover data/byte transactions, isolation, recovery/failures,
listing, title handles and native New Game/save/load. Gen2 additionally tests
all fifteen supported hosts and slot promotion, boot skeletons, duplicate slot
imports, failed saves, deletion, legacy API retention and RNG independence.
These are ROM-free persistence/controller contracts; native cartridge smoke
tests are separate and do not establish full playthrough compatibility.

```sh
luajit tests/engine/api3_storage_transactions.lua
luajit tests/engine/api3_playthrough_storage.lua
python3 tools/storage-contract-check/check.py --gen1 /path/to/gen1 \
  --report /tmp/storage-contract.json
```
