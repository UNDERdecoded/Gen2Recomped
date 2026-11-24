-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 90: the Somaria block on a conveyor. Items27 left "conveyors under
-- it" out; Ganon's Tower's 0x9D has its crystal switch at the top of a
-- conveyor that Link cannot walk onto (a rail, attribute 0x02, between): a
-- block thrown over the rail rides the belt into the switch.
--
-- GBA (Ancilla2C_SomariaBlock 0x0811DCA8, Link's block 0x03002230): on the
-- ground, the block's floor attribute (+0x187A) in 0x68..0x6B (`cmp r0,
-- #0x6B` 0x0811E1D8 / `cmp r0, #0x68` 0x0811E1DC) calls 0x0811B934
-- (Ancilla_ApplyConveyor): y speed (+0xDED) = table 0x0817F814[attr - 0x68]
-- (literal 0x0811B952), x speed (+0xDF7) = table 0x0817F818[attr - 0x68]
-- (literal 0x0811B960), then Ancilla_MoveY / Ancilla_MoveX (1/16 px); the
-- frame then skips the pit / water tests (branch to 0x0811E3E0).
--
-- The two 4-byte tables are read at import (data.t.belt90), refused on
-- other shapes. OURS: the move runs after the block's own frame (Items27 /
-- Somaria82), not in its middle; the block's +0x1732 / +0x1734 copies (the
-- next frame's tile test position) are not kept.

local bit = require("bit")
local band = bit.band

local M = { NAME = "belt90" }

M.SITES = { cmpHi = 0x0811E1D8, cmpLo = 0x0811E1DC, call = 0x0811E1E2, fn = 0x0811B934,
            yLit = 0x0811B952, xLit = 0x0811B960, sub = 0x0811B946 }

function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function u16(a) return rom:u16(a - 0x08000000) end
  local hi, lo = u16(S.cmpHi), u16(S.cmpLo)
  -- cmp r0, #imm is 0x28xx
  local base = band(lo, 0xFF)
  local ok = band(hi, 0xFF00) == 0x2800 and band(lo, 0xFF00) == 0x2800 and band(hi, 0xFF) - base == 3
  -- subs r1, #imm in the conveyor routine: the same base
  ok = ok and band(u16(S.sub), 0xFF) == base
  local yv, yf = RT.codeImm(rom, S.yLit)
  local xv, xf = RT.codeImm(rom, S.xLit)
  local t = {}
  if ok and yf == "ldr" and xf == "ldr" then
    t.base = base
    t.yv, t.xv = {}, {}
    for i = 0, 3 do
      local y, x = rom:u8(yv - 0x08000000 + i), rom:u8(xv - 0x08000000 + i)
      t.yv[i + 1] = y >= 128 and y - 256 or y
      t.xv[i + 1] = x >= 128 and x - 256 or x
    end
  else
    ok = false
  end
  check(ok and t.yv, "the Somaria block's conveyor speeds (Ancilla_ApplyConveyor)")
  return ok and t or {}
end

local function tab(game) return game.data and game.data.t and game.data.t.belt90 end
M.tab = tab

-- one frame: every resting block on a conveyor tile moves
function M.frame(game)
  local T = tab(game)
  if not (T and T.yv and game.interior and game.anc) then return 0 end
  local S82 = require("src.zelda.alttp.Somaria82")
  local n = 0
  for _, a in ipairs(game.anc) do
    if a.kind == "somaria" and not a.gone and a.shown and not a.held and (a.L or 0) == 0 and (a.H or 0) == 0 then
      local at = game:ancAttr(a.x, a.y)
      local j = (at or 0) - T.base
      if j >= 0 and j <= 3 then
        S82.move(a, "y", "suby", T.yv[j + 1])
        S82.move(a, "x", "subx", T.xv[j + 1])
        a.belt90 = (a.belt90 or 0) + 1
        n = n + 1
      end
    end
  end
  game.belt90 = (game.belt90 or 0) + n
  return n
end

function M.install(G)
  if G.belt90Installed then return end
  G.belt90Installed = true
  local upd0 = G.updateAncillae
  function G:updateAncillae()
    local r = upd0(self)
    if self.state == "room" and not self.roomScroll then M.frame(self) end
    return r
  end
end

return M
