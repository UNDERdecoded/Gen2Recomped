-- THE POKeGEAR MAP'S MARKINGS MODE (Y on a markable place): four icons and
-- four Easy Chat words per place, kept in the save. Opened by
-- src/ui/HgssGearMap.lua.
--
-- READ FROM CODE (pokeheartgold src/application/pokegear/map/
-- overlay_101_021E7FF4.c 439-1060, overlay_101_021EB568.c 790-1145,
-- overlay_101_021E9270.c 805-960, overlay_101_021ED498.c, pokegear_map.c
-- 236-330, include/unk_0202F370.h):
--   * the save: up to 100 places {mapID, icons[4] (15 = none), words[4]
--     (0xFFFF = none)}; a place whose last icon / word goes is dropped
--     (MapMarkingsRAM_IsInUse_EraseIfNot)
--   * the bottom screen: MAIN_3 = NSCR 44 + skin (the icon pool's band),
--     MAIN_2 = NSCR 38 + skin rows 0-13 (the four slots, the trash can at
--     (5, 8) 8 x 5 -- open from (22, 16) while something is held over it --
--     and BACK at (23, 8), pressed from (7, 16)); the place's name at (24,
--     5) (window 7); the slots' icons (map OBJ set A anim 0, frame = icon) at
--     (32 + 104 * (i % 2), 32 + 21 * (i / 2)), their words at (44 + 104 *
--     (i % 2), 25 + 21 * (i / 2)); the pool's eight icons at (40 + 24 * i,
--     132)
--   * the keys (PokegearMap_HandleKeyInput_SelectMarkingsSlot): the cursor
--     walks buttonSpecsMarkingsMenu (slots 0-7 = icon / word of 0..3 in
--     reading order, 8 = BACK); A on BACK or B leaves; A on a set slot
--     holds it (the trash can opens; A throws it away, B puts it back); A
--     on an empty icon slot opens the pool (LEFT / RIGHT walk the eight, A
--     sets the icon and stays, B goes back); A on an empty word slot picks
--     an Easy Chat word
--   * touch: a pool icon dragged onto an icon slot sets it; a set slot
--     dragged onto its own kind's slot swaps them, onto the trash can
--     (68-96, 44-100) throws it away; a tap on an empty word slot picks a
--     word; BACK (64-104, 192-232) leaves
--   * the top screen: the place's icons (OBJ set A, frame = icon) at
--     (32 + 104 * (i % 2), 155 + 21 * (i / 2)) and words in windows 3 / 4
--     ((5, 18) / (18, 18)) at (4, (i / 2) * 21 + 2) -- the screen y is
--     INFERRED from the sprites' world y 203 under a sub surface moved to 240
--     with the 192 the sprite system adds
--   * the map: places carrying markings show set B anim 4 at the place's
--     sprite position (ov101_021E9270.c:515)
--   * the sounds: GEARCURSOR, GEARDECIDE, GEARCANCEL, GEARSEALGRAB /
--     GEARSEALHAMERU (drag / drop), GEARGOMIBAKO (trash)
-- NOT DONE: the panels' slide in / out and the fades, the word OBJ's own
-- plate, the cursor's corner animation (drawn still).

local Font = require("src.render.Font")

local K = {}
K.__index = K

local NULL_ICON, NULL_WORD, MAX = 15, 0xFFFF, 100
K.NULL_ICON, K.NULL_WORD = NULL_ICON, NULL_WORD
local floor = math.floor

-- --------------------------------------------------------------- save --

function K.list(pg)
  pg.markings = pg.markings or {}
  return pg.markings
end

function K.get(pg, mapId)
  for _, n in ipairs(K.list(pg)) do if n.mapId == mapId then return n end end
  return nil
end

function K.getOrCreate(pg, mapId)
  local n = K.get(pg, mapId)
  if n then return n end
  local list = K.list(pg)
  if #list >= MAX then return nil end
  n = { mapId = mapId, icons = { NULL_ICON, NULL_ICON, NULL_ICON, NULL_ICON },
        words = { NULL_WORD, NULL_WORD, NULL_WORD, NULL_WORD } }
  list[#list + 1] = n
  return n
end

function K.inUse(n)
  for i = 1, 4 do
    if n.icons[i] ~= NULL_ICON or n.words[i] ~= NULL_WORD then return true end
  end
  return false
end

function K.remove(pg, node)
  local list = K.list(pg)
  for i, n in ipairs(list) do if n == node then table.remove(list, i); return end end
end

-- ------------------------------------------------------------- layout --

-- buttonSpecsMarkingsMenu: x, y, left / right / up / down neighbours and the
-- cursor's corner offsets {l, r, t, b}
local MENU = {
  [0] = { 0x20, 0x20, 3, 1, 4, 4, -6, 6, -6, 6 },
  { 0x28, 0x1F, 0, 2, 5, 5, 6, 80, -6, 6 },
  { 0x88, 0x20, 1, 3, 6, 6, -6, 6, -6, 6 },
  { 0x90, 0x1F, 2, 0, 8, 7, 6, 80, -6, 6 },
  { 0x20, 0x35, 7, 5, 0, 0, -6, 6, -6, 6 },
  { 0x28, 0x34, 4, 6, 1, 1, 6, 80, -6, 6 },
  { 0x88, 0x35, 5, 7, 2, 2, -6, 6, -6, 6 },
  { 0x90, 0x34, 6, 4, 3, 8, 6, 80, -6, 6 },
  { 0xD0, 0x54, nil, nil, 7, 3, -16, 16, -9, 3 },
}
K.MENU = MENU

local function R(t, b, l, r) return { t = t, b = b, l = l, r = r } end
local function inR(r, x, y) return x >= r.l and x < r.r and y >= r.t and y < r.b end
-- hitboxes {top, bottom, left, right}
local SLOT_HIT = {
  [0] = R(24, 44, 24, 40), R(24, 44, 40, 128), R(24, 44, 128, 144), R(24, 44, 144, 232),
  R(44, 64, 24, 40), R(44, 64, 40, 128), R(44, 64, 128, 144), R(44, 64, 144, 232),
}
local POOL_HIT = {}
for i = 0, 7 do POOL_HIT[i] = R(124, 140, 32 + 24 * i, 48 + 24 * i) end
local BACK_HIT = R(64, 104, 192, 232)
local TRASH_HIT = R(68, 96, 44, 100)
-- icon slot index (0..3) for the hitbox order {0, 2, 4, 6} of the menu
local ICON_SLOTS = { [0] = R(24, 44, 24, 40), R(24, 44, 128, 144), R(44, 64, 24, 40), R(44, 64, 128, 144) }
local WORD_SLOTS = { [0] = R(24, 44, 40, 128), R(24, 44, 144, 232), R(44, 64, 40, 128), R(44, 64, 144, 232) }

function K.slotPos(i) return 32 + 104 * (i % 2), 32 + 21 * floor(i / 2) end
function K.wordPos(i) return 44 + 104 * (i % 2), 25 + 21 * floor(i / 2) end
function K.poolPos(i) return 40 + 24 * i, 132 end

-- ---------------------------------------------------------------- mode --

function K.new(map)
  local self = setmetatable({ map = map, gear = map.gear, game = map.game }, K)
  self.spec = map.spec
  self.cursor = 0
  self.pool = 0
  self.drag = nil        -- "pool" / "set" (PGMAP_DRAG_*)
  self.held = nil        -- keys: the set slot held over the trash can
  self.trash = false
  self.busy = false
  return self
end

function K:pg() return self.gear:save() end
function K:node() return K.get(self:pg(), self.spec.mapId) end
function K:se(name) self.gear:se(name) end

-- MapApp_MarkingSlotIsSet: slot 0..7, even = icon, odd = word
function K:isSet(slot)
  local n = self:node()
  if not n or slot >= 8 then return false end
  local i = floor(slot / 2) + 1
  if slot % 2 == 0 then return n.icons[i] ~= NULL_ICON end
  return n.words[i] ~= NULL_WORD
end

function K:setIcon(i, icon)
  local n = K.getOrCreate(self:pg(), self.spec.mapId)
  if n then n.icons[i + 1] = icon end
end

function K:setWord(i, word)
  local n = K.getOrCreate(self:pg(), self.spec.mapId)
  if n then n.words[i + 1] = word end
end

-- PokegearMap_MarkingsMenu_DeleteSelected: kind 0 icon, 1 word
function K:delete(kind, i)
  local n = self:node()
  if not n then return end
  if kind == 0 then n.icons[i + 1] = NULL_ICON else n.words[i + 1] = NULL_WORD end
  if not K.inUse(n) then K.remove(self:pg(), n) end
end

function K:pickWord(i)
  self:se("SEQ_SE_GS_GEARDECIDE")
  require("src.pokemon.Gen4EasyChat").pick(self.game, function(word)
    if word then self:setWord(i, word) end
  end)
end

function K:exit()
  self:se("SEQ_SE_GS_GEARCANCEL")
  self.map.mark = nil
end

function K:move(dir)
  local spec = MENU[self.cursor]
  local to = spec[2 + dir]
  if to ~= nil then self.cursor = to end
  self:se("SEQ_SE_GS_GEARCURSOR")
end

function K:keys(input)
  if self.drag == "pool" then
    -- PokegearMap_HandleKeyInput_SelectedIconFromPool
    if input:wasPressed("a") then
      self:se("SEQ_SE_GS_GEARDECIDE")
      self:setIcon(floor(self.cursor / 2), self.pool)
    end
    if input:wasPressed("b") then self:se("SEQ_SE_GS_GEARCANCEL"); self.drag = nil; return end
    if input:wasPressed("left") then self.pool = (self.pool + 7) % 8; self:se("SEQ_SE_GS_GEARCURSOR")
    elseif input:wasPressed("right") then self.pool = (self.pool + 1) % 8; self:se("SEQ_SE_GS_GEARCURSOR") end
    return
  end
  if self.drag == "set" then
    -- PokegearMap_HandleKeyInput_SelectedMarkingSlot
    if input:wasPressed("a") then
      self:se("SEQ_SE_GS_GEARGOMIBAKO")
      self:delete(self.cursor % 2, floor(self.cursor / 2))
      self.drag, self.trash = nil, false
    elseif input:wasPressed("b") then
      self:se("SEQ_SE_GS_GEARCANCEL")
      self.drag, self.trash = nil, false
    end
    return
  end
  if input:wasPressed("b") then return self:exit() end
  if input:wasPressed("a") then
    self:se("SEQ_SE_GS_GEARDECIDE")
    if self.cursor == 8 then self.map.mark = nil; return end
    if self:isSet(self.cursor) then
      self.drag, self.trash = "set", true
    elseif self.cursor % 2 == 0 then
      self.drag, self.pool = "pool", 0
    else
      self:pickWord(floor(self.cursor / 2))
    end
    return
  end
  if input:wasPressed("left") then self:move(1)
  elseif input:wasPressed("right") then self:move(2)
  elseif input:wasPressed("up") then self:move(3)
  elseif input:wasPressed("down") then self:move(4) end
end

-- PokegearMap_HandleTouchInput_SelectMarkingsSlot (a new touch)
function K:touch(x, y)
  if self.drag then
    -- a touch while an item is held by keys puts it back (B's path)
    self:se("SEQ_SE_GS_GEARCANCEL")
    self.drag, self.trash = nil, false
    return true
  end
  if inR(BACK_HIT, x, y) then self.backPressed = 8; self:exit(); return true end
  for i = 0, 7 do
    if inR(POOL_HIT[i], x, y) then
      self.touchDrag = { kind = "pool", icon = i, x = x, y = y }
      self.busy = true
      self:se("SEQ_SE_GS_GEARSEALGRAB")
      return true
    end
  end
  for slot = 0, 7 do
    if inR(SLOT_HIT[slot], x, y) then
      local i = floor(slot / 2)
      if self:isSet(slot) then
        local wx, wy = K.wordPos(i)
        self.touchDrag = { kind = "set", slot = slot % 2 == 0 and i or i + 4, x = x, y = y,
          dx = slot % 2 == 1 and (wx - x) or 0, dy = slot % 2 == 1 and (wy - y) or 0 }
        self.busy = true
        self:se("SEQ_SE_GS_GEARSEALGRAB")
      elseif slot % 2 == 1 then
        self:pickWord(i)
      end
      return true
    end
  end
  return true
end

function K:touchMove(x, y)
  local d = self.touchDrag
  if not d then return end
  d.x, d.y = x, y
  if d.kind == "set" then self.trash = inR(TRASH_HIT, x, y) end
end

-- the stylus lifted: PokegearMap_HandleTouchInput_DragItemFromPool /
-- _DragMarkingSlot
function K:touchUp()
  local d = self.touchDrag
  self.touchDrag, self.busy = nil, false
  if not d then return end
  local x, y = d.x, d.y
  if d.kind == "pool" then
    self:se("SEQ_SE_GS_GEARSEALHAMERU")
    for i = 0, 3 do
      if inR(ICON_SLOTS[i], x, y) then self:setIcon(i, d.icon); break end
    end
    return
  end
  if inR(TRASH_HIT, x, y) then
    self:delete(floor(d.slot / 4), d.slot % 4)
    self.trash = false
    self:se("SEQ_SE_GS_GEARGOMIBAKO")
    return
  end
  self.trash = false
  self:se("SEQ_SE_GS_GEARSEALHAMERU")
  local to
  for i = 0, 3 do
    if inR(ICON_SLOTS[i], x, y) then to = i end
    if inR(WORD_SLOTS[i], x, y) then to = i + 4 end
  end
  if not to or floor(to / 4) ~= floor(d.slot / 4) or to == d.slot then return end
  local n = self:node()
  if not n then return end
  local t = floor(to / 4) == 0 and n.icons or n.words
  local a, b = d.slot % 4 + 1, to % 4 + 1
  t[a], t[b] = t[b], t[a]
end

function K:busyUpdate()
  if not self.gear.touchHeld then self:touchUp() end
end

function K:update()
  if self.backPressed then
    self.backPressed = self.backPressed - 1
    if self.backPressed <= 0 then self.backPressed = nil end
  end
end

-- --------------------------------------------------------------- draw --

local function wordText(game, word)
  if word == nil or word == NULL_WORD then return nil end
  local ok, s = pcall(function() return require("src.pokemon.Gen4EasyChat").toString(game.data, word) end)
  return ok and s or nil
end
K.wordText = wordText

function K:drawTouch()
  local gear = self.gear
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local bg = gear:img("map_marks_bg")
  local panel = gear:img("map_marks")
  if bg then gear:tiles(bg, 0, 0, 32, 24, 0, 0) else g.setColor(0.1, 0.2, 0.7, 1); g.rectangle("fill", 0, 0, 256, 192); g.setColor(1, 1, 1, 1) end
  if panel then
    gear:tiles(panel, 0, 0, 32, 14, 0, 0)
    if self.trash then gear:tiles(panel, 22, 16, 8, 5, 5, 8) end
    if self.backPressed then gear:tiles(panel, 7, 16, 6, 5, 23, 8) end
  end
  -- the place's name (window 7)
  Font.draw(self.map:landmarkName(self.spec.mapId), 24, 5)
  local n = self:node()
  local d = self.touchDrag
  for i = 0, 3 do
    local x, y = K.slotPos(i)
    local icon = n and n.icons[i + 1]
    if icon and icon ~= NULL_ICON and not (d and d.kind == "set" and d.slot == i) then gear:obj("mapA", 0, icon, x, y) end
    local word = n and wordText(self.game, n.words[i + 1])
    local wx, wy = K.wordPos(i)
    if word and not (d and d.kind == "set" and d.slot == i + 4) then Font.draw(word, wx, wy) end
  end
  for i = 0, 7 do
    if not (d and d.kind == "pool" and d.icon == i) then
      local x, y = K.poolPos(i)
      gear:obj("mapA", 0, i, x, y)
    end
  end
  -- what the stylus holds
  if d then
    if d.kind == "pool" then gear:obj("mapA", 0, d.icon, d.x, d.y)
    elseif d.slot < 4 then gear:obj("mapA", 0, n.icons[d.slot + 1], d.x, d.y)
    else
      local word = wordText(self.game, n.words[d.slot - 4 + 1])
      if word then Font.draw(word, d.x + d.dx, d.y + d.dy) end
    end
  end
  -- the cursor: four corners (set B 5-8)
  if not d then
    local cx, cy, l, r, t, b
    if self.drag == "pool" then
      cx, cy = K.poolPos(self.pool); l, r, t, b = -8, 8, -8, 8
    elseif self.drag == "set" then
      cx, cy, l, r, t, b = 0x48, 0x54, -18, 18, -12, 6
    else
      local s = MENU[self.cursor]
      cx, cy, l, r, t, b = s[1], s[2], s[7], s[8], s[9], s[10]
    end
    if self.drag then
      -- the slot being worked on keeps its corners, still
      local s = MENU[self.cursor]
      self:corners(s[1], s[2], s[7], s[8], s[9], s[10], true)
    end
    self:corners(cx, cy, l, r, t, b)
  end
end

function K:corners(x, y, l, r, t, b, still)
  local gear = self.gear
  local f = still and 0 or floor((self.map.t or 0) / 16) % 2
  if not gear:obj("mapB", 5, f, x + l, y + t) then
    love.graphics.setColor(1, 0.3, 0.3, 1)
    love.graphics.rectangle("line", x + l + 0.5, y + t + 0.5, r - l - 1, b - t - 1)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  gear:obj("mapB", 6, f, x + r, y + t)
  gear:obj("mapB", 7, f, x + l, y + b)
  gear:obj("mapB", 8, f, x + r, y + b)
end

-- the top screen's strip (map mode and markings mode alike)
function K.drawTop(map, spec)
  if not spec then return end
  local gear = map.gear
  local n = K.get(gear:save(), spec.mapId)
  if not n then return end
  for i = 0, 3 do
    local x, y = 32 + 104 * (i % 2), 155 + 21 * floor(i / 2)
    if n.icons[i + 1] ~= NULL_ICON then gear:obj("mapA", 0, n.icons[i + 1], x, y) end
    local word = wordText(map.game, n.words[i + 1])
    if word then Font.draw(word, (i % 2 == 0 and 40 or 144) + 4, 144 + floor(i / 2) * 21 + 2) end
  end
end

return K
