-- Source-driven FireRed/Emerald summary presentation. The existing controller
-- continues to own navigation, move slots, PP and callback lifetimes.
local S = {}
function S.detail(self)
  return self.moveSelect == true or type(self.choose) == "table"
end
function S.dexNumber(data, save, mon)
  local def = data.pokemon and data.pokemon[mon.species]
  if not def then
    return nil
  end
  local rec = data.constants and data.constants.gen3HoennDex
  if not (save and save.nationalDex) and rec and rec.numbers then
    local n = rec.numbers[mon.species]
    return n and n >= 1 and n <= (rec.native or 202) and n or nil
  end
  return tonumber(def.dex)
end
function S.ppColor(cur, max)
  if cur == max then
    return 12
  end
  if cur <= 0 then
    return 11
  end
  if cur <= (max <= 7 and 1 or math.floor(max / 4)) then
    return 10
  end
  if cur <= (max <= 7 and 2 or math.floor(max / 2)) then
    return 9
  end
  return 12
end
function S.moveType(def, chart, contest)
  if not def then
    return nil
  end
  if contest then
    local n = def.contestCategory or def.contestType
    if type(n) == "string" then
      n = ({ COOL = 0, BEAUTY = 1, CUTE = 2, SMART = 3, TOUGH = 4 })[n:upper()]
    end
    return type(n) == "number" and n >= 0 and n <= 4 and 18 + n or nil
  end
  local t = def.type
  local row = chart and chart.types and chart.types[t]
  local id = type(t) == "number" and t or row and row.index
  return type(id) == "number" and id >= 0 and id < 18 and id or nil
end
function S.types(def, chart)
  if not def or not (chart and chart.types) then
    return nil
  end
  local out = {}
  local seen = {}
  for _, name in ipairs({
    def.type1 or (def.types and def.types[1]),
    def.type2 or (def.types and def.types[2]),
  }) do
    local row = chart.types[name]
    local id = type(name) == "number" and name or row and row.index
    if not id or id < 0 or id >= 18 then
      return nil
    end
    if not seen[id] then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  return out
end
function S.apply(Menu)
  if Menu.__summaryPresentation then
    return
  end
  Menu.__summaryPresentation = true
  local V = require("src.core.GameVersion")
  local Font = require("src.render.Font")
  local Assets = require("src.render.Assets")
  local Strings = require("src.core.Strings")
  local function active(self)
    local c = self.game.data.constants or {}
    return V.generation() == 3 and c.gen3Summary and c.gen3Summary.parts
  end
  local function image(self, key)
    local p = active(self)
    return p and p.images[key] and Assets.image(p.images[key])
  end
  local function crop(img, x, y, w, h, dx, dy, sx, sy)
    local q = love.graphics.newQuad(x, y, w, h, img:getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    local ok, why = pcall(love.graphics.draw, img, q, dx or x, dy or y, 0, sx or 1, sy or 1)
    q:release()
    if not ok then
      error(why, 0)
    end
  end
  local function text(s, x, y, budget, ink, shadow)
    s = tostring(s or "")
    local scale = math.min(1, (budget or 240 - x) / math.max(1, Font.width(s)))
    love.graphics.push("all")
    love.graphics.translate(x, y)
    love.graphics.scale(scale, 1)
    love.graphics.setColor(1, 1, 1, 1)
    local two = Font.beginTwoTone(ink or { 0, 0, 0, 1 }, shadow or { 0.65, 0.65, 0.65, 1 })
    local ok, why = pcall(Font.draw, s, 0, 0)
    if two then
      Font.endTwoTone()
    end
    love.graphics.pop()
    if not ok then
      error(why, 0)
    end
  end
  local function words(self)
    local rec = self.game.data.constants.gen3Summary or {}
    local out = {}
    for key, value in pairs(rec.words or {}) do
      out[key] = Strings(value)
    end
    return out
  end
  local function help(self, frlg)
    local w = words(self)
    local detail = S.detail(self)
    local s
    if frlg then
      local key = self.isEgg and "Cancel"
        or type(self.choose) == "table" and "PickSwitch"
        or self.page == 1 and "PageCancel"
        or self.page == 2 and "Page"
        or detail and "PickSwitch"
        or "PageDetail"
      s = w[key]
      if not s then
        return
      end
    else
      if type(self.choose) == "table" then
        return
      end
      local label = self.page == 1 and (w.cancel or Strings("CANCEL"))
        or self.page >= 3 and (detail and w.switch or w.info)
      if not label then
        return
      end
      s = "{A_BUTTON}" .. label
    end
    local icons = frlg
        and {
          A_BUTTON = { 0, 0, 8, 12 },
          B_BUTTON = { 8, 0, 8, 12 },
          DPAD_LEFT = { 112, 0, 8, 12 },
          DPAD_RIGHT = { 120, 0, 8, 12 },
          DPAD_LEFTRIGHT = { 8, 16, 8, 12 },
          DPAD_UPDOWN = { 0, 16, 8, 12 },
          DPAD_ANY = { 16, 16, 8, 12 },
        }
      or { A_BUTTON = { 0, 0, 16, 16 }, B_BUTTON = { 0, 16, 16, 16 } }
    local img = image(self, frlg and "keypad" or "buttons")
    local segments = {}
    local width = 0
    local pos = 1
    while pos <= #s do
      local a, b, tag = s:find("{([A-Z_]+)}", pos)
      if a ~= pos then
        local value = s:sub(pos, a and a - 1 or #s)
        segments[#segments + 1] = { text = value, w = Font.width(value) }
        width = width + segments[#segments].w
      end
      if not a then
        break
      end
      local icon = icons[tag]
      if icon then
        segments[#segments + 1] = { icon = icon, w = icon[3] }
        width = width + icon[3]
      end
      pos = b + 1
    end
    local x = 238 - width
    for _, seg in ipairs(segments) do
      if seg.icon and img then
        local r = seg.icon
        crop(img, r[1], r[2], r[3], r[4], x, 0)
      elseif seg.text then
        text(seg.text, x, 1, seg.w, frlg and { 1, 1, 1, 1 } or { 0, 0, 0, 1 })
      end
      x = x + seg.w
    end
  end
  local header = Menu.drawHeader
  Menu.drawHeader = function(self, ...)
    local parts = active(self)
    local rec = self.game.data.constants.gen3Summary
    if
      not (
        parts
        and V.get() == "emerald"
        and self.hasArt
        and rec
        and rec.pageArt
        and self.mon
        and not self.mon.isEgg
      )
    then
      return header(self, ...)
    end
    local bg = Assets.image(rec.pageArt.info)
    local detail = S.detail(self) and self.page >= 3
    if not detail then
      love.graphics.setColor(parts.palette[15])
      love.graphics.rectangle("fill", 0, 16, 80, 144)
      if rec.pageArt.panel then
        crop(Assets.image(rec.pageArt.panel), 0, 16, 80, 144)
      end
      crop(bg, 0, 16, 80, 144)
      love.graphics.setColor(parts.palette[15])
      love.graphics.rectangle("fill", 0, 144, 80, 16)
    end
    -- The leftmost strip contains only the top bar's palette, no lettering.
    crop(bg, 0, 0, 1, 16, 0, 0, 240, 1)
    love.graphics.setColor(parts.palette[72])
    love.graphics.rectangle("fill", 152, 0, 88, 15)
    love.graphics.setColor(parts.palette[71])
    love.graphics.rectangle("fill", 152, 15, 88, 1)
    self:drawPagination()
    text(self.pages[self.page], 2, 1, 86, { 1, 1, 1, 1 })
    help(self, false)
    local mon, def = self.mon, self.def or {}
    local w = words(self)
    local dex = S.dexNumber(self.game.data, self.game.save, mon)
    if dex then
      text((w.number or "") .. ("%03d"):format(dex), 8, 17, 32, { 1, 1, 1, 1 })
    end
    text(mon.nickname or def.name or mon.species, 8, 97, 72, { 1, 1, 1, 1 })
    if not detail and not self.isEgg then
      text("/" .. (def.name or tostring(mon.species)), 8, 113, 72, { 1, 1, 1, 1 })
      text((w.level or "Lv") .. tostring(mon.level or 1), 32, 129, 32, { 1, 1, 1, 1 })
      local mark = self:genderMark()
      if mark then
        text(mark, 65, 129, 14, mark == "♀" and { 1, 0.3, 0.4, 1 } or { 0.3, 0.4, 1, 1 })
      end
      local balls = self.game.data.constants.gen3BallAnim
      local path = balls and balls.images and balls.images.balls
      if path then
        local sheet = Assets.image(path)
        local id = type(mon.ball) == "number" and mon.ball
          or require("src.battle.Gen3BallAnim").ballIndex(
            self.game.data,
            mon.ball,
            self.game.data.items
          )
        local size = balls.size or 16
        id = math.max(0, math.min(math.floor(sheet:getHeight() / size) - 1, id or 0))
        crop(sheet, 0, id * size, size, size, 8, 128)
      end
    end
    local marks = image(self, "markings")
    if marks then
      crop(marks, 0, (tonumber(mon.markings) or 0) % 16 * 8, 32, 8, 44, 22)
    end
    if self.pic then
      local pic = self.picAnim and self.picAnim:image() or self.pic
      local width, height = self.pic:getDimensions()
      love.graphics.push("all")
      local index = tonumber(def.index)
      if parts.noFlip and index and index >= 0 and index <= 411 and not parts.noFlip[index] then
        love.graphics.translate(80, 0)
        love.graphics.scale(-1, 1)
      end
      local ok, why = pcall(self.drawMon, self, pic, 40 - width / 2, 64 - height / 2)
      love.graphics.pop()
      if not ok then
        error(why, 0)
      end
    end
  end
  local moves = Menu.drawMoves
  Menu.drawMoves = function(self, contest, ...)
    if
      not (
        active(self)
        and V.get() == "emerald"
        and self.hasArt
        and self.game.data.constants.gen3Summary.typeBadges
      )
    then
      return moves(self, contest, ...)
    end
    local data = self.game.data
    local badge = Assets.image(data.constants.gen3Summary.typeBadges.image)
    local offered = type(self.choose) == "table" and self:chooseRows() or nil
    local count = offered or 4
    local rows = self.mon and self.mon.moves or {}
    if count == 5 then
      local rec = data.constants.gen3Summary
      local page = rec.pageArt and rec.pageArt[contest and "contest_moves" or "battle_moves"]
      if page then
        local art = Assets.image(page)
        crop(art, 80, 80, 160, 16, 80, 96)
        crop(art, 80, 104, 160, 8, 80, 112)
      end
    end
    for i = 1, count do
      local slot = rows[i]
      local id = i == offered and self.choose.move or type(slot) == "table" and slot.id or slot
      local def = id and data.moves[id]
      local y = 33 + (i - 1) * 16
      text(def and def.name or tostring(id or "-"), 120, y, 72, { 1, 1, 1, 1 })
      if def then
        local pp = type(slot) == "table" and slot.pp or def.pp
        local max = require("src.pokemon.Pokemon").maxPP(def, slot)
        local value = Strings("PP") .. tostring(pp or "-") .. "/" .. tostring(max or def.pp or "-")
        local parts = active(self)
        local colors = parts.textColors
        local color = S.ppColor(tonumber(pp) or 0, tonumber(max) or def.pp or 1)
        local ink = colors and parts.palette[128 + colors[color * 3 + 2]]
        local shadow = colors and parts.palette[128 + colors[color * 3 + 3]]
        text(value, 236 - Font.width(value), y, 44, ink, shadow)
        local t = S.moveType(def, data.type_chart, contest)
        if t then
          crop(badge, 0, t * 16, 32, 16, 85, y - 1)
        end
      else
        text("--", 212, y, 24)
      end
    end
    if S.detail(self) then
      local index = self.moveIndex or 1
      local slot = rows[index]
      local id = index == offered and self.choose and self.choose.move
        or type(slot) == "table" and slot.id
        or slot
      local def = id and data.moves[id]
      if def then
        if contest then
          text(words(self).appeal or Strings("APPEAL"), 8, 121, 40)
          text(words(self).jam or Strings("JAM"), 8, 137, 40)
          self:drawHearts(def)
        else
          text(words(self).power or Strings("POWER"), 8, 121, 49)
          text(tostring(def.power or "---"), 61, 121, 18)
          text(words(self).accuracy or Strings("ACCURACY"), 8, 137, 49)
          text(tostring(def.accuracy or "---"), 61, 137, 18)
        end
        self:drawDescription(contest and def.contestDescription or def.description, 121, 137)
      end
      local img = image(self, "selector")
      if img then
        local function selectRow(row, edge, mid)
          local y = 32 + (row - 1) * 16
          for x = 80, 224, 16 do
            local frame = (x == 80 or x == 224) and edge or mid
            crop(img, 0, frame * 16, 16, 16, x == 224 and 240 or x, y, x == 224 and -1 or 1, 1)
          end
        end
        if self.moveSwapFrom then
          selectRow(self.moveSwapFrom, 6, 7)
        end
        selectRow(self.moveIndex or 1, 4, 5)
      end
    end
  end
  local info = Menu.drawInfo
  Menu.drawInfo = function(self, ...)
    local rec = self.game.data.constants.gen3Summary
    local spec = rec and rec.typeBadges
    local windows = self:windows()
    local win = windows and windows.labels[10]
    local types = S.types(self.def, self.game.data.type_chart)
    if
      not (
        active(self)
        and V.get() == "emerald"
        and self.hasArt
        and spec
        and win
        and types
        and #types > 0
      )
    then
      return info(self, ...)
    end
    local old = rawget(self, "typeText")
    self.typeText = function()
      return nil
    end
    local ok, result = pcall(info, self, ...)
    self.typeText = old
    if not ok then
      error(result, 0)
    end
    local sheet = Assets.image(spec.image)
    love.graphics.push("all")
    local drawn, why = pcall(function()
      for i, id in ipairs(types) do
        crop(sheet, 0, id * 16, 32, 16, win.x + 32 + (i - 1) * 36, win.y)
      end
    end)
    love.graphics.pop()
    if not drawn then
      error(why, 0)
    end
    return result
  end
  local fr = Menu.drawFireRed
  Menu.drawFireRed = function(self, ...)
    local out = fr(self, ...)
    if active(self) then
      local small = Font.hasFace("small")
      if small then
        Font.pushFace("small")
      end
      local ok, why = pcall(help, self, true)
      if small then
        Font.popFace()
      end
      if not ok then
        error(why, 0)
      end
    end
    return out
  end
end
return S
