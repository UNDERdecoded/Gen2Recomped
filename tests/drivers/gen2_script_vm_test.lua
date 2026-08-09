-- Smoke test for the Gen2 script VM.  Confirms the ROM disassembly in
-- data/generated/map_scripts.lua is attached as MapScripts base contributions
-- and that a few known-shape scripts lower into runnable ScriptRunner rows.
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_script_vm_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Data = require("src.core.Data")
  local mapScripts = require("data.scripts.init")
  local ScriptRunner = require("src.script.ScriptRunner")

  local pass, fail = 0, 0
  local function check(label, ok, detail)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label .. (detail and (" -- " .. detail) or ""))
  end

  local store = Data.map_scripts
  check("map_scripts loaded", store ~= nil)
  if not store then U.log("RESULT", "FAIL"); love.event.quit(1); return end

  local info = store.info or {}
  check("maps decoded", (info.mapCount or 0) > 300, tostring(info.mapCount))
  check("scripts decoded", (info.scriptCount or 0) > 2000, tostring(info.scriptCount))
  check("coord events decoded", (info.coordCount or 0) > 50, tostring(info.coordCount))
  check("desyncs negligible", (info.desyncCount or 0) < 10, tostring(info.desyncCount))

  -- every lowered row has to be a command ScriptRunner can actually resolve,
  -- otherwise the script degrades silently at runtime instead of at import
  local VM = require("src.script.Gen2ScriptVM")
  local checked, bad, verbs = 0, 0, {}
  for label in pairs(store.scripts or {}) do
    if checked < 400 then
      local rows = VM.compile(Data, label)
      if rows then
        checked = checked + 1
        for _, problem in ipairs(ScriptRunner.validate(rows)) do
          bad = bad + 1
          if #verbs < 5 then verbs[#verbs + 1] = problem end
        end
      end
    end
  end
  check("lowered rows validate", bad == 0,
    string.format("%d scripts, %d problems %s", checked, bad, table.concat(verbs, "; ")))

  -- the maps the errand chain runs through must all carry a contribution
  for _, mapId in ipairs({ "ELMS_LAB", "CHERRYGROVE_CITY", "ROUTE30", "ROUTE31" }) do
    local view = mapScripts.get(mapId)
    check("contribution for " .. mapId, view ~= nil and next(view) ~= nil)
  end

  U.log("RESULT", fail == 0 and "PASS" or "FAIL")
  love.event.quit(fail == 0 and 0 or 1)
end
