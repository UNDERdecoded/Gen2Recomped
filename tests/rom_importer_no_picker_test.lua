-- #482: pressing Import ROM crashed on iOS with
--
--   src/import/RomImporter.lua: attempt to call field 'pickFile' (a nil value)
--
-- love.system.pickFile is a native bridge, not part of LÖVE, so it is absent
-- on any mobile build that did not compile one. The mobile path called it
-- unguarded, so a missing bridge took the app down instead of falling back to
-- the copy-into-the-save-folder flow each caller already had for a device with
-- no document picker.
--
-- Self-contained: `luajit tests/rom_importer_no_picker_test.lua`; also
-- dofile'd by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer without a picker")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  getSaveDirectory = love.filesystem.getSaveDirectory,
}

love.filesystem.getSaveDirectory = function() return "/tmp/pokemon-love2d" end
love.system.getOS = function() return "iOS" end
-- the condition the crash reports were in: a build with no native bridge
love.system.pickFile = nil

local function freshImporter()
  return setmetatable({
    android = true,          -- RomImporter treats iOS as the mobile path
    workState = nil,
    ready = { red = false, blue = false, yellow = false },
    notice = nil,
    modNotice = nil,
    saveNotice = {},
    chooseVersion = nil,
    startData = function(self, data, displayName)
      self._started = { data = data, name = displayName }
    end,
    _installMod = function(self, name) self._mod = name end,
    _importSave = function(self, version, name) self._save = name end,
  }, RomImporter)
end

-- ------- Import ROM

local ri = freshImporter()
local ok, err = pcall(function() ri:choose("red") end)
check(ok, "Import ROM does not crash without a picker: " .. tostring(err))
check(ri.notice ~= nil, "and it explains itself instead of doing nothing")
eq(ri.notice.detail, "/tmp/pokemon-love2d",
  "pointing at the folder to copy the ROM into")
check(not ri.pickPending, "with no pick left pending on a picker that never opened")

-- Yellow takes the same path: the crash was never version-specific.
ri = freshImporter()
ok = pcall(function() ri:choose("yellow") end)
check(ok, "Import ROM for Yellow does not crash either")

-- ------- Import mod .zip

ri = freshImporter()
ok, err = pcall(function() ri:chooseMod() end)
check(ok, "Import mod does not crash without a picker: " .. tostring(err))
check(ri.modNotice ~= nil and ri.modNotice.ok == false,
  "and reports that the picker could not open")

-- ------- Import save

ri = freshImporter()
ok, err = pcall(function() ri:chooseSaveImport("red") end)
check(ok, "Import save does not crash without a picker: " .. tostring(err))
check(ri.saveNotice.red ~= nil and ri.saveNotice.red.ok == false,
  "and reports that the picker could not open")
eq(ri.androidPendingVersion, nil,
  "leaving no pending import for a pick that never happened")

-- ------- and the picker is still used when the bridge IS there

local pickCalls = 0
love.system.pickFile = function() pickCalls = pickCalls + 1 return true end
ri = freshImporter()
ri:choose("red")
eq(pickCalls, 1, "a build WITH the bridge still opens the picker")
check(ri.pickPending, "and waits for the pick to come back")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.filesystem.getSaveDirectory = saved.getSaveDirectory

S.finish()
