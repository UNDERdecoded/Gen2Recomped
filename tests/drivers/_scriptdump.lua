-- Ad-hoc: print the lowered rows for named Gen2 script labels (SCRIPTS env,
-- comma separated, e.g. SCRIPTS=S45_4DB9,S45_4E3C).
local U = dofile("tests/drivers/util.lua")

return function(game)
  U.newGame(game)
  U.wait(20)
  local VM = require("src.script.Gen2ScriptVM")
  local raw = game.data.map_scripts and game.data.map_scripts.scripts or {}
  for label in (os.getenv("SCRIPTS") or ""):gmatch("[^,]+") do
    label = label:gsub("^%s+", ""):gsub("%s+$", "")
    U.log("=== " .. label .. (raw[label] and "" or "  (NOT FOUND)"))
    for i, row in ipairs(raw[label] or {}) do
      local parts = {}
      for _, v in ipairs(row) do parts[#parts + 1] = tostring(v) end
      U.log(("  %2d raw  %s"):format(i, table.concat(parts, " ")))
    end
    local rows = VM.compile(game.data, label)
    for i, row in ipairs(rows or {}) do
      local parts = {}
      for _, v in ipairs(row) do parts[#parts + 1] = tostring(v) end
      U.log(("  %2d low  %s"):format(i, table.concat(parts, " ")))
    end
  end
  U.log("RESULT PASS")
end
