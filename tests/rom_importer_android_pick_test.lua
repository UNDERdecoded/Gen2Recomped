-- #167: Android second-ROM Choose must open the picker (or import a pending
-- opposite cart), not re-import a leftover picked_rom.gb from the first game.
-- Self-contained: `luajit tests/rom_importer_android_pick_test.lua`; also
-- dofile'd by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer android pick")
local eq = S.eq
local check = S.check

local GameVersion = require("src.core.GameVersion")
local RomImporter = require("src.import.RomImporter")

local MiB = 1024 * 1024
local redData = string.rep("R", MiB)
local blueData = string.rep("B", MiB)

-- Map our fake 1 MiB blobs onto the real Red/Blue SHA-1 ids without needing
-- a crypto library in the headless stub.
love.data = love.data or {}
love.system = love.system or {}
-- the love stub is shared with every later suite in run_tests.lua;
-- restore whatever this file overrides
local saved = {
  hash = love.data.hash,
  encode = love.data.encode,
  getSaveDirectory = love.filesystem.getSaveDirectory,
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
}
love.data.hash = function(_, data)
  return { tag = data:sub(1, 1) }
end
love.data.encode = function(_, _, digest)
  if type(digest) == "table" and digest.tag == "R" then
    return GameVersion.info("red").sha1
  end
  if type(digest) == "table" and digest.tag == "B" then
    return GameVersion.info("blue").sha1
  end
  return "0000000000000000000000000000000000000000"
end

love.filesystem.getSaveDirectory = function() return "/tmp/pokemon-love2d" end

local pickCalls = 0
love.system.getOS = function() return "Android" end
love.system.pickFile = function()
  pickCalls = pickCalls + 1
  return true
end

local function freshImporter(ready)
  return setmetatable({
    android = true,
    workState = nil,
    ready = {
      red = ready.red and true or false,
      blue = ready.blue and true or false,
    },
    notice = nil,
    chooseVersion = nil,
    startData = function(self, data, displayName)
      self._started = { data = data, name = displayName }
    end,
  }, RomImporter)
end

-- Stale Red pick still on disk, Red already ready → Choose Blue opens picker.
love.filesystem.write("picked_rom.gb", redData)
pickCalls = 0
local ri = freshImporter({ red = true, blue = false })
ri:choose("blue")
eq(pickCalls, 1, "choose opens picker when only an already-imported ROM remains")
eq(ri._started, nil, "choose does not re-import the stale Red pick")

-- Same leftover must not re-import on focus either (picker cancelled).
ri = freshImporter({ red = true, blue = false })
ri:focus(true)
eq(ri._started, nil, "focus ignores already-imported leftover picked_rom.gb")

-- A pending Blue cart in the save dir imports without needing the picker.
love.filesystem.write("pokemon_blue.gb", blueData)
pickCalls = 0
ri = freshImporter({ red = true, blue = false })
ri:choose("blue")
eq(pickCalls, 0, "choose imports a pending opposite ROM from the save dir")
check(ri._started ~= nil, "choose started import for pending Blue")
eq(ri._started.name, "pokemon_blue.gb", "choose picked the pending Blue file")
eq(ri._started.data, blueData, "choose passed Blue ROM bytes")

-- focus after SAF overwrite: pending Blue becomes importable.
love.filesystem.write("picked_rom.gb", blueData)
ri = freshImporter({ red = true, blue = false })
ri:focus(true)
check(ri._started ~= nil, "focus imports pending Blue after picker returns")
eq(ri._started.name, "picked_rom.gb", "focus reads the SAF drop filename")

-- Cleanup so other suites sharing the stub do not see leftover .gb files
-- or this file's function stubs.
love.filesystem.remove("picked_rom.gb")
love.filesystem.remove("pokemon_blue.gb")
love.data.hash = saved.hash
love.data.encode = saved.encode
love.filesystem.getSaveDirectory = saved.getSaveDirectory
love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile

S.finish()
