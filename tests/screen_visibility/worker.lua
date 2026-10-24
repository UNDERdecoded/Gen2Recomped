package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
local fixture = dofile(root .. "/tests/screen_visibility/fixture.lua")
local f = fixture.new(root, backend, version, api, format)
local rows = dofile(root .. "/tests/screen_visibility/cases.lua").run(f)
f.close()
local bare = fixture.new(root, backend, version, api, format, true)
bare.T.eq(require("src.mods.Runtime").wantsHook("screen.render_visible"), false, "no-mod Runtime")
bare.T.eq(bare.stack:renderVisible(bare.menu), true, "no-mod visibility default")
bare.T.same(bare.frame({ bare.base, bare.menu }), { "BagMenu" }, "no-mod native composition")
bare.close()
print("SCREEN_VISIBILITY_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable screen.render_visible contract")
