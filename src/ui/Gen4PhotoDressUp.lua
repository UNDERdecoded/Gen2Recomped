-- THE DRESS-UP PHOTO STUDIO: Platinum's Jubilife TV dressing room
-- (ScrCmd_0A6 -> sub_0203DAC0 -> overlay 22's ov22_02255D44 / _02255E50 /
-- _02256098) and HGSS's Goldenrod Tunnel studio (ScrCmd_154 -> overlay 41's
-- ov41_02246DE0 / _02246F08 / _02247150, the same app with the contest
-- parts stripped). The contest's sixty-second version is
-- src/ui/Gen4ContestDressUp.lua; this is the PHOTO mode.
--
-- READ FROM CODE (pokeplatinum src/overlay022, ov22_02255D44.c unless named):
--   * no timer; at most 10 Accessories on the stage (ov22_02256708(.., 10));
--   * the first visit (the script's third argument) prints bank 385 line 47
--     first (main case 3..5); HGSS bank 215, the same lines;
--   * THE CASE (ov22_02257F50.c): every Accessory the Fashion Case holds is
--     its own sprite, one per copy, strewn at random over the case's
--     108 x 125 inside (ov22_0225804C: 10 + MTRNG % (108 - w), 18 + MTRNG %
--     (125 - h)); the Accessories are split by id into 14 pages
--     (ov22_02257FB0: 0-5, 6-11, 12-17, 18-21, 22-28, 29-33, 34-38, 39-42,
--     43-49, 50-55, 56-60, 61-71, 72-91, 92-99); the arrows turn to the next /
--     previous page that holds something (ov22_02258258), the old page's
--     Accessories falling out and the new one's falling in, 44 px a frame
--     for 3 frames, half of them a frame (ov22_022586C4), and the case's BG
--     swaps between its two looks (129/130 and 131/132) at each turn
--     (ov22_022583A0); the Backdrops page is the owned backdrops' 32 x 32
--     icons nine to a page at (16 + 32c, 24 + 40r) (ov22_02258610);
--   * THE BUTTONS (ov22_02259C58.c ov22_02259DBC): sprites, PREV (8, 144),
--     NEXT (48, 144), ACCESSORIES (96, 144), BACKDROPS (136, 144), DONE
--     (184, 144) with bank 385 line 0 on it; frame 1 while held, 2 for the
--     page that is up (ov22_0225A2D0, ov22_02259D2C);
--   * the stage is the 112 x 129 picture at (136, 16); a thing counts as
--     inside when its corners are in (138..246, 18..143)
--     (ov22_02257BE8 / _02257C04);
--   * LETTING GO (ov22_022589E0.c ov22_02258BB8): all four corners of the
--     Accessory's drawn extent on the stage -> it stays (the eleventh says
--     line 3 and flies back); else its box's two corners over the case -> it
--     stays in the case where it was let go; else one from the stage flies
--     to a random spot in the case, one from the case flies back to where it
--     was (4 frames, ov22_02258F4C);
--   * picking one up names it on the other screen (bank 386 / 388,
--     ov22_02259040);
--   * DRAW ORDER (ov22_022578F4.c): the stage keeps two lists. An Accessory
--     put down where one of the 16 grid points of its extent covers the
--     Pokemon goes to the FRONT of the Pokemon's list, any other to the front
--     of the second list (ov22_02257DEC); the Pokemon, put down, goes to the
--     BACK of its own list (ov22_02258D7C); priorities count down from -1
--     through the Pokemon's list, then 8 lower through the other
--     (ov22_02257B10) -- a higher one is drawn in front. Moving the Pokemon
--     moves everything in its list with it and keeps the lot inside the
--     stage (ov22_02258DAC / ov22_02257D04 / ov22_02257EC8);
--   * the room's BG (BG1, priority 0) is in front of the sprites (BG0, 1)
--     (ov22_022568DC): the frame hides what is outside its windows;
--   * the Pokemon starts centred on (192, 56) (ov22_022590D4);
--   * the Backdrops page: touching a backdrop puts it behind the stage at
--     once (ov22_02258E5C); backdrop 0 is up at the start (ov22_02257C88);
--   * DONE -> the stage slides to (72, 56) (ov22_02256C70) and line 1 "Is
--     your Pokemon all dressed up?" YES/NO; NO slides back (ov22_02256DE0);
--     YES -> line 2 "Would you like to save this design?" YES saves photo 0
--     (ov22_02256F38: the Pokemon's list then the other, each Accessory with
--     its priority, the Pokemon, the trainer, the backdrop), adds the
--     trainer-score event (TRAINER_SCORE_EVENT_UNK_07 / HGSS
--     SCORE_EVENT_POKEMON_DRESSED) and the script gets 1; NO leaves without
--     a photo and the script gets 0 (ov22_02256098, sub_0203DA64);
--   * THE OTHER SCREEN (ov22_0225A428, flags 1|2|4|8 in photo mode): BG
--     224 / 225 / 226, ten hearts at (38 + 18k, 104) filled for each
--     Accessory on the stage (ov22_0225A914 / _0225A9C8), the message window
--     at (2, 19) 27 x 4 tiles.
-- INFERRED / THE PORT'S OWN:
--   * the other screen is drawn through src/ui/SecondScreen.lua only where it
--     does not cover this one (a real second panel or the combined
--     layouts); otherwise its messages come up in a box here;
--   * the confirm view is the 123/124 BG shifted 64 to the left so its
--     window sits on the slid stage;
--   * pad controls (the cartridge is touch only): LEFT / RIGHT choose a thing
--     in the case, UP / DOWN turn the page, A takes out / puts down, B puts
--     back, X switches Accessories / Backdrops, SELECT or Y picks up what is
--     on the stage in turn (the Pokemon last), START is DONE.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")
local Photos = require("src.pokemon.Gen4Photos")

local P = {}
P.__index = P
P.isOpaque = false

function P:uiSize() return 256, 192 end

P.STAGE_X, P.STAGE_Y = 136, 16
P.IN = { l = 138, t = 18, r = 246, b = 143 }        -- ov22_02257BE8
P.CASE_IN = { l = 10, t = 18, r = 118, b = 143 }    -- ov22_02258304
P.CASE_PANEL_X, P.CASE_PANEL_Y = 8, 16
P.MON_CX, P.MON_CY = 192, 56                         -- ov22_022590D4
P.CAP = 10
P.SLIDE_X, P.SLIDE_Y = -64, 40                       -- ov22_02256C70 case 5
P.FALL, P.FALL_STEP, P.FALL_FRAMES = 132, 44, 3      -- ov22_022586C4 / _0225882C
P.FLY_FRAMES = 4                                     -- ov22_02258F4C(.., 4, ..)
-- ov22_02259DBC: sprite position, hit rectangle {x, y, w, h}
P.BTN = {
  next = { sprite = 0, x = 48, y = 144, hit = { 48, 152, 40, 24 } },
  prev = { sprite = 1, x = 8, y = 144, hit = { 8, 152, 40, 24 } },
  acc = { sprite = 2, x = 96, y = 144, hit = { 96, 156, 40, 34 } },
  bd = { sprite = 3, x = 136, y = 144, hit = { 136, 156, 40, 34 } },
  done = { sprite = 4, x = 184, y = 144, hit = { 184, 156, 72, 34 } },
}
-- ov22_02257FB0: the last Accessory id of each case page
P.PAGE_LAST = { 5, 11, 17, 21, 28, 33, 38, 42, 49, 55, 60, 71, 91, 99 }

function P.bank()
  return require("src.import.Gen4ScriptBands").family == "hgss" and 215 or 385
end
local function hgss() return require("src.import.Gen4ScriptBands").family == "hgss" end

function P.pageOf(id)
  for i, last in ipairs(P.PAGE_LAST) do if id <= last then return i - 1 end end
  return #P.PAGE_LAST - 1
end

local function inside(x, y)
  return x >= P.IN.l and x <= P.IN.r and y >= P.IN.t and y <= P.IN.b
end
local function inCase(x, y)
  return x >= P.CASE_IN.l and x <= P.CASE_IN.r and y >= P.CASE_IN.t and y <= P.CASE_IN.b
end
local function rand(n)
  if n <= 0 then return 0 end
  if love and love.math and love.math.random then return love.math.random(0, n - 1) end
  return math.random(0, n - 1)
end

-- an image's opaque extent {l,t,r,b} in its own pixels
local function extent(data, w, h)
  if not data then return { 0, 0, w - 1, h - 1 } end
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
  if r < 0 then return { 0, 0, w - 1, h - 1 } end
  return { l, t, r, b }
end

-- ov22_022577EC's sixteen points of a box {l, t, r, b}
local function gridPoints(l, t, r, b)
  local xs = { l, l + math.floor((r - l) / 3), l + math.floor((r - l) / 3) * 2, r }
  local ys = { t, t + math.floor((b - t) / 3), t + math.floor((b - t) / 3) * 2, b }
  local out = {}
  for _, x in ipairs(xs) do for _, y in ipairs(ys) do out[#out + 1] = { x, y } end end
  return out
end

-- ----------------------------------------------------------------- setup --

-- opts: { mon = party mon, firstTime = bool, onDone = function(saved) }
function P.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, opts = opts, onDone = opts.onDone,
    front = {}, back = {}, placed = {}, held = nil, tab = "acc", queue = {}, mode = "play",
    images = {}, pixels = {}, extents = {}, backdrop = 0, yes = 1, flying = {}, falling = {},
    cursor = 1, caseBg = 0, pressed = nil }, P)
  self.mon = opts.mon
  self.monItem = { kind = "mon" }
  self.front[1] = self.monItem                     -- ov22_022578F4
  self.monX, self.monY = P.MON_CX, P.MON_CY
  -- the case: one sprite per copy, page by id (ov22_022567FC / _022580A4)
  local inv = game.save and game.save.gen4Accessories or {}
  local rec = game.data.gen4_dressup or {}
  self.case = {}
  for p = 0, #P.PAGE_LAST - 1 do self.case[p] = {} end
  for id = 0, 99 do
    local n = tonumber(inv[id]) or 0
    if n > 0 and rec.accessories and rec.accessories[id] then
      for _ = 1, n do
        local w, h = self:accSize(id)
        local it = { kind = "acc", id = id, w = w, h = h }
        it.x, it.y = self:randomCaseSpot(w, h)
        local list = self.case[P.pageOf(id)]
        table.insert(list, 1, it)
      end
    end
  end
  self.accPage = 0
  self.backdrops = {}
  local bds = game.save and game.save.gen4Backdrops or {}
  for k = 0, 17 do
    if bds[k] and rec.backdrops and rec.backdrops[k] then self.backdrops[#self.backdrops + 1] = k end
  end
  self.bdPage = 0
  if opts.firstTime then
    self:say(47)
    if #self.queue > 0 then self.mode = "intro" end
  end
  self:rebuild()
  return self
end

function P:randomCaseSpot(w, h)
  return P.CASE_IN.l + rand(108 - w), P.CASE_IN.t + rand(125 - h)
end

function P:say(index)
  local text = T.resolve(self.data, P.bank(), index, self.game)
  if not text then return end
  for page in (text .. "\f"):gmatch("([^\v\f\r]*)[\v\f\r]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then self.queue[#self.queue + 1] = page end
  end
end

function P:line(index)
  return (T.resolve(self.data, P.bank(), index, self.game) or ""):gsub("[\v\f\r]", "\n")
end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.data, name) end
end

-- the other screen's message window (ov22_0225A628): the name of what was
-- picked up, or a notice
function P:sub(text) self.subMsg = text end

-- ----------------------------------------------------------------- art --

local function loadImage(self, key, path)
  if self.images[key] == nil then
    local ok, img = false, nil
    if path then ok, img = pcall(require("src.render.Assets").image, path) end
    if ok and img then img:setFilter("nearest", "nearest") end
    self.images[key] = ok and img or false
  end
  return self.images[key] or nil
end

local function rec(self) return self.data.gen4_dressup or {} end

function P:accImage(id)
  local r = rec(self).accessories and rec(self).accessories[id]
  return loadImage(self, "acc" .. id, r and r.path)
end

function P:accPixels(id)
  if self.pixels[id] == nil then
    local r = rec(self).accessories and rec(self).accessories[id]
    local ok, d = false, nil
    if r and r.path then ok, d = pcall(require("src.render.Assets").imageData, r.path) end
    self.pixels[id] = ok and d or false
  end
  return self.pixels[id] or nil
end

function P:accSize(id)
  local r = rec(self).accessories and rec(self).accessories[id]
  return r and r.width or 16, r and r.height or 16
end

function P:accExtent(id)
  if not self.extents[id] then
    local w, h = self:accSize(id)
    self.extents[id] = extent(self:accPixels(id), w, h)
  end
  return self.extents[id]
end

function P:screen(key)
  local p = rec(self).photo and rec(self).photo[key]
  return loadImage(self, key, p and p.path)
end

-- a sprite picture and its origin (Gen4DressUp `sprites`)
function P:sprite(key)
  local s = rec(self).sprites and rec(self).sprites[key]
  return loadImage(self, key, s and s.path), s
end
function P:drawSprite(key, x, y)
  local img, s = self:sprite(key)
  if not img then return false end
  love.graphics.draw(img, x + (s.originX or 0), y + (s.originY or 0))
  return true
end

function P:backdropImage(k)
  local b = rec(self).backdrops and rec(self).backdrops[k]
  return loadImage(self, "bd" .. tostring(k), b and b.path)
end

function P:monImage()
  if self.monImg == nil then
    local mon = self.mon
    local path = mon and require("src.pokemon.Sprites").path(self.data, mon.species, "front", { mon = mon, kind = "contest" })
    local okI, img, okD, dat = false, nil, false, nil
    if path then
      okI, img = pcall(require("src.render.Assets").image, path)
      okD, dat = pcall(require("src.render.Assets").imageData, path)
    end
    if okI and img then img:setFilter("nearest", "nearest") end
    self.monImg = okI and img or false
    self.monData = okD and dat or false
  end
  return self.monImg or nil
end

function P:monSize()
  local img = self:monImage()
  if img then return img:getDimensions() end
  return 80, 80
end

function P:monExtent()
  if not self.monExt then
    local w, h = self:monSize()
    self:monImage()
    self.monExt = extent(self.monData or nil, w, h)
  end
  return self.monExt
end

function P:monTopLeft()
  local w, h = self:monSize()
  return self.monX - math.floor(w / 2), self.monY - math.floor(h / 2)
end

-- does the Pokemon have an opaque pixel at (x, y)? (ov22_022592F0)
function P:monAt(x, y)
  local mx, my = self:monTopLeft()
  local w, h = self:monSize()
  local lx, ly = math.floor(x - mx), math.floor(y - my)
  if lx < 0 or ly < 0 or lx >= w or ly >= h then return false end
  if not self.monData then return true end
  local _, _, _, a = self.monData:getPixel(lx, ly)
  return a > 0
end

function P:accAt(it, x, y)
  local lx, ly = math.floor(x - it.x), math.floor(y - it.y)
  if lx < 0 or ly < 0 or lx >= it.w or ly >= it.h then return false end
  local d = self:accPixels(it.id)
  if not d then return true end
  local _, _, _, a = d:getPixel(lx, ly)
  return a > 0
end

-- ----------------------------------------------------------- the stage --

-- the Accessories on the stage, the Pokemon's list first (ov22_02256F38's
-- order), and the priorities of ov22_02257B10
function P:rebuild()
  self.placed = {}
  local z = -1
  for _, it in ipairs(self.front) do
    it.z = z
    z = z - 1
    if it.kind == "acc" then self.placed[#self.placed + 1] = it end
  end
  z = z - 8
  for _, it in ipairs(self.back) do
    it.z = z
    z = z - 1
    self.placed[#self.placed + 1] = it
  end
end

local function removeFrom(list, it)
  for i, v in ipairs(list) do if v == it then table.remove(list, i) return true end end
  return false
end

function P:stageCount() return #self.placed end

-- ov22_02257DEC: on the Pokemon -> the front of its list; else the front of
-- the other
function P:putOnStage(it)
  local e = self:accExtent(it.id)
  local touches = false
  for _, p in ipairs(gridPoints(it.x + e[1], it.y + e[2], it.x + e[3], it.y + e[4])) do
    if self:monAt(p[1], p[2]) then touches = true break end
  end
  it.from, it.home = nil, nil
  table.insert(touches and self.front or self.back, 1, it)
  self:rebuild()
end

-- ov22_02257EC8 / ov22_02257D04: how far the Pokemon's list sticks out of
-- the stage, the largest overshoot on each axis
function P:overshoot()
  local ox, oy = 0, 0
  local function check(l, t, r, b)
    local dx = (P.IN.l - l > 0) and (P.IN.l - l) or ((r - P.IN.r > 0) and -(r - P.IN.r) or 0)
    local dy = (P.IN.t - t > 0) and (P.IN.t - t) or ((b - P.IN.b > 0) and -(b - P.IN.b) or 0)
    if math.abs(dx) > math.abs(ox) then ox = dx end
    if math.abs(dy) > math.abs(oy) then oy = dy end
  end
  for _, it in ipairs(self.front) do
    if it.kind == "mon" then
      local mx, my = self:monTopLeft()
      local e = self:monExtent()
      check(mx + e[1], my + e[2], mx + e[3], my + e[4])
    else
      local e = self:accExtent(it.id)
      check(it.x + e[1], it.y + e[2], it.x + e[3], it.y + e[4])
    end
  end
  return ox, oy
end

-- ov22_02258DAC: the Pokemon and everything in its list move together, kept
-- inside the stage
function P:moveMon(cx, cy)
  local dx, dy = math.floor(cx) - self.monX, math.floor(cy) - self.monY
  local function shift(ddx, ddy)
    self.monX, self.monY = self.monX + ddx, self.monY + ddy
    for _, it in ipairs(self.front) do
      if it.kind == "acc" then it.x, it.y = it.x + ddx, it.y + ddy end
    end
  end
  shift(dx, dy)
  local ox, oy = self:overshoot()
  if ox ~= 0 or oy ~= 0 then shift(ox, oy) end
end

-- ------------------------------------------------------------- the case --

function P:accPages() return #P.PAGE_LAST end
function P:bdPages() return math.max(1, math.ceil(#self.backdrops / 9)) end

-- the things showing in the case now
function P:caseItems()
  if self.tab == "acc" then return self.case[self.accPage] or {} end
  local out = {}
  for i = self.bdPage * 9 + 1, math.min(#self.backdrops, self.bdPage * 9 + 9) do
    local k = self.backdrops[i]
    local slot = (i - 1) % 9                        -- ov22_02258610
    local r, c = math.floor(slot / 3), slot % 3
    out[#out + 1] = { kind = "bd", id = k, x = 8 * (c + 1) + 24 * c + 8, y = 8 * (r + 1) + 32 * r + 16, w = 32, h = 32 }
  end
  return out
end

function P:busy() return #self.falling > 0 end

-- ov22_02258258: the next / previous page that holds something; with the
-- falling turn (ov22_022586C4) and the BG's other look (ov22_022583A0)
function P:turn(dir)
  if self:busy() then return false end
  if self.tab == "bd" then
    local n = self:bdPages()
    if n <= 1 then return false end
    self.bdPage = (self.bdPage + dir) % n
  else
    local n = self:accPages()
    local to
    for step = 1, n - 1 do
      local p = (self.accPage + dir * step) % n
      if #self.case[p] > 0 then to = p break end
    end
    if not to then return false end
    local old = self.case[self.accPage]
    self.accPage = to
    -- the old page falls out, then the new one falls in, half of each a frame
    -- ov22_022588D8(n, 1): the whole old page in one frame; (n, 2): the new
    -- one half a frame
    for i = #old, 1, -1 do
      self.falling[#self.falling + 1] = { item = old[i], out = true, wait = 0, step = 0 }
    end
    local delay = #old > 0 and 1 or 0
    local new = self.case[to]
    local per = math.max(1, math.ceil(#new / 2))
    for i = #new, 1, -1 do
      new[i].fall = -P.FALL
      self.falling[#self.falling + 1] = { item = new[i], wait = delay + math.floor((#new - i) / per), step = 0 }
    end
  end
  self.caseBg = (self.caseBg + 1) % 2
  self.cursor = 1
  se(self, "SEQ_SE_DP_SELECT")
  return true
end

function P:setTab(tab)
  if self.tab == tab or self:busy() then return end
  self.tab = tab
  self.cursor = 1
  se(self, "SEQ_SE_DP_SELECT")
end

function P:take(it, from)
  if not it then return false end
  self.notice = nil
  if it.kind == "bd" then
    self.backdrop = it.id                           -- ov22_02258E5C
    self:sub(T.resolve(self.data, hgss() and 218 or 388, it.id, self.game))
    se(self, "SEQ_SE_DP_SELECT")
    return true
  end
  if from == "case" then removeFrom(self.case[P.pageOf(it.id)], it) end
  it.from, it.home = from, { it.x, it.y }
  self.held = it
  self:sub(T.resolve(self.data, hgss() and 216 or 386, it.id, self.game))   -- ov22_02259040
  se(self, "SEQ_SE_DP_BOX01")
  return true
end

-- back into the case at (x, y), flying there over 4 frames (ov22_02258F4C)
function P:flyHome(it, x, y)
  self.flying[#self.flying + 1] = { item = it, fx = it.x, fy = it.y, tx = x, ty = y, k = 0 }
end

-- ov22_02258BB8: where a let-go Accessory ends up
function P:put()
  local h = self.held
  if not h then return end
  self.held = nil
  if h.kind == "mon" then
    -- ov22_02258D7C: the Pokemon to the back of its own list
    removeFrom(self.front, self.monItem)
    self.front[#self.front + 1] = self.monItem
    self:rebuild()
    se(self, "SEQ_SE_DP_BOX02")
    return
  end
  local e = self:accExtent(h.id)
  local l, t, r, b = h.x + e[1], h.y + e[2], h.x + e[3], h.y + e[4]
  local home = h.home or { self:randomCaseSpot(h.w, h.h) }
  if inside(l, t) and inside(r, t) and inside(l, b) and inside(r, b) then
    if self:stageCount() >= P.CAP then
      se(self, "SEQ_SE_DP_HYUN2")
      self.notice = self:line(3)
      self.noticeTime = 60
      self:sub(self.notice)
      local x, y = home[1], home[2]
      if h.from == "stage" then x, y = self:randomCaseSpot(h.w, h.h) end
      return self:flyHome(h, x, y)
    end
    self:putOnStage(h)
    se(self, "SEQ_SE_DP_BOX01")
    return
  end
  if inCase(h.x, h.y) and inCase(h.x + h.w, h.y + h.h) then
    -- it stays in the case where it was let go
    h.from, h.home = nil, nil
    table.insert(self.case[P.pageOf(h.id)], 1, h)
    se(self, "SEQ_SE_DP_BOX02")
    return
  end
  se(self, "SEQ_SE_DP_HYUN2")
  if h.from == "stage" then
    local x, y = self:randomCaseSpot(h.w, h.h)
    return self:flyHome(h, x, y)
  end
  self:flyHome(h, home[1], home[2])
end

-- the topmost thing on the stage under (x, y): the Pokemon's list from its
-- front, then the other (ov22_02257C20)
function P:pickAt(x, y)
  if not inside(x, y) then return false end
  for _, list in ipairs({ self.front, self.back }) do
    for _, it in ipairs(list) do
      local hit = (it.kind == "mon") and self:monAt(x, y) or (it.kind == "acc" and self:accAt(it, x, y))
      if hit then
        if it.kind == "mon" then
          self.held = it
        else
          removeFrom(list, it)
          self:rebuild()
          self:take(it, "stage")
        end
        return true
      end
    end
  end
  return false
end

-- the topmost thing in the case under (x, y)
function P:caseAt(x, y)
  if not inCase(x, y) then return nil end
  for _, it in ipairs(self:caseItems()) do
    if it.kind == "bd" then
      if x >= it.x and x < it.x + it.w and y >= it.y and y < it.y + it.h then return it end
    elseif self:accAt(it, x, y) then
      return it
    end
  end
  return nil
end

-- ------------------------------------------------------------- finishing --

function P:startConfirm()
  if self.held or self:busy() or #self.flying > 0 then return end
  self.mode = "confirm1"
  self.yes = 1
  se(self, "SEQ_SE_DP_DECIDE")
end

-- ov22_02256F38, positions kept relative to the stage
function P:photoArgs()
  local acc = {}
  for _, p in ipairs(self.placed) do
    acc[#acc + 1] = { id = p.id, x = p.x - P.STAGE_X, y = p.y - P.STAGE_Y, z = p.z }
  end
  local save = self.game.save or {}
  local player = save.player or {}
  return { mon = self.mon, monX = self.monX - P.STAGE_X, monY = self.monY - P.STAGE_Y, monZ = self.monItem.z,
           accessories = acc, backdrop = self.backdrop, trainerName = player.name or save.playerName,
           trainerGender = player.gender == "girl" and 1 or 0 }
end

-- the trainer-score event ov22_02256098 adds when the photo is kept
P.SCORE_EVENT_PT, P.SCORE_EVENT_HGSS = 7, 8

function P:finish(saved)
  self.mode = "done"
  if saved and self.opts.save ~= false and self.game.save then
    Photos.writeDressUp(self.game.save, 0, self:photoArgs())
    pcall(function()
      require("src.pokemon.Gen4GameRecords").score(self.game.save, hgss() and P.SCORE_EVENT_HGSS or P.SCORE_EVENT_PT)
    end)
  end
  self.saved = saved and true or false
  if self.game.stack and self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone(self.saved) end
end

-- -------------------------------------------------------------- updates --

function P:updateYesNo(input, onYes, onNo)
  if input:wasPressed("up") or input:wasPressed("down") then self.yes = 3 - self.yes; se(self, "SEQ_SE_DP_SELECT") end
  if input:wasPressed("a") then
    se(self, "SEQ_SE_DP_SELECT")
    if self.yes == 1 then return onYes() end
    return onNo()
  end
  if input:wasPressed("b") then se(self, "SEQ_SE_DP_SELECT"); return onNo() end
end

-- the animations: the case's turn and things flying home
function P:animate()
  local still = {}
  for _, f in ipairs(self.falling) do
    if f.wait > 0 then
      f.wait = f.wait - 1
      still[#still + 1] = f
    else
      f.step = f.step + 1
      if f.out then
        f.item.fall = (f.item.fall or 0) + P.FALL_STEP
        if f.step >= P.FALL_FRAMES then f.item.fall = nil else still[#still + 1] = f end
      else
        f.item.fall = (f.item.fall or -P.FALL) + P.FALL_STEP
        if f.step >= P.FALL_FRAMES then f.item.fall = nil else still[#still + 1] = f end
      end
    end
  end
  self.falling = still
  local flying = {}
  for _, f in ipairs(self.flying) do
    f.k = f.k + 1
    local t = f.k / P.FLY_FRAMES
    f.item.x = math.floor(f.fx + (f.tx - f.fx) * t)
    f.item.y = math.floor(f.fy + (f.ty - f.fy) * t)
    if f.k >= P.FLY_FRAMES then
      f.item.from, f.item.home = nil, nil
      table.insert(self.case[P.pageOf(f.item.id)], 1, f.item)
    else
      flying[#flying + 1] = f
    end
  end
  self.flying = flying
end

function P:update(dt)
  local input = self.game.input
  self:animate()
  if self.noticeTime then
    self.noticeTime = self.noticeTime - 1
    if self.noticeTime <= 0 then self.noticeTime, self.notice = nil, nil end
  end
  if self.pressed then
    self.pressed.t = self.pressed.t - 1
    if self.pressed.t <= 0 then self.pressed = nil end
  end
  if self.mode == "intro" then
    if input:wasPressed("a") or input:wasPressed("b") then
      table.remove(self.queue, 1)
      if #self.queue == 0 then self.mode = "play" end
    end
    return
  end
  if self.mode == "confirm1" then
    return self:updateYesNo(input, function() self.mode = "confirm2"; self.yes = 1 end,
      function() self.mode = "play" end)
  end
  if self.mode == "confirm2" then
    return self:updateYesNo(input, function() self:finish(true) end, function() self:finish(false) end)
  end
  if self.mode ~= "play" then return end
  if input:wasPressed("start") then self:press("done") return self:startConfirm() end
  if input:wasPressed("x") and not self.held then
    local to = self.tab == "acc" and "bd" or "acc"
    self:press(to)
    return self:setTab(to)
  end
  if self.held and not self.dragging then
    local s = 2
    local dx, dy = 0, 0
    if input:isDown("left") then dx = -s end
    if input:isDown("right") then dx = s end
    if input:isDown("up") then dy = -s end
    if input:isDown("down") then dy = s end
    if self.held.kind == "mon" then
      self:moveMon(self.monX + dx, self.monY + dy)
      if input:wasPressed("a") or input:wasPressed("b") then self:put() end
      return
    end
    self.held.x, self.held.y = self.held.x + dx, self.held.y + dy
    if input:wasPressed("a") then self:put() end
    if input:wasPressed("b") then
      -- straight back
      local h = self.held
      self.held = nil
      se(self, "SEQ_SE_DP_HYUN2")
      local x, y = (h.home or {})[1], (h.home or {})[2]
      if h.from ~= "case" or not x then x, y = self:randomCaseSpot(h.w, h.h) end
      self:flyHome(h, x, y)
    end
    return
  end
  if input:wasPressed("select") or input:wasPressed("y") then
    -- the stage's things in turn, the Pokemon last
    local it = self.placed[1]
    if it then
      removeFrom(self.front, it)
      removeFrom(self.back, it)
      self:rebuild()
      self:take(it, "stage")
    else
      self.held = self.monItem
    end
    return
  end
  local items = self:caseItems()
  if input:wasPressed("up") then self:press("prev"); self:turn(-1) return end
  if input:wasPressed("down") then self:press("next"); self:turn(1) return end
  if #items > 0 then
    if input:wasPressed("right") then self.cursor = self.cursor % #items + 1 end
    if input:wasPressed("left") then self.cursor = (self.cursor - 2) % #items + 1 end
    self.cursor = math.max(1, math.min(#items, self.cursor))
    if input:wasPressed("a") and not self:busy() then
      local it = items[self.cursor]
      if it.kind == "acc" and self:take(it, "case") then
        -- a pad's pick lands mid-stage, ready to be moved
        it.x = math.floor((P.IN.l + P.IN.r) / 2 - it.w / 2)
        it.y = math.floor((P.IN.t + P.IN.b) / 2 - it.h / 2)
      elseif it.kind == "bd" then
        self:take(it, "case")
      end
    end
  end
end

-- a button shown held for a few frames
function P:press(name) self.pressed = { name = name, t = 6 } end

-- touch / mouse, in the screen's own 256x192
local function toUi(px, py)
  local rect = require("src.render.Renderer").uiPresentation
  if not rect then return px, py end
  return (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
end

local function hitRect(r, x, y) return x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] end

function P:touchpressed(id, px, py)
  if self.mode == "intro" then
    table.remove(self.queue, 1)
    if #self.queue == 0 then self.mode = "play" end
    return true
  end
  local x, y = toUi(px, py)
  if self.mode == "confirm1" or self.mode == "confirm2" then
    local yb, nb = { 200, 48, 48, 16 }, { 200, 64, 48, 16 }
    if hitRect(yb, x, y) then self.yes = 1 end
    if hitRect(nb, x, y) then self.yes = 2 end
    if hitRect(yb, x, y) or hitRect(nb, x, y) then
      if self.mode == "confirm1" then
        if self.yes == 1 then self.mode = "confirm2"; self.yes = 1 else self.mode = "play" end
      else
        self:finish(self.yes == 1)
      end
    end
    return true
  end
  if self.mode ~= "play" or self.held then return self.mode == "play" end
  local B = P.BTN
  if hitRect(B.done.hit, x, y) then self:press("done"); self:startConfirm() return true end
  if hitRect(B.acc.hit, x, y) then self:press("acc"); self:setTab("acc") return true end
  if hitRect(B.bd.hit, x, y) then self:press("bd"); self:setTab("bd") return true end
  if hitRect(B.prev.hit, x, y) then self:press("prev"); self:turn(-1) return true end
  if hitRect(B.next.hit, x, y) then self:press("next"); self:turn(1) return true end
  if not self:busy() then
    local it = self:caseAt(x, y)
    if it then
      if self:take(it, "case") and it.kind == "acc" then
        self.dragging = { id = id, dx = it.x - x, dy = it.y - y }
      end
      return true
    end
  end
  if self:pickAt(x, y) then
    if self.held.kind == "mon" then
      self.dragging = { id = id, dx = self.monX - x, dy = self.monY - y }
    else
      self.dragging = { id = id, dx = self.held.x - x, dy = self.held.y - y }
    end
    return true
  end
  return true
end

function P:touchmoved(id, px, py)
  local d = self.dragging
  if not (d and d.id == id and self.held) then return false end
  local x, y = toUi(px, py)
  if self.held.kind == "mon" then
    self:moveMon(x + d.dx, y + d.dy)
  else
    self.held.x, self.held.y = math.floor(x + d.dx), math.floor(y + d.dy)
  end
  return true
end

function P:touchreleased(id)
  local d = self.dragging
  if d and d.id == id then
    self.dragging = nil
    self:put()
  end
  return true
end

-- ---------------------------------------------------------------- draws --

local function ink() Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } }) end
local function white() Font.popStyle() end

function P:drawStage(ox, oy)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local bd = self:backdropImage(self.backdrop)
  if bd then g.draw(bd, P.STAGE_X + ox, P.STAGE_Y + oy) end
end

-- the stage's sprites, lowest priority first
function P:drawThings(ox, oy)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local all = {}
  for _, it in ipairs(self.front) do all[#all + 1] = it end
  for _, it in ipairs(self.back) do all[#all + 1] = it end
  table.sort(all, function(a, b) return (a.z or 0) < (b.z or 0) end)
  for _, it in ipairs(all) do
    if it.kind == "mon" then
      local mon = self:monImage()
      local mx, my = self:monTopLeft()
      if mon then g.draw(mon, mx + ox, my + oy) end
    else
      local img = self:accImage(it.id)
      if img then g.draw(img, it.x + ox, it.y + oy) end
    end
  end
end

function P:drawFill()
  local g = love.graphics
  local f = rec(self).photoFill
  if f then g.setColor(f[1] / 255, f[2] / 255, f[3] / 255, 1) else g.setColor(1, 0.23, 0.68, 1) end
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
end

function P:drawCase()
  local g = love.graphics
  local panel = self:screen(self.caseBg == 0 and "photo_case_acc" or "photo_case_bd")
  if panel then g.draw(panel, P.CASE_PANEL_X, P.CASE_PANEL_Y)
  else g.setColor(0.5, 0.9, 0.8, 1); g.rectangle("fill", P.CASE_IN.l, P.CASE_IN.t, 108, 125); g.setColor(1, 1, 1, 1) end
  -- the old page still falling out
  for _, f in ipairs(self.falling) do
    if f.out and f.item.fall then
      local img = self:accImage(f.item.id)
      if img then g.draw(img, f.item.x, f.item.y + f.item.fall) end
    end
  end
  local items = self:caseItems()
  -- drawn back to front: the list's first is the front (ov22_022581EC)
  for i = #items, 1, -1 do
    local it = items[i]
    g.setColor(1, 1, 1, 1)
    if it.kind == "acc" then
      local img = self:accImage(it.id)
      if img then g.draw(img, it.x, it.y + (it.fall or 0)) end
    else
      if not self:drawSprite("photo_bdicon_" .. it.id, it.x, it.y) then
        local img = self:backdropImage(it.id)
        if img then g.draw(img, it.x, it.y, 0, 32 / img:getWidth(), 32 / img:getHeight()) end
      end
    end
  end
  -- the pad's choice
  local it = items[self.cursor]
  if it and self.mode == "play" and not self.held and not self:busy() then
    g.setColor(1, 0.3, 0.3, 1)
    g.rectangle("line", it.x - 1.5, it.y - 1.5, it.w + 3, it.h + 3)
  end
  g.setColor(1, 1, 1, 1)
end

-- the five button sprites (ov22_02259DBC)
function P:drawButtons()
  local g = love.graphics
  for name, b in pairs(P.BTN) do
    local frame = 0
    if (name == "acc" and self.tab == "acc") or (name == "bd" and self.tab == "bd") then frame = 2 end
    if self.pressed and self.pressed.name == name then frame = (name == "acc" or name == "bd") and 2 or 1 end
    if not self:drawSprite(("photo_btn_%d_%d"):format(b.sprite, frame), b.x, b.y) then
      g.setColor(0.95, 0.85, 0.95, 1)
      g.rectangle("fill", b.hit[1], b.hit[2], b.hit[3], b.hit[4], 4, 4)
      g.setColor(1, 1, 1, 1)
    end
    if name == "done" then
      -- the label (FontOAM at y 15, 19 while held: ov22_0225A2F4)
      local label = self:line(0)
      if label == "" then label = "DONE!" end
      local w = Font.width and Font.width(label) or #label * 6
      local dy = (self.pressed and self.pressed.name == "done") and 19 or 15
      Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.55, 0.2, 0.35 } })
      Font.draw(label, b.x + math.floor((72 - w) / 2), b.y + dy)
      Font.popStyle()
    end
  end
  g.setColor(1, 1, 1, 1)
end

function P:drawMessage(text)
  local g = love.graphics
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then
    Font.drawDialogueBox(1, 18, 29, 6)
  else
    g.setColor(1, 1, 1, 1); g.rectangle("fill", 8, 144, 240, 44)
  end
  ink()
  local y = 152
  for l in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
  white()
end

function P:drawYesNo()
  local g = love.graphics
  if Font.drawStandardBox then Font.drawStandardBox(24, 5, 8, 6)
  else g.setColor(1, 1, 1, 1); g.rectangle("fill", 192, 40, 64, 48) end
  ink()
  local Strings = require("src.core.Strings")
  local labels = { Strings("YES"), Strings("NO") }
  for i = 1, 2 do
    local y = 48 + (i - 1) * 16
    Font.draw(labels[i], 212, y)
    if self.yes == i then Font.drawCode(require("src.ui.Theme").cursor, 200, y) end
  end
  white()
end

-- THE OTHER SCREEN (ov22_0225A428): BG 224, the ten hearts, the message
-- window. Drawn through SecondScreen where it has a surface of its own.
function P:subShown()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not (okS and type(SS) == "table" and SS.mode) then return false end
  local mode = SS.mode(self.game)
  local own = mode == "display" or (SS.combined and SS.combined(self.game))
  return own and not (SS.stowed and SS.stowed(self.game)) or false, SS
end

function P:subLine()
  if self.mode == "intro" then return self.queue[1] end
  return self.notice or self.subMsg
end

function P:drawSub()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local bg = self:screen("photo_sub")
  if bg then g.draw(bg, 0, 0) else g.setColor(1, 0.6, 0.8, 1); g.rectangle("fill", 0, 0, 256, 192); g.setColor(1, 1, 1, 1) end
  local n = self:stageCount() + ((self.held and self.held.kind == "acc") and 1 or 0)
  for k = 0, P.CAP - 1 do
    self:drawSprite(k < n and "photo_slot_0" or "photo_slot_1", 38 + 18 * (k % 10) - 8, 104 + 18 * math.floor(k / 10) - 8)
  end
  local text = self:subLine()
  if text and text ~= "" then
    if Font.drawDialogueBox then Font.drawDialogueBox(1, 18, 29, 6) end
    ink()
    local y = 152
    for l in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    white()
  end
  g.setColor(1, 1, 1, 1)
end

function P:draw()
  local g = love.graphics
  local shown, SS = self:subShown()
  self:drawFill()
  if self.mode == "confirm1" or self.mode == "confirm2" or self.mode == "done" then
    -- the slid view (ov22_02256C70): the stage at (72, 56)
    self:drawStage(P.SLIDE_X, P.SLIDE_Y)
    self:drawThings(P.SLIDE_X, P.SLIDE_Y)
    local bg = self:screen("photo_confirm")
    if bg then g.draw(bg, P.SLIDE_X, 0); g.draw(bg, P.SLIDE_X + 256, 0) end
    self:drawYesNo()
    -- the confirm prompts sit at the top (ov22_022574CC: window 2,1 27x2)
    if Font.drawStandardBox then Font.drawStandardBox(1, 0, 30, 4) end
    ink()
    Font.draw(self:line(self.mode == "confirm2" and 2 or 1), 16, 8)
    white()
    g.setColor(1, 1, 1, 1)
  else
    self:drawStage(0, 0)
    self:drawCase()
    self:drawThings(0, 0)
    -- what is held, then what flies home: sprites on the same 3D layer
    for _, f in ipairs(self.flying) do
      local img = self:accImage(f.item.id)
      if img then g.draw(img, f.item.x, f.item.y) end
    end
    if self.held and self.held.kind == "acc" then
      local img = self:accImage(self.held.id)
      if img then g.draw(img, self.held.x, self.held.y) end
    end
    -- the room's BG over the sprites (BG1 priority 0, ov22_022568DC)
    local bg = self:screen("photo_room")
    if bg then g.draw(bg, 0, 0) end
    self:drawButtons()
    if not shown then
      local text = (self.mode == "intro" and self.queue[1]) or self.notice
      if text then self:drawMessage(text) end
    end
  end
  if shown and SS then SS.draw(self.game, function() self:drawSub() end) end
  g.setColor(1, 1, 1, 1)
end

return P
