-- Diagnostic: which solid regions of a map NO building template claimed.
--
--   $env:DIAG_MAP="ECRUTEAK_CITY"; $env:POKEPORT_DRIVER="mods/Gen2DramaticShapes/tests/_diag_unclaimed.lua"
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapId = os.getenv("DIAG_MAP") or "ECRUTEAK_CITY"
  U.teleport(game, mapId, tonumber(os.getenv("DIAG_X") or "5"),
             tonumber(os.getenv("DIAG_Y") or "5"), "up")
  U.wait(10)

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  local Structures = V and V.require("Structures")
  local ow = game.overworld
  if not (Structures and ow and ow.map) then
    print("[diag] mod or map unavailable")
    return
  end

  local map = ow.map
  local S = Structures.forMap(map)
  local tw, th = map.def.width * 4, map.def.height * 4
  local function key(tx, ty) return (ty + 64) * 4096 + (tx + 64) end

  print(("[diag] %s tileset=%s %dx%d tiles"):format(
    mapId, tostring(map.tileset.id), tw, th))

  -- a tile is "structure" when it carries the class we are hunting (the
  -- volume path's default for an unrecognised building is `wall`) and no
  -- template has claimed it
  local want = os.getenv("DIAG_CLASS") or "wall"
  local open = {}
  for ty = 0, th - 1 do
    for tx = 0, tw - 1 do
      local k = key(tx, ty)
      local sh = S.shapeAt[k]
      open[ty * tw + tx] = (sh and sh.class == want and not S.skip[k]) or nil
    end
  end

  -- flood into connected components, 4-way
  local seen, groups = {}, {}
  for ty = 0, th - 1 do
    for tx = 0, tw - 1 do
      local i = ty * tw + tx
      if open[i] and not seen[i] then
        local stack, cells = { i }, {}
        seen[i] = true
        local x0, x1, y0, y1 = tx, tx, ty, ty
        while #stack > 0 do
          local j = table.remove(stack)
          cells[#cells + 1] = j
          local cx, cy = j % tw, math.floor(j / tw)
          if cx < x0 then x0 = cx end
          if cx > x1 then x1 = cx end
          if cy < y0 then y0 = cy end
          if cy > y1 then y1 = cy end
          local function step(nx, ny)
            if nx < 0 or nx >= tw or ny < 0 or ny >= th then return end
            local nj = ny * tw + nx
            if open[nj] and not seen[nj] then
              seen[nj] = true
              stack[#stack + 1] = nj
            end
          end
          step(cx + 1, cy); step(cx - 1, cy)
          step(cx, cy + 1); step(cx, cy - 1)
        end
        local member = {}
        for _, j in ipairs(cells) do member[j] = true end
        groups[#groups + 1] = { n = #cells, x0 = x0, x1 = x1, y0 = y0, y1 = y1,
                                member = member }
      end
    end
  end

  table.sort(groups, function(a, b) return a.n > b.n end)
  local top = tonumber(os.getenv("DIAG_TOP") or "8")
  for g = 1, math.min(top, #groups) do
    local r = groups[g]
    local w, h = r.x1 - r.x0 + 1, r.y1 - r.y0 + 1
    print(("[diag] region %d: %d tiles, %dx%d at tile (%d,%d) = cell (%d,%d)")
      :format(g, r.n, w, h, r.x0, r.y0, math.floor(r.x0 / 2),
              math.floor(r.y0 / 2)))
    for ty = r.y0, r.y1 do
      local out = {}
      for tx = r.x0, r.x1 do
        -- a leading "*" is a cell some template already claimed; the id is
        -- printed either way, because authoring a grid needs the whole
        -- rectangle and not just the part that fell through
        out[#out + 1] = ("%s0x%02X"):format(
          S.skip[key(tx, ty)] and "*" or " ", S.tileAt[key(tx, ty)] or 0)
      end
      print("[diag]   { " .. table.concat(out, ", ") .. " },")
    end
  end
  print(("[diag] %d unclaimed regions total"):format(#groups))
  print("[diag] done")
end
