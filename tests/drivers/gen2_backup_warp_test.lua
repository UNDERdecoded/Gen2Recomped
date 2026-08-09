local U = dofile("tests/drivers/util.lua")
local pass, fail = 0, 0
local function check(name, cond, got)
  if cond then pass = pass + 1 else fail = fail + 1 end
  U.log((cond and "PASS " or "FAIL ") .. name .. (cond and "" or " (got " .. tostring(got) .. ")"))
end

-- GSC warp id $FF means "back through the warp you came in by"
-- (EnterMapWarp swaps in wBackupWarp/MapGroup/MapNumber).  Every Pokecenter
-- 2F leaves by one, and the group/map bytes stored beside it name the 2F
-- itself -- taking those literally dumped the player at the middle of 2F.
return function(game)
  local data = game.data

  local sentinels = 0
  local seen = {}
  for _, def in pairs(data.maps) do
    if type(def) == "table" and def.warps and not seen[def.id or def] then
      seen[def.id or def] = true
      for _, w in ipairs(def.warps) do
        if w.destWarp == 255 then
          sentinels = sentinels + 1
          check("map " .. tostring(def.id) .. " warp $FF is LAST_WARP",
            w.destMap == "LAST_WARP", w.destMap)
        end
      end
    end
  end
  check("found the $FF warps", sentinels >= 1, sentinels)

  U.newGame(game); U.wait(20)
  U.teleport(game, "CHERRYGROVE_POKECENTER1_F", 0, 7); U.wait(30)
  local ow = game.stack:top()
  local up
  for _, w in ipairs(ow.map.def.warps) do
    if w.destMap == "POKECENTER2_F" then up = w end
  end
  check("1F has a stairs warp", up ~= nil)
  if not up then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail + 1))
    return
  end

  ow:takeWarp(up)
  U.wait(90)
  ow = game.stack:top()
  check("stairs reach 2F", ow.map.id == "POKECENTER2_F", ow.map.id)
  check("2F lands on the stairs cell",
    ow.player.cellX == 0 and ow.player.cellY == 7,
    ow.player.cellX .. "," .. ow.player.cellY)

  ow:takeWarp(ow.map.def.warps[1])
  U.wait(90)
  ow = game.stack:top()
  check("2F stairs return to the 1F we came from",
    ow.map.id == "CHERRYGROVE_POKECENTER1_F", ow.map.id)
  check("1F lands back on its stairs cell",
    ow.player.cellX == 0 and ow.player.cellY == 7,
    ow.player.cellX .. "," .. ow.player.cellY)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
end
