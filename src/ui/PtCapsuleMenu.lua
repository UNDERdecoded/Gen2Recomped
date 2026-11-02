-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S BALL CAPSULE APP (pokeplatinum src/applications/capsule_menu/
-- main.c, manager.c, placement.c, graphics.c), on the cb_data.narc art
-- (src/import/Gen4PtCapsuleArt.lua) and the seal case
-- (src/pokemon/Gen4SealCase.lua). Opened by `opensealcapsuleeditor`
-- (CapsuleMenu_StartFieldTask).
--
-- READ FROM CODE:
--   * the twelve capsules on the top screen, 4 x 3 at (40 + 56 c, 27 + 53 r)
--     (CapsuleGraphics_GetCapsuleGridLocation); a capsule shows sealed (anim
--     1) when it holds any seal, and its Pokemon's icon at (-16, +12);
--   * the pad (CapsuleManager_HandleCapsulePadMovement): left / right wrap
--     through all twelve, up / down stop at the top and bottom rows; A opens
--     the menu (bank 8: EDIT / SET or REMOVE / SHIFT / QUIT by what the
--     capsule holds, CapsuleGraphics_OpenCapsuleSelectionMenu), B leaves, a
--     tap on the touch screen goes straight to EDIT;
--   * EDIT (CapsuleManager_HandleCancelUpdateSeals + placement.c): the touch
--     screen's seal list (pages of 8, the seals the case holds or a capsule
--     uses, PopulateSealPage), a tap takes one out of the case (GiveOrTakeSeal
--     -1) and drags it; up to 8 a capsule; dropped more than 60 from the
--     ball's centre (190, 70) it goes back to the case (GiveOrTakeSeal2 +1);
--     a placed seal is dragged by a tap within 10 of it; CONFIRM keeps the
--     design (also on the Pokemon wearing it; trainer score event 6), CANCEL
--     asks "Quit without changing..." when anything changed and YES puts the
--     capsule and the counts back; THROW tries the design out (the Pokemon
--     the capsule is on, else the first that is not an egg) with the seals'
--     effects;
--   * SET (the party menu in PARTY_MENU_MODE_BALL_SEAL: eggs refused): the
--     capsule id and a copy on the Pokemon, and the Seal Club Show sighting
--     with the first seal's name (FieldSystem_SaveTVSegment_SealClubShow);
--     REMOVE clears the Pokemon's capsule id; SHIFT swaps two capsules and
--     the ids of the Pokemon wearing them (CapsuleGraphics_SwapCapsules).
-- INFERRED / SIMPLIFIED: the 3D Poke Ball spinning on the top screen and the
-- ball-rotation throw (overlay 11's BallRotation) are not drawn -- the throw
-- shows the Pokemon growing in with the seal effects; palette fades are
-- plain fades; the seal-name and count windows' places on the touch screen.
--
-- SCREENS as Gen4ScratchOffCards: with both screens on view, top + bottom;
-- with one, the selection shows the top screen and editing the touch screen,
-- SELECT swaps.

-- SOUNDS: SE_CONFIRM_sseq_3 is the fourth seqInfo entry on SE_CONFIRM.sseq,
-- SEQ_SE_DP_SELECT (INFERRED from pl_sound_data.json's order)

local Assets = require("src.render.Assets")
local SecondScreen = require("src.ui.SecondScreen")
local SealCase = require("src.pokemon.Gen4SealCase")

local S = {}; S.__index = S
S.isOpaque = true

local W, H = 256, 192
local BANK = 8
local CENTER_X, CENTER_Y, RADIUS = 190, 70, 60
local ICON_XY = { { 19, 22 }, { 75, 22 }, { 19, 46 }, { 75, 46 }, { 19, 70 }, { 75, 70 }, { 19, 94 }, { 75, 94 } }
local ICON_RECT = { { 8, 16, 24, 32 }, { 64, 16, 80, 32 }, { 8, 40, 24, 56 }, { 64, 40, 80, 56 },
                    { 8, 64, 24, 80 }, { 64, 64, 80, 80 }, { 8, 88, 24, 104 }, { 64, 88, 80, 104 } }
local PAGE_UP, PAGE_DOWN = { 8, 104, 48, 128 }, { 56, 104, 96, 128 }
local THROW, CONFIRM, CANCEL = { 18, 168, 77, 188 }, { 97, 168, 156, 188 }, { 178, 168, 237, 188 }
local ARROWS = { { 136, 16, 1 }, { 136, 128, 3 }, { 240, 16, 0 }, { 240, 128, 2 } }

local function inside(r, x, y) return x and x >= r[1] and x < r[3] and y >= r[2] and y < r[4] end

function S.available(game)
  local art = game and game.data and game.data.gen4_pt_capsule_art
  return type(art) == "table" and type(art.groups) == "table" and type(art.seals) == "table"
end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.data, name) end
end

-- onDone() when the player leaves (CAPSULE_MENU_GO_TO_FIELD)
function S.new(game, onDone, capsuleIndex)
  local self = setmetatable({ game = game, data = game.data, onDone = onDone }, S)
  self.art = game.data.gen4_pt_capsule_art or {}
  self.images, self.iconCache = {}, {}
  self.save = game.save
  self.cursor = math.max(0, math.min(11, tonumber(capsuleIndex) or 0))   -- capsuleIndex[0]
  self.cursor2 = self.cursor                                              -- capsuleIndex[1]
  self.mode, self.state = "select", "fadein"
  self.fade, self.fadeTarget = 16, 0
  self.message = 7
  self.page = 0
  self.render = {}                       -- sealRenderInfo[8]
  self.view = "top"
  self.stylus = { x = CENTER_X, y = CENTER_Y }
  self:assign()
  self:loadRender()
  return self
end

function S:uiSize() return W, H end
function S:wantsFillScale() return true end
function S:twoScreens() return SecondScreen.separate(self.game) end

-- ------------------------------------------------------------- the data --

function S:party() return self.save.party or {} end
function S:capsule(i) return SealCase.capsule(self.save, i + 1) end
function S:isEgg(mon) return require("src.pokemon.Party").isEgg(mon) end

-- CapsuleMenu_Init / CapsuleGraphics_AssignCapsules: who wears what
function S:assign()
  self.wearer = {}
  for slot, mon in ipairs(self:party()) do
    local id = math.floor(tonumber(mon.ballCapsule) or 0)
    if id >= 1 and id <= 12 then self.wearer[id - 1] = slot end
  end
end

function S:anim(i) return SealCase.anySeals(self:capsule(i)) and 1 or 0 end

-- CapsuleManager_CapsuleSelectionField
function S:field(i)
  local mon, a = self.wearer[i] ~= nil, self:anim(i)
  if not mon and a == 0 then return "empty" end
  if not mon and a == 1 then return "seals" end
  if mon and a == 1 then return "pokemon" end
  return "unreachable"
end

-- SealPlacement_UpdateSealsFromCapsule
function S:loadRender()
  local cap = self:capsule(self.cursor)
  self.render = {}
  for k = 1, 8 do
    local s = cap.seals[k]
    if (tonumber(s.type) or 0) ~= 0 then
      self.render[k] = { type = s.type, x = s.x, y = s.y, on = true, z = k }
    else
      self.render[k] = { type = 0, x = 0, y = 0, on = false, z = k }
    end
  end
end

-- SealPlacement_LoadCapsuleSeals: the design into the save
function S:storeRender()
  local cap = self:capsule(self.cursor)
  for k = 1, 8 do
    local r = self.render[k]
    cap.seals[k] = { type = r.on and r.type or 0, x = r.on and r.x or 0, y = r.on and r.y or 0 }
  end
end

-- SealPlacement_AnySealsChanged
function S:changed()
  local cap = self:capsule(self.cursor)
  for k = 1, 8 do
    local r, s = self.render[k], cap.seals[k]
    local t = r.on and r.type or 0
    if t ~= (tonumber(s.type) or 0) or (r.on and (r.x ~= s.x or r.y ~= s.y)) then return true end
  end
  return false
end

-- CapsuleGraphics_PopulateSealPage: the seals the case holds or a capsule
-- uses, eight a page
function S:pageSeals()
  local Seals = require("src.import.Gen4Seals")
  local list = {}
  for id = 1, 80 do
    local onAny = SealCase.inUse(self.save, id) > 0
    if Seals.caseCount(self.save, id) > 0 or onAny then list[#list + 1] = id end
  end
  self.maxPage = math.max(1, math.ceil(#list / 8))
  local out = {}
  for k = 1, 8 do out[k] = list[self.page * 8 + k] or 0 end
  return out
end

-- --------------------------------------------------------------- input --

function S:localPoint(px, py)
  if self:twoScreens() then return SecondScreen.toLocal(self.game, px, py) end
  if self.view ~= "bottom" then return nil end
  local renderer = package.loaded["src.render.Renderer"]
  local rect = renderer and renderer.uiPresentation
  if type(rect) == "table" then
    if px < rect.x or py < rect.y or px >= rect.x + rect.w or py >= rect.y + rect.h then return nil end
    px, py = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
  end
  if px < 0 or py < 0 or px >= W or py >= H then return nil end
  return px, py
end
function S:touchpressed(_, px, py)
  local x, y = self:localPoint(px, py)
  if not x then return false end
  self.touch = { x = math.floor(x), y = math.floor(y), fresh = true }
  return true
end
function S:touchmoved(_, px, py)
  if not self.touch then return true end
  local x, y = self:localPoint(px, py)
  if x then self.touch.x, self.touch.y = math.floor(x), math.floor(y) end
  return true
end
function S:touchreleased() self.touch = nil; return true end

-- the pen this frame: a real touch, or the port's d-pad stylus with A held
-- (only while editing)
function S:pen(input)
  if self.touch then
    local fresh = self.touch.fresh
    self.touch.fresh = false
    return self.touch.x, self.touch.y, fresh, true
  end
  if self.mode == "edit" and input then
    local c = self.stylus
    if input:isDown("left") then c.x = math.max(0, c.x - 3) end
    if input:isDown("right") then c.x = math.min(W - 1, c.x + 3) end
    if input:isDown("up") then c.y = math.max(0, c.y - 3) end
    if input:isDown("down") then c.y = math.min(H - 1, c.y + 3) end
    self.stylusShown = true
    if input:isDown("a") then return c.x, c.y, input:wasPressed("a"), true end
  end
  return nil
end

-- the raw buttons (Input folds Gen 4's X / Y into START / SELECT)
local function raw(input)
  local p = {}
  if not input then return p end
  local rp = input.pressed
  for _, k in ipairs({ "a", "b", "x", "y", "start", "select", "up", "down", "left", "right" }) do
    if type(rp) == "table" then p[k] = rp[k] and true or nil
    else p[k] = input:wasPressed(k) or nil end
  end
  return p
end

-- -------------------------------------------------------------- update --

function S:update()
  local input = self.game.input
  local keys = raw(input)
  self.frame = (self.frame or 0) + 1
  if self.fadeTarget then
    local step = 16 / 6
    if self.fadeTarget > self.fade then self.fade = math.min(16, self.fade + step) else self.fade = math.max(0, self.fade - step) end
    if self.fade == self.fadeTarget then self.fadeTarget = nil end
  end
  if keys.select and not self:twoScreens() then
    self.view = (self.view == "top") and "bottom" or "top"
    se(self, "SEQ_SE_DP_SELECT")
  end
  if self.throw then return self:tickThrow() end
  local m = self.mode
  if m == "select" then self:updateSelect(keys, input)
  elseif m == "menu" then self:updateMenu(keys)
  elseif m == "edit" then self:updateEdit(keys, input)
  elseif m == "remove" then
    if keys.a or keys.b or keys.x or keys.y or keys.up or keys.down or keys.left or keys.right then
      self.mode, self.message = "select", 7
    end
  elseif m == "shift" then self:updateShift(keys)
  end
end

-- CapsuleManager_HandleCapsulePadMovement
local function padMove(i, keys)
  if keys.right then return (i + 1) % 12 end
  if keys.left then return i > 0 and i - 1 or 11 end
  if keys.up then if math.floor(i / 4) ~= 0 then return (i - 4) % 12 end return nil end
  if keys.down then if math.floor(i / 4) ~= 2 then return (i + 4) % 12 end return nil end
  return nil
end

function S:updateSelect(keys, input)
  if self.state == "fadein" then
    if not self.fadeTarget then self.state = "pick" end
    return
  end
  if self.state == "fadeout" then
    if not self.fadeTarget then
      self.state = "done"
      self.game.stack:pop()
      if self.onDone then self.onDone(self.cursor) end
    end
    return
  end
  if self.touch and self.touch.fresh then
    self.touch.fresh = false
    return self:startEdit()
  end
  local to = padMove(self.cursor, keys)
  if to then
    self.cursor, self.cursor2 = to, to
    self:loadRender()
    se(self, "SEQ_SE_DP_SELECT")
  elseif keys.a then
    self:openMenu()
    se(self, "SEQ_SE_DP_SELECT")
  elseif keys.b then
    self.state, self.fadeTarget = "fadeout", 16
    se(self, "SEQ_SE_DP_DECIDE")
  end
end

-- CapsuleGraphics_OpenCapsuleSelectionMenu
function S:openMenu()
  local f = self:field(self.cursor)
  local ids
  if f == "empty" then ids = { 0, 4, 1 }
  elseif f == "pokemon" then ids = { 3, 0, 4, 1 }
  else ids = { 2, 0, 4, 1 } end
  self.menu = { ids = ids, index = 1 }
  self.mode, self.message = "menu", 8
end

function S:updateMenu(keys)
  local m = self.menu
  if keys.up then m.index = m.index > 1 and m.index - 1 or #m.ids; se(self, "SEQ_SE_DP_SELECT")
  elseif keys.down then m.index = m.index < #m.ids and m.index + 1 or 1; se(self, "SEQ_SE_DP_SELECT")
  elseif keys.b then self.mode, self.message, self.menu = "select", 7, nil
  elseif keys.a then
    local id = m.ids[m.index]
    self.menu = nil
    se(self, "SEQ_SE_DP_SELECT")
    if id == 0 then return self:startEdit()
    elseif id == 1 then self.mode, self.message = "select", 7
    elseif id == 2 then return self:startSet()
    elseif id == 3 then return self:startRemove()
    elseif id == 4 then
      self.mode, self.message, self.cursor2 = "shift", 10, self.cursor
    end
  end
end

-- ov76_0223E950: REMOVE (CapsuleManager_AssignCapsuleMon)
function S:startRemove()
  local slot = self.wearer[self.cursor]
  if slot then
    local mon = self:party()[slot]
    if mon then mon.ballCapsule = 0 end
  end
  self.wearer[self.cursor] = nil
  self.mode, self.message = "remove", 9
end

-- CapsuleManager_HandleSpritesAndInputs: SHIFT
function S:updateShift(keys)
  if self.shifted then
    if keys.a or keys.b or keys.x or keys.y or keys.up or keys.down or keys.left or keys.right then
      self.shifted, self.mode, self.message = nil, "select", 7
    end
    return
  end
  local to = padMove(self.cursor2, keys)
  if to then self.cursor2 = to; se(self, "SEQ_SE_DP_SELECT")
  elseif keys.a then
    self:swap(self.cursor, self.cursor2)
    self.cursor = self.cursor2
    self:loadRender()
    self.shifted, self.message = true, 11
    se(self, "SEQ_SE_DP_SELECT")
  elseif keys.b then
    self.cursor2 = self.cursor
    self.mode, self.message = "select", 7
    se(self, "SEQ_SE_DP_DECIDE")
  end
end

-- CapsuleGraphics_SwapCapsules
function S:swap(a, b)
  local party = self:party()
  local wa, wb = self.wearer[a], self.wearer[b]
  if wa and party[wa] then party[wa].ballCapsule = b + 1 end
  if wb and party[wb] then party[wb].ballCapsule = a + 1 end
  local ca, cb = SealCase.copy(self:capsule(a)), SealCase.copy(self:capsule(b))
  self.save.gen4SealCapsules[a + 1], self.save.gen4SealCapsules[b + 1] = cb, ca
  self:assign()
end

-- SET: the party menu (PARTY_MENU_MODE_BALL_SEAL), then back
function S:startSet()
  local game = self.game
  local idx = self.cursor
  local ok, PM = pcall(require, "src.ui.Gen4PartyMenu")
  if not ok then self.mode, self.message = "select", 7 return end
  local function open()
    game.stack:push(PM.new(game, { pickOnly = true,
      onSwitch = function(mon)
        if self:isEgg(mon) then                   -- eggs are refused
          se(self, "SEQ_SE_DP_CUSTOM06")
          return open()
        end
        se(self, "SEQ_SE_DP_SELECT")
        self:attach(mon, idx)
      end,
      onCancel = function() end }))
  end
  self.mode, self.message = "select", 7
  open()
end

-- CAPSULE_MENU_ATTACH_CAPSULE_STATE_ID
function S:attach(mon, idx)
  local cap = self:capsule(idx)
  mon.ballCapsule = idx + 1
  mon.ballCapsuleSeals = SealCase.copy(cap)
  local first = tonumber(cap.seals[1].type) or 0
  pcall(function()
    local E = require("src.battle.Gen4SealEffect")
    require("src.script.PtTvRecords").sealClub(self.save, mon, E.NAME[first] or 0)
  end)
  self:assign()
end

-- ---------------------------------------------------------------- edit --

-- CapsuleManager_HandleCancelUpdateSeals: CAPSULE_INIT_STATE_ID
function S:startEdit()
  local Seals = require("src.import.Gen4Seals")
  self.mode, self.message = "edit", nil
  self.view = "bottom"
  self.snapshot = SealCase.copy(self:capsule(self.cursor))     -- activeCapsule
  self.snapCounts = {}                                          -- sealCounts
  for id = 1, 80 do self.snapCounts[id] = Seals.caseCount(self.save, id) end
  self:loadRender()
  self.page = 0
  self.drag = nil
  self.sealName = nil
end

local function nextZ(self)
  local z = 0
  for k = 1, 8 do if self.render[k].on then z = math.max(z, self.render[k].z or 0) end end
  return z + 1
end

function S:updateEdit(keys, input)
  local Seals = require("src.import.Gen4Seals")
  if self.ask then return self:updateAsk(keys) end
  local x, y, fresh, held = self:pen(input)
  local d = self.drag
  if d then
    local r = self.render[d]
    if held and x then
      r.x, r.y = math.max(0, math.min(255, x)), math.max(0, math.min(191, y))
      self.sealName = r.type
    else
      -- SealPlacement_SealIsValid: more than 60 from the centre goes back
      if SealCase.distance(r.x, r.y, CENTER_X, CENTER_Y) > RADIUS then
        SealCase.giveBack(self.save, r.type, 1)
        self.render[d] = { type = 0, x = 0, y = 0, on = false, z = d }
      end
      se(self, "SEQ_SE_DP_BOX01")
      self.drag, self.sealName = nil, nil
    end
    return
  end
  if not (x and fresh) then
    if keys.b then return self:pressCancel() end
    return
  end
  -- a placed seal under the pen (its 20 x 20 touch rect), the frontmost first
  local best
  for k = 1, 8 do
    local r = self.render[k]
    if r.on and math.abs(x - r.x) <= 10 and math.abs(y - r.y) <= 10 then
      if not best or (r.z or 0) > (self.render[best].z or 0) then best = k end
    end
  end
  if best then
    self.drag = best
    self.render[best].z = nextZ(self)
    self.sealName = self.render[best].type
    se(self, "SEQ_SE_DP_BOX02")
    return
  end
  local ids = self:pageSeals()
  for k = 1, 8 do
    if inside(ICON_RECT[k], x, y) then
      local id = ids[k]
      local free
      for j = 1, 8 do if not self.render[j].on then free = j break end end
      if not free then
        se(self, "SEQ_SE_DP_CUSTOM06"); self.editMessage = 15
      elseif id ~= 0 and Seals.caseCount(self.save, id) > 0 then
        self.render[free] = { type = id, x = x, y = y, on = true, z = nextZ(self) }
        self.drag = free
        self.sealName = id
        Seals.change(self.save, id, -1)
        se(self, "SEQ_SE_DP_BOX02")
      elseif id ~= 0 then
        se(self, "SEQ_SE_DP_CUSTOM06"); self.editMessage = 16
      end
      return
    end
  end
  if inside(PAGE_UP, x, y) then
    self:pageSeals()
    self.page = self.page > 0 and self.page - 1 or (self.maxPage - 1)
    se(self, "SEQ_SE_DP_CUSTOM02")
  elseif inside(PAGE_DOWN, x, y) then
    self:pageSeals()
    self.page = (self.page + 1) % self.maxPage
    se(self, "SEQ_SE_DP_CUSTOM02")
  elseif inside(THROW, x, y) then
    se(self, "SEQ_SE_DP_DECIDE")
    self:startThrow()
  elseif inside(CONFIRM, x, y) then
    se(self, "SEQ_SE_DP_PIRORIRO")
    self:confirm()
  elseif inside(CANCEL, x, y) then
    self:pressCancel()
  end
end

-- CAPSULE_FADE_OUT_WAIT_STATE_ID: keep the design
function S:confirm()
  -- SealPlacement_UpdateSeals: the seals stored in their drawing order
  local order = {}
  for k = 1, 8 do if self.render[k].on then order[#order + 1] = self.render[k] end end
  table.sort(order, function(a, b) return (a.z or 0) < (b.z or 0) end)
  for k = 1, 8 do
    local r = order[k]
    self.render[k] = r and { type = r.type, x = r.x, y = r.y, on = true, z = k }
                     or { type = 0, x = 0, y = 0, on = false, z = k }
  end
  self:storeRender()
  pcall(function()
    local R = require("src.pokemon.Gen4GameRecords")
    R.score(self.save, R.EVENT.UNK_06)
  end)
  local slot = self.wearer[self.cursor]
  local mon = slot and self:party()[slot]
  if mon then mon.ballCapsuleSeals = SealCase.copy(self:capsule(self.cursor)) end
  self.mode, self.message, self.editMessage = "select", 12, nil
  self.view = "top"
end

-- CAPSULE_CANCEL_PRESSED_STATE_ID
function S:pressCancel()
  se(self, "SEQ_SE_DP_DECIDE")
  if not self:changed() then
    self.mode, self.message, self.editMessage = "select", 7, nil
    self.view = "top"
    return
  end
  self.ask = { index = 1 }
end

function S:updateAsk(keys)
  local a = self.ask
  local x, y, fresh = self:pen(self.game.input)
  local pick
  if fresh and x then
    -- YesNoTouchMenu at tile (25, 6): YES above NO, 6 x 4 tiles each
    if x >= 200 and x < 248 and y >= 48 and y < 80 then pick = 1 end
    if x >= 200 and x < 248 and y >= 80 and y < 112 then pick = 2 end
  end
  if keys.up or keys.down then a.index = 3 - a.index; se(self, "SEQ_SE_DP_SELECT") end
  if keys.a then pick = a.index end
  if keys.b then pick = 2 end
  if not pick then return end
  self.ask = nil
  se(self, "SEQ_SE_DP_SELECT")
  if pick == 1 then
    -- CapsuleManager_CopyFromActiveCapsule + SetSealCounts
    self.save.gen4SealCapsules[self.cursor + 1] = SealCase.copy(self.snapshot)
    self.save.gen4Seals = self.save.gen4Seals or {}
    for id = 1, 80 do self.save.gen4Seals[id] = self.snapCounts[id] end
    self:loadRender()
    self.mode, self.message, self.editMessage = "select", 12, nil
    self.view = "top"
  end
end

-- ---------------------------------------------------------------- throw --

-- CapsuleManager_LoadLeadingPokemon
function S:leadMon()
  local slot = self.wearer[self.cursor]
  if slot and self:party()[slot] then return self:party()[slot] end
  for _, mon in ipairs(self:party()) do if not self:isEgg(mon) then return mon end end
end

function S:startThrow()
  local mon = self:leadMon()
  local cap = { seals = {} }
  for k = 1, 8 do
    local r = self.render[k]
    cap.seals[k] = { type = r.on and r.type or 0, x = r.x, y = r.y }
  end
  local okE, fx = pcall(function() return require("src.battle.Gen4SealEffect").new(self.data, cap, 1) end)
  -- THROW_WAIT_INIT_THROW_STATE_ID: the Pokemon's own ball thrown out
  -- (ov12_02237728, BALL_THROW_MODE_SEND_OUT) -- the port's thrown-ball
  -- animation (Gen4BallAnim, release) to the stage at (192, 88); the seals
  -- and the Pokemon come out when it opens (THROW_WAIT_FOR_END_STATE_ID)
  local ball
  pcall(function()
    local Gen4Battle = require("src.battle.Gen4Battle")
    ball = require("src.battle.Gen4BallAnim").new({
      ball = Gen4Battle.ballThrowFor(mon and (mon.ball or mon.pokeball)),
      mode = "release", side = "player", to = { x = 192, y = 88 },
    })
  end)
  self.throw = { mon = mon, fx = okE and fx or nil, t = 0, scale = 0, phase = ball and "ball" or "in", ball = ball }
  self.message = 13
  self.view = "top"
end

-- THROW_*_STATE_ID: the Pokemon grows in (0x20 / 0x100 a frame), the seals
-- spray, 30 frames' rest, it shrinks away
function S:tickThrow()
  local th = self.throw
  th.t = th.t + 1
  if th.ball then
    pcall(th.ball.update, th.ball)
    if th.ball:isDone() then th.ball = nil end
  end
  if th.phase == "ball" then
    -- until the ball opens (its "arc" phase ends)
    local arc = th.ball and th.ball.throw and tonumber(th.ball.throw.frames) or 0
    if not th.ball or th.t >= arc then th.phase, th.t = "in", 0 end
    return
  end
  if th.fx and th.phase ~= "out" then th.fx:update() end
  if th.phase == "in" then
    th.scale = math.min(1, th.scale + 0x20 / 0x100)
    if th.scale >= 1 and th.t == 9 then se(self, "SEQ_SE_DP_CUSTOM05") end
    if th.scale >= 1 and (not th.fx or th.fx:isDone()) then th.phase, th.rest = "rest", 0 end
  elseif th.phase == "rest" then
    th.rest = th.rest + 1
    if th.rest >= 30 then th.phase = "out" end
  else
    th.scale = math.max(0, th.scale - 0x20 / 0x100)
    if th.scale <= 0 then
      self.throw, self.message = nil, nil
      self.view = "bottom"
    end
  end
end

-- ------------------------------------------------------------- drawing --

function S:image(rec)
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil
end

function S:picture(rec, x, y, alpha, scale)
  local img = self:image(rec)
  if not img then return end
  love.graphics.setColor(1, 1, 1, alpha or 1)
  local s = scale or 1
  love.graphics.draw(img, x, y, 0, s, s, -(rec.originX or 0), -(rec.originY or 0))
  love.graphics.setColor(1, 1, 1, 1)
end

local function cellAt(frames, tick)
  if not frames or #frames == 0 then return 0 end
  local total = 0
  for _, f in ipairs(frames) do total = total + math.max(1, f[2] or 1) end
  local t, acc = math.floor(tick or 0) % total, 0
  for _, f in ipairs(frames) do
    acc = acc + math.max(1, f[2] or 1)
    if t < acc then return f[1] end
  end
  return frames[1][1]
end

function S:sprite(group, anim, x, y, tick)
  local g = (self.art.groups or {})[group]
  if not g then return end
  local cell = cellAt(g.seqs and g.seqs[anim or 0], tick or self.frame or 0)
  local rec = g.cells and g.cells[cell]
  if rec then self:picture(rec, x, y) end
end

local function backdrop(c)
  local g = love.graphics
  c = c or { 0, 0, 0 }
  g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
end

-- bank 8 on Platinum; HeartGold / SoulSilver's overlay 57 opens bank 11
-- (NewMsgDataFromNarc(0, 0x1B, 0xB, ...), READ FROM its asm)
local function words(self, n)
  local T = require("src.import.Gen4Text")
  return (self.data.text or {})[T.label(self.art.hgss and 11 or BANK, n)] or ""
end

local function drawText(t, x, y)
  local Font = require("src.render.Font")
  for line in (tostring(t) .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, x, y)
    y = y + 16
  end
end

function S:drawIcon(mon, x, y)
  local PM = require("src.ui.Gen4PartyMenu")
  local okI, img, frameH = pcall(PM.iconFor, { game = self.game, icons = self.iconCache }, mon)
  if not (okI and img) then return end
  frameH = frameH or 32
  local frames = math.max(1, math.floor(img:getHeight() / frameH))
  local f = math.floor((self.frame or 0) / 10) % frames
  local q = love.graphics.newQuad(0, f * frameH, img:getWidth(), frameH, img:getWidth(), img:getHeight())
  love.graphics.draw(img, q, x - img:getWidth() / 2, y - frameH / 2)
end

-- THE TOP SCREEN: the capsules
function S:drawTop()
  local g = love.graphics
  backdrop(self.art.backdropMain)
  local bg = self.art.bg or {}
  if bg.main2 then self:picture(bg.main2, 0, 0) end
  if self.mode == "edit" or self.throw then
    if bg.main3 then self:picture(bg.main3, 0, 0) end
  end
  if self.throw then
    local th = self.throw
    local mon = th.mon
    if mon then
      local Sprites = require("src.pokemon.Sprites")
      local okP, path = pcall(Sprites.path, self.data, mon.species, "front", { mon = mon, kind = "summary" })
      local img = okP and self:image(path)
      if img and th.scale > 0 then
        local w, h = img:getDimensions()
        g.draw(img, 192, 48 + h / 2 - 8, 0, th.scale, th.scale, w / 2, h / 2)
      end
    end
    if th.fx and th.phase ~= "ball" then th.fx:draw(192, 80) end
    if th.ball then
      pcall(function()
        require("src.battle.Gen4Battle").drawThrownBall({ gen4Ball = th.ball, data = self.data, game = self.game })
      end)
    end
  elseif self.mode ~= "edit" then
    -- (editing turns the top screen's OBJ layer off: GXLayers_EngineAToggle-
    -- Layers(GX_PLANEMASK_OBJ, 0) at CAPSULE_FADE_IN_STATE_ID)
    for i = 0, 11 do
      local x, y = 40 + 56 * (i % 4), 27 + 53 * math.floor(i / 4)
      self:sprite("capsule", self:anim(i), x, y, 0)
      local slot = self.wearer[i]
      local mon = slot and self:party()[slot]
      if mon then self:drawIcon(mon, x - 16, y + 12) end
    end
    local cx, cy = 40 + 56 * (self.cursor % 4), 27 + 53 * math.floor(self.cursor / 4)
    self:sprite("cursor", (self.mode == "shift") and 1 or 0, cx, cy)
    if self.mode == "shift" then
      local sx, sy = 40 + 56 * (self.cursor2 % 4), 27 + 53 * math.floor(self.cursor2 / 4)
      self:sprite("cursor", 0, sx, sy)
    end
  end
  local Font = require("src.render.Font")
  if self.message then
    Font.drawBox(1, 20, 29, 4)
    g.setColor(0, 0, 0, 1)
    drawText(words(self, self.message), 2 * 8 + 1, 21 * 8 - 3)
    g.setColor(1, 1, 1, 1)
  end
  if self.menu then
    local n = #self.menu.ids
    local top = (n == 3) and 13 or 11
    Font.drawBox(20, top - 1, 11, n * 2 + 2)
    g.setColor(0, 0, 0, 1)
    for k, id in ipairs(self.menu.ids) do
      Font.draw(words(self, id), 22 * 8 + 4, (top + (k - 1) * 2) * 8 + 2)
    end
    Font.draw(">", 21 * 8 + 2, (top + (self.menu.index - 1) * 2) * 8 + 2)
    g.setColor(1, 1, 1, 1)
  end
end

-- THE TOUCH SCREEN
function S:drawBottom()
  local g = love.graphics
  local Font = require("src.render.Font")
  local Seals = require("src.import.Gen4Seals")
  backdrop(self.art.backdropSub)
  local bg = self.art.bg or {}
  local editing = self.mode == "edit"
  if editing then
    if bg.sub3 then self:picture(bg.sub3, 0, 0) end
  elseif bg.sub1 then self:picture(bg.sub1, 0, 0) end
  -- the capsule's seals: on the big ball at (-56, +16) while choosing
  -- (SealPlacement_OffsetSeals), where they are while editing
  local order = {}
  for k = 1, 8 do if self.render[k].on then order[#order + 1] = self.render[k] end end
  table.sort(order, function(a, b) return (a.z or 0) < (b.z or 0) end)
  for _, r in ipairs(order) do
    local rec = self.art.seals[tonumber(r.type)]
    if rec then
      local x, y = r.x, r.y
      if not editing then x, y = x - 56, y + 16 end
      -- SealPlacement_UpdateSealOamMode: outside the ball, see-through
      local out = editing and SealCase.distance(r.x, r.y, CENTER_X, CENTER_Y) > RADIUS
      self:picture(rec, x, y, out and 0.5 or 1)
    end
  end
  if editing then
    local ids = self:pageSeals()
    for k = 1, 8 do
      local id = ids[k]
      if id ~= 0 then
        local rec = self.art.icons[id]
        if rec then self:picture(rec, ICON_XY[k][1], ICON_XY[k][2]) end
        g.setColor(0, 0, 0, 1)
        Font.draw(tostring(Seals.caseCount(self.save, id)), ICON_XY[k][1] + 14, ICON_XY[k][2] - 6)
        g.setColor(1, 1, 1, 1)
      end
    end
    self:sprite("pageUp", 0, 27, 124)
    self:sprite("pageDown", 0, 67, 124)
    self:sprite("throw", 0, 32, 171)
    self:sprite("button", 0, 104, 171)
    self:sprite("button", 0, 192, 171)
    g.setColor(1, 1, 1, 1)
    Font.draw(words(self, 5), 104 - Font.width(words(self, 5)) / 2, 164)
    Font.draw(words(self, 6), 192 - Font.width(words(self, 6)) / 2, 164)
    for _, a in ipairs(ARROWS) do self:sprite("arrow", a[3], a[1], a[2]) end
    if self.sealName then
      local name = Seals.name(self.data, self.sealName) or ""
      g.setColor(0, 0, 0, 1)
      Font.draw(name, 8, 138)
      g.setColor(1, 1, 1, 1)
    end
    if self.editMessage or self.ask then
      Font.drawBox(0, 0, 32, 5)
      g.setColor(0, 0, 0, 1)
      drawText(words(self, self.ask and 14 or self.editMessage), 9, 7)
      g.setColor(1, 1, 1, 1)
    end
    if self.ask then
      for k = 1, 2 do
        Font.drawBox(25, 4 + k * 4, 6, 4)
        g.setColor(0, 0, 0, 1)
        Font.draw(k == 1 and "YES" or "NO", 25 * 8 + 10, (4 + k * 4) * 8 + 10)
        g.setColor(1, 1, 1, 1)
      end
      g.setColor(1, 0.3, 0.3, 1)
      g.rectangle("line", 200, 48 + (self.ask.index - 1) * 32, 48, 32)
      g.setColor(1, 1, 1, 1)
    end
    if self.stylusShown and not self.touch then
      g.setColor(1, 1, 1, 0.9)
      g.circle("line", self.stylus.x, self.stylus.y, 4)
      g.setColor(1, 1, 1, 1)
    end
  end
end

function S:drawFade()
  if self.fade > 0 then
    local g = love.graphics
    g.setColor(0, 0, 0, math.min(1, self.fade / 16))
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
end

function S:draw()
  if self:twoScreens() then
    self:drawTop()
    self:drawFade()
    SecondScreen.draw(self.game, function()
      self:drawBottom()
      self:drawFade()
    end)
    return
  end
  if self.view == "bottom" then self:drawBottom() else self:drawTop() end
  self:drawFade()
end

-- ------------------------------------------------ the script's command --
-- `opensealcapsuleeditor` (CapsuleMenu_StartFieldTask): the app, the script
-- paused until it closes; the capsule index carried between openings
function S.run(ctx)
  local game = ctx and ctx.game
  if not (game and game.stack and S.available(game)) then return false end
  local runner = ctx.runner
  game.stack:push(S.new(game, function()
    if runner then runner:resume() end
  end, 0))
  if runner then runner:yield() end
  return true
end

return S
