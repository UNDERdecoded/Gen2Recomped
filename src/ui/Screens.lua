-- Screen id -> factory resolution.  The screens registry (Data.screens)
-- wins; engine screens are the require fallback, so a mod-free boot
-- resolves every id to the exact module it required before.  One cache,
-- dropped with the rest of the asset caches on dev-mode hot reload.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Screens = {}

-- ids whose builtin module is not under src/ui/
local BUILTIN = {
  ManagerState = "src.mods.ManagerState",
  Gen2StartMenu = "src.ui.StartMenu",
}

local cache = {}

local function builtinFor(id)
  return require(BUILTIN[id] or ("src.ui." .. id))
end

-- What to show when a mod screen cannot be constructed.
--
-- The old recovery was `builtinFor(id).new(game, ...)` unconditionally, and a
-- MOD-OWNED id has no builtin by definition -- the id is the mod's own.  So
-- requiring it raised "module 'src.ui.<Id>' not found" OUT of Screens.push,
-- into whatever was pushing: a party-menu update, a script step, a battle
-- callback, all places where a raise ends the game.  The rescue was strictly
-- worse than the failure, and it hid it -- the reported error named a module
-- nobody wrote instead of the mod that broke.
--
-- Callers rely on push returning an instance, so this always returns one.
local function noticeScreen(game, id, err)
  local text = ("SCREEN FAILED\n\n%s\n\n%s"):format(tostring(id), tostring(err))
  return {
    screenId = id,
    isOpaque = true,
    update = function()
      if game.input and game.input:wasPressed("b") then game.stack:pop() end
    end,
    draw = function()
      -- Required here, not at the top of the file: Screens is pulled in early
      -- and the render stack is not needed to resolve an id.
      local Font = require("src.render.Font")
      Font.drawBox(0, 0, 20, 18)
      local y = 8
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        while #line > 18 do            -- 18 chars is the interior at one tile in
          Font.draw(line:sub(1, 18), 8, y)
          line, y = line:sub(19), y + 8
        end
        Font.draw(line, 8, y)
        y = y + 8
        if y > 136 then break end
      end
    end,
  }
end

-- ---------------------------------------------------------------------------
-- EMERALD'S SCREENS, WHEREVER THEY ARE ASKED FOR
--
-- Each of these ids has a GBA version, and until now the ONLY thing that knew
-- so was `field.boot.screens` -- a snapshot table read in exactly one place,
-- Gen3StartMenu:buildRows.  That is thin in two ways, and both of them showed
-- up on screen:
--
--   * EVERY OTHER CALL SITE HARDCODES THE GAME BOY ID.  BagMenu pushes
--     "PartyMenu" to pick an item's target, a script pushes it to choose a
--     mon, PartyMenu pushes "SummaryMenu" for STATS.  None of them consults
--     the boot record, so on a Gen 3 cache those routes opened the Game Boy
--     screen -- a Gen 1 stats page with FOUR stats and a single SPECIAL, for
--     an Emerald Pokemon that has six.
--   * AND ONE MISSING BOOT RECORD TAKES ALL OF THEM AT ONCE.  boot.screens is
--     built during Data:seedDefaults and lives on data.field; anything that
--     leaves that table without one -- a cache shape the seed did not run
--     for, a reload, a mod that replaces field -- silently reverts the bag,
--     the party menu and the trainer card together, which is exactly what it
--     looks like.
--
-- So the mapping moves here, where every push goes through it, and it is
-- derived from the DATASET rather than from a record something has to have
-- remembered to write.
--
-- `opts` IS PART OF THE DECISION.  Emerald's party menu is the START MENU's
-- party menu: it lists the party and it closes.  It does not do the Game
-- Boy screen's SWITCH/STATS/ITEM submenu, forced switch-ins, item targeting
-- or TM teaching, and handing it one of those calls would open a screen that
-- ignores the callback and strands the player.  So an alias declares which
-- options its screen actually serves, and a push carrying anything else stays
-- on the screen that implements it.  That is a smaller lie than the one it
-- replaces: a Game Boy party menu in a Hoenn battle is wrong, but a Hoenn
-- party menu that cannot switch is BROKEN.
-- WHICH PUSHES EACH GEN 3 SCREEN CAN ANSWER, by the option keys it reads.
--
-- The list is deliberately a whitelist rather than "anything": a push
-- carrying an option the Gen 3 screen does not implement would open a screen
-- that silently ignored it, and a party menu that ignores `tmhm` is worse
-- than one that declines and lets the older screen serve.
--
-- The battle keys were the gap the player actually felt.  Pressing POKeMON
-- or BAG mid-fight pushes `battle` (and `onSwitch`, `forceSwitch` or
-- `pickOnly` with it); with those absent here the push declined every time,
-- and an Emerald battle opened Kanto's Game Boy party list.
local GEN3_ALIASES = {
  -- `onPick` is the bag answering a QUESTION rather than using anything:
  -- the Berry Blender asks which berry you are throwing in, and the
  -- Gen 3 screen has answered that since it was written.  Without it
  -- here the alias declined and the blender opened Kanto's bag.
  BagMenu = { id = "Gen3BagMenu",
              opts = { onCancel = true, battle = true, onPick = true,
                       pick = true, pocket = true } },
  TrainerCard = { id = "Gen3TrainerCard", opts = { onCancel = true } },
  PartyMenu = { id = "Gen3PartyMenu", opts = {
    onCancel = true, onSwitch = true, battle = true,
    forceSwitch = true, pickOnly = true, keepOpen = true,
    -- TM/HM teaching.  Reported from play: "when teaching a move its falling
    -- back to the gen1 party menu instead of emerald".  It was declined here
    -- until Emerald's screen could answer ABLE / NOT ABLE off the learnset,
    -- which it now does out of the cartridge's own four words.
    tmhm = true,
    -- CHOOSING A TEAM for the Battle Frontier, both Battle Tents and the link
    -- colosseum -- pick some of the party, in order.  An alias that did not
    -- list these two declined the push, no screen opened, and the script that
    -- had just asked for a team compared VAR_RESULT against a stale value.
    chooseOrder = true, onOrder = true,
  } },
  -- `choose` is the move-learn screen asking this one to pick the move to
  -- forget, which is where the cartridge asks it
  SummaryMenu = { id = "Gen3SummaryMenu",
                  opts = { onCancel = true, mon = true, choose = true } },
  StartMenu = { id = "Gen3StartMenu", opts = { onCancel = true } },
  OptionsMenu = { id = "Gen3Options", opts = { onCancel = true } },
  -- THE DEX IS TWO SCREENS AND THE SECOND ONE IS PUSHED WITH A BARE SPECIES.
  -- Every other alias here takes an options table; DexEntryMenu's callers --
  -- the dex list, and the battle's "New POKeDEX data will be added" -- pass
  -- the species id itself, so the alias has to say that a plain species is a
  -- push it can serve.
  PokedexMenu = { id = "Gen3Pokedex", opts = { onCancel = true } },
  -- THE PC IS A GRID IN HOENN, NOT A STACK OF MENUS.  Bill's PC lists twenty
  -- names; a Hoenn box holds thirty, so the old screen could not show one
  -- even in principle.
  -- `mode` is what the storage menu above the grid asked for: WITHDRAW,
  -- DEPOSIT or MOVE.  Without it the grid falls back to its per-slot submenu,
  -- which is what a caller that has not been through that menu wants.
  BoxMenu = { id = "Gen3BoxMenu", opts = { onCancel = true, mode = true } },
  -- `onDone` because a SCRIPT opens this one too (special 63, the Poke
  -- Centre's "SOMEONE'S PC"), and pushBlocking always carries that option:
  -- an alias that does not list it declines the push, no screen opens, and
  -- the script asks its question again -- forever.
  StorageMenu = { id = "Gen3StorageMenu",
                  opts = { onCancel = true, onDone = true } },
  -- THE PC ITSELF, which Hoenn opens with a menu Gen 1 does not have: item
  -- storage, the mailbox and the decorations sit ABOVE the withdraw/deposit
  -- rows.  Reported from play as "the pc in the starting bedroom ... I get
  -- the gen1 menus for depositing items" -- there was no alias here, so the
  -- push fell through to the Game Boy screen, which also never called the
  -- script back and left the player unable to walk.
  PlayerPC = { id = "Gen3PlayerPC",
               opts = { onCancel = true, onDone = true, order = true } },
  -- THE ONE SCREEN HERE THAT IS NOT PUSHED WITH AN OPTIONS TABLE.  Six
  -- callers say Screens.push(game, "MoveLearnMenu", mon, moveId, onDone) --
  -- the bag's TM use, Evolution, both move-relearner specials and the
  -- battle's level-up learn -- so this alias passes every argument through
  -- as it stands rather than folding the first into a table.
  MoveLearnMenu = { id = "Gen3MoveLearnMenu", positional = true },
  -- THE EVOLUTION SCENE, which is positional for the same reason: it is
  -- pushed as (mon, newSpecies, onDone, via, evo) and the last two decide
  -- whether B may stop it.
  EvolutionState = { id = "Gen3EvolutionState", positional = true },
  DexEntryMenu = { id = "Gen3DexEntry", opts = { species = true,
                                                 forceOwned = true } },
}

-- WHICH GEN 4 SCREENS EXIST, which is currently one.
--
-- The same mechanism as GEN3_ALIASES above and for the same reason: every call
-- site in this engine hardcodes the Game Boy id, so a Platinum player pressing
-- OPTION in the START menu opened Kanto's option screen -- six Gen 1 rows, and
-- a FRAME row with nothing to choose between.  The boot record already named
-- Gen4Options, but only the MAIN MENU reads that record; the START menu pushes
-- the id.
--
-- THE LIST IS SHORT BECAUSE THE SCREENS DO NOT EXIST YET, and that is stated
-- rather than papered over.  Platinum's bag, party screen, summary pages and
-- trainer card are all EXTRACTED -- the art is in the cache -- and none of
-- them has a screen to draw it, so those ids still open the Game Boy ones and
-- will keep doing so until they do.  Adding an alias for a screen that is not
-- written would open a module that is not there.
local GEN4_ALIASES = {
  EvolutionState = { id = "Gen4EvolutionState", positional = true },
  StorageMenu = { id = "Gen4StorageMenu", opts = { onCancel = true, onDone = true } },
  BoxMenu = { id = "Gen4BoxMenu", opts = { mode = true, onCancel = true, onDone = true } },
  ShopMenu = { id = "Gen4ShopMenu", positional = true },
  OptionsMenu = { id = "Gen4Options", opts = { onCancel = true } },
  -- Reported from play alongside the options screen: the card was falling
  -- back to Kanto's.  The Gen 4 one answers the same one option.
  TrainerCard = { id = "Gen4TrainerCard", opts = { onCancel = true } },
  -- The bag serves the same options Emerald's does EXCEPT the shop and the
  -- PC's three stores, which have their own flows: a push carrying `sell`,
  -- `itemPc` or `store` is declined here and goes to the screen that can
  -- answer it rather than opening a Platinum bag that cannot.
  BagMenu = { id = "Gen4BagMenu",
              opts = { onCancel = true, battle = true, onPick = true,
                       pick = true, pocket = true } },
  -- THE PARTY MENU, IN A BATTLE TOO.
  --
  -- `battle` used to be deliberately absent here, on the reasoning that a
  -- declined push would be served by the Gen 3 screen, which already answers
  -- SHIFT, forced switches and an item's target. IT WOULD NOT. Look at
  -- `resolveId` below: once the Gen 4 alias declines it reaches
  -- `if not isGen3(game) then return id, arg end` and hands back the GAME BOY
  -- id, because a Platinum cache is not a Hoenn one. So every in-battle
  -- POKeMON press on Platinum opened KANTO'S party list -- reported from play,
  -- and the same shape as the keyboard and the Pokedex before it.
  --
  -- What made serving it honest rather than a dead end is that Gen4PartyMenu's
  -- submenu now offers SEND OUT in a battle instead of SWITCH; whether the
  -- member MAY go out is BattleState's own onSwitch, which already rejects an
  -- egg, a fainted member and one already on the field.
  --
  -- `tmhm` IS SERVED NOW, AND ITS ABSENCE WAS NOT COSMETIC.
  --
  -- The note here used to say it needed words the cache does not carry. It
  -- carries them: bank 453 has ABLE!, UNABLE!, LEARNED and "Teach which
  -- Pokemon?", and Gen4Menus.PARTY_BANK says how that was settled. What the
  -- absence actually cost was worse than a wrong-looking screen -- the push
  -- was declined, `resolveId` handed back the GAME BOY id, and whichever
  -- screen served it then called ItemEffects.use, which scans
  -- `speciesDef.tmhm` with a bare ipairs. A Gen 4 cache had no such list. SO
  -- USING A TM IN SINNOH RAISED. Both halves are fixed: the extractor unpacks
  -- the cartridge's machine mask into that list, and this alias stops
  -- declining the push.
  --
  -- STILL ABSENT, and the reason is now a different one: `chooseOrder` and
  -- `onOrder` are pushed by ONE caller in the whole port, Gen3Commands'
  -- chooseParty, which is a Gen 3 script special. NOTHING ON A GEN 4 CACHE
  -- PUSHES THEM, so listing them here would serve a push that never arrives.
  -- (The words are there too -- 154 ENTER, 155 NO ENTRY, 169..174
  -- FIRST..SIXTH -- so the day a Gen 4 command needs it, only the screen has
  -- to be written.)
  PartyMenu = { id = "Gen4PartyMenu",
                opts = { onCancel = true, onSwitch = true, pickOnly = true,
                         forceSwitch = true, keepOpen = true,
                         battle = true, tmhm = true } },
  -- The summary is pushed with the Pokemon itself, which `servedBy` reads as
  -- `mon`.
  --
  -- `readOnlyMoves` IS LISTED, and leaving it off crashed the game.  The Gen 4
  -- party menu's SUMMARY row pushes `{ mon = mon, readOnlyMoves = ... }` and
  -- `Gen4SummaryMenu.new` reads that key -- but the alias did not name it, so
  -- every press declined the Gen 4 screen and (on a Gen 4 cache, where the
  -- Gen 3 table is never consulted) landed on the Game Boy `SummaryMenu`.
  -- That screen takes `(game, mon, opts)` POSITIONALLY, so the options table
  -- arrived as the Pokemon, `mon.species` was nil, and `data.pokemon[nil]`
  -- was nil: "attempt to index local 'def' (a nil value)".
  --
  -- The lethal part is not the fallback, it is that the two generations'
  -- screens have DIFFERENT SIGNATURES and the fallback crosses them.  An
  -- unnamed key here is not a cosmetic downgrade; it is a crash.
  --
  -- `choose` -- the move-learn screen asking which move to forget -- is still
  -- NOT listed: that page needs the cartridge's own forget flow, and
  -- `Gen4SummaryMenu` assigns `self.choose` without ever reading it, so
  -- serving it there would be a screen with no way to pick.  (The note that
  -- used to sit here said the Gen 3 screen answers it.  It does not:
  -- `resolveId` consults the Gen 3 table only `if isGen3(game)`, so on
  -- Platinum a `choose` push reaches the Game Boy screen.  It is a fallback
  -- with a known destination now rather than an assumed one -- and that screen
  -- reads the options shape, so it no longer crashes on arrival.)
  SummaryMenu = { id = "Gen4SummaryMenu",
                  opts = { onCancel = true, mon = true, readOnlyMoves = true } },
  -- THE KEYBOARD, which had no entry at all -- so every name the player types
  -- opened Kanto's, on a Platinum save.  Reported as "the keyboard where you
  -- type your name or your pokemons nickname is also not correct for gen4
  -- platinum its falling back to gen1".
  --
  -- Every option the Game Boy screen takes is listed, because `servedBy`
  -- declines a push carrying a key the alias does not name and a naming
  -- screen is pushed from a dozen places with different halves of this set:
  -- the intro asks for a player name with `presets`, a nickname prompt passes
  -- `mon` and `species`, a box rename passes only `default`.
  NamingScreen = { id = "Gen4NamingScreen",
                   opts = { title = true, presets = true, maxLen = true,
                            default = true, onDone = true, kind = true,
                            species = true, mon = true } },
  -- THE POKEDEX, which was the last of the four screens reported as "looking
  -- like gen1 still" without an entry here.  It was left without one on
  -- purpose: its art composed blank, and a Gen 4 Pokedex drawn on a blank page
  -- would have been worse than Kanto's.  The `dex` stage composes it now.
  PokedexMenu = { id = "Gen4Pokedex", opts = { onCancel = true } },
  -- THE START MENU, which is the other half of the original brief: Platinum's
  -- own rows and icons, on the MAIN screen by default like every other version
  -- in this launcher, with a row on OPTIONS to move it to the second screen.
  --
  -- `servedBy` sees a bare push with no options at all from the field, which
  -- is why `opts` is empty rather than absent -- an alias with no opts table
  -- declines every push that carries one, and the Safari and Bug Contest
  -- pushes do not carry any either.
  StartMenu = { id = "Gen4StartMenu", opts = { onCancel = true } },
  -- ...AND THE UNDERGROUND HAS ITS OWN, which REPLACES that one while you
  -- are down there rather than sitting beside it. The cartridge builds a
  -- different window from a different table (`sUndergroundMenuOptions` in
  -- `src/underground/menus.c`), and GO UP exists nowhere else -- which is
  -- why `CanUseExplorerKit` refuses the kit underground.
  UndergroundMenu = { id = "Gen4UndergroundMenu", opts = { onCancel = true } },
}

local function isGen4(game)
  local data = game and game.data
  if data and data.isGen4Cache then return true end
  local ok, V = pcall(require, "src.core.GameVersion")
  return (ok and V.generation and V.generation(V.get()) == 4) and true or false
end

local function isGen3(game)
  local data = game and game.data
  if data and data.isGen3Cache then return true end
  local ok, V = pcall(require, "src.core.GameVersion")
  return (ok and V.isGen3()) and true or false
end

-- Does this push carry only options the Gen 3 screen serves?  A bare mon (the
-- shape PartyMenu hands "SummaryMenu") counts as `mon`.
-- one warning per screen and option, not one per press
local declined = {}

-- SAY WHICH OPTION DECLINED A PUSH, once per screen and key.
--
-- A push carrying an option the generation's screen does not list falls back
-- to the Game Boy one, and the player sees the wrong screen -- or, when the
-- pusher is a SCRIPT, no screen at all and a question asked over and over
-- ("when selecting someones pc ... it loops and asks over and over again").
-- The rule is deliberate; the silence was not.
--
-- IT WAS ON THE GEN 3 PATH ONLY, which is how the Gen 4 summary crash stayed
-- invisible: `Gen4PartyMenu` pushed `readOnlyMoves`, the Gen 4 alias did not
-- name it, and nothing said so.  One sentence, both generations.
local function warnDeclined(id, alias, arg)
  if type(arg) ~= "table" then return end
  for key in pairs(arg) do
    if not alias.opts[key] then
      local mark = id .. ":" .. tostring(key)
      if not declined[mark] then
        declined[mark] = true
        require("src.core.Logger").warn(
          "screens: a push of %s carries `%s`, which %s does not serve -- "
          .. "falling back to the Game Boy screen", id, tostring(key),
          alias.id)
      end
    end
  end
end

local function servedBy(alias, arg)
  if arg == nil then return true end
  -- a bare species id, which is how the dex entry page is asked for
  if type(arg) == "string" then return alias.opts.species == true end
  if type(arg) ~= "table" then return false end
  -- SummaryMenu's caller passes the Pokemon itself rather than an options
  -- table; a mon is recognised by carrying a species
  if arg.species ~= nil then return alias.opts.mon == true end
  for key in pairs(arg) do
    if not alias.opts[key] then return false end
  end
  return true
end

-- THE ALIAS TABLES, PUBLISHED FOR THE SUITE, for the same reason `resolveId`
-- is: the rule they encode can then be stated without driving a whole game.
--
-- What `tools/screen_alias_check.lua` does with them is the sweep that would
-- have caught the Gen 4 summary crash: every table-literal `Screens.push`
-- site in the port, every key in it, against the alias for that generation.
-- An unnamed key is not a cosmetic downgrade -- the push falls through to a
-- screen whose arguments are POSITIONAL, so the options table lands where the
-- Pokemon goes.
Screens.ALIASES_FOR_CHECKS = { gen3 = GEN3_ALIASES, gen4 = GEN4_ALIASES }

-- Is this id served by a POSITIONAL alias?
--
-- THE BATTLE'S MOVE LEARNING WAS THE GAME BOY SCREEN and this is why.
-- Reported from play: "in battle when a pokemon learns a move it should show
-- the gen3 menu but it doesnt".  The alias was here, and every push site got
-- Emerald's screen -- but the battle does not push, it builds, and
-- BattleState:buildScreen only consulted the alias when the call carried at
-- most ONE argument, because an options table is the only shape that can be
-- folded.  Move learning is built as (mon, moveId): two arguments, so the
-- alias was never asked and the Game Boy screen came up.  A positional alias
-- is exactly the case where that restriction does not apply -- nothing is
-- folded, every argument passes through as it stands -- so buildScreen asks
-- this before giving up on a multi-argument call.
function Screens.positionalAlias(id)
  local alias = GEN3_ALIASES[id] or GEN4_ALIASES[id]
  return (alias ~= nil and alias.positional == true) and true or false
end

-- The id a push should really open, and the arguments it should open with.
-- Public so the suite can state the rule without driving a whole game.
function Screens.resolveId(game, id, arg)
  -- Gen 4 first: a cache is one or the other, and asking in this order means
  -- the Gen 3 table never has to know that a fourth generation exists.
  local gen4 = GEN4_ALIASES[id]
  if gen4 and isGen4(game) then
    local screens = game and game.data and game.data.screens
    if not (screens and screens[id]) and (gen4.positional or servedBy(gen4, arg)) then
      local okG4, moduleG4 = pcall(builtinFor, gen4.id)
      if okG4 and type(moduleG4) == "table"
         and type(moduleG4.new) == "function" then
        return gen4.id, arg
      end
    end
    -- ...and when it did NOT serve, say which key -- see warnDeclined.
    -- Only on the declining path: a push that was served has returned by
    -- now, and a mod that overrode the id by name is not a decline.
    if not (screens and screens[id]) and not gen4.positional
       and not servedBy(gen4, arg) then
      warnDeclined(id, gen4, arg)
    end
  end
  local alias = GEN3_ALIASES[id]
  if not alias then return id, arg end
  if not isGen3(game) then return id, arg end
  -- A POSITIONAL alias takes its arguments as they come: there is no options
  -- table to inspect, so `servedBy` has nothing to say about it and the
  -- argument is handed back untouched.
  if alias.positional then
    local screens = game and game.data and game.data.screens
    if screens and screens[id] then return id, arg end
    local okPos, modulePos = pcall(builtinFor, alias.id)
    if not (okPos and type(modulePos) == "table"
            and type(modulePos.new) == "function") then
      return id, arg
    end
    return alias.id, arg
  end
  -- A MOD THAT OVERRODE THE ID STILL WINS.  It asked for this id by name,
  -- and quietly opening a different screen would make the override look
  -- broken rather than overridden.
  local screens = game and game.data and game.data.screens
  if screens and screens[id] then return id, arg end
  if not servedBy(alias, arg) then
    warnDeclined(id, alias, arg)
    return id, arg
  end
  local ok, module = pcall(builtinFor, alias.id)
  if not (ok and type(module) == "table" and type(module.new) == "function") then
    return id, arg
  end
  -- SummaryMenu takes the mon bare; the Gen 3 one takes it in an options
  -- table, so the one caller that passes a mon is adapted rather than
  -- rewritten at every call site.  A dex push carrying `species` is a species
  -- id, not a Pokemon, and its screen reads it as it stands.
  if type(arg) == "table" and arg.species ~= nil
     and alias.opts.species ~= true then
    return alias.id, { mon = arg }
  end
  return alias.id, arg
end

local function resolve(game, id)
  local hit = cache[id]
  if hit then return hit end
  local screens = game and game.data and game.data.screens
  local record = screens and screens[id]
  local factory
  if record then
    -- registry record: { new = fn } or a bare function (05-registry-system)
    factory = (type(record) == "function") and { new = record } or record
    factory.__modOwned = true
  else
    factory = builtinFor(id)
  end
  cache[id] = factory
  return factory
end

function Screens.get(game, id)
  return resolve(game, id)
end

local function pushWith(game, id, ...)
  local factory = resolve(game, id)
  local inst
  if factory.__modOwned then
    -- A broken mod screen degrades, and the degrade itself cannot raise.
    local ok, result = pcall(factory.new, game, ...)
    if ok and result then
      inst = result
    else
      Logger.error("mod screen '%s' failed: %s", id, tostring(result))
      cache[id] = nil
      -- Only where a builtin genuinely exists -- an engine id a mod overrode.
      local okBuiltin, builtin = pcall(builtinFor, id)
      if okBuiltin and type(builtin) == "table" and type(builtin.new) == "function" then
        local okNew, built = pcall(builtin.new, game, ...)
        if okNew and built then
          inst = built
        else
          Logger.error("builtin screen '%s' also failed: %s", id, tostring(built))
        end
      end
      inst = inst or noticeScreen(game, id, result)
    end
  else
    inst = factory.new(game, ...)
  end
  inst.screenId = inst.screenId or id
  game.stack:push(inst)
  return inst
end

function Screens.push(game, id, ...)
  -- A POSITIONAL alias keeps every argument, because its screen is not an
  -- options-table screen -- MoveLearnMenu takes (mon, moveId, onDone) and
  -- dropping the last two would open it with nothing to teach.
  if Screens.positionalAlias(id) then
    local resolvedId = Screens.resolveId(game, id, ...)
    return pushWith(game, resolvedId, ...)
  end
  -- Otherwise only the FIRST argument decides: every other screen in the
  -- alias table takes one options table and nothing else, and a caller
  -- passing more is by that fact not talking to one of them.
  local resolvedId, resolvedArg = Screens.resolveId(game, id, ...)
  if resolvedId ~= id then return pushWith(game, resolvedId, resolvedArg) end
  return pushWith(game, id, ...)
end

function Screens.invalidate()
  cache = {}
end

Assets.register(Screens.invalidate)

return Screens
