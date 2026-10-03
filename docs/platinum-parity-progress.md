# Platinum parity progress — October 1, 2026

This is a record of verified fixes, not a declaration of full ROM parity.

## Current pass

- Summary: caught-ball assets for all sixteen Platinum balls, native placement,
  stored OT names, traded/fateful encounter messages, egg hatch history and dates.
- Acquisition: gifts, captures, Day-Care eggs and hatches retain Gen4 origin
  dates and locations. Existing records are preserved; other generations keep
  their existing behavior. Older saves without dates remain blank.
- Story: party event-species lookup returns a zero-based slot or 255, skips eggs
  and requires the fateful encounter flag. Regigigas event checks and Pokérus
  queries now inspect saved party records instead of returning placeholder zero.
- Dex progression: local seen/caught counts use Sinnoh membership; duplicate,
  false and invalid entries do not inflate totals. Local completion requires
  210 species seen. National completion requires 482 catches after the ROM's
  eleven exclusions. Queries preserve the script comparison register.
- Story correctness: the two party-species opcodes have distinct handlers
  because their operand orders differ. The later handler previously overwrote
  the earlier one.

## Validation

Run with `python tools/run_lua_check.py`:

- `tools/gen4_event_party_check.lua`: event flags, species slots, Pokérus,
  acquisition provenance, Dex thresholds/exclusions and both species queries.
- `tools/gen4_menu_parity_check.lua`: menu controls and pointer scaling,
  item transfers, memo templates and page restrictions.
- `tools/gen4_command_audit.lua G:/Gen2Recomped/platinum/data/generated`:
  46 handler checks.
- `tools/gen4_gameplay_regression_check.lua G:/Gen2Recomped/platinum`:
  35 gameplay checks.
- `tools/gen4_storage_check.lua`: 22 storage and field-move checks.
- Party, service script, camera and zoom checks also pass.
- `tools/gen4_native_ui_render_check` runs under LOVE and verifies 706 native
  resources, including visible caught balls/tabs, and captures menu variants.

## Remaining gaps

The full game has not been played through for this pass. Script lowering still
contains unimplemented commands and placeholder subsystems; no lowering
percentage establishes story parity. Contest move summaries, exact animation
timing, bottom-screen summary controls, special egg origin variants and some
remaining menu behavior require implementation. Pokédex search/visual comparison
pages and storage still require a full interaction/art audit. Opening sequence
choreography, move callbacks and sprite animation coverage remain incomplete.
Switch audio needs hardware verification. Newly extracted UI assets require
re-extraction for older imports; runtime script lowering changes do not.

References: pret/pokeplatinum's summary `main.c`, `window.c`, `sprites.c`, sprite
template JSON, `scrcmd_party.c`, `scrcmd.c`, `pokedex.c` and `pokedex.h`, checked
against the supplied Platinum Rev 1 ROM and extracted dataset.

## Oreburgh Mine event completion repair

Roark's actual imported script was reproduced with the previous obstacle result:
it remained in its one-frame polling loop forever after the first dialogue.
The obstacle command now writes the ROM completion value (1); the script reaches
its second dialogue, rock removal, departure walk, both flags and ReleaseAll.
Native obstacle effect art/timing remains unfinished; this completion repair does
not claim animation parity. All seven imported obstacle sites use the corrected
handler, including all three supported obstacle kinds.

Related event audio repairs preserve variable operands for PlaySE, StopSE and
WaitSE, wait only for the requested effect, and play Platinum cries immediately
instead of queuing the shared older-generation text-box cry behavior. The unused
PlayCry operand no longer changes text-box waits. Future input-gate warnings now
include the last script row and its wait state.

Validation: `tools/gen4_event_completion_check.lua` reproduces the old freeze and
executes the real compiled Roark script with deferred dialogue/movement callbacks.
It verifies complete departure, flags and control release, all imported obstacle
sites, immediate cries and variable sound operands. Command audit (46), gameplay
regressions (35), nurse script traversal (152 instructions), dialogue, approaching
trainers, party event gates, zoom/story and menu checks passed. This is headless
script validation, not an interactive full-game playthrough. Runtime lowering
uses these corrections with existing imports; no ROM reimport is needed.

Primary references: [obstacle completion task](https://github.com/pret/pokeplatinum/blob/main/src/overlay006/ov6_02248948.c)
and [script sound commands](https://github.com/pret/pokeplatinum/blob/main/src/scrcmd_sound.c).

## Championship and NPC state checks

CheckGameCompleted now reads Platinum's FLAG_GAME_COMPLETED (0x964) rather
than always returning zero. SetGameCompleted writes that same flag. Existing
runtime saves with Hall of Fame records and no completion flag retain postgame
access; an explicit cleared flag remains authoritative. Query commands preserve
the script comparison register, as the ROM does.

ClearGame now prepares the induction by setting completion and communication
club access (0x966), and awarding Sinnoh Champion Ribbon 32 to each non-egg party
member, including fainted members. Existing ribbons are preserved. The shared
Hall of Fame/credits implementation remains in use; this pass does not establish
parity for that presentation or all of the native ClearGame save bookkeeping.

CheckDaycareHasEgg now reads the pending egg from the existing DayCare breeding
store without creating state. This fixes its NPC branch result; the full Solaceon
Day Care service script and Gen4 breeding behavior still need an audit.

Validation: `tools/gen4_postgame_daycare_check.lua` covers all eight imported
completion-check sites, the egg-query site and all three ClearGame sites. It also
checks before/after NPC branching, old-save recovery, explicit flag clearing,
fainted/egg ribbon eligibility, repeat induction and flag-before-scene ordering.
Roark completion, command audit (46), gameplay (35), party (35), storage (22),
service, event-party and menu regression suites passed. No interactive championship
playthrough was performed. These runtime changes apply to existing imports.

References: [completion flags](https://github.com/pret/pokeplatinum/blob/main/src/scrcmd_system_flags.c),
[ClearGame](https://github.com/pret/pokeplatinum/blob/main/src/clear_game.c), and
[Champion Ribbon eligibility](https://github.com/pret/pokeplatinum/blob/main/src/unk_02054884.c).

## Native forms, sightings and Unown event queries

Platinum alternate sprite forms now resolve their zero-based numeric IDs and
named keys through the native archive order, rather than Johto's DV-based Unown
formula. Runtime selection reads the extractor's existing front/back and shiny
fields, so those assets work in existing imports. Trainer party construction now
preserves decoded form IDs. Native per-form animation records replace base-species
strips; the extractor also writes shiny form strips. Older imports without those
shiny strips hold the correct still image rather than changing colour/form during
animation. New strips require re-extraction.

Battle sightings (including trainer replacements and both opponents in doubles),
gifts and native in-game trades record unique forms in encounter order for the
nine species the ROM tracks in UpdateForm. The dex forms page uses that history,
reads native asset field names, avoids a duplicate base entry and does not reveal
unseen variants. Old saves without form history retain the base-picture fallback.
GetUnownFormsSeenCount now reads actual sightings, including both punctuation
forms, and TurnOnPokedexFormDetection persists its flag. These queries preserve
the comparison register. Gen2 DV-based form selection remains unchanged.

Validation: `tools/gen4_forms_check.lua` verifies all 76 non-egg archive form
records, numeric/named IDs, normal/shiny front/back paths, strip selection, old
strip fallback, seen-order deduplication, all 28 Unown forms, invalid/egg filtering,
legacy isolation and battle sightings before capture. It exercises the actual
extractor with the supplied ROM, checking nonempty images and shiny strips, plus
all five imported Unown-query sites and the form-detection event. The LOVE form
render check draws all 76 normal/shiny forms through the live sprite resolver;
the resulting contact sheet was visually inspected. The native menu render check
still passes with 706 ROM UI resources. Story, gameplay, menu, party, storage and
command regressions passed.

Remaining: wild form generation/distributions, form-dependent stats/moves and
weather changes, exact per-form animation timing, form-detection UI gating and
full native dex controls/layout still need work. This pass fixes selection and
tracking, not complete form or Pokédex parity.

Primary reference: [Pokédex form updates and encounter-order storage](https://github.com/pret/pokeplatinum/blob/main/src/pokedex.c),
with native archive metadata verified against the supplied ROM.

## Wild forms and alternate personal records

Wild creation now reads the encounter archive's Shellos/Gastrodon selectors and
all eight Solaceon Unown room distributions, including the secret punctuation
room. Archive room IDs are converted from 1..8 as InitEncounterFieldParams does.
Explicit scripted form options take precedence over map selection.

The twelve alternate personal records (Deoxys, Wormadam, Giratina, Shaymin and
Rotom) now supply stats, types, abilities, held items, learnsets and TM masks.
Base species identity and artwork metadata remain intact. Pokémon creation,
trainer construction, battle definitions, summaries, NPC type queries, experience
level-ups, Rare Candies, Day Care level-up definitions and evolution use the
form-aware definition. Gen4 evolution retains IVs, EVs and nature. Trainer IV
scales remain on the Pokémon itself, so subsequent recalculation keeps them.
Duplicate shiny form-strip extraction was removed.

Validation: `tools/gen4_form_mechanics_check.lua` uses extracted Platinum records
to check all twelve personal forms, all eight native ruins rooms, both Shellos
regions, wild/trainer construction, summary lookup, seed replacement, level-up,
Rare Candy, Wormadam TM compatibility and Burmy-to-Wormadam evolution. All 76
form asset checks and existing story, command, gameplay, party, menu, storage
and item-use regressions passed. These are headless checks; no full-game
interactive playthrough was performed. Existing imports already contain these
personal and encounter records, so these runtime fixes do not need reimporting.

Remaining: weather/item/location-triggered form transitions, native trainer
personality generation, exact form animation timing, dex form-detection UI
gating and complete native Pokédex controls/layout still need work.

References: [wild form generation](https://github.com/pret/pokeplatinum/blob/main/src/overlay006/wild_encounters.c)
and [Pokemon_GetFormNarcIndex](https://github.com/pret/pokeplatinum/blob/main/src/pokemon.c).

## Android Pokétch input and passive display behavior

The always-present watch drawn on Android's second display now owns pointer
input. Previously it was drawn outside the state stack, while input only reached
the top state; its LCD and bezel buttons therefore received no taps. Claimed
gestures remain assigned to the original screen until release. Secondary fingers
cannot replace a watch drag, and captured gestures can release in the letterbox.
Both Java host copies release every pointer on Android cancellation. Synthesized
mouse moves/releases no longer create a second gameplay touch stream.

Passive watch presentation now advances coin animation, clock blinking, dowsing
and friendship feedback without consuming overworld controller input. App cycling
skips unregistered apps in both directions, handles a single unlocked app, and
immediately includes newly registered apps. Legacy saves without a registry keep
their prior access without invented acquisition flags. Watch/pointer state resets
when adopting a save or loading a game.

Validation: `tools/gen4_poketch_android_touch_check.lua` exercises Game's actual
fallback draw-owner selection and pointer dispatch, the host input queue, native
panel coordinate scaling, swap/inset transforms, both bezel buttons, memo dragging,
multitouch, letterbox release, specialized-screen ownership and app registration.
Pokétch/service (142), ROM records (49), display (76), file protocol (36), launcher
panel (121), mining (437), menu, Roark and form-mechanics regressions passed. Java
protocol constants passed; its cross-end byte/Java test skipped because no Lua
executable is on PATH. No Android device run or APK build was performed.

Reference: [native registered-app cycling](https://github.com/pret/pokeplatinum/blob/main/src/poketch.c).
Full watch artwork/layout and app behavior parity remain under review.

## Save editor Add Mon crash

The missing-art placeholder now converts numeric species IDs to text before
taking a substring. Platinum's picker excludes empty species 0, egg records
494/495 and alternate personal rows 496..507, so Add Mon creates a real species
instead of the empty record. Custom species entries remain selectable. Empty
catalogs safely refuse party/box creation. The inspector shows numeric dex IDs,
uses the runtime's form/shiny sprite resolver and caches by species registry plus
image/palette, preventing reuse across datasets. Form-aware stat recalculation
also applies to save-editor IV changes.

Validation: `tools/save_editor_add_mon_check.lua` drives the real Party Add button
and inspector in the same frame with extracted Platinum records. It also checks
the next roster draw, numeric/missing-art placeholders, all 493 selectable native
species, custom entries, box Add, empty catalogs, form stat recalculation,
normal/form/shiny sprite selection and separate dataset caches. The existing
Gen3/4 editor and form-mechanics regression checks passed. The broader legacy
save-editor runner stopped on its old save-identity assertion and Windows
temporary paths outside the writable workspace; it did not complete. No ROM
reimport is needed for these runtime/editor fixes.

## Pokédex knowledge and entry rendering

The regional/national numeric listing now keeps unseen gaps only through the
last encountered species. Entry navigation skips unseen species in both
directions. Numeric and symbolic knowledge keys are recognized, and unseen or
missing entries cannot trigger cries. Seen-but-not-caught entries conceal their
category, measurements, description, footprint and types. Size comparisons are
capture-only; the Forms button requires the story's form-detection upgrade.
Controller cycling skips locked pages, and mouse/touch cannot open them.

Info entries display the first encountered form and use that form's personal
types. Native type badges now occupy (170,72)/(220,72), with no duplicate single
type. Footprints use their native (120,88) anchor; Origin Giratina selects the
ROM's Metapod blank-footprint resource. The category background uses cell 17's
actual OAM origin (-86,-36), its text is centered within the native 136-pixel
window, and multiline descriptions share the left edge determined by their
widest line. New imports preserve SPECIES_NONE text-bank entries; older imports
hide caught-only facts and retain safe placeholders. Missing Dex metadata no
longer crashes the size page.

Validation: 30 real-cache knowledge/render-position checks, 10 feature/input
checks, 76 native-form extraction/resolution checks, form-mechanics, menu,
Roark-completion and save-editor Add Mon regressions passed. The LOVE GPU harness
rendered 706 supplementary ROM UI resources and the Dex/summary/shop/evolution
screens; the updated Info entry was visually inspected. This is not complete
Pokédex parity: native dual-screen page controls, scroll wheel/search, habitat
atlas overlays, cry visualizer and animated size comparisons still need work.

References: [InfoMain rendering and capture restrictions](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/infomain.c),
[native listing/default-form rules](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/pokedex_sort.c),
[page unlock checks](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/ov21_021E29DC.c).

## Move names and editor moveset parity

Save-editor move rows and change/clear messages resolve names from the current
dataset's move records. The map editor's trainer move rows and picker also show
names; its search accepts case-insensitive names and numeric IDs. Stored IDs
remain numeric for Platinum. Move 0 and the three unnamed archive-only records
468..470 are excluded from Platinum selectors, while named custom moves remain
available. Empty catalogs safely refuse cycling.

Platinum replacement moves clear the old move's PP Ups, deletion shifts the
remaining full move records, and Reset to learnset uses the active form's
personal record. Full heal restores depleted PP even at full HP and visits all
four slots in older saves containing gaps. Choosing a trainer move in a later
empty slot no longer drops it during moveset compaction; changes remain on the
working copy until the trainer team is saved.

Validation: `tools/save_editor_moves_check.lua` checks names for all 467 native
moves, actual inspector row rendering/clicks, trainer name/ID search and picker
selection, save encoding, PP restoration/replacement/deletion, form learnsets,
and legacy symbolic moves (499 checks). Add Mon, Gen3/4 editor, native-form
mechanics, menu and party (35 checks) regressions passed, as did `git diff
--check`. No ROM reimport is needed. These checks use UI stubs and extracted
records, not a device run; complete ROM parity remains in progress.

References: [native move range](https://github.com/pret/pokeplatinum/blob/main/generated/moves.txt),
[native reset/deletion behavior](https://github.com/pret/pokeplatinum/blob/main/src/pokemon.c).

## Pokédex National artwork and entry companion controls

The supplementary graphics extractor now composes the native Info entry,
banner and lower page-panel layers for Sinnoh and National views. National mode
replaces only palette row zero, preserving shared window colors. Six native
page-button sequences are extracted with their actual OAM crop origins.
Existing caches require ROM reimport to receive these new images; runtime uses
their earlier assets or safe backgrounds until then.

Entry pages now own their lower surface, rather than leaving Game to display
the overworld Pokétch fallback. Device-display, inset and raised swap modes
render the page buttons on that surface at the native centers. Physical-panel
and window input use SecondScreen's coordinate mapping; top-window clicks cannot
select an invisible physical-panel button. The Back button returns to the list,
page changes stop active cries, and Size/Forms retain their capture/story gates.
Lowered swap and single-screen modes retain the combined-screen footer controls.
SELECT on the listing switches Sinnoh/National views after the upgrade, without
changing the save's National Dex acquisition flag.

Validation: 40 actual-ROM graphics and dual-surface/input checks, 30 knowledge
checks, 10 feature checks, 76 second-display checks, Android Pokétch routing and
499 move-editor regressions passed. The GPU harness rendered 718 supplementary
ROM resources; National Info and both lower-panel images were visually inspected.
No Android hardware test was performed. Native list/search/scroll-wheel companion
layout and page-specific habitat, cry, size and form presentations remain pending.

References: [native entry panel/palette/buttons](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/ov21_021E29DC.c),
[native list switching](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/ov21_021D5AEC.c).

## Pokédex list companion, wheel and search rules

The list now owns the lower screen too. Its extracted scroll background,
Sinnoh/National/filtered palette variants, wheel and six button cells replace
the overworld Pokétch fallback. Search, Switch, Check, first/last and Quit/Cancel
use the native positions and hitboxes. Switch retains the National upgrade gate;
filtered results hide Search/Switch and Cancel restores the ordinary listing.
Single-screen mode also exposes search through X and its footer.

Wheel dragging works through the device-display and scaled inset/swap input
mapping, keeps one pointer owner, releases outside the panel, and clamps list
ends. The rotating layer uses a bounded, DPI-independent canvas to avoid spilling
onto the main screen in inset mode. Native inertial wheel timing and button
press animation are not yet reproduced.

All 47 order/name/type/body membership lists are now read from zukan_data.narc.
Search supports all six orders, nine name groups, both type criteria and fourteen
body shapes. It preserves regional membership and native ordering. Size orders
and type filters require captured species; alphabetical/name/body filters retain
seen-only entries. Two types intersect. Empty searches keep the previous listing
and report NONE FOUND; older caches without requested membership data safely
report that ROM reimport is required. The search top uses native filter maps,
selection patches, value positions and body silhouettes. The companion selector
is functional but still uses engine controls rather than Platinum's full native
search companion, and descriptions/text palettes/search transitions need work.

Validation: 148 actual-ROM artwork, search-rule and dual-surface/input checks,
30 knowledge checks, 10 feature checks, 76 second-display checks, Android Pokétch
routing and 499 move-editor regressions passed. The GPU harness rendered 746 ROM
resources; list companion, search top and body selection were visually inspected.
No hardware Android run was performed. Reimport Platinum for the new images and
membership tables. The upper list layout and page-specific habitat/cry/size/form
presentations still need parity work; full ROM parity is not complete.

References: [native list companion](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/ov21_021D76B0.c),
[search filtering rules](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/pokedex_sort.c),
[search graphics and value positions](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/pokedex_search.c).

## Native search companion grids and labels

Replaced the engine-drawn five-row search companion with the native search_main
background and search_buttons/search_button_forms cells. Extracts normal,
pressed and selected frame artwork with OAM crop origins. The right-side
Back/Order/Name/Type/Form/OK controls and left-side sort, name, two type pages
and body-shape grids use their native centers and hitboxes. Body shapes follow
the ROM's displayed order, which differs from its filter enum order. Pressed
and selected text follows the native vertical offsets. Controller arrows
navigate the visible buttons; A selects a criterion, OK applies, B cancels,
and Start remains a convenience shortcut for applying.

Type taps alternate the two criteria slots, ignore already-selected types,
and None clears the first occupied slot before the second, resetting selection
to slot one. Single-screen cycling now skips the other selected type too.
Search captures one touch pointer, ignores another finger while held, and
clears pressed state on outside release. Physical display, scaled inset mouse
and raised swap touch use the same native-grid hit testing.

The importer preserves all 128 strings from Pokédex text bank 697. Search now
uses the native order/type labels, capitalization, field descriptions and
no-match message, with safe older-cache fallbacks. Blank/unmapped labels still
use fallback text. Native search transitions/loading animation, exact text
palette/face handling and controller cursor presentation remain pending; the
upper Dex listing and habitat/cry/size/form pages also remain incomplete.

Validation: 279 actual-ROM artwork/search/grid/input checks, 30 knowledge checks,
10 feature checks, 76 second-display checks and Android Pokétch routing passed.
The GPU harness rendered 831 resources; sort, both type grids, body grid and
native-label top page were visually inspected. `git diff --check` passed.
No Android hardware run was performed. ROM reimport is required for the new
button frames, companion background and label bank.

References: [native search companion grids/actions](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/ov21_021D94BC.c),
[native button frames/text offsets](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/pokedex_main.c),
[search description/value positions](https://github.com/pret/pokeplatinum/blob/main/src/applications/pokedex/pokedex_search.c).
## Background music: the gap located and sized

Sinnoh plays no background music, and the cause is not the module inheritance
previously suspected. `Music.playMap` reads `data.audio.mapSongs[mapId]`, and
`data.audio.mapNightSongs[mapId]` when the hour is before 4 or at/after 20.
Platinum writes its own `audio.lua` rather than inheriting Kanto's, but that
file carries `cries` only: no `songs`, no `mapSongs`, no `mapNightSongs`. The
song resolves to nil and nothing sounds. `Music.lua` has no Gen 4 awareness at
all, and `playMap` is reached on Gen 4 because its call sites are in the shared
`OverworldController`.

A missing definition is silent rather than noisy: `Music.play` returns on
`not def` before any logging, so no warning is emitted per map entry and no
`failed` entry accumulates.

The assignment is already extracted. Every entry in `gen4_map_headers.lua`
carries `dayMusic` and `nightMusic` (ids 1000-1196): 593 maps carry a day
music, 85 distinct song ids are referenced across day and night, and 294 maps
specify a different song for night than for day. The existing day/night rule in
`playMap` matches that split without modification.

What is missing is the player, not the data. Per `src/import/Gen4Sdat.lua`'s own
header, `pl_sound_data.sdat` is mostly SSEQ sequences over SBNK banks and SWAR
wave archives -- a synthesiser rather than a decoder -- and that extractor
handles cries only, one PCM8 sample per species, which is why cries work and
nothing else does. Hoenn met the same wall and answered it with
`src/core/M4ASynth.lua`, a GBA sequencer over sampled instruments; a DS
equivalent is the structural precedent. Scope is 85 songs, not Hoenn's 611.

`mapSongs` and `mapNightSongs` can be written from the map headers with no
engine change, but doing so is audibly a no-op until a sequencer exists and a
sequencer may want a different definition shape, so it has deliberately not
been built ahead of that decision.

The three modules a Platinum cache was reported to borrow from Kanto --
`save_layout`, `scenes` and `songs` -- were each traced to their consumer and
are inert. `data.songs` is read nowhere (every music consumer reads
`data.audio.songs`, which comes from the `audio` module). `data.scenes` is read
nowhere. `save_layout` has a real consumer in `Boxes.load`, reached from the
shared overworld controller, but it is a Gen 3 module that Red and Yellow never
write, so there is nothing to inherit; box count and capacity now also branch on
`GameVersion.isGen4()` to 18 and 30. There is additionally no root cache present
on this machine for the additive overlay to resolve against. The borrowed list
is computed from the module lists rather than by resolving against a real root
cache, so it reports what would be inherited if a root cache existed, not what
is.

## Sheet widths: the backlog was one sheet, and it is closed

Two figures were carried as a live art backlog and neither survived
measurement. The first, 113 provisional sheets, came out of the installed
cache; that cache carries no `layoutFrom` field at all, which the extractor
writes for every non-tilemap sheet, so it is a pre-change extraction and its
flags describe rules that no longer apply. The second, 26 sheets drawn at a
width the file contradicts, was never right: the check producing it compared
each sheet's declared size against its nominal width without asking whether the
sheet is laid out at that width at all, and twenty-five of the twenty-six are
placed by a cell bank, which decides their shape outright. `pl_winframe`'s
message boxes, the headline case in that comment, are exactly those.

Measured through the extractor's own `composeJob` against the cartridge, all
364 sheets in the archive table resolve as: 179 placed by a cell bank, 109 at a
width written down for the group, 76 at the member's own declared size, and
**none** at a width nobody states. Of the 109 written-down widths, 36 sit on
members whose header also states a size, and all 36 agree -- so the
hand-measured table is confirmed by the cartridge rather than merely plausible,
while the other 73 sit on members whose header says `0xFFFF` and genuinely need
it.

The single real fault was the Pokedex's weight scale, which declares 16x2 and
was laid out 8 wide, extracting as 64x32 instead of 128x16. pokeplatinum
centres that sprite as `xPos = 128 - (128 / 2)`, `yPos = 96 - (16 / 2)`, which
states the size independently, and it is a software sprite with no cell bank so
the header is the only in-file source. It is **not** a visible fault: the
Pokedex takes its art from `gen4_dex` and nothing reads this sheet. It was
corrected so the census can assert an exact zero rather than carry a known
exception in prose, which is how the previous figure went stale.

`tools/gen4_sheet_layout_check.lua` now owns that census, with the three
legitimate provenances as floors, zero as an exact pin for the guessed one, and
zero header contradictions. It also probes an installed cache for the missing
`layoutFrom` and reports that a re-extract is needed -- which it is on this
machine: the cache predates this work and the Underground art passes, and
mentions none of the five Underground archives.

## Move targeting: Sinnoh was not reading its own `range`

`src/battle/Targeting.lua` decides who a move hits for every generation, and
it was written for Hoenn: it reads `move.target`, the byte at offset 6 of
gBattleMoves' 12-byte record. Platinum's move record has no such field -- it
carries `range`, 471 of them in the cache and not one `target`. Measured over
every dataset on this machine: platinum 471/0, emerald 0/3666, firered 0/2819,
and crystal, gold, silver, polishedcrystal and prism carry neither.

So `kindOf` read nil for all 467 Sinnoh moves and every one resolved as
`SELECTED`. In a single battle that is invisible -- there is one foe and
`SELECTED` means that one -- which is why it had never shown up. In a double it
is wrong for roughly a hundred and thirty moves at once: Explosion sparing your
own partner, Reflect asking you to pick a victim, Spikes aimed at a Pokemon
instead of at a side, Thrash never locking on. `BattleState` is shared and its
double-battle path routes target choice, spread animation and redirection
through this module for Sinnoh too.

The cache stores `range` as `1 << (id - 1)` of pokeplatinum's
`generated/move_ranges.txt` order, id 0 staying 0 -- verified move by move
against pret's own per-move `data.json`, 468 of 468. A first comparison against
the enum INDEX rather than the mask reported 118 disagreements; measuring the
mapping instead of asserting it showed the relationship was systematic and
total, a representation difference and not a fault.

The translation is explicit rather than an assignment, because the two
spellings overlap just enough to look interchangeable: both are small bitmasks
agreeing on 0 and 0x10, while 0x08 means "foes and your ally" in Sinnoh and
"both foes" in Hoenn, and 0x20 means "your own side's field" in Sinnoh and
"hits three Pokemon" in Hoenn. It also reads the cartridge's `range` where it
is used rather than writing a second `target` field into the cache -- the same
fact in two fields is this port's recurring bug, not its fix.

`tools/gen4_targeting_check.lua` (47 checks) pins the premise, every mask's
translation, the bucket counts, what each kind resolves to in a double-battle
fixture, that Hoenn still takes `target` first, and -- the point -- that the
five colliding masks must not translate to themselves, so collapsing the
translation back into `target = range` fails rather than silently re-aiming a
hundred and thirty moves.

Gen 1/2/3 are unaffected structurally and not merely by test: `target` wins
wherever it exists, and no dataset carries both fields.

## Move effects: the queue, measured, and its largest cluster closed

The remaining move-effect gap had been quoted from notes. Measured instead --
every record parsed through the current `Gen4Moves.parse` and its resolved name
looked up in `MoveEffects` -- of 471 moves, 412 carry an effect name and 59 stay
a number on purpose, and **65 distinct effects covering 67 moves have no
handler**. Nearly all 65 are Sinnoh-only and carry one move each.

(A first census keyed the lookup on `EFFECT_NAMES` and reported that nothing
worked at all -- 257 ids over 468 moves. That table holds only the 58
Gen 4-only names; Gen 4 inherited Hoenn's numbering wholesale, so the inherited
ids are named in `GEN4_MOVE_EFFECTS`.)

Four effects covering five moves -- Gyro Ball, Wring Out, Crush Grip, Brine and
Wake-Up Slap -- needed only arithmetic over HP, speed and status, and are now
implemented. Every constant is a transcription: pokeplatinum names its
per-effect battle scripts by effect id, so
`res/battle/scripts/effects/effect_script_0219.s` and its three siblings are the
source, and `POWER_MULTI` there is in tenths (10 is the move's own power, 20 is
double) -- which is why the doubling effects read the move's power rather than
naming 130 and 120.

Three boundaries decide whether an implementation agrees with the cartridge or
merely looks right. Brine tests `curHP > maxHP / 2` with an integer halving, so
a target on exactly half -- and on an odd maximum, 10 of 21 -- takes the doubled
hit, where the natural `cur < max / 2` would not. Wake-Up Slap's
`CheckSubstitute` jumps past the doubling AND the wake together, so a sleeping
Pokemon behind a Substitute takes 60 and stays asleep. And Gyro Ball's formula
divides by the attacker's speed, which a paralysed Pokemon on a speed floor can
make zero.

The four effects are named with pret's behaviour names rather than after their
moves. `gen4_moveeffect_check` rejected move-names outright -- the port may not
name an id neither source licenses -- and the rename fixed more than the check:
the names now match `gen4EffectName` instead of becoming a third spelling, and
`WRING_OUT_EFFECT` had mislabelled an effect that serves Crush Grip too.

Two checks turned out to be wrong rather than merely out of date. One asserted
the port names only ids from a hardcoded list of five -- a hardcoded twin of a
fact in `Gen4Moves`, the same fault repaired in `gen4_mining_art_check`, which
went stale the instant a sixth arrived while the invariant worth having was
never checked; it now derives the set and requires every such id to be
implemented. The other could not distinguish "the engine lost an effect name"
from "the id was promoted to a handler row", so all four promotions reported as
losses; the handler row now tells them apart, and the fault arm still fires when
a name goes missing with nothing replacing it.

`tools/gen4_dynamic_power_check.lua` (46 checks) pins both halves of the wiring,
every formula at its boundaries, and re-reads the four effect scripts so the
constants it was written from are the ones still on disk.

**These five moves join the re-extract queue.** The engine implements them; the
installed cache was written before it did and still carries their effect
numbers, which `gen4_cache_integrity_check` now reports as exactly that -- the
engine is right and the data is behind it. The same is true of Leer and Growl,
whose names have been correct in code since pass 148.

## How to check all of it at once

    python tools/run_checks.py --rom <platinum.nds> --cache <platinum/data/generated> \
                               --pret <pokeplatinum> --arm9 <arm9.bin> \
                               --emerald <emerald/data/generated> --assets <platinum/assets/generated>

Runs all 52 checks with the arguments each one states for itself, read from its
own invocation line rather than from a list in the runner. The distinction that
matters in the output is `PASS` from `PASS*`: the second means an optional input
was not supplied and the check ran a SMALLER version of itself and passed that.
`gen4_icon_check` without an ARM9 dump reports six checks where the full run is
nine, and the three it skips are the ones that compare the port against the
cartridge. `SKIP` means a required input was absent and the check did not run at
all, which is not a pass either.

This exists because a check given the wrong input does not say "wrong input" --
it scans what it was given and reports a fault. That happened three times in
three passes, and twice the phantom was believed: the party-icon palette table
"disagreeing with every verified species" (the .nds passed where an ARM9 dump
was wanted), "the overworld would not enter the gym" (a working copy without
`data/scripts/`), and 18 of 19 ball-throw sets broken (12 of 187 asset frames
present). The latter two now exit 2 with the real reason instead.

On a complete checkout the only expected red lines are the two that say the
extracted cache is behind the engine.

## Route 201's catching demonstration: Dawn lost to an underscore

Reported from play as "Dawn is missing from the pokeball catching intro it's
showing the old man placeholder". Route 201 has two objects on tile (9,21):
Professor Rowan, and a runtime-variable slot that the entry script fills with
the player's counterpart. Everything about that worked -- the script ran, the
gender branch picked graphics id 177, the archive member existed, the PNG was on
disk -- and the name lookup missed on an underscore, so the object kept its
placeholder and drew nothing, leaving Rowan alone where Dawn should stand beside
him.

A graphics id reaches a sheet through two hops and the second joins by NAME:
`Gen4ObjectGfx.name` is transcribed from pokeplatinum's `OBJ_EVENT_GFX_*`
constants, while the key is the NARC's own member name. 209 agree exactly; two
do not -- `player_m_holding_poke_ball` and `player_f_holding_poke_ball` against
members 155 and 156, `player_m_holding_pokeball` and `player_f_holding_pokeball`.
Neither list is wrong: pokeplatinum writes both spellings in one line of
`object_event_gfx_data.c`, and uses `POKEBALL` in the constant for the
distortion-world pair. The join is normalised now, with the exact name still
tried first.

**This one needed no re-extract** -- the cache already held the member under the
archive's spelling, with its picture. `tools/gen4_object_sprite_check.lua` (36
checks) pins the two, asserts the var slots and signposts still resolve to
nothing, asserts no two archive names collapse to the same normalised key, and
runs the hop itself for Dawn, for Lucas and for ids that must answer nothing.

Rowan's opening was checked end to end first and is correct: Dawn's four intro
figures extract properly (the PNG was opened and looked at), the member indices
match pokeplatinum's `{14,15,16,17}`, and the screen was driven headlessly
through the ball, the Buneary release and the gender choice without stalling.

## The parity map, measured

Of the script corpus' 78,093 instructions, 97.55% lower; 383 distinct opcodes
do not, 1,915 occurrences in all. Grouped by feature, largest first:

    Battle Tower / Frontier      35 opcodes  240 uses
    Bag and items from scripts    9           169      <- single-player
    Message buffering / text     25           158
    Super Contest                37           140
    Link / Union Room / Wi-Fi    20           129
    Berry growing                 9           128      <- single-player
    Day care / breeding          15            40
    Ribbons                       4            38
    PC / box storage              6            36      <- single-player
    Pokemon forms                 6            24
    Turnback Cave                 1            20
    the Underground               3            18
    Poketch                       3            12
    unclassified                170           563

The bag from scripts is the one a player meets first: `checkpockethasitems`
(72), `getselecteditem` (44) and `openbag` (44) are a script opening the bag and
reading the choice, and nothing in `src/` implements them. In the unclassified
group are Game Corner coins (34 uses), HM cut-ins, `trysavegame` with its saving
icon (27), the Catching Show and fossil revival.

Not a gap, though it reads like one: `getapproachingtrainerid` and its two
siblings are the SCRIPTED trainer walk-up. The overworld has a native sight path
covering Sinnoh, so ordinary trainer battles work.

## Built, read, and not in the cache

`gen4_cache_wiring_check` compares MODULE names both ways. It cannot see a
feature whose data rides as a key inside `constants`, and three finished
features were in that blind spot: the **berry patches**
(`gen4BerryGrowth`/`Positions`/`Initial` -> `Gen4BerryPatches.lua`), the **honey
trees** (`gen4HoneyEncounters` -> `Gen4HoneyTrees.lua`) and the **four in-game
trades** (`gen4Trades` -> `Gen4Commands.lua`). The extractor writes them, the
engine reads them, the installed cache has none of them.
`Gen4BerryPatches` returns nil without its data and says nothing, so all three
are finished in the repository and absent from the running game.

`tools/gen4_constants_wiring_check.lua` now checks all three directions, with
the key list parsed from the extractor's own `constants` literal rather than
copied, and names the consumer for each key a cache is missing.

## CORRECTION to the parity map above

The map in the previous section was measured against a container working copy,
not the repository, and overstated the gap. Against the repository's own files:
**98.07% of instructions lower and 358 opcodes do not**, 1,506 occurrences --
not 97.55%, 383 and 1,915.

**Twenty-five opcodes and 409 uses were already implemented**, and they are
exactly the three areas the map named as the place to start: the bag from
scripts (`openbag`, `getselecteditem`, `checkpockethasitems` -- 160 uses),
berry growing (all nine), and the PC (`openpokemonstorage`). The scripted
trainer approach and the honey trees are done as well.

The corrected top of the queue is Battle Tower (35 opcodes, 240 uses), the
Super Contest (37/140), link play (20/129) and the unnamed numeric opcodes
(43/217) -- facilities rather than the main line. What remains on the main line
is small: message buffering (24/138), the day care (15/40), ribbons (4/38),
forms (6/24), Turnback Cave (1/20) and the Underground's vendors (3/18).

An analysis is a claim about the repository. Staging a file before EDITING it
was already the rule; the same applies before MEASURING it, because a stale
copy is wrong in the direction that looks like progress -- it reports finished
work as outstanding.

## Pass 167 -- trainer dialogue: the index that was never extracted

`scripts_battles.s` is the shared script every trainer battle in Sinnoh
runs through, and three of its commands were unlowered -- `OpenMessage`,
`GetTrainerMessageTypes`, `PrintTrainerDialogue` -- so every trainer in the
region fought in silence. The 2,497 lines were already in `text.lua` under
`TEXT_B0617_*`; what was missing was the 12 KB index in
`/poketool/trmsg/{trtbl,trtblofs}.narc` that says which line belongs to
which trainer.

Field-script opcode coverage, re-measured after correcting a two-row
alignment bug in the enum parse: **96.61%** of 35,832 invocations
(332 of 692 opcodes lowered; 1,216 invocations over 360 opcodes remain,
overwhelmingly facilities, link play and contests).

`scripts_battles.s` is now **136 macro uses, 0 unlowered**. Also fixed in
the same file: `getmovementtype` (a `pending` stub -- nine disguised
trainers never revealed themselves), `getrematchtrainerid` (an unwritten
var on the path taken every time you talk to a beaten trainer), and the
approach trio (an unwritten var inside a jump-to-self, i.e. a hang the
moment that entry is dispatched).

Controls: our opcode table agrees with pret name-for-name at 840 of 840
indices; the trainer-message walk reaches 2,497 records of 2,497, matching
bank 617 exactly; a cache index built from the cartridge joins to the text
already on disk at 2,497 of 2,497.

**Awaiting the re-extract** -- `gen4_trainer_messages.lua` is not in any
cache yet, so trainers stay silent until the next import.

## Pass 167b -- the re-import landed

Trainer dialogue is live: `gen4_trainer_messages.lua` (53 KB) reports 836
trainers, 2,497 (trainer, type) pairs, and **2,497 of 2,497 indices resolving
to a line in bank 617** -- matching exactly the figures predicted from the
cartridge before the extractor stage existed.

The same import closed the other three red lines: `gen4_sheet_layout_check`
(185 `layoutFrom` records now in the cache), `gen4_constants_wiring_check`
(the berry patches, honey trees and four in-game trades are live rather than
inert), and `gen4_cache_integrity_check` (the 5 moves that kept a number now
carry their effect).

`gen4_cache_integrity_check`'s unimplemented-effect pin went **59 -> 54** --
pass 161's four dynamic-power handlers across five moves (Wring Out and Crush
Grip share an effect id). The pin still rejects the pre-import cache, so it
discriminates rather than merely accommodates.

Three checks that read picture files -- ball throws, terrain textures, battle
scenes -- were reporting a container with no asset tree as catastrophic art
loss. Against a real install: **19 of 19 ball sets, 187 of 187 frames; 3,693
of 3,693 terrain textures; 185 battlescene checks, 0 failures.** All three now
exit 2 rather than 1 when nothing at all is present, and each was proved still
to fail on one genuinely missing file.

Two tooling bugs found in passing: `gen4_battlescene_check` took an "assets
dir" and joined it to paths that already begin `assets/generated/`, so the
suite went red for anyone who supplied `--assets` correctly (160 false
failures); and `gen4_texture_files_check` took no path argument at all, so it
had reported SKIP on every suite run since it was written.

Suite with every input supplied: **PASS=53, REPORT=4, NOSPEC=41** -- no FAIL,
no SKIP, no PASS*.

**Nothing is marked complete.** The engine side is self-consistent and none of
it has been seen on screen; the play-test list is unchanged.

## Pass 168 -- the other shared script, and a truncating decoder

`scripts_field_moves.s` carries every use of Cut, Rock Smash, Strength, Rock
Climb, Surf, Waterfall, Defog and Flash in Sinnoh. Nine commands were
unlowered, 23 uses -- and three of the nine were **variable length**, which
`Gen4Script.decode` handled by stopping the walk. So those three were not
three missing rows but **four truncated scripts**.

pokeplatinum states the width rule outright (`asm/macros/scrcmd.inc`): one
byte, plus a word only when that byte is FIELD_MOVE_FUNC_CHECK_ACTIVE.
`Gen4ScriptOps.VARIABLE_SPEC` encodes it; an undefined sub-function still
refuses, because `ScrCmd_DoStrengthFunc`'s default arm is GF_ASSERT(FALSE).

Same corpus, before and after: **8 variable stops become 4** (end 4,070 ->
4,074), and the four that moved are exactly the three field-move commands.

Three corpus pins rose with it -- blocks 8,567 -> 8,571, instructions walked
78,093 -> 78,189, distinct opcodes **718 -> 720**, coverage 98.06% -> 98.15%.
The two new opcodes are 0x0C3 and 0x0C4, which sit on the line directly after
`DoFlashFunc`/`DoDefogFunc` -- so they had **never been seen anywhere in the
cartridge**, because the only places they occur are past a truncation point.

Those two opcodes are the same function byte for byte (both clear the
overworld weather) and lower to one row. That Platinum clears *weather* for
Flash is the finding: a dark cave and a foggy route are one mechanism on this
cartridge. `g4_overworld_weather` reads the clear back, or Defog would clear
the fog and the next read would still report fog.

Both shared scripts are now hole-free: **field_moves 297 uses / 0 unlowered,
battles 136 / 0**. New check `tools/gen4_field_moves_check.lua` (98 checks)
asserts both, and its first three sections need only the repository.

Suite: **PASS=54, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*.

**Nothing is marked complete.** Rock Climb is declared pending (no engine
climbs a rock wall) and Flash sets its flag but changes nothing on screen:
`PaletteFX.daytimeFor` takes a `flashUsed` argument and has **no callers at
all**.

## Pass 169 -- the item bands, and a census that lied the safe way

Ranked by **reach** -- how many map objects route into each shared script
band, which the cache records -- the two item bands sit third and fourth
(`visible_items` 329 objects, `hidden_items` 262) and had **one missing
command between them**.

Both end a pickup with `IsItemTMHM` and two `GoToIfEq`s. Unlowered, the var
neither jump tested was ever written, so neither was taken and the script fell
into `End` -- `AddItem` had already run, so **591 pickups put the item in the
bag and told the player nothing**.

`Item_IsTMHM` is an id range, not a pocket lookup. The two were compared:
over 446 items they select the same 100 rows (92 TMs + 8 HMs) with nothing in
one and not the other, and the ends are clean. The range is what the cartridge
uses, so that is what this is -- derived from item names, not hard-coded.

**The census was under-reporting.** It matched `L.name =` with a pattern and
could not see the nine berry commands, which are lowered inside a loop -- so
it reported the 118-tree berry band as having fourteen holes when it has none,
and sent this pass after finished work. Both checks now ask
`Gen4ScriptVM.lowered()`, the real table, and a canary asserts the
loop-assigned case so the pattern cannot come back.

Section 4 of `gen4_field_moves_check` now asserts an **invariant** rather than
a file list: no band with reach >= 10 may contain an unlowered command,
`common_scripts` excepted with a ceiling. It caught two bands the ranking had
skipped on its first run (`mystery_gift_deliveryman`, `tv_reporter_interviews`
-- both `messagefrombank`, which turned out to be the existing
`g4_message_bank` row). Both fixed.

**1,957 of 2,054 banded objects are now on a hole-free path.** Every band with
reach >= 10 is clean except `common_scripts` (97 objects, 43 uses).

Why instruction counts mislead, demonstrated: deleting the single
highest-reach command in the game moves the corpus by **2 instructions of
78,189**. The `lowered` floor catches it (re-levelled 76,740 -> 76,781); the
coverage percentage does not move at two decimals.

Suite: **PASS=54, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*.

**Nothing is marked complete.** Next: `common_scripts`, where three of the 43
are core-loop -- `survivepoison`, `blackoutfrombattle2` and `hatchegg`.

## Pass 170 -- field poison in Sinnoh cannot faint a Pokemon

`Pokemon_DoPoisonDamage` is `if (hp > 1) hp--`. That single comparison is the
rule: **field poison walks a Pokemon down to 1 HP and stops.** The counter
pokeplatinum calls `numFainted` counts mons that REACHED 1, and the script it
then runs loops `SurvivePoison`, which cures anything poisoned at exactly 1 HP
and prints "<MON> survived the poisoning!".

`OverworldState:applyFieldPoison` fainted them and whited the player out,
because it was written from Gen 2's rule and applied to every cartridge. **A
rule that differs rather than a feature that is missing** -- nothing errored,
nothing logged, every check stayed green, and the game occasionally took a
Pokemon and half the player's money for something the real one cannot do.

Gated on the cache; Gen 1/2/3 and the Crystal hacks keep their rule, and the
new check asserts that explicitly.

Two corrections caught by reading tables rather than identifiers:
FRIENDSHIP_EVENT_POISON_SURVIVE is `{-5,-5,-10}` -- friendship goes **down**,
despite the name -- and those are the *same* numbers as Gen 2's PIKAHAPPY_PSNFNT
over the same bands, so Gen 4 changed only when the penalty fires.

Also: the entry test was `status == "PSN"`, so **badly** poisoned mons were
exempt from the whole mechanic. The cartridge tests `(TOXIC | POISON)`.

`BlackOutFromBattle2` (0x14B) is byte-identical to 0x14A and still must not
share its row: 0x14A's no-op is justified by its caller (a lost battle), and
0x14B's only caller is the poison whiteout, where no battle happened. Declared
`pending` -- unreachable under the new rule.

`hatchegg` lowered by **extracting** the hatch out of `stepEggs` into
`OverworldState:hatchEgg` so both doors share it; proved a pure move (all 32
lines verbatim, none left behind).

New check `tools/gen4_field_poison_check.lua` (41 checks), with section 4
re-deriving the rule, the `== 1`, the `(TOXIC | POISON)` test, the delta row
and both band limits from pokeplatinum.

`common_scripts`: **43 -> 40**. What remains is saving (11), the PC (4), the
Underground (4) and misc. **Saving is next and deliberately not this pass.**

Suite: **PASS=55, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*.

**Nothing is marked complete.** The Gen 1/2 side matters here: walking poisoned
in Crystal/Gold/Silver/Prism must still faint, exactly as before.

## Pass 171 -- saving in Sinnoh is a script, and twelve of its commands had no row

The START menu's SAVE in Platinum is not a routine, it is a script:
`start_menu.c:1327` starts `SCRIPT_ID(COMMON_SCRIPTS, 5)`, which is
`CommonScript_SaveAndStoreResult`. So does the Underground descent
(`field_map_change.c:1175`), and eighteen `callcommonscript 2006` sites reach
the sibling entry. **Twelve commands in that script had no lowering**, so every
one of those paths ran into an unlowered command. Lowered as a group, because
they only make sense as one.

`checksavetype` (0x12C) is asked **twice** and its four answers decide which of
five messages the player reads. Nothing fails if it answers wrongly -- the
player just reads the wrong line on every save in the game. The four arms live
together in `src/script/Gen4Save.lua` in the cartridge's own order; the numbers
are `generated/save_types.txt`'s file order from zero, corroborated by
`script_manager.h`'s own note that *"0 here can mean overwrite or that the
player canceled"*.

**`fullSaveRequired` is derived, not hooked.** The cartridge sets it by hand
from ten places in `pc_boxes.c` plus four elsewhere. Porting that as a flag
would mean hooking every box mutation in this engine -- the recurring bug, on
the subject where it costs the player their game. So the boxes are
**fingerprinted** at save time and "the boxes changed" becomes a comparison.
HP is deliberately out of the fingerprint: a nurse is not a box operation.

**One arm is cold on purpose and still wired.** `SaveData_OverwriteCheck` is a
one-save-per-cartridge refusal; this engine has slots, so reproducing it would
make a new game on a used slot permanently unsavable. `overwriteBlocked` is
false with the reason recorded, and the check *forces* the arm with the
predicate held true, so cold is not the same as dead.

**The write is one sentence now.** Gen 3's `special SaveGame` already had the
right paragraph, so it moved verbatim into `src/script/ScriptSave.lua` and both
generations read it -- and Hoenn's special 96 is graded in the new check
alongside Sinnoh's. The source itself asserts that neither script file reaches
`writeSave` directly any more.

0x258/0x259 are unnamed in pokeplatinum and not a mystery: the player's save
pose, begun as a task and ended. The guard is the behaviour -- `ov5_021E0F54`
returns NULL unless the player is `PLAYER_AVATAR_WALKING`, which is why saving
on a bicycle does not drop you off it.

The save info panel's labels are read out of bank 534 rather than typed, and
two details came from reading rather than guessing: the dex count is
`Pokedex_CountSeen` **not owned** (the engine's own Gen 1 panel counts owned),
and the dex row is dropped entirely without a Pokedex, with the window two
tiles shorter.

**A pass-170 correction.** Its survive-poison line was written from the
message's pret *identifier*, not its text. Bank 213 entry 66 reads *"<MON>
survived the poisoning.\nThe poison faded away!"* -- two sentences, breaking
elsewhere. Now read from the extracted bank, via
`Gen4ScriptBands.TEXT_BANK.common_scripts` rather than a literal 213.

New check `tools/gen4_save_check.lua` (136 checks). **Nine faults planted, all
nine caught**, each verified to have landed, control re-run on md5-identical
files.

`src/script/Gen3Commands.lua` had moved on the device in parallel (warp x/y are
value-or-variable operands; Petalburg's sliding doors pass vars). The device
copy was adopted as the base, lone-LF count preserved, and this pass's change
applied on top.

`common_scripts`: **40 -> 25** -- fifteen uses across twelve opcodes.

Suite: **PASS=56, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Gen 3
clean (5 PASS), script registry 416.

**Nothing is marked complete.** Saving wants real play-testing: both prompts,
the quick-save message after an untouched save, the full-save message after a
deposit, the missing dex row, NO at either prompt, saving on a bike, the
Underground descent -- and saving in Crystal, Gold/Silver, Prism and Emerald,
which must behave exactly as before.

## Pass 173 -- nine kinds of Sinnoh scenery that answered nothing

`Field_TileBehaviorToScript` (overlay005/field_control.c) maps a tile's
**behaviour byte** to a script id, and it is the only thing that makes the PC,
four bookshelves, the trash can, three mart shelves, the wall map, the
bike-parking sign and the television interactive. None of them is an object
event and none is a bg event -- there is nothing in the map data to find.

This port had a Gen 2 arm (collision class $93) and a Gen 3 arm (the PC
metatile) and **no Gen 4 arm at all**. Measured against the cache: **3,527
tiles across 289 layouts**, the PC alone on 66 maps.

It is the fault Gen 3 already had and already fixed -- that branch's own note
reads *"what it opens is the CARTRIDGE'S OWN SCRIPT, not this port's PC menu
... it left the boxes unreachable from every Poke Centre in the region"*. Gen 4
was still calling `openPC`, which jumps straight to the storage grid, so
`CommonScript_PC` never ran: no Bebe's PC, no PLAYER'S PC, no professor's dex
rating, no HALL OF FAME row, no COMPARE POKeMON, no boot-up animation.

`src/world/Gen4TileScripts.lua` holds the table, by behaviour **name** rather
than number (`Gen4Behaviors.PACKED` already is the one place that says which
byte is which), with the cartridge's two facing guards -- the PC and the TV
answer only a player facing north. Rock Climb and Surf are deliberately out:
neither is an equality test, each is a derivation of its own, and this port
reaches Gen 4's field moves through the party menu. Waterfall is in, because it
has no guard and nothing answers a press at one today.

**One spelling of "run script n of band b".** The honey tree had the only copy,
inline; there are fourteen callers now. `SCRIPT_ID(band, n)` is 0-based and
`entries` is a Lua array, so entry n+1 is script n -- and the honey tree is the
control for that convention, since it has been reaching `entries[9]` for
`COMMON_SCRIPTS 8` since it was written.

**Eight of the nine work the moment they are reached**: `field_moves` and
`tv_broadcast` are at zero unlowered and `bg_events` has one -- `openregionmap`,
which wants a Sinnoh region map this port has not extracted.

The PC's own six commands took `common_scripts` **25 -> 19**. The three
prop-animation rows share the DOOR's named no-op (same NSBCA-on-an-NSBMD-prop
absence, stated once); both TV-segment commands now share one row;
`checkishalloffamecorrupted` answers FALSE because this engine has no save
sector to fail a checksum, and answering TRUE would tell the player their
records are damaged when they are not; `openpchalloffamescreen` is `pending`
rather than a no-op **because the data exists** -- `save.hallOfFame` has been
collecting rows all along and what is missing is a screen.

New check `tools/gen4_tile_script_check.lua` (118 checks); six faults planted,
all six caught. The one worth naming: with `compile` reading `entries[index]`
instead of `entries[index + 1]` every row still resolves *something*, so a
bookshelf would have answered with the trash can's line, silently. The check
asserts the resolved LABELS, not that the slots exist.

**Two of this port's own checks caught this work**, both correctly.
`gen4_save_check`'s canary named `checkishalloffamecorrupted` as its
"still-unlowered" subject and this pass lowered it -- a canary whose subject is
something somebody is trying to fix has a half-life. It is two derived
assertions now, neither of which can go stale. `gen4_trainer_message_check`'s
`pending` pin went 3 -> 4, which is the pin doing its job.

Suite: **PASS=58, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Gen 3
clean, registry 417.

**Nothing is marked complete.** Play-test items 28-37: the PC from a Pokemon
Centre (menu, not the grid), approaching it from the side, the storage rows,
bookshelves, trash cans, mart shelves, the TV, bike parking, the wall map, a
waterfall, the post-game Hall of Fame row, and that honey trees still work.


## Pass 175 -- TM/HM teaching

A screenshot of HM01 in the bag answering *"This isn't the time to use that!"*,
and two faults behind it.

**One absent field.** `BagMenu.useItem` gates the entire machine flow on
`def.machine`; of the 446 items in a Platinum cache, **zero** carried it. Gen 1,
2 and 3 extractors write it and the Gen 4 one never has. Every earlier piece of
TM work -- the party alias's `tmhm` key, the learnset mask, bank 453's
ABLE!/UNABLE! -- was correct and unreachable.

`ItemEffects.markGen4Machines` derives it the way `Item_MoveForTMHM` does: the
item **id is the index** into `constants.tmhmMoves`. Measured: ids 328..427
unbroken, 92 TM then 8 HM, 100 array entries. The item NAMES are the check on
the ids rather than a second mechanism -- TM01 must land on index 1 and HM01 on
93, and a disagreement stamps **nothing**, because a wrong split does not fail,
it teaches Rock Climb where it should teach Focus Punch. Stamped at load beside
`markFormsTrueColor`, so an existing cache is fixed without a re-import.

**And a line with a hole in it.** With the record stamped the bag printed *"It
contained ."* -- bank 7 entry 60 reads string slot 0 in both halves and nothing
filled it. `TMHMUseTask` fills it with `StringTemplate_SetMoveName(template, 0,
move)`, so `Gen4Text.buffer` does, and `Gen4Text.resolve` hands the game to
`gen4Markup`. No gsub.

**The field-poison line had been stripping nothing for months.** It spliced the
name in itself and stripped a trailing `\r`; the decoder was corrected to `\v`
(0x25BC) and that gsub was not. Measured: **0 of 46,053 cartridge strings
contain a carriage return.** Same bug, same shape: one idea spelled two ways in
two files that never meet.

Four more of the same found by the sweep, not argued: the Underground menu's
row labels and `g4_buffer_floor` read their banks raw; `bufferKind` marked up
two of its branches and not the rest, so a bag pocket or Poketch app name went
into a string slot with its tokens on; and `buffertmhmmovename` carried its own
copy of the item-to-move join with a literal 92 in it.

New check `tools/gen4_machine_check.lua` (71 checks), ten faults planted.
**Three did not land first time**, and each was worth more than the assertion
it tested: BagMenu's buffer call was a cold arm because the check buffered the
name itself; `src:find("markGen4Machines")` still matched `markGen4MachinesXX`;
and one plant **never applied at all** because `perl` ate `\v` and `\f` before
`\Q` could quote them. A measurement that cannot fail says nothing -- including
the apparatus.

Suite: **PASS=60, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Gen 2
and Gen 3 clean, registry 417.

**Nothing is marked complete.** Play-test items 41-48: teach a TM and an HM
from the Platinum bag (both boot-up words, the wait, the question, YES and NO),
a mon that reads UNABLE!, teaching at four moves, the field-poison line's box,
a department-store lift's floor labels, a pocket name in a line, and one TM in
Crystal to confirm Gen 1-3 are untouched.
