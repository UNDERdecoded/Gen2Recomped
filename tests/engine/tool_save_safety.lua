-- End-game persistence must honor a Game:writeSave veto so an ephemeral tool
-- session cannot overwrite the player's real save while THE END is on screen.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Commands = require("src.script.Commands")
local SaveData = require("src.core.SaveData")
local Screens = require("src.ui.Screens")

local originalPush, originalSave = Screens.push, SaveData.save
local screens = {}
local directWrites = 0

Screens.push = function(_, id, onDone, onTheEnd)
  screens[id] = { onDone = onDone, onTheEnd = onTheEnd }
  return screens[id]
end
SaveData.save = function()
  directWrites = directWrites + 1
  return true
end

local save = SaveData.newGame()
save.party = {}
local game = {
  data = { field = { boot = {} } },
  save = save,
  writeSave = function() return false end,
}
local runner = { yield = function() coroutine.yield() end }
local ctx = { game = game, save = save, runner = runner }
local co = coroutine.create(function() Commands.record_hall_of_fame(ctx) end)
local ok, err = coroutine.resume(co)
T.check(ok, "Hall of Fame command reaches its UI yield: " .. tostring(err))
T.check(screens.HallOfFame ~= nil, "Hall of Fame induction was requested")

screens.HallOfFame.onDone()
T.check(screens.Credits ~= nil, "credits were requested after induction")
screens.Credits.onTheEnd()
T.eq(directWrites, 0,
  "a vetoed Hall of Fame autosave performs no fallback disk write")

Screens.push, SaveData.save = originalPush, originalSave
T.finish("tool_save_safety")
