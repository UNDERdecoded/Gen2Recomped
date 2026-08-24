-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Bring a character sheet in from a PNG on disk.
--
-- WHAT A GEN 2 OVERWORLD SHEET IS, because every decision here follows from it:
-- a 16-pixel-wide column of 16x16 frames stacked vertically, six of them for a
-- walker (stand down, stand up, stand side, walk down, walk up, walk side) and
-- fewer for something that does not move. Right is the X-flip of left, which is
-- why there is no seventh frame and why a sheet drawn with one comes out with a
-- spare pose nothing ever shows. The 32x32 dolls (Snorlax, Lapras) are the one
-- exception and they carry `big`.
--
-- SpriteRenderer works all of that out from the image's dimensions, so this
-- file's real job is to REFUSE the sheets that would slice wrong -- and to say
-- why, at import time, rather than letting a 24-pixel-wide sheet through to be
-- discovered as a smear on the map an hour later.
--
-- THE PIXELS ARE COPIED, NOT LINKED. The path the picker returns is somewhere
-- on the reader's disk: a Downloads folder they will empty, a USB stick they
-- will unplug, a path with a drive letter that means nothing on the machine
-- they send the mod to. A sheet referenced from there works until it does not.
-- The bytes are written into the save directory beside the extended atlases,
-- which is the same place -- and the same reasoning -- as `MapEdits.extendAtlas`.

local MapEdits = require("tools.map-editor.MapEdits")

local SpriteImport = {}

-- Where imported sheets live, under the save directory. Mirrors
-- `editor/atlas/` -- one folder per kind of thing the editor produces, so a
-- reader poking around their save folder can tell what made what.
SpriteImport.DIR = "editor/sprites"

-- A sheet is 16 wide; anything else is not a Gen 2 overworld sprite. 32 is the
-- big-doll case and is allowed through as one.
local FRAME = 16
local BIG = 32

-- The most frames a sheet can carry. Six is a walker; the extractor writes at
-- most six for a person and one for a doll. A taller image is almost always a
-- sheet laid out in a grid (four columns of poses) rather than a column, and
-- accepting it would slice the first column and silently drop the rest.
SpriteImport.MAX_FRAMES = 6

-- WHAT A SHEET HAS TO BE, in the words the panel shows before you pick a file.
--
-- BUILT FROM THE SAME CONSTANTS `describe` VALIDATES AGAINST, and that is the
-- whole point of it being here rather than typed into the panel. A hand-written
-- caption saying "16 pixels wide" beside a validator that has moved on is worse
-- than no caption: the reader follows it, is refused, and now distrusts both.
--
-- Stated BEFORE the picker, too. Every one of these rules already produced a
-- clear refusal -- the messages in `describe` are good -- but a refusal arrives
-- after the reader has found their art, opened the picker and chosen, and by
-- then the useful moment (while they still had the image open in an editor) is
-- gone.
function SpriteImport.requirements()
  return {
    string.format("PNG, %d pixels wide", FRAME),
    string.format("frames are %dx%d, stacked in ONE column top to bottom",
                  FRAME, FRAME),
    string.format("%d frames = a walker: stand down, up, side, then the same "
                  .. "three walking", SpriteImport.MAX_FRAMES),
    "1 frame = stands still; 2-5 are allowed and will not walk",
    "facing RIGHT is drawn by flipping the SIDE frame - do not draw it",
    string.format("a big doll (Snorlax, Lapras) is the one exception: %dx%d",
                  BIG, BIG),
    "4 colours read best - the game recolours it through a GBC palette",
  }
end

-- ---------------------------------------------------------------------------
-- reading
-- ---------------------------------------------------------------------------

-- Read a file the picker or a drop handed us. NOT `love.filesystem.read`: that
-- reads inside the save directory and the game folder, and this path is
-- neither -- it is wherever the reader keeps their art. `io.open` is the only
-- door to an absolute path, and it is the same one `RomImporter.readExternalPath`
-- uses for a dropped ROM.
function SpriteImport.readExternal(path)
  if type(path) ~= "string" or path == "" then return nil, "no file chosen" end
  local f, err = io.open(path, "rb")
  if not f then return nil, tostring(err or "could not open the file") end
  local data = f:read("*a")
  f:close()
  if type(data) ~= "string" or #data == 0 then
    return nil, "that file is empty"
  end
  return data
end

-- PNG, and actually PNG -- the eight-byte signature, not the extension.
--
-- Renaming a JPEG to .png is the commonest way a sheet arrives broken, and the
-- failure without this check is `love.image.newImageData` raising inside a
-- pcall three functions away, where the only thing left to report is "could
-- not read the image".
function SpriteImport.isPng(data)
  return type(data) == "string" and #data > 8
     and data:sub(1, 8) == "\137PNG\r\n\26\n"
end

-- ---------------------------------------------------------------------------
-- what the sheet IS
-- ---------------------------------------------------------------------------

-- Decide the record's shape from the image's own dimensions, or refuse.
--
-- Returns a spec table, or nil plus a reason the reader can act on. Every
-- refusal names the size found AND the size wanted, because "invalid sprite
-- sheet" tells somebody with a 32x48 image nothing about what to do next.
function SpriteImport.describe(w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 0 or h <= 0 then
    return nil, "that image has no size"
  end

  -- THE BIG DOLL, first, because it is 32 wide and the width test below would
  -- otherwise refuse it. One frame, no walk cycle -- SpriteRenderer forces
  -- `frames = 1` for these anyway, and a record that disagrees is a record
  -- that makes the renderer look wrong.
  if w == BIG then
    if h ~= BIG then
      return nil, string.format(
        "a 32px-wide sheet is a big doll and must be 32x32; this is %dx%d",
        w, h)
    end
    return { frames = 1, walker = false, big = true, width = BIG, height = BIG }
  end

  if w ~= FRAME then
    return nil, string.format(
      "an overworld sheet is 16 pixels wide (or 32 for a big doll); this is %d",
      w)
  end
  if h % FRAME ~= 0 then
    return nil, string.format(
      "the height must be a whole number of 16px frames; %d is %.2f of them",
      h, h / FRAME)
  end

  local frames = math.floor(h / FRAME)
  if frames > SpriteImport.MAX_FRAMES then
    return nil, string.format(
      "%d frames is more than a sheet carries (max %d: 3 standing, 3 walking)",
      frames, SpriteImport.MAX_FRAMES)
  end

  -- WALKER AT SIX, and only at six. The walk quads are frames 3, 4 and 5 --
  -- see SpriteRenderer's STAND/WALK tables -- so a four-frame sheet marked as
  -- a walker asks for quads that are not there, and LOVE draws whatever is at
  -- that offset in the atlas, which is nothing.
  return { frames = frames, walker = frames >= 6 }
end

-- ---------------------------------------------------------------------------
-- importing
-- ---------------------------------------------------------------------------

-- The name the reader gets if they do not give one: the file's own, minus its
-- extension, which is nearly always what they would have typed.
function SpriteImport.nameFromPath(path)
  local base = tostring(path or ""):match("[^/\\]+$") or ""
  return (base:gsub("%.[Pp][Nn][Gg]$", ""))
end

-- Import `path` as a new sheet. Returns the id and the spec, or nil + why.
--
-- `S` is the editor state -- it needs the store, the game and `S.data.sprites`
-- so the sheet is usable on the very next frame rather than after a restart.
function SpriteImport.import(S, path, name)
  if not (S and S.mapEdits ~= nil or S) then return nil, "no editor state" end

  local data, why = SpriteImport.readExternal(path)
  if not data then return nil, why end
  if not SpriteImport.isPng(data) then
    return nil, "that is not a PNG (renaming a JPEG does not convert it)"
  end
  if not (love and love.image and love.image.newImageData) then
    return nil, "this build has no image support to read it with"
  end

  -- Decoded through LOVE rather than by parsing the IHDR by hand: the decode
  -- is the real test of whether the file is usable, and a header that says
  -- 16x96 on a truncated file would pass a hand-read and fail at draw time.
  local okData, imageData = pcall(function()
    return love.image.newImageData(
      love.filesystem.newFileData(data, "import.png"))
  end)
  if not (okData and imageData) then
    return nil, "that PNG could not be decoded"
  end

  local spec, refusal = SpriteImport.describe(imageData:getWidth(),
                                              imageData:getHeight())
  if not spec then return nil, refusal end

  local store = S.mapEdits
  if not store then
    store = MapEdits.load()
    S.mapEdits = store
  end
  local game = SpriteImport.gameOf(S)
  local id = MapEdits.newSpriteId(store, game,
    (name and name ~= "" and name) or SpriteImport.nameFromPath(path),
    S.data and S.data.sprites)
  if not id then return nil, "no free sprite id left" end

  -- WRITTEN AS PNG THROUGH ImageData:encode, not by copying the bytes.
  --
  -- The bytes would be the faster path and it is the wrong one: a PNG can
  -- carry an interlace, a palette, 16 bits a channel and an ICC profile, and
  -- `Assets.imageData` re-decodes whatever is on disk every time it is asked.
  -- Encoding what LOVE already decoded normalises all of that once, here,
  -- where a failure can still be reported to the person who chose the file.
  local rel = string.format("%s/%s.png", SpriteImport.DIR, id)
  if love.filesystem and love.filesystem.createDirectory then
    pcall(love.filesystem.createDirectory, SpriteImport.DIR)
  end
  local okEnc = pcall(function() imageData:encode("png", rel) end)
  if not okEnc then
    return nil, "the sheet could not be written to the save folder"
  end

  spec.image = rel
  spec.source = "editor import"
  local okSet, setErr = MapEdits.setSprite(store, game, id, spec)
  if not okSet then return nil, tostring(setErr or "could not record it") end

  -- LIVE, NOW. `applySprites` is what the next launch runs; this is the same
  -- record laid on the table the editor is already drawing from, so the sheet
  -- is in the picker and on the map this frame. Without it the import
  -- succeeded and nothing anywhere showed it.
  if S.data and type(S.data.sprites) == "table" then
    local def = { id = id, editorImported = true }
    for k, v in pairs(spec) do def[k] = v end
    S.data.sprites[id] = def
  end
  -- and the caches that answered "there is no such sheet" a moment ago
  S.objSpriteIds = nil
  pcall(function() require("tools.map-editor.panels.Preview").forgetSprites() end)

  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return id, spec
end

function SpriteImport.gameOf(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring((S and S.version) or v or "unknown")
end

-- Forget one. The PNG is left on disk deliberately: another map's NPC may
-- still name it in a patch that has not been reloaded yet, and an orphaned
-- 400-byte file in a save folder is a smaller problem than a map that draws a
-- fallback where a character used to be.
function SpriteImport.forget(S, id)
  if not (S and id) then return false end
  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  MapEdits.deleteSprite(store, SpriteImport.gameOf(S), id)
  if S.data and type(S.data.sprites) == "table"
     and (S.data.sprites[id] or {}).editorImported then
    S.data.sprites[id] = nil
  end
  S.objSpriteIds = nil
  pcall(function() require("tools.map-editor.panels.Preview").forgetSprites() end)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return true
end

-- Every imported sheet, sorted, for a panel that wants to list them apart from
-- the cartridge's.
function SpriteImport.list(S)
  local store = S and S.mapEdits
  if not store then return {} end
  local out = {}
  for id in pairs(MapEdits.sprites(store, SpriteImport.gameOf(S))) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

return SpriteImport
