local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_fields%.lua$")
  return dofile(codeRoot .. "/script_flags.lua").fixture(root, backend, version, "script_fields")
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  f.game.save.modData.foreign = { marker = 17 }
  local value = { phase = 2, enabled = false, items = { "A", 3 } }
  assert(
    f.exports.queue({
      { "wait", 1 },
      { "set_field", "portableRoot", true },
      { "set_field", "mod:story", value },
      { "set_option", "portableChoice", "FAST" },
      { "set_option", "mod:theme", false },
      { "set_flag", "mod:after" },
    })
  )
  value.phase = 9
  value.items[1] = "CHANGED"
  f:drain()
  assert(f.exports.result().success and f.exports.get("mod:after"))
  local save = f.game.save
  assert(save.portableRoot == true and save.modData.script_fields.story.phase == 2)
  assert(save.modData.script_fields.story.items[1] == "A" and save.modData.foreign.marker == 17)
  local report = {
    root = save.portableRoot,
    private = save.modData.script_fields.story,
    options = save.options,
    foreign = 17,
  }
  f = M.fixture(root, backend, version)
  local result, why =
    f.exports.queue({ { "set_field", "portableRoot", true }, { "set_field", "mod.foreign.field", 1 } })
  assert(result == nil and type(why) == "string" and f.game.save.portableRoot == nil)
  report.preflight = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
