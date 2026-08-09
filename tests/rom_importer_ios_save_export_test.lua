package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer iOS save export")
local eq = S.eq
local check = S.check

love.system = love.system or {}
local saved = {
  createFile = love.system.createFile,
  read = love.filesystem.read,
  write = love.filesystem.write,
  getSaveDirectory = love.filesystem.getSaveDirectory,
}

local writes = {}
love.filesystem.read = function(name)
  eq(name, "exports/red.sav", "export reads the generated save")
  return "save-data"
end
love.filesystem.write = function(name, data)
  writes[#writes + 1] = { name = name, data = data }
  return true
end
love.filesystem.getSaveDirectory = function() return "/tmp/gen1recomp-save" end

local createCalls = {}
love.system.createFile = function(name, saveDirectory)
  createCalls[#createCalls + 1] = { name = name, saveDirectory = saveDirectory }
  return true
end

package.loaded["src.import.SaveFileIO"] = {
  exportActiveSlot = function(version)
    eq(version, "red", "exports the selected game save")
    return true, "exports/red.sav"
  end,
}

local RomImporter = require("src.import.RomImporter")
local ri = setmetatable({
  android = true,
  ios = true,
  workState = nil,
  saveNotice = {},
}, RomImporter)

ri:exportSave("red")

eq(#writes, 1, "stages the save for iOS export")
eq(writes[1].name, "pending_export.sav", "uses the native bridge staging name")
eq(writes[1].data, "save-data", "preserves the exported save data")
eq(#createCalls, 1, "opens the system destination picker")
eq(createCalls[1].name, "red.sav", "suggests the original save name")
eq(createCalls[1].saveDirectory, "/tmp/gen1recomp-save", "passes the exact staging directory")
check(ri.saveNotice.red.ok, "reports that the destination picker opened")

love.system.createFile = saved.createFile
love.filesystem.read = saved.read
love.filesystem.write = saved.write
love.filesystem.getSaveDirectory = saved.getSaveDirectory
package.loaded["src.import.SaveFileIO"] = nil

S.finish()
