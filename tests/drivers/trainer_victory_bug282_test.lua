-- Driver: the beaten trainer scrolls back in and says his own line ON the
-- battle screen, before the prize money (#282).  Order is pokered
-- engine/battle/core.asm:915-949: defeat text, scroll-in, 40 frames,
-- EndBattleText, money.  No POKEPORT_SPEED on this run.
--   POKEPORT_DRIVER=tests/drivers/trainer_victory_bug282_test.lua \
--     POKEPORT_IDENTITY=bug282 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")

  -- pokered data/maps/objects/Route3.asm: object_event 10, 6, ... RIGHT,
  -- OPP_BUG_CATCHER, 4.  The sight line runs east along row 6, so (13,6) is
  -- one cell outside it; party 4 is three bug mons a :L15 CHARMANDER beats.
  local MAP = "ROUTE_3"
  local MAP_LABEL = "Route3"
  local TRAINER = "ROUTE3_YOUNGSTER1"
  local TRAINER_INDEX = 2
  local STAND = { x = 13, y = 6, facing = "left" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- A missing EndBattleText and a fix that never fires look identical on
  -- screen: defeat text straight to money, nothing in between.
  local header = game.data:trainerHeader(MAP_LABEL, TRAINER_INDEX)
  check(TRAINER .. " has a trainer header", header ~= nil)
  local wonKey = header and header.won
  check("the header names an EndBattleText", wonKey ~= nil)
  local wonText = wonKey and game.data.text[wonKey]
  check("that text resolves to a string",
        type(wonText) == "string" and wonText ~= "")
  if type(wonText) == "string" then
    U.log("  " .. tostring(wonKey) .. " reads:", (wonText:gsub("\n", " / ")))
  end

  local mapDef = game.data.maps[MAP]
  local trainerDef
  for _, o in ipairs(mapDef and mapDef.objects or {}) do
    if o.name == TRAINER then trainerDef = o end
  end
  check(TRAINER .. " is still on " .. MAP, trainerDef ~= nil)
  local partyDef = trainerDef
    and game.data.trainers[trainerDef.trainerClass]
    and game.data.trainers[trainerDef.trainerClass].parties[trainerDef.trainerParty]
  check("its party is still loadable", partyDef ~= nil)
  if partyDef then
    local names = {}
    for _, slot in ipairs(partyDef) do
      names[#names + 1] = slot.species .. " :L" .. slot.level
    end
    U.log("  fighting:", trainerDef.trainerClass, "party",
          trainerDef.trainerParty, "--", table.concat(names, ", "))
  end

  -- ---- a mon that will evolve off the back of this fight -----------------
  -- The pacing half of the report: with the loss line inside the battle, the
  -- evolution follows it directly instead of sitting between two overworld
  -- cuts.  Park the mon one exp point short of its evolution level.
  local def = game.data.pokemon.CHARMANDER
  local evoLevel
  for _, evo in ipairs((def and def.evolutions) or {}) do
    if evo.level then evoLevel = evo.level end
  end
  check("CHARMANDER still has a level evolution", evoLevel ~= nil)
  local mon = Pokemon.new(game.data, "CHARMANDER", (evoLevel or 16) - 1)
  mon.exp = Growth.expForLevel(def.growthRate, evoLevel or 16) - 1
  game.save.party = { mon }
  U.log("  party: CHARMANDER :L" .. mon.level, "exp", mon.exp,
        "-- one point short of :L" .. tostring(evoLevel))

  -- ---- walk into the trainer's sight line --------------------------------
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil)

  local function liveBattle()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == BattleState then return s end
    end
    return nil
  end

  local npc
  for _, n in ipairs((ow and ow.npcs) or {}) do
    if n.def and n.def.name == TRAINER then npc = n end
  end
  check("the trainer object loaded on the live map", npc ~= nil)
  if npc and npc.cellY ~= STAND.y then
    -- a map edit moved him: approach from wherever he stands now
    U.log("trainer moved to", npc.cellX, npc.cellY, "-- re-approaching")
    U.teleport(game, MAP, npc.cellX + 3, npc.cellY, "left")
    U.wait(10)
  end

  local battle
  for _ = 1, 12 do
    U.hold(game, "left", 12)
    U.wait(20)
    battle = liveBattle()
    if battle then break end
    -- the pre-battle line ("Hey! You have POKéMON!") holds the overworld
    U.tap(game, "a")
    U.wait(20)
    battle = liveBattle()
    if battle then break end
  end
  check("the trainer battle started", battle ~= nil)
  if not battle then
    U.log("FAIL nothing to show -- walk left along row 6 into the BUG CATCHER")
    while true do coroutine.yield() end
  end

  -- The loss line has to be handed to the battle (engageTrainer sets
  -- battle.endBattleText) instead of left for the overworld to print.
  check("the battle carries the trainer's EndBattleText (#282)",
        type(battle.endBattleText) == "string" and battle.endBattleText ~= "")
  if type(battle.endBattleText) == "string" then
    U.log("  battle.endBattleText =",
          (battle.endBattleText:gsub("\n", " / "):gsub("\f", " <page> ")))
  end

  -- ---- win it ------------------------------------------------------------
  -- Stop the moment the battle is decided, so the whole victory sequence is
  -- still ahead of the player.
  for _ = 1, 900 do
    if battle.result then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the battle was won", battle.result == "win")
  if battle.result ~= "win" then
    U.log("FAIL result was", tostring(battle.result),
          "-- the party may have been too weak; nothing below applies")
  end

  -- the victory sequence is still queued; the loss line has to be one of its
  -- rows, not something the overworld prints later
  local queuedLoss, queuedMoney = false, false
  local firstWord = (battle.endBattleText or ""):match("^%S+") or "\1"
  for _, row in ipairs(battle.queue or {}) do
    if row.text then
      if row.text:find(firstWord, 1, true) then queuedLoss = true end
      if row.text:find("winning", 1, true) then queuedMoney = true end
    end
  end
  check("the trainer's loss line is queued INSIDE the battle", queuedLoss)
  check("the prize money is queued behind it", queuedMoney)

  -- step past the exp / level-up rows so the player's very next A press is
  -- the one that starts the scroll-in
  for _ = 1, 400 do
    local cur = battle.current
    if cur and cur.text and cur.text:find("defeated", 1, true) then break end
    U.tap(game, "a")
    U.wait(4)
  end
  local cur = battle.current
  check("stopped on the defeat line",
        cur ~= nil and cur.text ~= nil
        and cur.text:find("defeated", 1, true) ~= nil)
  if not U.shot(game, DIR .. "/bug282_1_defeat_text.png") then
    U.log("FAIL could not capture the defeat line")
  end

  -- ---- hand off ----------------------------------------------------------
  U.log("The fight is won and the defeat line is up.  Press A once, then")
  U.log("watch without touching anything for a couple of seconds.")
  U.log("His picture should scroll in from the right and settle two tiles")
  U.log("right of the battle slot with no pokeballs beside it, pause, print")
  U.log("his own line, then the prize money, and only then cut back to")
  U.log("Route 3 (#282).  The CHARMANDER evolves straight off the fight.")

  while true do
    coroutine.yield()
  end
end
