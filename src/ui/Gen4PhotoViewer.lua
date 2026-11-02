-- THE PHOTO FRAME VIEWER: Platinum's ShowDressUpPhoto / 0A8 (overlay 22's
-- ov22_0225B660 / _0225B738 / _0225B7FC) and HGSS's ScrCmd_155
-- (AccessoryPortrait_Init / Main / Exit in overlay 41, the dress-up branch
-- only).
--
-- READ FROM CODE (pokeplatinum src/overlay022/ov22_0225B660.c,
-- ov22_0225AF8C.c):
--   * the frame is imageclip 125 / 126 / 128 (127 for a contest photo);
--   * the photo is drawn again from the save: the backdrop, the Pokemon at
--     its kept place, every kept Accessory (ov22_0225B388), the stage moved
--     to x 72 (ov22_0225B490 / _0225B080 with 72, 16);
--   * a text window at tile row 18, 32 x 6 (ov22_0225BA40): a dress-up
--     photo prints the trainer's name centred on x 128 at y 7, then bank
--     385 line 45 (the title word) centred at y 27 (ov22_0225BB00); a
--     contest photo prints line 43 (contest type, rank) and line 44
--     (trainer's Pokemon) instead (ov22_0225BC18);
--   * A or B closes it (ov22_0225B738 case 3); HGSS also takes a touch.
-- INFERRED: the stage's top-left is (72, 14) so the frame's 108 x 123
-- window (74..181, 16..138 in the composed BG) sits where the dressing
-- room's does on its stage (2 px in). READ: the name plate sprite under the
-- text (imageclip 231..234; ov22_0225B964 / _0225BB00 / _0225BC18); the
-- photo's sprites are drawn by their kept priorities (ov22_0225B388).

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")
local Photos = require("src.pokemon.Gen4Photos")

local V = {}
V.__index = V
V.isOpaque = false
V.STAGE_X, V.STAGE_Y = 72, 14

function V:uiSize() return 256, 192 end

-- opts: { kind = "dressUp" | "contest", slot = n, onDone = function() }
function V.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, kind = opts.kind or "dressUp", slot = opts.slot or 0,
    onDone = opts.onDone, images = {} }, V)
  self.photo = Photos.get(game.save, self.kind, self.slot)
  return self
end

local function bank() return require("src.import.Gen4ScriptBands").family == "hgss" and 215 or 385 end

local function load(self, key, path)
  if self.images[key] == nil then
    local ok, img = false, nil
    if path then ok, img = pcall(require("src.render.Assets").image, path) end
    if ok and img then img:setFilter("nearest", "nearest") end
    self.images[key] = ok and img or false
  end
  return self.images[key] or nil
end

function V:close()
  if self.closed then return end
  self.closed = true
  if self.game.stack and self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

function V:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then self:close() end
end

function V:touchpressed() self:close() return true end

-- the text lines (ov22_0225BB00 / ov22_0225BC18)
function V:lines()
  local p = self.photo or {}
  local data = self.data
  if self.kind == "contest" then
    local function txt(b, i) return data.text and data.text[T.label(b, i)] or "" end
    local cb = 204   -- Contest_GetContestTypeMessageID / _GetRankMessageID's bank (Platinum)
    local typeName = txt(cb, 41 + (p.contestType or 0))
    local rank = p.rank or 0
    local rankName = txt(cb, rank <= 3 and 46 + rank or 51)
    local species = Photos.speciesId(p.mon and p.mon.species)
    local nick = (p.mon and p.mon.nickname) or txt(412, species)
    -- line 43 = { 0 type, 1 rank }, line 44 = { 3 trainer, 4 nickname }
    T.buffer(self.game, typeName, rankName, "", tostring(p.trainerName or ""), tostring(nick))
    local l1 = T.resolve(data, bank(), 43, self.game) or ""
    local l2 = T.resolve(data, bank(), 44, self.game) or ""
    if l1:match("^%s*$") then l1 = ("%s %s"):format(typeName, rankName) end
    if l2:match("^%s*$") then l2 = ("%s's %s"):format(tostring(p.trainerName or ""), tostring(nick)) end
    return l1, l2
  end
  local title = ""
  if p.title and p.title ~= 0xFFFF then
    local ok, s = pcall(function() return require("src.pokemon.Gen4EasyChat").toString(data, p.title) end)
    title = ok and s or ""
  end
  T.buffer(self.game, title)
  local l2 = T.resolve(data, bank(), 45, self.game) or title
  if l2 == "" then l2 = title end
  return tostring(p.trainerName or ""), l2
end

-- the photo itself, its stage's top-left at (x, y)
function V.drawPhoto(game, photo, x, y, images)
  local g = love.graphics
  local data = game.data
  local rec = data.gen4_dressup or {}
  images = images or {}
  local function img(key, path)
    if images[key] == nil then
      local ok, im = false, nil
      if path then ok, im = pcall(require("src.render.Assets").image, path) end
      if ok and im then im:setFilter("nearest", "nearest") end
      images[key] = ok and im or false
    end
    return images[key] or nil
  end
  g.setColor(1, 1, 1, 1)
  local bd = rec.backdrops and rec.backdrops[photo.backdrop or 0]
  local bdi = bd and img("bd" .. tostring(photo.backdrop or 0), bd.path)
  if bdi then g.draw(bdi, x, y) end
  -- the Pokemon and the Accessories by their kept priorities, the lowest
  -- first (ov22_0225B388 sets them; a higher one is in front)
  local things = {}
  local mon = photo.mon
  if mon and mon.species then things[#things + 1] = { mon = true, z = photo.monZ or 1000, n = 0 } end
  for i, a in ipairs(photo.accessories or {}) do things[#things + 1] = { acc = a, z = a.z or (999 - i), n = i } end
  table.sort(things, function(a, b)
    if a.z ~= b.z then
      if photo.monZ == nil then return a.n < b.n end
      return a.z < b.z
    end
    return a.n < b.n
  end)
  for _, th in ipairs(things) do
    if th.mon then
      local path = require("src.pokemon.Sprites").path(data, mon.species, "front", { mon = mon, kind = "contest" })
      local mi = path and img("mon:" .. path, path)
      if mi then
        local w, h = mi:getDimensions()
        g.draw(mi, x + (photo.monX or 56) - math.floor(w / 2), y + (photo.monY or 40) - math.floor(h / 2))
      end
    else
      local a = th.acc
      local r = rec.accessories and rec.accessories[a.id]
      local ai = r and img("acc" .. tostring(a.id), r.path)
      if ai then g.draw(ai, x + a.x, y + a.y) end
    end
  end
end

function V:draw()
  local g = love.graphics
  local rec = self.data.gen4_dressup or {}
  local key = self.kind == "contest" and "photo_viewer_contest" or "photo_viewer"
  local frame = rec.photo and rec.photo[key] and load(self, key, rec.photo[key].path)
  g.setColor(0.42, 0.74, 1, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  if self.photo then
    -- the photo under the frame's window
    V.drawPhoto(self.game, self.photo, V.STAGE_X, V.STAGE_Y, self.images)
  end
  -- the name plate (ov22_0225B964: imageclip 233/234/232/231 at (0, 144);
  -- a dress-up photo's sequence 5 moved to (48, 144), a contest photo's
  -- sequence its type: ov22_0225BB00 / _0225BC18)
  local function plate()
    local seq = self.kind == "contest" and ((self.photo and self.photo.contestType) or 0) or 5
    local key = "photo_deco_" .. seq
    local s = rec.sprites and rec.sprites[key]
    local im = s and load(self, key, s.path)
    if im then g.draw(im, (self.kind == "contest" and 0 or 48) + (s.originX or 0), 144 + (s.originY or 0)) end
  end
  -- the frame over it: whatever the dress-up kept is inside the window
  -- (every corner on the stage, the Pokemon held inside it), so nothing of
  -- the photo needs to show over the frame
  if frame then g.draw(frame, 0, 0) end
  plate()
  local l1, l2 = self:lines()
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
  local function centred(s, y)
    local w = Font.width and Font.width(s) or #s * 6
    Font.draw(s, 128 - math.floor(w / 2), y)
  end
  centred(l1, 144 + 7)
  centred(l2, 144 + 27)
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

return V
