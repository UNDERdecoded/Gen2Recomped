-- Driver: level-up learn with a full moveset (#173).
-- Injects the post-KO level-up queue (grew + StatBox + learnMove) inside
-- a live wild battle so MoveLearnMenu runs the same path as a real win.
--
--   SHOT_DIR=/tmp/learn173 POKEPORT_DRIVER=tests/drivers/learn_move_full_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/learn173"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(game.data, "CHARMANDER", 14)
  mon.moves = {
    { id = "SCRATCH", pp = 35 },
    { id = "GROWL", pp = 40 },
    { id = "EMBER", pp = 25 },
    { id = "SMOKESCREEN", pp = 20 },
  }
  table.insert(game.save.party, 1, mon)
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(game, "RATTATA", 2)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function top() return game.stack:top() end
  local function stackIds()
    local parts = {}
    for _, st in ipairs(game.stack.states or {}) do
      local id = st.screenId or (st.pages and "TextBox")
        or (st.onChoose and "ChoiceBox")
        or (st.mon and st.stats and "StatBox")
        or (st.newMoveId and "MoveLearnMenu")
        or (st.phase and ("Battle:" .. tostring(st.phase)))
        or "?"
      if st.selecting ~= nil then
        id = id .. (st.selecting and "[sel]" or "[ask]")
      end
      if st.pages then
        id = id .. string.format("[p%d/%d%s%s]", st.pageIndex or 0, #st.pages,
          st.waiting and "W" or "", st.done and "D" or "")
      end
      parts[#parts + 1] = id
    end
    return table.concat(parts, ">")
  end
  local function isText()
    local t = top()
    return t and t.pages ~= nil
  end
  local function isChoice()
    local t = top()
    return t and t.onChoose ~= nil and t.index ~= nil and not t.mon
  end
  local function learnMenu()
    for _, st in ipairs(game.stack.states or {}) do
      if st.newMoveId and st.mon and st.index then return st end
    end
  end
  local function waitFor(cond, max)
    for i = 1, max or 900 do
      if cond() then return true end
      U.wait(1)
    end
    return false
  end
  local function atPrompt()
    local t = top()
    return t and t.pages and (t.waiting or t.done)
  end
  -- #163: \v conts pause with ▼ mid-page; tap through them so the shot
  -- lands on the full page (or the done+choice tail)
  local function advanceTextPage()
    waitFor(atPrompt, 300)
    for _ = 1, 4 do
      local t = top()
      if not (t and t.pages and t.waiting and t.contAdvance) then break end
      U.tap(game, "a")
      U.wait(2)
      waitFor(atPrompt, 300)
    end
    U.wait(2)
  end

  waitFor(function() return battle.phase == "menu" end, 400)
  local StatBox = BattleState.StatBox
  battle.phase = "messages"
  battle.afterQueue = "menu"
  battle.queue = {}
  battle.current = nil
  battle.nextInsert = 0
  battle:say("CHARMANDER gained\n16 EXP. Points!")
  battle:say("CHARMANDER grew\nto level 15!")
  battle:ui(function() return StatBox.new(game, mon) end)
  mon.level = 15
  -- append (not uiNext): learnMove uses uiNext for mid-fn ordering
  battle:ui(function()
    return battle:buildScreen("MoveLearnMenu", mon, "LEER")
  end)

  for _ = 1, 400 do
    if learnMenu() then break end
    U.tap(game, "a")
    U.wait(2)
  end
  if not learnMenu() then error("MoveLearnMenu never opened: " .. stackIds()) end
  U.log("opened", stackIds())

  -- page 1
  advanceTextPage()
  U.log("shot0", stackIds())
  U.shot(game, DIR .. "/learn_0_trying.png")
  U.tap(game, "a"); U.wait(2)

  -- page 2
  advanceTextPage()
  U.log("shot1", stackIds())
  U.shot(game, DIR .. "/learn_1_cant_more.png")
  U.tap(game, "a"); U.wait(2)

  -- page 3 types out (through its cont), then ChoiceBox overlays
  advanceTextPage()
  if not waitFor(isChoice, 120) then
    error("ChoiceBox never appeared: " .. stackIds())
  end
  U.wait(4) -- let choice settle over Delete prompt
  U.log("shot2", stackIds())
  U.shot(game, DIR .. "/learn_2_delete_yesno.png")
  U.tap(game, "a"); U.wait(4) -- YES

  if not waitFor(function()
    local m = learnMenu()
    return m and m.selecting and top() == m
  end, 120) then
    error("forget list never active: " .. stackIds())
  end
  U.log("shot3", stackIds())
  U.shot(game, DIR .. "/learn_3_which_move.png")
  U.tap(game, "a"); U.wait(4) -- forget SCRATCH

  local n = 4
  for _ = 1, 60 do
    if not isText() then break end
    local t = top()
    if t.done or t.waiting then
      U.log("shot" .. n, stackIds())
      U.shot(game, ("%s/learn_%d_after.png"):format(DIR, n))
      n = n + 1
      U.tap(game, "a")
      U.wait(4)
    else
      U.wait(1)
    end
  end

  U.log("done", DIR, "moves[1]=", mon.moves[1] and mon.moves[1].id, stackIds())
  love.event.quit()
end
