-- BLACK AND WHITE'S BATTLE FIELD, DRAWN IN 3D (`gen5_battle_scene`, from
-- src/import/Gen5BattleScene.lua): the backdrop model -- a sky cylinder round
-- a field -- and the two platforms, through src/render/Gen4Model.
--
-- THE CAMERA WAS SET BY EYE. pokeblack carries no symbols for the battle
-- camera, so these values were found by rendering the cartridge's own models
-- and moving the camera until the two platforms sat where Gen4Battle stands
-- the Pokemon (its PLATFORM_POS: the foe's centre at (192, 88), the
-- player's at (64, 136)) with the horizon high, as BW's is. They are the
-- port's, not the cartridge's, and are kept together here so they can be
-- replaced in one place when the real ones are found.

local V = {}

V.CAMERA = { distance = 30, pitch = math.rad(-18), fov = math.rad(45), target = { 0, 2, 0 } }
-- A DOUBLE PULLS THE CAMERA BACK.  The doubles homes (Gen5BattleLayout.HOME,
-- the cartridge's own) stand the player's pair either side of the singles
-- spot; through the singles camera the left one's back sprite, drawn about
-- twice size, sat almost wholly off the left edge (a Hydreigon showed only a
-- wing).  BW's doubles camera is further out; its values are not known, so
-- this factor is the port's, set by eye like the camera above (INFERRED).
V.DOUBLE_DISTANCE = 1.35
V.cam = V.CAMERA
function V.cameraFor(battle)
  local okL, L = pcall(require, "src.battle.Gen5BattleLayout")
  if okL and L.rule(battle) == "double" then
    local c = V.CAMERA
    return { distance = c.distance * V.DOUBLE_DISTANCE, pitch = c.pitch, fov = c.fov, target = c.target }
  end
  return V.CAMERA
end
V.ENEMY = { 11, 0.2, -8 }
V.PLAYER = { -6, 0.2, 12 }
V.W, V.H = 256, 192
-- BATTLE LAYOUT = WIDE: the field is drawn as wide as the battle's surface
-- (Gen4Battle.width) with the same vertical view -- the extra width shows
-- more of the field to either side, as Platinum's widened backdrop does --
-- instead of the cartridge's 256 left in the middle of a wider screen
V.curW = V.W
function V.widthFor(battle)
  local okB, B = pcall(require, "src.battle.Gen4Battle")
  local w = okB and B.width and B.width(battle) or V.W
  return (type(w) == "number" and w >= V.W) and w or V.W
end
V.DEFAULT = { bg = "batt_bg01", stage = "batt_stage01" }

local FLIP_Y = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

local function scene(battle)
  local data = battle and (battle.data or (battle.game and battle.game.data))
  return data and data.gen5_battle_scene
end

function V.available(battle)
  local s = scene(battle)
  return s ~= nil and s.models ~= nil
end

-- the season letter for the outdoor sets (spring a .. winter d), by month,
-- the way the cartridge's season follows the calendar month (BW's season is
-- the month mod 4: Jan, May, Sep spring ...)
function V.season(now)
  local m = os.date("*t", now or os.time()).month
  return ({ "a", "b", "c", "d" })[((m - 1) % 4) + 1]
end

-- which models: a battle may name its own (`battle.gen5Scene = { bg, stage }`);
-- otherwise the grass field, in this month's season when it has one
function V.pick(battle)
  local s = scene(battle)
  local want = battle.gen5Scene or {}
  local function seasonal(name)
    if s.models[name] then return name end
    local seasoned = name .. V.season()
    return s.models[seasoned] and seasoned or nil
  end
  local bg = seasonal(want.bg or V.DEFAULT.bg) or V.DEFAULT.bg
  local stage = seasonal(want.stage or V.DEFAULT.stage) or V.DEFAULT.stage
  return bg, stage
end

local cache = {}
local function model(s, name)
  if cache[name] == nil then
    local M = require("src.render.Gen4Model")
    local rec = s.models[name]
    cache[name] = (rec and M.new(rec)) or false
  end
  return cache[name] or nil
end

local target = {}
-- render(battle) -> canvas, or nil when this device cannot draw depth
function V.render(battle)
  local s = scene(battle)
  if not s then return nil end
  local M = require("src.render.Gen4Model")
  local w = V.widthFor(battle)
  if target.colour and target.w ~= w then target.colour, target.depth, target.failed = nil, nil, nil end
  if not target.colour then
    target.colour, target.depth = M.newTarget(w, V.H)
    target.w = w
    if not target.colour then target.failed = true end
  end
  V.curW = w
  -- the camera this battle's rule uses; project / standPoint read the same
  V.cam = V.cameraFor(battle)
  if target.failed then return nil end
  local bgName, stageName = V.pick(battle)
  local bg, stage = model(s, bgName), model(s, stageName)
  if not bg then return nil end
  local g = love.graphics
  -- push("all") / pop() saves and restores the whole render target (and
  -- its depth): handing getCanvas()'s answer back to setCanvas raised
  -- "Canvas expected" when a mod's renderer had bound its own target.
  g.push("all")
  g.setCanvas({ target.colour, depthstencil = target.depth })
  g.clear(0, 0, 0, 1, true, true)
  local c = V.cam or V.CAMERA
  local vp = M.multiply(FLIP_Y, M.multiply(M.perspective(c.fov, V.curW / V.H, 4, 4000),
                                           M.orbit(c.target, c.distance, 0, c.pitch)))
  bg:draw(vp)
  if stage then
    for _, at in ipairs({ V.ENEMY, V.PLAYER }) do
      stage:draw(M.multiply(vp, { 1, 0, 0, at[1], 0, 1, 0, at[2], 0, 0, 1, at[3], 0, 0, 0, 1 }))
    end
  end
  g.pop()
  return target.colour
end

local function viewProjection()
  local M = require("src.render.Gen4Model")
  local c = V.cam or V.CAMERA
  return M.multiply(FLIP_Y, M.multiply(M.perspective(c.fov, V.curW / V.H, 4, 4000),
                                       M.orbit(c.target, c.distance, 0, c.pitch)))
end

-- project({x, y, z}) -> screen x, y: where a point of the field lands, which
-- is where BW stands a Pokemon -- its picture is a billboard at its
-- platform's centre in the scene, not a fixed place on the screen
function V.project(p)
  local m = viewProjection()
  local x, y, z = p[1], p[2], p[3]
  local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
  local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
  local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
  if cw == 0 then return nil end
  return (cx / cw + 1) / 2 * V.curW, (cy / cw + 1) / 2 * V.H
end

-- how much bigger a billboard draws at a side's platform than at the foe's:
-- the cartridge's sprites are polygons in the scene, so the one nearer the
-- camera is drawn larger by exactly the perspective (the foe's is 1)
local function clipW(p)
  local m = viewProjection()
  return m[13] * p[1] + m[14] * p[2] + m[15] * p[3] + m[16]
end
function V.depthScale(side)
  if side ~= "player" then return 1 end
  local we, wp = clipW(V.ENEMY), clipW(V.PLAYER)
  if not (we and wp) or wp == 0 then return 1 end
  return we / wp
end

-- the screen point a side's Pokemon stands on
function V.standPoint(side)
  return V.project(side == "player" and V.PLAYER or V.ENEMY)
end

-- the field, in place of Gen4Battle's backdrop and platforms
function V.draw(battle)
  local okR, canvas = pcall(V.render, battle)
  if not (okR and canvas) then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  return true
end

return V
