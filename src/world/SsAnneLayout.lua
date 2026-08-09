-- S.S. Anne 1F cabins: ROM packs rooms so hallway doors map right→left
-- onto the 3×2 rooms map (warp 1 = top-left = rightmost door).  Survey
-- zoom makes that look left/right flipped vs 2F/B1F.  Reorder door→cell
-- and slide objects so each door keeps its OG occupants while L→R doors
-- land in reading order on the rooms map.

local SsAnneLayout = {}

local function leftmostRoomDoor(hall)
  local best
  for _, w in ipairs(hall.warps or {}) do
    if w.destMap == "SS_ANNE_1F_ROOMS" then
      if not best or w.x < best.x then best = w end
    end
  end
  return best
end

function SsAnneLayout.apply(maps)
  if not maps then return false end
  local hall = maps.SS_ANNE_1F
  local rooms = maps.SS_ANNE_1F_ROOMS
  if not hall or not rooms then return false end
  local left = leftmostRoomDoor(hall)
  -- already hallway-ordered (leftmost door → rooms warp 1)
  if not left or left.destWarp == 1 then return false end

  local doors = {}
  for _, w in ipairs(hall.warps) do
    if w.destMap == "SS_ANNE_1F_ROOMS" then doors[#doors + 1] = w end
  end
  table.sort(doors, function(a, b) return a.x < b.x end)
  for i, w in ipairs(doors) do w.destWarp = i end

  -- rooms warps 1..6 return through hall warps 8..3 (L→R cabin doors)
  for i, w in ipairs(rooms.warps or {}) do
    if w.destMap == "SS_ANNE_1F" then w.destWarp = 9 - i end
  end

  local warpPos = {}
  for i, w in ipairs(rooms.warps or {}) do
    warpPos[i] = { x = w.x, y = w.y }
  end
  for _, o in ipairs(rooms.objects or {}) do
    local col, row = math.floor(o.x / 10), math.floor(o.y / 10)
    local oldK
    for k, p in ipairs(warpPos) do
      if math.floor(p.x / 10) == col and math.floor(p.y / 10) == row then
        oldK = k
        break
      end
    end
    if oldK then
      local newK = 7 - oldK
      o.x = o.x + (warpPos[newK].x - warpPos[oldK].x)
      o.y = o.y + (warpPos[newK].y - warpPos[oldK].y)
    end
  end
  return true
end

return SsAnneLayout
