-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Where the player can and cannot go: paint it, and look at it.
--
-- WHY THIS IS ITS OWN TOOL AND NOT A MODE OF THE TILE PAINTER. They change
-- different things and only one of them is visible. The tile brush changes
-- what a cell LOOKS like; this changes what it DOES, and a map can be wrong in
-- either way while looking right in the other -- a fence you can walk through
-- draws perfectly. The whole reason to have this is to see the half you cannot
-- see, so it comes with its own overlay and it stays on while you work.
--
-- WHAT AN EDIT ACTUALLY DOES lives in MapCollision, and the short version is
-- that a collision class belongs to the TILESET, which thirty maps share --
-- so a per-cell edit mints a block rather than writing through to all of them.
-- Read that file's header before changing anything here.

local MapCollision = require("tools.map-editor.MapCollision")

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, caption = { 160, 175, 205 },
}

local Collision = {}

-- The three things a click can mean. WALL and FLOOR are the ones you reach
-- for; TOGGLE is for tidying a boundary where you would otherwise be switching
-- tools every second cell.
Collision.MODES = {
  { id = "wall",   label = "WALL",   blurb = "make the cell solid" },
  { id = "floor",  label = "FLOOR",  blurb = "make the cell walkable" },
  { id = "toggle", label = "SWAP",   blurb = "flip whatever is there" },
}

function Collision.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map first.")
    return
  end
  local pad = 16 * s
  local btnH = 28 * s

  Kit.caption(x, y, "WALKABLE - " .. tostring(S.mapId))
  local fy = y + Kit.textHeight("caption") + 6 * s

  -- THE OVERLAY IS ON BY DEFAULT WHILE THIS TOOL IS OPEN, because a tool for
  -- editing something invisible that starts with it invisible is a tool nobody
  -- can use. It is still a switch: the art underneath is what you are checking
  -- the collision AGAINST, and sometimes you need to see it clean.
  if S.collShow == nil then S.collShow = true end
  local half = (w - 6 * s) / 2
  if Kit.chip(x, fy, half, 24 * s, "SHOW WALLS", S.collShow) then
    S.collShow = not S.collShow
  end
  if Kit.chip(x + half + 6 * s, fy, half, 24 * s, "SHOW FLOOR",
              S.collShowOpen) then
    S.collShowOpen = not S.collShowOpen
  end
  fy = fy + 24 * s + 8 * s

  S.collMode = S.collMode or "wall"
  local mw = (w - 12 * s) / 3
  for i, m in ipairs(Collision.MODES) do
    if Kit.chip(x + (i - 1) * (mw + 6 * s), fy, mw, 26 * s, m.label,
                S.collMode == m.id) then
      S.collMode = m.id
    end
  end
  fy = fy + 26 * s + 4 * s
  for _, m in ipairs(Collision.MODES) do
    if m.id == S.collMode then
      Kit.text("small", m.blurb, x, fy, PAL.muted)
    end
  end
  fy = fy + 18 * s

  -- WHETHER THIS MAP HAS PER-CELL COLLISION AT ALL, said plainly and early.
  --
  -- An import whose tileset carries no walkable list falls back to "anything
  -- that is not the border block is walkable" -- that is what the GAME does,
  -- so it is what the overlay shows, and a per-cell edit there cannot mean
  -- anything. Finding that out by painting twenty cells that do not change is
  -- the worst possible way to learn it.
  local ts, def = MapCollision.tilesetOf(S)
  local hasClasses = MapCollision.hasClasses(S, def)
  if not hasClasses then
    Kit.text("small", Kit.ellipsize("small",
      "this tileset has no walkable list", w), x, fy, PAL.yellow)
    fy = fy + 15 * s
    Kit.text("small", Kit.ellipsize("small",
      "the game decides by border block, so the overlay is a guess and",
      w), x, fy, PAL.muted)
    fy = fy + 14 * s
    Kit.text("small", Kit.ellipsize("small",
      "painting a cell cannot change it", w), x, fy, PAL.muted)
    fy = fy + 18 * s
  end

  local open, blocked = MapCollision.tally(S)
  Kit.text("small", string.format("%d walkable  -  %d blocked", open, blocked),
           x, fy, PAL.muted)
  fy = fy + 18 * s

  -- WHAT IS UNDER THE CURSOR, which is how you find out what a class IS. The
  -- number means nothing on its own and everything next to the cell it came
  -- from.
  local at = S.pvCell
  if at then
    local cls, blockId, q = MapCollision.classAt(S, at.cx, at.cy)
    local walk = MapCollision.isWalkable(S, at.cx, at.cy)
    Kit.text("body", string.format("cell %d,%d", at.cx, at.cy), x, fy)
    fy = fy + 16 * s
    Kit.text("small", string.format("%s  -  class %s  -  block %s (q%d)",
             walk and "walkable" or "blocked",
             cls and string.format("0x%02X", cls) or "-",
             tostring(blockId or "-"), q or 0), x, fy,
             walk and PAL.muted or PAL.red)
    fy = fy + 20 * s

    if Kit.button(x, fy, w, btnH,
                  walk and "MAKE THIS CELL SOLID" or "MAKE THIS CELL WALKABLE",
                  { font = "small", kind = "accent" }) then
      local ok, why = MapCollision.set(S, at.cx, at.cy, not walk)
      S.collNotice = ok and "changed" or tostring(why)
    end
    fy = fy + btnH + 8 * s
  else
    Kit.text("small", "pick a cell on the map", x, fy, PAL.muted)
    fy = fy + 18 * s
  end

  -- THE CLASSES THIS TILESET USES, and which of them walk. This is the legend
  -- for every number above, and it is per tileset -- 0x00 is floor in most of
  -- them and there is no rule saying it must be.
  do
    local set = MapCollision.walkableSet(ts)
    local seen, list = {}, {}
    for _, cls in ipairs((ts and ts.collision) or {}) do
      if not seen[cls] then
        seen[cls] = true
        list[#list + 1] = cls
      end
    end
    table.sort(list)
    Kit.text("small", string.format("%d class%s in this tileset", #list,
             #list == 1 and "" or "es"), x, fy, PAL.muted)
    fy = fy + 16 * s
    local cw = 52 * s
    local perRow = math.max(1, math.floor(w / cw))
    for i, cls in ipairs(list) do
      if i > perRow * 4 then break end
      local col = (i - 1) % perRow
      local row = math.floor((i - 1) / perRow)
      local bx = x + col * cw
      local by = fy + row * 20 * s
      local walkable = set[cls] and true or false
      if walkable then
        love.graphics.setColor(0.30, 0.85, 0.45, 0.22)
      else
        love.graphics.setColor(0.95, 0.28, 0.32, 0.26)
      end
      love.graphics.rectangle("fill", bx, by, cw - 4 * s, 18 * s, 4 * s, 4 * s)
      love.graphics.setColor(1, 1, 1, 1)
      Kit.text("small", string.format("%02X", cls), bx + 6 * s, by + 3 * s)
    end
    fy = fy + math.min(4, math.ceil(#list / perRow)) * 20 * s + 6 * s
  end

  if S.collNotice then
    Kit.text("small", Kit.ellipsize("small", S.collNotice, w), x, fy,
             PAL.yellow)
  end
end

-- THE CLICK ON THE MAP, routed from Preview exactly as the tile painter's is.
-- Returns true when it took the click.
function Collision.paintAt(S, cx, cy)
  local mode = S.collMode or "wall"
  local ok, why
  if mode == "toggle" then
    ok, why = MapCollision.toggle(S, cx, cy)
  else
    ok, why = MapCollision.set(S, cx, cy, mode == "floor")
  end
  -- "already like that" is not an error to report on every cell of a drag; it
  -- is the ordinary case in the middle of a stroke.
  if not ok and why and not tostring(why):find("already") then
    S.collNotice = tostring(why)
  end
  return true
end

return Collision
