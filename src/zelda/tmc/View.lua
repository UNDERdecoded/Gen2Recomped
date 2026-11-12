-- Round 14 (a port feature, not cartridge behaviour): the zoom and the view
-- past the room's edges.
--
-- * Zoom: the Pokemon games' controls (mouse wheel, R3 in, L3 out, L3+R3
--   back to the default).  The default step (1) is the cartridge's own
--   picture, drawn into the 240x160 canvas exactly as before.  Any other
--   step draws the world at the window's resolution through the runtime's
--   drawWindow hook (the canvas then carries only the HUD, text and fades,
--   at the normal scale); without the hook it is drawn into the canvas.
--   The step is kept in the runtime's per-game options (Host:gameOption).
-- * Past the room: zoomed out, or while the seamless camera (Seamless.lua)
--   is still easing into a new room, the rooms around the current one are
--   drawn from the player's ROM at their map positions (RoomHeader map_x /
--   map_y, the coordinates border warps keep): on the overworld every room
--   of the overworld areas (area flag $80), and in a dungeon the rooms of
--   Link's floor (gDungeonMaps).  Elsewhere (houses, caves) only the room.
--   Neighbours draw their BG layers; their entities are not loaded.
local bit = require("bit")
local Room = require("src.zelda.tmc.Room")

local V = {}
local W, H = 240, 160

V.STEPS = { 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 0.09375, 0.0625 }
V.DEFAULT = 3

-- ------------------------------------------------------------- zoom state
-- kept with the runtime's per-game options (Host:gameOption, options.zelda
-- .game.minishcap.zoom)
local function host(game) return game and game.opts and game.opts.host end

function V.index(game)
  if game._zoomIndex then return game._zoomIndex end
  local h = host(game)
  local i = V.DEFAULT
  if h and h.gameOption then
    local ok, v = pcall(h.gameOption, h, "zoom")
    if ok and tonumber(v) then i = tonumber(v) end
  end
  if not V.STEPS[i] then i = V.DEFAULT end
  game._zoomIndex = i
  return i
end

function V.factor(game) return V.STEPS[V.index(game)] or 1 end

local function persist(game)
  local h = host(game)
  if h and h.gameOption then pcall(h.gameOption, h, "zoom", game._zoomIndex) end
end

-- dir > 0: zoom in (a bigger picture), < 0: out
function V.step(game, dir)
  local i = V.index(game) + (dir > 0 and -1 or 1)
  game._zoomIndex = math.max(1, math.min(#V.STEPS, i))
  persist(game)
end

function V.reset(game)
  game._zoomIndex = V.DEFAULT
  persist(game)
end

-- the pad: R3 "zoomin", L3 "zoomout" (Input's HotActions defaults, the
-- Pokemon games' bindings); both together reset
function V.input(game)
  local inp = game.opts and game.opts.input
  if not (inp and inp.wasPressed) then return end
  local zin, zout = inp.wasPressed("zoomin"), inp.wasPressed("zoomout")
  if not (zin or zout) then return end
  if inp.isDown and inp.isDown("zoomin") and inp.isDown("zoomout") then return V.reset(game) end
  V.step(game, zin and 1 or -1)
end

-- ---------------------------------------------------------- neighbours
local cache, cacheOrder = {}, {}
local function roomAt(assets, area, room)
  local k = area * 256 + room
  local r = cache[k]
  if r == nil then
    local ok, rr = pcall(Room.load, assets, area, room)
    r = ok and rr or false
    cache[k] = r
    cacheOrder[#cacheOrder + 1] = k
    if #cacheOrder > 48 then local old = table.remove(cacheOrder, 1); cache[old] = nil end
  end
  return r or nil
end
V.roomAt = roomAt
function V.put(room) -- (Seamless: the room Link just left)
  if room and room.area then
    local k = room.area * 256 + room.room
    if cache[k] == nil then cacheOrder[#cacheOrder + 1] = k end
    cache[k] = room
  end
end
function V.clearCache() cache, cacheOrder = {}, {} end
function V.cached(area, room) return cache[area * 256 + room] end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
V.overlaps = overlaps

-- the floor list (gDungeonMaps) holding area:room, if any
local function floorOf(assets, area, room)
  local dm = assets.manifest.dungeonMaps
  for _, floors in pairs(dm or {}) do
    for _, lays in pairs(floors) do
      for _, l in ipairs(lays) do
        if l[1] == area and l[2] == room then return lays end
      end
    end
  end
  return nil
end
V.floorOf = floorOf

function V.isOverworld(assets, area)
  local ai = assets:area(area)
  return ai ~= nil and bit.band(ai.flags or 0, 0x80) ~= 0
end

-- rooms {area, room, x, y, w, h} around the current room, nearest first
function V.candidates(f)
  local r = f.room
  local A = f.assets
  local key = r.area * 256 + r.room
  if f._viewCand and f._viewCand.key == key and f._viewCand.rx == r.x then return f._viewCand.list end
  local list = {}
  local function add(area, id, hdr)
    if area == r.area and id == r.room then return end
    if not hdr or not hdr.file or (hdr.w or 0) <= 0 then return end
    list[#list + 1] = { area = area, room = id, x = hdr.x, y = hdr.y, w = hdr.w, h = hdr.h }
  end
  if V.isOverworld(A, r.area) then
    for a = 0, 0x3F do
      local ai = A:area(a)
      if ai and ai.rooms and bit.band(ai.flags or 0, 0x80) ~= 0 then
        for id, hdr in pairs(ai.rooms) do
          -- the festival town (area $15) stands in for Hyrule Town's room
          -- 0 only while Link is in it (Field:enterRoom); the town is left
          -- out then
          if a == 0x02 and id == 0 and r.area ~= 0x15 and (f.save and f.save.progress or 2) == 1 then
            -- round 15: while the festival runs (progress 1) the town
            -- room is the festival town, set at town map_x + $130
            -- (sub_unk3_HyruleTown_0, Field:enterRoom)
            local fa = A:area(0x15)
            local fh = fa and fa.rooms and fa.rooms[0]
            if fh and fh.file then
              list[#list + 1] = { area = 0x15, room = 0, x = hdr.x + 0x130, y = hdr.y, w = fh.w, h = fh.h }
            end
          elseif a ~= 0x15 and not (a == 0x02 and id == 0 and r.area == 0x15) then add(a, id, hdr) end
        end
      end
    end
  else
    for _, l in ipairs(floorOf(A, r.area, r.room) or {}) do
      local ai = A:area(l[1])
      add(l[1], l[2], ai and ai.rooms and ai.rooms[l[2]])
    end
  end
  -- nearest first, then drop rooms that overlap the current room or one
  -- already kept (Cloud Tops' stacked rooms and the like)
  local cx, cy = r.x + r.width / 2, r.y + r.height / 2
  for _, c in ipairs(list) do c.d = math.abs(c.x + c.w / 2 - cx) + math.abs(c.y + c.h / 2 - cy) end
  table.sort(list, function(a, b) return a.d < b.d end)
  local kept = { { x = r.x, y = r.y, w = r.width, h = r.height } }
  local out = {}
  for _, c in ipairs(list) do
    local clash = false
    for _, k in ipairs(kept) do if overlaps(c, k) then clash = true break end end
    if not clash then kept[#kept + 1] = c; out[#out + 1] = c end
  end
  f._viewCand = { key = key, rx = r.x, list = out }
  return out
end

-- preload the rooms a view rect (room coordinates) touches, `n` at most
function V.preload(f, vx, vy, vw, vh, n)
  local r = f.room
  local view = { x = r.x + vx, y = r.y + vy, w = vw, h = vh }
  local loaded = 0
  for _, c in ipairs(V.candidates(f)) do
    if overlaps(c, view) and V.cached(c.area, c.room) == nil then
      roomAt(f.assets, c.area, c.room)
      loaded = loaded + 1
      if loaded >= (n or 99) then return end
    end
  end
end

-- ------------------------------------------------- tileset managers
-- A room with a tileset manager (Hyrule Town, Minish Village, ...) swaps
-- graphics by where the camera is, so one picture of the whole room would
-- show the swapped-out tiles.  Zoomed out, such a room is drawn in 240x160
-- windows (aligned to the room), each with the swap a camera there would
-- load (Field.swapFor), as round 2's swapmap stitching did.
local variants, nVariants = {}, 0
local function variant(assets, base, spec)
  local k = (base.area * 256 + base.room) .. "|" .. spec.key
  local v = variants[k]
  if v == nil then
    local ok, r = pcall(Room.load, assets, base.area, base.room)
    if ok and r then
      if not pcall(r.applySwap, r, spec) then r = false end
    else r = false end
    if nVariants > 32 then variants, nVariants = {}, 0 end
    variants[k], nVariants = r, nVariants + 1
    v = r
  end
  return v or nil
end

function V.drawLayer(f, room, name, cx, cy, vw, vh)
  local defs = f.assets.manifest.tileSwaps
  if not (defs and defs[room.area * 256 + room.room]) then return room:drawLayer(name, cx, cy) end
  local Field = require("src.zelda.tmc.Field")
  local g = love.graphics
  local gx0, gx1 = math.max(0, math.floor(cx / W)), math.floor(math.min(room.width - 1, cx + vw) / W)
  local gy0, gy1 = math.max(0, math.floor(cy / H)), math.floor(math.min(room.height - 1, cy + vh) / H)
  for gy = gy0, gy1 do
    for gx = gx0, gx1 do
      local camX = math.max(0, math.min(gx * W, room.width - W))
      local camY = math.max(0, math.min(gy * H, room.height - H))
      local spec = Field.swapFor(f.assets, room, camX, camY, {})
      local v = spec and variant(f.assets, room, spec) or room
      local ax, ay = g.transformPoint(gx * W - cx, gy * H - cy)
      local bx, by = g.transformPoint((gx + 1) * W - cx, (gy + 1) * H - cy)
      g.push("all")
      g.intersectScissor(math.floor(ax), math.floor(ay), math.max(0, math.ceil(bx - ax)), math.max(0, math.ceil(by - ay)))
      v:drawLayer(name, cx, cy)
      g.pop()
    end
  end
end

-- ---------------------------------------------------------- drawing
-- Is the picture something other than the cartridge's room view?
function V.active(f)
  return V.factor(f.game) ~= 1 or f.camFree ~= nil
end

-- the view's top-left in room coordinates and its size, for zoom z
function V.viewRect(f, z)
  local cx, cy
  if z == 1 then
    cx, cy = f.camX + W / 2, f.camY + H / 2
  else
    local t = f.cameraTarget or f.pan or f.player
    cx, cy = t.x, t.y - 8
    local r = f.room
    if z > 1 then
      -- zoomed in: inside the room, like the normal camera
      local hw, hh = W / 2 / z, H / 2 / z
      if r.width > 2 * hw then cx = math.max(hw, math.min(r.width - hw, cx)) else cx = r.width / 2 end
      if r.height > 2 * hh then cy = math.max(hh, math.min(r.height - hh, cy)) else cy = r.height / 2 end
    elseif #V.candidates(f) == 0 then
      -- nothing around (a house, a cave): the room in the middle
      cx, cy = r.width / 2, r.height / 2
    end
  end
  local vw, vh = W / z, H / z
  return cx - vw / 2, cy - vh / 2, vw, vh
end

local function backdropRect(room, x, y)
  local bd = room:backdrop()
  love.graphics.setColor(bd[1], bd[2], bd[3], 1)
  love.graphics.rectangle("fill", x, y, room.width, room.height)
  love.graphics.setColor(1, 1, 1, 1)
end

-- draw the world (worldFn = the field's own room picture) for zoom z with
-- the output origin (ox, oy) and `scale` output pixels per canvas pixel
function V.draw(f, z, ox, oy, scale, worldFn)
  local g = love.graphics
  local r = f.room
  local vx, vy, vw, vh = V.viewRect(f, z)
  g.push("all")
  g.setScissor(ox, oy, W * scale, H * scale)
  g.translate(ox, oy)
  g.scale(scale * z, scale * z)
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, vw, vh)
  g.setColor(1, 1, 1, 1)
  local view = { x = r.x + vx, y = r.y + vy, w = vw, h = vh }
  local drawn = 0
  for _, c in ipairs(V.candidates(f)) do
    if overlaps(c, view) then
      local nr = roomAt(f.assets, c.area, c.room)
      if nr then
        local dx, dy = c.x - r.x, c.y - r.y
        backdropRect(nr, dx - vx, dy - vy)
        -- round 15: a neighbour's BG3 background (Bg3.lua) under its layers
        local B3 = require("src.zelda.tmc.Bg3")
        if nr.bg3 == nil then B3.forRoom(nr) end
        -- and its BG tile animations, stepped once per field frame
        if nr._animFrame ~= f.frame then nr._animFrame = f.frame; pcall(nr.updateAnims, nr) end
        if nr.bg3 then B3.draw(f, nr, vx - dx, vy - dy) end
        V.drawLayer(f, nr, "bottom", vx - dx, vy - dy, vw, vh)
        V.drawLayer(f, nr, "top", vx - dx, vy - dy, vw, vh)
        drawn = drawn + 1
      end
    end
  end
  -- the room Link just left, while the camera still shows it
  local prev = f.camFree and f.camFree.prev
  if prev and prev.x and not (prev.area == r.area and prev.room == r.room) then
    local seen = false
    for _, c in ipairs(V.candidates(f)) do if c.area == prev.area and c.room == prev.room then seen = true break end end
    if not seen then
      local dx, dy = prev.x - r.x, prev.y - r.y
      backdropRect(prev, dx - vx, dy - vy)
      prev:drawLayer("bottom", vx - dx, vy - dy)
      prev:drawLayer("top", vx - dx, vy - dy)
      drawn = drawn + 1
    end
  end
  f.viewNeighbours = drawn
  backdropRect(r, -math.floor(vx), -math.floor(vy))
  local camX0, camY0 = f.camX, f.camY
  f._realCam = { camX0, camY0 } -- round 15: Bg3.lua scrolls BG3 by the field's own camera
  f.camX, f.camY = vx, vy
  if z ~= 1 then f.layerFn = function(room, name, cx, cy) V.drawLayer(f, room, name, cx, cy, vw, vh) end end
  local ok, err = pcall(worldFn)
  f.layerFn = nil
  f._realCam = nil
  f.camX, f.camY = camX0, camY0
  if not ok then g.pop() error(err, 0) end
  g.pop()
end

return V
