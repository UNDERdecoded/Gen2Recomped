local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/flags%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "flags")
  if backend == "gen1" and f.gen == 2 then
    f.ow.events = require("src.world.gen2.Events").new()
  elseif backend == "gen1" and f.gen == 3 then
    package.loaded["src.core.game3.scripting.space"].store = { flags = f.game.save.flags, vars = {} }
  end
  if f.gen == 1 then
    f.number, f.symbol = 0, "EVENT_FOLLOWED_OAK_INTO_LAB"
  elseif f.gen == 2 then
    f.number, f.symbol = 16, "EVENT_GOT_HM01_CUT"
  else
    f.symbol = "FLAG_SYS_POKEDEX_GET"
    local catalog = dofile(
      codeRoot .. "/../../src/mods/flag_names/" .. (version == "emerald" and "emerald" or "firered") .. ".lua"
    )
    for number, row in pairs(catalog.records) do
      for _, alias in ipairs(row) do
        if alias == f.symbol then
          f.number = number
        end
      end
    end
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local report = { invalid = {} }
  for _, name in ipairs({ -1, 0.5, math.huge, "UNKNOWN_NATIVE_FLAG", {}, false }) do
    local value, why = f.exports.set(name, true)
    assert(
      value == nil
        and (
          why == "invalid or unknown flag"
          or version == "crystal"
            and type(name) == "string"
            and why == "symbolic event flags unavailable for Crystal; use native ids"
        ),
      tostring(why)
    )
    assert(#f.exports.events() == 0)
    report.invalid[#report.invalid + 1] = why
  end
  assert(f.exports.get(f.number) == false)
  assert(f.exports.set(f.number, true))
  assert(f.exports.get(f.number) == true)
  assert(f.exports.set(f.number, true))
  assert(#f.exports.events() == 1)
  if version == "crystal" then
    local value, why = f.exports.get(f.symbol)
    assert(value == nil and why == "symbolic event flags unavailable for Crystal; use native ids")
    report.symbol = why
  else
    assert(f.exports.get(f.symbol) == true)
    assert(f.exports.set(f.symbol, false))
    assert(f.exports.get(f.number) == false)
    assert(#f.exports.events() == 2)
    report.symbol = true
  end
  report.events = f.exports.events()
  assert(f.exports.set("mod:quest", true))
  assert(f.exports.get("mod.flags.quest") == true)
  local value, why = f.exports.set("mod.other.quest", true)
  assert(value == nil and why == "foreign mod flag")
  report.private = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
