-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The map editor's manual, in the map editor.
--
-- WHY THE TEXT LIVES IN A DATA TABLE AND NOT IN THE DRAWING CODE.
--
-- There are two places a control has to be explained: in the editor, where
-- somebody is stuck right now, and in the repository, where somebody is
-- deciding whether to try it at all. Written twice they drift, and a manual
-- that is wrong about a key is worse than no manual -- it costs the reader the
-- time they spend trusting it. So `Help.SECTIONS` is the only copy;
-- `scripts/build_map_editor_readme.lua` flattens it to docs/MAP_EDITOR.md, and
-- tests/map_editor_help_test.lua fails if the committed markdown is not what
-- that script produces.
--
-- WHAT COUNTS AS A ROW. One row is one thing the reader can DO and the
-- shortest true statement of what happens. Rows that describe the editor's
-- opinion of itself belong in the section blurb; rows that name a key must
-- name the key exactly as the code reads it, because that is the string the
-- reader will be looking for.
--
-- OVER THE WHOLE WINDOW, painted after the frame, for the reason every other
-- modal here is: Kit has no z-order, so "on top" and "drawn last" are the same
-- sentence.

local okKit, KitModule = pcall(require, "Kit")
if not okKit then KitModule = nil end

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, green = { 120, 210, 130 },
  caption = { 160, 175, 205 }, text = { 226, 232, 245 },
  heading = { 226, 232, 245 },
}

local Help = {}

Help.TITLE = "MAP EDITOR - CONTROLS & FEATURES"

-- The manual. Order is the order a new reader meets these things: the map
-- first, because it is what is in front of them; sharing last, because it is
-- what they do once the work is done.
Help.SECTIONS = {
  {
    id = "map",
    title = "MOVING AROUND THE MAP",
    blurb = "The map is always on screen -- the tools open in a drawer beside "
      .. "it rather than replacing it. Everything below works in the flat 2D "
      .. "view; the 3D view has its own section.",
    rows = {
      { "left-drag", "pan the map" },
      { "right-drag  /  middle-drag", "pan the map without touching the selection" },
      { "mouse wheel", "zoom in and out" },
      { "W A S D  or  arrow keys", "pan the map by one step" },
      { "click a cell", "select it -- every tool acts on the selection" },
      { "shift-click", "add that cell to the selection" },
      { "ctrl-click  (cmd-click)", "select every cell on the map like that one" },
      { "double-click a warp", "follow it to the map it leads to" },
      { "click the viewport", "drop the text cursor, so W A S D pan again "
        .. "instead of typing into the last box you used" },
      { "escape", "clear the selection and put down anything you are holding" },
    },
  },
  {
    id = "view",
    title = "THE 3D VIEW",
    blurb = "The 3D button swaps the flat map for the voxel world the 3D mods "
      .. "draw. It is the same map and the same selection -- only the camera "
      .. "changes.",
    rows = {
      { "3D  /  2D", "swap between the voxel world and the flat map" },
      { "W A S D", "fly the camera along the ground" },
      { "Q  /  E", "fly down and up" },
      { "hold shift  /  hold alt", "fly fast  /  fly slowly, for placing the camera exactly" },
      { "left-drag", "orbit" },
      { "right-drag  /  middle-drag  /  shift-left-drag", "pan" },
      { "mouse wheel", "camera distance" },
      { "left  /  right arrow", "turn the camera" },
      { "up  /  down arrow", "raise and lower the camera angle" },
      { "F", "frame the selected cell" },
      { "home", "frame the whole map" },
      { "5", "switch between perspective and orthographic" },
      { "7  /  1  /  3  /  0", "top, front, side and user views" },
      { "G", "show or hide the grid" },
      { "F3  (or ctrl-D)", "show the diagnostics overlay" },
      { "PERSP / ORTHO, shading buttons", "the same two settings from the header" },
    },
  },
  {
    id = "layers",
    title = "WHAT THE MAP SHOWS",
    blurb = "The toggles under the map decide what is drawn over it. They "
      .. "change nothing in the map itself -- turning WARPS off does not "
      .. "remove a door, it stops drawing the marker.",
    rows = {
      { "WARPS", "show the doors, stairs and cave mouths" },
      { "NPCs", "show the people and items standing on the map" },
      { "EDITS", "show which cells you have changed" },
      { "GRID", "show the cell grid" },
      { "WORLD", "draw the neighbouring maps around this one, in place, so a "
        .. "seam can be judged against what is actually on the other side" },
      { "the region chips", "every region in the import. Johto and Kanto are "
        .. "separate regions because they touch only through indoor maps; "
        .. "Gen 1 has Kanto and its islands; a romhack has whatever it has. "
        .. "The view opens on the region holding your map" },
      { "the order they sit in", "the cartridge's own: regions run left to "
        .. "right by their first town-map landmark, so Johto is left of "
        .. "Kanto. Islands of one or two maps -- a map pack's two rooms, a "
        .. "pair you joined while trying something out -- go to the END, so "
        .. "they cannot stand between two real regions" },
      { "right-drag  /  middle-drag", "pan the world view" },
      { "clicking a map", "opens it" },
      { "a seam that drifts a block", "is normal. Gen 2's Kanto has loops "
        .. "that do not close -- Celadon to Route 14 the long way lands one "
        .. "block from the short way -- and the game never draws two branches "
        .. "at once, so it never has to agree with itself. Nothing to fix" },
      { "the gaps between regions", "are not geography. Inside a region every "
        .. "offset is the engine's own; between two regions the cartridge "
        .. "never places them in one space, so they are packed side by side "
        .. "to be looked at" },
      { "BACK TO MAP", "leave the world view" },
    },
  },
  {
    id = "tools",
    title = "THE TOOL DRAWER",
    blurb = "Seven tools, each opening in a drawer over one side of the map. "
      .. "Opening the tool that is already open closes it, and escape closes "
      .. "whichever is open.",
    rows = {
      { "WARPS", "doors, stairs and cave mouths; make new maps" },
      { "NPCs & ITEMS", "people, items, trainers and their teams" },
      { "SCRIPTS", "what an object does when you talk to it" },
      { "VOXELS", "per-cell height and shape for the 3D mods" },
      { "WILDS", "what lives in the grass, the water and on a hook" },
      { "TILES", "paint the ground itself, block by block" },
      { "WALKABLE", "where the player can and cannot go, and see it" },
    },
  },
  {
    id = "paint",
    title = "PAINTING TILES",
    blurb = "Open TILES and pick a block. While a block is picked the left "
      .. "button paints instead of selecting; the other two buttons still pan, "
      .. "so getting around never stops working mid-stroke.",
    rows = {
      { "click a cell", "lay the picked block there" },
      { "left-drag", "lay a stroke of blocks across every cell it crosses" },
      { "ctrl-click", "select every cell like that one, then paint the lot" },
      { "the big tile view", "the picked tile, drawn large in the drawer, so "
        .. "individual pixels can be aimed at" },
      { "wheel over the big tile", "zoom it, 2x to 160x, around the pointer" },
      { "right-drag  /  middle-drag over it", "pan the zoomed tile" },
      { "FIT", "put the zoom and the pan back" },
    },
  },
  {
    id = "npcs",
    title = "NPCs, TRAINERS AND TEXT",
    blurb = "An NPC is a sprite, a place to stand, a way to face and something "
      .. "to say. A trainer is all of that plus a team and the distance at "
      .. "which they notice you.",
    rows = {
      { "NEW NPC", "drop a person beside the selected cell" },
      { "facing", "which way they stand, and which way they turn to face you "
        .. "-- the map and the 3D view redraw them facing that way as soon as "
        .. "you press it" },
      { "movement", "still, wandering, or a fixed path" },
      { "text", "what they say -- typed in the box, shown a page at a time "
        .. "in game, with A to advance" },
      { "sprite import", "a PNG of the right size and palette; the disclaimer "
        .. "beside the button says what will and will not load" },
      { "Pokemon sprites", "every species has an overworld sheet -- search the "
        .. "sprite list by name (\"lugia\", \"suicune\") and it is there, "
        .. "listed as the species with its SPRITE_MON_nnn id beside it" },
      { "WILD", "give the NPC a species and it becomes a wild encounter: "
        .. "talking to it says its TEXT, then opens the battle, and beating "
        .. "it removes it for good -- the same mechanism the cartridge stands "
        .. "Ho-Oh and Suicune on" },
      { "LEVEL", "what level that wild Pokemon is; it always has one" },
      { "TRAINER", "make them a trainer -- the party editor and the sight "
        .. "settings appear once they are one" },
      { "party editor", "up to six Pokemon, each with a level, four moves and "
        .. "its stats; cartridge trainers open with their real team in it" },
      { "sight range", "how many blocks ahead they spot the player and start "
        .. "the battle; the cartridge's own value is shown where there is one" },
    },
  },
  {
    id = "events",
    title = "EVENTS AND FLAGS",
    blurb = "EVENTS in the title bar opens the map's events -- the ones you "
      .. "wrote and the ones the cartridge shipped, in one list.",
    rows = {
      { "the left-hand list", "every event on this map; cartridge events are "
        .. "selectable, viewable and editable, not just the new ones" },
      { "WHAT HAPPENS", "the beats the event plays, in order" },
      { "WHEN", "the flags that decide whether it runs, by name rather than "
        .. "by number" },
      { "TAKE OVER", "adopt a cartridge event so your edits replace it" },
      { "a flag's watchers", "everything on every map that reads that flag -- "
        .. "objects that hide, doors that open, trainers that stop appearing" },
    },
  },
  {
    id = "voxels",
    title = "VOXELS AND HEIGHT",
    blurb = "Height is per cell, and can be cut finer than a cell. The grain "
      .. "chips decide how fine. The finest is a sculpting tool and is costly; "
      .. "most maps never need it.",
    rows = {
      { "16  /  8  /  4  /  2  /  1", "the grain, in pixels: a whole cell, a "
        .. "tile, then 4, 16 and 64 heights per tile" },
      { "click a square", "select it" },
      { "shift-click", "add it to the selection" },
      { "arrow keys", "pan the cell grid" },
      { "E", "swap between painting height and erasing it" },
      { "SHOW THE TILE BIG", "put the selected tile in the drawer, large, "
        .. "instead of the cell grid" },
      { "CELL GRID", "go back to the grid" },
      { "BUILDING / ROOF OVER n CELLS", "select a building's footprint and "
        .. "this raises its walls and lays a roof on the top row. The voxel "
        .. "path can only raise what the DRAWING says is there, and some "
        .. "buildings have no roof to read -- Route 23's league gate runs off "
        .. "the top of its own map -- so those come out flat-topped until an "
        .. "author says otherwise" },
      { "WALLS / ROOF + / ROWS", "the wall height, how far the roof sits "
        .. "above it, and how many rows of the selection are roof" },
      { "the voxel source button", "which installed mod's heights are being "
        .. "edited -- two mods can pin the same tile to different shapes" },
    },
  },
  {
    id = "typing",
    title = "TYPING",
    blurb = "Every text box in the editor is the same widget, so these work "
      .. "everywhere -- the dialogue box, the map filter, a map's name.",
    rows = {
      { "hold backspace", "keeps deleting rather than deleting one character" },
      { "click and drag", "select part of the text" },
      { "ctrl-A  /  ctrl-C  /  ctrl-X  /  ctrl-V", "select all, copy, cut, paste" },
      { "enter", "commit and leave the box" },
      { "escape", "leave the box without committing" },
      { "click the map", "leave the box, so the letter keys go back to panning" },
    },
  },
  {
    id = "work",
    title = "KEEPING AND UNDOING WORK",
    blurb = "Edits live in an edit store beside the save, not in the "
      .. "cartridge. Nothing you do here writes to the ROM.",
    rows = {
      { "SAVE EDITS  (ctrl-S)", "write the edits; the button is lit only while "
        .. "there is something unsaved" },
      { "ctrl-Z", "undo" },
      { "ctrl-shift-Z", "redo" },
      { "RESET MAP", "put this map back as the cartridge has it -- press once "
        .. "to arm, again to confirm" },
      { "Close", "leave the editor; asks once if there are unsaved edits" },
      { "?", "open this help" },
    },
  },
  {
    id = "share",
    title = "SHARING WHAT YOU MADE",
    blurb = "An export is a content mod, not a copy of the edit store. A map "
      .. "that borrows art from another cartridge says so, and the person "
      .. "installing it is told which games they need.",
    rows = {
      { "EXPORT", "write the edits out as an installable .zip map pack" },
      { "IMPORT", "install a map pack somebody else exported" },
      { "required games", "an export declares every cartridge its maps borrow "
        .. "from, and the import dialog says, per game, whether it is already "
        .. "imported or still has to be" },
      { "ASSETS", "the library of pieces you have cut out of maps, reusable on "
        .. "any map in the project" },
    },
  },
}

function Help.isOpen(S)
  return S ~= nil and S.helpOpen == true
end

function Help.open(S, sectionId)
  if not S then return false end
  S.helpOpen = true
  S.helpSection = sectionId or S.helpSection or Help.SECTIONS[1].id
  S.helpScroll = 0
  return true
end

function Help.toggle(S)
  if not S then return false end
  if S.helpOpen then Help.close(S) return false end
  return Help.open(S)
end

function Help.close(S)
  if S then
    S.helpOpen = nil
    if KitModule and KitModule.forgetModal then
      KitModule.forgetModal("help-ask")
    end
  end
end

-- The section on screen, resolved rather than assumed: `S.helpSection` is a
-- plain string that can outlive a rename or arrive from a caller that made it
-- up, and a nil here would draw an empty right-hand pane that reads as the
-- help being broken rather than as a bad id.
function Help.section(S)
  local want = S and S.helpSection
  for _, sec in ipairs(Help.SECTIONS) do
    if sec.id == want then return sec end
  end
  return Help.SECTIONS[1]
end

-- How tall the chosen section's body is, in rows -- measured so the scrollbar
-- knows the whole length rather than the part that happens to fit.
function Help.rowCount(sec)
  return #((sec and sec.rows) or {})
end

function Help.draw(S, Kit)
  if not Help.isOpen(S) then return false end

  local s = Kit.scale
  local winW, winH = love.graphics.getDimensions()
  local pad = 16 * s

  local pw = math.max(420 * s, math.min(960 * s, winW - 40 * s))
  local ph = math.max(300 * s, math.min(720 * s, winH - 40 * s))
  local x = math.floor((winW - pw) / 2)
  local y = math.floor((winH - ph) / 2)

  -- The guard runs before any widget of this dialog is drawn: Kit.tapAway
  -- swallows the click on the frame the dialog goes up, and it can only do
  -- that for widgets drawn after it.
  local tappedAway = Kit.tapAway("help-ask", x, y, pw, ph)

  love.graphics.setColor(0.03, 0.04, 0.11, 0.72)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", x, y, pw, ph, 10 * s, 10 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(x, y, pw, ph)

  local headH = 34 * s
  Kit.caption(x + pad, y + pad, Help.TITLE)
  if Kit.button(x + pw - pad - 84 * s, y + pad - 8 * s, 84 * s, headH, "CLOSE",
                { font = "small" }) then
    Help.close(S)
    return true
  end

  local bodyY = y + pad + Kit.textHeight("caption") + 12 * s
  local bodyH = ph - (bodyY - y) - pad

  -- ------------------------------------------------ left: the section list
  local listW = math.min(240 * s, pw * 0.32)
  local rowH = 30 * s
  local ly = bodyY
  for _, sec in ipairs(Help.SECTIONS) do
    local on = (Help.section(S).id == sec.id)
    if Kit.press(x + pad, ly, listW - 8 * s, rowH - 4 * s) then
      S.helpSection = sec.id
      S.helpScroll = 0
    end
    Kit.row(x + pad, ly, listW - 8 * s, rowH - 4 * s, on)
    Kit.text("small", Kit.ellipsize("small", sec.title, listW - 26 * s),
             x + pad + 9 * s, ly + 6 * s, on and PAL.text or PAL.muted)
    ly = ly + rowH
  end

  -- ------------------------------------------------ right: the chosen one
  local sec = Help.section(S)
  local dx = x + pad + listW
  local dw = pw - pad - (dx - x) - pad
  local lineH = 15 * s

  Kit.text("body", sec.title, dx, bodyY, PAL.heading)
  local by = bodyY + Kit.textHeight("body") + 6 * s
  for _, line in ipairs(Kit.wrap("small", sec.blurb or "", dw)) do
    Kit.text("small", line, dx, by, PAL.muted)
    by = by + lineH
  end
  by = by + 10 * s

  -- THE ROWS SCROLL, THE HEADING DOES NOT. A section can be longer than the
  -- card on a small window, and a reader who has scrolled halfway down a list
  -- of keys with no title over it does not know which list they are in.
  local viewY = by
  local viewH = math.max(rowH, (bodyY + bodyH) - viewY)

  -- Measured first, so the scrollbar knows the whole length: a wrapped
  -- description is two rows tall and a fixed row height would cut it off.
  local keyW = math.min(220 * s, dw * 0.42)
  local textW = dw - keyW - 12 * s - 10 * s
  local heights, total = {}, 0
  for i, row in ipairs(sec.rows or {}) do
    local lines = math.max(1, #Kit.wrap("small", tostring(row[2] or ""), textW))
    heights[i] = math.max(22 * s, lines * lineH + 8 * s)
    total = total + heights[i]
  end

  local maxScroll = math.max(0, total - viewH)
  S.helpScroll = math.max(0, math.min(S.helpScroll or 0, maxScroll))

  Kit.pushClip(dx, viewY, dw, viewH)
  local ry = viewY - (S.helpScroll or 0)
  for i, row in ipairs(sec.rows or {}) do
    local h = heights[i]
    if ry + h > viewY and ry < viewY + viewH then
      Kit.text("small", Kit.ellipsize("small", tostring(row[1] or ""), keyW),
               dx, ry + 2 * s, PAL.yellow)
      local ty = ry + 2 * s
      for _, line in ipairs(Kit.wrap("small", tostring(row[2] or ""), textW)) do
        Kit.text("small", line, dx + keyW + 12 * s, ty, PAL.text)
        ty = ty + lineH
      end
    end
    ry = ry + h
  end
  Kit.popClip()

  -- A HAND-DRAWN TRACK, not Kit.scroll: that helper CONSUMES the wheel and
  -- returns a row offset, and this pane already takes the wheel through
  -- Help.wheelmoved in pixels. Calling it here would eat the notch twice and
  -- the list would jump two steps for one turn.
  if maxScroll > 0 then
    local trackX, trackW = dx + dw - 4 * s, 3 * s
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.rectangle("fill", trackX, viewY, trackW, viewH)
    local knobH = math.max(20 * s, viewH * (viewH / total))
    local knobY = viewY + (viewH - knobH) * ((S.helpScroll or 0) / maxScroll)
    love.graphics.setColor(1, 1, 1, 0.28)
    love.graphics.rectangle("fill", trackX, knobY, trackW, knobH)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if tappedAway then Help.close(S) end
  return true
end

function Help.wheelmoved(S, dy)
  if not Help.isOpen(S) then return false end
  S.helpScroll = math.max(0, (S.helpScroll or 0) - (dy or 0) * 40)
  return true
end

function Help.keypressed(S, key)
  if not Help.isOpen(S) then return false end
  if key == "escape" or key == "return" or key == "kpenter" then
    Help.close(S)
    return true
  end
  -- UP AND DOWN WALK THE SECTIONS, because the list is the thing with a
  -- position in it and the body follows from that.
  local step = (key == "down" and 1) or (key == "up" and -1) or nil
  if step then
    local cur = Help.section(S)
    for i, sec in ipairs(Help.SECTIONS) do
      if sec.id == cur.id then
        local nxt = Help.SECTIONS[i + step]
        if nxt then S.helpSection = nxt.id; S.helpScroll = 0 end
        break
      end
    end
    return true
  end
  if key == "pagedown" then S.helpScroll = (S.helpScroll or 0) + 200 return true end
  if key == "pageup" then
    S.helpScroll = math.max(0, (S.helpScroll or 0) - 200)
    return true
  end
  return true      -- a modal swallows the rest rather than letting it through
end

return Help
