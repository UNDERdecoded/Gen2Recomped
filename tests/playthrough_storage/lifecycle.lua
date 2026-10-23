local M = {}
function M.run(f, version)
  local T, e, S, rows = f.T, f.e, f.Save, {}
  local function check(value, label)
    T.eq(value, true, label)
    rows[#rows + 1] = { case = label, value = value }
  end
  local a = { save = S.newGame({ version = version }) }
  local first = assert(e.context(a)).playthroughId
  check(e.write(a, "lifecycle/value", { n = 27 }), "lifecycle write")
  check(S.save(a.save, {}), "native ordinary save")
  S.resetSlotState()
  local loaded = { save = assert(S.load(version)) }
  check(e.context(loaded).playthroughId == first, "native reload preserves storage identity")
  check(e.read(loaded, "lifecycle/value").n == 27, "native reload preserves mod record")
  local b = { save = S.newGame({ version = version }) }
  check(e.context(b).playthroughId ~= first, "new game receives separate namespace")
  local value, code = e.read(b, "lifecycle/value")
  check(value == nil and code == "not_found", "new game cannot inherit prior mod record")
  loaded.stack = { states = { { screenId = "TitleState" } } }
  local selected = assert(e.selected(loaded))
  check(selected:context().playthroughId == first, "title resolves selected identity")
  check(selected:read("lifecycle/value").n == 27, "title resolves selected mod record")
  check(type(selected:context().normalSavedAt) == "number", "title resolves ordinary-save chronology")
  return rows
end
return M
