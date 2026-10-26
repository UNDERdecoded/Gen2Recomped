-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.


-- Shared GBA field-weather identifiers, retained from the native importer.
local names = {
  [0] = "NONE", [1] = "SUNNY_CLOUDS", [2] = "SUNNY", [3] = "RAIN",
  [4] = "SNOW", [5] = "RAIN_THUNDERSTORM", [6] = "FOG_HORIZONTAL",
  [7] = "VOLCANIC_ASH", [8] = "SANDSTORM", [9] = "FOG_DIAGONAL",
  [10] = "UNDERWATER", [11] = "SHADE", [12] = "DROUGHT", [13] = "DOWNPOUR",
  [14] = "UNDERWATER_BUBBLES", [15] = "ABNORMAL",
  [20] = "ROUTE119_CYCLE", [21] = "ROUTE123_CYCLE",
}
local byName={}
for id,name in pairs(names)do byName[name]=id end
return {names=names,byName=byName}
