# Gold, Silver and Crystal Bug-Catching Contest

The contest's `CheckPartyFullAfterContest` handler in Gen2Commands was
overwritten when Gen2Specials loaded. The replacement skipped contest cleanup
and party restoration, and returned its numeric result to ScriptRunner. The
runner interprets numbers as row jumps: zero caused an invalid-row error, and
one or two restarted earlier script rows. That prevented the results script
from reliably reaching its gate scene reset and daily entry flag.

Gen2Commands now owns this special. Gen2Specials answers through the script
variable without returning a row number, including its other result specials.
Timer/out-of-balls notices reserve their shared exit before opening the text
box, and a completed contest cannot queue another results script.

Additional cartridge behavior corrected:

- Ten possible AI entrants are extracted (IDs 2–11), rather than nine.
- Only the five selected entrants participate in judging. Each score includes
  the ROM's random 0–7 adjustment. A later AI wins a tied score, and the player
  wins ties against AI because the cartridge inserts the player last.
- The held party returns before the catch is transferred. The current box is
  used when the party is full; other boxes are not silently selected. The full
  current box follows the cartridge's BOXED_MON result even when no room exists.
- A stored catch receives the post-contest nickname prompt and naming screen.
- Prize, contestant-event, daily-entry and gate-scene changes run through each
  version's extracted bytecode, rather than substituting Crystal's IDs for Gold
  or Silver's IDs.

`tools/gen2_contest_rom_flow_check.lua` executes the real VM, script runner,
contest commands and exit methods against all three extracted ROM caches.
It also extracts each version's contest tables directly from its ROM. The
1,233 checks cover all four prize branches, no catch, one/six-member parties,
party/box nickname choices, repeated gate visits, concurrent ending notices,
current-box overflow, selected opponents, score jitter and tie ordering.
UI choices, movement and warp completion are acknowledged by the harness;
rendering, sound, physical-device input and full visual parity are not proven
by this headless test.

## Contest UI verification

The START status window now accounts for Textbox's interior dimensions: 17x5
becomes 19x7 including borders. The right menu begins at (10,2) and draws over
the status window's empty right side, leaving its name, level and ball rows
readable. Contest entries follow the cartridge order, with QUIT replacing SAVE,
no PACK or launcher LINK row, and a separate EXIT that closes the menu without
retiring. Mod-provided entries still pass through the existing menu hook.

The battle row now uses the native multiplication glyph and zero-padded Park
Ball count (07, rather than a blank followed by 7). Catch replacement opens the
full-screen STOCK/THIS panels at (0,0) and (0,6), including species, level and
max-HP HEALTH values. YES/NO is at (14,7); NO and B retain the old catch without
an extra invented release message. The retained catch gets `Caught <name>!`.
Stock names come from the species record, as GetPokemonName does in the ROM.

`tools/gen2_contest_ui_check.lua` exercises production UI and battle queue code
for all three games: 303 checks cover layout, all 0–20 ball counts, YES/NO/B,
the 15-frame answer hold, retained mon identity, battle completion, EXIT and
both retirement answers. The extracted contest-flow check still verifies the
prize branches, transfers, nickname prompts, daily flags and loop guards.

`tools/gen2_contest_ui_harness` runs in LOVE and renders the production widgets
with each version's extracted font atlas. Run from the repository root:

```powershell
$env:CONTEST_REPO=(Get-Location).Path
& 'C:/Program Files/LOVE/lovec.exe' tools/gen2_contest_ui_harness
```

The harness expects the local caches at `G:/Gen2Recomped/<version>`. Its PNG
contact sheet contains Gold, Silver and Crystal rows; columns show empty catch,
stored catch, battle menu, comparison, judging and time-up text. All 18 renders
were visually inspected. The plain background is a harness backdrop, not the
park or gate renderer. This verifies these widgets' rendering and placement;
it is not an emulator framebuffer comparison or a physical-device playthrough.

Additional UI references:

- [Gold/Silver comparison](https://github.com/pret/pokegold/blob/master/engine/events/bug_contest/display_stats.asm)
- [Crystal comparison](https://github.com/pret/pokecrystal/blob/master/engine/events/bug_contest/display_stats.asm)
- [Crystal status panel](https://github.com/pret/pokecrystal/blob/master/engine/menus/menu_2.asm)
- [Crystal battle menu](https://github.com/pret/pokecrystal/blob/master/engine/battle/menu.asm)
- [Crystal START menu](https://github.com/pret/pokecrystal/blob/master/engine/menus/start_menu.asm)

The import marker changes only for Gold, Silver and Crystal, so rebuilding
their caches picks up the tenth AI entrant. Runtime loop fixes do not depend
on reimporting the ROM.

Cartridge references:

- [Gold/Silver judging](https://github.com/pret/pokegold/blob/master/engine/events/bug_contest/judging.asm)
- [Crystal judging](https://github.com/pret/pokecrystal/blob/master/engine/events/bug_contest/judging.asm)
- [Crystal contest catch transfer](https://github.com/pret/pokecrystal/blob/master/engine/pokemon/caught_data.asm)
