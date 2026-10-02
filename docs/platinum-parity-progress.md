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
