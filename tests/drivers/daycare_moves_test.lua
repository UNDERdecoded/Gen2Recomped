-- Driver (#184): Magikarp Day Care 13→19 should learn Tackle at 15.
-- Runs the DAYCARE retrieve script (same path as the gentleman NPC),
-- logs the moveset, then screenshots status page 2 (moves + PP).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local SummaryMenu = require("src.ui.SummaryMenu")
  local story2 = require("data.scripts.story2")

  local def = game.data.pokemon.MAGIKARP
  local karp = Pokemon.new(game.data, "MAGIKARP", 13)
  karp.nickname = "FISHY"
  game.save.party = { Pokemon.new(game.data, "RATTATA", 5) }
  game.save.money = 10000
  game.save.player.name = "RED"

  local steps = Growth.expForLevel(def.growthRate, 19)
    - Growth.expForLevel(def.growthRate, 13)
  game.save.daycare = {
    mon = karp, steps = steps, depositLevel = 13,
  }

  local before = {}
  for _, mv in ipairs(karp.moves) do before[#before + 1] = mv.id end
  U.log("before: Lv", karp.level, "moves", table.concat(before, ","))

  U.teleport(game, "DAYCARE", 2, 2, "up")

  -- Resolve dialogue synchronously (parity_daycare style) without stacking
  -- fake TextBoxes over the overworld.
  local realTextBox = package.loaded["src.render.TextBox"]
  package.loaded["src.render.TextBox"] = {
    new = function(_, text, onDone, opts)
      if opts and opts.choice then
        opts.choice(true)
      elseif onDone then
        onDone()
      end
      return { text = text }
    end,
  }
  local realPush = game.stack.push
  game.stack.push = function() end
  local done = false
  story2.DAYCARE.talk.TEXT_DAYCARE_GENTLEMAN(
    game, game.overworld, nil, function() done = true end)
  game.stack.push = realPush
  package.loaded["src.render.TextBox"] = realTextBox

  local mon = game.save.party[#game.save.party]
  local ids = {}
  for _, mv in ipairs(mon.moves or {}) do ids[#ids + 1] = mv.id end
  U.log("after: Lv", mon.level, "moves", table.concat(ids, ","),
        "done=", done, "daycare_cleared=", game.save.daycare == nil)

  local hasTackle = false
  for _, id in ipairs(ids) do if id == "TACKLE" then hasTackle = true end end
  U.log("Magikarp 13→19 learned Tackle:", hasTackle)

  local summary = SummaryMenu.new(game, mon)
  game.stack:push(summary)
  U.wait(4)
  U.shot(game, DIR .. "/daycare_00_summary_p1.png")
  summary.page = 2
  U.wait(2)
  U.shot(game, DIR .. "/daycare_01_moves.png")
  U.log("shots under", DIR)

  if not (mon.species == "MAGIKARP" and mon.level == 19 and hasTackle) then
    error("daycare #184 failed: Lv" .. tostring(mon.level)
      .. " [" .. table.concat(ids, ",") .. "]")
  end
end
