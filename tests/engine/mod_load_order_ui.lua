-- Manager staging, profile compatibility, and launcher pointer dispatch.
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = require("tests.love_stub")
local T = require("tests.harness")
local Manager = require("src.mods.ManagerState")
local Profile = require("src.mods.ModProfile")
local SaveData = require("src.core.SaveData")
local Order = require("src.mods.LoadOrder")
local Font = require("src.render.Font")

local available = {
  { id = "base", name = "Base", priority = -10, enabled = true, state = "loaded" },
  { id = "addon", name = "Addon", priority = 0, enabled = true, state = "loaded" },
  { id = "visual", name = "Visual", priority = 0, enabled = true, state = "loaded" },
}
local writes, restarts = 0, 0
local game = { save = { options = SaveData.defaultOptions() },
  mods = { requestedOrder = {}, status = function() return { available = available, errors = {} } end },
  writeOptions = function() writes = writes + 1 end,
  restartWithMods = function() restarts = restarts + 1 end,
}
local manager = Manager.new(game)
manager:refresh()
T.eq(manager.restartPending, false, "opening manager stages nothing")
local row = manager:modRows()[#manager:modRows()]
T.eq(row.label, "LOAD ORDER..", "manager exposes a load-order screen")
row.action()
T.eq(manager.screen, "order", "load-order action opens the screen")
T.eq(manager:orderRows()[1].orderId, "base", "manager defaults to manifest priority")
manager.cursor = 2
manager:adjustOrTab(-1)
T.same(game.save.options.modOrder, { "addon", "base", "visual" }, "controller left moves selected mod earlier")
T.eq(manager.cursor, 1, "selection follows moved mod")
T.check(manager.restartPending, "order-only edit requires restart")
T.eq(restarts, 0, "staging does not restart automatically")
T.same(game.mods.requestedOrder, {}, "staging does not change the running loader")
T.check(writes > 0, "order changes persist through the normal game writer")
manager:pressStart()
T.eq(manager.screen, "apply", "START opens apply for order-only changes")
manager:discardChanges()
T.same(game.save.options.modOrder, {}, "discard restores the boot preference")
T.eq(manager.restartPending, false, "discard clears pending order")
manager.screen, manager.cursor = "order", 1
manager:adjustOrTab(-1)
T.eq(manager.restartPending, false, "moving past boundary does not stage changes")
manager.cursor = 2
manager:adjustOrTab(-1)

local profile = Profile.capture(available, {}, game.save.options.modOrder)
profile.name = "ORDERED"
local decoded = assert(Profile.decode(Profile.encode(profile)))
T.same(decoded.order, { "addon", "base", "visual" }, "profile export/import retains order")
profile.order[1] = "mutated"
T.eq(game.save.options.modOrder[1], "addon", "profile capture is detached")
manager:discardChanges()
game.save.options.modProfiles = { decoded }
manager:applyProfile(decoded)
T.eq(game.save.options.modOrder[1], "addon", "applying profile stages its order")
T.check(manager.restartPending, "profile order arms restart")
T.eq(game.save.options.activeProfile, "ORDERED", "ordered profile stays active")
T.check(manager:matchesProfile(decoded), "profile match includes its order")
manager:discardChanges()
T.eq(manager:matchesProfile(decoded), false, "changed order no longer matches the profile")

local legacy = assert(Profile.decode(Profile.encode({ name = "LEGACY", enabled = {}, options = {}, slots = {} })))
T.eq(legacy.order, nil, "legacy modlist has no implicit reset")
game.save.options.modOrder = { "visual", "base", "addon" }
manager:applyProfile(legacy)
T.same(game.save.options.modOrder, { "visual", "base", "addon" }, "legacy profile preserves current order")
local malformed = assert(Profile.decode(Profile.encode({ name = "BADORDER", enabled = {},
  options = {}, slots = {}, order = { "visual", "visual", false, "base" } })))
T.same(malformed.order, { "visual", "base" }, "import normalizes duplicate and invalid entries")
T.eq(Profile.decode(Profile.encode({ name = "BADTYPE", enabled = {},
  options = {}, slots = {}, order = "bad" })), nil, "invalid profile order cannot silently reset preferences")
local seeded = { modOrder = { "visual", "addon", "base" } }
Profile.ensureFirst(seeded, available, {})
T.same(seeded.modProfiles[1].order, seeded.modOrder, "first profile captures the existing order")

-- Exercise the normal drawing branch so a navigable but blank screen fails.
local labels, oldDraw = {}, Font.draw
Font.draw = function(s) labels[#labels + 1] = s end
manager.screen = "order"
manager.notice = nil
manager:draw()
Font.draw = oldDraw
T.check(table.concat(labels, "|"):find("LOAD ORDER", 1, true) ~= nil, "order screen draws its title")
T.check(table.concat(labels, "|"):find("LEFT/RIGHT:MOVE", 1, true) ~= nil, "order screen draws controller hint")

local RI = require("src.import.RomImporter")
local moved
local launcher = setmetatable({ tab = "mods", slotScroll = {},
  modOrderRects = { { x = 100, y = 200, width = 80, height = 30, id = "addon", delta = 1 } },
  _moveModInOrder = function(_, id, delta) moved = { id, delta } end,
}, RI)
launcher:mousepressed(110, 210, 1)
T.same(moved, { "addon", 1 }, "launcher dispatches the clicked order button")
launcher:_resetFrameRects()
T.eq(launcher.modOrderRects, nil, "frame reset removes stale move targets")
T.eq(launcher.modResetOrderRect, nil, "frame reset removes stale reset target")
T.eq(launcher.modOrderViewRect, nil, "frame reset removes stale view target")
moved = nil
launcher:mousepressed(110, 210, 1)
T.eq(moved, nil, "clicking a previous frame's button cannot reorder")

T.finish("mod load order UI and profiles")
