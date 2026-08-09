-- scratch: walk up to a map object and press A the way the player does,
-- logging what the overworld actually ran.
--   TALKMAP=OLIVINE_GOOD_ROD_HOUSE TALKAT=2,4 TALKFACE=up
local U = require("tests.drivers.util")

return function(game)
  U.newGame(game)
  U.wait(20)
  local pre = os.getenv("TALKFLAG")
  if pre then
    game.save.flags = game.save.flags or {}
    for f in pre:gmatch("[^,]+") do game.save.flags[f] = true end
  end
  local mapId = os.getenv("TALKMAP")
  local at = os.getenv("TALKAT") or "0,0"
  local x, y = at:match("(%d+),(%d+)")
  U.teleport(game, mapId, tonumber(x), tonumber(y), os.getenv("TALKFACE") or "up")
  U.wait(20)

  local walk = os.getenv("TALKWALK")
  if walk then
    for dir, n in walk:gmatch("(%a+)(%d+)") do
      for _ = 1, tonumber(n) do
        U.hold(game, dir, 22)
        U.wait(6)
      end
    end
    U.wait(30)
  end

  local ow = game.stack:top()
  U.log(("map=%s player=(%d,%d) facing=%s")
    :format(tostring(ow.map and ow.map.id), ow.player.cellX, ow.player.cellY,
            tostring(ow.player.facing)))
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def or {}
    U.log(("npc %s (%d,%d) text=%s script=%s item=%s")
      :format(tostring(d.name), n.cellX, n.cellY, tostring(d.text),
              tostring(d.script), tostring(d.item)))
  end

  local MapScripts = require("src.script.MapScripts")
  local live = ow.map and ow.map.id
  for _, n in ipairs(ow.npcs or {}) do
    local key = n.def.text or n.def.script
    local rows = key and MapScripts.talkScript(live, key)
    U.log(("key=%s rows=%s"):format(tostring(key),
      rows and tostring(#rows) or "nil"))
    for _, row in ipairs(rows or {}) do
      if row[1] == "show_text" or row[1] == "g2_yesno" then
        local s = game.data.text[row[2]]
        U.log(("   %s %s -> %s"):format(row[1], tostring(row[2]),
          tostring(s and s:sub(1, 48))))
      end
    end
  end

  U.tap(game, "a")
  U.wait(20)
  local top = game.stack:top()
  U.log("top state after A: " .. tostring(top and top.__name or top))
  U.log("runner: " .. tostring(ow.runner and ow.runner:isRunning()))
  for gy = 0, (ow.map.heightCells or ow.map.height or 8) - 1 do
    local row = {}
    for gx = 0, (ow.map.widthCells or ow.map.width or 8) - 1 do
      row[#row + 1] = ow.map:isWalkableCell(gx, gy) and "." or "#"
    end
    U.log(("row %2d %s"):format(gy, table.concat(row)))
  end
  U.log("RESULT PASS")
end
