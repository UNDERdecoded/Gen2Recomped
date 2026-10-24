# Battle snapshot API

```lua
local battle = mod.battle -- safe in the mod entry chunk, before Game exists
local snapshot, reason = battle:snapshot()
if snapshot then
  local actor = snapshot.player
  if actor then print(actor.name, actor.hp, actor.maxHp) end
end
```

Available to API 1 and API 2 mods on all supported Gen 1–5 versions. Neither
`content_format` nor `callback_format` is required. This reads the shared
BattleState in the current Game's stack, including beneath another screen.
A read before Game is loaded also returns `nil, "no battle"` without
bootstrapping Game. Outside battle it returns `nil, "no battle"`. A UI screen merely holding a
`.battle` reference does not count as another battle.

If the capability-query extension is installed,
`mod:supports("battle", "snapshot")` returns true without constructing Game.
When the [battle action extension](battle-actions-api.md) is installed,
`mod:supports("battle", "submit")` also returns true. Other battle capabilities
return false with a reason.

## Records

All returned tables, including nested records and `native` diagnostics, are
copies. They carry no engine objects, functions, userdata, threads or
metatables. Unknown native Pokemon extension fields are copied as data;
cycles are preserved. These diagnostics are not a portable write format or
necessarily JSON-serializable. Changing a snapshot never changes battle/save
state or future reads.

| Field | Meaning |
| --- | --- |
| `revision` | Positive, monotonically increasing within this facade; see below |
| `kind`, `phase`, `result` | Battle kind (including ghost/safari/oldman variants), native phase and optional outcome |
| `turn` | Native resolved-turn count; zero before the first turn |
| `double` | Whether this battle is configured as a double |
| `active` | Player position the menu currently selects for (0 or 2) |
| `player` | Occupied battler at `active`, or nil |
| `enemy` | Occupied opponent-left battler (1), or nil; use `battlers` for all foes |
| `battlers` | Array of occupied battler records in position order |
| `party` | Battle-specific player party when supplied (link copies), otherwise save party order, with one-based `slot` and `active` |
| `moves` | Current actor's battle moves, including Transform/Mimic overrides |
| `items` | Positive inventory quantities; acquisition order, then sorted unlisted IDs |
| `catchable` | Wild battle, one living foe, no ghost/noCatch/result restriction |
| `prompt` | Description of the battle screen's input phase; see below |
| `message` | Optional array of currently revealed text lines; unknown glyphs leave it unavailable |
| `messageSource` | Optional current message source text, which can include unrevealed text |
| `safariBalls` | Optional native remaining Safari ball count |
| `menuIndex`, `moveIndex`, `moveSwapIndex` | Optional one-based native menu/move/reorder cursors |
| `targets` | During targetSelect, ordered positional IDs from the native selector; otherwise empty |
| `targetIndex` | Optional one-based cursor into `targets` |
| `mimicMoves`, `mimicIndex` | Optional Mimic options and one-based cursor |

Battler IDs are **0 player-left, 1 opponent-left, 2 player-right, 3
opponent-right**. Array indices are not battler IDs. Empty positions are
omitted; an enemy at 3 never masquerades as enemy-left. `player` follows the
second player chooser, including after the left flank leaves the field.

Pokemon records expose `species`, optional `item`, `nickname`, `name`,
`level`, `hp`, `maxHp`, `status`, `isEgg`, `stats`, `moves`, and copied `native`
diagnostics. Species/move/item IDs use canonical string names from this boot's
registries. Numeric DS IDs resolve through the imported names and aliases;
unresolved IDs use their string form. Pristine IDs remain stable across
presentation-name patches; definitions registered by later mods are visible.
Status codes SLP/PSN/BRN/FRZ/PAR/TOX become
sleep/poison/burn/freeze/paralyze/toxic; unknown values are retained.

Stats use `hp`, `attack`, `defense`, `speed`, `special`, `specialAttack`,
`specialDefense`; Gen 1's special supplies both split stats. `maxHp` comes
from stored `stats.hp`. HP and status are logical state, not interpolated HUD
values. Battlers additionally expose `id`, `side` (player/enemy), `active`,
`absent` (false for occupied rows), `ally`, optional one-based `partyIndex`,
`displaySpecies`, `battleStats`, `types`, and `stages`. Original species and
stored stats stay separate from Transform's displayed species/current stats.
NPC allies are not added to the player's party.

Moves expose one-based `slot`, portable `id`, optional `name`, `pp`, `maxPp`,
`ppUps`, `type`, `power`, `accuracy`. Max PP follows the native base PP plus
clamped 0–3 PP Ups, each adding floor(base PP / 5). Definition fields are base
values, not damage/accuracy predictions. Only the top-level actor `moves`
also expose `disabled`: true for Disable, no PP, Taunt or Torment; false if
none applies on Gen 1–4. In BW this field is omitted unless a common
restriction is known, because additional native Choice/Imprison/Gravity/
Heal Block controllers may refuse the move. Nil is unknown, not false.
Mimic options retain their original move `slot` even if options are compacted.

Items expose `id`, optional `name`, `count`, `ball`, `catchable`, optional
`pocket`. This is an **inventory view**, not a list of currently usable items;
it can include badges/key items. Ball classification follows imported ball
metadata. `catchable` describes the target restriction, not permission to use
an item: noItems/frontier rules, party capacity and the active bag controller
still own item eligibility. No `needsTarget`, catchChance, hitChance,
displayPower, effectiveness or guessed preview is produced.

## Prompts and revisions

`prompt` is `menu`, `moves`, `target`, `mimic`, `safari`, `advance`, or
`locked`. Intro, automatic demos/Palace, conservative Arena menu handling,
known automatic battler locks and every covered battle are locked. Message
advance is reported only when native manual text waits have finished their
pre-advance delay. Party, bag and choice screens above battle stay locked;
this API does not inspect or drive those screens. Link controllers remain locked.
Visible messages decode the native revealed glyph buffer through the imported
charmap and already-loaded Unicode glyph map; this never initializes a font. A prompt is descriptive,
not an action-permission token. The [battle action extension](battle-actions-api.md) supplies separately validated
submission; the snapshot's descriptive prompt is not its permission check.

Identical successive snapshot records and action contexts retain their revision.
The action extension also tracks native controller/selector identity and private
control flags, so replacement objects can invalidate an otherwise identical
record. Accepted public actions invalidate all facades on that Game, including
snapshots observed during native callbacks. A change to
any exposed data advances it once at the next read; animation clocks and
interpolated HP alone do not. A different battle or Game also advances it,
even with identical records. Observing `no battle` invalidates the previous
record, so re-entry advances it. Unobserved transitions between reads cannot
be detected if the same Game and battle objects are reused. Each mod has its
own counter; revisions are not save data or globally synchronized IDs.

Reading constructs no Pokemon or screen, loads no gameplay/graphics module,
executes no action, emits no event/hook and consumes no RNG. Only facade
bookkeeping and loader-local ID indexes change. The API provides an observer
boundary, not hidden-information filtering or a write-back transaction.
