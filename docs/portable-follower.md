# Portable follower predicate

`world.follower.spawn(next, game, world)` controls whether the native optional
companion exists. It receives the original opaque Game/world handles in every
SDK mode. Return `next(game, world)` to keep the host's native decision, or a
Lua truthy/falsey result to enable/disable it. In particular, `0` and `""` enable
it; `false` and `nil` disable it. This is a lifecycle predicate, not a once-only
spawn notification: do not depend on a callback count per frame.

```lua
local mod = ...
if mod:supports("hooks", "world.follower.spawn") then
  mod.hooks:wrap("world.follower.spawn", function(next, game, world)
    if myOptions.companion then return true end
    return next(game, world)
  end)
end
```

The producer runs on native map entry and normal follower updates. A denial
removes the companion from its native update/draw lists; a later allowance
recreates it. Removing the wrapper restores the native predicate. Wrapper
errors retain the normal hook bus recovery rules, including keeping a
completed downstream decision after a post-`next` failure. API 3 repeated
`next` evaluates the downstream chain once per invocation.

## Native scope

- Gen 1 uses the existing Pikachu controller. The unchanged Yellow default
  still checks the starter event, healthy party Pikachu, biking/surfing and
  available artwork. Other GB games default to no follower. Existing scripted
  Yellow scenes retain their own update ownership.
- Gen 2 and GBA default to no companion. An allowance creates a passable native
  NPC which follows committed player steps; the ordinary world NPC loop owns
  its interpolation and rendering. Gold-family mid-map spawns start behind
  the player when walkable; map loads and GBA spawns start under the player.
  Connection carry preserves the NPC and buffered trail. GBA same-map long
  teleports reset the companion to the player. These optional companions do
  not enter Yellow's emotion/dialogue controller.
- DS reports the hook unavailable. Scripted escorts and HGSS's walking Pokemon
  keep their native controllers; this hook does not take ownership of them.

Artwork and actor internals are not normalized by this predicate. Gen2Recomped
uses `SPRITE_PIKACHU` when present, otherwise the player's sheet (then the native
placeholder fallback); each companion owns a renderer. The fallback never
writes a registry alias. The pinned Gen1 GBA controller instead leaves its
optional renderer to the mod. An artwork mod that imports or replaces private
controllers still needs a public artwork/actor contract before it is portable.
Yellow's existing native eligibility and scene mechanics also differ between
the engines; this PR preserves their defaults rather than changing them.

## Validation

The unchanged `examples/portable_follower` entry and manifest are loaded through
both real SDKs. Shared tests drive the real GB, Gold and GBA follower modules
and native NPC interpolation, with fixture assets/session data only. No fake
follower or hand-called Runtime hook substitutes for the native controllers.
The reference is a clean Gen1 checkout at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.

The checker covers Red/Blue/Yellow/Gold/Silver/Crystal/FireRed/Emerald in API 1
native, API 2 native/unified and API 3. Gen1 API 2 has no optional unified mode;
that comparison exercises Gen2's opt-in format against Gen1's native format.
Cases include native defaults, original handles, allow/deny, every interpolated
frame of a four-direction walk, map entry, GB/Gold connection carry/rebase, GBA
teleport, Lua truthiness, wrapper failure, removal, API-3 repeated `next`, and
failed-entry cleanup. These are controller/SDK contracts, not identical artwork,
Yellow scene parity or full-playthrough validation.

Gen2 unit tests additionally check every host version, DS exclusions, unrelated
NPC preservation, fallback rendering ownership, cast invalidation and legacy
SDK behavior.

```sh
luajit tests/engine/follower_spawn.lua
python3 tools/follower-contract-check/check.py --gen1 /path/to/clean/gen1 \
  --api 3 --format unified --report /tmp/follower-contract.json
```
