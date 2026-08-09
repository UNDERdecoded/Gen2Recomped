-- Driver: #189 S.S. Anne 1F door→room order. Enter each hallway cabin
-- door left→right; screenshot room contents (SHOT_DIR).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots-189"

  local doors = {}
  for i, w in ipairs(game.data.maps.SS_ANNE_1F.warps) do
    if w.destMap == "SS_ANNE_1F_ROOMS" then
      doors[#doors + 1] = { index = i, x = w.x, y = w.y, destWarp = w.destWarp }
    end
  end
  table.sort(doors, function(a, b) return a.x < b.x end)

  U.teleport(game, "SS_ANNE_1F_ROOMS", 12, 8, "down")
  U.shot(game, DIR .. "/anne189_rooms_overview.png")

  U.teleport(game, "SS_ANNE_1F", 20, 10, "up")
  U.shot(game, DIR .. "/anne189_hall_overview.png")

  for n, d in ipairs(doors) do
    U.teleport(game, "SS_ANNE_1F", d.x, d.y + 1, "up")
    U.shot(game, string.format("%s/anne189_door%d_hall_x%d.png", DIR, n, d.x))
    U.hold(game, "up", 24)
    local ow = game.overworld
    for _ = 1, 120 do
      U.wait(1)
      if ow.map.id == "SS_ANNE_1F_ROOMS" and not ow.transitioning
         and #(ow.scriptMoves or {}) == 0 and not ow.player.moving then
        break
      end
    end
    U.wait(10)
    local names = {}
    local col = math.floor(ow.player.cellX / 10)
    local row = math.floor(ow.player.cellY / 10)
    for _, npc in ipairs(ow.npcs or {}) do
      if math.floor(npc.cellX / 10) == col and math.floor(npc.cellY / 10) == row then
        names[#names + 1] = npc.def.name or "?"
      end
    end
    table.sort(names)
    U.log(string.format(
      "door%d hall(%d,%d)#%d destWarp=%d -> %s (%d,%d) cell=%d,%d npcs: %s",
      n, d.x, d.y, d.index, d.destWarp, ow.map.id,
      ow.player.cellX, ow.player.cellY, col, row, table.concat(names, ",")))
    U.shot(game, string.format("%s/anne189_door%d_room.png", DIR, n))
  end
end
