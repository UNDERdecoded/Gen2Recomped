-- Map browser: view any map, follow its warps, and set the save's spawn point
-- / remembered outdoor or heal spot by clicking cells on the rendered map.
-- Reuses the game's own MapLoader/TileRenderer/Warp so the editor's view
-- matches what the player would actually see.
--
-- Three columns: a searchable map list, the viewport, and the spawn
-- inspector.  Overlays are drawn in this order so the selection always wins:
--   cyan hollow  warp cell (clicking follows the warp)
--   red filled   the save's player position
--   green / amber  lastHeal / lastOutdoor
--   yellow hollow  the current click selection

local MapLoader = require("src.world.MapLoader")
local Warp = require("src.world.Warp")
local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local MapBrowser = {}

local CELL = 16   -- the walk grid; a cell is 16px of map art

local function clampZoom(z)
  if z < 1 then return 1 end
  if z > 4 then return 4 end
  return z
end

-- Point the camera so (cx,cy) lands in the middle of the viewport.  The
-- viewport size is only known while drawing, so it is stashed on S.
local function centerOn(S, cx, cy)
  local vw = S._mapViewW or 480
  local vh = S._mapViewH or 432
  S.mapCamX = cx * CELL - vw / (2 * S.mapZoom)
  S.mapCamY = cy * CELL - vh / (2 * S.mapZoom)
end
MapBrowser.centerOn = centerOn

local function sortedMapIds(data)
  local ids = {}
  for id in pairs(data.maps) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- LAST_MAP warps resolve against the remembered outdoor spot; skip with a
-- status message if the save has none (fresh games, or old saves).  Mirrors
-- the game: leaving an OVERWORLD/PLATEAU map via a warp updates lastOutdoor
-- so building exits (Indigo lobby, Route 22 Gate, ...) return to the map you
-- entered from.
local OUTSIDE_TILESETS = { OVERWORLD = true, PLATEAU = true }

local function goToWarp(S, warp)
  local def = warp.def
  local fromMap = S.data.maps[S.mapId]
  if fromMap and OUTSIDE_TILESETS[fromMap.tileset]
     and def.destMap ~= "LAST_MAP" and def.destMap ~= S.mapId then
    S.save.lastOutdoor = { id = S.mapId, x = def.x, y = def.y }
  end
  if def.destMap == "LAST_MAP" and not S.save.lastOutdoor then
    S.status = "Can't follow warp: no remembered outdoor map (lastOutdoor unset)"
    return
  end
  local ok, destMap, dx, dy = pcall(Warp.destination, S.data, def, S.save.lastOutdoor)
  if not ok then
    S.status = "Warp failed: " .. tostring(destMap)
    return
  end
  S.mapId = destMap
  S.mapClickCell = nil
  centerOn(S, dx, dy)
  -- claim the lazy first-draw centering below, so it does not immediately
  -- re-centre the destination map and lose the warp's landing cell
  S._mapCenteredFor = destMap
  S.status = "Followed warp to " .. destMap
end

-- Screen-space point inside the viewport -> map cell, or nil if the point is
-- outside the viewport or off the edge of the map.
local function cellAtScreen(S, map, Kit, vx, vy, vw, vh)
  if Kit.mouseX < vx or Kit.mouseX >= vx + vw
     or Kit.mouseY < vy or Kit.mouseY >= vy + vh then
    return nil
  end
  local wx = (Kit.mouseX - vx) / S.mapZoom + S.mapCamX
  local wy = (Kit.mouseY - vy) / S.mapZoom + S.mapCamY
  local cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
  if not map:inBounds(cx, cy) then return nil end
  return cx, cy
end

-- Wired from App.wheelmoved while the Map tab is active.
function MapBrowser.wheelmoved(S, dy)
  S.mapZoom = clampZoom((S.mapZoom or 2) + (dy > 0 and 0.25 or -0.25))
end

local PAN_KEYS = {
  up = { 0, -CELL }, w = { 0, -CELL },
  down = { 0, CELL }, s = { 0, CELL },
  left = { -CELL, 0 }, a = { -CELL, 0 },
  right = { CELL, 0 }, d = { CELL, 0 },
}

-- Wired from App.keypressed while the Map tab is active.
function MapBrowser.keypressed(S, key)
  local d = PAN_KEYS[key]
  if not d then return end
  S.mapCamX = (S.mapCamX or 0) + d[1]
  S.mapCamY = (S.mapCamY or 0) + d[2]
end

-- Select a map by id.  The camera is left to the first-draw centering in
-- draw(), which knows the viewport size and so can actually centre.
function MapBrowser.select(S, id)
  S.mapId = id
  S.mapClickCell = nil
  S._mapCenteredFor = nil
  S.status = "Viewing " .. id
end

-- Called inside the viewport's translate+scale transform, so every rect is
-- in map space: a cell is CELL units wide whatever the zoom is.
local function drawOverlays(S, map)
  local function cellRect(cx, cy)
    return cx * CELL - S.mapCamX, cy * CELL - S.mapCamY, CELL, CELL
  end
  love.graphics.setColor(0.27, 0.59, 1, 0.55)
  for _, wdef in ipairs(map.def.warps) do
    love.graphics.rectangle("line", cellRect(wdef.x, wdef.y))
  end
  if S.save.player.map == S.mapId then
    love.graphics.setColor(1, 0.36, 0.4, 0.9)
    love.graphics.rectangle("fill", cellRect(S.save.player.x, S.save.player.y))
  end
  local heal = S.save.lastHeal
  if heal and heal.map == S.mapId then
    love.graphics.setColor(0.24, 0.88, 0.54, 0.9)
    love.graphics.rectangle("line", cellRect(heal.x, heal.y))
  end
  local out = S.save.lastOutdoor
  if out and out.id == S.mapId then
    love.graphics.setColor(1, 0.8, 0.02, 0.9)
    love.graphics.rectangle("line", cellRect(out.x, out.y))
  end
  if S.mapClickCell then
    love.graphics.setColor(1, 1, 0.35, 0.95)
    love.graphics.rectangle("line", cellRect(S.mapClickCell.cx, S.mapClickCell.cy))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function MapBrowser.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s
  local pad = 16 * s
  S.mapQuery = S.mapQuery or ""
  S.mapZoom = clampZoom(S.mapZoom or 2)

  local listW = math.max(200 * s, math.min(260 * s, w * 0.2))
  local sideW = math.max(230 * s, math.min(300 * s, w * 0.22))
  local viewX = x + listW + gap
  local viewW = w - listW - sideW - 2 * gap

  -- --------------------------------------------------------- the map list
  Kit.card(x, y, listW, h)
  Kit.caption(x + pad, y + pad, "MAPS")
  local qy = y + pad + Kit.textHeight("caption") + 8 * s
  S.mapQuery = Kit.textfield("map-query", x + pad, qy, listW - 2 * pad, 32 * s,
    S.mapQuery, "search maps...")

  local ids = {}
  for _, id in ipairs(sortedMapIds(S.data)) do
    if S.mapQuery == "" or id:lower():find(S.mapQuery:lower(), 1, true) then
      ids[#ids + 1] = id
    end
  end

  local gotoH = 34 * s
  local gotoY = y + h - pad - gotoH
  local pagerH = 30 * s
  local pagerY = gotoY - 10 * s - pagerH
  local listTop = qy + 32 * s + 10 * s
  local mRowH = 26 * s
  local mGap = 4 * s
  local perPage = math.max(1, math.floor((pagerY - 10 * s - listTop) / (mRowH + mGap)))
  S.mapListOffset = Ops.clamp(S.mapListOffset or 0, 0, math.max(0, #ids - perPage))

  for i = 1, math.min(perPage, #ids - S.mapListOffset) do
    local id = ids[S.mapListOffset + i]
    local ry = listTop + (i - 1) * (mRowH + mGap)
    if Kit.row(x + pad, ry, listW - 2 * pad, mRowH, id == S.mapId, PAL.blue, 7 * s) then
      MapBrowser.select(S, id)
    end
    Kit.text("tiny", Kit.ellipsize("tiny", id, listW - 2 * pad - 18 * s),
      x + pad + 9 * s, ry + (mRowH - Kit.textHeight("tiny")) / 2,
      id == S.mapId and PAL.heading or PAL.muted)
  end
  if #ids == 0 then
    Kit.text("mono", "no map matches", x + pad + 9 * s, listTop + 8 * s, PAL.faint)
  end
  S.mapListOffset = Kit.pager(x + pad, pagerY, listW - 2 * pad, S.mapListOffset,
    #ids, perPage)
  if Kit.button(x + pad, gotoY, listW - 2 * pad, gotoH, "Go to save location",
      { font = "small", radius = 9 * s }) then
    MapBrowser.select(S, S.save.player.map)
    Ops.say(S, ("Jumped to %s (%d,%d)"):format(S.save.player.map,
      S.save.player.x, S.save.player.y))
  end

  -- ---------------------------------------------------------- the viewport
  Kit.card(viewX, y, viewW, h)
  local vpad = 18 * s
  local vx0 = viewX + vpad
  local vinner = viewW - 2 * vpad
  local headH = 28 * s
  Kit.text("monoBig", tostring(S.mapId), vx0,
    y + vpad + (headH - Kit.textHeight("monoBig")) / 2, PAL.heading)

  local ok, map = pcall(MapLoader.load, S.data, S.mapId)
  if not ok then
    Kit.text("mono", "Failed to load map: " .. tostring(map), vx0,
      y + vpad + headH + 20 * s, PAL.red)
    return
  end

  local outdoor = Ops.isOutdoor(S, map)
  local oLabel = outdoor and "OUTDOOR" or "INDOOR"
  local oW = Kit.textWidth("tiny", oLabel) + 16 * s
  local oX = vx0 + Kit.textWidth("monoBig", tostring(S.mapId)) + 14 * s
  Theme.stroke(oX, y + vpad + (headH - 20 * s) / 2, oW, 20 * s, 6 * s,
    PAL.cardBorder, 0.3, 1)
  Kit.textCenter("tiny", oLabel, oX,
    y + vpad + (headH - 20 * s) / 2 + (20 * s - Kit.textHeight("tiny")) / 2, oW,
    outdoor and PAL.green or PAL.muted)

  -- zoom cluster, right-aligned in the viewport header
  local centerW = 130 * s
  local zBtn = 32 * s
  local rightEdge = vx0 + vinner
  if Kit.button(rightEdge - centerW, y + vpad, centerW, headH, "Center on player",
      { kind = "accent", font = "small", radius = 7 * s }) then
    if S.save.player.map == S.mapId then
      centerOn(S, S.save.player.x, S.save.player.y)
      Ops.say(S, "Centred on the player")
    else
      Ops.say(S, "Player isn't on this map")
    end
  end
  local zx = rightEdge - centerW - 10 * s - (2 * zBtn + 56 * s + 12 * s)
  if Kit.stepper(zx, y + vpad, zBtn, headH, "-", { radius = 7 * s }) then
    S.mapZoom = clampZoom(S.mapZoom - 0.5)
  end
  Kit.textCenter("mono", ("%.2fx"):format(S.mapZoom), zx + zBtn + 6 * s,
    y + vpad + (headH - Kit.textHeight("mono")) / 2, 56 * s, PAL.muted)
  if Kit.stepper(zx + zBtn + 62 * s, y + vpad, zBtn, headH, "+", { radius = 7 * s }) then
    S.mapZoom = clampZoom(S.mapZoom + 0.5)
  end

  local legendH = 22 * s
  local vy0 = y + vpad + headH + 12 * s
  local vh0 = (y + h - vpad - legendH - 10 * s) - vy0
  S._mapViewW, S._mapViewH = vinner, vh0

  -- First draw of a map: park the camera somewhere meaningful rather than at
  -- (0,0), which leaves a small map wedged in the top-left corner.  Deferred
  -- to here because centerOn needs the viewport size, which only exists once
  -- the panel has laid itself out.
  if S._mapCenteredFor ~= S.mapId then
    S._mapCenteredFor = S.mapId
    if S.save.player.map == S.mapId then
      centerOn(S, S.save.player.x, S.save.player.y)
    else
      centerOn(S, map.widthCells / 2, map.heightCells / 2)
    end
  end

  Theme.col(PAL.bgBot, 1)
  love.graphics.rectangle("fill", vx0, vy0, vinner, vh0, 12 * s, 12 * s)
  Theme.stroke(vx0, vy0, vinner, vh0, 12 * s, PAL.cardBorder, 0.28, 1)

  -- love_stub (headless tests) lacks push/pop/scale/scissor; skip the actual
  -- render there but keep all click/button logic below running.
  if love.graphics.push then
    love.graphics.setScissor(math.floor(vx0), math.floor(vy0),
      math.ceil(vinner), math.ceil(vh0))
    love.graphics.push()
    love.graphics.translate(vx0, vy0)
    love.graphics.scale(S.mapZoom, S.mapZoom)
    map.renderer:draw(S.mapCamX, S.mapCamY)
    drawOverlays(S, map)
    love.graphics.pop()
    love.graphics.setScissor()
  end

  -- click handling: warp cells jump the view, everything else selects
  if Kit.mouseClicked then
    local cx, cy = cellAtScreen(S, map, Kit, vx0, vy0, vinner, vh0)
    if cx then
      local warp = map:warpAtCell(cx, cy)
      if warp then
        goToWarp(S, warp)
      else
        S.mapClickCell = { cx = cx, cy = cy }
        S.status = string.format("Selected cell (%d,%d) on %s", cx, cy, S.mapId)
      end
    end
  end

  -- legend + the current selection readout
  local ly = y + h - vpad - legendH + 4 * s
  local lx = vx0
  local legend = {
    { PAL.blue, "warp", false },
    { PAL.red, "player", true },
    { PAL.green, "lastHeal", false },
    { PAL.yellow, "lastOutdoor", false },
  }
  for _, item in ipairs(legend) do
    local box = 10 * s
    if item[3] then
      Theme.col(item[1], 1)
      love.graphics.rectangle("fill", lx, ly + 2 * s, box, box)
    else
      Theme.stroke(lx, ly + 2 * s, box, box, 0, item[1], 1, 1.5 * s)
    end
    Kit.text("tiny", item[2], lx + box + 6 * s, ly, PAL.muted)
    lx = lx + box + 6 * s + Kit.textWidth("tiny", item[2]) + 16 * s
  end
  Kit.textRight("mono", S.mapClickCell
      and ("selected (%d,%d)"):format(S.mapClickCell.cx, S.mapClickCell.cy)
      or "click a cell to select it",
    vx0 + vinner, ly, PAL.caption)

  -- ------------------------------------------------------ spawn inspector
  local sx0 = viewX + viewW + gap
  Kit.card(sx0, y, sideW, h)
  Kit.caption(sx0 + pad, y + pad, "SPAWN POINTS")
  local sTop = y + pad + Kit.textHeight("caption") + 12 * s
  local sInner = sideW - 2 * pad
  local player = S.save.player
  local out = S.save.lastOutdoor
  local heal = S.save.lastHeal
  local spawns = {
    { key = "PLAYER", color = PAL.red,
      value = ("%s (%d,%d)"):format(player.map, player.x, player.y),
      set = function() Ops.setPlayerHere(S) end },
    { key = "LAST HEAL", color = PAL.green,
      value = heal and ("%s (%d,%d)"):format(heal.map, heal.x, heal.y) or "unset",
      set = function() Ops.setLastHeal(S) end },
    { key = "LAST OUTDOOR", color = PAL.yellow,
      value = out and ("%s (%d,%d)"):format(out.id, out.x, out.y) or "unset",
      set = function() Ops.setLastOutdoor(S, map) end },
  }
  local spawnH = 62 * s
  for i, sp in ipairs(spawns) do
    local ry = sTop + (i - 1) * (spawnH + 8 * s)
    Theme.row(sx0 + pad, ry, sInner, spawnH, 10 * s, 0.6)
    Kit.text("tiny", sp.key, sx0 + pad + 12 * s, ry + 11 * s, sp.color)
    local setW = 70 * s
    if Kit.button(sx0 + pad + sInner - 12 * s - setW, ry + 8 * s, setW, 26 * s,
        "Set here", { kind = "accent", font = "tiny", radius = 7 * s,
        enabled = S.mapClickCell ~= nil }) then
      sp.set()
    end
    Kit.text("mono", Kit.ellipsize("mono", sp.value, sInner - 24 * s),
      sx0 + pad + 12 * s, ry + spawnH - 10 * s - Kit.textHeight("mono"), PAL.muted)
  end

  local noteY = sTop + 3 * (spawnH + 8 * s) + 6 * s
  Kit.textCenter("tiny",
    "Click a cell first. Warp cells follow the warp instead of selecting. " ..
    "Arrow keys / WASD pan, the wheel zooms.",
    sx0 + pad, noteY, sInner, PAL.caption)
end

return MapBrowser
