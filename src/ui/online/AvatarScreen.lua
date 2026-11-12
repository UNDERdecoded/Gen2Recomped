-- MY LOOK: the sheet and colour you wear -- offline in your own game and
-- online, where other players see it (src/online/world/Avatar.lua).  Opened
-- from the top of OPTIONS (offline, any time), WORLDS (in and out of a
-- world) and ONLINE settings: one look for all of them.
--
--   SPRITE    LEFT / RIGHT through this game's own protagonists, then its
--             other trainer sheets (L / R jump ten)
--   COLOR     ORIGINAL, eight tints, HUE SWAP, CUSTOM
--   HUE / STRENGTH / MODE   the CUSTOM colour (shown only for it)
--   SKIN / HAIR / OUTFIT / ACCENT   each part on its own: ORIGINAL, presets,
--             CUSTOM (then HUE / LIGHT under it).  The part's whole colour
--             ramp is remapped, shading kept (src/online/world/AvatarParts.lua).
--             Game Boy sheets have four shades and no parts: the row says so.
--   RESET     back to your own character, original colours
--   SAVE      keep it (options.looks[game]); in a world or a link
--             room the change goes out with the next presence update
--   BACK      leave without saving
--
-- The preview is the sheet itself, walking, wearing the colour, and the
-- battle back pic of the matching protagonist in the same colours.

local WorldUi = require("src.ui.online.WorldUi")
local Avatar = require("src.online.world.Avatar")
local Parts = require("src.online.world.AvatarParts")

local AvatarScreen = {}
AvatarScreen.__index = AvatarScreen
AvatarScreen.isOpaque = true
AvatarScreen.isWorldUi = true

local function playerGender(game)
  local g = game and game.save and game.save.player and game.save.player.gender
  return g == "girl" and "girl" or "boy"
end

function AvatarScreen.open(game, opts)
  local self = setmetatable({}, AvatarScreen)
  self.game = game
  self.opts = opts or {}
  self.width, self.height = WorldUi.surface()
  self.style = WorldUi.style(game)
  self.index = 1
  self.choices = Avatar.choices(game and game.data)
  self:load()
  if game and game.stack then game.stack:push(self) end
  return self
end

function AvatarScreen:uiSize() return self.width, self.height end

-- the saved choice, or the player's own character in original colours
function AvatarScreen:load()
  local saved = Avatar.saved(self.game) or {}
  self.sel = 1
  local want = saved.s
  local mine = playerGender(self.game)
  for i, c in ipairs(self.choices) do
    if want and c.key == want then self.sel = i break end
    if not want and c.role == mine then self.sel = i break end
  end
  self.preset = Avatar.PRESET_BY_ID[saved.p or ""] or 1
  local t = saved.t
  if t and not saved.p then self.preset = Avatar.PRESET_BY_ID.custom end
  self.custom = { h = (t and t.h) or 200, k = (t and t.k) or 60, m = (t and t.m) or "tint" }
  -- the parts: index 0 = ORIGINAL, 1..n = presets, n + 1 = CUSTOM
  self.parts = {}
  local cp = saved.cp or {}
  for _, def in ipairs(Parts.LIST) do
    local list = Parts.PRESETS[def.id]
    local st = { idx = 0, custom = { h = 200, s = 60, b = 0 } }
    local v = saved.c and saved.c[def.id]
    if v then
      st.idx = #list + 1
      st.custom = { h = v.h, s = v.s, b = v.b }
      for i, pr in ipairs(list) do if pr.id == cp[def.id] then st.idx = i end end
    end
    self.parts[def.id] = st
  end
  self.dirty = false
end

-- a part's value, or nil (ORIGINAL)
function AvatarScreen:partValue(id)
  local st = self.parts and self.parts[id]
  if not st or st.idx == 0 then return nil end
  local list = Parts.PRESETS[id]
  local pr = list[st.idx]
  if pr then return { h = pr.h, s = pr.s, b = pr.b }, pr.id end
  return { h = st.custom.h, s = st.custom.s, b = st.custom.b }, "custom"
end

function AvatarScreen:partsValue()
  local c, cp, any = {}, {}, false
  for _, def in ipairs(Parts.LIST) do
    local v, pid = self:partValue(def.id)
    if v then c[def.id] = v cp[def.id] = pid any = true end
  end
  if not any then return nil, nil end
  return c, cp
end

-- the paint the rows describe (whole-sprite tint and/or parts)
function AvatarScreen:paint()
  local c = self:partsValue()
  return Avatar.paint({ t = self:tint(), c = c })
end

-- a Game Boy sheet: four shades, no parts
function AvatarScreen:isGb()
  local c = self:choice()
  local data = self.game and self.game.data
  local def = c and data and data.sprites and data.sprites[c.key]
  return type(def) == "table" and not def.trueColor
end

function AvatarScreen:presetRow() return Avatar.PRESETS[self.preset] or Avatar.PRESETS[1] end

-- the tint the current rows describe (nil = original colours)
function AvatarScreen:tint()
  local p = self:presetRow()
  if p.id == "custom" then return Avatar.cleanTint(self.custom) end
  if not p.h then return nil end
  return Avatar.cleanTint({ h = p.h, k = p.k, m = p.m })
end

function AvatarScreen:choice() return self.choices[self.sel] end

-- the choice as Avatar.store takes it
function AvatarScreen:value()
  local c = self:choice()
  local p = self:presetRow()
  local parts, cp = self:partsValue()
  return { s = c and c.key, r = c and c.role, p = p.id, t = self:tint(), c = parts, cp = cp }
end

function AvatarScreen:rows()
  local c = self:choice()
  local p = self:presetRow()
  -- the sheet's name, cut to what fits beside its label (a 160-wide GB screen)
  local name = c and c.label or "-"
  local st = self.style
  if st and st.width then
    local room = (self.width or 160) - 8 - 14 - 8 - 8
    local okL, labelW = pcall(st.width, st, "LOOK ")
    room = room - ((okL and labelW) or 40)
    while #name > 3 do
      local okW, w = pcall(st.width, st, name)
      if not okW or w <= room then break end
      name = name:sub(1, -2)
    end
  end
  local rows = {
    { label = "LOOK", value = name, act = "sprite" },
    { label = "COLOR", value = p.label, act = "preset" },
  }
  if p.id == "custom" then
    rows[#rows + 1] = { label = "HUE", value = tostring(self.custom.h), act = "hue" }
    rows[#rows + 1] = { label = "STRENGTH", value = tostring(self.custom.k), act = "strength" }
    rows[#rows + 1] = { label = "MODE", value = self.custom.m == "shift" and "SHIFT" or "TINT", act = "mode" }
  end
  if self:isGb() then
    rows[#rows + 1] = { label = "PARTS", value = "GBA/DS ONLY", disabled = true }
  else
    for _, def in ipairs(Parts.LIST) do
      local st = self.parts[def.id]
      local list = Parts.PRESETS[def.id]
      local label = (st.idx == 0 and "ORIGINAL") or (list[st.idx] and list[st.idx].label) or "CUSTOM"
      rows[#rows + 1] = { label = def.label, value = label, act = "part", part = def.id }
      if st.idx == #list + 1 then
        rows[#rows + 1] = { label = " HUE", value = tostring(st.custom.h), act = "parthue", part = def.id }
        rows[#rows + 1] = { label = " LIGHT", value = tostring(st.custom.b), act = "partlight", part = def.id }
      end
    end
  end
  rows[#rows + 1] = { label = "RESET", act = "reset" }
  rows[#rows + 1] = { label = "SAVE", act = "save" }
  rows[#rows + 1] = { label = "BACK", act = "back" }
  return rows
end

local function wrap(i, n) return (i - 1) % n + 1 end

-- one step of a value row; d = -1 / +1 (or +-10 with L / R on SPRITE)
function AvatarScreen:adjust(act, d, part)
  local st = part and self.parts and self.parts[part]
  if act == "part" and st then
    st.idx = (st.idx + (d > 0 and 1 or -1)) % (#Parts.PRESETS[part] + 2)
  elseif act == "parthue" and st then
    st.custom.h = (st.custom.h + (d > 0 and 1 or -1) * Parts.HUE_STEP) % 360
  elseif act == "partlight" and st then
    st.custom.b = math.max(-60, math.min(60, st.custom.b + (d > 0 and 1 or -1) * Parts.LIGHT_STEP))
  elseif act == "sprite" and #self.choices > 0 then
    self.sel = wrap(self.sel + d, #self.choices)
  elseif act == "preset" then
    self.preset = wrap(self.preset + (d > 0 and 1 or -1), #Avatar.PRESETS)
  elseif act == "hue" then
    self.custom.h = (self.custom.h + (d > 0 and 1 or -1) * Avatar.HUE_STEP) % 360
  elseif act == "strength" then
    local k = self.custom.k + (d > 0 and 1 or -1) * Avatar.STRENGTH_STEP
    self.custom.k = math.max(Avatar.STRENGTH_STEP, math.min(100, k))
  elseif act == "mode" then
    self.custom.m = self.custom.m == "shift" and "tint" or "shift"
  else
    return false
  end
  self.dirty = true
  self.previewKey = nil
  return true
end

function AvatarScreen:close()
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
end

function AvatarScreen:save()
  local v = self:value()
  local c = self:choice()
  local mine = playerGender(self.game)
  -- your own character in its own colours is "no choice": nothing is sent
  if c and c.role == mine and not v.t and not v.c then
    Avatar.store(self.game, nil)
  else
    Avatar.store(self.game, v)
  end
  self.dirty = false
end

function AvatarScreen:activate(row)
  local act = row.act
  if act == "save" then
    self:save()
    WorldUi.sound(self.game, "Press_AB")
    self:close()
  elseif act == "back" then
    self:close()
  elseif act == "reset" then
    local mine = playerGender(self.game)
    for i, c in ipairs(self.choices) do if c.role == mine then self.sel = i break end end
    self.preset = 1
    for _, st in pairs(self.parts) do st.idx = 0 end
    self.dirty = true
    self.previewKey = nil
  else
    self:adjust(act, 1, row.part)
  end
end

function AvatarScreen:update(dt)
  self.clock = (self.clock or 0) + (dt or 1 / 60)
  local okW, W = pcall(require, "src.online.world.OnlineWorld")
  if okW and W.tick then W.tick(dt) end
  local input = self.game and self.game.input
  if not input then return end
  local rows = self:rows()
  if self.index > #rows then self.index = #rows end
  self.index = WorldUi.nav(self.game, self.index, rows)
  local row = rows[self.index]
  if row then
    if input:wasPressed("left") then self:adjust(row.act, -1, row.part)
    elseif input:wasPressed("right") then self:adjust(row.act, 1, row.part) end
    if row.act == "sprite" then
      if input:wasPressed("l") then self:adjust("sprite", -10)
      elseif input:wasPressed("r") then self:adjust("sprite", 10) end
    end
  end
  if input:wasPressed("a") and row then
    WorldUi.sound(self.game, "Select")
    self:activate(row)
  elseif input:wasPressed("b") then
    self:close()
  end
end

-- ------------------------------------------------------------ preview

function AvatarScreen:previewSprite()
  local c = self:choice()
  local data = self.game and self.game.data
  local def = c and data and data.sprites and data.sprites[c.key]
  if not def then return nil end
  local t = self:paint()
  local key = c.key .. "|" .. Avatar.paintSig(t)
  if self.previewKey ~= key then
    self.previewKey = key
    local ok, sr = pcall(function()
      local s = require("src.render.SpriteRenderer").new(def, "avatar_preview")
      if t then Avatar.dress(s, t) end
      return s
    end)
    self.preview = ok and sr or nil
    self.previewBack = nil
    -- the battle back pic: the chosen protagonist's, else the player's own
    -- gender's (other trainers have no back pic), in the same paint
    local forms = data.field and data.field.playerForms
    local g = (c.role == "boy" or c.role == "girl") and c.role or playerGender(self.game)
    local f = type(forms) == "table" and (forms[g] or forms.boy)
    local back = type(f) == "table" and f.back
    if back and not self:isGb() then
      -- at rest as the battle shows it: the DS throw strip's first frame
      -- (Black / White's still has no arms; BattleLook.restBack)
      local okB, img, quad, bw, bh = pcall(require("src.online.BattleLook").restBack, data, back, t)
      self.previewBack = okB and img or nil
      self.previewBackQuad = okB and quad or nil
      self.previewBackSize = okB and img and { bw, bh } or nil
    end
  end
  return self.preview
end

local FACINGS = { "down", "left", "up", "right" }

function AvatarScreen:drawPreview(x, y, w, h)
  local sr = self:previewSprite()
  if not sr then return end
  local g = love.graphics
  local okI, image = pcall(sr.resolveImage, sr)
  if not okI or not image then image = sr.image end
  local tw, th = sr.tileW or 16, sr.tileH or 16
  -- the back pic takes the right third when there is one
  local back = self.previewBack
  if back then
    local bw, bh = back:getDimensions()
    if self.previewBackSize then bw, bh = self.previewBackSize[1], self.previewBackSize[2] end
    local bs = math.max(0.25, math.min((h - 2) / bh, (w * 0.34) / bw))
    if bs >= 1 then bs = math.floor(bs) end
    g.setColor(1, 1, 1, 1)
    if self.previewBackQuad then
      g.draw(back, self.previewBackQuad, math.floor(x + w - bw * bs), math.floor(y + h - bh * bs), 0, bs, bs)
    else
      g.draw(back, math.floor(x + w - bw * bs), math.floor(y + h - bh * bs), 0, bs, bs)
    end
    w = w * 0.64
  end
  local scale = math.max(1, math.floor(math.min((h - 4) / th, (w / 4 - 4) / tw)))
  local t = self.clock or 0
  local phase = math.floor(t * 4) % 2
  local stepFlip = math.floor(t * 2) % 2 == 1
  local cellW = w / 4
  for i, facing in ipairs(FACINGS) do
    local okP, frame, flip = pcall(sr.poseFrame, sr, facing, phase, stepFlip)
    local quad = okP and sr.frames and (sr.frames[frame] or sr.frames[0]) or (sr.frames and sr.frames[0])
    if quad then
      local cx = x + (i - 0.5) * cellW
      local dx = math.floor(cx - tw * scale / 2)
      local dy = math.floor(y + (h - th * scale) / 2)
      g.setColor(1, 1, 1, 1)
      if flip then
        g.draw(image, quad, dx + tw * scale, dy, 0, -scale, scale)
      else
        g.draw(image, quad, dx, dy, 0, scale, scale)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

function AvatarScreen:draw()
  local st = self.style
  local W, H = self.width, self.height
  local lh = st:lineHeight()
  st:clear(W, H)
  local rows = self:rows()
  local rowH = lh + 2
  local listH = #rows * rowH + lh + 14
  -- at most ~40% of the screen for the picture; the list scrolls under it
  local previewH = math.max(24, math.min(H - listH - 12, math.floor(H * 0.4)))
  if previewH < math.floor(H * 0.3) then previewH = math.floor(H * 0.34) end
  st:box(4, 4, W - 8, previewH)
  local okD, err = pcall(self.drawPreview, self, 8, 6, W - 16, previewH - 4)
  if not okD and not self.warned then
    self.warned = true
    require("src.core.Logger").warn("avatar preview: %s", tostring(err))
  end
  local y = 4 + previewH + 4
  local room = H - y - 2
  if #rows * rowH + lh + 14 > room then rowH = lh end
  local visible = math.max(3, math.floor((room - lh - 14) / rowH))
  local first = 1
  if self.index > visible then first = self.index - visible + 1 end
  WorldUi.drawList(st, 4, y, W - 8, rows, self.index, "MY LOOK",
                   { first = first, visible = visible, rowH = rowH })
end

return AvatarScreen
