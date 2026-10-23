package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/input_hooks/fixture.lua")
local f = Fixture.new(".", "gen2", "red", 2, "native")
dofile("tests/input_hooks/cases.lua").run(f)
f.close()
-- The no-mod path bypasses Runtime.call altogether for all three hooks.
local Runtime = require("src.mods.Runtime")
local none = Fixture.new(".", "gen2", "red", 2, "native", true)
for _, name in ipairs({ "input.key", "input.gamepad", "input.wheel" }) do
  T.eq(Runtime.wantsHook(name), false, "no subscriber: " .. name)
end
local call = Runtime.call
Runtime.call = function()
  error("unsubscribed input entered hook bus")
end
none.game:keypressed("up")
T.eq(none.Input:isDown("up"), true, "no-mod native key press")
none.game:keyreleased("up")
T.eq(none.Input:isDown("up"), false, "no-mod native key release")
none.game:gamepadpressed(none.pad, "a")
T.eq(none.Input:isDown("a"), true, "no-mod native pad press")
none.game:gamepadreleased(none.pad, "a")
T.eq(none.Input:isDown("a"), false, "no-mod native pad release")
none.game:gamepadaxis(none.pad, "leftx", 0.9)
T.eq(none.Input:isDown("right"), true, "no-mod native axis")
none.game:gamepadaxis(none.pad, "leftx", 0)
none.game:wheelmoved(0, 1)
T.same(none.zoom, { 1 }, "no-mod native wheel")
Runtime.call = call
none.close()
T.finish("portable input hooks")
