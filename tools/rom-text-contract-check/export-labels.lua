-- Read address/name facts from the pinned reference's public import metadata.
package.path = "./?.lua;./?/init.lua;" .. package.path
local version = assert(arg[1])
local V = require("src.core.GameVersion")
V.set(version)
local M = require("src.import.gba.versions")
M.select(version)
print("ROM_LABEL_FACTS " .. require("src.link.Json").encode({
  text = M.NAMED_TEXTS,
  battle = M.NAMED_BATTLE_TEXTS,
}))
