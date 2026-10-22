local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_gifts%.lua$")
  local f = dofile(codeRoot .. "/script_state.lua").fixture(root, backend, version, "script_gifts")
  love = love or require("tests.love_stub")
  local data, save = f.game.data, f.game.save
  data.text = data.text or {}
  data.font = data.font or dofile(codeRoot .. "/../fixture_data/font.lua")
  if not getmetatable(data) then
    setmetatable(data, { __index = require("src.core.Data") })
  end
  save.player = save.player or {}
  save.player.name, save.player.id = "TEST", 12345
  f.game.input = {
    wasPressed = function()
      return false
    end,
    isDown = function()
      return false
    end,
  }
  local Stack = require("src.core.StateStack")
  setmetatable(f.game.stack, { __index = Stack })
  f.ow.update = function(self)
    self.runner:update()
  end
  require("src.render.Font").load(data)
  if backend == "gen1" and f.gen == 3 then
    local pokemon = require("src.core.game3.pokemon")
    pokemon._learnsets, pokemon._national, pokemon._abilityNames = {}, { [151] = 151 }, {}
  end
  f.party = function()
    local mon = save.party[#save.party]
    return { count = #save.party, level = mon.level, species = (mon.species == 151 and "MEW" or mon.species) }
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "give_item", "POTION", 2, false },
    { "give_pokemon", "MEW", 5, true, false },
    { "set_flag", "mod:gifted" },
  }))
  f:drain()
  assert(f.exports.result().success == true and f.exports.get("mod:gifted") == true)
  assert(f.quantity() == 5 and #f.game.save.party == 2)
  local report = { items = f.quantity(), party = f.party() }
  f = M.fixture(root, backend, version)
  local value, why =
    f.exports.queue({ { "give_item", "POTION", 1, false }, { "give_pokemon", "UNKNOWN", 5, true, false } })
  assert(value == nil and type(why) == "string" and f.quantity() == 3 and #f.game.save.party == 1)
  report.preflight = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
