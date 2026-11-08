-- BLACK AND WHITE'S BATTLE HUD, on the two-screen battle Gen4Battle draws.
--
-- The pictures are the cartridge's (src/import/Gen5BattleUi.lua ->
-- `gen5_battle_ui`); where they go was measured off those pictures, since
-- pokeblack has no symbols for the battle code: the boxes are one 128 x 32
-- cell each, the foe's in the top left and the player's above the message
-- box on the right, the name above the bar, "Lv" and the level at its right,
-- the HP fill in the 48-pixel slot after "HP", the player's numbers in the
-- dark strip under it and the EXP line at its foot.
--
-- Gen4Battle hands over at five places when the cache carries this record:
-- the healthboxes, the bottom screen, the single-screen strip (action and
-- moves) and the two hit tests. The menu indices are Gen4Battle's own -- 1
-- FIGHT, 2 BAG, 3 POKeMON, 4 RUN -- which is also BW's grid: FIGHT! above,
-- BAG / RUN / POKeMON under it.

local H = {}

H.ENEMY = { x = 64, y = 38 }      -- the boxes' cell centres
H.PLAYER = { x = 192, y = 118 }
H.HP_BAR = { x = 56, y = 16, w = 48 }
H.EXP_BAR = { x = 24, y = 24, w = 96 }
H.NAME = { x = 6, y = 0 }
H.LEVEL = { x = 96, y = 6 }
H.HP_TEXT = { x = 104, y = 18 }

-- the touch screen, in its own pixels
H.ACTION_RECTS = {
  [1] = { x = 48, y = 56, w = 160, h = 64 },     -- FIGHT!
  [2] = { x = 0, y = 132, w = 80, h = 60 },      -- BAG
  [3] = { x = 176, y = 132, w = 80, h = 60 },    -- POKeMON
  [4] = { x = 88, y = 148, w = 80, h = 44 },     -- RUN
}
H.MOVE_RECTS = require("src.import.Gen5BattleUi").MOVE_RECTS
H.BACK_RECT = { x = 176, y = 140, w = 80, h = 52 }

local images = {}
local function img(path)
  if type(path) ~= "string" then return nil end
  if images[path] == nil then
    local ok, i = pcall(require("src.render.Assets").image, path)
    images[path] = ok and i or false
    if images[path] then images[path]:setFilter("nearest", "nearest") end
  end
  return images[path] or nil
end

local function rec(battle)
  local data = battle and (battle.data or (battle.game and battle.game.data))
  return data and data.gen5_battle_ui
end

function H.active(battle)
  local r = rec(battle)
  return r ~= nil and r.images ~= nil and r.images.sub_base ~= nil
end

local function picture(battle, name)
  local r = rec(battle)
  local e = r and r.images[name]
  return e and img(e.path), e
end

-- a tile out of the 256 x 16 gauge sheet
local quads = {}
H.picture = function(battle, name) return picture(battle, name) end

local function partTile(battle, t, x, y)
  local sheet, e = picture(battle, "gauge_parts")
  if not sheet then return end
  local key = t
  if not quads[key] then
    quads[key] = love.graphics.newQuad((t % 32) * 8, math.floor(t / 32) * 8, 8, 8, sheet:getDimensions())
  end
  love.graphics.draw(sheet, quads[key], math.floor(x), math.floor(y))
end

local function digits(battle, n, x, y, rightAlign)
  local s = tostring(math.max(0, math.floor(n or 0)))
  local w = #s * 8
  local x0 = rightAlign and (x - w) or x
  for i = 1, #s do partTile(battle, 41 + tonumber(s:sub(i, i)), x0 + (i - 1) * 8, y) end
end

local function gauge(battle, x, y, w, frac, base)
  local px = math.max(0, math.min(w, math.floor(w * frac + 0.5)))
  if frac > 0 and px == 0 then px = 1 end
  for c = 0, math.floor(w / 8) - 1 do
    local fill = math.max(0, math.min(8, px - c * 8))
    partTile(battle, base + fill, x + c * 8, y)
  end
end

local function drawBox(battle, battler, side, slot)
  local g = love.graphics
  -- a double's boxes (slot 2..5): the shorter doubles cells, placed by the
  -- cartridge's gauge table (src/battle/Gen5BattleLayout.lua)
  local doubles = slot ~= nil and slot >= 2
  local mon = battler and battler.mon
  if not mon then return false end
  local name = side == "player" and "healthbox_player" or "healthbox_enemy"
  local box, e = picture(battle, doubles and (name .. "_doubles") or name)
  if not box and doubles then box, e = picture(battle, name) end
  if not box then return false end
  local c = side == "player" and H.PLAYER or H.ENEMY
  if doubles then
    local cx, cy = require("src.battle.Gen5BattleLayout").healthbox(slot, H.ENEMY, H.PLAYER)
    if cx then c = { x = cx, y = cy } end
  end
  local x, y = c.x + (e.originX or -64), c.y + (e.originY or -16)
  -- BATTLE LAYOUT = WIDE: the player's box keeps to the right edge, as
  -- Gen4Battle.healthboxPos moves Platinum's (the foe's stays at the left)
  if side == "player" then
    local okB, GB = pcall(require, "src.battle.Gen4Battle")
    if okB and GB.extra then x = x + (GB.extra(battle) or 0) end
  end
  g.setColor(1, 1, 1, 1)
  g.draw(box, x, y)
  -- the DRAINING value (battler.shownHP, which BattleState walks toward the
  -- real HP after the move's animation, as Gen4Battle's boxes draw it) -- the
  -- mon's own hp jumped the bar to its new length before the hit landed
  local hp = math.max(0, math.floor(tonumber(battler.shownHP) or tonumber(mon.hp) or 0))
  local max = math.max(1, tonumber(mon.stats and mon.stats.hp) or tonumber(mon.maxHp) or 1)
  local frac = hp / max
  local base = (frac > 0.5 and 0) or (frac > 0.2 and 9) or 18
  gauge(battle, x + H.HP_BAR.x, y + H.HP_BAR.y, H.HP_BAR.w, frac, base)
  digits(battle, mon.level, x + H.LEVEL.x, y + H.LEVEL.y)
  -- (the doubles cell has no strip for the numbers and the EXP line)
  if side == "player" and not doubles then
    -- "cur/max", right-aligned to the strip's end; the slash is text
    local Font = require("src.render.Font")
    digits(battle, hp, x + 88, y + H.HP_TEXT.y, true)
    g.setColor(1, 1, 1, 1)
    -- the slash as a line: the font's glyph carries its own background
    g.setColor(0.85, 0.85, 0.85, 1)
    g.line(x + 90.5, y + H.HP_TEXT.y + 7, x + 94.5, y + H.HP_TEXT.y)
    g.setColor(1, 1, 1, 1)
    digits(battle, max, x + 97, y + H.HP_TEXT.y)
    -- BattleState:expFraction: the creeping fill while exp is being paid,
    -- the mon's own progress the rest of the time (the old reader required a
    -- module that does not exist, so the bar sat empty in every battle)
    local okE, frac2 = pcall(function()
      return battle.expFraction and battle:expFraction(mon) or 0
    end)
    gauge(battle, x + H.EXP_BAR.x, y + H.EXP_BAR.y, H.EXP_BAR.w, okE and tonumber(frac2) or 0, 32)
  end
  -- the name, in the system face, above the bar
  local Font = require("src.render.Font")
  local faced = Font.pushFace and Font.pushFace("system")
  -- white letters, dark grey shadow, as the cartridge prints a battler's name
  Font.pushStyle({ text = { 0.97, 0.97, 0.97, 1 }, shadow = { 0.25, 0.25, 0.3, 1 } })
  g.setColor(1, 1, 1, 1)
  local nick = (battler.name or mon.nickname or mon.name or "")
  Font.draw(nick, x + H.NAME.x, y + H.NAME.y)
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  local gender = okP and Pokemon.genderOf and Pokemon.genderOf(battle.data, mon)
  if gender == "male" or gender == "female" then
    g.setColor(1, 1, 1, 1)
    partTile(battle, gender == "male" and 29 or 31, x + H.NAME.x + Font.width(nick) + 2, y + H.NAME.y + 2)
  end
  Font.popStyle()
  if faced then Font.popFace() end
  g.setColor(1, 1, 1, 1)
  return true
end

function H.drawHealthboxes(battle)
  local drew = 0
  -- the effect VM's GAUGE_VANISH (op 51): the capture hides the boxes
  local ball = battle.gen4Ball
  local anim = battle.gen4AnimPlaying and battle.gen4Anim
  if (ball and ball.gen5 and ball.player and ball.player.gaugesHidden)
     or (anim and anim.gen5 and anim.gaugesHidden) then
    return true
  end
  local notEnemy = battle.showEnemyTrainer or battle.enemySendingOut
  local notPlayer = battle.showPlayerBack
  -- A DOUBLE: four boxes, one a slot, far side first (an empty slot -- its
  -- Pokemon fainted and nothing came in -- draws no box and is not missing)
  local okL, L = pcall(require, "src.battle.Gen5BattleLayout")
  if okL and L.rule(battle) == "double" and not battle.gen4Safari then
    for _, p in ipairs({ 3, 1, 0, 2 }) do
      local side = (p % 2 == 1) and "enemy" or "player"
      local hold = (side == "enemy" and notEnemy) or (side == "player" and notPlayer)
      local b = battle:battlerAt(p)
      if not hold and b and b.mon and not b.fainted then drawBox(battle, b, side, p + 2) end
    end
    return true
  end
  if notEnemy or drawBox(battle, battle.enemy, "enemy") then drew = drew + 1 end
  if notPlayer or drawBox(battle, battle.player, "player") then drew = drew + 1 end
  return drew == 2
end

-- -------------------------------------------------------------- the screens

local function moveName(battle, i)
  local chooser = battle.menuBattler and battle:menuBattler()
  local mv = chooser and chooser.curMoves and chooser.curMoves[i]
  if not mv then return nil end
  local def = battle.data.moves and battle.data.moves[mv.id]
  local maxPP = def and (def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)) or 0
  return def and def.name or tostring(mv.id), mv.pp, maxPP,def and def.type
end

local function highlight(rect, alpha)
  local g = love.graphics
  g.setColor(1, 1, 0.5, alpha or 0.35)
  g.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)
  g.setColor(1, 1, 1, 1)
end

function H.drawScreen(battle, over)
  local g = love.graphics
  local Font = require("src.render.Font")
  g.setColor(1, 1, 1, 1)
  if over == "action" then
    local base, action = picture(battle, "sub_base"), picture(battle, "sub_action")
    if base then g.draw(base, 0, 0) end
    if action then g.draw(action, 0, 0) end
    local r = H.ACTION_RECTS[battle.menuIndex or 1]
    if r and battle.gen4CursorActive ~= false then highlight(r) end
    -- the Bug Contest / Safari words are not on BW's art; nothing to swap
    return true
  elseif over == "moves" then
    local moves, back = picture(battle, "sub_moves"), picture(battle, "sub_back")
    if moves then g.draw(moves, 0, 0) end
    if back then g.draw(back, 0, 0) end
    for i, r in ipairs(H.MOVE_RECTS) do
      local name, pp, maxPP,moveType = moveName(battle, i)
      if name then
        local button=moveType and picture(battle,"move_"..moveType.."_"..i)
        if button then g.draw(button,r.x,r.y)end
        g.setColor(1, 1, 1, 1)
        Font.draw(name, math.floor(r.x + (r.w - Font.width(name)) / 2), r.y + 12)
        local s = ("PP %d/%d"):format(pp or 0, maxPP or 0)
        Font.draw(s, math.floor(r.x + (r.w - Font.width(s)) / 2), r.y + 28)
      end
    end
    local r = H.MOVE_RECTS[battle.moveIndex or 1]
    if r then highlight(r) end
    g.setColor(1, 1, 1, 1)
    return true
  end
  return false
end

function H.drawBottomScreen(battle, SecondScreen, over)
  if over ~= "action" and over ~= "moves" then return false end
  local okD
  SecondScreen.draw(battle.game, function() okD = H.drawScreen(battle, over) end)
  SecondScreen.drawFrame(battle.game)
  return okD
end

-- a piece of the touch screen drawn into a strip slot, at one scale for both
-- axes (the hexagons squash into lozenges otherwise), centred in the slot
local function slice(image, r, x, y, w, h)
  if not image then return end
  local q = love.graphics.newQuad(r.x, r.y, r.w, r.h, image:getDimensions())
  local k = math.min(w / r.w, h / r.h)
  love.graphics.draw(image, q, math.floor(x + (w - r.w * k) / 2), math.floor(y + (h - r.h * k) / 2), 0, k, k)
end

local function outline(x, y, w, h)
  local g = love.graphics
  g.setColor(1, 0.85, 0.2, 1)
  g.setLineWidth(2)
  g.rectangle("line", x + 1, y + 1, w - 2, h - 2, 4, 4)
  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
end

-- BW's own label colours: BAG orange, RUN blue, POKeMON green (off the art)
H.LABEL_INK = { [1] = { 1, 1, 1 }, [2] = { 1.0, 0.62, 0.15 },
                [3] = { 0.45, 0.92, 0.25 }, [4] = { 0.35, 0.72, 1.0 } }

function H.drawCompactActions(battle)
  local Gen4Battle = require("src.battle.Gen4Battle")
  local base, action = picture(battle, "sub_base"), picture(battle, "sub_action")
  if not (base and action) then return false end
  local g = love.graphics
  local Font = require("src.render.Font")
  local labels = Gen4Battle.actionLabels(battle)
  for i = 1, 4 do
    local x, y, w, h = Gen4Battle.compactButtonRect(i)
    -- the button stretched to the slot (the label inside it is redrawn as
    -- text, so stretching costs the words nothing)
    -- unlabelled pieces of the art: the pokeball's red band for FIGHT, the
    -- plain grey move button for the other three
    local moves = picture(battle, "sub_moves")
    local src = (i == 1 or not moves) and base or moves
    local inset = (i == 1 or not moves) and { x = 0, y = 4, w = 256, h = 20 }
                  or { x = 2, y = 30, w = 124, h = 50 }
    g.setColor(1, 1, 1, 1)
    local q = love.graphics.newQuad(inset.x, inset.y, inset.w, inset.h, src:getDimensions())
    g.draw(src, q, x, y, 0, w / inset.w, h / inset.h)
    local s = labels[i] or ""
    local ink = H.LABEL_INK[i]
    g.setColor(ink[1], ink[2], ink[3], 1)
    Font.draw(s, math.floor(x + (w - Font.width(s)) / 2), math.floor(y + (h - 12) / 2))
    if (battle.menuIndex or 1) == i then outline(x, y, w, h) end
  end
  g.setColor(1, 1, 1, 1)
  return true
end

function H.drawCompactMoves(battle)
  local Gen4Battle = require("src.battle.Gen4Battle")
  local moves = picture(battle, "sub_moves")
  if not moves then return false end
  local g = love.graphics
  local Font = require("src.render.Font")
  for i = 1, 4 do
    local x, y, w, h = Gen4Battle.compactMoveRect(i)
    g.setColor(1, 1, 1, 1)
    local name, pp, maxPP,moveType = moveName(battle, i)
    if name then
      -- the button stretched to the slot: the strip's rows are wider than
      -- the hexagon's proportions, and the words need the width
      local r = H.MOVE_RECTS[i]
      local button=moveType and picture(battle,"move_"..moveType.."_"..i)
      if button then g.draw(button,x,y,0,w/r.w,h/r.h)
      else
        local q = love.graphics.newQuad(r.x, r.y, r.w, r.h, moves:getDimensions())
        g.draw(moves, q, x, y, 0, w / r.w, h / r.h)
      end
      -- clear of the hexagon's points, which widen with the stretch (about
      -- 12 of the art's 124 columns): on a widened panel the words at x+8
      -- sat on the left point and the PP on the right one
      local inset = 8 + math.max(0, math.floor(12 * (w / r.w - 1)))
      Font.draw(name, x + inset, y + 3)
      local s = ("%d/%d"):format(pp or 0, maxPP or 0)
      Font.draw(s, x + w - inset - Font.width(s), y + 14)
    end
    if (battle.moveIndex or 1) == i then outline(x, y, w, h) end
  end
  g.setColor(1, 1, 1, 1)
  return true
end

-- the bottom screen's own hit test, in its pixels
function H.bottomHit(x, y, over)
  local function inside(r) return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end
  if over == "action" then
    for i = 1, 4 do if inside(H.ACTION_RECTS[i]) then return "action", i end end
  elseif over == "moves" then
    if inside(H.BACK_RECT) then return "cancel" end
    for i = 1, 4 do if inside(H.MOVE_RECTS[i]) then return "move", i end end
  end
  return nil
end

return H
