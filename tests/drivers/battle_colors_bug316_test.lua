-- Driver: cycling COLORS mid-battle must not move a sprite (#316).  pokered
-- SlidePlayerAndEnemySilhouettesOnScreen (engine/battle/core.asm:13-15) puts
-- the back pic at `hlcoord 1, 5` so its bottom row sits on the text box, and a
-- palette swap must not lift it off.
--   POKEPORT_DRIVER=tests/drivers/battle_colors_bug316_test.lua \
--     POKEPORT_IDENTITY=bug316 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local PaletteFX = require("src.render.PaletteFX")

  -- Route 1 (5, 5) is open walkable ground; the battle is pushed straight in.
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 5, facing = "down" }
  -- ARTICUNO's back pic has left padding as well as bottom padding.
  local PARTY = { { "BULBASAUR", 12 }, { "ARTICUNO", 40 } }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- No transparent padding on the back pics means no jump to see, so a broken
  -- fix would read as a pass.
  local function padOf(path)
    if not (love.image and love.image.newImageData) then return nil end
    local ok, id = pcall(love.image.newImageData, path)
    if not ok then return nil end
    local w, h = id:getDimensions()
    local bottom = h - 1
    while bottom >= 0 do
      local opaque = false
      for x = 0, w - 1 do
        local _, _, _, a = id:getPixel(x, bottom)
        if a > 0 then opaque = true break end
      end
      if opaque then break end
      bottom = bottom - 1
    end
    local left = 0
    while left < w do
      local opaque = false
      for y = 0, h - 1 do
        local _, _, _, a = id:getPixel(left, y)
        if a > 0 then opaque = true break end
      end
      if opaque then break end
      left = left + 1
    end
    return h - 1 - bottom, left, w, h
  end

  for _, path in ipairs({ "assets/generated/battle/redb.png",
                          "assets/generated/battle/back/bulbasaurb.png",
                          "assets/generated/battle/back/articunob.png" }) do
    local pad, padL, w, h = padOf(path)
    if pad == nil then
      check(path .. " could be measured", false)
    else
      U.log(("  %s is %dx%d, %d transparent bottom rows, %d left columns")
              :format(path, w, h, pad, padL))
      check(path .. " still carries bottom padding to lose", pad > 0)
    end
  end
  check("BattleState.invalidate still exists (PaletteFX.setMode calls it)",
        type(BattleState.invalidate) == "function")
  U.log("  COLORS ladder:", table.concat(PaletteFX.MODES, ", "))

  -- Where drawPicsLayer puts every pic this frame; love.graphics.draw is
  -- shadowed so nothing reaches the screen.  Both call shapes matter:
  -- draw(img, x, y, r, sx, sy) and the faint-clip draw(img, quad, x, y, ...).
  local function picGeometry(battle)
    local out = {}
    local realDraw = love.graphics.draw
    love.graphics.draw = function(_, a, b, c, d, e)
      if type(a) == "number" then
        out[#out + 1] = { x = a, y = b, s = d }
      else
        out[#out + 1] = { x = b, y = c, s = e }
      end
    end
    pcall(battle.drawPicsLayer, battle, 0, 0, 0)
    love.graphics.draw = realDraw
    return out
  end

  local function describe(geo)
    local parts = {}
    for _, g in ipairs(geo) do
      parts[#parts + 1] = ("(%s, %s x%s)"):format(tostring(g.x), tostring(g.y),
                                                  tostring(g.s or 1))
    end
    return table.concat(parts, " ")
  end

  local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
      if a[i].x ~= b[i].x or a[i].y ~= b[i].y or a[i].s ~= b[i].s then
        return false
      end
    end
    return true
  end

  -- The back pic is the only thing drawn at 2x (BattleState.backPlacement's
  -- third return); the enemy front pic is 1x.
  local function backEntry(geo)
    for _, g in ipairs(geo) do
      if g.s == 2 then return g end
    end
    return nil
  end

  -- Ground truth off the art on disk, not off the cache: comparing against an
  -- earlier frame only catches a pad lost DURING the run, and this one is also
  -- lost by any pic loaded after an invalidate().
  local bpad, bpadL, bw, bh = padOf("assets/generated/battle/back/bulbasaurb.png")
  local expX, expY = nil, nil
  if bpad then
    expX, expY = BattleState.backPlacement(bw, bh, bpad, bpadL, 2)
    U.log(("  a %dx%d back pic with %d ground rows belongs at (%d, %d) at 2x")
            :format(bw, bh, bpad, expX, expY))
  end

  local function grounded(label, geo)
    if not expY then return end
    local b = backEntry(geo)
    check(label .. ": the back pic stands on the text box at y = "
          .. tostring(expY) .. " (got " .. tostring(b and b.y) .. ")",
          b ~= nil and b.y == expY and b.x == expX)
  end

  -- ---- get a back pic on screen ------------------------------------------
  game.save.party = {}
  for _, slot in ipairs(PARTY) do
    table.insert(game.save.party, Pokemon.new(game.data, slot[1], slot[2]))
  end
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil)

  local battle = BattleState.newWild(game, "PIDGEY", 6)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)

  -- Red's own back pic is up during the intro, and that is the pic the report
  -- names, so check it first.
  check("Red's back pic is on screen", battle.showPlayerBack == true)
  local introBefore = picGeometry(battle)
  U.log("  intro pics before:", describe(introBefore))
  grounded("before any COLORS change", introBefore)
  U.shot(game, DIR .. "/bug316_1_intro_before.png")
  game:keypressed("2")
  U.wait(4)
  local introAfter = picGeometry(battle)
  U.log("  intro pics after :", describe(introAfter))
  U.log("  COLORS is now", PaletteFX.modeLabel(PaletteFX.mode))
  check("cycling COLORS did not move Red's back pic (#316)",
        same(introBefore, introAfter))
  grounded("after one COLORS change", introAfter)
  U.shot(game, DIR .. "/bug316_2_intro_after.png")

  -- now the mon's own back pic, at the action menu, where a player actually
  -- sits when they press 2
  for _ = 1, 80 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the battle reached its action menu", battle.phase == "menu")
  check("the mon's back pic replaced Red's", battle.showPlayerBack == false)

  local base = picGeometry(battle)
  U.log("  menu pics baseline:", describe(base))
  grounded("the mon's own back pic at the menu", base)
  U.shot(game, DIR .. "/bug316_3_menu_" .. tostring(PaletteFX.mode) .. ".png")

  -- walk the whole COLORS ladder; every mode has to leave the geometry alone
  local moved, ungrounded = {}, {}
  for i = 1, #PaletteFX.MODES do
    game:keypressed("2")
    U.wait(4)
    local geo = picGeometry(battle)
    local label = PaletteFX.modeLabel(PaletteFX.mode)
    if not same(base, geo) then
      moved[#moved + 1] = label
      U.log("  MOVED under " .. label .. ":", describe(geo))
    end
    local b = backEntry(geo)
    if expY and not (b and b.y == expY and b.x == expX) then
      ungrounded[#ungrounded + 1] = label
    end
    if i == 1 then
      U.shot(game, DIR .. "/bug316_4_menu_" .. tostring(PaletteFX.mode) .. ".png")
    end
  end
  check("no COLORS mode moved a pic (walked the whole ladder of "
        .. #PaletteFX.MODES .. ")", #moved == 0)
  check("the back pic is still grounded in every COLORS mode",
        #ungrounded == 0)
  if #ungrounded > 0 then
    U.log("  modes where it floated:", table.concat(ungrounded, ", "))
  end
  if #moved > 0 then
    U.log("  modes that moved something:", table.concat(moved, ", "))
  end
  U.log("  back on", PaletteFX.modeLabel(PaletteFX.mode))

  -- ---- hand off ----------------------------------------------------------
  U.log("At the FIGHT/PKMN/ITEM/RUN menu: press 2 to cycle COLORS and watch the")
  U.log("back sprite's feet.  They stay planted on the top edge of the text box;")
  U.log("#316 hopped the sprite 8 pixels up on the first press.  Switching to")
  U.log("ARTICUNO in slot 2 shows the sideways half of it.")
  U.log("Sprites already on screen keep their baked palette, which is deliberate.")
  U.log("Screenshots: " .. DIR .. "/bug316_*.png")

  while true do
    coroutine.yield()
  end
end
