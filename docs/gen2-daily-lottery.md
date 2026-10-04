# Gen 2 daily events and Lucky Number Show

Gold, Silver and Crystal now clear the full set of engine flags covered by
their cartridge's daily WRAM resets. This includes contest participation,
haircuts, grooming and the other daily services. Crystal additionally clears
its daily phone, rematch and swarm flags. Story flags, badges and the weekly
lottery prize flag are retained.

The Lucky Number Show uses a separate deadline for the next in-game Friday.
It respects `g2DayOffset`, the weekday selected at Mom's clock, and uses
calendar arithmetic across daylight-saving changes. Talking to the clerk
after claiming a prize cannot reroll the number or duplicate the prize.
The reset special starts a new weekly draw; the check special tests that
deadline rather than the prize flag. Printing the ID writes string buffer 3
without opening an additional textbox.

Winner selection scans the party, current PC box and remaining boxes in ROM
order. Eggs are excluded, and trailing-digit prize tiers are unchanged.
The box-free-space script variable now reports actual current-box capacity.

Crystal's extracted engine flag table previously stopped at 128 of 162
entries. Extraction now reaches the complete table and validates every row's
WRAM address and bit mask. Gold and Silver retain their 93-entry tables.
The import revision for these three games changes so rebuilt applications
regenerate stale extracted data. Reimporting the ROMs also refreshes it.

## Verification

Run `python tools/run_lua_check.py tools/gen2_daily_lottery_check.lua`.
The harness uses the original ROMs and manifests in the workspace and caches
under `G:/Gen2Recomped` (an alternate cache root can be passed as an argument).
All 492 checks pass:

- Daily reset membership is checked against every extracted engine flag and
  the WRAM reset ranges from each ROM's manifest.
- Same-day polling, next-day contest availability and preservation of story
  and weekly prize flags are checked.
- Thursday, Friday, Saturday, next-Friday, selected weekdays and serialized
  deadline persistence are checked.
- The actual extracted Radio Tower clerk scripts execute through the runtime
  VM and script runner for PC winners, repeat visits, a full bag, retrying and
  the following week's prize.
- Prize tiers, egg exclusion, string buffer writes and active-box free space
  are checked directly.

The existing extracted contest flow also passes all 1,233 checks. Daily,
lottery and contest tests do not establish visual or audio parity: text UI,
NPC movement and item delivery are acknowledged by the headless clerk
harness. Original-save lottery countdown import is not added here; old
launcher saves without a deadline keep their number and prize state until
the next Friday measured from their first check. ROM-specific hacks retain
their existing daily behavior rather than receiving vanilla raw flag ranges.

## Cartridge references

- [Gold daily and weekly timers](https://github.com/pret/pokegold/blob/master/engine/overworld/time.asm)
- [Crystal daily and weekly timers](https://github.com/pret/pokecrystal/blob/master/engine/overworld/time.asm)
- [Crystal engine flags](https://github.com/pret/pokecrystal/blob/master/data/events/engine_flags.asm)
- [Lucky-number winner selection](https://github.com/pret/pokecrystal/blob/master/engine/events/lucky_number.asm)
- [Gold clerk script](https://github.com/pret/pokegold/blob/master/maps/RadioTower1F.asm)
- [Gold script variables](https://github.com/pret/pokegold/blob/master/engine/overworld/variables.asm)
