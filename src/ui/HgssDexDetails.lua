-- HEARTGOLD / SOULSILVER POKEDEX: THE ENTRY PAGES (overlay 18 states 66-91)
-- that DETAILS (A) opens -- AREA, SIZE, FORMS (with COMPARE) and the
-- "RETURN TO LIST" page -- under the AREA / SIZE / FORMS / BACK bar. Owned
-- by src/ui/HgssPokedex.lua (`dex`); the data is src/ui/HgssDexData.lua.
--
-- READ FROM CODE (pokeheartgold src/application/pokedex/ov18_021E8BF4.c,
-- asm/overlay_18.s):
--   * DETAILS opens AREA (MainSeq_11 case 4 -> 18 -> 66 -> 68 -> 69)
--   * the bar (ov18_021F7B94, rects ov18_021FB704): y 168-183, AREA x 7-57,
--     SIZE x 71-121 (only for a CAUGHT species; greyed otherwise,
--     ov18_021E673C), FORMS x 135-185, BACK x 199-249; B = BACK
--   * the pages wrap left / right: RETURN <- AREA -> SIZE (caught) -> FORMS
--     -> RETURN (ov18_021F7C14 / 7D00 / 7D30 / 7E70)
--   * AREA (ov18_021F7C14, rects ov18_021FB934): the list rows y 40-55 /
--     64-79 / 112-127 / 136-151 move -2 / -1 / +1 / +2 (the middle row
--     88-103 is the current one), the arrows (x 231-252, y 37-52 / 139-154)
--     and the bar (y 53-138); the JOHTO / KANTO tabs (y 6-25, x 70-129 /
--     190-247, only with the National Dex; SELECT toggles, L = JOHTO,
--     R = KANTO); the three time circles (centres (33,77) / (33,109) /
--     (33,141), r 13; A cycles morning -> day -> night); UP / DOWN scroll;
--     the top screen's map (SUB0 scrolled -72 for Johto, +104 for Kanto,
--     ov18_021EE1F8 / EE21C)
--   * FORMS (ov18_021F7D30, rects ov18_021FB804): rows y 8-23 / 32-47 /
--     80-95 / 104-119 = -2 / -1 / +1 / +2 around 56-71, arrows / bar at
--     x 231-252, COMPARE y 134-154 x 134-255 (A), only with more than one
--     form (MainSeq_80 case 11); COMPARE (ov18_021F7DCC, rects
--     ov18_021FB7E0): the two forms' up / down arrows, the two panels
--     (LEFT / RIGHT pick the side), SWITCH (X) flips front / back, CANCEL
--     (A or B) back to FORMS; the two sides never show the same form and
--     only move with three forms or more (ov18_021EDF48 / EDF84)
--   * RETURN TO LIST (page 4, ov18_021F7E70): the button y 72-103 x 48-207
--     or A goes back to the list, as BACK does
--   * the windows (ov18_021F9E4C area, 9DE4 size, 9EBC forms, 9DB0 page 4,
--     tiles) and the words: bank 802 (128 Area Unknown, 129-131 Morning /
--     Day / Night, 65 / 66 JOHTO / KANTO, 136-141 the size checks and the
--     trainer's 4'11" / 88.2 / 90.4 lbs., 142 AREA, 143 SIZE, 168 COMPARE,
--     169 "Compare ...", 170 FORMS, 171 SWITCH, 172 CANCEL, 173 / 174 page
--     4); the forms list per ov18_021E8254 (HgssDexData.forms)
--   * the SIZE figures: zukan_data's per-species scales (256 / scale) and
--     y offsets, the trainer's figure by gender (OBJ 111 / 114, the icons
--     105 / 109)
-- THE AREA LIST AND MARKERS come from zukan_enc when the cache carries
-- `gen4_zukan_enc` (hgss-zukan-enc-v1; HgssDexData.encAreas / encMarker,
-- READ FROM CODE); an older cache still lists places by scanning
-- data.encounters by map name and time of day (Johto / Kanto by the name).
-- NOT DONE / APPROXIMATED: the markers' blend (drawn as plain alpha over the
-- map, INFERRED from G2S_SetBlendAlpha), the page fades,
-- the scroll bars (drawn plainly), the SIZE figures' exact placement, the
-- forms the port does not track per gender (both genders listed when the
-- species has both).

local D = require("src.ui.HgssDexData")

local P = {}
P.__index = P

local floor = math.floor

local function R(t, b, l, r) return { t = t, b = b, l = l, r = r } end
local function inRect(r, x, y) return x >= r.l and x <= r.r and y >= r.t and y <= r.b end

local BAR = { R(168, 183, 7, 57), R(168, 183, 71, 121), R(168, 183, 135, 185), R(168, 183, 199, 249) }
local AREA_ROWS = { { R(40, 55, 82, 221), -2 }, { R(64, 79, 82, 221), -1 }, { R(136, 151, 82, 221), 2 },
  { R(112, 127, 82, 221), 1 }, { R(37, 52, 231, 252), -1 }, { R(139, 154, 231, 252), 1 } }
local AREA_BAR = R(53, 138, 231, 252)
local AREA_TABS = { R(6, 25, 70, 129), R(6, 25, 190, 247) }
local AREA_TIMES = { { 33, 77 }, { 33, 109 }, { 33, 141 } }
local TIME_NAMES = { "morning", "day", "night" }
local FORM_ROWS = { { R(8, 23, 34, 213), -2 }, { R(32, 47, 34, 213), -1 }, { R(104, 119, 34, 213), 2 },
  { R(80, 95, 34, 213), 1 }, { R(5, 20, 231, 252), -1 }, { R(107, 122, 231, 252), 1 } }
local FORM_BAR = R(21, 106, 231, 252)
local COMPARE_BUTTON = R(134, 154, 134, 255)
local CMP = { R(48, 63, 56, 71), R(120, 136, 56, 71), R(48, 63, 184, 199), R(120, 136, 184, 199),
  R(160, 183, 8, 119), R(160, 183, 128, 255), R(67, 116, 2, 114), R(67, 116, 130, 253) }
local RETURN_BUTTON = R(72, 103, 48, 207)

local GREEN, ORANGE, PURPLE, GREY = { 0.13, 0.66, 0.42 }, { 0.94, 0.52, 0.16 }, { 0.72, 0.46, 0.95 }, { 0.62, 0.66, 0.7 }

function P.new(dex, species, page)
  local self = setmetatable({}, P)
  self.dex = dex
  self.game = dex.game
  self.species = species
  self.caught = dex:status(species) == "owned"
  self.time = 0     -- 18C9: 0 morning, 1 day, 2 night
  self.region = 0   -- 18C8: 0 Johto, 1 Kanto
  self.scroll = 0   -- 18CA
  self.formAt = 0   -- 18C5
  self.formB = 1    -- 18C6
  self.side = 0     -- 18C7_0
  self.back = false -- 18C7_7
  self.t = 0
  self.forms = D.forms(self.game, species)
  self.allAreas = D.areas(self.game, species)
  self:setPage(page or "area")
  return self
end

function P:words(i, fallback) return D.text(self.game, 802, i) or fallback end
function P:se(name) self.dex:se(name) end
function P:def() return ((self.game.data or {}).pokemon or {})[self.species] or {} end

function P:areaList()
  -- the cartridge's list out of zukan_enc (HgssDexData.encAreas): row 0 the
  -- whole region, then the places
  if D.encAvailable(self.game) then
    local k = self.time .. ":" .. self.region
    if self.encKey ~= k then self.encRows = D.encAreas(self.game, self.species, self.time, self.region); self.encKey = k end
    return self.encRows
  end
  local want, out = TIME_NAMES[self.time + 1], {}
  for _, rec in ipairs(self.allAreas) do
    if (rec.kanto and 1 or 0) == self.region and rec.times[want] then out[#out + 1] = rec end
  end
  return out
end

function P:setPage(page)
  if page == "size" and not self.caught then return end
  self.page = page
  self.scroll = 0
  if page == "forms" then self.formAt = 0 end
end

-- ------------------------------------------------------------- moves --

function P:moveList(delta)
  if self.page == "area" then
    local n = #self:areaList()
    local to = self.scroll + delta
    if to < 0 or to >= n then return end
    self.scroll = to
  else
    local to = self.formAt + delta
    if to < 0 or to >= #self.forms then return end
    self.formAt = to
  end
  self:se("SEQ_SE_GS_ZKN03")
end

-- ov18_021EDF48: step `which` by dir, skipping the other side's form
function P:stepCompare(which, dir)
  local n = #self.forms
  if n < 3 then return end
  local key, other = which == 0 and "formAt" or "formB", which == 0 and self.formB or self.formAt
  local v = self[key]
  for _ = 1, n do
    v = (v + dir) % n
    if v ~= other then break end
  end
  if v ~= self[key] then self[key] = v; self:se("SEQ_SE_GS_ZKN03") end
end

function P:openCompare()
  if #self.forms <= 1 then return end
  self:se("SEQ_SE_GS_ZKN04")
  self.page = "compare"
  self.side, self.back = 0, false
  self.formB = self.formAt == 0 and 1 or 0
  if self.formB == self.formAt then self.formB = (self.formAt + 1) % #self.forms end
end

function P:exit() self:se("SEQ_SE_GS_GEARCANCEL"); self.dex:closeDetails() end

function P:barTap(x, y)
  for i, r in ipairs(BAR) do
    if inRect(r, x, y) then
      if i == 1 then if self.page ~= "area" then self:se("SEQ_SE_GS_ZKN04"); self:setPage("area") end
      elseif i == 2 then if self.caught and self.page ~= "size" then self:se("SEQ_SE_GS_ZKN04"); self:setPage("size") end
      elseif i == 3 then if self.page ~= "forms" then self:se("SEQ_SE_GS_ZKN04"); self:setPage("forms") end
      else self:exit() end
      return true
    end
  end
  return false
end

-- ------------------------------------------------------------- input --

function P:tap(x, y)
  local page = self.page
  if page == "compare" then
    for i, r in ipairs(CMP) do
      if inRect(r, x, y) then
        if i == 1 then self:stepCompare(0, -1) elseif i == 2 then self:stepCompare(0, 1)
        elseif i == 3 then self:stepCompare(1, -1) elseif i == 4 then self:stepCompare(1, 1)
        elseif i == 5 then self.back = not self.back; self:se("SEQ_SE_GS_ZKN04")
        elseif i == 6 then self:se("SEQ_SE_GS_GEARCANCEL"); self.page = "forms"
        elseif i == 7 or i == 8 then
          if #self.forms >= 3 and self.side ~= i - 7 then self.side = i - 7; self:se("SEQ_SE_GS_ZKN03") end
        end
        return
      end
    end
    return
  end
  if self:barTap(x, y) then return end
  if page == "area" then
    for _, row in ipairs(AREA_ROWS) do if inRect(row[1], x, y) then return self:moveList(row[2]) end end
    if inRect(AREA_BAR, x, y) then
      local n = #self:areaList()
      if n > 1 then
        local to = math.max(0, math.min(n - 1, floor((y - AREA_BAR.t) * n / (AREA_BAR.b - AREA_BAR.t + 1))))
        if to ~= self.scroll then self.scroll = to; self:se("SEQ_SE_GS_ZKN03") end
      end
      return
    end
    if self.dex.hasNational then
      for i, r in ipairs(AREA_TABS) do
        if inRect(r, x, y) and self.region ~= i - 1 then
          self.region, self.scroll = i - 1, 0
          return self:se("SEQ_SE_GS_ZKN04")
        end
      end
    end
    for i, c in ipairs(AREA_TIMES) do
      local dx, dy = x - c[1], y - c[2]
      if dx * dx + dy * dy <= 13 * 13 and self.time ~= i - 1 then
        self.time, self.scroll = i - 1, 0
        return self:se("SEQ_SE_GS_ZKN04")
      end
    end
  elseif page == "forms" then
    for _, row in ipairs(FORM_ROWS) do if inRect(row[1], x, y) then return self:moveList(row[2]) end end
    if inRect(FORM_BAR, x, y) and #self.forms > 1 then
      local n = #self.forms
      local to = math.max(0, math.min(n - 1, floor((y - FORM_BAR.t) * n / (FORM_BAR.b - FORM_BAR.t + 1))))
      if to ~= self.formAt then self.formAt = to; self:se("SEQ_SE_GS_ZKN03") end
      return
    end
    if inRect(COMPARE_BUTTON, x, y) then return self:openCompare() end
  elseif page == "return" then
    if inRect(RETURN_BUTTON, x, y) then return self:exit() end
  end
end

function P:update(pressed, rep)
  self.t = self.t + 1
  local page = self.page
  if page == "compare" then
    if rep("up") then return self:stepCompare(self.side, -1) end
    if rep("down") then return self:stepCompare(self.side, 1) end
    if pressed("left") then if #self.forms >= 3 and self.side ~= 0 then self.side = 0; self:se("SEQ_SE_GS_ZKN03") end return end
    if pressed("right") then if #self.forms >= 3 and self.side ~= 1 then self.side = 1; self:se("SEQ_SE_GS_ZKN03") end return end
    if pressed("x") then self.back = not self.back; return self:se("SEQ_SE_GS_ZKN04") end
    if pressed("a") or pressed("b") then self:se("SEQ_SE_GS_GEARCANCEL"); self.page = "forms" end
    return
  end
  if pressed("b") then return self:exit() end
  local left, right = rep("left"), rep("right")
  if page == "area" then
    if rep("up") then return self:moveList(-1) end
    if rep("down") then return self:moveList(1) end
    if pressed("a") then
      self.time, self.scroll = (self.time + 1) % 3, 0
      return self:se("SEQ_SE_GS_ZKN03")
    end
    if self.dex.hasNational then
      if pressed("select") or (self.region == 0 and pressed("r")) or (self.region == 1 and pressed("l")) then
        self.region, self.scroll = 1 - self.region, 0
        return self:se("SEQ_SE_GS_ZKN03")
      end
    end
    if left then self:se("SEQ_SE_GS_ZKN03"); return self:setPage("return") end
    if right then self:se("SEQ_SE_GS_ZKN03"); return self:setPage(self.caught and "size" or "forms") end
  elseif page == "size" then
    if left then self:se("SEQ_SE_GS_ZKN03"); return self:setPage("area") end
    if right then self:se("SEQ_SE_GS_ZKN03"); return self:setPage("forms") end
  elseif page == "forms" then
    if rep("up") then return self:moveList(-1) end
    if rep("down") then return self:moveList(1) end
    if pressed("a") then return self:openCompare() end
    if left then self:se("SEQ_SE_GS_ZKN03"); return self:setPage(self.caught and "size" or "area") end
    if right then self:se("SEQ_SE_GS_ZKN03"); return self:setPage("return") end
  elseif page == "return" then
    if pressed("a") then return self:exit() end
    if left then self:se("SEQ_SE_GS_ZKN03"); return self:setPage("forms") end
    if right then self:se("SEQ_SE_GS_ZKN03"); return self:setPage("area") end
  end
end

-- -------------------------------------------------------------- draw --

local function fill(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function reset() love.graphics.setColor(1, 1, 1, 1) end

local function grid()
  local g = love.graphics
  g.setColor(1, 1, 1, 1); g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(0.86, 0.88, 0.9, 1)
  for x = 0, 256, 16 do g.rectangle("fill", x, 0, 1, 192) end
  for y = 0, 192, 16 do g.rectangle("fill", 0, y, 256, 1) end
  reset()
end
local function box(r, c)
  local g = love.graphics
  g.setColor(0.35, 0.38, 0.42, 1); g.rectangle("fill", r.l, r.t, r.r - r.l + 1, r.b - r.t + 1, 3, 3)
  fill(c or { 0.97, 0.98, 0.99 }); g.rectangle("fill", r.l + 1, r.t + 1, r.r - r.l - 1, r.b - r.t - 1, 3, 3)
  reset()
end
local function header(dex, c, label)
  local g = love.graphics
  fill(c); g.rectangle("fill", 0, 0, 256, 16); reset()
  dex.ui.put("header", label, 16, 0)
end

-- the bar (fragment 16 = bar_details, at row 20), SIZE greyed when uncaught
function P:drawBar()
  local dex = self.dex
  if not dex:bg("bar_details", 0, 160) then
    local g = love.graphics
    g.setColor(0.2, 0.3, 0.75, 1); g.rectangle("fill", 0, 160, 256, 32); reset()
    local labels = { "AREA", "SIZE", "FORMS", "BACK" }
    for i, r in ipairs(BAR) do box(r); dex.ui.putCentre("dark", labels[i], r.l, r.r + 1, r.t - 1) end
  end
  local current = ({ area = 1, size = 2, forms = 3 })[self.page]
  local g = love.graphics
  if current then
    local r = BAR[current]
    g.setColor(1, 0.85, 0.3, 0.35); g.rectangle("fill", r.l, r.t, r.r - r.l + 1, r.b - r.t + 1)
  end
  if not self.caught then
    g.setColor(0.3, 0.3, 0.3, 0.55); g.rectangle("fill", 64, 160, 64, 32)
  end
  reset()
end

-- a 5-row list centred on `at` (windows at x, y0 + 24 k)
local function drawRows(dex, items, at, x, w, y0, label)
  for k = -2, 2 do
    local item = items[at + k + 1]
    if item then dex.ui.putCentre("dark", label(item), x, x + w, y0 + 24 * (k + 2)) end
  end
end
local function scrollBar(r, at, n, c)
  local g = love.graphics
  fill({ 0.85, 0.88, 0.9 }); g.rectangle("fill", r.l + 6, r.t, 10, r.b - r.t + 1, 4, 4)
  if n > 1 then
    local h = math.max(10, floor((r.b - r.t + 1) / n))
    local y = r.t + floor((r.b - r.t + 1 - h) * at / (n - 1))
    fill(c); g.rectangle("fill", r.l + 6, y, 10, h, 4, 4)
  end
  reset()
end

function P:drawArea()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  local art = dex:bg("area_base", 0, 0)
  art = dex:bg("area_tabs_" .. (dex.hasNational and 1 or 0), 0, 0) or art
  if not art then
    grid()
    box(R(4, 152, 0, 66), { 0.95, 0.97, 0.96 })
    for _, t in ipairs(AREA_TABS) do box(t) end
    box(R(36, 155, 80, 224), { 0.97, 0.99, 0.98 })
    fill({ 0.9, 0.2, 0.2 }); g.rectangle("line", 81, 86, 143, 19); reset()
  end
  if dex.hasNational then
    ui.putCentre("dark", self:words(65, "JOHTO"), 70, 130, 8)
    ui.putCentre("dark", self:words(66, "KANTO"), 190, 248, 8)
    local r = AREA_TABS[self.region + 1]
    g.setColor(0.2, 0.75, 0.45, 0.4); g.rectangle("fill", r.l, r.t, r.r - r.l + 1, r.b - r.t + 1); reset()
  else
    -- window 6 at (144,8): the one region's name in the single box
    ui.putCentre("dark", self:words(65, "JOHTO"), 128, 216, 8)
  end
  -- (4) the time's name; the circles, the chosen one lit
  ui.putCentre("dark", self:words(129 + self.time, TIME_NAMES[self.time + 1]), 8, 56, 40)
  for i, c in ipairs(AREA_TIMES) do
    if i - 1 == self.time then
      fill({ 0.98, 0.78, 0.2 }); g.circle("fill", c[1], c[2], 11)
    elseif not art then
      fill({ 0.62, 0.68, 0.76 }); g.circle("fill", c[1], c[2], 11)
    end
    reset()
    ui.putCentre(i - 1 == self.time and "dark" or "white", ({ "M", "D", "N" })[i], c[1] - 8, c[1] + 8, c[2] - 8)
  end
  local list = self:areaList()
  drawRows(dex, list, self.scroll, 80, 144, 40, function(rec) return rec.label end)
  scrollBar(AREA_BAR, self.scroll, #list, GREEN)
  self:drawBar()
end

function P:drawAreaTop()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  g.setColor(0.86, 0.94, 0.88, 1); g.rectangle("fill", 0, 0, 256, 192); reset()
  local map = dex:pic("area_map")
  if map then
    -- SUB0 under the frame, scrolled -72 (Johto) / +104 (Kanto)
    g.draw(map, self.region == 0 and 72 or -104, 0)
  end
  if not dex:bg("area_top", 0, 0) then
    header(dex, GREEN, "")
    box(R(24, 40, 2, 70)); box(R(104, 140, 2, 70))
    if not map then box(R(24, 182, 66, 250), { 0.9, 0.97, 0.92 }) end
  end
  ui.put("header", self:words(142, "AREA"), 16, 0)
  local def = self:def()
  ui.putCentre("dark", def.name or "", 4, 68, 24)
  dex:icon(self.species, 36, 116, 1, floor(self.t / 8))
  self:drawMarkers()
  local rows = self:areaList()
  if #rows == 0 or (rows[1].all and #rows == 1) then
    if not dex:bg("area_unknown", 80, 88) then box(R(88, 119, 80, 239)) end
    ui.putCentre("dark", self:words(128, "Area Unknown"), 104, 216, 96)
  end
end

-- the map's markers (HgssDexData.encMarker): row 0 shows them all, another
-- row its own; the shown set swaps each blink between the timed places
-- (palette 4) and the special ones (palette 5), fading 15 frames in and 15
-- out (ov18_021EE26C, the OBJ blended over SUB0)
function P:drawMarkers()
  if not D.encAvailable(self.game) then return end
  local enc = self.game.data.gen4_zukan_enc
  local rows = self:areaList()
  local toggle = floor(self.t / 30) % 2
  local k = self.t % 30
  local c = k <= 15 and k or 30 - k
  local want = toggle == 0 and 1 or 2
  local g = love.graphics
  g.setColor(1, 1, 1, math.min(1, c / 15))
  local function put(anim, x, y)
    local rec = enc.art and enc.art[(toggle == 0 and "hg_marker_t_" or "hg_marker_s_") .. anim]
    local img = rec and self.dex:image(rec.path)
    if img then g.draw(img, x + (tonumber(rec.originX) or 0), y + (tonumber(rec.originY) or 0)) end
  end
  local extras = 0
  for i, rec in ipairs(rows) do
    if not rec.all and (self.scroll == 0 or i == self.scroll + 1) then
      local m, extra = D.encMarker(self.game, rec, self.region)
      if m and math.floor(rec.flags / want) % 2 == 1 then
        put(m.anim, m.x, m.y)
        if extra > 0 and math.floor(extras / extra) % 2 == 0 then extras = extras + extra end
      end
    end
  end
  for bitv, spots in pairs(D.ENC_EXTRA) do
    if math.floor(extras / bitv) % 2 == 1 then for _, p in ipairs(spots) do put(0, p[1], p[2]) end end
  end
  reset()
end

function P:sizeOf(key)
  local s = ((self.dex.art or {}).search or {}).size
  local t = s and s[key]
  return t and t[tonumber(self.species)]
end

function P:drawSizeTop()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  local girl = ((self.game.save or {}).player or {}).gender == "girl"
  if not dex:bg("size_top", 0, 0) then
    grid(); header(dex, ORANGE, "")
    box(R(22, 34, 30, 98)); box(R(22, 34, 158, 226)); box(R(46, 60, 72, 184), { 1, 0.9, 0.8 })
    box(R(66, 150, 22, 234), { 0.9, 0.91, 0.93 })
    fill(ORANGE); g.rectangle("fill", 8, 166, 240, 18, 6, 6); reset()
  end
  ui.put("header", self:words(143, "SIZE"), 16, 0)
  ui.putCentre("dark", ((self.game.save or {}).player or {}).name or "", 32, 96, 24)
  local def = self:def()
  ui.putCentre("dark", def.name or "", 160, 224, 24)
  ui.putCentre("dark", self:words(136, "Height Check"), 80, 176, 48)
  -- the two figures, 256 / scale (zukan_data members 3-6), bottoms on the
  -- panel's floor; the y offsets (7-10)
  local suffix = girl and "F" or "M"
  local pScale = self:sizeOf("playerScale" .. suffix) or 256
  local mScale = self:sizeOf("monScale" .. suffix) or 256
  local trainer = dex:pic(girl and "size114_0" or "size111_0")
  local floorY = 150
  if trainer then
    local s = 256 / math.max(1, pScale)
    local w, h = trainer:getDimensions()
    g.draw(trainer, 80 - w * s / 2, floorY - h * s + (self:sizeOf("playerY" .. suffix) or 0) * s, 0, s, s)
  end
  local path = D.formPicture(self.game, self.species, self.forms[1], "front")
  local img = path and dex:image(path)
  if img then
    local s = 256 / math.max(1, mScale)
    local w, h = img:getDimensions()
    g.setColor(0, 0, 0, 1)
    g.draw(img, 176 - w * s / 2, floorY - h * s + (self:sizeOf("monY" .. suffix) or 0) * s, 0, s, s)
    reset()
  end
  ui.put("dark", self:words(girl and 139 or 138, "4'11\""), 56, 168)
  ui.put("dark", D.fmtHeight(D.height(self.game, (dex.art or {}).search, self.species)), 176, 168)
end

function P:drawSize()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  local girl = ((self.game.save or {}).player or {}).gender == "girl"
  if not dex:bg("size_base", 0, 0) then
    grid()
    box(R(8, 24, 88, 168), { 1, 0.9, 0.8 })
    fill(ORANGE); g.rectangle("fill", 8, 134, 240, 18, 6, 6); reset()
  end
  ui.putCentre("dark", self:words(137, "Weight Check"), 80, 176, 8)
  -- the trainer's icon and the Pokemon's on the scale (OBJ 105 / 109)
  if not dex:obj(girl and "size109_0" or "size105_0", 88, 96) then
    fill({ 0.3, 0.3, 0.35 }); g.circle("fill", 88, 96, 10); reset()
  end
  dex:icon(self.species, 168, 96, 1, floor(self.t / 8))
  fill({ 0.55, 0.58, 0.62 }); g.rectangle("fill", 64, 112, 128, 4); reset()
  ui.put("white", self:words(girl and 141 or 140, "88.2 lbs."), 56, 136)
  ui.put("white", D.fmtWeight(D.weight(self.game, (dex.art or {}).search, self.species)), 176, 136)
  self:drawBar()
end

function P:formLabel(i)
  local f = self.forms[i + 1]
  return f and f.label or ""
end

function P:drawFormPicture(form, cx, cy, back)
  local path = D.formPicture(self.game, self.species, form, back and "back" or "front")
  local img = path and self.dex:image(path)
  if not img then return end
  local w, h = img:getDimensions()
  love.graphics.draw(img, cx - floor(w / 2), cy - floor(h / 2))
end

function P:drawFormsTop(compare)
  local dex, ui = self.dex, self.dex.ui
  if not dex:bg(compare and "compare_top" or "forms_top", 0, 0) then
    grid(); header(dex, PURPLE, "")
    box(R(38, 56, 20, 236), { 0.96, 0.93, 1 })
    box(R(72, 162, 22, 100)); box(R(72, 162, 150, 228))
  end
  ui.put("header", self:words(170, "FORMS"), 16, 0)
  local def = self:def()
  if compare then
    local s = self:words(169, "Compare")
    ui.putCentre("dark", (s:gsub("%s*$", "")) .. " " .. (def.name or ""), 32, 224, 40)
    self:drawFormPicture(self.forms[self.formAt + 1], 61, 117, self.back)
    self:drawFormPicture(self.forms[self.formB + 1], 189, 117, self.back)
  else
    ui.putCentre("dark", def.name or "", 56, 200, 40)
    local form = self.forms[self.formAt + 1]
    self:drawFormPicture(form, 61, 117, false)
    self:drawFormPicture(form, 189, 117, true)
  end
end

function P:drawForms()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  local art = dex:bg("forms_base", 0, 0)
  art = dex:bg("forms_front", 0, 0) or art
  if not art then
    grid()
    box(R(6, 122, 30, 218), { 0.98, 0.96, 1 })
    fill({ 0.9, 0.2, 0.2 }); g.rectangle("line", 32, 54, 184, 19); reset()
    box(COMPARE_BUTTON)
  end
  if #self.forms == 1 then
    if not dex:bg("forms_one", 128, 128) then g.setColor(0.6, 0.6, 0.6, 0.6); g.rectangle("fill", 134, 134, 122, 21); reset() end
  else
    ui.putCentre("dark", self:words(168, "COMPARE"), 168, 248, 136)
  end
  drawRows(dex, self.forms, self.formAt, 64, 144, 8, function(f) return f.label end)
  scrollBar(FORM_BAR, self.formAt, #self.forms, PURPLE)
  self:drawBar()
end

function P:drawCompare()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  if not dex:bg("compare_base", 0, 0) then
    grid()
    box(R(12, 28, 88, 168), { 0.96, 0.93, 1 })
    box(CMP[7]); box(CMP[8]); box(CMP[5]); box(CMP[6])
  end
  ui.putCentre("dark", self:words(168, "COMPARE"), 88, 168, 12)
  local side = CMP[7 + self.side]
  g.setColor(0.75, 0.5, 1, 0.35); g.rectangle("fill", side.l, side.t, side.r - side.l + 1, side.b - side.t + 1); reset()
  ui.putCentre("dark", self:formLabel(self.formAt), 0, 128, 84)
  ui.putCentre("dark", self:formLabel(self.formB), 128, 256, 84)
  if #self.forms >= 3 then
    for i = 1, 4 do
      local r = CMP[i]
      local cx, cy = floor((r.l + r.r) / 2), floor((r.t + r.b) / 2)
      fill(PURPLE)
      if i % 2 == 1 then g.polygon("fill", cx - 6, cy + 4, cx + 6, cy + 4, cx, cy - 4)
      else g.polygon("fill", cx - 6, cy - 4, cx + 6, cy - 4, cx, cy + 4) end
      reset()
    end
  end
  ui.putCentre("dark", self:words(171, "SWITCH"), 24, 120, 164)
  ui.putCentre("dark", self:words(172, "CANCEL"), 144, 240, 164)
end

function P:drawReturn()
  local dex, ui = self.dex, self.dex.ui
  if not dex:bg("return_base", 0, 0) then grid(); box(RETURN_BUTTON) end
  ui.putCentre("dark", self:words(174, "RETURN TO LIST"), 64, 208, 80)
  self:drawBar()
end

function P:drawTouch()
  reset()
  if self.page == "area" then self:drawArea()
  elseif self.page == "size" then self:drawSize()
  elseif self.page == "forms" then self:drawForms()
  elseif self.page == "compare" then self:drawCompare()
  else self:drawReturn() end
end

function P:drawTop()
  reset()
  if self.page == "area" then self:drawAreaTop()
  elseif self.page == "size" then self:drawSizeTop()
  elseif self.page == "forms" then self:drawFormsTop(false)
  elseif self.page == "compare" then self:drawFormsTop(true)
  else
    local dex = self.dex
    if not dex:bg("return_top", 0, 0) then grid(); header(dex, GREY, "") end
    dex.ui.put("header", self:words(173, ""), 16, 0)
    -- the entry stays on the top screen behind the page's header
    self:drawFormPicture(self.forms[1], 128, 104, false)
  end
end

return P
