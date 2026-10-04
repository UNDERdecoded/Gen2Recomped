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


## Pass 176 -- `common_scripts` 19 -> 7

The last band with reach that still had holes, and this takes everything left
whose subject pokeplatinum names. Pass 171 took the save dialogue (40 -> 25),
pass 173 the PC (25 -> 19); this is 19 -> 7.

**Two commands that write real state.** `givetrap` and `givesphere` both end
`*destVar = Underground_TryAdd...()`, and every call site follows with a
`gotoif` on that var -- so unlowered they did not merely fail to add a trap,
they left the var holding the previous comparison and the script branched on
it. The inventory is the cartridge's: 40 slots each, a zero sentinel
(`TRAP_NONE` / `SPHERE_NONE`, line one of their generated enums), the sphere's
type and size in the same slot index of two parallel arrays, and
`MAX_SPHERE_SIZE` 99 that an oversized sphere **saturates** at rather than
being refused. It lives in `save.underground`, beside the dig spots.

**Four bank numbers, established three ways**, because a wrong one does not
fail -- it prints a trap called "Yellow Cushion". The line-number rule; three
numbers already in the port sitting either side of them; and the content item
for item -- bank 630 entry 1 is "Move Trap UP" and `traps.txt` line 2 is
`TRAP_MOVE_UP`, so **the trap id is its own bank index**, 14 of them agreeing,
and the five sphere types in 628 the same. That agreement is an assertion.

**Five honest answers rather than five stubs.** `countmailinmailbox` and
`countuniquesealsinsealcase` lower onto `g4_no_feature` -- this port has no
mailbox and no seal state at all, zero is the true answer, and the var still
gets written because the branch reads it. `opensealcapsuleeditor` is `pending`,
a whole screen. `waitfortransition` is a no-op with its reason: it is
`FieldTransition_FinishMap`, and in this engine the warp owns the teardown.
`messagefromtrainertype` takes no operands -- the entry is the target object's
own trainer type, which a Gen 4 object record already carries.

**A live bug the new check found on its first run.** `pending(verb, what)`
installs the handler and returned nothing, so `Commands.x = pending("x", ...)`
**overwrote it with nil**. `g4_open_hall_of_fame`, added in pass 173 and pinned
by `gen4_trainer_message_check` ever since, had never had a handler --
`gen4_seam_check` had been reporting it unresolved and now reports *"every
emitted verb resolves."* One idea, two spellings, one silently broken.

**And a canary with a to-do item as its subject.** `gen4_tile_script_check`
asserted `VM.lowered("opensealcapsuleeditor") == false`; this pass lowered it.
Second time -- `gen4_save_check` named `checkishalloffamecorrupted` and pass 173
lowered that. It names nothing now: over all 840 opcodes the detector must say
yes to something and no to something, with the no being `false` rather than nil.

New check `tools/gen4_underground_inventory_check.lua` (81 checks), nine faults
planted and **every plant md5-verified to have applied** before the run was
believed. The seven commands left are not the same kind of backlog: five are
unnamed in pokeplatinum too (a bare `sub_0209ACF4` with no subject; `2f6` gates
on Wi-Fi), and the two shard-cost rows need `sTeachableMoves`' four costs,
which want their own extraction stage.

Suite: **PASS=61, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Gen 2
and Gen 3 clean, registry 421.

**Play-test items 41 and 42 are DONE, confirmed from play** (*"the last fixes
worked for the teaching of tms and hms"*). 43-48 are still open. New items
49-55: a sphere and a trap from a dug wall and the forty-first refused, a line
naming a trap or a sphere, a contest backdrop named in a line, the PC's Hall of
Fame row (which until this pass reached no verb at all), an NPC whose line is
chosen by trainer type, and the poison whiteout end to end.


## Pass 177 -- Sinnoh's weather

`applyMapWeather` opened `if not GameVersion.isGen3() then return end`, so every
Platinum map's weather byte was stored by the extractor, read by one script
command, and shown to the player nowhere. **133 of 593 maps set a weather and
not one of them looked like anything** -- 51 of them fog. Second region, same
hole as Hoenn's ninety maps.

**Darkness is a WEATHER in Platinum**, which is the fact that settles an open
item from pass 171. `field_map_change.c` substitutes CLEAR for
`OVERWORLD_WEATHER_DARK_FLASH` (16) when the Flash flag is set -- so Flash does
not light a cave by picking a palette row, and `PaletteFX.daytimeFor`, which has
no callers, was never going to get one. It is Gen 2's answer to a question
Sinnoh asks differently. Defog clears FOG (14) only; DEEP_FOG (15) is not
clearable and adding the obvious second row would be a guess.

**Five maps have a calendar.** Weathers 32..36 are columns of
`sYearlyWeather[366][5]` read at the day of the year -- Route 212 south, 213,
216, Acuity Lakefront, Snowpoint City. All 1,830 entries are transcribed and
**re-derived from pret one at a time** by the check. The leap-year correction is
two halves in two files that cancel (rtc.c lays March onward out as 365 days and
adds one back in a leap year; the weather code subtracts one and adds one in a
non-leap year), so it is ported as written and both halves are graded; 1 March
must read the same row in 2024 and 2026.

**Flash and Defog were on no party menu at all** -- in `Gen4FieldMoves.ids` and
nowhere else, so a party carrying Flash in Wayward Cave had no way to use it.
They are offered now under one condition each, the weather, because
`FieldMoves_CanUseMoves` gates them on nothing else. Selecting one runs the
cartridge's own script (`scripts_field_moves.s` entries 14 and 15, confirmed by
`FieldMoves_FlashTask`'s `SCRIPT_ID(FIELD_MOVES, 15)`), which already carries
the message, the cut-in, the flag set and the in-place weather clear.

**One saved value.** `getoverworldweather` reads `save.gen4WeatherActive` now
rather than the map def -- Route 213's header is 33, a calendar id, which is not
a weather -- and the in-place clear moves the drawn value too, or Flash would
have reported success and left the cave dark until the next load.

**Six ids pokeplatinum has not named either**, covering 57 maps including 32 of
Mt. Coronet's interior. They are named after their own ids and given no look at
all -- not `false`, which would launder them into the 460 maps that really are
clear. Nothing is drawn for them on purpose.

Measured: **65 maps now draw a weather** that drew nothing before (51 fog, 5
calendar, 8 others, 1 dark cave), and the check floors that number.

New check `tools/gen4_weather_check.lua` (116 checks), twelve faults planted,
every plant md5-verified. One did not land first time -- the party-menu
assertion searched the whole module for `weatherOffers` and `useFieldMove` calls
it too, so deleting the gate from the row-building loop passed; it is scoped to
`actions()` now.

Suite: **PASS=62, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Gen 2 and
Gen 3 clean.

**Nothing is marked complete.** Play-test items 56-64: fog on one of the 51
maps, Defog from the party menu (the row present only while the fog is up, and
the fog going immediately), Wayward Cave dark and navigable, Flash lighting it
and staying lit through a doorway, the Flash row disappearing afterwards, the
five calendar maps, battle weather carried into a fight, Mt. Coronet unchanged
on purpose, and one rainy route each in Emerald and Crystal to confirm Gen 1-3
are untouched.


## Pass 178 -- door sounds

The three door-animation commands lowered onto `g4_noop`. Over the whole
decoded corpus they are **194 invocations** -- the largest declined subject in
the port.

**The reason for declining them had expired.** The comment said this port "has
no SE bank for Gen 4 yet"; `audio.lua` carries 2,030 sound effects keyed by the
cartridge's own SSEQ symbols, and `g4_play_sound` has been using them all
along. Third instance of a declined feature outliving its blocker, after
`g4_overworld_weather`'s "the port keeps no saved weather" and pass 175's `\r`
strip -- so the census that found it (rank every `g4_noop`/`g4_no_feature`
subject by real invocation count) is written up as a repeatable measurement.

**The sound comes from the door's model**, so it needed three cartridge tables,
all graded against pret: the 20 names in `doorModelIDs[]` in order,
`DoorAnimation_GetSoundEffectType`'s three arms (one chime model, six sliding,
the rest hinged), and the four SSEQ symbols -- of which **two are silent on
close**, because `PlayCloseAnimation` sets `soundEffectID = 0` for sliding and
chime. A pneumatic door that creaked shut would be wrong in every Pokémon
Centre.

**The model is found by the cartridge's own hitbox** -- `(x, z, -1, 0, 3, 1)`,
three tiles wide starting one left of the named tile, because door props are
anchored on half-tiles. Measured: of the ROM's 52 `loaddooranimation` sites the
15 on a region map resolve **15 of 15**; across the whole cache **190 door
props asked at their own tile are found 190 times**, splitting hinged 111 /
sliding 76 / chime 3, so all three sound arms are reached by real placements.

The tag is overworld state, not save state (52 loads against 142 plays, so it
outlives its script -- but `MapPropOneShotAnimationManager` is a field-system
object and a saved tag would make a Jubilife door answer for a Hearthome one).
A model that cannot be identified still makes the hinged sound and logs once,
because a silent door is the fault being fixed.

**The animation is still absent** and said so in one place: NSBCA is not read
and a chunk's props are baked flat. The PC-animation rows carried the same
stale claim and are corrected rather than deleted -- they part from the doors
for a real reason, in that the PC calls `PlayAnimation` with no sound argument
where a door calls `PlayAnimationWithSoundEffect`.

New check `tools/gen4_door_sound_check.lua` (66 checks), eleven faults planted,
every plant md5-verified. **Section 0 is a canary on the model join**: the first
draft of this measurement reported 0 of 52 sites because the probe's own loader
stubbed `Gen4Archives` and every `find()` answered nil -- a zero from a dead
join looks exactly like a zero from wrong geometry. And one plant exposed a hole
in the check's own control: widening the hitbox to 64 tiles passed it, because
widening moves the far edge away from the door rather than over it. The control
probes leftward too now, and the same plant fails at 41% against a 15% ceiling.

Suite: **PASS=63, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Registry
422. Gen 2 and Gen 3 clean.

**Nothing is marked complete.** Play-test items 65-70: a hinged door creaking
open and shut; a Pokémon Centre, gym, GTS or lift hissing open and closing
**silently**; the Veilstone department store's chime; walking back out through
the inside doors; nothing animating yet, on purpose; and one door each in
Crystal and Emerald to confirm Gen 1-3 are untouched.


## Pass 179 -- the money window

`showmoney`, `hidemoney` and `updatemoneydisplay` lowered onto `g4_noop`.
Second on the declined-subject census: **109 invocations** (20 shows, 66 hides,
23 refreshes), behind the doors at 194. Not the shop's balance -- this is the
standalone window a field script puts up while you decide: the Game Corner, the
Day-Care fee, the Ribbon Syndicate, Floaroma's flower seller, the Pastoria
gates, the cafe.

**The operand order was the risk.** pret swaps the parameter names twice and
they cancel -- `ScrCmd_ShowMoney` reads left then top, `CreateMoneyWindow`
declares them the other way round, `Window_Add` takes left then top again -- so
operand one is the LEFT. Derived three ways: all three signatures, pret's 17
literal call sites, and all 20 decoded sites in the ROM, every one of which
fits on a 32x24-tile screen with this order and would not with the other.

10x4 tiles, bank 543 entries 18 ("Money") and 19 (`"${STRVAR_1 55 0 0}"`), the
balance padded to six digits **with spaces** and right-aligned to the window's
right edge -- which is what the padding is for, and why zero-padding would
print `$000007`.

**The Poke-dollar needs no constant**, because entry 19 carries the literal
ASCII `$` the DS font draws as one. That surfaced the last hand-spelling of it:
`Gen4TrainerCard` kept a `MONEY_SIGN` local whose comment ended "ShopMenu ...
will have the same fault in a Gen 4 shop; that is its own fix" -- and that fix
had landed, so the local was redundant and the forward reference stale. Seven
files read `GameVersion.moneySign` now and none keeps its own; the check sweeps
for it.

**The refresh rebuilds rather than reading live**, and that beat matters: the
window must not change when a script takes the money, only when the
`updatemoneydisplay` after it runs. The Game Corner's counter depends on it.
The panel is overworld state, not save state.

New check `tools/gen4_money_window_check.lua` (86 checks), thirteen faults
planted, every plant md5-verified. Swapping the operands was caught by the
behavioural assertions rather than the pret-signature ones -- those grade pret,
not the port.

Suite: **PASS=64, REPORT=4, NOSPEC=41** -- no FAIL, no SKIP, no PASS*. Registry
423. Gen 2 and Gen 3 clean.

**Nothing is marked complete.** Play-test items 71-76: the Game Corner's
counter (the one site at 20,7 rather than 20,2); buying coins and watching the
balance hold until the refresh; the five top-right sites; the sign being the
Poke-dollar on both the window and the trainer card; the window not surviving a
map change; and one mart each in Crystal and Emerald.

## Pass 180 -- the Underground goods PC, and a wrong answer

`checkhasroomforgoodsinpc` (16 script sites) and `sendgoodtopc` (1) lowered
onto `g4_no_feature`. Third on the declined-subject census at 17 invocations,
and chosen ahead of larger subjects because it was not merely absent: **it was
answering, and the answer was false.** `g4_no_feature` writes 0, and 0 for
"has room for goods in the PC" means *no room*, so sixteen branches were told a
PC holding nothing was full. A fresh Underground has 200 free slots and the
truthful answer is 1 -- that difference is the difference between an absent
feature and a lie about a present one.

The direct sibling of pass 176's trap and sphere inventories: same 200-slot
sweep for a NONE sentinel, same `(var, var, destVarPointer)` operand shape with
the middle operand read and dropped.

**A pass-176 invention had to be removed.** `addTrap` and `addSphere` refused
`TRAP_NONE` / `SPHERE_NONE`. No cartridge adder does: handed the sentinel it
writes it into the free slot it found and answers TRUE, because "was there a
free slot" is the only question the branch asks. The state half of my reasoning
was right -- storing the sentinel densely would make `#list` grow while the
cartridge's slot still read as empty -- but the answer half was wrong. All
three adders now share one `addDense` helper: answer yes, store nothing, and
answer no only when the inventory is genuinely full.

That mattered because the operands are not constants. Walking `scr_seq.narc`
through jumps and calls finds exactly nineteen rows for the four commands
(16 + 1 + 1 + 1, matching the census), and every operand of all nineteen is a
var -- `0x8004`, `0x8005`, destination `0x800C`. The value handed to the adder
is whatever the caller left in a var at run time, so the sentinel path is live.

`tools/gen4_underground_inventory_check.lua` extended 81 -> 112 checks rather
than replaced, keeping one owner for these invariants. Fourteen plants, each
md5-verified to have applied, each landing on its own assertion. Three of them
taught the check something:

- a destination var must be **seeded**, because `getVar` answers 0 for a var
  nobody wrote and 0 is also the honest "no" -- silence was indistinguishable
  from an answer;
- operand order needs a **source** assertion, because the handler tests call
  the handlers directly and a swapped lowering passed everything;
- the sentinel contract is written as an **invariant over all three adders**,
  not three separate cases.

Suite PASS=64, REPORT=4, NOSPEC=41, no FAIL, SKIP, ERROR or PASS*. Unchanged
from pass 179 because no file was added. Registry 423 -> 424. Gen 2 and Gen 3
clean.

Still not complete: nothing reads the 200 stored ids back, because the goods
are Secret Base furniture and the base is not built. What is fixed is the
answer the sixteen branches take, and a store already capped where the
cartridge caps it.

Play-test items 77-80: the goods PC answering yes on an ordinary save (band 93
holds twelve of the asks, band 92 four); band 211's single `sendgoodtopc`,
which shares its band with the only `givetrap` and `givesphere`; traps and
spheres behaving exactly as in pass 176 despite the sentinel rewrite; and no
Underground at all in Crystal, Gold, Silver, Prism or Emerald.

## Pass 181 -- the News Press, and the census that chooses the passes

**The ranking that has picked the last five passes was wrong in three ways**,
and none of them was visible from its numbers.

1. **It counted decodes, not positions.** The corpus walk re-decodes a block
   entered from a second address inside it, so an overlapping tail is counted
   once per path: 78,189 decodes over **57,333 distinct byte positions**, 36.4%
   inflation across 132 bands. Up to 5x on one subject. Both numbers are
   meaningful -- decodes weight by reachable paths, positions by how much of the
   corpus names a thing -- but the doc called them "invocations".
2. **A subject split across spellings ranked as several subjects.** The eight
   `initpersistedmapfeaturesfor*` rows name eight subjects and are one
   mechanism behind nine wrappers over `PersistedMapFeatures_InitFor*`. Apart:
   11, 9, 4, 3, 1, 1, 1, 1, largest ranked eleventh. Together with the two gym
   buttons and the flower clock: **53 sites, twelve rows, second-largest open
   subject.** The recurring bug eating the measurement meant to find it.
3. **The scan read `L.name =` and not `L["name"] =`**, so five rows whose
   opcodes have no name were never counted. Closing it found thirteen more rows
   and five subjects absent from the census entirely, including the Spear
   Pillar cutscene at 20 sites.

Corrected top: the scripted blackout 64 (argued), **the persisted map features
53**, menu anchor side 52 (argued), the journal 50 (was 78), the door
animation's wait 48 (argued), the move tutor 43 (was 73).

`tools/gen4_declined_census_check.lua` (NEW, 15 checks) makes the census a
checked tool: it reports both metrics, floors the corpus, asserts the two stay
distinguishable, and **requires every subject to be classified** -- an
unclassified one fails with its own name and site count, and a stale merge
entry fails too. Six subjects needed classifying on the first clean run.

**Then the corrected census was used.** Auditing all 30 `g4_no_feature` rows
for what 0 means to the branch behind them -- pass 180's lesson run as a
measurement -- found `getrandomseenspecies`: 0 is SPECIES_NONE, so Solaceon's
Pokemon News Press named a blank. Everything it needed was already here
(`save.pokedex.seen`, and `g4_dex_seen_count`'s Sinnoh filter), so the zero was
a wrong answer, not an absence.

The cartridge's default is **SPECIES_PIKACHU, written before the loop** -- so an
empty dex, and a dex whose seen species are all outside Sinnoh (the count and
the loop use different predicates), both answer Pikachu. Both asserted. The dex
walk became one `dexIDs` helper rather than two walks of the same question.

`src/script/Gen4Daily.lua` (NEW) holds the deadline countdown, which is a
**count** and not a reset: pret subtracts `daysPassed` and saturates at zero, so
a week away clears a three-day deadline rather than taking one day off it. That
needs an absolute day count -- `Gen4Weather.dayNumber` is a day-of-year and goes
negative across New Year -- so `civilDay` is days_from_civil. The two cases the
check pins are the ones that silently cost a player a day: a first poll on a
save with no recorded day counts nothing, and a backwards clock re-anchors
without counting.

Var ids derived by the enum walk and re-derived by the check behind three
anchors: `VAR_OBJ_GFX_ID_0` 0x4020, `VAR_LAST_TALKED` 0x800D, and
`VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON` 0x40E5 -- the last read out of the
cartridge's own script bytes, which is the anchor that closes the loop.
The deadline is 0x403B; line arithmetic gets it wrong by two.

**One subject the audit cleared instead of porting.**
`getsummaryselectedmoveslot` looked worse than the goods PC -- 4 is the cancel
sentinel and 0 is move slot one, so a stub forgets the first move whatever the
player picks. But all four sites are in bands 83, 181, 458 and 1103, and all
four are move-tutor bands, so the path is cold until `sTeachableMoves` is
extracted. The row's original subject was right and my suspicion was wrong;
recorded because the measurement settled it.

Suite PASS=66 (both new checks), REPORT=4, NOSPEC=41, no FAIL, SKIP, ERROR or
PASS*. Registry 424 -> 426. Gen 2 and Gen 3 clean. Eighteen plants, each
md5-verified and each landing on its own assertion.

Play-test items 81-85: the News Press naming a seen Sinnoh species and never a
blank; the pick varying; a brand-new save still getting a real name; the
deadline surviving a reload and losing the days that actually passed; and no
News Press and untouched daily resets in Gen 1, 2 and 3.

## Pass 182 -- two infinite script loops, hidden by a subject name

Pass 181's third fault was that the census read `L.name =` and not
`L["name"] =`. Four rows use the bracket form because their opcodes have no
name, and all four were named after **the map they appear on** rather than what
they do: "a Spear Pillar effect" (18C and 20D), "a Spear Pillar cue" (2FB), "an
Iron Island cue" (2B6). Named that way they read as unimplementable set-pieces.
Three were nothing of the kind.

**`scrcmd 20D` was a hang.** `ov6_02243004` is a ten-mode switch over one
overlay-6 field effect; eight modes start or stop something and fall through to
`return 0`, and exactly two -- 1 and 6 -- are completion polls reading a staged
animation's state counter. The scripts poll them in a backwards jump:

```
20d 0x1 0x800C  /  comparevartovalue 0x800C 0x0  /  gotoif 1 -18
```

`g4_no_feature` writes 0, which for those two means "not finished" -- so the
answer never changed and the script span on the spot. Two infinite loops, bands
236 and 237, on the Spear Pillar path. An effect the port never starts has
already finished, so 1 is both the non-hanging answer and the true one; the
other eight modes keep writing 0, as the cartridge does.

**The stub was right for eight of the ten modes**, which is why nobody looked.
A row that misbehaves in two cases out of ten is far harder to doubt than one
that misbehaves always.

The check derives the loop from the ROM rather than describing it: it finds all
four 20D sites and asserts each poll-mode site is followed by a compare against
zero and a `gotoif` whose target is **the poll instruction itself** (5 + 6 + 7
bytes, operand -18).

**`scrcmd 18C` is `MapObject_TryFace`** -- "turn this object to face a
direction", fifteen sites, and a function `ScrCmd_FaceTargetObject` and
`trainer_encounter.c` already call, so the port did this under another name.
The direction table was already here too: `g4_player_dir`'s
`FACING = { up = 0, down = 1, left = 2, right = 3 }` matches
`DIR_NORTH/SOUTH/WEST/EAST`, so `FACE_NAME` is that table **inverted at load**
and the check round-trips all four directions through both halves.

**Two stay no-ops, now argued.** `2B6` sets or clears `MAP_OBJ_STATUS_18`, the
flag `sub_02063F00` checks when deciding whether an object blocks a tile -- so
it is object-vs-object solidity, and both its sites pass the value that means
*solid*, which is the default nothing ever clears. `2FB` fades out and starts
overlay 100 as a child application: a whole screen the port lacks.

**The census caught its own table going stale.** Renaming the four subjects
made two `MERGES` entries name prose no row uses and left two subjects in
neither table -- all of it failing with names and counts. That is pass 181's
fail-closed list working on its first real test, one pass later, and it is the
half of that design that mattered. The new check is `gen4_field_effect_check`
and not `gen4_spear_pillar_check`, for the same reason the rows were renamed.

Suite PASS=67, REPORT=4, NOSPEC=41, no FAIL, SKIP, ERROR or PASS*. Registry
426 -> 428. Gen 2 and Gen 3 clean. Eleven plants, each md5-verified and each
landing on its own assertion. Two of my own slips are recorded in the check as
instances of known shapes: a handler placed above the local it calls (pass
180's `addDense` again), and a loop assertion written as `target < poll` when
the target is `== poll`, which failed on a correct port.

Still not complete: the effect is not drawn, so the sequence will play through
empty where overlay 6 would have rendered. What is fixed is that it plays
through at all, and that the objects in it turn.

Play-test items 86-90: the Spear Pillar sequence completing and setting flags
0x1C8/0x1C9 instead of locking up; objects turning at the fifteen 18C sites
(the player at seven of them); nothing visual for the effect itself, which is
expected; band 329's object 4 unchanged; and Gen 1/2/3 untouched.

## Pass 183 -- the door animation's real blocker was the join

`Gen4Doors.lua` opens by warning that the door sounds had been declined for a
reason that stopped being true -- then committed the same fault in its own next
paragraph: *"this port reads NSBMD without NSBCA and bakes a chunk's props into
a flat canvas"*. Both halves were already false.

**NSBCA is read** -- `Gen4Anim.jointMatrices` produces per-frame joint matrices
and the title sequence and starter models already wear them. **Props are not
baked** -- the land chunk is, but every prop is drawn as a live model each
frame, and `Gen4Model:draw(viewProjection, pose, ...)` takes a pose as its
second argument.

The real blocker: `/arc/bm_anime.narc` holds 98 animations and **no models**, so
the extractor's same-archive node-count pairing marked all 98 `unworn` --
correctly, by that rule. The pairing is in a third file that pokeplatinum's
map-format graph names: `area_build -> bm_anime_list -> bm_anime`, with
`bm_anime_list.narc` holding 590 records, one per prop model.

**The documented record layout is wrong by one.** The spec puts
`animeArchiveIDs` at 0x03; the records are 20 bytes with a zero at 0x03 and the
array at 0x04. Measured both ways: at 0x03, 264 ids fall outside the 98-member
archive; at 0x04, **zero** do, with 166 resolved across 112 props. The symptom
is self-consistent -- at 0x03 every id reads as `real << 8`, swallowing the pad
byte. The check re-runs both offsets and requires 0x04 to resolve strictly
more, so the correction is re-derived every run.

Also from the doc and tested: `hasAnimations` is **0xFF**, not 0, when a prop
has none, so the test is `== 1`; `~= 0` would call every unanimated prop
animated.

All twenty doors resolve: 11 ordinary hinged doors have four animations
(7, 8, 9, 10) and the other nine have two. **Count and sound type are
independent axes**, proved sharply: `mansion_door` and
`veilstone_dpt_store_door` play the *same* two animations (29, 30) and
*different* sounds -- hinged versus chime. Pass 178's sound table is correct;
this is an orthogonal fact, and a reader assuming "hinged means four" is wrong
about two of the thirteen.

The index rule is fully derived -- both of pokeplatinum's `== 2` / `== 4` arms
collapse to the same index, so **open is 0 and close is 1** for every door, and
a four-animation door loads all four while the door path plays only two.
Indices 2 and 3 are recorded as deliberately unreached.

**One of the twenty could move today:** `elevator_door` is BTP0, a texture
flipbook `Gen4TexAnim` already renders. The other nineteen are BCA0.

`tools/gen4_prop_anim_check.lua` (NEW, 228 checks) re-derives every row from
the cartridge. Eleven plants, each md5-verified and each landing on its own
assertion. Suite PASS=68, REPORT=4, NOSPEC=41, no FAIL/SKIP/ERROR/PASS*.
Registry unchanged at 428 -- no new script verbs.

Still not complete: nothing animates. What changed is that the animation for
any door and action is a derived lookup, and all three pieces a renderer pass
needs are present -- the pairing, the matrices, and a draw that takes a pose.
The missing step is the extractor pairing `bm_anime` to `build_model` ACROSS
archives using this table, and the prop draw asking for a pose.

Play-test items 91-93: the door sounds unchanged (pass 178's 65-70 still hold);
nothing animating by accident; Gen 1/2/3 doors untouched.

## Pass 184 -- the extractor pairs across archives

Pass 183 found the join; this puts it where the cache is built. The extractor
asked "is there a model in THIS archive with this many nodes?", and `bm_anime`
has no models, so all 98 of its animations were `unworn` -- right by the rule,
wrong about the cartridge.

`RomExtractorGen4:propAnimationClaims()` now builds
`{ [bm_anime member] = { prop model ids } }` from `bm_anime_list.narc`, and an
archive declaring `claims = true` takes that route instead of counting nodes.
The claiming props are recorded on the animation as `record.props` -- the join a
renderer needs, which a node count could never give because it does not say
WHICH prop.

Measured: 112 props carry animations; **98 of 98** members claimed, nothing
orphaned; the archive is 32 BCA0 / 43 BTA0 / 23 BTP0; **all 32 joint animations
now worn**, none unworn; 90 joints, 13,093 joint-frames, longest 600; 613.7 KB
packed with every track passing `verifyTrack`. Every door animation is claimed.

**The old comment's 2.2 MB was right.** 613.7 KB of packed bytes becomes about
that as escaped Lua literals. Two corrections replace it: the claim test buys
**no** size saving here (all 98 are claimed, so it changes `unworn` from
98-of-98 to none -- my first draft claimed the opposite and the measurement
corrected it), and what changed is the *reason* rather than the trade -- the old
decision was right while nothing could apply a pose, and the doors alone are 48
script sites now.

**Two check faults the plants found**, both shapes already in the lessons doc:
section 7 first built the claim map itself, so a plant emptying the extractor's
loop left 275 checks green (shape 6a -- it graded a mirror); and the source
assertion `find("propAnimationClaims%s*%(")` matched the method DEFINITION, so
deleting the only call passed (shape 3b -- a name is not a call). The check now
constructs a real extractor and calls the method, and anchors on the `self:`
form.

`tools/gen4_prop_anim_check.lua` 228 -> 277 checks. Suite PASS=68, REPORT=4,
NOSPEC=41, no FAIL/SKIP/ERROR/PASS*. Registry unchanged at 428. Gen 2 and Gen 3
clean, and both cache checks clean -- which matters because this changes what
the cache will contain.

Still not complete: **the cache has not been regenerated**, so nothing has
changed on disk for the game. The check proves the pairing against the
cartridge rather than a rebuilt cache, which is why it needs no 10 MB rebuild.
Remaining: a re-import to get the tracks into `gen4_models.lua`, then
`Gen4Ground` asking for a pose when a prop has a running one-shot -- the only
step still needing design.

Play-test items 94-96: a re-import still producing a loadable cache (watch the
cache-integrity and cache-wiring checks); the cache growing ~2.2 MB, which is
expected; and nothing else starting to wear a pose, since the node-count route
is unchanged everywhere else.

## Pass 185 -- the one-shot runner, and a wait that was unreachable

Two faults, the second hiding the first. `Commands.g4_wait_animation` was
`noop`, and there were **two** `L.waitforanimation` lowerings -- an early one
onto `g4_wait_animation` and a later one onto `g4_noop` that, being later in
the same table, silently overwrote it. The handler was unreachable, and the
census filed all **48 sites** under "the door animation's wait". Two spellings
of one command in one table, both copies in the same file.

The surviving lowering also discarded the operand: `waitforanimation` is `"b"`,
the **tag**, which `ScrCmd_WaitForAnimation` reads and waits on.

`src/world/Gen4PropOneShot.lua` (NEW) is tag-keyed like the cartridge's
manager. The prop is carried by **identity** -- `modelAt` now returns the
object it found as a third value, and the renderer iterates that same table, so
no coordinate is compared twice. Durations are derived from `bm_anime.narc`:
6-15 frames, with open and close always equal and a four-animation door's
unplayed pair a different, shorter animation.

**A tag that is not running is finished** -- the one thing a real wait could get
catastrophically wrong. A door the port cannot identify is never started, so
the wait steps over rather than freezing. The old no-op did that by accident;
this does it on purpose. And a finished one-shot **holds its last frame**:
clearing it would snap the door shut the instant it opened, and
`unloadanimation` is what releases the slot.

The renderer's pose slot was always there -- `Gen4Model:draw(vp, pose, ...)` --
and every prop draw passed nil. `Gen4Ground:oneShotPose` fills it and the two
LIVE draws ask for one. **The first draft was cold by construction**: it read
`self.overworld`, a field `Gen4Ground` does not have and should not grow, so it
would have answered nil for ever with nothing to say so. The overworld hands
the table over each frame instead, and the check asserts both halves plus that
`self.overworld` appears nowhere in that file.

**What this pass deliberately does not do:** door props are still baked, so
nothing moves. `animationsFor` answers for texture animation only, so an NSBCA
door stays baked however correct the pose is. Moving the twenty door props onto
a live path spans the bake guard, `bakeAnimated`'s selection and the 2D passes,
cannot be checked without looking at the screen, and risks a visible regression
across the overworld -- so it is its own pass, with a note in the bake guard.
Everything here is inert until a re-import: no tracks means a nil pose, which
is the rest pose. No visual change and no visual risk.

`tools/gen4_prop_anim_check.lua` 277 -> 387 checks. Fifteen plants, and **five
found faults in the check rather than the code**: two clamp faults landed
silently because the clamp is only reachable by overshooting in ONE step; bare
`running(...).frame` indexing RAISED instead of failing and killed the run; and
the nil-length guards were cold, so the check now breaks a live slot on purpose
and calls `finished` through pcall. Two were fixed in the subject -- `finished`
and `advance` treat a lengthless slot as finished rather than comparing with
nil, which is the same contract, not a hedge.

Suite PASS=68, REPORT=4, NOSPEC=41, no FAIL/SKIP/ERROR/PASS*. Registry
unchanged at 428 -- the verb existed; what changed is that it is reachable.
Gen 2 and Gen 3 clean.

Play-test items 97-100: `waitforanimation` not freezing anything (48 sites, and
the risk runs the other way now); doors still not moving, with pass 178's
sounds unchanged; the overworld rendering identically, since the pose is nil
until a re-import and any visual change is therefore a fault; and Gen 1/2/3
untouched behind `GameVersion.isGen4()`.

## Pass 186 -- two namespaces for one door

Taken while de-risking the bake split, and the reason that split must not be
done by name.

**pokeplatinum's `doorModelIDs[]` names the FILE; the cache names the MODEL
INSIDE the file; they disagree for nineteen of the twenty doors.**
`brown_wooden_door` is `t1_door1`, `pokecenter_door` is `p_door`,
`elevator_door` is `ele_door1`, `veilstone_dpt_store_door` is `c5_door_s`.
`Gen4Archives.find` resolves file names and `Gen4Ground.animsByName` keys on
internal names -- both correct, different namespaces, and nothing had joined
them because nothing had needed to. The recurring bug in its purest form.

**`door01` agreeing is the dangerous part**: a reader who spot-checked one door
would have concluded the namespaces were the same. The check asserts the COUNT
-- exactly one agrees -- rather than that they differ. And `gym_door` ->
`gym_door00` with `hearthome_gym_inside_door` -> `gym_door01`, close enough to
look like a typo of each other, where a swap picks the wrong door with no
symptom; pinned separately.

Pass 185's `oneShotPose` is right by construction because it keys on the
`bm_anime` member. The bake split decides per prop whether it is baked, and by
name it would have been wrong for nineteen of twenty while looking right for the
one anybody checked.

**The two prop selections were asking different questions.** The static bake
guard passed `object.archive`; the animated bake's selection did not -- so for a
`fldeff` prop they consulted different models, and the prop could land in both
passes and be drawn twice. Measured: zero fldeff props are placed in terrain
chunks, so there was nothing for it to catch. Fixed, and the check now requires
all four `animationsFor` calls to pass both arguments: two selections that must
be complements cannot read different tables.

Also asserted: **position is member** for the buildings set -- every
`models[index + 1]` lookup and the static bake depend on it, so every
`byMember` entry is verified to be `member + 1` rather than trusted.

`tools/gen4_prop_anim_check.lua` 387 -> 403 checks. Seven plants, each
md5-verified and each landing on its own assertion. The fldeff count is
reported rather than asserted at zero, since a future pass placing signposts as
terrain props should move it.

Suite PASS=68, REPORT=4, NOSPEC=41, no FAIL/SKIP/ERROR/PASS*. Registry 428.
Gen 2 and Gen 3 clean, and `gen4_mapprops_check` (5,224 checks) clean -- the one
that would notice a prop selection going wrong.

Still not complete: the bake split itself. What this pass removed is the trap
inside it -- key on member, not name, and make both selections ask the same
question. Both are now asserted.

Play-test items 101-103: every prop drawn exactly once (twice shows as a
brighter or double-shadowed object, zero times simply vanishes); signposts and
mailboxes unchanged, since they are the fldeff props the archive argument was
about; Gen 1/2/3 untouched.

## Pass 187 -- the bake split, against the regenerated cache

The re-import landed and confirmed every pass-184 prediction on the real file:
`gen4_models.lua` 10.0 -> **12.3 MB** (predicted ~+2.2), `tracks` 20 -> **52**
(+32 BCA0), `unworn` 32 -> **0**, `props` 0 -> **32**.

The tracks are real: **60 of the doors' 62 animation ids carry usable joint
tracks**, and the two that do not are `elevator_door`'s BTP0 pair, as pass 183
said. Animation 7's `props` lists eleven prop models -- the eleven ordinary
hinged doors -- so the claim table round trips. Its first joint track is the
**identity matrix at frame 0** and a **90-degree Y rotation at frame 7**: a door
swinging open a quarter turn.

`oneShotProps()` derives the one-shot-capable set from the cache **by index**
(the namespaces disagree for nineteen of twenty doors): 39 prop models, 218
placements -- the doors plus nineteen other animated props, so the PC, the
honey trees and the lift platform come along. The two decisions are named
methods now, `shouldBake` defined as `not shouldAnimate`, because two separate
tests is how complements drift.

**Measured cost:** 72 more chunks of 666 (10.8%) rebuild a moving canvas each
frame, on top of 119 (17.9%). Conditional membership would cost nothing at rest
but needs the static canvas invalidated on start AND unload, and a door holds
its open pose until the unload -- so the saving is smaller than it looks. Taken
the simple way with the number recorded.

**Three plants did not fail, and each was a known shape.** The complement test
was *modelling* the selections, so reverting the static guard -- drawing every
door twice -- left 427 checks green (6a); fixed by making the subject expose
`shouldBake`/`shouldAnimate` and asking them. Pass 186's assertion pinned a
call count my own change moved, failing on a correct tree (shape 2); it now
asserts that no per-object call omits the archive. And dropping the `tracks`
requirement changed nothing -- **because `props` was written only inside the
loop over `pending`, which holds BCA0 alone**, so the 43 BTA0 and 23 BTP0
claims were never recorded, `elevator_door` among them. Now recorded on every
animation; that one needs another re-import to appear in the cache, and the
check asserts it at the source so it cannot be lost meanwhile.

**And one measurement that cannot fail, said so.** With `shouldBake` as the
negation, "in both" and "in neither" are true by construction -- a plant making
`shouldAnimate` always false left both green. Kept as cheap cover, with the
comment pointing at the source assertion that actually protects the complement.

`tools/gen4_prop_anim_check.lua` 403 -> 430 checks, including the complement
over all **3,476 placed props** (2,968 baked, 508 animated) and the assertion
that animation 7's frame 0 is the identity while its last frame differs --
which is what proves a posed door visibly moves. Eleven plants, each
md5-verified and each landing on its own assertion once the three above were
repaired.

Suite PASS=68, REPORT=4, NOSPEC=41, no FAIL/SKIP/ERROR/PASS*. Registry 428.
Gen 2 and Gen 3 clean, and the two cache checks plus `gen4_mapprops_check`
(5,224) clean **against the regenerated cache** -- which is what items 94-96
asked for.

Still not complete: doors should now animate, but I cannot see the screen, so
that is a play-test claim rather than a result.

Play-test items 104-106: open a door and watch it swing a quarter turn over
eight frames and hold open (`elevator_door` animates by texture and may not
move yet); watch for a stutter entering a town, since 72 more chunks rebuild a
canvas each frame and conditional membership is the fix if it shows; and
`waitforanimation` still not freezing, now that one-shots really run.

## Pass 188 -- how a door actually moves, measured

Pass 187 proved a door can be posed; this asked whether it will look like the
cartridge, and got three corrections.

**Sliding doors do not swing, they squash.** Hinged doors (anim 7/8, 9/10,
27/28, 29/30, 33/34) rotate 90 degrees about Y. The Poke Centre family (5/6)
applies an X **scale** from 1.00 to **0.20** with no rotation at all -- six of
the twenty doors. Read from the joint matrices, not assumed.

**Open and close are exact mirrors**: open's last frame is close's first and
open's first is close's last, for all six pairs. So close is its own animation
running forwards, not the open one reversed -- the cartridge's data confirming
pret's index rule rather than only its source.

**The last frame is held, and the cartridge does it the same way.**
`AdvanceAnimations` sets `looping = FALSE` on the last frame and then
`continue`s for ever, and `IsAnimationLoopFinished` is literally
`looping == FALSE`. That is what pass 185's clamp reproduces; now cited rather
than reasoned.

**The Veilstone door's panels really do shift, and that is the ROM.**
Animation 29 is claimed by `d3_door1` (mansion, panels at +/-10) AND
`c5_door_s` (Veilstone, panels at **+/-12**), and its frame 0 carries -10/+10
as real constant translation channels -- the translation-absent flag is not
set. The hardware writes them, so opening the Veilstone door moves its panels
two units inward, and preserving the model's own translation would be the
DIVERGENCE. Pinned as an enumerated exception that fails if it stops being
true. Everything else rests where the static bake draws it: **29 of 30
pairings** match their model's node matrices at frame 0.

**Four more plants did not fail.** The pose arithmetic was never *executed* --
`oneShotPose` needs LOVE, so only its source was read, and writing every track
to joint 0 (half-moving the mansion door) or dropping the frame clamp changed
nothing. It is `jointMatricesAt(slot)` now, graphics-free, and section 15 runs
it. The clamp is not tidiness: `advance` holds a finished one-shot at
`frame == frames` and a track's last readable index is `frames - 1`, so an
unclamped read runs past the end of every door standing open. Section 13's
spot check of `tracks[1]` said nothing about the four three-joint animations
whose motion is in joint 2. My own "rest pose is the identity" assertion was
wrong and failed on a correct tree -- the identity is only right for
single-joint doors. And the motion-kind list counted a duplicate twice, so
"twelve distinct animations" passed over eleven.

`tools/gen4_prop_anim_check.lua` 430 -> 531 checks. Suite PASS=68, REPORT=4,
NOSPEC=41, no FAIL/SKIP/ERROR/PASS*. Registry 428. Gen 2 and Gen 3 clean.

Still not complete: pass 187's props-on-every-animation fix needs a second
re-import before `elevator_door` can move through the texture path.

Play-test items 107-110: a Poke Centre door squashing rather than swinging; the
mansion door moving all three panels; the Veilstone panels shifting about two
units inward, which is the cartridge and not a bug; and a door held open
staying open without flicker.

## Pass 189 -- the persisted map features: one slot, and the var that was not a boolean

The census's biggest remaining subject -- 53 sites over twelve stub rows,
ranked as "nine separate implementations". Both halves of that were wrong.

**It is one slot.** The cartridge keeps `{ int id; u8 buffer[32]; }` in the
misc save block, one feature at a time, and `PersistedMapFeatures_GetBuffer`
GF_ASSERTs that the id you ask for is the id that is there. The nine
`initpersistedmapfeaturesfor*` rows are nine CONSTRUCTORS over one union. The
union is exactly big enough: `DistWorldPersistedData` is 4 + 8 + 4 + 16 = 32
bytes, which is `PERSISTED_MAP_FEATURES_BUFFER_SIZE` -- the largest tenant
fills it to the byte.

**And the census under-counted by a third, because of how the census works.**
The family is 82 sites over nineteen commands, and 24 of them -- six commands
-- had NO LOWERING AT ALL: `setplayerheightcalculationenabled` 12,
`checkgreatmarshtramlocation` 6, `movegreatmarshtram` 2,
`movehearthomegymdplift` 2, `initgreatmarshtram` 1,
`initpersistedmapfeaturesforvilla` 1. The census reads its subject out of the
PROSE in `g4_noop` rows, so a command with no lowering names no subject and
cannot enter the ranking: the tool built to stop a subject hiding has a blind
spot shaped exactly like the worst case, since an unlowered command is
strictly worse than a declared one. It now has a section 5 that counts both --
301 unlowered commands over 1,002 sites, the Battle Tower's 121 at the top --
and is fail-closed on this family against `Gen4ScriptOps.COMMANDS`.

**One of the six was a lie.** All six `checkgreatmarshtramlocation` sites read
`check... , 0x8004 / setvarfromvalue 0x8005, N / comparevartovalue 0x8004, 6 /
callif 1, -> movegreatmarshtram`. GREAT_MARSH_TRAM_AT_LOCATION is **5** and
NOT_AT_LOCATION is **6** -- not 1 and 0 -- and the script compares against the
literal 6. Unlowered, the var holds whatever the last script left; a port that
wrote a boolean would be wrong at all six sites in the same direction and the
tram would never be summoned. All twelve `setplayerheightcalculationenabled`
sites turn out to be in the SAME script member (497) as those six, which turned
the family's largest unlowered command into its smallest subject.

**Pastoria's gates pair with the water inverted** -- HIGH ground opens at LOW
water and LOW ground at HIGH -- and the check states that as the invariant so a
reader who "fixes" it fails. The other initial values a cleared buffer would get
wrong: Pastoria starts at GREEN (1), not the enum's zero ORANGE; Canalave's
bitfield is 0x00AD0DC0, ten of 24 platforms in position B; Sunyshore's rotation
is per-room (2, 1, 0) AND forced to 0 when the player's z equals that room's
entrance z; the Great Marsh is the ONE constructor of eleven that checks the id
first, because all six marsh maps run its init script and an unconditional
stamp would send the tram home every time you changed area. `MoveToLocation` is
three arms with else-branches, not "go to the destination": from 1-2 to 1-2 the
tram goes to 5-6.

**The Eterna clock is an honest no, established not assumed.** It writes a var,
and a var is the one kind of state a script can branch on -- so all 1,124
members of scr_seq were scanned for VAR_ETERNA_GYM_FLOWER_CLOCK_STATE (0x404B)
and NONE mentions it. Engine-private; the floor stays open and no branch takes
a wrong arm.

**The three dispatch tables are three different sets** -- 10/7/7 -- and the
exceptions are not the same features: Pastoria has collision and no free,
HEARTHOME has free and NO collision. Which is the same fact as
`movehearthomegymdplift` being dead code: its task functions are
`HearthomeGymDP_RaiseLift`/`LowerLift`, and Platinum rebuilt that gym as
Fantina's quiz doors.

**Why there is no collision resolver, measured three ways.** The recorded 0x59
census was wrong twice: Canalave 293 (right), Pastoria **445** (recorded 356),
Sunyshore **411** (recorded 293 -- Canalave's number copied), total **1,149**
(recorded 942). The behaviour is still in those six chunks and nowhere else.
Then: searching over (cell, water level) from Pastoria's entrance warp, with
0x59 walkable 708 of 1,325 cells and all ten buttons are reachable with the
gates enforced or ignored alike; with 0x59 BLOCKED it is **57 cells and ZERO
buttons** -- no button means no way to change the level, so the plain reading of
the behaviour's name ships an unfinishable gym. (The first draft used a plain
flood and got 219, which looked survivable: the flood was ignoring the gates. A
flood cannot answer "is this finishable".) And the gates alone change nothing --
708 either way, a 22-cell detour -- because the puzzle is the height
arithmetic: the cartridge compares the tile's level against the PLAYER'S y, and
Pastoria's BDHC answers 0/8/24/32/40/56/64 while the water sits at 0, 32 and
64. The gym is a three-storey building and the water is the floor that moves
between its storeys. Giving the player a height is an engine change, not a gym
feature. The resolvers are declared, the registry asserted empty, and
`checkCollision` keeps the cartridge's three-way contract (not handled /
blocked / OPEN) because collapsing it to a boolean would lose Canalave, whose
resolver returns TRUE unconditionally.

**Four check faults.** A lookup that matched nothing and reported agreement
(`Ops.OPS or Ops.ops or Ops` fell through to the module table, so deleting a
name from the family list stayed green). The handlers live in the shared
`src.script.Commands` registry, not on the Gen4Commands module -- looking them
up on the wrong table failed on a correct tree. A check that cannot find its
subject SKIPS, which looks like a pass: the Canalave array is in
`persisted_map_features_init.c`, not `gym_features.c`. And the flood-versus-
search above.

`tools/gen4_dynamic_map_features_check.lua`: **181 checks**, ten sections, ten
planted faults each landing on its own assertion's message.
`gen4_declined_census_check` 15 -> 30 checks. Suite PASS=69, REPORT=4,
NOSPEC=41, no FAIL/SKIP/ERROR/PASS*. Registry 433. Gen 2 and Gen 3 clean.

Play-test items 111-115: the Great Marsh tram coming when called (the one
visible behaviour change -- six sites were branching on a stale var); the tram
remembering where it is across areas; the three gyms still crossable and no
HARDER, since a cell that has started blocking means the deliberately-omitted
resolver was half-written; Eterna's floor still open; and the nine init rows no
longer reporting an absence in the log.

## Pass 190 -- the prop animation join: the port's was by name, the cartridge's is by claim

**Correction first, because this section's first version got the re-import
wrong.** It said the models stage re-ran eight minutes before the fix landed and
nothing else was re-extracted. Both halves were false: every measurement behind
them came from the container's read mount of Cedric's machine, and **that mount
is a point-in-time snapshot, not a live view**. It showed `gen4_models.lua` at
01:10 where the live file is **02:39**, the rest of the cache at 24-29 September
where it is **02:38-02:40**, and 401 files in `platinum/assets/generated` where
the real tree is many times that. Cedric had re-imported **fully** while the
pass was being written; the partial asset tree was the snapshot, and the five
asset checks that "failed" against it are shape 1 of
`claude/check_design_lessons.md` through a new door -- now 1a there: **a
snapshot of the subject is not the subject.**

**What the live cache says, measured structurally** (loading the table, not
reading the file): 98 field animations, **98 carrying `props`** -- 32 BCA0,
43 BTA0, 23 BTP0 -- `tracks` **52** across all six sets (field 32, fldeff 13,
starter 4, title 3), `unworn` 0, `patternImages` **16**.
`src/import/RomExtractorGen4.lua` on the device is 03:11, this pass's own
commit, so the 02:39 import ran with the 187/189 tree: the `props` fix present,
this pass's claim matching not. **Pass 187's prediction is confirmed exactly,
and `tracks` is identical to pass 184's 52 -- nothing regressed.**

**The 95 and the 47 were a grep.** `grep -o 'props = '` answers 95 of 98 and
`'tracks = '` answers 47 where the previous import gave 52 -- plausible numbers,
and the second is the alarming shape, a drop after a re-import. The cache writer
has a chunk-boundary spelling for a value too large to sit inside the chunk it
is being written into: `__t["props"] = {` three times and
`__t["tracks"] = (function` five times. 95+3=98, 47+5=52. **A generated cache is
a table, so load it; do not count its text** -- both checks here read it
structurally, which is why they said 98 while the greps said 95. Recorded as
3c-ii in the lessons file.

**And the stale-cache failures are gone.** Against the snapshot,
`gen4_cache_integrity_check` reported five moves keeping a number although a
handler row exists and 59 unimplemented effects against a pinned 54, and
`gen4_constants_wiring_check` eight missing constants keys. The advice -- a full
re-import -- was right and has happened: against the live cache both are clean
(128/0 and 14/0), with `gen4_cache_wiring_check` 30/0 and
`gen4_mapprops_check` 5,224/0.

**The elevator door could not have moved, and the reasons were three.**
`Gen4PropAnim.lua` has said since pass 183 that its BTP0 pair made it "the one
of the twenty that could move today". `oneShotProps` gated capability on
`record.tracks`, which no BTP0 record has, so `ele_door1` went to the STATIC
bake where the draw never asks for a pose at all; `animationsFor` joined by
name, and the animations are `ele_door1_op` / `ele_door1_cl` while the model is
`ele_door1`; and the extractor decoded a BTP0's alternate frames only for a
model whose name an animation shared, so the four `ele_door.*` pictures were
never written. Eighth instance of the stale-claim pattern, and the first where
the claim is a **prediction** rather than a blocker -- which is why it survived
seven passes, and is now 8a in the lessons file.

**And the join is wrong for 44 props, not one.** 112 prop models are claimed by
a `bm_anime` animation, **68** share a name with theirs, **44** do not -- 22
joint (already reached, because `oneShotProps` keys on the claim) and **22
texture** over **124 placements** -- and **zero** are name-reachable and not
claim-reachable, which is the control that makes a union the whole fix. Among
the 22: all six `wfall*` models, every one claimed by animation 18 (`wfall`, 61
frames) and not one named `wfall`, so **Platinum's waterfalls were static**;
`cy_slope`/`cy_slope_dun` (20/21); `ev_o01` (35/36); `l_lake_l4` (19);
`c5_o03`/`r212s02` (`funsui`, 0); the four `stair_pc_*` escalators (15/16);
`table_l01/l02/l03` and `pc01` (41/42); `machine_pc03` (32); `ele_door1`
(51/52).

**A fourth thing had to be true and was not obvious: a flipbook door must not be
driven by the frame clock**, or widening the join alone would have opened and
shut `ele_door1` for ever by itself. The clock-driven set excludes the
script-owned ids, derived from `Gen4PropAnim.DOORS` (fourteen ids over the
twenty doors) rather than listed, and narrow on purpose -- the monitors and the
escalators are flipbooks that genuinely loop.

What landed: `animsByProp` as a third index; `Gen4Ground.oneShotAnimations()`;
`animationsFor` as the deduplicated union of both joins minus the script-owned
ids; a second arm on `oneShotProps` for a texture-pattern one-shot, restricted
to those members and requiring the model to carry the animation's pictures;
`texturePatternAt(slot, index)`, the flipbook half of `oneShotPose`, split out
of the draw so a check can execute it; and `propMaterials(object, frame)` as
the one question all three draw sites ask -- pass 186 had already caught two of
the three spelling it differently. On the import side the flipbook frame
extraction now matches on the claim as well as the name, measured before it was
widened: all ten claim-only BTP0 models carry every one of their animation's
texture names in their **own** TEX0 (15 pairs, 0 misses).

**The clamp is the one that would be visible.** `advance` holds a finished
one-shot at `frame == frames` and `materials` takes `frame % period`, so an
unclamped read of frame 8 of 8 wraps to key zero and snaps the door shut the
instant it finishes opening.

**What moves on Cedric's cache today**, measured by driving
`Gen4Ground:movesAtRuntime` over all 590 build models against the live cache and
terrain: **90 -> 102** models, and 112 after one more import. **The twelve BTA0
models move now** -- the six waterfalls, `cy_slope`, `cy_slope_dun`, `ev_o01`,
`l_lake_l4`, `c5_o03`, `r212s02`, **36 placements**, 14 chunks newly rebuilding
a canvas each frame and 9 that already did -- because a texture scroll needs
only `record.srt` and `props`, both of which the 02:39 cache has. **The ten
BTP0 models still cannot**, all ten for one reason: `patternImages` is 16, so
none carries its flipbook frames, and the extractor change that writes them was
committed after the import. **One more re-import takes `patternImages` 16 -> 26,
the run-time count 102 -> 112, and brings in the remaining 88 placements.**

`tools/gen4_prop_claim_check.lua`: **103 checks**, nine sections, everything
outside the two cartridge sections running with no ROM and no cache. Section 9
accepts a cache in either of its two legitimate states -- all 98 claims or
exactly the 32 BCA0 ones -- names which, and fails on anything between; it is
green against the live cache and against the reference one. Thirteen plants,
each md5-verified. **One landed and nothing failed**, a finding about the check:
dropping `or claimed` from the extractor's guard leaves the `record.props` loop
in place as dead code, so all three source assertions still matched -- shape 6c
inside the check, fixed by asserting the condition's own text. A second was
re-aimed: the door-exclusion assertion pointed at a model with no pictures,
which `animates` refuses whatever the exclusion does.

`tools/gen4_prop_anim_check.lua` **531 -> 532**, and a pin the re-import
tripped: section 12 read `claimed == 32` and reported *"98 … not 32"* against
the live cache -- shape 2d, an assertion demanding the work not be done.
Re-pinned as the relation each state rests on (`claimed == total` or
`claimed == tracked`) with a floor and a report line, green on both caches; its
plant is a **real** cache with `props` deleted from 48 of 98 records, because a
synthetic one tripped four earlier assertions and never reached section 12.

Two stale duplicates found and **not** deleted: `src/world/NPC-1.lua` is a
byte-identical copy of `NPC.lua` (988 lines) and `src/script/Gen4Commands-1.lua`
a 2,944-line copy of the 5,283-line `Gen4Commands.lua`. Nothing requires
either, and `tools/gen4_machine_check.lua` already carries two explicit
exclusions for the second.

Suite **PASS=70**, REPORT=4, NOSPEC=41, no FAIL/SKIP/ERROR/PASS* against the
reference cache; **PASS=71** combined with the parallel update pass. Registry
433. Gen 1/2/3 untouched: the three changed engine files are Gen 4-only,
`Gen4Ground`'s only construction site answers nil for a cache with no Gen 4
terrain stage, and the Gen 2 and Gen 3 checks are green.

Play-test items 116-121: **waterfalls moving on the cache he already has** (no
further import needed -- this is the one a player sees first); the Canalave
slopes, `ev_o01`, the two fountains and `l_lake_l4` also live today; **the
elevator door, the escalators and the PC monitors needing one more re-import**,
`patternImages` 16 -> 26, after which the door opens over eight frames and
STAYS open (a snap shut is the frame clamp, a door cycling with no script near
it is the clock exclusion); nothing animating that is not on those lists, since
the union only ever adds; no prop drawn twice, since twelve models have just
changed pass; and a stutter check on a waterfall route or in Canalave, for the
14 extra chunks today and 41 after the flipbooks land.
