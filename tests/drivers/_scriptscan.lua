-- Ad-hoc: find every Gen2 script whose raw rows contain a given opcode
-- (SCAN=opcode[,opcode...]), printing label + the matching row.
local U = dofile("tests/drivers/util.lua")

return function(game)
  U.newGame(game)
  U.wait(20)
  local raw = game.data.map_scripts and game.data.map_scripts.scripts or {}
  local wanted = {}
  for op in (os.getenv("SCAN") or ""):gmatch("[^,]+") do
    wanted[(op:gsub("^%s+", ""):gsub("%s+$", ""))] = true
  end
  local labels = {}
  for label in pairs(raw) do labels[#labels + 1] = label end
  table.sort(labels)
  for _, label in ipairs(labels) do
    for i, row in ipairs(raw[label]) do
      if wanted[row[1]] then
        local parts = {}
        for _, v in ipairs(row) do parts[#parts + 1] = tostring(v) end
        U.log(("%-14s row %2d  %s"):format(label, i, table.concat(parts, " ")))
      end
    end
  end
  U.log("RESULT PASS")
end
