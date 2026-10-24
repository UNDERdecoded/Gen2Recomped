package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local old = V.get()
for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
  for _, version in ipairs(V.ORDER) do
    if V.generation(version) == 2 then
      dofile("tests/mart_content/cases.lua").run(".", "gen2", version, mode[1], mode[2])
    else
      local f = dofile("tests/mart_content/fixture.lua").new(".", "gen2", version, mode[1], mode[2], "none")
      local m = f.e.api.content.marts
      T.eq(f.e.api:supports("content", "marts"), false, "honest unavailable generation")
      T.eq(m:get("0"), nil, "unavailable get has no shelf")
      T.eq(m:each()(), nil, "unavailable enumeration is empty")
      local original = f.data.map_scripts.marts[0]
      m:patch("0", { "ULTRA_BALL" })
      T.eq(next(f.result.loader.content.marts.ops), nil, "unavailable write adds no operation")
      T.eq(f.data.map_scripts.marts[0], original, "unavailable write leaves native data intact")
      f.close()
    end
  end
end
V.set(old)
T.finish("public mart content and native purchases")
