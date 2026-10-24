package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local fixture = dofile(root .. "/tests/status_hud/fixture.lua")
local f = fixture.new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/status_hud/cases.lua").run(f)
f.close()
local bare = fixture.new(root, backend, version, api, format, true)
bare.T.eq(require("src.mods.Runtime").wantsHook("battle.status_hud_visible"), false, "no-mod Runtime")
bare.T.eq(bare.visible(), true, "no-mod default true")
bare.T.eq(bare.draw(), true, "no-mod native HUD draw")
bare.close()
print("STATUS_HUD_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable battle.status_hud_visible contract")
