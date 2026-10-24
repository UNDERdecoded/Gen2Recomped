# Portable AI-class definitions

API 3 exposes `mod.content.ai_classes` on Gen-1, Gen-2 and the registered
FireRed/Emerald profiles. Class `item` references use common names such as
`POTION` and `FULL_RESTORE`, resolved against the mounted item registry. Mods
do not need generation-specific `ITEM_018` or `ITEM_013` keys.

```lua
local mod = ...
if not mod:supports("content", "ai_classes") then return end
mod.content.ai_classes:register("MY_CLASS", {
  kind = "class", uses = 2, chance = 256, item = "POTION",
})
```

`register`, `override` and `patch` translate an optional `item` before recording
the native operation and return a detached record with its common item name.
Unknown item names return `nil, reason` without recording that operation;
non-finite numbers and cyclic records are errors. Native schema, duplicate-ID
and dangling-reference checks still apply. `override` replaces the definition,
whereas `patch` preserves omitted fields. Use `mod.DELETE` in a patch to remove
the optional item. `remove` retains the ordinary registry behavior.

`get` and `each` also return detached records. Editing these copies cannot
change the runtime AI class. Use registry operations during mod entry to
author definitions; writes freeze after loading, and a failed entry rolls its
operations back. Functions in `kind = "brain"` records retain their callable
identity; copying a record does not sandbox a callback's captured state.

Gen2Recomped also applies this boundary to API 2 mods explicitly opting into
`content_format = "unified"`. The shared reference contract is **Gen1Recomp
API 3**, compared with Gen2Recomped API 3 and API 2/unified. Gen1Recomp's API-2
AI-class passthrough exposes live records even with that manifest field; this
PR does not claim equal API-2 read-aliasing behavior on both engines. Native
API-1/2 content formats retain their existing physical item keys and handles.

This aligns definition records, not the native battle policies that consume
them. It does not enable `battle.enemy_switch_or_item`, add new writable
trainer fields, or establish identical brain execution and enemy item/switch
decisions. Those runtime contracts require separate native tests.

`tests/engine/unified_content.lua` covers resolution, detachment, refusal,
rollback, dangling references, deletion and native formats. The unchanged
`examples/portable_ai_class_content` consumer is exercised through both real
SDKs by [the shared checker](../tools/ai-class-content-contract-check/README.md).

For actual imported data, install the example in an isolated test identity:

```sh
POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/ai_class_content.lua \
  bash scripts/run-portability-test.sh
```

The driver checks mod load, common/native item resolution, detached records
and frozen writes at the title and after an in-memory New Game. It supports
Red, Gold, FireRed and Emerald. It does not execute a normal SAVE action,
battle decision, complete playthrough or fresh full-ROM import.

## Validation

The isolated feature passes **442/442** unified-content checks and **670/670**
loader checks. Each SDK comparison mode passes **16 workers / 56 paired
observations** against the clean reference above. The unchanged #173 parent
fails the same public consumer in Gold and FireRed with an unresolved item
reference, providing a negative control.

The complete feature run passes **139/149** engine suites, **3/3** SDK suites
and B30. Its 26 FAIL lines exactly match the predecessor's ten baseline
failure suites; the separate repair PRs #128–134 are not part of this feature
branch. Native LÖVE 11.5 checks pass for imported Red, Gold, FireRed and
Emerald at title and in-memory New Game, within the metadata scope above.
The installed temporary example was removed after verifying its file hashes.
