-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- docs/MAP_EDITOR.md, out of the help panel's own table.
--
-- THE PROBLEM THIS EXISTS FOR is the one LICENSE.md and LICENSE have: two
-- copies of the same statement, maintained by hand, disagree -- and a manual
-- that is wrong about a key costs the reader more than no manual, because
-- they spend time trusting it. So tools/map-editor/panels/Help.lua holds the
-- only copy of the text and this flattens it.
--
--   texlua scripts/build_map_editor_readme.lua          -- write the file
--   texlua scripts/build_map_editor_readme.lua --check  -- fail if stale
--
-- Deliberately runs under plain Lua: Help.lua's requires are all pcall'd, so
-- it loads with no love, no Kit and no Theme, and this script never has to
-- start a window to read a table of strings.

package.path = "./?.lua;./?/init.lua;./tools/save-editor/?.lua;" .. package.path

local Help = require("tools.map-editor.panels.Help")

local OUT = "docs/MAP_EDITOR.md"

local HEAD = [[
# Gen2Recomped Map Editor

Everything the map editor can do, and every control that does it.

The same text is in the editor: press **?** in the title bar. That panel and
this file are generated from one table
(`tools/map-editor/panels/Help.lua`), so they cannot disagree -- if you are
reading a key here, that is the key the code reads.

## Opening it

The map editor is a mode of the same shell the save editor runs in, so it
inherits that window's gamepad cursor, on-screen keyboard and DPI layout
rather than reimplementing them. Open it from the launcher; the title bar
reads **MAP EDITOR** and the badge reads **ME**.

Nothing in this editor writes to a ROM. Edits live in an edit store beside the
save, and an export is a separate content mod.

]]

local FOOT = [[

## Where the edits go

* **Saving** writes the edit store. The game reads it on load and lays it over
  the cartridge's own maps, and it is laid over again after mods merge, so a
  map pack cannot quietly overwrite your own work.
* **Exporting** writes an installable `.zip`. Maps that borrow art from
  another cartridge are exported *by reference*, so the pack carries no ROM
  data -- which is why it declares the games it needs and why the import
  dialog checks for them.
* **Resetting** a map discards this map's edits only, and asks twice.

## If a control does nothing

Two causes account for most of it:

* **A text box still has focus.** The letter keys go to the box, not the map.
  Click the map, or press escape.
* **The build has no `tools/map-editor`.** The editor's panels are loaded
  through `pcall`, so a packaged build missing them loses the buttons rather
  than failing to start. `scripts/pack_love.sh` ships the directory; a
  hand-made payload may not.
]]

-- One section, as markdown. The key column is code-spanned because most of
-- these ARE keys, and the ones that are button names read correctly that way
-- too -- they are things to press either way.
local function sectionMd(sec)
  local out = { "## " .. sec.title, "" }
  if sec.blurb and sec.blurb ~= "" then
    out[#out + 1] = sec.blurb
    out[#out + 1] = ""
  end
  out[#out + 1] = "| control | what it does |"
  out[#out + 1] = "| --- | --- |"
  for _, row in ipairs(sec.rows or {}) do
    out[#out + 1] = string.format("| `%s` | %s |", tostring(row[1]),
                                  tostring(row[2]))
  end
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local function render()
  local parts = { HEAD }
  -- A CONTENTS LIST, because eleven sections is past the point where a reader
  -- scrolls looking for the one they want.
  parts[#parts + 1] = "## Contents\n"
  for _, sec in ipairs(Help.SECTIONS) do
    local anchor = sec.title:lower():gsub("[^%w%s%-]", ""):gsub("%s+", "-")
    parts[#parts + 1] = string.format("* [%s](#%s)", sec.title, anchor)
  end
  parts[#parts + 1] = ""
  for _, sec in ipairs(Help.SECTIONS) do
    parts[#parts + 1] = sectionMd(sec)
  end
  parts[#parts + 1] = FOOT
  return (table.concat(parts, "\n"):gsub("\n\n\n+", "\n\n"))
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  return src
end

local want = render()
local check = false
for _, a in ipairs(arg or {}) do if a == "--check" then check = true end end

if check then
  local have = read(OUT)
  if have == want then
    print("map editor readme: up to date")
    os.exit(0)
  end
  io.stderr:write(OUT .. " is stale -- run: texlua "
    .. "scripts/build_map_editor_readme.lua\n")
  os.exit(1)
end

local f = assert(io.open(OUT, "w"))
f:write(want)
f:close()
print("wrote " .. OUT)
