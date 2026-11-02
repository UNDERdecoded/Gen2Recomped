-- THE VISUAL COMPETITION'S DRESS-UP (pokeplatinum overlay022, ov22_02255D44):
-- sixty seconds to dress your Pokemon from your Accessories, before it goes on
-- stage.
--
-- THE RULES, as the overlay keeps them:
--   * no more than 5 / 10 / 15 / 20 Accessories out at once, by rank
--     (ov22_02257580; 20 in a link contest) -- the cap is on what is on the
--     screen, not on what counts;
--   * sixty seconds (ov22_02256BF4's 60), or DONE and "Is your Pokemon all
--     dressed up?";
--   * what COUNTS is what is ON the Pokemon (ov22_02256FD8 /
--     ov22_0225768C): starting from the Pokemon, an Accessory is attached when
--     one of its opaque pixels covers one of sixteen points of an attached
--     thing's trimmed box -- the 4x4 grid of its edges and thirds
--     (ov22_022577EC) -- so Accessories chain off each other; at most twenty
--     are kept;
--   * the score is each attached Accessory's worth in the theme's table
--     (ov17_02252A70 -> Gen4Contest.dressScore).
-- Accessories are not used up.
--
-- THE SCREEN: the dressing room (imageclip.narc 121/133/122 -- 224/225/226
-- is the other screen's, see D:draw; the old 224 picture stays the fallback
-- on a cache without the photo studio's art) with the
-- Accessories in your case down the left (as line 47 says) and the Pokemon
-- on the right at the overlay's x 192. The words are bank 385's.
--
-- CONTROLS: drag with the touch screen / mouse. Or: arrows choose in the
-- case, A takes one out; arrows move it, A puts it down, B puts it back;
-- SELECT picks up the Accessories already out, in turn; START is DONE.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local D = {}
D.__index = D

D.BANK = 385
D.TIME = 60
D.KEEP = 20
D.MON_X, D.MON_FOOT = 192, 145
-- the case's window in the dressing room BG is (10..117, 18..140)
D.CASE = { x = 10, y = 18, cols = 3, rows = 3, cell = 36 }
D.DONE = { x = 200, y = 4, w = 52, h = 14 }

function D.cap(rank, link)
  if link then return 20 end
  return ({ [0] = 5, 10, 15, 20 })[tonumber(rank) or 0] or 5
end

-- ov22_022577EC's sixteen points of a box {l, t, r, b}
function D.gridPoints(box)
  local l, t, r, b = box[1], box[2], box[3], box[4]
  local xs = { l, l + math.floor((r - l) / 3), l + math.floor((r - l) / 3) * 2, r }
  local ys = { t, t + math.floor((b - t) / 3), t + math.floor((b - t) / 3) * 2, b }
  local out = {}
  for _, x in ipairs(xs) do for _, y in ipairs(ys) do out[#out + 1] = { x, y } end end
  return out
end

-- ov22_0225768C: which placed things are on the Pokemon. `mon` and each of
-- `items` are { box = {l,t,r,b}, opaque = function(x, y) }. Returns the
-- attached items in the order they joined, at most D.KEEP.
function D.attached(mon, items)
  local state = {}
  local list = { { thing = mon, state = 1 } }
  for _, it in ipairs(items) do list[#list + 1] = { thing = it, state = 0 } end
  local joined = {}
  local i = 1
  while i <= #list do
    local a = list[i]
    if a.state == 1 then
      for _, c in ipairs(list) do
        if c.state == 0 then
          for _, p in ipairs(D.gridPoints(a.thing.box)) do
            if c.thing.opaque(p[1], p[2]) then
              c.state = 1
              joined[#joined + 1] = c.thing
              break
            end
          end
        end
      end
      a.state = 2
      i = 1
    else
      i = i + 1
    end
  end
  local out = {}
  for k = 1, math.min(#joined, D.KEEP) do out[k] = joined[k] end
  return out
end

-- An image's opaque extent as a box at (x, y), and a pixel test for it.
local function shape(data, x, y)
  local w, h = data:getDimensions()
  local l, t, r, b = w, h, -1, -1
  for py = 0, h - 1 do
    for px = 0, w - 1 do
      local _, _, _, a = data:getPixel(px, py)
      if a > 0 then
        if px < l then l = px end
        if px > r then r = px end
        if py < t then t = py end
        if py > b then b = py end
      end
    end
  end
  if r < 0 then l, t, r, b = 0, 0, 0, 0 end
  return {
    box = { x + l, y + t, x + r, y + b },
    opaque = function(qx, qy)
      local lx, ly = math.floor(qx - x), math.floor(qy - y)
      if lx < 0 or ly < 0 or lx >= w or ly >= h then return false end
      local _, _, _, a = data:getPixel(lx, ly)
      return a > 0
    end,
  }
end
D.shape = shape

-- ----------------------------------------------------------------- setup --

function D.new(game, contest, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, c = contest, data = game.data, onDone = opts.onDone,
    placed = {}, held = nil, focus = "case", cursor = 1, page = 0, queue = {},
    time = D.TIME, mode = "intro", images = {}, imageData = {} }, D)
  self.cap = D.cap(contest.rank, opts.link)
  local inv = game.save and game.save.gen4Accessories or {}
  local rec = game.data.gen4_dressup or {}
  self.owned = {}
  for id = 0, 99 do
    local n = tonumber(inv[id]) or 0
    if n > 0 and rec.accessories and rec.accessories[id] then self.owned[#self.owned + 1] = { id = id, count = n } end
  end
  local practice = require("src.pokemon.Gen4Contest").isPractice(contest.competition)
  self:say(practice and 28 or 26)
  self:say(29 + (contest.theme or 0))
  self:say(practice and 41 or 42, { [0] = tostring(self.cap) })
  return self
end

function D:say(index, slots)
  local values = {}
  for slot = 0, 4 do values[slot + 1] = slots and slots[slot] or "" end
  T.buffer(self.game, (table.unpack or unpack)(values))
  local text = T.resolve(self.data, D.BANK, index, self.game)
  if not text then return end
  for page in (text .. "\f"):gmatch("([^\v\f\r]*)[\v\f\r]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then self.queue[#self.queue + 1] = page end
  end
end

local function rec(self, id)
  local r = self.data.gen4_dressup
  return r and r.accessories and r.accessories[id]
end

function D:image(id)
  if self.images[id] == nil then
    local r = rec(self, id)
    local ok, img = false, nil
    if r and r.path then ok, img = pcall(require("src.render.Assets").image, r.path) end
    if ok and img then img:setFilter("nearest", "nearest") end
    self.images[id] = ok and img or false
  end
  return self.images[id] or nil
end

function D:pixels(id)
  if self.imageData[id] == nil then
    local r = rec(self, id)
    local ok, d = false, nil
    if r and r.path then ok, d = pcall(require("src.render.Assets").imageData, r.path) end
    self.imageData[id] = ok and d or false
  end
  return self.imageData[id] or nil
end

function D:monImage()
  if self.mon == nil then
    local mon = self.c.contestants[0].mon
    local path = require("src.pokemon.Sprites").path(self.data, mon.species, "front", { mon = mon, kind = "contest" })
    local okI, img = false, nil
    local okD, dat = false, nil
    if path then
      okI, img = pcall(require("src.render.Assets").image, path)
      okD, dat = pcall(require("src.render.Assets").imageData, path)
    end
    self.mon = { image = okI and img or nil, data = okD and dat or nil }
  end
  return self.mon
end

-- the Pokemon's top-left: centred on x 192, standing on the overlay's floor
function D:monAt()
  local m = self:monImage()
  local w, h = 80, 80
  if m.image then w, h = m.image:getDimensions() end
  return D.MON_X - math.floor(w / 2), D.MON_FOOT - h, w, h
end

-- ------------------------------------------------------------- the case --

function D:visibleOwned()
  local per = D.CASE.cols * D.CASE.rows
  local out = {}
  for k = self.page * per + 1, math.min(#self.owned, (self.page + 1) * per) do out[#out + 1] = { slot = k, entry = self.owned[k] } end
  return out
end

function D:cellAt(slotInPage)
  local col = (slotInPage - 1) % D.CASE.cols
  local row = math.floor((slotInPage - 1) / D.CASE.cols)
  return D.CASE.x + col * D.CASE.cell, D.CASE.y + row * D.CASE.cell
end

function D:outCount(id)
  local n = 0
  for _, p in ipairs(self.placed) do if p.id == id then n = n + 1 end end
  if self.held and self.held.id == id then n = n + 1 end
  return n
end

function D:take(entry, x, y)
  if not entry then return false end
  local total = #self.placed + (self.held and 1 or 0)
  if total >= self.cap or self:outCount(entry.id) >= entry.count then return false end
  local r = rec(self, entry.id)
  local w, h = r and r.width or 16, r and r.height or 16
  self.held = { id = entry.id, x = x - math.floor(w / 2), y = y - math.floor(h / 2), w = w, h = h }
  return true
end

function D:put()
  local h = self.held
  if not h then return end
  self.held = nil
  local cx = h.x + h.w / 2
  -- let go over the case: back in the case
  if cx < D.CASE.x + D.CASE.cols * D.CASE.cell then return end
  self.placed[#self.placed + 1] = h
end

function D:pickAt(x, y)
  for k = #self.placed, 1, -1 do
    local p = self.placed[k]
    local d = self:pixels(p.id)
    local lx, ly = math.floor(x - p.x), math.floor(y - p.y)
    if lx >= 0 and ly >= 0 and lx < p.w and ly < p.h then
      local a = 1
      if d then local _, _, _, al = d:getPixel(lx, ly); a = al end
      if a > 0 then
        table.remove(self.placed, k)
        self.held = p
        return true
      end
    end
  end
  return false
end

-- ------------------------------------------------------------- finishing --

function D:finish()
  local mx, my = self:monAt()
  local m = self:monImage()
  local monShape = m.data and shape(m.data, mx, my)
    or { box = { mx, my, mx + 79, my + 79 }, opaque = function() return false end }
  local items = {}
  for _, p in ipairs(self.placed) do
    local d = self:pixels(p.id)
    local s = d and shape(d, p.x, p.y) or { box = { p.x, p.y, p.x + p.w - 1, p.y + p.h - 1 }, opaque = function() return false end }
    s.placed = p
    items[#items + 1] = s
  end
  local worn = {}
  for _, s in ipairs(D.attached(monShape, items)) do
    local p = s.placed
    -- kept relative to the Pokemon's centre, for drawing it on stage
    worn[#worn + 1] = { accessory = p.id, x = p.x - D.MON_X, y = p.y - (D.MON_FOOT - 40) }
  end
  self.c.contestants[0].accessories = worn
  self.mode = "done"
  if self.onDone then self.onDone(worn) end
end

-- -------------------------------------------------------------- updates --

function D:update(dt)
  local input = self.game.input
  if self.mode == "intro" then
    if input:wasPressed("a") or input:wasPressed("b") then
      table.remove(self.queue, 1)
      if #self.queue == 0 then self.mode = "play" end
    end
    return
  end
  if self.mode == "confirm" then
    if input:wasPressed("a") then self.held = nil; return self:finish() end
    if input:wasPressed("b") then self.mode = "play" end
    return
  end
  if self.mode ~= "play" then return end
  self.time = self.time - (dt or 1 / 60)
  if self.time <= 0 then
    self.time = 0
    if self.held then self:put() end
    return self:finish()
  end
  if input:wasPressed("start") then self.mode = "confirm"; self.prompt = T.resolve(self.data, D.BANK, 1); return end
  if self.held and not self.dragging then
    local s = 2
    if input:isDown("left") then self.held.x = self.held.x - s end
    if input:isDown("right") then self.held.x = self.held.x + s end
    if input:isDown("up") then self.held.y = self.held.y - s end
    if input:isDown("down") then self.held.y = self.held.y + s end
    if input:wasPressed("a") then self:put() end
    if input:wasPressed("b") then self.held = nil end
    return
  end
  local per = D.CASE.cols * D.CASE.rows
  if input:wasPressed("right") then self.cursor = math.min(#self.owned, self.cursor + 1) end
  if input:wasPressed("left") then self.cursor = math.max(1, self.cursor - 1) end
  if input:wasPressed("down") then self.cursor = math.min(#self.owned, self.cursor + D.CASE.cols) end
  if input:wasPressed("up") then self.cursor = math.max(1, self.cursor - D.CASE.cols) end
  self.page = math.max(0, math.floor((self.cursor - 1) / per))
  if input:wasPressed("a") and self.owned[self.cursor] then
    local mx, my, w, h = self:monAt()
    self:take(self.owned[self.cursor], mx + w / 2, my + h / 2)
  end
  if input:wasPressed("select") and #self.placed > 0 then
    self.held = table.remove(self.placed, 1)
  end
end

-- touch / mouse, in the screen's own 256x192
local function toUi(px, py)
  local rect = require("src.render.Renderer").uiPresentation
  if not rect then return px, py end
  return (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
end

function D:touchpressed(id, px, py)
  if self.mode == "intro" then table.remove(self.queue, 1); if #self.queue == 0 then self.mode = "play" end; return true end
  if self.mode == "confirm" then return true end
  if self.mode ~= "play" then return false end
  local x, y = toUi(px, py)
  local b = D.DONE
  if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
    self.mode = "confirm"; self.prompt = T.resolve(self.data, D.BANK, 1)
    return true
  end
  for k, v in ipairs(self:visibleOwned()) do
    local cx, cy = self:cellAt(k)
    if x >= cx and x < cx + D.CASE.cell and y >= cy and y < cy + D.CASE.cell then
      self.cursor = v.slot
      if self:take(v.entry, x, y) then self.dragging = { id = id, dx = self.held.x - x, dy = self.held.y - y } end
      return true
    end
  end
  if self:pickAt(x, y) then
    self.dragging = { id = id, dx = self.held.x - x, dy = self.held.y - y }
    return true
  end
  return true
end

function D:touchmoved(id, px, py)
  local d = self.dragging
  if not (d and d.id == id and self.held) then return false end
  local x, y = toUi(px, py)
  self.held.x, self.held.y = math.floor(x + d.dx), math.floor(y + d.dy)
  return true
end

function D:touchreleased(id)
  local d = self.dragging
  if d and d.id == id then
    self.dragging = nil
    self:put()
  end
  return true
end

-- ---------------------------------------------------------------- draws --

function D:drawAccessory(p)
  local img = self:image(p.id)
  if img then love.graphics.draw(img, p.x, p.y) end
end

function D:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if self.room == nil then
    local room = self.data.gen4_dressup and self.data.gen4_dressup.room
    local ok, img = false, nil
    if room and room.path then ok, img = pcall(require("src.render.Assets").image, room.path) end
    self.room = ok and img or false
  end
  -- THE ROOM IS IMAGECLIP 121 / 133 / 122, as in the photo studio:
  -- VisualCompetition_Init calls the same ov22_02256948(v0, 0) as
  -- ov22_02255D44 (pokeplatinum ov22_02255D44.c 455); 224 / 225 / 226 is the
  -- OTHER screen's BG (ov22_02256BF4 -> ov22_0225A428 flag 2,
  -- ov22_0225A6E0, BG_LAYER_SUB). Behind its windows: backdrop 0
  -- (ov22_02256790 -> ov22_02257C88(.., 0, ..)) and the case's BG 129/130.
  local photo = self.data.gen4_dressup and self.data.gen4_dressup.photo
  if self.photoRoom == nil then
    local function load(rec)
      local ok, img = false, nil
      if rec and rec.path then ok, img = pcall(require("src.render.Assets").image, rec.path) end
      if ok and img then img:setFilter("nearest", "nearest") end
      return ok and img or false
    end
    local bds = self.data.gen4_dressup and self.data.gen4_dressup.backdrops
    self.photoRoom = load(photo and photo.photo_room)
    self.photoCase = load(photo and photo.photo_case_acc)
    self.photoBackdrop = load(bds and bds[0])
    self.photoFill = self.data.gen4_dressup and self.data.gen4_dressup.photoFill
  end
  local bg = self.photoRoom or self.room
  if self.photoRoom then
    local f = self.photoFill
    if f then g.setColor(f[1] / 255, f[2] / 255, f[3] / 255, 1); g.rectangle("fill", 0, 0, 256, 192); g.setColor(1, 1, 1, 1) end
    if self.photoBackdrop then g.draw(self.photoBackdrop, 136, 16) end
    if self.photoCase then g.draw(self.photoCase, 8, 16) end
  end
  if bg then g.draw(bg, 0, 0) else g.setColor(0.95, 0.6, 0.8, 1); g.rectangle("fill", 0, 0, 256, 192); g.setColor(1, 1, 1, 1) end
  -- the Pokemon
  local m = self:monImage()
  local mx, my = self:monAt()
  if m.image then g.draw(m.image, mx, my) end
  for _, p in ipairs(self.placed) do self:drawAccessory(p) end
  -- the case
  if not self.photoRoom then
    g.setColor(1, 1, 1, 0.75)
    g.rectangle("fill", D.CASE.x - 2, D.CASE.y - 2, D.CASE.cols * D.CASE.cell + 4, D.CASE.rows * D.CASE.cell + 4)
  end
  for k, v in ipairs(self:visibleOwned()) do
    local cx, cy = self:cellAt(k)
    g.setColor(1, 1, 1, 1)
    local img = self:image(v.entry.id)
    if img then
      local w, h = img:getDimensions()
      local s = math.min(1, (D.CASE.cell - 6) / math.max(w, h))
      g.draw(img, cx + D.CASE.cell / 2, cy + D.CASE.cell / 2, 0, s, s, w / 2, h / 2)
    end
    local left = v.entry.count - self:outCount(v.entry.id)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.85, 0.85, 0.85 } })
    if v.entry.count > 1 then Font.draw(tostring(left), cx + D.CASE.cell - 10, cy + D.CASE.cell - 14) end
    Font.popStyle()
    if v.slot == self.cursor and self.mode == "play" and not self.held then
      g.setColor(1, 0.3, 0.3, 1)
      g.rectangle("line", cx + 0.5, cy + 0.5, D.CASE.cell - 1, D.CASE.cell - 1)
    end
  end
  g.setColor(1, 1, 1, 1)
  if self.held then self:drawAccessory(self.held) end
  -- the timer, the count and DONE
  Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.3, 0.1, 0.3 } })
  Font.draw(("%d"):format(math.ceil(self.time)), 140, 4)
  Font.draw(("%d/%d"):format(#self.placed + (self.held and 1 or 0), self.cap), 160, 4)
  Font.popStyle()
  local b = D.DONE
  g.setColor(0.95, 0.95, 1, 1)
  g.rectangle("fill", b.x, b.y, b.w, b.h, 3, 3)
  g.setColor(1, 1, 1, 1)
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.85, 0.85, 0.85 } })
  Font.draw(T.resolve(self.data, D.BANK, 0) or "DONE!", b.x + 6, b.y + 1)
  Font.popStyle()
  -- a message
  local text = (self.mode == "intro" and self.queue[1]) or (self.mode == "confirm" and self.prompt) or nil
  if text then
    if Font.hasDialogueFrame and Font.hasDialogueFrame() then
      Font.drawDialogueBox(1, 18, 29, 6)
    else
      g.setColor(1, 1, 1, 1); g.rectangle("fill", 8, 144, 240, 44)
    end
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
    local y = 152
    for l in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    Font.popStyle()
  end
  g.setColor(1, 1, 1, 1)
end

return D
