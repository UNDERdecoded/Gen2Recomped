-- Additive Gen3 actor observations. Resolvers stay private in closures;
-- snapshots neither call live pose methods nor load graphics or a world.
-- Native pose rules lazily require this pure helper for hops. Resolve it
-- before mod execution so observations cannot be attributed as private imports.
require("src.world.Gen4Jump")
local Assets = require("src.render.Assets")
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
  local states = game and game.stack and game.stack.states
  for i = #(type(states) == "table" and states or {}), 1, -1 do
    if type(states[i]) == "table" and states[i].isOverworld then
      return states[i]
    end
  end
  local ow = game and game.overworld
  return type(ow) == "table" and ow.isOverworld and ow or nil
end
local function sheet(sprite)
  local d = type(sprite) == "table" and sprite.def
  if not (type(d) == "table" and id(d.id) and d.trueColor == true and id(d.image)) then
    return nil, "actor sheet unavailable"
  end
  -- Version 1 observes the true-color Gen3 single-column sheets, including
  -- run/field-move variants. It does not reinterpret GB recolors or big dolls.
  if sprite.big or sprite.mirrorHalf or d.monIcon then
    return nil, "unsupported actor geometry"
  end
  local w, h = sprite.tileW, sprite.tileH
  local n = math.max(d.frames or 1, d.poseFrames or 1)
  if not (integer(w, 8, 128) and integer(h, 8, 128) and integer(n, 1, 256) and w * h * n <= 1048576) then
    return nil, "unsupported actor geometry"
  end
  return { id = "sprite:" .. d.id, path = d.image, width = w, height = h, frames = n }
end
local function observe(ctx)
  local ow = ctx.world
  if ow.flyAnim then
    return nil, "fly presentation unavailable"
  end
  local entities, ghosts = ow.entities or {}, ow.ghosts or {}
  if #entities + #ghosts > 256 then
    return nil, "too many actors"
  end
  local out, sheets, seen = {}, {}, {}
  local function add(e, kind, mapId, ox, oy)
    if type(e) ~= "table" then
      return nil, "actor unavailable"
    end
    if e.hidden or e.invisible or e.berryVisualEmpty then
      return true
    end
    local class = package.loaded[kind == "player" and "src.world.Player" or "src.world.NPC"]
    if type(class) ~= "table" or getmetatable(e) ~= class then
      return nil, "unsupported actor implementation"
    end
    -- Player:pose has legacy draw-side timer writes. Invoke the engine's
    -- own rules on an observational copy, never on the live actor. Nested
    -- records used by these Gen3 rules (stair offsets, sprites) are read only.
    local copy = {}
    for k, v in pairs(e) do
      copy[k] = v
    end
    setmetatable(copy, class)
    copy.isUnderwater = function()
      return ctx.map.def and ctx.map.def.mapType == "UNDERWATER"
    end
    copy.walkPhase = class.walkPhase
    local ok, sprite, px, py, facing, phase, step = pcall(class.pose, copy)
    if not ok then
      return nil, "actor pose unavailable"
    end
    local s, why = sheet(sprite)
    if not s then
      return nil, why
    end
    local native = package.loaded["src.render.SpriteRenderer"]
    if not native then
      return nil, "actor pose unavailable"
    end
    local frame, flip
    if kind == "player" and e.fieldMove and (sprite.def.poseFrames or 1) > 1 then
      frame = math.max(0, math.min(s.frames - 1, math.floor(e.fieldMovePose or 0)))
      flip = false
    elseif kind == "npc" and e.fixedFrame ~= nil then
      frame, flip = e.fixedFrame, false
    elseif (sprite.def.frames or 1) <= 1 then
      frame, flip = 0, false
    else
      frame, flip = native.poseFrame(sprite, facing, phase, step)
    end
    if not integer(frame, 0, s.frames - 1) or not sprite.frames[frame] then
      frame = 0
    end
    if not sprite.frames[frame] then
      return nil, "actor frame unavailable"
    end
    if
      not (
        finite(px)
        and finite(py)
        and finite(e.px)
        and finite(e.py)
        and math.abs(px) <= 16777216
        and math.abs(py) <= 16777216
      )
    then
      return nil, "invalid actor position"
    end
    if kind == "player" and e.fishing and e.fishTiles and e.fishTiles[facing] then
      return nil, "multipart fishing pose unavailable"
    end
    local localId = e.def and e.def.index
    if kind == "npc" and not integer(localId, 0, 65535) then
      return nil, "actor identity unavailable"
    end
    local key = kind == "player" and "player" or ("npc:%d:%s:%d:%d:%d"):format(#mapId, mapId, localId, ox, oy)
    if seen[key] then
      return seen[key] == e and true or nil, "ambiguous actor identity"
    end
    seen[key] = e
    local old = sheets[s.id]
    if
      old and (old.path ~= s.path or old.width ~= s.width or old.height ~= s.height or old.frames ~= s.frames)
    then
      return nil, "ambiguous actor sheet"
    end
    sheets[s.id] = s
    local bias = sprite.cellYBias
    if not finite(bias) then
      return nil, "actor anchor unavailable"
    end
    local elevation = e.currentElevation or e.elevation or (e.def and e.def.elevation) or 0
    if not integer(elevation, 0, 15) then
      return nil, "actor elevation unavailable"
    end
    if #out >= 256 then
      return nil, "too many actors"
    end
    local dx = math.floor(px) + ox - (sprite.offsetX or 0)
    local dy = math.floor(py) + oy + bias - (sprite.offsetY or 0)
    local clock = e.animClock or 0
    if
      not (
        finite(dx)
        and finite(dy)
        and finite(clock)
        and (facing == "down" or facing == "up" or facing == "left" or facing == "right")
      )
    then
      return nil, "actor pose unavailable"
    end
    out[#out + 1] = {
      id = key,
      kind = kind,
      mapId = mapId,
      localId = kind == "npc" and localId or nil,
      x = e.px + ox,
      y = e.py + oy,
      groundX = e.px + ox + 8,
      groundY = e.py + oy + 16,
      elevation = elevation,
      facing = facing,
      animationClock = clock,
      moving = e.moving == true,
      surfing = e.surfing == true,
      spinning = e.spinning == true,
      sheetId = s.id,
      frame = frame,
      flipX = flip == true,
      draw = { x = dx, y = dy, width = s.width, height = s.height },
      source = { x = 0, y = frame * s.height, width = s.width, height = s.height },
    }
    return true
  end
  if ow.player then
    local ok, err = add(ow.player, "player", ctx.map.id, 0, 0)
    if not ok then
      return nil, err
    end
  end
  for _, e in ipairs(entities) do
    if e ~= ow.player then
      local ok, err = add(e, "npc", ctx.map.id, 0, 0)
      if not ok then
        return nil, err
      end
    end
  end
  for _, g in ipairs(ghosts) do
    local map = g.nb and g.nb.map
    if
      not (map and id(map.id) and integer(g.ox, -16777216, 16777216) and integer(g.oy, -16777216, 16777216))
    then
      return nil, "actor placement unavailable"
    end
    local ok, err = add(g.npc, "npc", map.id, g.ox, g.oy)
    if not ok then
      return nil, err
    end
  end
  table.sort(out, function(a, b)
    if a.groundY ~= b.groundY then
      return a.groundY < b.groundY
    end
    if a.groundX ~= b.groundX then
      return a.groundX < b.groundX
    end
    return a.id < b.id
  end)
  return out, sheets
end
local function sample(ctx)
  local ok, rows, sheets = pcall(observe, ctx)
  if not ok then
    return nil, "actor data unavailable"
  end
  return rows, sheets
end
local function be32(s, at)
  return ((s:byte(at) * 256 + s:byte(at + 1)) * 256 + s:byte(at + 2)) * 256 + s:byte(at + 3)
end
function M.attach(api, getGame, generation, readSheet)
  local handle = rawget(api, "renderData") or {}
  api.renderData = handle
  local function active(version, expected)
    if version ~= 1 then
      return nil, "unsupported actor data version"
    end
    if generation ~= 3 then
      return nil, "unsupported generation"
    end
    if not id(expected) then
      return nil, "invalid map id"
    end
    local ow = world(getGame())
    if not (ow and ow.map) then
      return nil, "no overworld"
    end
    if ow.map.id ~= expected then
      return nil, "active map changed"
    end
    return { world = ow, map = ow.map }
  end
  function handle:supportsActors(version)
    return version == 1 and generation == 3
  end
  function handle:actors(version, expected)
    local ctx, err = active(version, expected)
    if not ctx then
      return nil, err
    end
    local rows, why = sample(ctx)
    if not rows then
      return nil, why
    end
    return { version = 1, generation = 3, mapId = expected, coordinateBase = 0, cellSize = 16, actors = rows }
  end
  function handle:actorSheet(version, expected, sheetId)
    local ctx, err = active(version, expected)
    if not ctx then
      return nil, err
    end
    if type(sheetId) ~= "string" or #sheetId == 0 or #sheetId > 167 then
      return nil, "invalid actor sheet id"
    end
    local rows, sheets = sample(ctx)
    if not rows then
      return nil, sheets
    end
    local s = sheets[sheetId]
    if not s then
      return nil, "actor sheet not resident"
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
      return nil, "actor image unavailable"
    end
    local w, h = be32(bytes, 17), be32(bytes, 21)
    if w ~= s.width or h ~= s.height * s.frames then
      return nil, "actor image geometry changed"
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
-- Called after the base API (and any terrain/API-3 extension) is built.
function M.install(api, loader)
  return M.attach(
    api,
    function()
      return loader.game or package.loaded["src.core.Game"]
    end,
    api.generation,
    function(path, limit)
      -- Resolve exactly the asset used by native sprites, including overrides.
      -- The caller supplies only a resident opaque sheet ID, never a path.
      if
        type(path) ~= "string"
        or path:sub(1, 1) == "/"
        or path:find("\\", 1, true)
        or path:find(":", 1, true)
        or path:find("%z")
      then
        return nil
      end
      for part in path:gmatch("[^/]+") do
        if part == ".." then
          return nil
        end
      end
      local resolved = Assets.resolve(path)
      local fs = loader.fs
      local modern = fs and type(fs.openFile) == "function"
      if not (fs and (modern or fs.newFile)) then
        return nil
      end
      local f
      if modern then
        -- Native generated assets may be redirected to a version cache.
        -- Existing runtimes shim newFile, but not LÖVE 12's replacement.
        local cache = package.loaded["src.import.CacheFs"]
        if love and fs == love.filesystem and cache and cache._redirect then
          resolved = cache._redirect(resolved)
        end
        f = fs.openFile(resolved, "r")
      else
        f = fs.newFile(resolved)
      end
      if not f then
        return nil
      end
      local ok, bytes = pcall(function()
        if not modern and not f:open("r") then
          return nil
        end
        local size = f:getSize()
        if type(size) ~= "number" or size < 33 or size > limit then
          return nil
        end
        return f:read(limit + 1)
      end)
      pcall(f.close, f)
      return ok and bytes or nil
    end
  )
end

return M
