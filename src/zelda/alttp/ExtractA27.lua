-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Round 27 (team A): the import of this round's world / item / sound
-- modules, one call from Extract.lua (each module reads its own GBA tables).

local X = {}

X.MODULES = {
  { "owe27", "OwEnemies27" }, { "items27", "Items27" }, { "story", "Story27" },
  { "dmap", "DungeonMap" }, { "grove", "Grove" }, { "fairy", "FatFairy" }, { "smith", "Smiths" },
  { "flute", "Flute" },
  { "sfx", "Sfx" },   -- last: it wraps the other modules' call sites
}

function X.extract(t, rom, R, check)
  for _, m in ipairs(X.MODULES) do
    t[m[1]] = require("src.zelda.alttp." .. m[2]).extract(rom, R, check)
  end
end

function X.install(G)
  for _, m in ipairs(X.MODULES) do require("src.zelda.alttp." .. m[2]).install(G) end
  require("src.zelda.alttp.Hooks28").install(G)   -- r28: the items on team B's round-27 hooks
end

return X
