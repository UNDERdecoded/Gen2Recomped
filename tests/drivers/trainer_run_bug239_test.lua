-- Driver: the trainer-battle run refusal prints its third line (#239).
-- data/generated/text.lua keeps the original's markers:
--   _NoRunningText = "No! There's no\nrunning from a\011trainer battle!"
-- \011 is \v (ContText): down-arrow, wait, then scroll line 3 in; the port
-- hard-coded three \n.  No POKEPORT_SPEED, the typewriter is real-time.
--   POKEPORT_DRIVER=tests/drivers/trainer_run_bug239_test.lua POKEPORT_IDENTITY=bug239 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local TextBox = require("src.render.TextBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- a wild battle shows no refusal at all, which is not the same failure
  -- as a refusal that truncates
  local text = game.data.text and game.data.text._NoRunningText
  check("_NoRunningText is in the generated text", type(text) == "string")
  if type(text) == "string" then
    local pages = TextBox.paginate(text)
    check("the refusal is one page of three lines",
          #pages == 1 and #pages[1] == 3)
    check("line 3 waits for a button (\\v, not \\n)",
          pages.contBefore and pages.contBefore[1]
          and pages.contBefore[1][3] == true)
    check("line 3 really is 'trainer battle!'",
          pages[1][3] and pages[1][3]:find("trainer battle!", 1, true) ~= nil)
  end

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "bryan"

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  -- any class works: the refusal is keyed on kind == "trainer"
  local OPP = "OPP_YOUNGSTER"
  check("trainer class " .. OPP .. " exists in the data",
        game.data.trainers and game.data.trainers[OPP] ~= nil)

  local ok, battle = pcall(BattleState.newTrainer, game, OPP, 1)
  check("trainer battle constructed", ok and battle ~= nil)
  if not ok then
    U.log("could not start", OPP, "->", tostring(battle))
    U.log("pick another class from game.data.trainers and re-run")
  else
    check("battle kind is trainer (wild battles let you run)",
          battle.kind == "trainer")
    game.stack:push(battle)
    U.wait(120) -- let the intro text and the throw settle
  end

  U.log("Choose RUN from the battle command menu.  The box should hold on")
  U.log("'running from a' with a down-arrow until you press a button, then")
  U.log("scroll 'trainer battle!' in (#239 cut the sentence off there).")
  U.log("Control: running from a WILD battle gets the escape roll, no text.")

  while true do
    coroutine.yield()
  end
end
