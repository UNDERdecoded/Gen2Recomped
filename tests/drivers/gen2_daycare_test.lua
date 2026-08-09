-- Route 34 DAY-CARE: two pens, breeding, the yard sprites and the EGG hand-over.
--
-- The specials (DayCareMan $1E, DayCareLady $1F, DayCareManOutside $20,
-- DayCareMon1/2 $44/$45) were already lowered, but nothing wrote the three
-- ENGINE flags the two object callbacks stage the cast from:
--
--   Route34EggCheckCallback  4B:$5077   flags $05/$06/$07 -> events 1765..1768
--   DayCareEggCheckCallback  57:$7185   flag  $05         -> events 1765/1766
--
-- so the yard never held a sprite and the MAN OUTSIDE could never step out to
-- announce an EGG.  DayCareManScript_Outside also branches on wScriptVar
-- ($1 = no room), which the special never set, so the walk back inside was a
-- coin toss.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL", what) end
  end

  U.newGame(game)
  U.wait(10)

  local Commands = require("src.script.Commands")
  local Flags = require("src.script.Flags")
  local Pokemon = require("src.pokemon.Pokemon")
  local DayCare = require("src.pokemon.DayCare")
  local VM = require("src.script.Gen2ScriptVM")
  local OverworldState = require("src.world.OverworldController")
  require("src.script.Gen2Commands")

  local save = game.save

  -- ---------------------------------------------------------------- lowering
  local function lower(label)
    local rows = VM.compile(game.data, label) or {}
    local names = {}
    for _, row in ipairs(rows) do names[row[1]] = true end
    return names
  end
  ok(lower("S57_7199").g2_daycare_man, "DayCareManScript_Inside -> special $1E")
  ok(lower("S57_71A1").g2_daycare_lady, "DayCareLadyScript -> special $1F")
  ok(lower("S4B_50D7").g2_daycare_mon1, "DayCareMon1Script -> special $44")
  ok(lower("S4B_50DD").g2_daycare_mon2, "DayCareMon2Script -> special $45")
  local outside = lower("S4B_50AF")
  ok(outside.g2_daycare_outside, "DayCareManScript_Outside -> special $20")
  ok(outside.g2_move and outside.g2_object,
     "the outside script keeps its walk-back-inside movement")
  ok(lower("S4B_5077").check_flag, "Route34EggCheckCallback reads the flags")

  -- ------------------------------------------------------- the two pens fill
  local function mon(species, level) return Pokemon.new(game.data, species, level) end
  save.daycare = nil
  DayCare.syncFlags(save)
  ok(not Flags.get(save, DayCare.FLAG_MAN_HAS_MON), "empty pen -> flag $06 clear")
  ok(not Flags.get(save, DayCare.FLAG_LADY_HAS_MON), "empty pen -> flag $07 clear")
  ok(not Flags.get(save, DayCare.FLAG_HAS_EGG), "no EGG -> flag $05 clear")

  -- DITTO + a NIDORAN-F: the ROM's canonical breeding pair
  local ditto, nidoran = mon("SPECIES_132", 20), mon("SPECIES_029", 20)
  DayCare.deposit(save, DayCare.MAN, nidoran)
  ok(Flags.get(save, DayCare.FLAG_MAN_HAS_MON), "MAN's pen sets flag $06")
  ok(not Flags.get(save, DayCare.FLAG_LADY_HAS_MON), "LADY's pen still clear")
  DayCare.deposit(save, DayCare.LADY, ditto)
  ok(Flags.get(save, DayCare.FLAG_LADY_HAS_MON), "LADY's pen sets flag $07")
  ok(DayCare.mon(save, DayCare.MAN) == nidoran
     and DayCare.mon(save, DayCare.LADY) == ditto,
     "both slots hold their own mon")

  -- ------------------------------------------------- the yard sprites appear
  local function objByIndex(mapId, index)
    for _, obj in ipairs(game.data.maps[mapId].objects or {}) do
      if obj.index == index then return obj end
    end
  end
  local function npcOnMap(index)
    for _, npc in ipairs(game.overworld.npcs or {}) do
      if npc.def.index == index then return npc end
    end
  end

  U.teleport(game, "ROUTE_34", 15, 21)
  U.wait(20)
  ok(game.overworld.map.id == "ROUTE_34", "standing on Route 34")
  ok(npcOnMap(8) ~= nil, "SPRITE_MON_BREED_1 stands in the yard")
  ok(npcOnMap(9) ~= nil, "SPRITE_MON_BREED_2 stands in the yard")
  ok(npcOnMap(7) == nil, "the MAN OUTSIDE stays indoors while there is no EGG")
  local breed1 = npcOnMap(8)
  ok(breed1 and breed1.sprite ~= nil, "the yard sprite resolved a mon sheet")
  -- GetMonSprite.BreedMon1 dresses the object in the boarded species' party
  -- menu icon; a species with no def falls back to sprite 1, the player sheet
  ok(breed1 and breed1.sprite.def.id == "SPRITE_MON_029",
     "the MAN's pen wears NIDORAN_F's icon, not the player's sheet")
  ok(npcOnMap(9) and npcOnMap(9).sprite.def.id == "SPRITE_MON_132",
     "the LADY's pen wears DITTO's icon")
  ok(game.data.sprites["SPRITE_MON_132"].monIcon == true,
     "and it is a 2-frame icon, not a 6-frame walker")

  -- ------------------------------- boarding a SECOND mon through the dialogue
  --
  -- DayCareMan/DayCareLady are two independent pens (wBreedMon1/wBreedMon2),
  -- so once the MAN is holding one the LADY must still offer to take another.
  -- DayCareAskDepositPokemon (05:$69EE) is `cp 2 / jr c, .OnlyOneMon`, so the
  -- only thing that ever refuses is being down to a single party member.
  local ScriptRunner = require("src.script.ScriptRunner")
  local PartyMenu = require("src.ui.PartyMenu")

  save.daycare = nil
  DayCare.syncFlags(save)
  save.money = 5000
  save.party = { mon("SPECIES_155", 10), mon("SPECIES_158", 10),
                 mon("SPECIES_152", 10) }
  U.teleport(game, "DAY_CARE", 3, 5)
  U.wait(10)

  local said = {}
  local realShow = Commands.show_text
  Commands.show_text = function(c, textId, subs, extra)
    said[#said + 1] = tostring(textId)
    return realShow(c, textId, subs, extra)
  end
  local function saidMatching(pat)
    for _, s in ipairs(said) do if s:find(pat) then return s end end
  end

  local function talk(command, pick)
    said = {}
    local runner = ScriptRunner.new(game, game.overworld)
    runner:run({ { command } }, { npc = { def = {} } })
    for _ = 1, 900 do
      if not runner:isRunning() then break end
      local top = game.stack:top()
      if getmetatable(top) == PartyMenu and pick then top.index = pick end
      U.tap(game, "a")
      U.wait(2)
      runner:update()
    end
    while getmetatable(game.stack:top()) == PartyMenu do game.stack:pop() end
    return not runner:isRunning()
  end

  ok(talk("g2_daycare_man", 1), "the DAY-CARE MAN's deposit conversation finishes")
  ok(saidMatching("DAY%-CARE\nMAN%. Do you know"),
     "his first greeting is the long IntroEggText")
  ok(saidMatching("What should I"), "he opens the party menu to pick")
  ok(DayCare.mon(save, DayCare.MAN) ~= nil, "the MAN is holding wBreedMon1")
  ok(#save.party == 2, "the boarded mon left the party")
  ok(saidMatching("left with\011the DAY%-CARE MAN"), "he confirms the hand-off")
  ok(game.stringBuffer ==
     require("src.script.Gen2Commands").dayCareName(game, DayCare.mon(save, DayCare.MAN)),
     "wStringBuffer holds the boarded mon's name for {RAM:DC41}")

  -- the whole point: with the MAN full, the LADY still takes a second one
  ok(talk("g2_daycare_lady", 1), "the DAY-CARE LADY's conversation finishes")
  ok(not saidMatching("just one"), "two party members is enough to board again")
  ok(saidMatching("DAY%-CARE\nLADY"), "she introduces herself and offers")
  ok(DayCare.mon(save, DayCare.LADY) ~= nil, "the LADY is holding wBreedMon2")
  ok(DayCare.mon(save, DayCare.MAN) ~= DayCare.mon(save, DayCare.LADY),
     "the two pens hold different mons")
  ok(#save.party == 1, "the second mon left the party too")
  ok(Flags.get(save, DayCare.FLAG_MAN_HAS_MON)
     and Flags.get(save, DayCare.FLAG_LADY_HAS_MON),
     "both pens report full")

  -- talking to a full pen is the withdraw conversation, not a third deposit
  talk("g2_daycare_man", 1)
  ok(saidMatching("Back already") or saidMatching("grown"),
     "a full pen switches the MAN to his grown-report")

  -- .OnlyOneMon: down to a single party member nobody takes another
  DayCare.withdraw(save, DayCare.LADY)
  save.party = { mon("SPECIES_155", 10) }
  talk("g2_daycare_lady", 1)
  ok(saidMatching("just one"), "the last party member can never be boarded")
  ok(DayCare.mon(save, DayCare.LADY) == nil, "and nothing was taken")

  -- the second meeting drops the long spiel (DayCareIntroText's bit 7)
  ok(not saidMatching("Do you know"), "her second greeting is the short intro")

  Commands.show_text = realShow

  -- put the breeding pair back for the rest of the run
  save.daycare = nil
  DayCare.deposit(save, DayCare.MAN, nidoran)
  DayCare.deposit(save, DayCare.LADY, ditto)

  -- ----------------------------------------------------------- compatibility
  ok(select(1, DayCare.pair(game.data, save)) ~= nil, "DITTO pairs with NIDORAN")
  ok(DayCare.compatibility(game.data, save) > 0, "the pair has a nonzero tier")
  ok(DayCare.eggSpecies(game.data, save) == "SPECIES_029",
     "a DITTO pair takes the other parent's base form")

  -- two DITTO never breed (.ditto_and_ditto)
  local saved = DayCare.mon(save, DayCare.MAN)
  DayCare.deposit(save, DayCare.MAN, mon("SPECIES_132", 20))
  ok(DayCare.pair(game.data, save) == nil, "DITTO + DITTO refuses to breed")
  DayCare.deposit(save, DayCare.MAN, saved)

  -- ---------------------------------------------------------- the EGG lands
  math.randomseed(7)
  local made = false
  for _ = 1, 20000 do
    if DayCare.step(game.data, save, 1) then made = true break end
  end
  ok(made, "DayCareStep eventually rolls an EGG")
  local breed = DayCare.store(save, false)
  ok(breed.egg and breed.egg.isEgg, "the EGG is parked for the MAN OUTSIDE")
  ok(breed.egg and breed.egg.species == "SPECIES_029", "the EGG is a NIDORAN")
  ok(Flags.get(save, DayCare.FLAG_HAS_EGG), "an EGG sets flag $05")

  -- ------------------------------- the old man moves out to meet the player
  U.teleport(game, "DAY_CARE", 3, 5)
  U.wait(20)
  ok(npcOnMap(1) == nil, "the MAN has left his post inside the DAY-CARE")
  U.teleport(game, "ROUTE_34", 15, 21)
  U.wait(20)
  ok(npcOnMap(7) ~= nil, "the MAN OUTSIDE is standing at the fence")

  -- ------------------------------------------------------------ the handover
  local ctx = { game = game, save = save, overworld = game.overworld }
  save.party = { mon("SPECIES_155", 5) }
  local answers, texts = { true }, {}
  local realAsk, realShow = Commands.ask, Commands.show_text
  Commands.ask = function(c, text) texts[#texts + 1] = text
    c.lastCheck = table.remove(answers, 1) and true or false end
  Commands.show_text = function(_, text) texts[#texts + 1] = text end

  Commands.g2_daycare_outside(ctx)
  ok(ctx.g2Var == 0, "accepting leaves wScriptVar 0 (he walks back inside)")
  ok(#save.party == 2 and save.party[2].isEgg, "the EGG joins the party")
  ok(save.party[2].eggSteps and save.party[2].eggSteps > 0, "the EGG has a hatch counter")
  ok(DayCare.store(save, false).egg == nil, "the pending EGG is consumed")
  ok(not Flags.get(save, DayCare.FLAG_HAS_EGG), "handing it over clears flag $05")

  -- a full party keeps him there (.PartyFull -> wScriptVar 1)
  DayCare.store(save, true).egg = mon("SPECIES_029", 5)
  DayCare.syncFlags(save)
  save.party = {}
  for i = 1, 6 do save.party[i] = mon("SPECIES_155", 5) end
  answers = { true }
  Commands.g2_daycare_outside(ctx)
  ok(ctx.g2Var == 1, "no room leaves wScriptVar 1 (he stays at the fence)")
  ok(DayCare.store(save, false).egg ~= nil, "the EGG waits for a free slot")

  -- declining throws it away, and he still walks back inside
  save.party = { mon("SPECIES_155", 5) }
  answers = { false }
  Commands.g2_daycare_outside(ctx)
  ok(ctx.g2Var == 0, "declining also leaves wScriptVar 0")
  ok(DayCare.store(save, false).egg == nil, "a declined EGG is discarded")
  ok(not Flags.get(save, DayCare.FLAG_HAS_EGG), "declining clears flag $05")

  Commands.ask, Commands.show_text = realAsk, realShow

  -- --------------------------------------------- withdrawing empties the yard
  DayCare.withdraw(save, DayCare.MAN)
  DayCare.withdraw(save, DayCare.LADY)
  ok(not Flags.get(save, DayCare.FLAG_MAN_HAS_MON), "withdrawing clears flag $06")
  ok(not Flags.get(save, DayCare.FLAG_LADY_HAS_MON), "withdrawing clears flag $07")
  U.teleport(game, "ROUTE_34", 15, 21)
  U.wait(20)
  ok(npcOnMap(8) == nil and npcOnMap(9) == nil, "the yard is bare again")
  ok(objByIndex("ROUTE_34", 8) ~= nil, "the yard object still exists in the map")

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  if fail > 0 then error("gen2 daycare test failed") end
end
