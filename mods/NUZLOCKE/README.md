# Nuzlocke & Soul Link

Adds the Nuzlocke and Soul Link rules to every Pokémon game the engine runs.
Players: Nuzlocke challengers, solo or with a friend.

1. Start a NEW GAME, set **NUZLOCKE** (or **SOUL LINK**) to ON on the RUN MODES screen, then START.
2. Play. Only the first wild POKéMON in each area can be caught. A POKéMON that faints is gone for good.
3. Check the run under **OPTIONS → NUZLOCKE → NUZLOCKE RECORD**.

The randomizer (RANDOM WILD / RANDOM STARTERS) is not part of this mod. It
is a setting of the game itself, in OPTIONS and on the NEW GAME screen.

## The rules

- **One encounter per area.** An area is a region-map section (Route 101's
  eleven maps are one area; a cave's floors are one area). The first wild
  POKéMON met there, once the bag holds a POKé BALL, is the only one that can
  be caught. Later ones dodge every ball. Scripted single battles (legendaries,
  Snorlax) are statics: they never use up an area and can always be caught.
- **Fainted means dead.** A POKéMON that faints is marked dead at once. On the
  next overworld frame it leaves the party for the run's graveyard. It is
  kept in the save and never deleted.
- **Run over.** When the whole party is gone, the RUN OVER screen offers
  *PLAY ON, NO RULES*, which brings every fallen POKéMON back, healed,
  or *END RUN*, which saves and returns to the title. The save is never wiped.

## Soul Link

Both players pick SOUL LINK at NEW GAME, then meet in an online world:
*LINK → WORLDS*, either a world one of them hosts (share its invite code) or
the Link Hub's world. The first Soul Link run heard is bound as the partner
and stays bound in the save.

- Encounters are paired **by area** when both play the same game, else **by
  encounter order** (the n-th encounter of each run, caught or missed).
- When one side misses an area and the other caught there, the caught one
  dies.
- When a paired POKéMON dies, its partner's pair dies too, even from the PC.
- Events queue in the save until the partner acknowledges them, so going
  offline or reloading loses nothing.
- Soul Link POKéMON can't be traded or put in the GTS.

## Online

The mod declares `run_rules`. It judges only this save's run and never the
shared battle simulation, so online play stays open with it on. Dead
POKéMON never go into a link battle, a trade, the GTS or a transfer. This is
enforced by the engine, so it holds even with the mod switched off.
