-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BUG ROUND 95 (user report "when picking up pots it's not showing them in my
-- hand, it's showing a gray tile"): the lifted pot's kind and palette.
--
-- GBA, the lift (Link's indoor lift query 0x0808176C, see Lift52.lua): the
-- attribute of the tile in front, (attr & 0xF0) == 0x70 -> its replacement
-- state dung_replacement_tile_state[attr & 15] (+0x195C); a pot's state is
-- the one RoomDraw_SinglePot writes (`ldr r1, =state` at 0x0807CB12, the
-- literal read at import); the lift's answer is the low byte of
-- kDungeon_QueryIfTileLiftable_rv[state & 15] (0x081532EC, read at import),
-- and that answer's index in kLink_Lift_tab (Drops.LIFT_KIND) is the thrown
-- sprite's kind (sprite_C). The port lifted every pot as kind 0 -- the
-- sign's kind -- so Sprite_EC_ThrownItem's char (kThrowableScenery_Char
-- [kind], 0x080E7B2C) picked the indoor misc
-- sheet's sign picture: a gray cross-hatched square over Link's head, the
-- thrown pot and its shards the sign's too.
--
-- The palette: Sprite_SpawnThrowableTerrain (0x080C29F0..0x080C2A2E) writes
-- 0x80 to the OAM flags of an indoor kind 2 and then, for every kind, the
-- kThrowableScenery_Flags byte over it (the GBA drops the SNES 0x50 of an
-- indoor bush); Sprite_EC takes its palette from the same byte. The port
-- drew an indoor kind 2 with flags 0x50 (palette 0, mirrored).
--
-- The Dark World palaces: Sprite_EC (0x080E7AF0..0x080E7B1A) adds the
-- indoor byte (+0x9B2) and the Dark World byte (+0x164C); above 1 the char
-- index is kind + 5 (`adds r1, r2, #5` at 0x080E7B18, the immediate read
-- at import) where the SNES adds 6. The port added 6.
--
-- Outdoors (bushes, rocks, signs: Drops.LIFT_KIND of the tile's attribute)
-- and the big blocks (Lift52) already had the cartridge's kind.

local bit = require("bit")
local band = bit.band

local M = { NAME = "carry95" }

M.SITES = { potStateLdr = 0x0807CB12, rvTable = 0x081532EC, ecDraw = 0x080E7B2C, spawn = 0x080C29F0,
            dwAdd = 0x080E7B18 }

local function off(a) return a - 0x08000000 end
-- the Thumb `ldr rX, [pc, #imm]` literal at a
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end
M.lit = lit

function M.extract(rom, R, check)
  local st = lit(rom, M.SITES.potStateLdr)
  check(st ~= nil and band(st, 0xF0F0) == 0x1010, "carry95: the pot's replacement state (RoomDraw_SinglePot literal)")
  if not st then return {} end
  local rv = rom:u16(off(M.SITES.rvTable) + band(st, 15) * 2)
  local attr = band(rv, 0xFF)
  check(attr >= 0x50 and attr <= 0x57, "carry95: kDungeon_QueryIfTileLiftable_rv for the pot")
  -- `adds rd, rn, #imm3` (0x1C00 | imm3 << 6 | rn << 3 | rd)
  local h = rom:u16(off(M.SITES.dwAdd))
  local add = band(h, 0xFE00) == 0x1C00 and band(bit.rshift(h, 6), 7) or nil
  check(add ~= nil and add > 0, "carry95: Sprite_EC's Dark World palace char offset")
  return { potState = band(st, 0xFFFF), potAttr = attr, dwAdd = add }
end

local function tabs(game) return game.data and game.data.t and game.data.t.carry95 end

-- the thrown sprite's kind of a lifted pot (nil: the import has no carry95)
function M.potKind(game)
  local t = tabs(game)
  if not (t and t.potAttr) then return nil end
  return require("src.zelda.alttp.Drops").LIFT_KIND[t.potAttr]
end

-- Sprite_EC_ThrownItem's OAM entry for a kind (< 6): char, flags
function M.oamOf(cb, what, indoors, dark, dwAdd)
  if not (cb and cb.throwChar and what and what < 6) then return nil end
  local ch = cb.throwChar[what + ((indoors + dark >= 2) and (dwAdd or 6) or 0) + 1]
  if not ch or ch == 0 then return nil end
  return ch, cb.throwFlags[what + 1] or 0
end

function M.install(G)
  if G.carry95Installed then return end
  G.carry95Installed = true

  local start0 = G.startLift
  function G:startLift(obj)
    if obj and obj.kind == "pot" then
      local k = M.potKind(self)
      if k then obj.what = k end
    end
    return start0(self, obj)
  end

  -- Carry.lua's drawThrowable with the GBA's flags (no indoor 0x50)
  function G:drawThrowable(what, x, y)
    local cb = self.data.roomIdx and self.data.roomIdx.combat
    local indoors = (self.state == "room") and 1 or 0
    local dark = (self.link.world == "dw") and 1 or 0
    local t = tabs(self)
    local ch, fl = M.oamOf(cb, what, indoors, dark, t and t.dwAdd)
    if not ch then return false end
    local spr = self:shadowSprites()
    if not spr then return false end
    spr:oam(x, y, ch, fl, 2)
    self.thrownDraws95 = (self.thrownDraws95 or 0) + 1
    return true
  end
end

return M
