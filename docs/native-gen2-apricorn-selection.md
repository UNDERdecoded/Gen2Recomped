# Native ApricornBalls and Kurt selection

The GSC importer reads the actual `ApricornBalls` pairs in cartridge order,
retaining native apricorn/ball item IDs and row indices. A single `$ff` ends
the table. Missing symbols leave no invented recipe data; explicit empty or
malformed/truncated tables never fall back to retail rows. Reads are bounded
and cannot cross a cartridge bank boundary. The map-script output includes
recipe records and completeness metadata. Stock Gold/Silver/Crystal cache
markers require reimport; other edition markers are unchanged.

Kurt's actual native special now consumes the imported order, including
cartridge-specific table changes. Historical stock caches retain the original
native item order85/89/92/93/97/99/101 until reimport, without fabricating their
missing ball mappings. The earlier colour-based fallback reordering was
incorrect and is corrected here; the ROM-table import itself was unaffected.

Gold/Silver take one apricorn without opening a quantity menu. Crystal asks
for quantity, including a one-item stack; cancelling quantity returns to the
apricorn list with its cursor retained and consumes nothing. An explicit
CANCEL row and bounded scrolling retain access to the complete list. The
quantity is capped at99 and the native inventory is rechecked before removal,
so a changed bag cannot mint a paid job. Unreviewed hack layouts retain their
previous quantity-cancel protocol and are not given a guessed table import.

The native script variable still receives the actual selected item byte.
The existing `g2KurtApricorns` field holds its confirmed quantity. Native
script branches, event/working flags, daily resets and ball choice remain
script-owned. This does not add a competing Kurt job model or rewrite a ROM
script's ball operand merely because its selection table contains a pair.

Validation:216 synthetic checks use actual importer/map-script serialization,
Gen2ScriptVM, ScriptRunner, StateStack, Menu input and Bag operations. They
cover order/bounds, malformed data, cache readiness, Gold/Silver single-item
handover, Crystal confirmation/reselection/cancellation/scrolling and a real
`verbosegiveitemvar` collection path: a full ball stack preserves the event,
successful delivery grants the confirmed quantity and event clearing prevents
duplicate collection. Only text/audio IO is substituted. A private read-only
Crystal Rev0 table probe finds seven complete rows, agrees with an independent
byte decoder and leaves the original ROM unchanged. It is not a full import,
GPU, original-story or Gold/Silver actual-ROM acceptance claim.

The `apricorns` registry now projects authored recipe records into the actual
decoded native Kurt programs. The importer queues four named roots and their
reachable scripts; incomplete or home-bank bindings are unavailable rather
than guessed. An additional stock-GSC cache revision requires that import.
The adapter derives each base recipe's event from its native selection and
collection branches, rather than assuming an event/colour order. For example:

```lua
mod.content.apricorns:patch("RED_APRICORN", {ball="ULTRA_BALL"})
```

All fields are `apricorn`, `ball`, `event` and `index`, as in the reference
registry. Items must resolve to real indexed GSC item bytes. Additional recipes
can use previously indexed native items and new word-sized events, excluding
the `$ffff` indirect-event sentinel. The selector still returns the real item
byte; it is never replaced with a fabricated seven-colour ordinal. Actual
native membership and event-dispatch branches, including overlapping roots,
consume the resulting table. Working/day flags, quantity, dialogue and
full-bag refusal stay in native scripts. Removed/rekeyed recipes stop new
jobs while unclaimed original pending events retain their original output.

The observational `apricorn.converted` event is emitted only after a native
gift succeeds and its real event is cleared. API1/2 callbacks retain native
item IDs. The fork separately tests its API3 semantic callback boundary. It cannot veto or redirect
the gift. Recipe record views use semantic IDs through upstream API1/2 native content. The fork also tests its API2/3
unified content modes; those additional APIs are not imported by this PR. Later item registrations resolve before
projection; invalid owners and affected consumers roll back before any native
script mutation. Unload restores unchanged owned rows/scripts, preserving
external edits. A new script table invalidates the VM's compiled-root cache.

Synthetic integration checks cover actual Loader, VM, Menu, daily resets,
bag operations, observers, invalid/forward references, removal, unload and
generation isolation. A private read-only Crystal Rev0 probe also decodes
31 reachable native programs (264 instructions, zero desyncs), registers an
eighth recipe and executes the native selection, map reentry, working branch,
daily reset, full-bag refusal, three-ball delivery and exactly-once completion.
Only external text/audio IO is substituted; the original ROM is unchanged.
These checks do not establish full GPU/story or Gold/Silver actual-ROM
acceptance. The legacy Apricorns facade, full native daily/tree lifecycle and
remaining Gen1 feature parity remain open.

Behavior was checked against the read-only Gen1 reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91` and primary disassembly sources:
[Gold selection/table](https://github.com/pret/pokegold/blob/master/engine/menus/menu_2.asm),
[Gold handover](https://github.com/pret/pokegold/blob/master/engine/events/specials.asm),
[Crystal selection/quantity](https://github.com/pret/pokecrystal/blob/master/engine/events/kurt.asm),
[Crystal recipe table](https://github.com/pret/pokecrystal/blob/master/data/items/apricorn_balls.asm).
These links identify behavior/provenance; no ROM or extracted table bytes are
included in the contribution.

Original contributions by Roxas2712; existing reference, upstream and
third-party rights and credits remain applicable. See the [specific PR contribution permission and credits](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
