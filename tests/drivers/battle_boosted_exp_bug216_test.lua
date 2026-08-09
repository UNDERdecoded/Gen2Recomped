-- Driver: reproduce #216 - "Boosted EXP text cut off".
--
-- A traded mon's EXP gain prints a 3-line message:
--   "<mon> gained\na boosted\v<N> EXP. Points!"
-- (engine/battle/experience.asm _GainedText/_BoostedText/_ExpPointsText;
-- _BoostedText ends in the CONT code \v = char 11, "a boosted\011" in the
-- extracted data/generated/text.lua).  The in-battle message box only has
-- room for two lines (rows y=112 and y=128), so before the fix the third
-- line was drawn at y=144 -- one row past the 160x144 screen -- and was
-- never seen: a single A press dismissed the whole message and the wild win
-- popped straight back to the overworld, so the boosted amount was invisible.
--
-- Gen1-correct behavior (home/text.asm ContText): the box scrolls a 2-line
-- window, waiting for A/B on the \v (drawing the blinking ▼ arrow), then
-- scrolls "a boosted" up to the top row and types "<N> EXP. Points!" on the
-- bottom row (y=128) -- a VISIBLE row.
--
-- The driver builds a deterministic traded RATTATA, KOs a weak wild PIDGEY
-- with no level-up, then renders the battle into a clean offscreen canvas
-- while capturing Font.drawCode, and asserts the encoded "EXP. Points!"
-- glyph run lands on a visible row (y <= 130), not off-screen at y=144.
-- Fails on the buggy build (amount only ever drawn at y=144); passes once
-- the box scrolls.
--
-- Run:
--   SHOT_DIR=/tmp/bug216 POKEPORT_IDENTITY=bug216 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/battle_boosted_exp_bug216_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local Font = require("src.render.Font")
  local BattleState = require("src.battle.BattleState")

  -- deterministic traded RATTATA :L8; exp pinned to the L8 floor so a single
  -- weak wild KO (~22 boosted exp) stays below the L9 threshold (no level-up
  -- to muddy the message).  DVs pinned to max so numbers are stable per run.
  local rattata = Pokemon.new(game.data, "RATTATA", 8, function(_, b) return b end)
  local def = game.data.pokemon.RATTATA
  rattata.exp = Growth.expForLevel(def.growthRate, 8, game.data.growth_rates)
  rattata.traded = true -- the flag real trades/link set (Commands.lua / Protocol.lua)
  game.save.party = { rattata }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  -- weak enemy: 1 HP so the first move KOs, speed 1 so RATTATA always moves
  -- first, rng pinned low so every accuracy roll hits (Damage.accuracyRoll:
  -- rng(0,255) < acc)
  local battle = BattleState.newWild(game, "PIDGEY", 2)
  battle.onFinish = function() end
  battle.rng = function(a, _) return a end
  battle.enemy.mon.hp = 1
  battle.enemy.mon.stats.speed = 1
  ow:pushBattle(battle)

  -- Render the battle into a clean offscreen 160x144 canvas while recording
  -- every Font.drawCode(code, x, y).  Returns true iff `targetCodes` appear
  -- as a contiguous left-to-right run on a row at y <= maxY.  The off-screen
  -- amount row (y=144) is excluded, so the buggy build never counts as
  -- "shown".  BattleState:draw runs its own canvas pipeline internally and
  -- restores the caller's canvas (see battle_hpbar_gbc_bug229_test.lua).
  local canvas = love.graphics.newCanvas(160, 144)
  local function seqVisible(targetCodes, maxY)
    local rec = {}
    local orig = Font.drawCode
    Font.drawCode = function(code, x, y)
      rec[#rec + 1] = { code, x, y }
      return orig(code, x, y)
    end
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    local okDraw = pcall(function() battle:draw() end)
    love.graphics.setCanvas()
    Font.drawCode = orig
    if not okDraw then return false end
    -- group glyphs by row, sort left-to-right, join codes into a delimited
    -- string, and search each visible row for the target subsequence
    local byY = {}
    for _, g in ipairs(rec) do
      if g[3] <= maxY then
        byY[g[3]] = byY[g[3]] or {}
        table.insert(byY[g[3]], g)
      end
    end
    local tparts = {}
    for _, c in ipairs(targetCodes) do tparts[#tparts + 1] = tostring(c) end
    local needle = "," .. table.concat(tparts, ",") .. ","
    for _, list in pairs(byY) do
      table.sort(list, function(a, b) return a[2] < b[2] end)
      local cs = {}
      for _, g in ipairs(list) do cs[#cs + 1] = tostring(g[1]) end
      if ("," .. table.concat(cs, ",") .. ","):find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local amountCodes = Font.encode("EXP. Points!")

  -- mash through the intro to the FIGHT menu, then FIGHT -> move slot 1
  -- (TACKLE) -> KO (mirrors battle_levelup_hpbar_bug224_test.lua)
  for _ = 1, 300 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(3)
  end
  if battle.phase ~= "menu" then error("bug216: never reached the FIGHT menu") end
  U.tap(game, "a") -- FIGHT
  for _ = 1, 60 do
    if battle.phase == "moveSelect" then break end
    U.wait(1)
  end
  if battle.phase ~= "moveSelect" then error("bug216: never reached move select") end
  U.tap(game, "a") -- TACKLE -> KO

  -- Phase A: advance to the boosted-EXP message (contains both "boosted"
  -- and "EXP. Points!").  Break the frame it becomes current, before any A
  -- press could scroll past it.
  local function isBoosted()
    local c = battle.current
    return c and c.text and c.text:find("EXP. Points!", 1, true)
             and c.text:find("boosted", 1, true)
  end
  local reached = false
  for _ = 1, 900 do
    if isBoosted() then reached = true break end
    if game.stack:top() ~= battle then break end
    U.tap(game, "a")
    U.wait(2)
  end
  if not reached then
    error("bug216: never reached the boosted-EXP message (battle ended early)")
  end
  U.log("boosted message: " ..
        (tostring(battle.current.text):gsub("[\n\v]", "|")))

  -- let the first two lines type out, then capture the cut-off
  -- "gained / a boosted" box (both builds show this; the buggy build has no
  -- visible third row)
  U.wait(40)
  U.shot(game, DIR .. "/bug216_boosted.png")

  -- Phase B: the amount must become visible on a real row.  Each iteration
  -- renders offscreen and checks; then taps A -- which scrolls the CONT
  -- window on the fixed build, and (once fully typed) dismisses the message
  -- on the buggy build.
  local shown = false
  for _ = 1, 120 do
    if seqVisible(amountCodes, 130) then shown = true break end
    if game.stack:top() ~= battle then break end
    U.tap(game, "a")
    U.wait(4)
  end

  if not shown then
    error("bug216: 'EXP. Points!' amount never shown on a visible row " ..
          "(drawn off-screen at y=144); the box did not scroll to the amount")
  end

  U.shot(game, DIR .. "/bug216_amount.png")

  -- no level-up muddied the message
  if battle.player.mon.level ~= 8 then
    error("bug216: expected level 8, got " .. tostring(battle.player.mon.level))
  end

  U.log("bug216 OK: boosted EXP amount shown on a visible row, level still 8")
  U.wait(4)
end
