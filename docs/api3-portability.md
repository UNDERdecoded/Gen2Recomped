# Shared API 3 entry

Use the same manifest and entry file on Gen1Recomp and Gen2Recomped:

```json
{
  "id": "portable_example",
  "name": "Portable Example",
  "version": "1.0.0",
  "api": 3,
  "games": ["gen1", "gen2", "gen3"],
  "entry": "main.lua"
}
```

```lua
local mod = ...
if mod.content.moves:has("TACKLE") then
  local ok, reason = mod.content.moves:patch("TACKLE", {power = 45})
  if not ok then mod.log:warn("%s", reason) end
end
```

Create a portable starter with:

```sh
python3 tools/modkit.py scaffold portable_example --api 3
```

It generates the shared games list and a guarded canonical move patch. It
omits an engine-release range because Gen1 and Gen2 have independent engine
version numbers. The default scaffold remains API 2 with its existing range
and profile templates. The `--api` value is now honored instead of silently
emitting API 2 for every value.

API 3 automatically selects unified content, callbacks and portable scripts.
No `content_format`, `callback_format` or `script_format` fields are needed.
An explicit `"native"` for one of those fields is an error under API 3;
`"unified"` is accepted. API 1/2 retain native defaults, and API 2 retains
its existing individual opt-ins. The engine advertises `Version.modApi = 3`.
A higher unknown API remains a load error.

This is a common entry and a tested compatibility subset, not a claim that
all of Gen1Recomp's services have been ported. It builds on PRs #90–#99.
The existing unified-content limitations still apply: unsupported writes
return `nil, reason` before recording an operation, native diagnostics are
read-only, and ordinary schema errors raise an attributed load error.
Entry failure rolls back the mod's content and subscriptions. Content is
frozen after loading.

## Public contracts

Core `pokemon`, `moves`, `items`, `trainers` and `encounters` handles use the
existing unified adapters. Other registries retain their native record
shapes, rather than inventing canonical fields. Every content handle exposes
`has(id)`, `supports()` and `available`. API-3 passthrough reads and iteration
return detached values too; change data through the write methods.

The API-3 Pokemon boundary uses short statuses (`SLP`, `PSN`, `BRN`, `FRZ`,
`PAR`, `TOX`), nickname-first display names and a common Special alias.
Writing `stats.special` in a writable callback sets both later Special stats;
contradictory split values are rejected before commit. API-2 unified status
names and callback behavior are unchanged. DVs/shiny presentation is read-only
in the callback boundary. Party and battle reads remain detached snapshots.

Capture `mod.world` and `mod.battle` at entry time. World methods can be called
before Game exists and return `nil, reason`; reading the facade never boots
Game. The same world handle follows the loader's current Game/save instead of
retaining an earlier one. Battle snapshots and intents retain their existing
revision/replay validation.

The common world calls currently enabled for generations 1–3 are:

- `overworld`, `current`, `party`, `activeBlockAt`, `liveMaps`, `mapOverview`,
  `effectiveEncounters`;
- `canReorderParty`, `reorderParty`, `availableFieldActions`, `useFieldAction`,
  `canFly`, `flyTo`;
- `getFlag`/`setFlag` for private `mod:<key>` boolean flags;
- `queueScript` for the existing bounded portable script language.

Check `mod:supports("world", name)` before relying on a call. The other
Gen1 world method names remain callable but explicitly return
`nil, "unsupported: ..."`: warp/object/block mutations, runtime NPC operations,
`startWildBattle` and `invalidateMap` have not yet been verified against the
Gen1 API-3 contract. Their native/API-2 counterparts are unaffected. Native
symbolic flag mappings and `mod.datasets:open` are also explicitly unavailable.
Gen4/5 do not claim the shared world surface in this first entry PR.

Private flags use `save.modData[modId].worldFlags`, independently of native
flags and other mods. A read does not create a bucket. Clearing removes the
stored key. A change emits `flag.changed` with
`name = "mod.<modId>.<key>"` and the boolean value; setting the same value
emits nothing. Invalid save stores are refused without overwriting them.

Gen1 API-3 callback names from the pinned reference are recognized even when
this engine has no call site for them. Registration is allowed; availability
still requires a native call site in the selected version. For example,
`battle.caught_marker_visible` can be subscribed to but reports unavailable here. Unknown
names remain errors. An accepted subscription is not proof that a feature
runs. Source-specific engine handles in lifecycle/UI payloads remain native.

For scripts, use `mod:supports("scripts", verb)` to test Gen2Recomped's current
bounded vocabulary. A `queueScript` method does not imply support for every
Gen1 script verb. See [portable world scripts](portable-world-scripts.md).

## Reproducible contract checks

```sh
luajit tests/engine/api3_entry.lua
luajit tests/engine/api3_compat.lua
python3 tools/api3-contract-check/check.py \
  --gen1 /path/to/clean/pinned/gen1recomp --lua luajit \
  --report /tmp/api3-contract-report.json
```

The external reference must be a clean checkout at
`bryanthaboi/gen1recomp@79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.
Use a separate checkout; do not reset a working installation. No Gen1 engine
implementation is vendored into this repository. Only public callback names
are recorded as a compatibility catalog.

The exact same manifest and mod entry run on both engines for Red, Blue,
Yellow, Gold, Silver, Crystal, FireRed and Emerald, in both success and
intentional-rollback cases. Each engine/version/case has its own LuaJIT
process. The shared harness constructs native-shaped synthetic datasets;
the mod fixtures contain no engine imports or engine-specific branches.
The runner also generates an API-3 mod through the real scaffold CLI and
loads those same generated files on both engines for each version. This adds
eight comparisons to the sixteen normal/rollback cases: 24 comparisons and
48 isolated loader runs. It compares JSON projections of public results and
records hashes of both shared and generated fixture files. It refuses a different or modified reference.

Coverage includes canonical content reads/writes/iteration and native merge
results, detached core and passthrough reads, callable early handles, later
Game replacement, party fields, private flags, Gen1 battle snapshot/invalid-intent boundaries, callback payloads and native
writeback, custom events, unsupported-name handling, frozen content and failed
owner cleanup. Separate Gen2 tests check API-1/2 behavior, contradictory
manifest fields, honest availability and malformed flag stores. CI pins the
same external commit and uploads the report.

These are ROM-free loader/runtime-boundary tests, not retail-ROM gameplay
or a proof of every exposed native callback's payload. Native action details
remain covered by the prerequisite PR suites. Extend these shared fixtures
whenever another API-3 service becomes portable; do not make a failing
comparison pass by changing only one engine's mod fixture.
