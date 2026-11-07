-- BLACK AND WHITE'S POKEMON SUMMARY, over HGSS's (src/ui/HgssSummaryMenu.lua)
-- for the moves' details, switching and the move-learning answer, and through
-- it Platinum's for the species, dex number, types, HP / EXP arithmetic and
-- the picture. The art is /a/0/7/8's (src/import/Gen5SummaryArt.lua); the
-- words are bank 158 (numbered as HGSS's 302), the memo bank 188, abilities
-- 182 / 183.
--
-- TWO PAGES, as Bulbapedia's captures of the cartridge show them:
--
--   page      top screen                           touch screen
--   STATUS    the memo: nature, met date / place,  the info grid, the
--             met level, characteristic            Pokemon's panel, item, EXP
--   SKILLS    the stats with the HP bar, ability   the four moves as capsules
--
-- The Pokemon's panel (ball, name, gender, level, the picture, the item) is on
-- the touch screen on both. A or a tap on a move shows its details on the top
-- screen in place of the stats; A on one move then another switches them.
-- Learning a move (`choose`): a fifth capsule holds the offered move.
--
-- Keys: left / right pages, up / down the party, B leaves; SELECT shows the
-- other screen on one screen.
--
-- MEASURED off the captures, there being no symbols: every position. The SKILLS
-- top and its move details are screens 73 / 74 with the <<STATS>> / <<BATTLE
-- MOVES>> strips 75 / 76 (the drawn panels are only a fallback). STAND-IN,
-- said so: the caught ball is its item icon at half size; the foot's page
-- icons are not found (the page in view is outlined).

local HgssSummaryMenu = require("src.ui.HgssSummaryMenu")
local Font = require("src.render.Font")
local Party = require("src.pokemon.Party")
local SecondScreen = require("src.ui.SecondScreen")

local Gen5SummaryMenu = setmetatable({}, { __index = HgssSummaryMenu })
Gen5SummaryMenu.__index = Gen5SummaryMenu
Gen5SummaryMenu.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local BANK, MEMO = 158, 188

-- touch: the info grid
local INFO_LABEL_X, INFO_VALUE_X = 17, 80
local INFO_ROW = { 11, 27, 43, 58, 74 }
local EXP_LABEL_Y, EXP_VALUE_Y, NEXT_LABEL_Y, NEXT_VALUE_Y, EXP_RIGHT, NEXT_RIGHT = 90, 106, 122, 138, 97, 92
local EXP_BAR = { 76, 155, 64, 3 }
-- touch: the Pokemon's panel
local BALL_AT, NAME_AT, GENDER_RIGHT, LV_AT = { 166, 8 }, { 177, 3 }, 248, { 160, 20 }
local PICTURE_AT, ITEM_LABEL, ITEM_VALUE = { 200, 103 }, { 157, 139 }, { 157, 155 }
-- touch: the moves
-- the capsule cell is 136 x 40 with its art in rows 7..40
local CAPSULE_X, CAPSULE_Y, CAPSULE_PITCH = 8, 9, 32
local MOVE_NAME_DX, MOVE_NAME_DY, PP_DX, PP_DY, PP_RIGHT_DX = 43, 11, 52, 29, 117
-- top: memo and stats
local MEMO_X, MEMO_Y = 32, 42
local STAT_LABEL_X, HP_LABEL_X, STAT_RIGHT, HP_RIGHT = 60, 82, 169, 184
local STAT_ROW = { 34, 59, 74, 90, 107, 123 }
local HP_BAR = { 133, 51, 48, 3 }
local VALUE_COLUMN = { 117, 28, 67, 110 }
local ABILITY_BOX = { 34, 138, 166, 50 }
local ABILITY_LABEL, ABILITY_VALUE_X, ABILITY_DESC_Y = { 53, 141 }, 112, 158
local FOOT_CLOSE, FOOT_BACK = { 188, 164 }, { 220, 164 }
local CLOSE_RECT, BACK_RECT = { 168, 191, 196, 219 }, { 168, 191, 228, 255 }
local PAGE_RECTS = { { 168, 191, 4, 35 }, { 168, 191, 43, 74 } }

local INK = {
  label = { text = { 1, 1, 1 }, shadow = { 0.25, 0.25, 0.30 } },
  value = { text = { 0.16, 0.16, 0.18 }, shadow = { 0.70, 0.70, 0.72 } },
  blue = { text = { 0.10, 0.35, 0.90 }, shadow = { 0.65, 0.75, 0.95 } },
  red = { text = { 0.85, 0.15, 0.15 }, shadow = { 0.95, 0.70, 0.70 } },
}

local function inRect(r, p) return p.y >= r[1] and p.y <= r[2] and p.x >= r[3] and p.x <= r[4] end

function Gen5SummaryMenu.new(game, arg)
  local self = HgssSummaryMenu.new(game, arg)
  setmetatable(self, Gen5SummaryMenu)
  self.bw = (game.data or {}).gen5_summary_art or {}
  self.ink = INK
  return self
end

function Gen5SummaryMenu:w(index, fallback)
  local text = ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(BANK, index)]
  if type(text) ~= "string" or text == "" then return fallback end
  return (text:gsub("{[^}]*}", ""))
end

function Gen5SummaryMenu:memoWord(index)
  local text = ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(MEMO, index)]
  return type(text) == "string" and text ~= "" and text or nil
end

function Gen5SummaryMenu:bwImg(key)
  local rec = self.bw[key]
  if type(rec) ~= "table" then return nil end
  return self:image(rec.path), rec
end

-- THE UNOVA DEX: national 494 (Victini, No. 000) .. 649 in order, which is
-- what the summary shows until the National Pokedex is had
function Gen5SummaryMenu:dexNumber()
  local def = self:speciesDef()
  local national = tonumber(def and (def.dex or def.id)) or tonumber(self.mon.species)
  local dex = (self.game.save or {}).pokedex or {}
  if national and not dex.national and national >= 494 and national <= 649 then return national - 494 end
  return national
end

function Gen5SummaryMenu:pagesShown()
  if Party.isEgg(self.mon) then return { 1 } end
  return { 1, 2 }
end

-- ------------------------------------------------------------- the memo --

function Gen5SummaryMenu:memoLines()
  local mon, data = self.mon, self.game.data
  local lines = {}
  local nature = mon.personality and mon.personality % 25
  if nature == nil then
    for i, name in ipairs((data.constants or {}).natureOrder or {}) do
      if name == mon.nature then nature = i - 1; break end
    end
  end
  if nature then lines[#lines + 1] = self:memoWord(nature) end
  local met = self:memoWord(25)
  if met then
    local d = type(mon.metDate) == "table" and mon.metDate or {}
    local year, month, day = tonumber(d.year or mon.metYear), tonumber(d.month or mon.metMonth), tonumber(d.day or mon.metDay)
    local place = mon.metLocation
    local map = type(place) == "string" and (data.maps or {})[place]
    place = (map and (map.name or map.displayName)) or (type(place) == "string" and place) or nil
    local k = 0
    for line in (met .. "\n"):gmatch("([^\n]*)\n") do
      k = k + 1
      if k == 1 and year and month and day then
        lines[#lines + 1] = ("%d/%d/20%02d"):format(month, day, year % 100)
      elseif k == 2 and place then
        lines[#lines + 1] = place
      elseif k == 3 and mon.metLevel then
        lines[#lines + 1] = (line:gsub("{CMD 0202 3}", tostring(mon.metLevel)))
      end
    end
  end
  if type(mon.ivs) == "table" then
    local names = { "hp", "attack", "defense", "speed", "spAttack", "spDefense" }
    local start = (tonumber(mon.personality) or 0) % 6
    local best, bestValue = start, -1
    for step = 0, 5 do
      local slot = (start + step) % 6
      local value = tonumber(mon.ivs[names[slot + 1]]) or 0
      if value > bestValue then best, bestValue = slot, value end
    end
    lines[#lines + 1] = self:memoWord(53 + best * 5 + bestValue % 5)
  end
  for i, l in ipairs(lines) do lines[i] = (tostring(l):gsub("{[^}]*}", "")) end
  return lines
end

-- -------------------------------------------------------------- input --

function Gen5SummaryMenu:update()
  self.t = (self.t or 0) + 1
  local tap = self.tapAt
  self.tapAt = nil
  if self.moveMode then return self:moveInput(self.game.input, tap) end
  if tap then
    if inRect(CLOSE_RECT, tap) or inRect(BACK_RECT, tap) then return self:close() end
    for i, r in ipairs(PAGE_RECTS) do if inRect(r, tap) then return self:setPage(i) end end
    if self.hgPage == 2 then
      for i = 1, 4 do
        local y = CAPSULE_Y + (i - 1) * CAPSULE_PITCH
        if tap.x >= CAPSULE_X and tap.x <= CAPSULE_X + 136 and tap.y >= y + 7 and tap.y < y + 40 and (self.mon.moves or {})[i] then
          self.moveMode, self.moveIndex = true, i
          return self:sfx("SEQ_SE_DP_SYU01")
        end
      end
    end
    return
  end
  return HgssSummaryMenu.update(self)
end

function Gen5SummaryMenu:moveInput(input, tap)
  local count = self:moveCount()
  if tap then
    for i = 1, count do
      local y = CAPSULE_Y + (i - 1) * CAPSULE_PITCH
      if tap.x >= CAPSULE_X and tap.x <= CAPSULE_X + 136 and tap.y >= y + 7 and tap.y < y + 40 then
        if i == self.moveIndex or self.choose or self.swapMove then return self:pickMove(i) end
        self.moveIndex = i
        return self:sfx("SEQ_SE_DP_SELECT")
      end
    end
    if inRect(BACK_RECT, tap) or inRect(CLOSE_RECT, tap) then
      if self.choose then return self:answer(nil) end
      self.moveMode, self.swapMove = nil, nil
    end
    return
  end
  return HgssSummaryMenu.moveInput(self, input, nil)
end

-- --------------------------------------------------------------- draw --

function Gen5SummaryMenu:drawPanelColumn()
  local mon = self.mon
  local egg = Party.isEgg(mon)
  local g = love.graphics
  -- the caught ball: its item icon at half size (STAND-IN for the sprite)
  local ball = tonumber(mon.caughtBall or mon.ball or mon.pokeball) or 4
  local icon = self:img(("items/icon_%03d"):format(ball))
  g.setColor(1, 1, 1, 1)
  if icon then g.draw(icon, BALL_AT[1] - 8, BALL_AT[2] - 8, 0, 0.5, 0.5) end
  local def = self:speciesDef()
  self:put("label", egg and "Egg" or mon.nickname or (def and def.name) or tostring(mon.species), NAME_AT[1], NAME_AT[2])
  if not egg then
    local gender = require("src.pokemon.DayCare").gender(self.game.data, mon)
    if gender == "male" or gender == "female" then
      self:putRight(gender == "male" and "blue" or "red", self:w(gender == "male" and 1 or 2, gender == "male" and "♂" or "♀"), GENDER_RIGHT, NAME_AT[2])
    end
    local lv = self:w(3, "Lv. ") or "Lv. "
    self:put("value", (lv:gsub("%s*$", " ")) .. tostring(tonumber(mon.level) or 1), LV_AT[1], LV_AT[2])
  end
  local image, flip = self:pictureArt()
  if image then
    local w, h = image:getDimensions()
    g.setColor(1, 1, 1, 1)
    g.draw(image, PICTURE_AT[1], PICTURE_AT[2], 0, flip and -1 or 1, 1, w / 2, h / 2)
  end
  if not egg then
    self:put("label", self:w(4, "Item"), ITEM_LABEL[1] + 4, ITEM_LABEL[2])
    local held = mon.item or mon.heldItem
    local item = held and self.game.data.items and self.game.data.items[held]
    self:put("value", (item and item.name) or self:w(6, "None"), ITEM_VALUE[1], ITEM_VALUE[2])
  end
end

function Gen5SummaryMenu:drawInfoTouch()
  local mon, def = self.mon, self:speciesDef()
  if Party.isEgg(mon) then return end
  local number = self:dexNumber()
  local player = (self.game.save or {}).player or {}
  local otFemale = mon.otGender == 1 or mon.otGender == "female"
  local rows = {
    { 8, "Dex No.", number and ("%03d"):format(number) or self:w(22, "???"), "value" },
    { 10, "Name", (def and def.name) or tostring(mon.species), "value" },
    { 12, "Type" },
    { 13, "OT", tostring(mon.otName or mon.ot or player.name or ""), otFemale and "red" or "blue" },
    { 15, "ID No.", ("%05d"):format((tonumber(mon.otId or player.id) or 0) % 65536), "value" },
  }
  for i, r in ipairs(rows) do
    self:put("label", self:w(r[1], r[2]), INFO_LABEL_X, INFO_ROW[i])
    if r[3] then self:put(r[4], r[3], INFO_VALUE_X, INFO_ROW[i]) end
  end
  local t1, t2 = self:monTypes()
  if t1 then self:drawType(t1, INFO_VALUE_X + 16, INFO_ROW[3] + 6) end
  if t2 then self:drawType(t2, INFO_VALUE_X + 50, INFO_ROW[3] + 6) end
  local Growth = require("src.pokemon.Growth")
  local level, exp = tonumber(mon.level) or 1, tonumber(mon.exp) or 0
  local rate = def and def.growthRate
  local base = Growth.expForLevel(rate, level) or 0
  local nextExp = level < 100 and (Growth.expForLevel(rate, level + 1) or exp) or exp
  self:put("label", self:w(17, "Exp. Points"), INFO_LABEL_X, EXP_LABEL_Y)
  self:putRight("value", tostring(floor(exp)), EXP_RIGHT, EXP_VALUE_Y)
  self:put("label", self:w(19, "To Next Lv."), INFO_LABEL_X, NEXT_LABEL_Y)
  self:putRight("value", tostring(math.max(0, level >= 100 and 0 or nextExp - exp)), NEXT_RIGHT, NEXT_VALUE_Y)
  if level < 100 then self:fill(EXP_BAR, math.max(0, exp - base), math.max(1, nextExp - base), { 0.15, 0.55, 0.95, 1 }) end
end

function Gen5SummaryMenu:drawCapsule(i, entry, selected)
  local g = love.graphics
  local y = CAPSULE_Y + (i - 1) * CAPSULE_PITCH
  local img = self:bwImg(entry and "capsule_0" or "capsule_15")
  g.setColor(1, 1, 1, 1)
  if img then g.draw(img, CAPSULE_X, y) end
  local record, id = self:moveRecord(entry)
  if entry and id and id ~= 0 then
    if record then self:drawType(record.type, CAPSULE_X + 26, y + MOVE_NAME_DY + 6) end
    self:put("label", (record and record.name) or tostring(id), CAPSULE_X + MOVE_NAME_DX, y + MOVE_NAME_DY)
    local pp = type(entry) == "table" and entry.pp or nil
    local maxPp = record and record.pp
    if maxPp and type(entry) == "table" then
      maxPp = maxPp + math.min(3, math.max(0, tonumber(entry.ppUps) or 0)) * floor(maxPp / 5)
    end
    self:put("label", self:w(135, "PP"), CAPSULE_X + PP_DX, y + PP_DY - 4)
    self:putRight("label", ("%s/%s"):format(tostring(pp or maxPp or "-"), tostring(maxPp or "-")), CAPSULE_X + PP_RIGHT_DX, y + PP_DY - 4)
  else
    self:put("label", "-----", CAPSULE_X + MOVE_NAME_DX, y + MOVE_NAME_DY)
    self:putRight("label", self:w(153, "--"), CAPSULE_X + PP_RIGHT_DX, y + PP_DY - 4)
  end
  if selected then
    local c = self:bwImg("cursor_0")
    if c then g.draw(c, CAPSULE_X, y) end
  end
end

function Gen5SummaryMenu:drawMovesTouch()
  local moves = self.mon.moves or {}
  for i = 1, 4 do self:drawCapsule(i, moves[i], self.moveMode and self.moveIndex == i) end
  if self.choose then self:drawCapsule(5, self.choose.move, self.moveIndex == 5) end
end

function Gen5SummaryMenu:drawFoot()
  local g = love.graphics
  local bag = (self.game.data or {}).gen5_bag_art or {}
  for key, at in pairs({ button_0 = FOOT_CLOSE, button_1 = FOOT_BACK }) do
    local rec = bag[key]
    local img = type(rec) == "table" and self:image(rec.path)
    if img then g.setColor(1, 1, 1, 1); g.draw(img, at[1], at[2]) end
  end
  -- the page in view, outlined
  local r = PAGE_RECTS[self.hgPage]
  if r then
    g.setColor(0.9, 0.9, 0.9, 1); g.setLineWidth(1)
    g.rectangle("line", r[3] + 0.5, r[1] + 4.5, r[4] - r[3], r[2] - r[1] - 8)
    g.setColor(1, 1, 1, 1)
  end
end

function Gen5SummaryMenu:drawTouch()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local grid = self:bwImg("grid")
  if grid then g.draw(grid, 0, 0) else g.setColor(0.15, 0.15, 0.17, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  local back = self:bwImg(self.hgPage == 2 and "skills" or "info")
  if back then g.draw(back, 0, 0) end
  if not self.mon then return end
  if self.hgPage == 1 then self:drawInfoTouch() else self:drawMovesTouch() end
  self:drawPanelColumn()
  self:drawFoot()
end

function Gen5SummaryMenu:drawSkillsTop()
  local g = love.graphics
  local stats = self.mon.stats or {}
  local hp, max = self:hpValues()
  local page = self:bwImg("stats_page")
  if page then
    g.setColor(1, 1, 1, 1); g.draw(page, 0, 0)
  else
    g.setColor(0.90, 0.91, 0.92, 1)
    g.rectangle("fill", VALUE_COLUMN[1], VALUE_COLUMN[2], VALUE_COLUMN[3], VALUE_COLUMN[4])
    g.setColor(0.88, 0.88, 0.90, 0.92)
    g.rectangle("fill", ABILITY_BOX[1], ABILITY_BOX[2], ABILITY_BOX[3], ABILITY_BOX[4])
  end
  g.setColor(1, 1, 1, 1)
  self:put("label", self:w(110, "HP"), HP_LABEL_X, STAT_ROW[1])
  self:putRight("value", ("%d/ %d"):format(hp, max), HP_RIGHT, STAT_ROW[1])
  local px = max > 0 and hp * 48 / max or 0
  self:fill(HP_BAR, hp, max, (px > 24) and { 0.30, 0.85, 0.35, 1 } or (px >= 10) and { 0.94, 0.80, 0.16, 1 } or { 0.94, 0.30, 0.25, 1 })
  local rows = {
    { 111, "Attack", stats.attack or stats.atk },
    { 112, "Defense", stats.defense or stats.def },
    { 113, "Sp. Atk", stats.spAttack or stats.spatk or stats.specialAttack },
    { 114, "Sp. Def", stats.spDefense or stats.spdef or stats.specialDefense },
    { 115, "Speed", stats.speed or stats.spe },
  }
  for i, r in ipairs(rows) do
    self:put("label", self:w(r[1], r[2]), STAT_LABEL_X, STAT_ROW[i + 1])
    self:putRight("value", tostring(r[3] or "-"), STAT_RIGHT, STAT_ROW[i + 1])
  end
  self:put("value", self:w(116, "Ability"), ABILITY_LABEL[1], ABILITY_LABEL[2])
  local mon, def = self.mon, self:speciesDef()
  local ability = require("src.pokemon.AbilityOf").pick(mon, def and def.abilityIds) or require("src.pokemon.AbilityOf").pick(mon, def and def.abilities)
  local id = tonumber(ability)
  local text = self.game.data.text or {}
  local name = id and text[("TEXT_G5S_0182_%05d"):format(id)] or (ability and tostring(ability))
  local desc = id and text[("TEXT_G5S_0183_%05d"):format(id)]
  if name then self:put("value", name, ABILITY_VALUE_X, ABILITY_LABEL[2]) end
  if type(desc) == "string" then
    local y = ABILITY_DESC_Y
    for line in (desc .. "\n"):gmatch("([^\n]*)\n") do
      if y < 186 then self:put("value", line, ABILITY_LABEL[1], y) end
      y = y + 16
    end
  end
end

-- the details of the move under the cursor, on top in place of the stats
function Gen5SummaryMenu:drawMoveDetailsTop()
  local g = love.graphics
  local entry = self.moveIndex == 5 and self.choose and self.choose.move or (self.mon.moves or {})[self.moveIndex]
  local record = self:moveRecord(entry)
  local page = self:bwImg("moves_page")
  if page then
    g.setColor(1, 1, 1, 1); g.draw(page, 0, 0)
  else
    g.setColor(0.90, 0.91, 0.92, 1)
    g.rectangle("fill", 34, 28, 166, 158)
  end
  g.setColor(1, 1, 1, 1)
  if not record then return end
  self:put("value", record.name or "", 44, 34)
  self:drawType(record.type, 172, 40)
  local rows = { { 149, "CATEGORY" }, { 147, "POWER" }, { 148, "ACCURACY" } }
  for i, r in ipairs(rows) do self:put("value", self:w(r[1], r[2]), 44, 50 + i * 16) end
  self:drawType(record.class or "status", 172, 72)
  local power, acc = tonumber(record.power) or 0, tonumber(record.accuracy) or 0
  self:putRight("value", power > 1 and power or self:w(153, "--"), 190, 82)
  self:putRight("value", acc > 0 and acc or self:w(153, "--"), 190, 98)
  local y = 120
  for line in ((tostring(record.description or ""):gsub("[\v\f]", "\n")) .. "\n"):gmatch("([^\n]*)\n") do
    if y < 180 then self:put("value", line, 44, y) end
    y = y + 16
  end
end

function Gen5SummaryMenu:drawTop()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local grid = self:bwImg("grid")
  if grid then g.draw(grid, 0, 0) else g.setColor(0.15, 0.15, 0.17, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  if not self.mon then return end
  if self.hgPage == 1 then
    local memo = self:bwImg("memo")
    if memo then g.draw(memo, 0, 0) end
    for i, line in ipairs(self:memoLines()) do
      self:put(i == 1 and "value" or "value", line, MEMO_X, MEMO_Y + (i - 1) * 16)
    end
  else
    local dark = self:bwImg("stats")
    if dark then g.draw(dark, 0, 0) end
    if self.moveMode then self:drawMoveDetailsTop() else self:drawSkillsTop() end
  end
  local header = self:bwImg(self.hgPage == 2 and (self.moveMode and "header_moves" or "header_stats") or "header_info")
    or self:bwImg("header_info")
  if header then g.draw(header, 0, 0) end
end

function Gen5SummaryMenu:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self:bottomOnSecond() then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawTouch() end)
  elseif self.showTop then
    self:drawTop()
  else
    self:drawTouch()
  end
  g.setColor(1, 1, 1, 1)
end

return Gen5SummaryMenu
