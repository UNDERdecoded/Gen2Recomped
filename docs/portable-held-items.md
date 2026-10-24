# Portable held-effect decisions

`held_item.trigger(next, ctx)` wraps a native held-effect **read** on Gen 2/3
hosts. It lets a mod suppress an effect, substitute another `HELD_*` name, or
change its parameter. Native code still owns rolls, damage/healing, messages,
item consumption and battle queues. GB/DS report this seam unavailable.

```lua
local mod = ...
if mod:supports("hooks", "held_item.trigger") then
  mod.hooks:wrap("held_item.trigger", function(next, ctx)
    if ctx.item == "LEFTOVERS" and ctx.trigger == "residual" then
      return "HELD_BERRY", 7
    end
    return next(ctx)
  end)
end
```

Use API 3 for common item/Pokemon IDs. The unchanged
`examples/portable_held_item` consumer also runs through legacy/native and
API-2 unified adapters. Legacy IDs and other engine objects retain their
native representations. An opaque `ctx.battle` is the actual controller;
`ctx.mon` is the holder's Pokemon. Constructors, external/link battlers and
replacements bind to their current battle without adding a public engine
handle to Pokemon records.

The context also has `item`, `def`, `effect`, `parameter` and `trigger`.
`def` is absent for an empty hand; an ordinary held item with no native effect
still has a definition. The public effect names include `HELD_BERRY`,
`HELD_LEFTOVERS`, `HELD_QUICK_CLAW`, `HELD_BRIGHTPOWDER`, `HELD_FOCUS_BAND`,
`HELD_FLINCH`, `HELD_CRITICAL_UP`, `HELD_HEAL_*` and the `HELD_*_BOOST` family.
GBA's Scope Lens and pinch-critical berry remain distinct (`HELD_CRITICAL_UP`
and `HELD_PINCH_CRITICAL_UP`). All 66 GBA native enum names are covered.

`next(ctx)` returns `ctx.effect, ctx.parameter`. A non-string effect suppresses
it. An omitted/non-numeric parameter falls back to the native parameter; zero
is meaningful and is preserved. Mutating `ctx.effect` / `ctx.parameter` before
`next` is supported. GBA probability parameters for Quick Claw, BrightPowder,
Focus Band and King's Rock use the common byte scale: the view is
`floor(nativePercent * 256 / 100)`. An unchanged forwarded pair retains its
exact native percentage; changed odds clamp to 0–256 before converting back.
Other native parameter meanings remain generation-specific.

Native comparison reasons include `priority`, `damage`, `endure`, `flinch`,
`accuracy`, `confuse`, `residual` and `check`. Gold also uses `status` for
immediate cures and `pp` for MysteryBerry; GBA escape uses `run`. A read is not
an activation event: calls may repeat and an effect can be ineligible after
it is read. Filter by the actual item/effect and trigger rather than counting
calls. Field/party scans are not battle hook producers.

API-3 definition scalar metadata retains the reference's transaction behavior.
`def.id` uses the common item identity; `def.heldEffect` / `def.heldParameter`
use the public names/parameters. Valid changes are visible to downstream
callbacks. Gold writes to its live item definition, so those metadata changes
persist; GBA supplies a temporary info record and discards them after the read.
The already captured `ctx.effect` is independent of definition edits. Use the
returned pair to steer the current comparison and `mod.content` for deliberate
content changes. Native diagnostic snapshots are not a portable write surface.
Invalid transactional definition edits cannot partially commit Pokemon edits.

No subscriber means no hook dispatch or context construction. Unsubscribe and
entry rollback restore native reads. Wrapper errors retain normal bus recovery;
API-3 repeated `next` calls reuse both downstream results.

## Native integration and boundaries

The hook is wired through the actual priority, critical/type/stat damage,
accuracy, lethal-hit endurance, King's Rock, confusion, PP and residual readers.
GBA also reads it for Macho Brace speed, Shell Bell, held escape, entry prize
multipliers and White Herb. Gold Focus Band now reaches the direct-damage
path, including a holder already on 1 HP. Gold's Berry threshold is strictly
below half HP, matching the reference; GBA retains at-half activation. The GBA
100%-accuracy shortcut no longer bypasses a held accuracy reduction.

This is a held-read contract, not complete native battle equivalence. Other
move/rule differences and GBA's full Choice Band locking remain separate work.
The GBA host now separates selective move-end cures/White Herb from normal
item checks. After a completed action it retries the normal scan up to four
times, restarting at the first slot after each successful activation. Called
moves do not add another action sweep; spread moves finish all targets first.
Queued switch-in abilities complete before their normal item sweep. Leftovers
is eligible only in the regular end-of-turn phase.

The GBA residual path orders Wish before weather, then Ingrain, abilities,
items, Leech Seed and status damage per battler. The post-residual item sweep
precedes Future Sight/Perish Song and the public field-residual hook. Weather
uses all active slots and the GBA sixteenth-max-HP chip; Leech Seed uses its
current source slot, eighth-max-HP drain and Liquid Ooze. Pinch berries respect
stage caps and existing Focus Energy; Leppa restores only up to the move's PP
cap. These changes do not replace the GB/Gen2/DS turn loops.

The formerly unequal unrestricted 7-HP Berry fixture now heals **35 HP on both
engines**, with six residual reads. Native move/called/spread, PP, cure-before-
poison, Ingrain, Wish/weather, Seed/status, speed-order and four-slot cases run
through the same consumer and native handlers. The strict checker compares
both the raw HP result and read count and is required by CI. This proves the
listed item phases, not all battle rules: Choice Band locking, deferred
ability interactions, Quick Claw turn-RNG ordering and further volatile rules
still need their own cross-engine coverage.

## Validation

```sh
luajit tests/engine/held_item_contract.lua
luajit tests/engine/held_item_authority.lua
python3 tools/held-item-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified \
  --report /tmp/held-item-contract.json
```

The reference is clean and pinned to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Gold/Silver/Crystal and
FireRed/Emerald run the same consumer via real SDKs and native held readers,
actual native moves/order, and registered residual code. The producer and
native effect handlers are not replaced or dispatched manually. Extractor-
shaped fixture items also cover all 66 GBA enums through the actual item-data
fallback reader. Four SDK modes are compared; Gen1 API 2 has no unified opt-in,
so that comparison uses its native callback.

The host suites additionally cover registered generations, replacement/link
binding, no-mod/entry rollback, byte-odds clamping, field/party isolation and
metadata transactions. `tests/drivers/held_item.lua` checks the installed public
consumer against imported Gold/FireRed/Emerald in isolated LÖVE: native
FIGHT/move input and result queues, HP/consumption, endurance and GBA entry/RUN.
It starts New Game and constructs bounded in-memory battles; it is not a full
playthrough or cross-engine pixel-equivalence proof.
