# Run modes: Nuzlocke, Soul Link, randomizer

Every Pokémon game the engine runs (Red/Blue/Yellow, Gold/Silver/Crystal,
Emerald/FireRed/LeafGreen, Platinum, HeartGold/SoulSilver, Black/White) asks
at **NEW GAME** what kind of run this is:

| Row | What it does |
|---|---|
| NUZLOCKE | First POKéMON met in each area only; fainted = dead; the run ends when the whole party is gone. Needs the bundled NUZLOCKE mod. |
| SOUL LINK | Nuzlocke with a friend online: encounters per area are paired, and when one dies, its partner dies too. |
| RANDOM WILD | Wild encounters are randomized, seeded per save. |
| RANDOM STARTERS | The starter is randomized, seeded per save. |

The choice is stored in the save as `save.runModes` (`src/runmodes/RunModes.lua`).
A save without that field, which includes every save made before this
feature, plays with every mode off. Nothing in the run modes ever deletes or
wipes a save: a dead POKéMON moves to the run's graveyard
(`save.runModes.graveyard`), and a finished run can be played on with the
rules off and every POKéMON back.

**The randomizer is a game setting, not a mod.** RANDOM WILD and RANDOM
STARTERS are rows in every game's own OPTIONS menu
(`OptionsMenu.buildRows`, which the Gen 3 and DS options screens append) and
on the NEW GAME screen. They work with no mod installed. Turning one on gives
the save its seed. Turning it off and on again keeps that seed, so the same
species come back.

On a Nuzlocke or Soul Link save, OPTIONS also has a **NUZLOCKE** row, which
opens the run's modes and record. Those rules come from the bundled
NUZLOCKE mod.

## Where it lives

- `src/runmodes/RunModes.lua`: the save field, the seed and hashing, the dead and
  Soul Link flags, the hello summary.
- `src/runmodes/Randomizer.lua`: the seeded picks.
  - **Wild:** every encounter is its own pick, from (seed, map, species, the
    save's encounter counter `wildCount`). Two Zigzagoon in a row become two
    different species, and the same species never comes up twice running
    (`lastWild`). The counter is saved, so a reload replays the same sequence.
  - **Starters:** one stable pick per starter.
  - **Strength:** a pick keeps the original's strength band (base stat
    total), widened until it holds at least 40 candidates for wild mons.
- `src/runmodes/RunHooks.lua`: the engine seams, called from shared code:
  - `BattleState.newWild` (randomizer, and the Nuzlocke catch verdict through
    `battle.noCatch`)
  - `Commands.give_pokemon` (starters: the first mon of a randomized-starters
    save, when it is one of the game's starters)
  - `BattleState:onFaint` / `storeCaughtMon` / `finish`
  - `OverworldState:update`

  Scripted single battles (`Commands.start_battle`) are statics: never
  randomized, and they never use up an area. Catch tutorials, link battles
  and Pal Park run quiet.
- `src/runmodes/NewGameGate.lua` + `src/ui/RunSetup.lua`: the NEW GAME screen,
  pushed from `Game:makeTitleState`'s NEW GAME for every family.
  `POKEPORT_RUNMODES=skip` skips it for harnesses that script the title.
- `mods/NUZLOCKE`: the rules (`lib/Rules.lua`), Soul Link (`lib/SoulLink.lua`)
  and the RECORD / RUN OVER screens. It is bundled with every release
  (`scripts/bundled_mods.txt`) and declares `run_rules`.
  `Handshake.onlineBlockers` lets such a mod through after checking it: no
  registry writes, and only `runmodes.*` / menu seams.
- `src/online/SoulLinkService.lua`: the `soullink` relay on every hosted world
  and the Link Hub world.

## Online

- **Link battles:** `Protocol.packParty` never packs a dead mon.
- **Trades:** `TradeSession:_runGate` greys out dead and Soul Link mons.
- **GTS:** `GtsRules.depositBlocker` refuses them.
- **Transfers:** `TransferSession` refuses them.
- **The hello:** it carries `runModes` (the summary), so a peer can see what
  kind of run it is linking with.

These filters are engine-side, so they hold even with the mod switched off.

## Tests

```
python tools/run_lua_check.py tests/runmodes_test.lua
python tools/run_lua_check.py mods/NUZLOCKE/tests/nuzlocke_test.lua
```

Set `POKEPORT_DATA_DIR=<install>/data/generated` to run on a real dataset.
Both suites pass on the Red, Crystal, Emerald, FireRed, Platinum, HeartGold
and Black caches.

## The full randomizer

RUN MODES -> **RANDOMIZER...** (NEW GAME) and OPTIONS -> **RANDOMIZER** (live
save) open `src/ui/RandomizerSetup.lua`: every option with its own switch,
grouped POKéMON / MOVES / ITEMS & SHOPS / TRAINERS, plus **FULL (EVERYTHING)**,
**ALL OFF** and (OPTIONS only) **WRITE SPOILER LOG** (`randomizer/spoiler_<seed>.txt`
in the save directory). Options that do nothing on the loaded generation are
greyed out.

- `src/runmodes/RandomOptions.lua`: the catalog (keys, labels, generations,
  FULL values). Options live in `save.runModes.random`; `randomWild` /
  `randomStarters` stay at the top of `save.runModes`.
- `src/runmodes/RandomData.lua`: the data-side options (move power / accuracy /
  PP / type / category, learnsets, TM and tutor compatibility, types,
  abilities, base stats, evolutions, wild held items, prices, trainer names,
  field items) are written into the loaded dataset IN MEMORY through a journal
  and taken off again when another save is live (`RandomData.sync`, from
  `RunHooks.tick` and every pick). Nothing is written to disk.
- `src/runmodes/RunHooks.lua`: the picks made when they happen: statics and
  gifts, trainer teams and their held items, starting moves, marts
  (`ShopMenu.new`, `Gen3ShopMenu.new`, `Gen4ShopMenu` `Shop.new`), item gifts
  (`Commands.give_item`, `g2_giveitem`, `g4_give_item`) and the relearner
  (`Gen2Specials`, `Gen3Commands.relearnableMoves`, `Gen4Commands.reminderMoves`).

Safety: level 1 always has an attack and every other later move is one; HM
(and tutor) compatibility is kept; key items, HMs and story items are never
replaced or handed out; prices stay between half and double and balls never
get dearer; marts keep their POKé BALLS and POTIONS; legends (BST 580+) keep
their species as statics and gifts.

```
python tools/run_lua_check.py tests/randomizer_full_test.lua   # POKEPORT_DATA_DIR=<game>/data/generated
```

## Randomized starters and the rival

The starter scripts and their vars stay vanilla. Only the species changes:

- **Your starter:** `RunHooks.giftSpecies` swaps it at give time.
- **Rival and trainers:** `RunHooks.trainerParty` (in `BattleState.newTrainer`)
  replaces every starter-line mon in a trainer's party with the randomized
  counterpart at the same evolution stage, so the rival still counters your
  pick.
- **Starter screens:** the Gen 3/4/5 select screens draw the randomized
  species (`RunHooks.shownStarter`). The Gen 1 dex entry and received text
  and the Gen 2 pokepic and name buffer use `RunHooks.introShown`, which only
  applies while the party holds at most the starter.
- **Fixed text:** ROM dialogue that names a species outright ("So! You want
  CHARMANDER?") stays as written.

## Soul Link pairing

- **Same game:** encounters pair by area.
- **Different games:** they pair by encounter order, the n-th counted
  encounter of each run, caught or missed. A miss breaks a pair across games
  too.
- **Unpaired catches:** statics and catches made before the first Poké Ball
  are free and never paired.

## Scripted runs

`POKEPORT_DRIVER` / `POKEPORT_AUTOPILOT` skip the RUN MODES screen. Their NEW
GAME mashes A, which would toggle a row forever. Set `POKEPORT_RUNMODES=show`
to drive the screen.

## Known gaps

- Rental mons (Battle Factory) are skipped by the faint rule, but frontier
  battles with your own party count like any other trainer battle.
