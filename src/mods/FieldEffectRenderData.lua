-- Read-only, independently negotiated Gen3 field-effect observations.
local Map = require("src.world.Map")
local Source = require("src.mods.RenderSource")
local M = {}
local KINDS = { grass = true, ripple = true, sparkle = true }
local function number(v, lo, hi)
  return type(v) == "number" and v == v and v >= lo and v <= hi
end
local function integer(v, lo, hi)
  return number(v, lo, hi) and v % 1 == 0
end
local function id(v)
  return type(v) == "string" and #v > 0 and #v <= 160
end
local function world(game)
  if type(game) ~= "table" then
    return nil
  end
  local states = type(game.stack) == "table" and game.stack.states or {}
  if type(states) ~= "table" then
    states = {}
  end
  for i = #states, 1, -1 do
    if type(states[i]) == "table" and states[i].isOverworld then
      return states[i]
    end
  end
  local ow = game.overworld
  return type(ow) == "table" and ow.isOverworld and ow or nil
end
-- The native map query is observational apart from its packed-layout cache.
-- Override blockAt on a fresh native view to read one word instead of filling
-- def._blockArray, even when the map has never been drawn before.
local function grassMap(map)
  if getmetatable(map) ~= Map or map.blockCells ~= 1 then
    error("unsupported grass map")
  end
  local view = setmetatable({}, Map)
  for k, v in pairs(map) do
    if type(v) ~= "function" then
      view[k] = v
    end
  end
  view.blockAt = function(_, x, y)
    local d = map.def
    if x < 0 or y < 0 or x >= d.width or y >= d.height then
      return d.borderBlock
    end
    local i = y * d.width + x + 1
    if map.blockPatch[i] ~= nil then
      return map.blockPatch[i]
    end
    if type(d.blocks) == "string" then
      local a, b = d.blocks:byte(i * 2 - 1, i * 2)
      if not b then
        error("incomplete grass layout")
      end
      return (a + b * 256) % 1024
    end
    return d.blocks[i]
  end
  return view
end
local function observe(ctx)
  local ow, game = ctx.world, ctx.game
  if ow.flyAnim then
    error("fly presentation unavailable")
  end
  local constants = game.data and game.data.constants or {}
  local effects, sheets = {}, {}
  local function sheet(kind, d)
    if type(d) ~= "table" or not id(d.image) or d.trueColor ~= true then
      error("effect source unavailable")
    end
    local w, h, n = d.frameWidth or 16, d.frameHeight or 16, d.frames or 1
    if
      not (integer(w, 8, 128) and integer(h, 8, 128) and integer(n, 1, 256) and w * h * n <= 1048576)
      or d.big
      or d.monIcon
    then
      error("unsupported effect geometry")
    end
    local s = { id = "field:" .. kind, path = d.image, width = w, height = h, frames = n }
    local old = sheets[s.id]
    if old and (old.path ~= s.path or old.width ~= w or old.height ~= h or old.frames ~= n) then
      error("ambiguous effect source")
    end
    sheets[s.id] = s
    return s
  end
  local function emit(kind, index, s, frame, x, y, gx, gy, layer, ownerId, clock)
    if
      #effects >= 512
      or not integer(frame, 0, s.frames - 1)
      or not number(x, -16777216, 16777216)
      or not number(y, -16777216, 16777216)
      or not number(gx, -16777216, 16777216)
      or not number(gy, -16777216, 16777216)
      or not number(clock, 0, 2147483647)
    then
      error("invalid effect state")
    end
    effects[#effects + 1] = {
      id = kind .. ":" .. index,
      kind = kind,
      mapId = ctx.map.id,
      layer = layer,
      ownerId = ownerId,
      order = #effects + 1,
      groundX = gx,
      groundY = gy,
      animationClock = clock,
      sheetId = s.id,
      frame = frame,
      flipX = false,
      flipY = false,
      draw = { x = x, y = y, width = s.width, height = s.height },
      source = { x = 0, y = frame * s.height, width = s.width, height = s.height },
      pixelSnap = kind == "grass" and "floorCamera" or "floorRelative",
      terrainOcclusion = kind == "ripple" and "reflectionCover" or "none",
    }
  end
  local function sequence(set, clock, hold, linger)
    if
      not number(clock, 0, 2147483647)
      or type(set.order) ~= "table"
      or #set.order < 1
      or #set.order > 256
    then
      error("invalid effect sequence")
    end
    local t, last = clock, nil
    for _, step in ipairs(set.order) do
      local duration = step.hold or hold
      if not integer(duration, 1, 65535) then
        error("invalid effect hold")
      end
      last = step.frame or 0
      if t < duration then
        return last
      end
      t = t - duration
    end
    if not linger then
      return last
    end
  end
  for _, kind in ipairs({ "ripple", "sparkle" }) do
    local live = ow[kind == "ripple" and "ripples" or "sparkles"] or {}
    if type(live) ~= "table" or #live > 256 then
      error("too many effects")
    end
    if #live > 0 then
      local set = constants[kind == "ripple" and "gen3Ripple" or "gen3Sparkle"]
      local d = set and game.data.sprites and game.data.sprites[set.key]
      if not d then
        error("effect source unavailable")
      end
      -- Source metadata, not rippleSprite()/sparkleSprite(): those lazily
      -- allocate SpriteRenderers and mutate the world.
      local s = sheet(kind, d)
      local bias = (
        d.gen3ObjectEvent == true or (d.source or ""):find("gObjectEventGraphicsInfoPointers", 1, true)
      )
          and 0
        or -4
      for i, e in ipairs(live) do
        local frame = sequence(set, e.clock, kind == "ripple" and 8 or 5, kind == "sparkle")
        if frame ~= nil then
          if not number(e.px, -16777216, 16777216) or not number(e.py, -16777216, 16777216) then
            error("invalid effect position")
          end
          emit(
            kind,
            i,
            s,
            frame,
            e.px - math.floor((s.width - 16) / 2),
            e.py + 4 + bias - (s.height - 16),
            e.px + 8,
            e.py + 16,
            kind == "ripple" and "ground" or "front",
            nil,
            e.clock
          )
        end
      end
    end
  end
  local entities = ow.entities or {}
  if type(entities) ~= "table" or #entities > 256 then
    error("too many actors")
  end
  local record = constants.gen3TallGrass
  if #entities > 0 then
    local map = grassMap(ctx.map)
    local s, seen = nil, {}
    for _, e in ipairs(entities) do
      if not e.hidden and not e.invisible and not e.berryVisualEmpty then
        if e.berryTreeId then
          error("berry presentation unavailable")
        end
        local owner
        if e == ow.player then
          owner = "player"
        elseif e.def and integer(e.def.index, 0, 65535) then
          owner = ("npc:%d:%s:%d:0:0"):format(#ctx.map.id, ctx.map.id, e.def.index)
        else
          error("actor identity unavailable")
        end
        for _, entering in ipairs({ false, true }) do
          local x, y = e.cellX, e.cellY
          if entering then
            x, y = e.targetX, e.targetY
          end
          if x ~= nil then
            if not integer(x, -1048576, 1048576) or not integer(y, -1048576, 1048576) then
              error("invalid actor cell")
            end
            if map:isGrassCell(x, y) then
              if not record then
                error("grass source unavailable")
              end
              s = s
                or sheet("grass", {
                  image = record.image,
                  trueColor = true,
                  frameWidth = record.frameWidth,
                  frameHeight = record.frameHeight,
                  frames = record.frames,
                })
              local frame = s.frames - 1
              if entering then
                local span = tonumber(e.stepFramesCur or e.stepFrames) or 16
                if span > 0 then
                  local t = math.max(0, math.min(1, (tonumber(e.progress) or 0) / span))
                  frame = math.min(s.frames - 1, math.floor(t * s.frames))
                end
              end
              local key = owner .. ":" .. (entering and "entering" or "standing")
              if seen[key] then
                error("ambiguous grass owner")
              end
              seen[key] = true
              if not number(e.px, -16777216, 16777216) or not number(e.py, -16777216, 16777216) then
                error("invalid actor position")
              end
              emit(
                "grass",
                key,
                s,
                frame,
                x * 16,
                y * 16,
                e.px + 8,
                e.py + 16,
                "actorCover",
                owner,
                tonumber(e.progress) or 0
              )
            end
          end
        end
      end
    end
  end
  return effects, sheets
end
local function sample(ctx)
  local ok, rows, sheets = pcall(observe, ctx)
  if not ok then
    return nil, "field effect data unavailable"
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
      return nil, "unsupported field effect version"
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
  function handle:supportsFieldEffects(version, kind)
    return version == 1 and generation == 3 and (kind == nil or KINDS[kind] == true)
  end
  function handle:fieldEffects(version, expected)
    local ctx, err = active(version, expected)
    if not ctx then
      return nil, err
    end
    local rows, why = sample(ctx)
    if not rows then
      return nil, why
    end
    return {
      version = 1,
      generation = 3,
      mapId = expected,
      coordinateBase = 0,
      cellSize = 16,
      coverage = "subset",
      supportedKinds = { "grass", "ripple", "sparkle" },
      effects = rows,
    }
  end
  function handle:fieldEffectSheet(version, expected, sheetId)
    local ctx, err = active(version, expected)
    if not ctx then
      return nil, err
    end
    if type(sheetId) ~= "string" or #sheetId > 32 then
      return nil, "invalid effect sheet id"
    end
    local rows, sheets = sample(ctx)
    if not rows then
      return nil, sheets
    end
    local s = sheets[sheetId]
    if not s then
      return nil, "effect sheet not resident"
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
      return nil, "effect image unavailable"
    end
    local w, h = be32(bytes, 17), be32(bytes, 21)
    if w ~= s.width or h ~= s.height * s.frames then
      return nil, "effect image geometry changed"
    end
    local tail, why = active(version, expected)
    if not tail then
      return nil, why
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
  return M.attach(api, function()
    return loader.game or package.loaded["src.core.Game"]
  end, api.generation, Source.reader(loader))
end
return M
