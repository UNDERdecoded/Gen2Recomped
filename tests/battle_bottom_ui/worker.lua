package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local fixture = dofile(root .. "/tests/battle_bottom_ui/fixture.lua")
local f = fixture.new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/battle_bottom_ui/cases.lua").run(f)
f.close()
local bare = fixture.new(root, backend, version, api, format, true)
bare.T.eq(require("src.mods.Runtime").wantsHook("battle.bottom_ui_visible"), false, "no-mod Runtime")
bare.T.eq(bare.visible(), true, "no-mod default true")
bare.T.eq(bare.draw(), true, "no-mod native bottom draw")
bare.close()
print("BATTLE_BOTTOM_UI_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable battle.bottom_ui_visible contract")
