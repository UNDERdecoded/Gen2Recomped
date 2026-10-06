-- src/ui/Gen4BattleParty.lua
--
-- PLATINUM'S BATTLE PARTY LIST -- the BOTTOM-SCREEN screen POKeMON opens in a
-- battle (src/battle_sub_menus/battle_party*.c), drawn while the battle stays
-- on the top screen.  Two of its screens, which are the switch itself:
--
--   PARTY    six panels and CANCEL (BATTLE_PARTY_SCREEN_POKEMON_PARTY)
--   SELECT   SHIFT / SUMMARY / CHECK MOVES / CANCEL for one member
--            (BATTLE_PARTY_SCREEN_SELECT_POKEMON)
--
-- SUMMARY and CHECK MOVES hand over to the port's own Gen 4 summary screen
-- rather than the cartridge's bottom-screen pages (those are the next piece
-- of this screen), with the moves page asked for by CHECK MOVES.
--
-- Everything placed here is the cartridge's number, all out of the decomp:
--   panels       sButtonDimensions, tile (0,0) (16,1) (0,6) (16,7) (0,12)
--                (16,13), 16x6; CANCEL (27,19) 5x5; SHIFT (1,1) 30x17;
--                SUMMARY (0,19), CHECK MOVES (13,19), 13x5
--   panel art    RetrieveButtonData: the Pokemon IN battle on the primary
--                panel, the rest on the ALT one, an empty slot on ALT
--                DISABLED, a fainted one forced onto palette 2, an egg with
--                its HP-bar columns blanked
--   slot text    sPartyPokemonScreenWindowTemplates (15x5 at the panel's
--                tile): name at (32, 8) FONT_SUBSCREEN TEXT_COLOR(7, 8, 9),
--                gender FONT_SYSTEM right-aligned at y 8 in (10, 11) / (12,
--                13); HP "cur/max" in special chars at (56, 32); the HP bar
--                at (64, 24), 48 px, colour 1/3/5 with +1 on its top and
--                bottom rows; "Lv" + level at (8, 32) unless a status icon
--                is up
--   sprites      icon centres (16,16) (144,24) (16,64) (144,72) (16,112)
--                (144,120); status icons (28,40) .. (156,144); held item at
--                icon + (8, 8), mail at icon + (16, 8); the select screen's
--                icon at (128, 72)
--   cursor       sPokemonPartyScreenCursorPositions /
--                sSelectPokemonScreenCursorPositions, drawn with the battle
--                subscreen's corner cursor
--   words        bank 3: "Choose a Pokémon." (6), SHIFT (15), SUMMARY (18),
--                CHECK MOVES (19), in the message box at window (2, 21) 22x2
--
-- Art: gen4_battle_art's bparty_* / bselect_* (src/import/Gen4BattleArt.lua);
-- colours: gen4_battle_anims.partyInk (row 9 of the screen's palette).
--
-- The interface is Gen4PartyMenu's battle mode, so BattleState hands either
-- screen the same options: { battle, onSwitch(mon), forceSwitch, onCancel }.

local Strings = require("src.core.Strings")

local Gen4BattleParty = {}
Gen4BattleParty.__index = Gen4BattleParty

-- Not opaque: the battle is the top screen and keeps drawing underneath.
Gen4BattleParty.isOpaque = false

Gen4BattleParty.BANK = 3
Gen4BattleParty.TEXT = { choose = 6, shift = 15, male = 16, female = 17, summary = 18, checkMoves = 19 }

Gen4BattleParty.PANEL_TILES = {
  { 0, 0 }, { 16, 1 }, { 0, 6 }, { 16, 7 }, { 0, 12 }, { 16, 13 },
}
Gen4BattleParty.ICON = {
  { 16, 16 }, { 144, 24 }, { 16, 64 }, { 144, 72 }, { 16, 112 }, { 144, 120 },
}
Gen4BattleParty.STATUS_AT = {
  { 28, 40 }, { 156, 48 }, { 28, 88 }, { 156, 96 }, { 28, 136 }, { 156, 144 },
}
Gen4BattleParty.CANCEL_AT = { 216, 152 }
Gen4BattleParty.SHIFT_AT = { 8, 8 }
Gen4BattleParty.SUMMARY_AT = { 0, 152 }
Gen4BattleParty.CHECK_AT = { 104, 152 }
Gen4BattleParty.SELECT_ICON = { 128, 72 }
Gen4BattleParty.HP_BAR = 48

-- the cursor's corners and its neighbours (index 7 = CANCEL on the party
-- screen; 1 SHIFT, 2 SUMMARY, 3 CHECK MOVES, 4 CANCEL on the select one)
Gen4BattleParty.PARTY_CURSOR = {
  { 8, 8, 120, 40,     up = 7, down = 3, left = 7, right = 2 },
  { 136, 16, 248, 48,  up = 5, down = 4, left = 1, right = 3 },
  { 8, 56, 120, 88,    up = 1, down = 5, left = 2, right = 4 },
  { 136, 64, 248, 96,  up = 2, down = 6, left = 3, right = 5 },
  { 8, 104, 120, 136,  up = 3, down = 2, left = 4, right = 6 },
  { 136, 112, 248, 144, up = 4, down = 7, left = 5, right = 7 },
  { 224, 160, 248, 184, up = 6, down = 1, left = 6, right = 1 },
}
Gen4BattleParty.SELECT_CURSOR = {
  { 16, 16, 240, 136, up = 1, down = "previous", left = 1, right = 1 },
  { 8, 160, 96, 184,  up = 1, down = 2, left = 2, right = 3 },
  { 112, 160, 200, 184, up = 1, down = 3, left = 2, right = 4 },
  { 224, 160, 248, 184, up = 1, down = 4, left = 3, right = 4 },
}
-- the touch rects (sPartyPokemonScreenTouchRects / sSelectPokemonScreenTouchRects)
Gen4BattleParty.PARTY_TOUCH = {
  { 0, 47, 0, 127 }, { 8, 55, 128, 255 }, { 48, 95, 0, 127 },
  { 56, 103, 128, 255 }, { 96, 143, 0, 127 }, { 104, 151, 128, 255 },
  { 152, 191, 216, 255 },
}
Gen4BattleParty.SELECT_TOUCH = {
  { 8, 143, 8, 247 }, { 152, 191, 0, 103 }, { 152, 191, 104, 207 }, { 152, 191, 216, 255 },
}

function Gen4BattleParty.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4BattleParty)
  self.game = game
  self.battle = opts.battle
  self.onSwitch = opts.onSwitch
  self.onCancel = opts.onCancel
  self.forceSwitch = opts.forceSwitch
  self.screen = "party"
  self.index = 1
  self.selectIndex = 1
  self.t = 0
  self.images = {}
  local data = game and game.data or {}
  self.art = data.gen4_battle_art or {}
  self.ink = (data.gen4_battle_anims or {}).partyInk or {}
  return self
end

-- Does this cache carry the screen?  BattleState asks before choosing it.
function Gen4BattleParty.available(data)
  local art = data and data.gen4_battle_art
  return art and art.bparty_bg and art.bparty_panel_0_0 and true or false
end

-- The battle's own surface, so the screen draws in it untranslated.
function Gen4BattleParty:uiSize()
  if self.battle and self.battle.uiSize then return self.battle:uiSize() end
  return 256, 192
end

function Gen4BattleParty:party() return (self.game.save and self.game.save.party) or {} end

local function isEgg(mon) return require("src.pokemon.Party").isEgg(mon) end

function Gen4BattleParty:text(id, fallback)
  local data = self.game and self.game.data
  local s = data and data.text and data.text[("TEXT_B%04d_%05d"):format(Gen4BattleParty.BANK, id)]
  if type(s) ~= "string" or s == "" then return Strings(fallback) end
  return (s:gsub("{[^}]*}", ""))
end

function Gen4BattleParty:image(key)
  local rec = self.art[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  return self.images[path] or nil, rec
end

local function rgb(c, fallback)
  c = c or fallback or { 0, 0, 0 }
  return { c[1] / 255, c[2] / 255, c[3] / 255, 1 }
end

function Gen4BattleParty:drawArt(key, x, y)
  local img, rec = self:image(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(x + (type(rec) == "table" and rec.originX or 0)),
                     math.floor(y + (type(rec) == "table" and rec.originY or 0)))
  return true
end

-- Is this member the one standing in the battle (or its partner)?
function Gen4BattleParty:inBattle(mon)
  local b = self.battle
  if not (b and mon) then return false end
  if b.player and b.player.mon == mon then return true end
  local partner = b.partnerOf and b.player and b:partnerOf(b.player)
  return partner and partner.mon == mon and true or false
end

function Gen4BattleParty:panelKey(slot)
  local mon = self:party()[slot]
  if not mon then return "bparty_panel_1_3" end
  local a = self:inBattle(mon) and 0 or 1
  local key = ("bparty_panel_%d_0"):format(a)
  if isEgg(mon) then return key .. "_egg" end
  if (tonumber(mon.hp) or 0) <= 0 then return key .. "_fnt" end
  return key
end

-- ---------------------------------------------------------------- words --

local function tone(ink, a, s)
  local Font = require("src.render.Font")
  if ink[a] and ink[s] and Font.beginTwoTone then
    return Font.beginTwoTone(rgb(ink[a]), rgb(ink[s]))
  end
  love.graphics.setColor(0, 0, 0, 1)
  return false
end

function Gen4BattleParty:drawWords(text, x, y, face, a, s)
  local Font = require("src.render.Font")
  local faced = face and Font.pushFace(face)
  local t = tone(self.ink, a, s)
  Font.draw(text, math.floor(x), math.floor(y))
  if t then Font.endTwoTone() end
  if faced then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

local function widthIn(face, text)
  local Font = require("src.render.Font")
  local faced = face and Font.pushFace(face)
  local w = Font.width and Font.width(text) or #text * 8
  if faced then Font.popFace() end
  return w
end

-- the special-character strip: 0..9, "/" at 10, "Lv" at 11-12
function Gen4BattleParty:glyph(n, x, y, w)
  local img = self:image("bparty_digits")
  if not img then return end
  local iw, ih = img:getDimensions()
  self.quads = self.quads or {}
  local k = n .. ":" .. (w or 8)
  if not self.quads[k] then self.quads[k] = love.graphics.newQuad(n * 8, 0, w or 8, 8, iw, ih) end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, self.quads[k], x, y)
end

function Gen4BattleParty:number(value, cells, pad, x, y)
  local cellsOut = require("src.battle.Gen4Battle").numberCells(value, cells, pad)
  for i, d in ipairs(cellsOut) do
    if d then self:glyph(d, x + (i - 1) * 8, y) end
  end
end

function Gen4BattleParty:genderOf(mon)
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  if okP and Pokemon.genderOf then return Pokemon.genderOf(self.game.data, mon) end
  return mon and mon.gender
end

function Gen4BattleParty:nameOf(mon)
  if isEgg(mon) then return mon.nickname or "EGG" end
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
  return def and def.name or tostring(mon.species)
end

-- SummaryStatus: 1 PAR, 2 FRZ, 3 SLP, 4 PSN, 5 BRN, 6 FNT (0 is Pokerus)
local STATUS_SEQ = { PAR = 1, FRZ = 2, SLP = 3, PSN = 4, TOX = 4, BRN = 5 }
function Gen4BattleParty.statusSeq(mon)
  if not mon or isEgg(mon) then return nil end
  if (tonumber(mon.hp) or 0) <= 0 then return 6 end
  local s = type(mon.status) == "string" and mon.status:upper():sub(1, 3)
  return s and STATUS_SEQ[s] or nil
end

-- ----------------------------------------------------------------- icons --

function Gen4BattleParty:drawIcon(mon, cx, cy)
  local data = self.game.data
  local icons = data.icons
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[mon.species]) or (def and def.icon)
  if isEgg(mon) and icons and icons.bySpecies then
    entry = icons.bySpecies[mon.species == 490 and 495 or 494] or entry
  end
  local path = type(entry) == "table" and entry.image or entry
  if type(path) ~= "string" then return end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  local img = self.images[path]
  if not img then return end
  local iw, ih = img:getDimensions()
  local fh = math.min(ih, tonumber(type(entry) == "table" and entry.frameHeight) or 32)
  local frames = math.max(1, math.floor(ih / fh))
  local f = 0
  if (tonumber(mon.hp) or 0) > 0 and frames > 1 then f = math.floor(self.t / 0.32) % frames end
  local q = love.graphics.newQuad(0, f * fh, iw, fh, iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, math.floor(cx - iw / 2), math.floor(cy - fh / 2))
end

function Gen4BattleParty:drawHeld(mon, cx, cy)
  if not mon.item or mon.item == 0 then return end
  local item = self.game.data.items and self.game.data.items[mon.item]
  local mail = item and (item.pocket == "MAIL")
  self:drawArt(mail and "bparty_held_mail" or "bparty_held_item", cx + 8, cy + 8)
end

-- ----------------------------------------------------------------- draw --

function Gen4BattleParty:drawSlot(slot)
  local mon = self:party()[slot]
  local tx, ty = Gen4BattleParty.PANEL_TILES[slot][1] * 8, Gen4BattleParty.PANEL_TILES[slot][2] * 8
  self:drawArt(self:panelKey(slot), tx, ty)
  if not mon then return end
  local ink = self.ink
  -- the window sits on the panel's own tile, so its (x, y) is the panel's
  local name = self:nameOf(mon)
  self:drawWords(name, tx + 32, ty + 8, "subscreen", 7, 8)
  if not isEgg(mon) then
    local g = self:genderOf(mon)
    if g == "male" or g == "female" then
      local sym = self:text(g == "male" and Gen4BattleParty.TEXT.male or Gen4BattleParty.TEXT.female,
                            g == "male" and "♂" or "♀")
      local w = widthIn("system", sym)
      self:drawWords(sym, tx + 120 - w, ty + 8, "system",
                     g == "male" and 10 or 12, g == "male" and 11 or 13)
    end
    -- HP: "cur/max" in the special characters, the bar above it
    local max = math.max(1, (mon.stats and mon.stats.hp) or mon.maxHp or 1)
    local cur = math.max(0, math.min(max, tonumber(mon.hp) or 0))
    self:number(cur, 3, "spaces", tx + 56, ty + 32)
    self:glyph(10, tx + 80, ty + 32)
    self:number(max, 3, "none", tx + 88, ty + 32)
    local px = math.floor(cur * Gen4BattleParty.HP_BAR / max)
    if px == 0 and cur > 0 then px = 1 end
    if px > 0 then
      local colour = (px > Gen4BattleParty.HP_BAR / 2 and 1)
                     or (px > Gen4BattleParty.HP_BAR / 5 and 3) or 5
      local edge, body = rgb(ink[colour + 1]), rgb(ink[colour])
      local g = love.graphics
      g.setColor(edge); g.rectangle("fill", tx + 64, ty + 24 + 1, px, 1)
      g.setColor(body); g.rectangle("fill", tx + 64, ty + 24 + 2, px, 2)
      g.setColor(edge); g.rectangle("fill", tx + 64, ty + 24 + 4, px, 1)
      g.setColor(1, 1, 1, 1)
    end
    local status = Gen4BattleParty.statusSeq(mon)
    if status then
      local at = Gen4BattleParty.STATUS_AT[slot]
      self:drawArt("bparty_status_" .. status, at[1], at[2])
    else
      self:glyph(11, tx + 8, ty + 32, 16)
      self:number(tonumber(mon.level) or 1, 3, "none", tx + 24, ty + 32)
    end
  end
  local ic = Gen4BattleParty.ICON[slot]
  self:drawIcon(mon, ic[1], ic[2])
  self:drawHeld(mon, ic[1], ic[2])
end

function Gen4BattleParty:drawParty()
  self:drawArt("bparty_bg", 0, 0)
  self:drawArt("bparty_fg", 0, 0)
  for slot = 1, 6 do self:drawSlot(slot) end
  self:drawArt(self.forceSwitch and "bparty_cancel_3" or "bparty_cancel_0",
               Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  -- "Choose a Pokémon." in the options frame, window (2, 21) 22x2
  local Font = require("src.render.Font")
  Font.drawDialogueBox(1, 20, 24, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self:text(Gen4BattleParty.TEXT.choose, "Choose a POKéMON."), 16, 168)
  love.graphics.setColor(1, 1, 1, 1)
  local c = Gen4BattleParty.PARTY_CURSOR[self.index]
  self:drawCursor(c)
end

function Gen4BattleParty:drawSelect()
  local mon = self:party()[self.index]
  self:drawArt("bselect_bg", 0, 0)
  self:drawArt("bselect_fg", 0, 0)
  self:drawArt("bparty_shift", Gen4BattleParty.SHIFT_AT[1], Gen4BattleParty.SHIFT_AT[2])
  local egg = mon and isEgg(mon)
  self:drawArt(egg and "bparty_small_3" or "bparty_small_0", Gen4BattleParty.SUMMARY_AT[1], Gen4BattleParty.SUMMARY_AT[2])
  self:drawArt(egg and "bparty_small_3" or "bparty_small_0", Gen4BattleParty.CHECK_AT[1], Gen4BattleParty.CHECK_AT[2])
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  if mon then
    -- the name, centred in its 96-wide window at (80, 32), the symbol after it
    local name = self:nameOf(mon)
    local g = not egg and self:genderOf(mon)
    local sym = (g == "male" or g == "female")
                and self:text(g == "male" and Gen4BattleParty.TEXT.male or Gen4BattleParty.TEXT.female,
                              g == "male" and "♂" or "♀") or nil
    local sw = widthIn("subscreen", name)
    local gw = sym and widthIn("system", sym) or 0
    local x0 = 80 + math.floor((96 - sw - gw - (sym and 8 or 0)) / 2)
    self:drawWords(name, x0, 32 + 8, "subscreen", 7, 8)
    if sym then
      self:drawWords(sym, x0 + sw + 8, 32 + 8, "system", g == "male" and 10 or 12, g == "male" and 11 or 13)
    end
    local ic = Gen4BattleParty.SELECT_ICON
    self:drawIcon(mon, ic[1], ic[2])
    self:drawHeld(mon, ic[1], ic[2])
  end
  local function centred(text, wx, wy, ww)
    local w = widthIn("subscreen", text)
    self:drawWords(text, wx + math.floor((ww - w) / 2), wy + 6, "subscreen", 7, 8)
  end
  centred(self:text(Gen4BattleParty.TEXT.shift, "SHIFT"), 88, 96, 80)
  if not egg then
    centred(self:text(Gen4BattleParty.TEXT.summary, "SUMMARY"), 8, 160, 88)
    centred(self:text(Gen4BattleParty.TEXT.checkMoves, "CHECK MOVES"), 112, 160, 88)
  end
  self:drawCursor(Gen4BattleParty.SELECT_CURSOR[self.selectIndex])
end

function Gen4BattleParty:drawCursor(c)
  if not c then return end
  local Gen4Battle = require("src.battle.Gen4Battle")
  local i = Gen4Battle.CURSOR_INSET
  Gen4Battle.drawCursorCorners(self.battle or { game = self.game, data = self.game.data, frame = math.floor(self.t * 60) },
    { left = c[1] - i, top = c[2] - i, right = c[3] + i, bottom = c[4] + i })
end

function Gen4BattleParty:drawBottom()
  if self.screen == "select" then self:drawSelect() else self:drawParty() end
end

function Gen4BattleParty:draw()
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return end
  SecondScreen.draw(self.game, function() self:drawBottom() end)
  if SecondScreen.drawFrame then SecondScreen.drawFrame(self.game) end
end

-- ---------------------------------------------------------------- input --

function Gen4BattleParty:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4BattleParty:handOff(mon)
  self.game.stack:pop()
  if self.onSwitch then self.onSwitch(mon, self) end
end

function Gen4BattleParty:openSummary(page)
  local mon = self:party()[self.index]
  if not mon then return end
  require("src.ui.Screens").push(self.game, "SummaryMenu", {
    mon = mon, readOnlyMoves = true, page = page,
  })
end

-- A slot that cannot be selected (CheckCanPartySlotBeSelected: empty) is not
-- a place the cursor or a tap goes.
function Gen4BattleParty:pickSlot(slot)
  if slot == 7 then
    if not self.forceSwitch then self:close() end
    return
  end
  if not self:party()[slot] then return end
  self.index = slot
  self.screen = "select"
  self.selectIndex = 1
end

function Gen4BattleParty:pickSelect(i)
  local mon = self:party()[self.index]
  if i == 1 then return self:handOff(mon) end
  if i == 4 then self.screen = "party"; return end
  if mon and isEgg(mon) then return end
  if i == 2 then return self:openSummary(nil) end
  if i == 3 then return self:openSummary("moves") end
end

local function step(grid, index, dir, prev)
  local cell = grid[index]
  local nxt = cell and cell[dir]
  if nxt == "previous" then return prev or 2 end
  return nxt or index
end

function Gen4BattleParty:update(dt)
  self.t = (self.t or 0) + (dt or 1 / 60)
  local input = self.game.input
  if not input then return end
  local dirs = { "up", "down", "left", "right" }
  if self.screen == "party" then
    for _, d in ipairs(dirs) do
      if input:wasPressed(d) then
        local n = self.index
        for _ = 1, 7 do
          n = step(Gen4BattleParty.PARTY_CURSOR, n, d)
          if n == 7 or self:party()[n] then break end
        end
        self.index = n
        return
      end
    end
    if input:wasPressed("a") then return self:pickSlot(self.index) end
    if input:wasPressed("b") then
      if not self.forceSwitch then self:close() end
    end
  else
    for _, d in ipairs(dirs) do
      if input:wasPressed(d) then
        local before = self.selectIndex
        local n = step(Gen4BattleParty.SELECT_CURSOR, before, d, self.lastLower)
        if before ~= 1 and n == 1 then self.lastLower = before end
        self.selectIndex = n
        return
      end
    end
    if input:wasPressed("a") then return self:pickSelect(self.selectIndex) end
    if input:wasPressed("b") then self.screen = "party" end
  end
end

function Gen4BattleParty:touchpressed(_, px, py)
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return false end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end
  local rects = self.screen == "party" and Gen4BattleParty.PARTY_TOUCH or Gen4BattleParty.SELECT_TOUCH
  for i, r in ipairs(rects) do
    -- { top, bottom, left, right }, bottom and right inclusive as stored
    if y >= r[1] and y <= r[2] and x >= r[3] and x <= r[4] then
      if self.screen == "party" then self:pickSlot(i) else self:pickSelect(i) end
      return true
    end
  end
  return true
end

return Gen4BattleParty
