-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The map editor's tools, as a drawer over the map instead of tabs beside it.
--
-- WHY THIS REPLACED THE TABS. Every one of these tools works ON the map: the
-- warp editor puts a door at the selected cell, the NPC editor drops a person
-- next to it, the voxel editor shapes the ground under it. A tab takes the map
-- off the screen to show you the tool for changing it, so you edit a
-- coordinate, switch back to see what happened, switch again to adjust -- and
-- the one thing you actually need in front of you is the one thing the tab
-- hides. A drawer keeps the map visible and puts the tool beside it, which is
-- what every other level editor does and for this reason.
--
-- MODAL IS LITERAL, and the same shape SpeciesPicker uses because Kit has no
-- z-order. App raises `Kit.blockClicks` over the chrome and the panel while
-- this is open and lowers it only for this layer, so nothing underneath can
-- take the same tap. Getting that wrong does not look like a bug in the
-- drawer: it looks like the map randomly repainting itself when you click a
-- button that happens to sit over a cell.
--
-- The map keeps drawing underneath, unshielded and unscrimmed on the side the
-- drawer does not cover, because seeing the change land is the whole point.

local Theme = require("Theme")
local PAL = Theme.PAL

local Sidebar = {}

-- The tools, and what each is for. `id` is the panel key App resolves, so the
-- set here is the set that used to be tabs -- nothing new had to be written to
-- move them, which is the test of whether this is a presentation change or a
-- rewrite.
Sidebar.TOOLS = {
  { id = "warps",   title = "WARPS",
    blurb = "doors, stairs and cave mouths; make new maps" },
  { id = "objects", title = "NPCs & ITEMS",
    blurb = "people, items, trainers and their teams" },
  { id = "scripts", title = "SCRIPTS",
    blurb = "what an object does when you talk to it" },
  { id = "voxels",  title = "VOXELS",
    blurb = "per-cell height and shape for the 3D mods" },
  { id = "wilds",   title = "WILDS",
    blurb = "what lives in the grass, the water and on a hook" },
  { id = "tiles",   title = "TILES",
    blurb = "paint the ground itself, block by block" },
  { id = "collision", title = "WALKABLE",
    blurb = "where the player can and cannot go, and see it" },
}

function Sidebar.toolFor(id)
  for _, t in ipairs(Sidebar.TOOLS) do
    if t.id == id then return t end
  end
  return nil
end

function Sidebar.isOpen(S)
  return S ~= nil and S.sidebar ~= nil
end

function Sidebar.openId(S)
  return S and S.sidebar and S.sidebar.id or nil
end

-- `opened` is consumed on the first frame the drawer is drawn -- see the note
-- in `draw`. Opening the same tool twice is a close, so a tool button is a
-- toggle rather than a no-op the second time.
function Sidebar.open(S, id)
  if not S then return false end
  if S.sidebar and S.sidebar.id == id then
    S.sidebar = nil
    return false
  end
  S.sidebar = { id = id, opened = true, scroll = 0 }
  return true
end

function Sidebar.close(S)
  if S then S.sidebar = nil end
end

-- How wide the drawer is, in DPI units. Wide enough for the widest of these
-- panels -- the voxel tab carries a brush column AND a cell grid -- and capped
-- so the map keeps most of the window on a small screen. On a narrow window it
-- takes what is left rather than overflowing, because a control drawn off the
-- edge cannot be reached at all.
function Sidebar.width(Kit, width)
  local s = Kit.scale
  return math.max(320 * s, math.min(720 * s, width * 0.46))
end

-- The map's own room while a drawer is open, so the panel underneath can lay
-- itself out around it rather than being covered.
function Sidebar.mapWidth(S, Kit, width)
  if not Sidebar.isOpen(S) then return width end
  return math.max(200 * Kit.scale, width - Sidebar.width(Kit, width))
end

-- Draw the drawer over everything, and dispatch its body to the panel that
-- used to own the tab.
--
-- `panels` is App's own PANELS table: this file deliberately does not require
-- any of them. They are optional -- a checkout without tools/map-editor loads
-- the save editor with no map mode at all -- and a require here would make
-- this file the one that breaks instead.
function Sidebar.draw(S, Kit, panels, x, y, width, height)
  local sb = S and S.sidebar
  if not sb then return false end
  local panel = panels and panels[sb.id]
  local s = Kit.scale

  -- THE CLICK THAT OPENED THE DRAWER IS STILL THIS FRAME'S CLICK. The tool
  -- button dispatches earlier in App.draw than this overlay does, so without
  -- swallowing it the "tap outside to close" test below would read it as a tap
  -- on the map and shut the drawer in the frame it went up. App re-raises the
  -- shield at the top of the next frame, so leaving it up here is safe.
  if sb.opened then
    sb.opened = nil
    Kit.blockClicks = true
  end

  local w = Sidebar.width(Kit, width)
  local dx = x + width - w

  -- A TAP ON THE MAP IS NOT A CLOSE.
  --
  -- It was, and that was wrong the moment a tool acted on the map: the tile
  -- painter's clicks land there, and so do the voxel brush's and the warp
  -- editor's "put it here" -- so a click on the map that shut the drawer meant
  -- the drawer could only be open while you were not using what it was for.
  -- The X and Escape close it, which is what closes everything else here.

  -- AN OPAQUE PLATE FIRST. `Kit.card` is a card in a COLUMN -- it paints a
  -- tinted gradient at eight per cent over whatever the panel's background
  -- already is, which is right when there is a background behind it and wrong
  -- when there is a map. Drawn straight onto the world the drawer was a ghost:
  -- its labels and the map's tiles and the tools column underneath all legible
  -- at once and none of them readable. A modal has to stop the light.
  Theme.col(PAL.bgBot, 1)
  love.graphics.rectangle("fill", dx, y, w, height)
  Kit.card(dx, y, w, height)
  -- A hairline down the inner edge, so the drawer reads as over the map rather
  -- than as another column of it.
  Theme.col(PAL.cardBorder, 0.5)
  love.graphics.rectangle("fill", dx, y, 1 * s, height)

  local pad = 16 * s
  local tool = Sidebar.toolFor(sb.id)
  Kit.caption(dx + pad, y + pad, tool and tool.title or string.upper(tostring(sb.id)))
  local closeW = 30 * s
  if Kit.button(dx + w - pad - closeW, y + pad - 4 * s, closeW, 26 * s, "x",
                { font = "small", radius = 7 * s }) then
    Sidebar.close(S)
    return true
  end
  local hy = y + pad + Kit.textHeight("caption") + 4 * s
  if tool and tool.blurb then
    Kit.text("small", Kit.ellipsize("small", tool.blurb, w - 2 * pad - closeW),
             dx + pad, hy)
    hy = hy + 16 * s
  end

  -- THE OTHER TOOLS, as a row of chips along the top of the drawer.
  --
  -- Moving between them was the one thing tabs were genuinely good at, and
  -- losing it would trade one annoyance for another: a warp needs an NPC
  -- beside it and the NPC needs a script, and closing the drawer to reopen it
  -- somewhere else is three taps for what was one.
  local chipH = 26 * s
  local n = #Sidebar.TOOLS
  local chipW = (w - 2 * pad - (n - 1) * 6 * s) / n
  for i, t in ipairs(Sidebar.TOOLS) do
    if panels and panels[t.id] then
      local cx = dx + pad + (i - 1) * (chipW + 6 * s)
      if Kit.chip(cx, hy, chipW, chipH, t.title, t.id == sb.id) then
        -- a new tool starts at the top of itself, not at wherever the last
        -- one happened to be scrolled to
        S.sidebar = { id = t.id, scroll = 0 }
      end
    end
  end
  hy = hy + chipH + 10 * s

  local bodyH = (y + height - pad) - hy

  -- THE BODY SCROLLS.
  --
  -- These panels were written for a full tab -- most of a window tall -- and a
  -- drawer is shorter. The NPC editor is the worst of them: its fields flow
  -- down the column while SAVE, REVERT and DELETE are anchored to the bottom,
  -- so in a short drawer the flow ran straight into them and TRAINER printed
  -- through DELETE. Text over a delete button is not a cosmetic problem.
  --
  -- SCROLLED BY MOVING THE RECTANGLE, not by translating the canvas. The panel
  -- is handed a y above the drawer and a height taller than it, and lays
  -- itself out from those exactly as it always has -- so its hit tests land on
  -- the same coordinates as its drawing, with no transform for the two to
  -- disagree about. A translate would move the pixels and leave Kit testing
  -- the mouse against where the control used to be.
  -- HOW TALL A PAGE THE PANEL GETS.
  --
  -- A constant was a guess, and the guess was wrong in both directions: too
  -- short for the NPC editor with a trainer roster open (SAVE, REVERT and
  -- DELETE flowed below the last field and off the end of the page, reachable
  -- by nothing), too tall for a warp with three fields.  So panels MEASURE
  -- themselves -- `Sidebar.reportHeight`, called at the end of a draw with the
  -- height that draw actually used -- and this is the floor for the first
  -- frame and for any panel that does not report.
  --
  -- ONE FRAME BEHIND, and that is fine: a panel lays itself out from the
  -- rectangle it is handed, so it cannot know its height until it has drawn
  -- one.  The page grows on the next frame and the rail appears with it.
  local VIRTUAL = math.max(780 * s, sb.measuredH or 0)
  local vh = math.max(bodyH, VIRTUAL)
  local maxScroll = math.max(0, vh - bodyH)
  sb.scroll = math.max(0, math.min(sb.scroll or 0, maxScroll))

  if panel and panel.draw then
    Kit.pushClip(dx, hy, w, bodyH)
    -- A CONTROL SCROLLED OUT OF SIGHT MUST BE DEAD. Clipping hides it and
    -- nothing more -- Kit hit-tests raw coordinates -- so a DELETE button
    -- scrolled off the bottom would still fire from where it used to be. The
    -- shield goes up whenever the pointer is not inside the body.
    local wasBlocked = Kit.blockClicks
    if not Kit.hit(dx, hy, w, bodyH) then Kit.blockClicks = true end
    -- The panel is handed the drawer's inside and nothing else. None of them
    -- needed changing to move here, which is the point: they were always
    -- "draw yourself into this rectangle", and a tab was only ever one choice
    -- of rectangle.
    panel.draw(S, Kit, dx + pad, hy - sb.scroll, w - 2 * pad, vh)
    Kit.blockClicks = wasBlocked
    Kit.popClip()

    -- A scroll rail, only when there is something to scroll to. Without it the
    -- fact that there is more below is something you find out by accident.
    if maxScroll > 0 then
      local railW = 4 * s
      local rx = dx + w - railW - 3 * s
      Theme.col(PAL.cardBorder, 0.18)
      love.graphics.rectangle("fill", rx, hy, railW, bodyH, railW, railW)
      local thumb = math.max(24 * s, bodyH * (bodyH / vh))
      local ty = hy + (bodyH - thumb) * (sb.scroll / maxScroll)
      Theme.col(PAL.cardBorder, 0.6)
      love.graphics.rectangle("fill", rx, ty, railW, thumb, railW, railW)
      love.graphics.setColor(1, 1, 1, 1)
    end
  else
    Kit.emptyBox(dx + pad, hy, w - 2 * pad, bodyH,
      "This tool is not in this build.")
  end
  sb.bodyRect = { hy, bodyH, maxScroll }
  return true
end

-- Wheel and keys go to the open drawer, not to the map behind it. Without this
-- the arrow keys pan the map while you are typing coordinates into the drawer,
-- which is the sort of thing that reads as the editor being possessed.
-- A panel says how tall it actually drew, in the same units it was handed.
--
-- Capped, because a panel whose layout depends on the height it is given can
-- feed its own growth back in -- an action row pinned to the foot of the page
-- reports a taller page, which moves the foot down again.  Panels report their
-- FLOWED height for that reason; the cap is the backstop for one that forgets.
function Sidebar.reportHeight(S, used)
  local sb = S and S.sidebar
  if not (sb and type(used) == "number" and used == used) then return false end
  sb.measuredH = math.max(0, math.min(used, 6000))
  return true
end

function Sidebar.wheelmoved(S, panels, dy)
  local sb = S and S.sidebar
  if not sb then return false end
  -- THE PANEL FIRST. A panel with its own list has somewhere for the notch to
  -- go and knows better than this file where; the drawer only scrolls what is
  -- left over. The voxel tab in particular has a class list, a profile popup
  -- and a cell grid, all of which want the wheel before the drawer does.
  --
  -- A PANEL THAT DECLINES THE NOTCH GETS THE DRAWER TO SCROLL INSTEAD.
  --
  -- Offering it first was right; taking "it has a wheelmoved" as "it consumed
  -- the wheel" was not.  The voxel tool's handler panned its grid whatever the
  -- pointer was over, so on that tool the drawer could not scroll at all --
  -- and the drawer is shorter than the panel, so its lower controls were
  -- clipped away with no way to reach them.  A handler that returns false is
  -- saying the notch was not for it.
  local panel = panels and panels[sb.id]
  if panel and panel.wheelmoved then
    local ok, took = pcall(panel.wheelmoved, S, dy)
    -- nil from a handler that returns nothing still means "consumed", which is
    -- what every panel written before this meant by returning nothing at all.
    if not ok or took ~= false then return true end
  end
  local max = sb.bodyRect and sb.bodyRect[3] or 0
  sb.scroll = math.max(0, math.min((sb.scroll or 0) - (dy or 0) * 48, max))
  return true
end

function Sidebar.keypressed(S, panels, key)
  local sb = S and S.sidebar
  if not sb then return false end
  if key == "escape" then
    Sidebar.close(S)
    return true
  end
  local panel = panels and panels[sb.id]
  if panel and panel.keypressed then
    panel.keypressed(S, key)
    return true
  end
  return true
end

return Sidebar
