-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 83: the push-block chest (RoomTag_PushBlockForChest) and the reveal
-- sound.
--
-- Chest70 hides the chests of a room whose tag is one of the chest tags,
-- but of the tags that reveal them only 0x27 (switch), 0x29..0x32 (kill)
-- and 0x3E (torches, Items.lua) were ported: Turtle Rock's chain chomp room
-- (0xB6, tag 0x3C) kept its key chest hidden for good -- the chest at
-- (120, 80) between the chomps could never appear.
--
-- Traced on the GBA:
--   the tag routine table (dung tag routines, 4-byte Thumb pointers at
--     0x08152AC4): the entry that points at 0x0807B6FC is the push-block
--     chest tag (read at import, 0x3C on the cartridge);
--   0x0807B6FC: `ldr r1, =0xBBF` (0x0807B700) -- dung_flag_movable_block_
--     was_pushed -- `cmp r0, #0` / `beq`, then `bl` RoomTag_OperateChestReveal
--     (0x0807B70A -> 0x0807A478). No quadrant test, no other condition;
--   the push block's landing (0x0808373C) toggles +0xBBF (`eors` with 1 at
--     0x08083764) -- the port's inside.blockPushed (RoomObjects), so a
--     second push before the reveal turns it off again, as on the cartridge;
--   RoomTag_OperateChestReveal ends with `movs r0, #imm` / `bl 0x0812A324`
--     (0x0807A6FC / 0x0807A6FE): the reveal's sound, for every tag that
--     reveals chests (read at import). The port's Chest70 reveal was silent;
--     now any reveal plays it (once per reveal).
-- The tag number and the sound id are read from the player's ROM at import
-- (data.t.chest83); the extract refuses other code shapes.

local bit = require("bit")
local band, bnot = bit.band, bit.bnot

local M = { NAME = "chest83" }

M.SITES = {
  table = 0x08152AC4,     -- the tag routine table (entry n = tag n)
  routine = 0x0807B6FC,   -- RoomTag_PushBlockForChest
  flagLit = 0x0807B700,   -- ldr r1, =0xBBF
  cmp = 0x0807B706,       -- cmp r0, #0
  call = 0x0807B70A,      -- bl RoomTag_OperateChestReveal
  reveal = 0x0807A478,    -- RoomTag_OperateChestReveal
  landLit = 0x0808375C,   -- the block landing: ldr r1, =0xBBF
  landEor = 0x08083764,   -- eors r1, r2 (r2 = 1)
  sfx = 0x0807A6FC,       -- movs r0, #sound
  sfxCall = 0x0807A6FE,   -- bl 0x0812A324
  play = 0x0812A324,
}

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= op then return nil end
  return band(h, 0xFF)
end

-- the target of a Thumb `bl` pair
local function bl(rom, a)
  local h1, h2 = rom:u16(off(a)), rom:u16(off(a) + 2)
  if band(h1, 0xF800) ~= 0xF000 or band(h2, 0xF800) ~= 0xF800 then return nil end
  local o = band(h1, 0x7FF) * 4096 + band(h2, 0x7FF) * 2
  if o >= 0x400000 then o = o - 0x800000 end
  return a + 4 + o
end

function M.extract(rom, R, check)
  local S = M.SITES
  local t = {}
  for n = 0, 0x3F do
    if rom:u32(off(S.table) + n * 4) == S.routine + 1 then t.tag = n break end
  end
  local flag = lit(rom, S.flagLit)
  local z = imm8(rom, S.cmp, 0x2800)
  t.sfx = imm8(rom, S.sfx, 0x2000)
  check(t.tag and flag and flag == lit(rom, S.landLit) and z == 0 and bl(rom, S.call) == S.reveal
        and rom:u16(off(S.landEor)) == 0x4051 and t.sfx and bl(rom, S.sfxCall) == S.play,
        "chest83 RoomTag_PushBlockForChest / reveal shape")
  return t
end

-- ------------------------------------------------------------ run time

local function tab(game) return game and game.data and game.data.t and game.data.t.chest83 end
M.tab = tab

local function sfx(game, id)
  if id then pcall(require("src.zelda.alttp.Sfx").start, game, id, "chest83") end
end

-- the push-block tag: the chests appear once the room's block flag is set
function M.tagFrame(game, inside)
  local t = tab(game)
  if not (t and t.tag and inside and inside.mem) then return false end
  if inside.mem.chestShown or (inside.chestsHidden70 or 0) == 0 then return false end
  local hdr = inside.hdr or {}
  if (hdr[6] ~= t.tag and hdr[7] ~= t.tag) or not inside.blockPushed then return false end
  local C70 = require("src.zelda.alttp.Chest70")
  C70.reveal(inside)
  game.roomImages = nil
  game.chestReveals83 = (game.chestReveals83 or 0) + 1
  return true
end

-- the reveal's sound (any tag): Chest70.reveal marks the room, the next
-- room-tag pass plays it
function M.soundFrame(game, inside)
  if inside and inside.revealSfx83 then
    inside.revealSfx83 = nil
    local t = tab(game)
    sfx(game, t and t.sfx)
    game.revealSounds83 = (game.revealSounds83 or 0) + 1
  end
end

function M.install(G)
  if G.chest83Installed then return end
  G.chest83Installed = true
  local C70 = require("src.zelda.alttp.Chest70")
  local reveal0 = C70.reveal
  function C70.reveal(inside)
    local n = reveal0(inside)
    if n and n > 0 then inside.revealSfx83 = true end
    return n
  end
  local Pm = require("src.zelda.alttp.Palace")
  local rt0 = Pm.roomTags
  function Pm.roomTags(self, lk)
    local r = rt0(self, lk)
    local game = self.game
    local inside = self.inside or (game and game.interior)
    M.tagFrame(game, inside)
    M.soundFrame(game, inside)
    return r
  end
end

return M
