-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FOUR SWORDS MODE: 1-4 Links on a Four Swords floor from the cartridge.
--
-- From the ROM: the floors (both layers, per-area tileset and palettes), the
-- collision, each floor's start point (its type-4 object), the world tables
-- that order the floors, and the four Links' palettes (green, red, blue,
-- purple). Ours, documented in docs/zelda/alttp.md: Link's sprite (the
-- ALttP sheet recoloured into each Four Swords palette), the rupee layout
-- (seeded; the cartridge drops rupees from grass, pots and enemies, none of
-- which is ported), the rupee shape, the stage timer and the results screen.
--
-- CAMERA: like the cartridge (0x08015DD8), every player's screen follows
-- their own Link, clamped to the 1008x1008 floor -- each GBA had its own
-- screen, so there is no shared camera to keep everyone in.
--
-- ONLINE (host authoritative for rupees and the stage):
--   event  { t="fs_start", serial, w, i, seed, n, taken = { [id]=by } }
--   event  { t="fs_take", serial, id }        guest -> host: I touched it
--   event  { t="fs_got",  serial, id, by }    host -> all: who gets it
--   event  { t="fs_end",  serial, scores }    host -> all: the tally
--   snapshot { v=1, m="fs", serial, x, y, f, s }

local Fs = require("src.zelda.alttp.Fs")
local Link = require("src.zelda.alttp.Link")
local Palette = require("src.zelda.alttp.Palette")

local M = {}
M.__index = M

M.W, M.H = 240, 160
M.STAGE_FRAMES = 60 * 120      -- two minutes a stage (ours)
M.RUPEES = 30
M.START_WORLD = 4               -- the world table with the Sea of Trees floors

function M.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, fs = opts.fs,
                              peers = {}, scores = {}, serial = 0, state = "idle",
                              frame = 0, images = {} }, M)
  if not self.fs then self.fs = Fs.load(game.opts.cache) end
  self:buildPalettes()
  return self
end

-- ALttP Link's colour indices -> the nearest colour of the green Four Swords
-- palette, so every player's tunic uses the cartridge's own four palettes
function M:buildPalettes()
  local src = Palette.link(self.data)
  local fsp = self.fs.info.linkPalettes
  local function rgb(c) return c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32 end
  local map = {}
  for i = 0, 15 do
    local r, g, b = rgb(src[i])
    local best, bd = 1, 1e9
    for j = 2, 16 do
      local r2, g2, b2 = rgb(fsp[1][j])
      local dd = (r - r2) ^ 2 + (g - g2) ^ 2 + (b - b2) ^ 2
      if dd < bd then best, bd = j, dd end
    end
    map[i] = best
  end
  self.indexMap = map
  self.pals = {}
  for p = 1, 4 do
    local pal = {}
    for i = 0, 15 do pal[i] = fsp[p][map[i]] end
    self.pals[p] = pal
  end
end

function M:session()
  local g = self.game
  if g.session then return g.session end
  local h = g.opts.host
  if h and h.session then return h:session() end
  return g.opts.online
end
function M:myId()
  local s = self:session()
  return (s and s.localId) or 1
end
function M:isHost()
  local s = self:session()
  return not s or s.isHost
end

function M:floorEntry(w, i)
  local list = self.fs.info.worlds[w]
  if not list or #list == 0 then return nil end
  return list[((i - 1) % #list) + 1]
end

-- start (or join) a stage
function M:start(w, i, seed, serial, taken)
  local entry = assert(self:floorEntry(w, i), "no such floor")
  self.world, self.index, self.seed = w, i, seed
  self.serial = serial or (self.serial + 1)
  self.floor = self.fs:floor(entry.floor)
  self.rupees = Fs.layoutRupees(self.floor, seed, M.RUPEES)
  self.byId = {}
  for _, r in ipairs(self.rupees) do self.byId[r.id] = r end
  self.scores = {}
  self.pending = {}
  if taken then
    for id, by in pairs(taken) do self:award(tonumber(id), tonumber(by)) end
  end
  -- player n spawns on the n-th nearest reachable cell to the start
  local reach = Fs.reachable(self.floor)
  local me = ((self:myId() - 1) % 4) + 1
  local cell = reach[math.min(#reach, 1 + (me - 1) * 2)] or reach[1]
  local cx, cy = cell % Fs.W, math.floor(cell / Fs.W)
  self.link = Link.new(self.data, { x = cx * 16, y = cy * 16 - 8, facing = Link.DOWN, world = "fs" })
  self.timer = M.STAGE_FRAMES
  self.state = "play"
  self.results = nil
  self:dropImages()
  if self:isHost() then
    self:send({ t = "fs_start", serial = self.serial, w = w, i = i, seed = seed, n = M.RUPEES })
  end
end

function M:dropImages()
  for _, im in pairs(self.images) do pcall(im.release, im) end
  self.images = {}
end

function M:send(ev, to)
  local s = self:session()
  if not s then return end
  if to then pcall(s.sendEventTo, s, to, ev) else pcall(s.sendEvent, s, ev) end
end

function M:award(id, by)
  local r = self.byId and self.byId[id]
  if not r or r.taken then return false end
  r.taken = by
  self.scores[by] = (self.scores[by] or 0) + r.value
  return true
end

function M:remaining()
  local n = 0
  for _, r in ipairs(self.rupees or {}) do if not r.taken then n = n + 1 end end
  return n
end

function M:finish()
  self.state = "results"
  self.results = Fs.ranking(self.scores)
  if self:isHost() then self:send({ t = "fs_end", serial = self.serial, scores = self.scores }) end
end

local function held(input, b) return input and input.isDown(b) end
local function pressed(input, b) return input and input.wasPressed(b) end

function M:update(input)
  self.frame = self.frame + 1
  if self.state == "idle" then
    if self:isHost() then self:start(M.START_WORLD, 1, (os.time() % 100000) + 7, 1) end
    return
  end
  if self.state == "results" then
    if self:isHost() and pressed(input, "a") then
      self:start(self.world, self.index + 1, self.seed + 101, self.serial + 1)
    end
    return
  end
  if self.state ~= "play" then return end
  local fl = self.floor
  local inp = { up = held(input, "up"), down = held(input, "down"),
                left = held(input, "left"), right = held(input, "right") }
  self.link:update(inp, function(_, x, y) return Fs.blocked(fl, x, y) and 0x01 or 0x00 end)
  -- touching a rupee (Link's 16x16 body box at y+8)
  local me = self:myId()
  local lx, ly = self.link.x, self.link.y + 8
  for _, r in ipairs(self.rupees) do
    if not r.taken and not self.pending[r.id]
       and lx < r.x + 8 and lx + 16 > r.x and ly < r.y + 8 and ly + 16 > r.y then
      if self:isHost() then
        if self:award(r.id, me) then self:send({ t = "fs_got", serial = self.serial, id = r.id, by = me }) end
      else
        self.pending[r.id] = true
        self:send({ t = "fs_take", serial = self.serial, id = r.id })
      end
    end
  end
  for _, p in pairs(self.peers) do
    if p.tx then
      p.x = p.x + (p.tx - p.x) * 0.5
      p.y = p.y + (p.ty - p.y) * 0.5
    end
  end
  if self:isHost() then
    self.timer = self.timer - 1
    if self.timer <= 0 or self:remaining() == 0 then self:finish() end
  else
    self.timer = math.max(0, self.timer - 1)
  end
end

-- ------------------------------------------------------------------ online

function M:snapshot()
  if not self.link then return nil end
  return { v = 1, m = "fs", serial = self.serial, x = self.link.x, y = self.link.y,
           f = self.link.facing, s = self.link.steps }
end

local function num(v, d) v = tonumber(v) return v and math.floor(v) or d end

function M:apply(peer, snap)
  if type(snap) ~= "table" or snap.m ~= "fs" then return end
  local p = self.peers[peer] or { id = peer }
  p.tx = math.max(0, math.min(Fs.PX, num(snap.x, 0)))
  p.ty = math.max(0, math.min(Fs.PX, num(snap.y, 0)))
  if not p.x then p.x, p.y = p.tx, p.ty end
  local f = num(snap.f, 2)
  p.facing = (f == 0 or f == 2 or f == 4 or f == 6) and f or 2
  p.steps = math.max(0, math.min(8, num(snap.s, 0)))
  p.serial = num(snap.serial, 0)
  self.peers[peer] = p
end

function M:event(peer, ev)
  if type(ev) ~= "table" then return end
  local serial = num(ev.serial, -1)
  if ev.t == "fs_start" and not self:isHost() then
    local w, i, seed = num(ev.w, M.START_WORLD), num(ev.i, 1), num(ev.seed, 1)
    if self.fs.info.worlds[w] then self:start(w, i, seed, serial, ev.taken) end
  elseif ev.t == "fs_take" and self:isHost() and serial == self.serial and self.state == "play" then
    local id, by = num(ev.id, 0), num(peer, 0)
    if by >= 1 and by <= 4 and self:award(id, by) then
      self:send({ t = "fs_got", serial = self.serial, id = id, by = by })
    end
  elseif ev.t == "fs_got" and not self:isHost() and serial == self.serial then
    local id, by = num(ev.id, 0), num(ev.by, 0)
    self.pending[id] = nil
    if by >= 1 and by <= 4 then self:award(id, by) end
  elseif ev.t == "fs_end" and not self:isHost() and serial == self.serial then
    if type(ev.scores) == "table" then
      local sc = {}
      for k, v in pairs(ev.scores) do
        local id = num(k, 0)
        if id >= 1 and id <= 4 then sc[id] = math.max(0, num(v, 0)) end
      end
      self.scores = sc
    end
    self.state = "results"
    self.results = Fs.ranking(self.scores)
  end
end

-- a guest who arrives mid-stage gets the stage and what is already taken
function M:peerJoined(peer)
  if self:isHost() and self.state ~= "idle" and self.rupees then
    local taken = {}
    for _, r in ipairs(self.rupees) do if r.taken then taken[tostring(r.id)] = r.taken end end
    self:send({ t = "fs_start", serial = self.serial, w = self.world, i = self.index,
                seed = self.seed, n = M.RUPEES, taken = taken }, peer)
  end
end

function M:peerLeft(peer) self.peers[peer] = nil end

-- ------------------------------------------------------------------ drawing

function M:camera()
  local cx = self.link.x + 8 - M.W / 2
  local cy = self.link.y + 12 - M.H / 2
  cx = math.max(0, math.min(Fs.PX - M.W, cx))
  cy = math.max(0, math.min(Fs.PX - M.H, cy))
  return math.floor(cx), math.floor(cy)
end

function M:layerImage(layer)
  local key = layer
  if self.images[key] then return self.images[key] end
  local View = require("src.zelda.alttp.View")
  local pal = self.fs:palette(self.floor.area)
  local idx = self.fs:decodeLayer(self.floor.map, self.floor.area, layer)
  local img = love.image.newImageData(Fs.PX, Fs.PX)
  View.fill(img, Fs.PX, Fs.PX, idx, pal, layer == "B" and pal[0] or nil)
  local im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  self.images[key] = im
  return im
end

M.RUPEE_RGB = { green = { 0.25, 0.85, 0.3 }, blue = { 0.3, 0.5, 1.0 }, red = { 1.0, 0.3, 0.3 } }

function M:drawLinkAt(x, y, facing, steps, player, camx, camy)
  local view = self.game.view
  local parts = Link.pose(self.data, facing, steps or 0)
  local pal = self.pals[((player - 1) % 4) + 1]
  for i = #parts, 1, -1 do
    local p = parts[i]
    local im = view:linkCell(p.cell, pal, "fs" .. player)
    love.graphics.draw(im, x - camx + p.dx + (p.hflip and 16 or 0), y - camy + p.dy + (p.vflip and 16 or 0),
                       0, p.hflip and -1 or 1, p.vflip and -1 or 1)
  end
end

function M:draw()
  if self.state == "idle" or not self.floor then
    love.graphics.printf("FOUR SWORDS\nwaiting for the host...", 0, 64, M.W, "center")
    return
  end
  local camx, camy = self:camera()
  -- both BG layers sit behind the sprites (B the ground, A over it); the
  -- cartridge's per-tile priority tricks for canopies are not ported
  love.graphics.draw(self:layerImage("B"), -camx, -camy)
  love.graphics.draw(self:layerImage("A"), -camx, -camy)
  -- rupees (our shape)
  for _, r in ipairs(self.rupees) do
    if not r.taken then
      local c = M.RUPEE_RGB[r.kind]
      local x, y = r.x - camx, r.y - camy
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.polygon("fill", x + 4, y - 2, x + 8, y + 3, x + 4, y + 10, x, y + 3)
      love.graphics.setColor(1, 1, 1, 0.8)
      love.graphics.line(x + 4, y, x + 4, y + 7)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local list = {}
  for id, p in pairs(self.peers) do
    if p.x and p.serial == self.serial then
      list[#list + 1] = { y = p.y, f = function() self:drawLinkAt(math.floor(p.x + 0.5), math.floor(p.y + 0.5), p.facing, p.steps, id, camx, camy) end }
    end
  end
  local me = self:myId()
  list[#list + 1] = { y = self.link.y, f = function() self:drawLinkAt(self.link.x, self.link.y, self.link.facing, self.link.steps, me, camx, camy) end }
  table.sort(list, function(a, b) return a.y < b.y end)
  for _, e in ipairs(list) do e.f() end
  self:drawHud()
end

M.PLAYER_RGB = { { 0.3, 0.9, 0.3 }, { 1, 0.35, 0.35 }, { 0.4, 0.6, 1 }, { 0.8, 0.45, 1 } }

function M:drawHud()
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, M.W, 12)
  local x = 2
  for id = 1, 4 do
    if id == self:myId() or self.peers[id] or self.scores[id] then
      local c = M.PLAYER_RGB[id]
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.print(("%d:%d"):format(id, self.scores[id] or 0), x, 0)
      x = x + 48
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local secs = math.ceil(self.timer / 60)
  love.graphics.print(("%d:%02d"):format(math.floor(secs / 60), secs % 60), M.W - 34, 0)
  if self.state == "results" and self.results then
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 30, 30, 180, 100)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("STAGE CLEAR", 30, 34, 180, "center")
    for i, e in ipairs(self.results) do
      local c = M.PLAYER_RGB[e.id] or { 1, 1, 1 }
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.printf(("%d. Player %d  %d rupees"):format(e.place, e.id, e.rupees), 30, 34 + i * 16, 180, "center")
    end
    love.graphics.setColor(1, 1, 1, 1)
    if self:isHost() then love.graphics.printf("A: next floor", 30, 116, 180, "center") end
  end
end

return M
