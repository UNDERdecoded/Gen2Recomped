-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 88: GANON'S TOWER'S SEAL (zelda3 names; traced on the GBA).
--
-- THE TRIGGER. Area 0x43's sprite lists (phases 2 / 3) hold sprite 0x37
-- (the waterfall trigger) under the sealed doors. Its routine (GBA
-- 0x0810BD5C, through the per-kind table 0x0817CBAC): Sprite_ReturnIfInactive
-- (0x080C3438), then on contact (Sprite_CheckDamageToLink_same_layer,
-- 0x080C500C) in the area of `cmp r0, #imm` (0x0810BD82) it calls
-- AncillaAdd_GTCutscene (0x08124178), elsewhere the waterfall splash.
-- AncillaAdd_GTCutscene: nothing when +0x1791 bit 7 | link_auxiliary_state
-- (+0x1702), when (crystals 0x0200235A & imm) != imm (0x0812419A /
-- 0x0812419E) or when save_ow_event_info[area] (0x02002280 + area) has the
-- bit of `movs r0, #imm` (0x081241A8); else the cutscene ancilla 0x43, every
-- sprite of type `cmp r0, #imm` (0x081241E6) gone, Link held (+0x1770). The
-- ancilla (0x0812430C) shows the crystals; its last part counts the timer
-- 0x02006892 (set to the immediate at 0x08124270) down to 0, then
-- trigger_special_entrance (+0xB6E) = `movs r0, #imm` (0x08124568), the
-- sequence counter (+0x9E8) 0.
--
-- THE ENTRANCE. Overworld_AnimateEntrance (0x0808F148: +0x1770 / +0x1605 /
-- +0xC90 = the trigger, then table 0x08153BF0[trigger - 1]); the tower's
-- routine 0x0808F440 steps table 0x08153BBC by +0x9E8: the screen whitened
-- and back (0x08132B4C: sound, the fade level +0xCF8) three times, the event
-- bit set, then every 32-52 frames a draw step (sounds, map16 tiles through
-- Overworld_DrawMap16_Persist 0x0808B8B8 / 0x0808B948 at area-relative
-- positions converted by 0x08092568), the end 0x0808D788 (sound,
-- trigger 0, Link free). Instead of a copy of those steps, the import runs
-- them (FrontRun's Thumb interpreter, the draw / sound routines hooked) and
-- keeps what they do frame by frame: data.t.gt88.seq. The opened entrance on
-- a later visit is the last tile drawn at each position; the import checks
-- it against the area's event overlay (Overworld_LoadEventOverlay's routine
-- 0x153C04[area], run by Castle44.runThumb): the same map8 words.
--
-- OURS: the crystals' picture and their first parts (they rise, circle and
-- close in) are not drawn; Link waits the ancilla's final timer only; the
-- fade is a white veil timed by the whitening routine's step counter; the
-- sprite's contact is tested every frame (the cartridge: every 4th by slot)
-- and does not hurt.

local bit = require("bit")
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local M = {}

M.A = {
  base = 0x03002230, trig = 0xB6E, ctr = 0x9E8, screen = 0x9C6, fade = 0xCF8,
  dispatch = 0x0808F148,                       -- Overworld_AnimateEntrance (r0 = trigger)
  drawAt = 0x0808B8B8, drawNext = 0x0808B948,  -- Overworld_DrawMap16_Persist (at +0x96C / next)
  toMap = 0x08092568, sound = 0x0812A324,
  overlayFns = 0x153C04,
}
M.SITES = {
  area = 0x0810BD82,    -- cmp r0, #area (the sprite's routine)
  mask = 0x0812419A,    -- movs r0, #mask (crystals)
  maskCmp = 0x0812419E, -- cmp r0, #mask
  bit = 0x081241A8,     -- movs r0, #bit (save_ow_event_info)
  spr = 0x081241E6,     -- cmp r0, #type (the sprites removed: the trigger's own type)
  timer = 0x08124270,   -- movs r0, #timer (the ancilla's last countdown)
  trigger = 0x08124568, -- movs r0, #trigger (trigger_special_entrance)
}

local function off(a) return a - 0x08000000 end
local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= op then return nil end
  return band(h, 0xFF)
end

-- run the tower's entrance routine frame by frame; returns the frames'
-- draws / sounds / fade levels (nil, why on anything unexpected)
function M.runSequence(romStr, area, trigger, maxFrames)
  local FR = require("src.zelda.alttp.FrontRun")
  local A = M.A
  local S = FR.new(romStr)
  local r, iw = S.r, S.iw
  local function ib(a) return iw[(a - 0x03000000) % 0x8000] end
  local function sb(a, v) iw[(a - 0x03000000) % 0x8000] = v % 256 end
  local function rmem(a)
    local o = (a - 0x03000000) % 0x8000
    return iw[o] + iw[o + 1] * 256 + iw[o + 2] * 65536 + iw[o + 3] * 16777216
  end
  local function wmem(a, v)
    local o = (a - 0x03000000) % 0x8000
    for k = 0, 3 do iw[o + k] = v % 256; v = math.floor(v / 256) end
  end
  local seq = { frames = 0, ev = {}, fade = {} }
  local f = 0
  local cur
  local function ev() local e = seq.ev[f] or { draws = {}, sounds = {} }; seq.ev[f] = e; return e end
  local function ret() r[15] = r[14] - r[14] % 2; return true end
  S.hooks[A.sound] = function() local e = ev(); e.sounds[#e.sounds + 1] = r[0] % 256; return ret() end
  S.hooks[A.toMap] = function() cur = r[0]; return false end
  S.hooks[A.drawAt] = function()
    local e = ev(); e.draws[#e.draws + 1] = { cur, math.floor(r[0] / 4) }; return ret()
  end
  S.hooks[A.drawNext] = function()
    if r[0] < 0x03000000 or r[1] < 0x03000000 then error("Gt88: draw pointers outside IWRAM", 0) end
    local id4, pos = rmem(r[0]), rmem(r[1])
    local e = ev(); e.draws[#e.draws + 1] = { pos, math.floor(id4 / 4) }
    wmem(r[0], id4 + 4); wmem(r[1], pos + 2)
    return ret()
  end
  sb(A.base + A.screen, area); sb(A.base + A.screen + 1, 0)
  sb(A.base + A.trig, trigger)
  local ok, why = pcall(function()
    for k = 1, maxFrames or 4000 do
      f = k
      r[13] = 0x03007E00
      S.call(A.dispatch + 1, S.steps + 2000000, ib(A.base + A.trig))
      seq.fade[k] = ib(A.base + A.fade) + ib(A.base + A.fade + 1) * 256
      if ib(A.base + A.trig) == 0 then seq.frames = k; return end
    end
    error("Gt88: the entrance routine did not end", 0)
  end)
  if not ok then return nil, tostring(why) end
  -- the event byte the routine set
  seq.event = S.ew[(0x02002280 + area) % 0x40000]
  return seq
end

-- the last tile drawn at each position (the opened entrance)
function M.finals(seq)
  local last, order = {}, {}
  for k = 1, seq.frames do
    local e = seq.ev[k]
    for _, d in ipairs(e and e.draws or {}) do
      if last[d[1]] == nil then order[#order + 1] = d[1] end
      last[d[1]] = d[2]
    end
  end
  local out = {}
  for _, p in ipairs(order) do out[#out + 1] = { p, last[p] } end
  return out
end

function M.extract(rom, R, check)
  local S = M.SITES
  local t = {}
  t.area = imm8(rom, S.area, 0x2800)
  t.mask = imm8(rom, S.mask, 0x2000)
  local mask2 = imm8(rom, S.maskCmp, 0x2800)
  t.bit = imm8(rom, S.bit, 0x2000)
  t.spr = imm8(rom, S.spr, 0x2800)
  t.timer = imm8(rom, S.timer, 0x2000)
  t.trigger = imm8(rom, S.trigger, 0x2000)
  check(t.area and t.mask and mask2 == t.mask and t.bit and t.spr and t.timer and t.trigger and t.trigger >= 1 and t.trigger <= 8,
        "Ganon's Tower trigger sites (area, crystals, event bit, sprite, timer, trigger)")
  if not (t.area and t.trigger and rom.data) then return t end
  local seq, why = M.runSequence(rom.data, t.area, t.trigger)
  check(seq ~= nil, "Ganon's Tower entrance routine run: %s", tostring(why))
  if not seq then return t end
  check(band(seq.event or 0, t.bit or 0) ~= 0, "the entrance routine sets the area's event bit")
  t.seq = seq
  t.final = M.finals(seq)
  check(#t.final >= 2 and #t.final <= 32, "Ganon's Tower entrance: %d tiles", #t.final)
  -- the map16 words of every id drawn (merged into the room index at run time)
  t.map16 = {}
  for k = 1, seq.frames do
    for _, d in ipairs(seq.ev[k] and seq.ev[k].draws or {}) do
      if R and R.map16 and not t.map16[d[2]] then t.map16[d[2]] = rom:bytesU16(R.map16 + d[2] * 8, 4) end
    end
  end
  -- the area's event overlay draws the same words as the last tiles
  local fn = rom:u32(M.A.overlayFns + t.area * 4)
  local okOv = false
  if R and R.map16 and fn >= 0x08000000 then
    local stores = require("src.zelda.alttp.Castle44").runThumb(rom, band(fn, bnot(1)) - 0x08000000, 1024)
    if stores and #stores == #t.final * 4 then
      local want = {}
      for _, p in ipairs(t.final) do for _, w in ipairs(t.map16[p[2]]) do want[w] = (want[w] or 0) + 1 end end
      okOv = true
      for _, s in ipairs(stores) do
        if (want[s[2]] or 0) == 0 then okOv = false break end
        want[s[2]] = want[s[2]] - 1
      end
    end
  end
  check(okOv, "Ganon's Tower: the last tiles match the area's event overlay")
  return t
end

-- ------------------------------------------------------------ run time
local function T(game) return game.data and game.data.t and game.data.t.gt88 end

local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
function M.done(game, t)
  return band(events(game)[tostring(t.area)] or 0, t.bit) ~= 0
end

local function mergeMap16(game, t)
  local idx = game.data.roomIdx
  if not (idx and idx.map16) or game.gt88Map16 then return end
  game.gt88Map16 = true
  for k, v in pairs(t.map16 or {}) do if not idx.map16[k] then idx.map16[k] = v end end
end

local function draw16(game, pos, id)
  local a = game.area
  local x = a.x + (pos % 128) / 2 * 16
  local y = a.y + math.floor(pos / 128) * 16
  game:owSetMap16(x, y, id)
end

-- the trigger sprite's spot in the area's list (phase 2 / 3 lists)
function M.spot(game, t)
  local n = game.data.t and game.data.t.npc
  if not n then return nil end
  local prog = game:storyProgress()
  local phase = (prog == 2 and 2) or (prog == 3 and 3) or 1
  local l = n.ow[phase] and n.ow[phase][t.area + 1]
  local bx = (t.area % 8) * 512
  local by = math.floor((t.area % 64) / 8) * 512
  for _, e in ipairs(l or {}) do
    if e[3] == t.spr then return bx + e[2] * 16, by + e[1] * 16 end
  end
  return nil
end

function M.canStart(game, t)
  local lk = game.link
  if M.done(game, t) then return false end
  if band(game.progress.crystals or 0, t.mask) ~= t.mask then return false end
  if game.recoil or game.cape or (lk.z or 0) > 0 then return false end
  local x, y = M.spot(game, t)
  if not x then return false end
  local Actors = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not cb then return false end
  local hx, hy, hw, hh = Actors.hitbox(cb, { type = t.spr, x = x, y = y })
  local lx, ly, lw, lh = Actors.linkBox(lk)
  return Actors.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh)
end

-- the veil (OURS): the whitening routine's step counter +0xCF8 runs 0..64
-- per flash (0xFF when idle); white up to step 31, back down after
function M.veil(c)
  if c <= 0 or c >= 0xFF then return 0 end
  local v = c <= 31 and c or math.max(0, 63 - c)
  return math.min(1, v / 31) * 0.85
end

local function sfx(game, id)
  pcall(require("src.zelda.alttp.Sfx").start, game, id, "gt88")
end

-- one frame; true while the cutscene holds Link
function M.frame(game, inp)
  local t = T(game)
  if not (t and t.seq) or game.interior then return false end
  local lk = game.link
  if lk.world ~= "dw" or not game.area or game.area.parent ~= t.area then
    game.gt88Key, game.gt88 = nil, nil
    return false
  end
  local s = game.gt88
  if s then
    s.t = s.t + 1
    if s.phase == "crystals" then
      if s.t >= t.timer then s.phase, s.t = "entrance", 0 end
    else
      local e = t.seq.ev[s.t]
      if e then
        for _, id in ipairs(e.sounds) do sfx(game, id) end
        if #e.draws > 0 then mergeMap16(game, t) end
        for _, d in ipairs(e.draws) do draw16(game, d[1], d[2]) end
      end
      if s.t == 1 then
        local ev = events(game)
        ev[tostring(t.area)] = bor(ev[tostring(t.area)] or 0, t.bit)
      end
      game.gt88Fade = t.seq.fade[s.t] or 0
      if s.t >= t.seq.frames then
        game.gt88, game.gt88Fade = nil, 0
        game.gt88Key = game.area.parent
        game.gt88Opened = (game.gt88Opened or 0) + 1
        return false
      end
    end
    lk.moving, lk.steps = false, 0
    return true
  end
  -- the opened entrance stays (drawn again whenever the area loads)
  if M.done(game, t) then
    if game.gt88Key ~= game.area.parent then
      mergeMap16(game, t)
      for _, p in ipairs(t.final) do draw16(game, p[1], p[2]) end
      game.gt88Key = game.area.parent
    end
    return false
  end
  if M.canStart(game, t) then
    game.gt88 = { phase = "crystals", t = 0 }
    game.gt88Starts = (game.gt88Starts or 0) + 1
    lk.moving, lk.steps = false, 0
    return true
  end
  return false
end

function M.install(G)
  if G.gt88Installed then return end
  G.gt88Installed = true
  local owFrame0 = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if M.frame(self, inp) then return true end
    return owFrame0(self, inp)
  end
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    self.gt88, self.gt88Key, self.gt88Fade = nil, nil, 0
    return enter0(self, e)
  end
  local leave0 = G.leaveRoom
  function G:leaveRoom()
    self.gt88Key = nil
    return leave0(self)
  end
  local xf0 = G.drawCrossfade
  function G:drawCrossfade()
    if xf0 then xf0(self) end
    local lv = M.veil(self.gt88Fade or 0)
    if lv > 0 and love and love.graphics then
      local lg = love.graphics
      lg.push("all")
      lg.setColor(1, 1, 1, lv)
      lg.rectangle("fill", -4096, -4096, 8192, 8192)
      lg.pop()
    end
  end
end

return M
