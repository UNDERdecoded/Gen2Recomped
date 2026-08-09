-- Mania's SHUCKIE: GiveShuckle / ReturnShuckie (SpecialsPointers $4A/$4B)
-- and VAR_PARTYCOUNT (readvar 1).  Both specials used to be warn-once stubs
-- that left wScriptVar at 0, which is the branch ManiaScript reads as "Your
-- POKeMON party is full" -- reported even with five free slots.
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
  require("src.script.Gen2Commands")

  ok(type(Commands.g2_give_shuckle) == "function", "g2_give_shuckle registered")
  ok(type(Commands.g2_return_shuckie) == "function", "g2_return_shuckie registered")

  -- 1. the lowering: ManiaScript's two `special` rows must name the commands,
  --    not fall through to the g2_special stub
  local VM = require("src.script.Gen2ScriptVM")
  local function lower(label)
    local rows = VM.compile(game.data, label)
    local names = {}
    for _, row in ipairs(rows or {}) do names[row[1]] = true end
    return names
  end
  local give = lower("S5D_4F6D")
  ok(give.g2_give_shuckle, "ManiaScript lowers special 74 to g2_give_shuckle")
  ok(not give.g2_special, "ManiaScript has no unhandled special left")
  local back = lower("S5D_4FB1")
  ok(back.g2_return_shuckie, "the return branch lowers special 75")

  -- 2. readvar 1 is wPartyCount, not 0
  local ctx = { game = game, save = game.save }
  game.save.party = { Pokemon.new(game.data, "SPECIES_155", 5),
                      Pokemon.new(game.data, "SPECIES_161", 5) }
  Commands.g2_readvar(ctx, 1)
  ok(ctx.g2Var == 2, ("readvar 1 = party count (got %s)"):format(tostring(ctx.g2Var)))
  for i = 3, 6 do
    game.save.party[i] = Pokemon.new(game.data, "SPECIES_161", 5)
  end
  Commands.g2_readvar(ctx, 1)
  ok(ctx.g2Var == 6, "readvar 1 tracks a full party")

  -- 3. a full party is the only thing that refuses the gift
  Commands.g2_give_shuckle(ctx)
  ok(ctx.g2Var == 0 and ctx.lastCheck == false, "full party -> wScriptVar 0")
  ok(#game.save.party == 6, "refused gift adds nothing")

  -- 4. five slots used is NOT full (the reported bug)
  table.remove(game.save.party)
  Flags.clear(game.save, "FLAG_G2_0084")
  Commands.g2_give_shuckle(ctx)
  ok(ctx.g2Var == 1 and ctx.lastCheck == true, "room in the party -> wScriptVar 1")
  ok(#game.save.party == 6, "SHUCKIE joins the party")
  local shuckie = game.save.party[6]
  ok(shuckie.species == "SPECIES_213", "the gift is SHUCKLE")
  ok(shuckie.level == 15, "SHUCKIE is level 15")
  ok(shuckie.nickname == "SHUCKIE", "SHUCKIE keeps its nickname")
  ok(shuckie.ot == "MANIA", "OT is MANIA")
  ok(shuckie.otId == 0x0206, "OT id is $0206")
  ok(shuckie.traded == true, "a foreign OT marks it traded")
  ok(shuckie.item == "ITEM_173", "SHUCKIE holds a BERRY")
  ok(Flags.get(game.save, "FLAG_G2_0084"),
     "GiveShuckle sets $D968 bit 5 (ManiaScript's checkflag 84)")

  -- 5. ReturnShuckie's five outcomes, driven through the party menu
  local ScriptRunner = require("src.script.ScriptRunner")
  local ow = { map = { id = "MANIAS_HOUSE", def = {} }, npcs = {}, entities = {} }
  local function runReturn(pickIndex)
    local runner = ScriptRunner.new(game, ow)
    local seen
    runner:run({ { "g2_return_shuckie" } }, { npc = { def = {} } })
    for _ = 1, 400 do
      if not runner:isRunning() then break end
      local top = game.stack:top()
      if getmetatable(top) == require("src.ui.PartyMenu") then
        if pickIndex then
          top.index = pickIndex
          U.tap(game, "a")
        else
          U.tap(game, "b")
        end
      end
      U.wait(2)
      runner:update()
      seen = runner.ctx and runner.ctx.g2Var or seen
    end
    while getmetatable(game.stack:top()) == require("src.ui.PartyMenu") do
      game.stack:pop()
    end
    return seen
  end

  ok(runReturn(nil) == 1, "backing out of the pick -> wScriptVar 1 (refused)")
  ok(runReturn(1) == 0, "handing over the wrong mon -> wScriptVar 0")
  ok(#game.save.party == 6, "a wrong pick takes nothing")

  shuckie.happiness = 200
  ok(runReturn(6) == 3, "a happy SHUCKIE stays with you -> wScriptVar 3")
  ok(#game.save.party == 6, "the too-happy SHUCKIE is not removed")

  shuckie.happiness = 70
  ok(runReturn(6) == 2, "SHUCKIE goes home -> wScriptVar 2")
  ok(#game.save.party == 5, "the returned SHUCKIE leaves the party")

  -- 6. .nothingleft: SHUCKIE alone, or the only one still standing
  game.save.party = { shuckie }
  ok(runReturn(1) == 4, "SHUCKIE as the last mon -> wScriptVar 4")
  ok(#game.save.party == 1, "the last mon is not taken")

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
