-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LATER PALACES (round 26, team B): the hub that loads the palace
-- modules (Hera.lua, the bosses' files...) into Palace.lua's registry
-- (Palace.register), imports their GBA tables (data.t.d26) and runs the
-- dungeon-wide mechanics the SNES code the GBA keeps runs for every palace
-- (zelda3 names; GBA file offsets found by value, r26b/py/tabfind.py and
-- dmd26.py):
--
--   * the crystal switch (Sprite_1E_CrystalSwitch): a hit (sprite_F 15,
--     B held < 9 frames) toggles orange_blue_barrier_state when F passes
--     11; its palette is kCrystalSwitchPal[state] (2 / 4); touching it
--     stops a dash. Module07_16_UpdatePegs freezes the game 16 frames and
--     swaps the peg tiles (VRAM tiles 0x1D0-0x1D7 = main tileset slot 7
--     tiles 16-23: the GBA's slot-7 sheet IS bg sheet 0x0F, whose tiles
--     0-3 / 4-7 / 8-11 / 12-15 are the four peg frames that
--     Dungeon_UpdatePegGFXBuffer picks: steps (0x80, 0x100), (0x100, 0x80),
--     then RecoverPegGFXFromMapping (0, 0x180) / (0x180, 0)), then
--     Dungeon_FlipCrystalPegAttribute swaps attributes 0x66 <-> 0x67 on both
--     tables. The state is reset by Dungeon_LoadEntrance and applied again
--     to every room loaded (Dungeon_LoadAttributeTable's flip).
--   * pits (TileBehavior_Pit 0x20, 0xB0-0xBD): Player_TileDetectNearby's
--     four points (x, y + 8), (x, y + 23), (x + 15, y + 8), (x + 15, y + 23);
--     all four in a pit -> LinkState_FallingIntoHole: 6 steps of 10 frames,
--     then the room's dung_hdr_travel_destinations[0] (header byte 9) on
--     the level of dung_hdr_hole_teleporter_plane (header byte 7 & 3), or
--     -- in a room of kDungeonPitsHurtPlayer (GBA 0x1676FE, 57 rooms) --
--     8 damage and back to where Link came from (DungeonPitDoDamage).
--     Some but not all points in a pit pull Link towards it
--     (kFallHolePitDirs / kFallHoleDirs2).
--   * the boss death (sprite_state 4, SpriteModule_Explode): delay 255 (or
--     224), the boss still running while delay >= 64, an explosion every 8
--     frames below 0xC0, gone at 32 and the heart container 0xEA if the
--     screen is clear (SpriteExplode_SpawnEA).
--
-- OURS: no sound; the crystal switch's sparkle garnish; Link's falling
-- poses (he shrinks instead) and the landing drop's speed (4 px a frame);
-- the explosions use the death puff (the GBA's halfslot explosion chars are
-- not loaded); the pull towards a pit is 1 px a frame.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local D = {}

-- the palace modules (loaded in this order; a missing file is skipped)
D.MODULES = { "Hera", "Agahnim", "PalaceOfDarkness", "SwampPalace", "SkullWoods", "ThievesTown",
              "IcePalace", "MiseryMire", "TurtleRock", "GanonsTower", "Ganon", "Enemies26",
              -- r27b: the later palaces' common enemies, traps, mechanics, maidens and the ending
              "Enemies27A", "Enemies27B", "Traps27", "Mech27", "Floors27", "Ending27" }
D.loaded = {}

D.OFF = {
  pitsHurt = 0x1676FE,     -- kDungeonPitsHurtPlayer (57 rooms)
  sine = 0x173F38,         -- kSinusLookupTable (256 u16, half a wave)
  explodeXY = 0x172F9C,    -- kSpriteExplode_RandomXY (16)
  overlays = 0x1633C8,     -- kDungeonRoomOverlay pointers (21; GBA Module07_03 0x080886B4)
  pred = 0x164520,         -- kPredefinedTileData (SrcPtr; RoomObjects' bomb floor = +0x220)
}
D.BOOM = 0x1FF             -- (our pseudo type for a boss explosion)
D.CRYSTAL = 0x1E
D.CRYSTAL_PAL = { [0] = 2, 4 }   -- kCrystalSwitchPal (code constants)
D.PEG = { tile = 0x1D0, slot = 7, first = 16 }   -- VRAM tiles 0x1D0-0x1D7 = slot 7 tiles 16..23

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
D.s8, D.s16 = s8, s16
-- GBA DrawMultipleData: x, y (s16), char, flags, (pad), big
function D.dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

local function mods()
  local out = {}
  for _, n in ipairs(D.MODULES) do
    local m = D.loaded[n]
    if m == nil then
      local ok, r = pcall(require, "src.zelda.alttp." .. n)
      m = ok and r or false
      if not ok and not tostring(r):find("not found") then error(r) end
      D.loaded[n] = m
    end
    if m then out[#out + 1] = m end
  end
  return out
end
D.mods = mods

-- ------------------------------------------------------------ import
function D.extract(rom, R, check)
  local O = D.OFF
  local t = { pitsHurt = {}, sine = rom:bytesU16(O.sine, 256), explodeXY = s8(rom:bytesU8(O.explodeXY, 16)) }
  local list = rom:bytesU16(O.pitsHurt, 57)
  for _, r in ipairs(list) do t.pitsHurt[r] = true end
  t.pitsList = list
  check(list[1] == 0x72 and list[57] == 0x123 and t.pitsHurt[0x56] and not t.pitsHurt[0x07], "kDungeonPitsHurtPlayer")
  check(t.sine[129] == 256 and t.sine[1] == 0 and t.explodeXY[2] == 4 and t.explodeXY[13] == -24, "sine / explosion offsets")
  -- the room overlays (Dungeon_DrawRoomOverlay): x, y (tile), object type
  t.overlays = {}
  for i = 0, 20 do
    local o = rom:ptr(O.overlays + i * 4)
    local list = {}
    for _ = 1, 64 do
      if not o or rom:u16(o) == 0xFFFF then break end
      list[#list + 1] = { rshift(rom:u8(o), 2), rshift(rom:u8(o + 1), 2), rom:u8(o + 2) }
      o = o + 3
    end
    t.overlays[i] = list
  end
  -- the predefined words the overlays draw: the hole (0x5AA, 0x63C + 2,
  -- 0x642 + 2) and the floor fillers (byte offsets 0x00..0xF0)
  t.pred = {}
  for _, off in ipairs({ 0x5AA, 0x63E, 0x644 }) do t.pred[off] = rom:u16(O.pred + off) end
  for f = 0, 15 do
    for _, k in ipairs({ 0, 2, 8, 10 }) do t.pred[f * 16 + k] = rom:u16(O.pred + f * 16 + k) end
  end
  -- each room's floor byte (the object data's first byte: floor 1 / floor 2)
  t.floors = {}
  for r = 0, (R.roomCount or 296) - 1 do
    local p = rom:ptr(R.roomObjects + r * 4)
    t.floors[r] = p and rom:u8(p) or 0
  end
  check(#t.overlays[8] == 5 and t.overlays[8][1][3] == 0xA4 and t.overlays[9][1][2] == 30 and t.pred[0x5AA] == 0x1E9,
        "room overlays (kDungeonRoomOverlay) / kPredefinedTileData")
  for _, m in ipairs(mods()) do
    if m.extract then t[m.NAME] = m.extract(rom, R, check, D) end
  end
  return t
end
function D.tabs(game) return game.data.t and game.data.t.d26 end

-- ------------------------------------------------------------ helpers
local function H() return require("src.zelda.alttp.Palace")._h end
local function A() return require("src.zelda.alttp.Actors") end
D.H, D.A = H, A
local function cbOf(self) return self.game.data.roomIdx.combat end
D.cbOf = cbOf
function D.rnd(self) return require("src.zelda.alttp.Drops").rng(self.game:dropRng()) end
function D.spawn(self, t, x, y, lower) return H().spawn(self, t, x, y, lower) end

-- Sprite_CheckDamageToLink (every 4th frame by slot, the hit timer clear,
-- on Link's level): the type's bump damage; true on contact. opts.box =
-- { x, y, w, h } replaces the sprite's hit box; opts.harmless = flags2 0x80
function D.contact(self, a, lk, opts)
  opts = opts or {}
  local game = self.game
  local cb = cbOf(self)
  if not opts.anyLayer and (a.lower or false) ~= (self.inside.lower or false) then return false end
  if not opts.always and (band(bxor(a.k or 0, self.frame), 3) ~= 0 or (a.inv or 0) > 0) then return false end
  if game.pitFall then return false end   -- link_disable_sprite_damage
  local hx, hy, hw, hh
  if opts.box then hx, hy, hw, hh = opts.box[1], opts.box[2], opts.box[3], opts.box[4]
  else hx, hy, hw, hh = A().hitbox(cb, a); hy = hy - (a.z or 0) end
  local lx, ly, lw, lh = A().linkBox(lk)
  if not A().overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) then return false end
  if not opts.harmless then
    local cls = band(a.bump or cb.bump[a.type + 1] or 0, 0x0F)
    game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
  end
  return true
end

-- Sprite_ApplyRecoilToLink / link_actual_vel: Link pushed at `vel`
-- (1/16 px) away from (x, y) for `t` frames
function D.pushLink(game, x, y, vel, t)
  local lk = game.link
  local vx, vy = A().project(x, y, lk.x, lk.y, vel)
  game.recoil = { vx = vx, vy = vy, t = t or 16, sx = 0, sy = 0, vz = 0 }
end

-- Sprite_CheckIfScreenIsClear (the camera's 256 x 256; flags4 0x40 skip)
function D.screenClear(self, but)
  return require("src.zelda.alttp.DesertPalace").screenClear(self, but)
end

-- Sprite_ConvertVelocityToAngle (the GBA table)
function D.angle(game, x, y)
  local DPm = require("src.zelda.alttp.DesertPalace")
  local tb = DPm.tabs(game)
  if not tb then return 0 end
  return DPm.angle(tb, x, y)
end

-- Sprite_ProjectSpeedTowardsLink with the cartridge's target (x, y + 8 + z
-- for dungeon sprites -- Palace.towardsLink)
function D.towardsLink(a, lk, vel) return H().towardsLink(a, lk, vel) end

-- the boss is finished (Sprite_ReturnIfBossFinished: the heart taken)
function D.bossFinished(self)
  local p = self.game.progress
  return p.bossBeaten ~= nil and p.bossBeaten[self.inside.room] == true
end

-- SpriteModule_Explode for a boss: state 4 from `delay`
function D.explode(self, a, delay)
  a.exploding, a.delay = true, delay or 255
  a.untouchable, a.noTouch = true, true
end
-- one frame of state 4; returns true while the boss itself should still run
function D.explodeFrame(self, a)
  local d = a.delay or 0
  local tb = D.tabs(self.game)
  if d <= 32 then
    a.dead = true
    a.exploding = nil
    if a.noHeart then return false end
    if D.screenClear(self, a) then
      local hc = D.spawn(self, 0xEA, a.x, a.y, a.lower)
      hc.z, hc.vz = 1, 32
      self.bossDone = true
    end
    return false
  end
  if d < 0xC0 and band(d, (a.type == 0x92) and 3 or 7) == 0 then
    local xy = tb and tb.explodeXY or { 0 }
    local hi = (a.type == 0x92) and 8 or 0
    local xo = xy[bor(band(D.rnd(self), 7), hi) + 1] or 0
    local yo = xy[bor(band(D.rnd(self), 7), hi) + 1] or 0
    require("src.zelda.alttp.Effects").death(self.game, { type = 0x00, x = a.x + xo, y = a.y + yo - (a.z or 0), z = 0, lower = a.lower })
    self.game.bossBooms = (self.game.bossBooms or 0) + 1
  end
  return d >= 64 and (d >= 0x70 or band(d, 1) == 0)
end

-- ------------------------------------------------------------ the crystal switch
local Core = { NAME = "core", TYPES = { [D.CRYSTAL] = true, [D.BOOM] = true }, FIGHTS = {} }
D.Core = Core

function Core.prep(self, a)
  if a.type == D.CRYSTAL then
    a.cswitch, a.F = true, 0
    a.untouchable = true
  end
end

function Core.update(self, a, lk)
  local game = self.game
  if a.type ~= D.CRYSTAL then return end
  a.pegSt = game.pegState or 0
  -- Sprite_CheckDamageToLink_same_layer (harmless): a dash stops
  if D.contact(self, a, lk, { harmless = true, always = true }) then game.dashStop = true end
  if (a.F or 0) > 0 then
    local f = a.F
    a.F = f - 1
    if f == 11 then D.togglePegs(game) end
  end
end

function Core.draw(spr, a, x, y, frame, game)
  if a.type ~= D.CRYSTAL then return true end
  local info = spr.info
  local st = a.pegSt or (game and game.pegState) or 0
  local f = band(info.flags3[a.type + 1] or 0, 0x0F)
  f = bor(band(f, bit.bnot(0x0E)), D.CRYSTAL_PAL[band(st, 1)])
  local ch = info.single2[(info.single1[a.type + 1] or 0) + 1]
  if ch then spr:oam(x, y, ch, f, 2) end
  return true
end
function Core.swordImmune() return false end

-- the sword / a thrown thing / an arrow on a crystal switch: sprite_F 15
-- (Sprite_GiveDamage's flag4 path: damage 0, flags 4), B held < 9
function D.hitSwitches(actors, x, y, w, h, how)
  local n = 0
  if how and how.sword and ((how.held) or (how.bFrames or 0) >= 9) then return 0 end
  local cb = cbOf(actors)
  for _, a in ipairs(actors.list or {}) do
    if a.cswitch and not a.dead and (a.F or 0) == 0
       and not (how and how.lower ~= nil and (a.lower or false) ~= how.lower) then
      local hx, hy, hw, hh = A().hitbox(cb, a)
      if A().overlapCart(x, y, w, h, hx, hy, hw, hh) then a.F = 15; n = n + 1 end
    end
  end
  return n
end

-- ------------------------------------------------------------ the pegs
-- the two 4-tile groups at VRAM 0x1D0 / 0x1D4 by sheet-0x0F tile offset
local PEG_STEPS = {
  -- Module07_16 steps (subsubmodule 4, 8, 12): (state 1, state 0)
  [1] = { { 4, 8 }, { 8, 4 } },     -- Step1: (0x80, 0x100) / (0x100, 0x80)
  [2] = { { 8, 4 }, { 4, 8 } },     -- Step2
  [3] = { { 12, 0 }, { 0, 12 } },   -- RecoverPegGFXFromMapping
}
function D.pegTilesFor(state) if state == 1 then return { 12, 0 } end return { 0, 12 } end

-- Dungeon_FlipCrystalPegAttribute on the loaded room
function D.flipPegAttrs(inside)
  local n = 0
  for _, pair in ipairs({ { inside.attrs, inside.grid }, { inside.attrsLo, inside.gridLo } }) do
    local at, gr = pair[1], pair[2]
    if at then
      for c = 0, 4095 do
        local v = at[c]
        if v == 0x66 or v == 0x67 then
          at[c] = bxor(v, 1)
          gr[c] = (at[c] == 0x67)
          n = n + 1
        end
      end
    end
  end
  return n
end

-- the switch was hit: orange_blue_barrier_state ^= 1, submodule 22
function D.togglePegs(game)
  game.pegState = bxor(game.pegState or 0, 1)
  game.pegAnim = { t = 0 }
  game.pegToggles = (game.pegToggles or 0) + 1
end

-- Module07_16_UpdatePegs, one frame (the game is frozen meanwhile)
function D.pegFrame(game)
  local an = game.pegAnim
  an.t = an.t + 1
  if band(an.t, 3) ~= 0 then return end
  local step = rshift(an.t, 2)
  local inside = game.interior
  local st = game.pegState or 0
  if step >= 1 and step <= 3 then
    local p = PEG_STEPS[step][(st == 1) and 1 or 2]
    if inside then inside.pegTiles = { p[1], p[2] } end
    game.roomImages = nil
  elseif step >= 4 then
    if inside then D.flipPegAttrs(inside); inside.pegFlipped = st end
    game.pegAnim = nil
  end
end

-- the peg tiles of the room's slot-7 sheet (a proxy data object while the
-- room's maps are decoded)
local sheetCache = setmetatable({}, { __mode = "k" })
local function pegSheet(data, sheetN, tiles, star)
  local per = sheetCache[data]
  if not per then per = {}; sheetCache[data] = per end
  local key = sheetN .. ":" .. tiles[1] .. "," .. tiles[2] .. ":" .. (star or 0)
  local hit = per[key]
  if hit then return hit end
  local raw = data:sheet(sheetN)
  local f = data:sheet(0x0F)
  local function grp(o) return f:sub(o * 32 + 1, o * 32 + 128) end
  local s = raw:sub(1, D.PEG.first * 32) .. grp(tiles[1]) .. grp(tiles[2]) .. raw:sub((D.PEG.first + 8) * 32 + 1)
  if star == 1 then
    -- Dungeon_RestoreStarTileChr: VRAM tiles 0x1ED / 0x1EE (slot 7 tiles
    -- 45 / 46) = bg sheet 5 tiles 48 / 49, swapped while byte_7E04BC is set
    local s5 = data:sheet(5)
    s = s:sub(1, 45 * 32) .. s5:sub(49 * 32 + 1, 50 * 32) .. s5:sub(48 * 32 + 1, 49 * 32) .. s:sub(47 * 32 + 1)
  end
  per[key] = s
  return s
end
D.pegSheet = pegSheet

-- ------------------------------------------------------------ overlays
-- room tags -> Dung_TagRoutine_Func2's base overlay (kDungTagroutines)
D.OVERLAY_TAG = { [0x21] = 1, [0x23] = 3, [0x34] = 6, [0x35] = 8, [0x36] = 10, [0x37] = 12, [0x39] = 14, [0x3A] = 16 }

-- RoomTag_CheckForPressedSwitch on the BG2 attribute table: 0x2323 /
-- 0x3A3A / 0x3B3B at Link's tile (or the 3 around) with the same pair
-- below; returns the attribute
function D.pressedSwitch(inside, lk)
  local t = inside.attrs
  local p = math.floor(band(lk.x - 1, 0x1F8) / 8) + math.floor(band(lk.y + 14, 0x1F8) / 8) * 64
  local function ok(v) return v == 0x23 or v == 0x3A or v == 0x3B end
  for _, q in ipairs({ p, p + 64, p + 1, p + 65 }) do
    local a, b = t[q], t[q + 1]
    if a and a == b and ok(a) then
      if t[q + 64] == a and t[q + 65] == a then return a end
      return nil
    end
  end
  return nil
end

-- Dungeon_DrawRoomOverlay + Dungeon_DrawRoomOverlay_Apply (BG2 and its
-- attribute table)
function D.drawOverlay(game, n)
  local inside = game.interior
  local tb = D.tabs(game)
  local list = tb and tb.overlays[n]
  if not list then return false end
  local data = inside.data
  local O = require("src.zelda.alttp.Overworld")
  local floor2 = band(tb.floors[inside.room] or 0, 0x0F) * 16
  local pr = tb.pred
  local W = require("src.zelda.alttp.Interior").WALKABLE
  for _, e in ipairs(list) do
    local c0 = e[1] + e[2] * 64
    for r = 0, 3 do
      for c = 0, 3 do
        local w
        if e[3] == 0xA4 then
          w = (r == 0 and pr[0x63E]) or (r == 3 and pr[0x644]) or pr[0x5AA]
        else
          local k = (band(r, 1) == 0) and ((band(c, 1) == 0) and 0 or 2) or ((band(c, 1) == 0) and 8 or 10)
          w = pr[floor2 + k]
        end
        inside.patch[c0 + r * 64 + c] = w
      end
    end
    for r = 0, 3 do
      for c = 0, 3 do
        local cell = c0 + r * 64 + c
        local tn = band(inside.patch[cell] or data:roomWord(inside.bg2, O.cellIndex(cell % 64, math.floor(cell / 64))), 0x3FE)
        local v = (tn == 0xEE or tn == 0xFE) and 0 or 0x20
        inside.attrs[cell] = v
        inside.grid[cell] = not W[v]
      end
    end
  end
  game.roomImages = nil
  game.overlaysDrawn = (game.overlaysDrawn or 0) + 1
  return true
end

-- the overlay room tags, one frame (Dung_TagRoutine_Func2 / RoomTag_Holes2)
function D.overlayTags(game)
  local inside, lk = game.interior, game.link
  local hdr = inside.hdr or {}
  inside.mem.tagDone = inside.mem.tagDone or {}
  for slot, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
    local av = D.OVERLAY_TAG[tag]
    if av and not inside.mem.tagDone[slot] then
      if not inside.overlayNow then inside.overlayNow = av end
      local sw = (not game.recoil) and D.pressedSwitch(inside, lk)
      if sw then
        local want = av + ((sw == 0x3B) and 1 or 0)
        if want ~= inside.overlayNow then
          inside.overlayNow = want
          inside.starFlip = bxor(inside.starFlip or 0, 1)
          D.drawOverlay(game, want)
        end
      end
    elseif tag == 0x24 and not inside.mem.tagDone[slot] then
      if (not game.recoil) and D.pressedSwitch(inside, lk) then
        inside.mem.tagDone[slot] = true
        D.drawOverlay(game, 5)
      end
    end
  end
end

-- ------------------------------------------------------------ pits
local PIT = { [0x20] = true }
for v = 0xB0, 0xBD do PIT[v] = true end
D.PIT = PIT

-- Player_TileDetectNearby: bits 8 (x, y+8), 2 (x, y+23), 4 (x+15, y+8), 1 (x+15, y+23)
function D.pitBits(inside, x, y)
  local b = 0
  local function at(px, py, bitv)
    local v = inside:attrAt(px, py)
    if v and PIT[v] then b = bor(b, bitv) end
  end
  at(x, y + 8, 8); at(x, y + 23, 2); at(x + 15, y + 8, 4); at(x + 15, y + 23, 1)
  return b
end

local FALLHOLE_PIT = { [0] = 12, 3, 10, 5 }           -- kFallHolePitDirs
local FALLHOLE_DIRS2 = { [0] = 10, 9, 6, 5, 8, 4, 2, 1 }   -- kFallHoleDirs2 (8 up, 4 down, 2 left, 1 right)

-- one frame of Link near / in a pit (after his move); true when the fall
-- has begun
function D.pitCheck(game)
  local inside, lk = game.interior, game.link
  if not inside or game.pitFall or game.roomScroll or lk.hop or game.climb then return false end
  local bits = D.pitBits(inside, lk.x, lk.y)
  if bits == 0 then return false end
  if bits == 0x0F then
    -- LinkState_FallingIntoHole: the fall begins
    game.pitFall = { t = 0, step = 0, cnt = 9, from = { lk.x, lk.y, inside.lower }, room = inside.room }
    if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
    game.swing = nil
    game.pitFalls = (game.pitFalls or 0) + 1
    return true
  end
  -- partly over a pit: pulled towards it (kFallHolePitDirs / kFallHoleDirs2)
  local i
  for j = 3, 0, -1 do if bits == FALLHOLE_PIT[j] then i = j + 4 end end
  if not i then
    i = 3
    local p = bits
    while band(p, 1) == 0 do i = i - 1; p = rshift(p, 1) end
  end
  local d = FALLHOLE_DIRS2[i] or 0
  local dx = (band(d, 1) ~= 0 and 1 or 0) - (band(d, 2) ~= 0 and 1 or 0)
  local dy = (band(d, 4) ~= 0 and 1 or 0) - (band(d, 8) ~= 0 and 1 or 0)
  lk.x, lk.y = lk.x + dx, lk.y + dy
  game.pitPulls = (game.pitPulls or 0) + 1
  return false
end

-- one frame of the fall / the drop into the room below; true while it runs
function D.pitFrame(game)
  local pf = game.pitFall
  local lk = game.link
  local inside = game.interior
  if pf.drop then
    pf.drop = pf.drop - 4
    if pf.drop <= 0 then pf.drop = nil; game.pitFall = nil; game.pitLandings = (game.pitLandings or 0) + 1 end
    return true
  end
  pf.cnt = pf.cnt - 1
  if pf.cnt >= 0 then return true end
  pf.cnt = 9
  pf.step = pf.step + 1
  if pf.step < 6 then return true end
  -- step 6: the next room (or the pit hurts)
  local tb = D.tabs(game)
  local room = inside.room
  if tb and tb.pitsHurt[room] then
    -- DungeonPitDoDamage + Module07_14_RecoverFromFall: 8 damage, back
    game.pitFall = nil
    local st = game.stats
    st.health = math.max(0, (st.health or 0) - 8)
    lk.x, lk.y = pf.prevX or pf.from[1], pf.prevY or pf.from[2]
    game.pitHurts = (game.pitHurts or 0) + 1
    return true
  end
  local hdr = inside.hdr or {}
  local dest = hdr[10] or 0
  local plane = band(hdr[8] or 0, 3)
  if game.dropCarry then game:dropCarry() end
  inside:loadRoom(dest, inside.main)
  inside.lower = plane >= 2
  game.roomImages = nil
  inside.qx, inside.qy = math.floor((lk.x + 8) / 256), math.floor((lk.y + 12) / 256)
  game.roomChanges = (game.roomChanges or 0) + 1
  -- (Module07_07: Link drops in from the top of the screen to his y)
  local cy = select(2, inside:camera(lk.x, lk.y, 240, 160))
  pf.drop = math.max(4, lk.y - cy + 16)
  pf.step = 0
  pf.landed = dest
  return true
end

-- ------------------------------------------------------------ install
function D.install(G)
  local P = require("src.zelda.alttp.Palace")
  P.register(Core)
  for _, m in ipairs(mods()) do
    if m.TYPES then P.register(m) end
    if m.install then m.install(G, D) end
  end
  local I = require("src.zelda.alttp.Interior")
  -- the lowered pegs and the pits are floor to Link (TileBehavior_NothingOW
  -- 0x66; TileBehavior_Pit -- the fall is D.pitCheck)
  I.WALKABLE[0x66] = true
  for v in pairs(PIT) do I.WALKABLE[v] = true end
  -- a room loads with the barrier state (Dungeon_LoadAttributeTable)
  local load0 = I.loadRoom
  function I:loadRoom(room, main)
    local r = load0(self, room, main)
    local st = self.pegState or 0
    self.pegTiles = D.pegTilesFor(st)
    -- Dungeon_LoadHeader: dung_overlay_to_load = 0; ResetStarTileGraphics
    self.overlayNow, self.starFlip = nil, 0
    if st == 1 then D.flipPegAttrs(self) end
    return r
  end
  local dec0 = I.decodeLayer
  function I:decodeLayer(layer, cells)
    local pt = self.pegTiles
    local star = self.starFlip or 0
    if not pt or (pt[1] == 0 and pt[2] == 12 and star == 0) or (self.sheets and self.sheets[8] ~= 0x0F) then
      return dec0(self, layer, cells)
    end
    local real = self.data
    local sheetN = self.sheets[8]
    local proxy = setmetatable({ sheet = function(d, i)
      if i == sheetN then return pegSheet(real, i, pt, star) end
      return real:sheet(i)
    end }, { __index = real })
    self.data = proxy
    local ok, out = pcall(dec0, self, layer, cells)
    self.data = real
    if not ok then error(out) end
    return out
  end
  -- the game's barrier state is the interior's (set before each load)
  local function syncPeg(g)
    if g.interior then g.interior.pegState = g.pegState or 0 end
  end
  local enter0 = G.enterRoom
  function G:enterRoom(entrance)
    -- Dungeon_LoadEntrance: orange_blue_barrier_state = 0
    self.pegState, self.pegAnim, self.pitFall = 0, nil, nil
    local r = enter0(self, entrance)
    syncPeg(self)
    return r
  end
  local start0 = G.enterStart
  function G:enterStart(i, entranceId)
    self.pegState, self.pegAnim, self.pitFall = 0, nil, nil
    local r = start0(self, i, entranceId)
    syncPeg(self)
    return r
  end
  local esc0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.interior then self.interior.pegState = self.pegState or 0 end
    -- Module07_16_UpdatePegs: everything waits
    if self.pegAnim then D.pegFrame(self); return true end
    if self.pitFall then
      if self.actors.room ~= self.interior.room or self.actors.inside ~= self.interior then
        self.actors:enterRoom(self.interior)
      end
      D.pitFrame(self)
      return true
    end
    local r = esc0(self, inp)
    if self.interior and not self.roomScroll and not self.pitFall then D.overlayTags(self) end
    return r
  end
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    if g.pitFall then return end
    local lk = g.link
    local px, py = lk.x, lk.y
    move0(g, inp)
    if g.interior and not g.pitFall then
      if not D.pitCheck(g) and D.pitBits(g.interior, lk.x, lk.y) == 0 then
        g.pitSafe = { px, py }
      elseif g.pitFall and g.pitSafe then
        g.pitFall.prevX, g.pitFall.prevY = g.pitSafe[1], g.pitSafe[2]
      end
    end
  end
  -- Link shrinks while he falls and drops in from above (OURS: no poses)
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    local pf = self.pitFall
    if pf and lk == self.link and self.cam then
      if not pf.drop and pf.step >= 6 then return end
      local sx = lk.x - self.cam.x + 8
      local sy = lk.y - self.cam.y + 16
      local s = pf.drop and 1 or math.max(0.1, 1 - pf.step / 6)
      love.graphics.push()
      love.graphics.translate(sx, sy - (pf.drop or 0))
      love.graphics.scale(s, s)
      love.graphics.translate(-sx, -sy)
      dl0(self, lk, tint)
      love.graphics.pop()
      return
    end
    return dl0(self, lk, tint)
  end
  -- weapons on the crystal switches
  local Act = A()
  local sh0 = Act.swordHit
  function Act:swordHit(x, y, w, h, how)
    local n = D.hitSwitches(self, x, y, w, h, how)
    self.switchHits = (self.switchHits or 0) + n
    return sh0(self, x, y, w, h, how)
  end
end

return D
