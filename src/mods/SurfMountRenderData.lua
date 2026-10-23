-- Generic read-only surf-mount data for portable render-hook consumers.
require("src.world.Gen4Jump")
local Source = require("src.mods.RenderSource")
local M = {}
local function finite(v)
  return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function integer(v, lo, hi)
  return finite(v) and v % 1 == 0 and v >= lo and v <= hi
end
local function id(v)
  return type(v) == "string" and #v > 0 and #v <= 160
end
local function world(game)
  if type(game) ~= "table" then
    return nil
  end
  local states = type(game.stack) == "table" and game.stack.states
  for i = #(type(states) == "table" and states or {}), 1, -1 do
    if type(states[i]) == "table" and states[i].isOverworld then
      return states[i]
    end
  end
  local ow = game.overworld
  return type(ow) == "table" and ow.isOverworld and ow or nil
end
local function observe(ctx, getTime)
  local ow, p = ctx.world, ctx.world.player
  if
    not p
    or p.hidden
    or p.invisible
    or not p.surfing
    or (ctx.map.def and ctx.map.def.mapType == "UNDERWATER")
  then
    return {}, {}
  end
  if ow.flyAnim then
    return nil, "fly presentation unavailable"
  end
  local class = package.loaded["src.world.Player"]
  if type(class) ~= "table" or getmetatable(p) ~= class then
    return nil, "unsupported rider implementation"
  end
  local copy = {}
  for k, v in pairs(p) do
    copy[k] = v
  end
  setmetatable(copy, class)
  copy.isUnderwater = function()
    return false
  end
  copy.walkPhase = class.walkPhase
  -- Legacy spin/hop pose writes stay on the copy. The new Gen3 surf bob
  -- lives in update(), and this observes exactly the body actor's pose.
  local _, px, py, facing = class.pose(copy)
  if p.fishing and p.fishTiles and p.fishTiles[facing] then
    return {}, {}
  end
  if
    not (
      finite(px)
      and finite(py)
      and finite(p.px)
      and finite(p.py)
      and math.abs(px) <= 16777216
      and math.abs(py) <= 16777216
    )
  then
    return nil, "invalid rider position"
  end
  local direction = ({ down = 0, up = 1, left = 2, right = 2 })[facing]
  if direction == nil then
    return nil, "invalid rider facing"
  end
  local d = ctx.game.data and ctx.game.data.constants and ctx.game.data.constants.gen3SurfBlob
  if not (type(d) == "table" and d.trueColor == true and id(d.image)) then
    return nil, "surf mount source unavailable"
  end
  local w, h, n = d.frameWidth or 32, d.frameHeight or 32, d.frames or 1
  if not (integer(w, 8, 128) and integer(h, 8, 128) and integer(n, 1, 256) and w * h * n <= 1048576) then
    return nil, "unsupported surf mount geometry"
  end
  local frame = direction
  if n >= 6 then
    local seconds = getTime()
    if not finite(seconds) or seconds < 0 or seconds > 2147483647 then
      return nil, "surf mount clock unavailable"
    end
    frame = direction * 2 + math.floor(seconds * 60 / 48) % 2
  end
  if frame >= n then
    frame = 0
  end
  local elevation = p.currentElevation or p.elevation or 0
  if not integer(elevation, 0, 15) then
    return nil, "invalid rider elevation"
  end
  local s = { id = "surf:player", path = d.image, width = w, height = h, frames = n }
  return {
    {
      id = "surf:player",
      kind = "surf",
      state = "riding",
      ownerId = "player",
      mapId = ctx.map.id,
      layer = "actorUnderlay",
      groundX = p.px + 8,
      groundY = p.py + 16,
      elevation = elevation,
      facing = facing,
      riderPose = { x = px, y = py },
      sheetId = s.id,
      frame = frame,
      flipX = facing == "right",
      flipY = false,
      draw = { x = px - math.floor((w - 16) / 2), y = py - 4 - (h - 16) + 8, width = w, height = h },
      source = { x = 0, y = frame * h, width = w, height = h },
      pixelSnap = "floorRelative",
    },
  }, { [s.id] = s }
end
local function sample(ctx, getTime)
  local ok, rows, sheets = pcall(observe, ctx, getTime)
  if not ok then
    return nil, "surf mount data unavailable"
  end
  return rows, sheets
end
local function be32(s, at)
  return ((s:byte(at) * 256 + s:byte(at + 1)) * 256 + s:byte(at + 2)) * 256 + s:byte(at + 3)
end
function M.attach(api, getGame, generation, readSheet, getTime)
  local handle = rawget(api, "renderData") or {}
  api.renderData = handle
  local function active(version, expected)
    if version ~= 1 then
      return nil, "unsupported surf mount data version"
    end
    if generation ~= 3 then
      return nil, "unsupported generation"
    end
    if not id(expected) then
      return nil, "invalid map id"
    end
    local game = getGame()
    local ow = world(game)
    if not (ow and type(ow.map) == "table") then
      return nil, "no overworld"
    end
    if ow.map.id ~= expected then
      return nil, "active map changed"
    end
    return { game = game, world = ow, map = ow.map }
  end
  function handle:supportsSurfMounts(version)
    return version == 1 and generation == 3
  end
  function handle:surfMounts(version, expected)
    local ctx, err = active(version, expected)
    if not ctx then
      return nil, err
    end
    local rows, why = sample(ctx, getTime)
    if not rows then
      return nil, why
    end
    return { version = 1, generation = 3, mapId = expected, coordinateBase = 0, cellSize = 16, mounts = rows }
  end
  function handle:surfMountSheet(version, expected, sheetId)
    local ctx, err = active(version, expected)
    if not ctx then
      return nil, err
    end
    if type(sheetId) ~= "string" or #sheetId == 0 or #sheetId > 167 then
      return nil, "invalid surf mount sheet id"
    end
    local rows, sheets = sample(ctx, getTime)
    if not rows then
      return nil, sheets
    end
    local s = sheets[sheetId]
    if not s then
      return nil, "surf mount sheet not resident"
    end
    local ok, bytes = pcall(readSheet, s.path, 4194304)
    if
      not ok
      or type(bytes) ~= "string"
      or #bytes < 33
      or #bytes > 4194304
      or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n"
      or bytes:sub(13, 16) ~= "IHDR"
      or be32(bytes, 9) ~= 13
    then
      return nil, "surf mount image unavailable"
    end
    local w, h = be32(bytes, 17), be32(bytes, 21)
    if w ~= s.width or h ~= s.height * s.frames then
      return nil, "surf mount image geometry changed"
    end
    local tail, reason = active(version, expected)
    if not tail then
      return nil, reason
    end
    if tail.world ~= ctx.world or tail.map ~= ctx.map then
      return nil, "active world changed"
    end
    return {
      version = 1,
      generation = 3,
      id = s.id,
      format = "png",
      graphicsState = "source",
      width = w,
      height = h,
      frameWidth = s.width,
      frameHeight = s.height,
      frames = s.frames,
      bytes = bytes,
    }
  end
  return api
end
function M.install(api, loader)
  return M.attach(
    api,
    function()
      return loader.game or package.loaded["src.core.Game"]
    end,
    api.generation,
    Source.reader(loader),
    function()
      return love and love.timer and love.timer.getTime and love.timer.getTime()
    end
  )
end
return M
