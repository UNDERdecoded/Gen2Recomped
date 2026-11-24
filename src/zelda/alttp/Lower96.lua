-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 96: a lower-level pot or chest is redrawn on the lower map.
--
-- The cartridge keeps a manipulable object's spot as a byte offset into the
-- room's maps, with 0x2000 added for the object list's layer 2 (the port's
-- p.pos, Pots74). Every redraw adds that offset (& 0x3FFF, 0x08080380) to
-- 0x02018000 (e.g. the push block / pot redraw 0x08083AE4: `ldr r3,
-- =0x02018000` at 0x08083B54, `adds` / `strh` of the kept word): layer 1 is
-- the upper map 0x02018000 (our "bg2"), layer 2 is 0x02018000 + 0x2000 =
-- 0x0201A000, the lower map (our "bg3"). The pre-rendered maps agree: over
-- all 304 rooms the 55 layer-2 pots (0x2F) and chests (0x19 / 0x31) have
-- their words in the lower map and nothing in the high-priority copy
-- 0x0201C000 (our "bg1"; r96 harness SCAN96).
--
-- The port wrote a lower pot's hole / switch (Interior:removePot /
-- potSwitch), a lower chest's open or closed picture (Interior:openChest,
-- Chest70.reveal, Chest74.redraw) to patch1 -- the high-priority map, drawn
-- at GBA priority 1 over every sprite -- and read a lower pot's words from
-- bg1 (potWords): Ganon's Tower 0x5B's middle pot stayed drawn on the lower
-- map, its switch was drawn over Link (OBJ priority 3 on the lower level)
-- and he vanished on it (r95's "Link hidden in 0x5B's T bar"). Here those
-- calls use patch3 / bg3 for layer-2 objects. No ROM data: nothing is read
-- (extract returns an empty table).

local M = { NAME = "lower96" }

M.SITES = { redraw = 0x08083AE4, mapBase = 0x08083B54, offsetMask = 0x08083B46 }
M.LOWER_BIT = 0x2000          -- the layer-2 offset bit (0x0201A000 - 0x02018000)

function M.extract(rom, R, check) return {} end

-- the map a layer's redraw goes to: "bg3" (the lower map) for layer 2
function M.mapOf(layer)
  return layer == 2 and "bg3" or "bg2"
end

-- run f(...) with inside.patch1 standing for the lower map's patch (the
-- original code picks patch1 for lower objects); restored afterwards
local function asLower(inside, f, ...)
  if not (inside and inside.patch3) then return f(...) end
  local keep = inside.patch1
  inside.patch1 = inside.patch3
  local ok, a, b, c = pcall(f, ...)
  inside.patch1 = keep
  if not ok then error(a, 0) end
  return a, b, c
end
M.asLower = asLower

function M.install(G)
  if G.lower96Installed then return end
  G.lower96Installed = true
  local I = require("src.zelda.alttp.Interior")

  local removePot0 = I.removePot
  function I.removePot(self, p, ...)
    if p and p.layer == 2 then return asLower(self, removePot0, self, p, ...) end
    return removePot0(self, p, ...)
  end

  local potSwitch0 = I.potSwitch
  function I.potSwitch(self, p, ...)
    if p and p.layer == 2 then return asLower(self, potSwitch0, self, p, ...) end
    return potSwitch0(self, p, ...)
  end

  local potWords0 = I.potWords
  function I.potWords(self, p, ...)
    if p and p.layer == 2 and self.bg3 then
      local keep = self.bg1
      self.bg1 = self.bg3
      local ok, w = pcall(potWords0, self, p, ...)
      self.bg1 = keep
      if not ok then error(w, 0) end
      return w
    end
    return potWords0(self, p, ...)
  end

  local openChest0 = I.openChest
  function I.openChest(self, c, ...)
    if c and c.lower then return asLower(self, openChest0, self, c, ...) end
    return openChest0(self, c, ...)
  end

  -- these two treat upper chests with inside.patch: aliasing patch1 for the
  -- whole call only moves the lower ones
  local C70 = require("src.zelda.alttp.Chest70")
  local reveal0 = C70.reveal
  function C70.reveal(inside, ...) return asLower(inside, reveal0, inside, ...) end
  local C74 = require("src.zelda.alttp.Chest74")
  local redraw0 = C74.redraw
  function C74.redraw(inside, ...) return asLower(inside, redraw0, inside, ...) end
end

return M
