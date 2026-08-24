-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Map objects: the NPCs, item balls and trainers standing on a map.
--
-- Plugs into the existing save-editor shell (App.lua's TABS/PANELS) rather than
-- opening a second window. That shell already solves the things a new tool
-- would have to solve again and get wrong: the pad cursor, the console
-- keyboard applet, the modal shield, DPI layout. `MAPS` picks the map; this
-- edits what is on it.
--
-- EVERY CHANGE IS WRITTEN TWICE, on purpose:
--   * into `S.data.maps[id].objects` so the editor (and the map view beside it)
--     shows the change immediately, and
--   * into the MapEdits store, which is what survives.
-- The live table is a rendering of the store, never the other way round -- a
-- reload rebuilds it from the cartridge and re-applies the store on top.
--
-- The list is the CURRENT state (cartridge objects, minus deletions, plus
-- additions), because that is what the player is looking at on the map. Where
-- an entry came from is shown as a tag rather than by splitting the list into
-- three, which would make "the third NPC from the left" impossible to find.

-- Kit arrives as a draw() argument, the way every save-editor panel takes it;
-- requiring it here as well would give the module a second handle on the same
-- table and make it unclear which one a helper is using.
local MapEdits = require("tools.map-editor.MapEdits")

-- The save editor's species SEARCH and LABEL are reused; its picker is not.
-- `Ops.setSpecies` mutates a real save Pokemon -- recomputing stats, DVs and
-- the party checksum -- and a trainer's roster entry is a plain
-- { species, level } row with none of that behind it. Sharing the mutation
-- would either corrupt a save mon or need setSpecies to grow a second mode.
-- The valuable half (the catalogue and the fuzzy match) has no such coupling.

-- The palette, for the guidance line under IMPORT A PNG -- "this is advice,
-- not a control" needs a colour that says so.
--
-- GUARDED, because this panel is loaded by harnesses that put only
-- tools/map-editor on the path -- Theme lives with the save editor's Kit. A
-- missing palette is a colour, not a feature, so it falls back rather than
-- taking the whole panel down with it.
local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
  red = { 230, 90, 90 }, caption = { 160, 175, 205 },
}
local Ops = require("Ops")
local Catalog = require("Catalog")

-- Every SPRITE_* the import produced, sorted, cached per open editor. There is
-- no Catalog list for these -- the save editor never needed one -- so it is
-- built from data.sprites, which is the same table NPC.lua resolves a sheet
-- through, meaning anything listed here is guaranteed to render.
local function spriteIds(S)
  if S.objSpriteIds then return S.objSpriteIds end
  local out = {}
  for id in pairs((S.data and S.data.sprites) or {}) do
    if type(id) == "string" then out[#out + 1] = id end
  end
  table.sort(out)
  S.objSpriteIds = out
  return out
end

-- The same sheets the map draws with, resolved by the same code -- Preview
-- publishes its cache for exactly this. Guarded: a build without the map
-- preview still edits objects, it just does it with names alone.
local function spritePreview(S, spriteId)
  local ok, Preview = pcall(require, "tools.map-editor.panels.Preview")
  if not (ok and type(Preview) == "table" and Preview.spriteQuadFor) then
    return nil
  end
  local okS, image, quad, sw, sh = pcall(Preview.spriteQuadFor, S, spriteId)
  if not okS then return nil end
  return image, quad, sw, sh
end

local function speciesLabel(S, id)
  if not id or id == "" then return "(none)" end
  local ok, label = pcall(Catalog.speciesLabel, S.data, id)
  return (ok and label) or id
end

-- POKEMON OVERWORLD SHEETS ARE ALREADY IN THE LIST. NOBODY COULD FIND THEM.
--
-- The extractor writes one per species -- `SPRITE_MON_249` and the rest -- so
-- Lugia, Ho-Oh, the beasts, the Lake of Rage Gyarados and every other
-- walkabout Pokemon have always been pickable. What they did not have was a
-- NAME: the list is sorted ids, and `SPRITE_MON_249` sits between
-- `SPRITE_MON_248` and `SPRITE_MON_250` saying nothing. Typing "lugia" found
-- nothing at all, which is indistinguishable from the sprite not existing --
-- and that is how it was reported.
--
-- The species is in the id. `SPECIES_249` is the key `data.pokemon` is filed
-- under and `Catalog.speciesLabel` turns into LUGIA, so the name costs a
-- pattern match and a table read.
local function monSpeciesOf(id)
  local n = type(id) == "string" and id:match("^SPRITE_MON_(%d+)$")
  return n and string.format("SPECIES_%03d", tonumber(n)) or nil
end

-- What the row says. A Pokemon sheet is shown by species with its id in
-- brackets -- the id is what an export and a script name, so hiding it would
-- break the one workflow that needs it, and leading with it is what made
-- these unreadable.
local function spriteLabel(S, id)
  local species = monSpeciesOf(id)
  if not species then return id end
  local name = speciesLabel(S, species)
  if name == species then return id end        -- no species table loaded
  return name .. "  (" .. id .. ")"
end

local function spriteMatches(S, id, query)
  if query == "" then return true end
  query = query:lower()
  if id:lower():find(query, 1, true) then return true end
  -- ...and by the species name, so "lugia" finds SPRITE_MON_249.
  local species = monSpeciesOf(id)
  if species then
    local name = speciesLabel(S, species)
    if type(name) == "string" and name:lower():find(query, 1, true) then
      return true
    end
  end
  return false
end

-- WHAT THE PLAYER ACTUALLY HEARS.
--
-- `obj.text` is not the dialogue. The extractor stores a text CONSTANT there
-- -- `NewBarkTownGrampsText` and the like -- and the string itself lives in
-- `data.text`, reached either directly or through the map's own text-pointer
-- table (`Data:resolveText`, which also handles the `_Label` wrappers). So the
-- TEXT box on this panel has been showing every cartridge NPC's label and
-- none of their words: the field looked empty of meaning on exactly the
-- objects that had the most to say.
--
-- Editing still writes a plain string into `obj.text`, and that works because
-- `show_text` falls back to printing its argument when it resolves to nothing
-- -- so prose typed here IS the line. The resolution below is what makes it
-- possible to see what you are replacing before you replace it.
local function resolveText(S, value)
  if type(value) ~= "string" or value == "" then return nil end
  local data = S.data
  if not data then return nil end
  local direct = data.text and data.text[value]
  if type(direct) == "string" then return direct end
  local def = data.maps and data.maps[S.mapId]
  local label = def and def.label
  if label and type(data.resolveText) == "function" then
    local ok, resolved = pcall(data.resolveText, data, label, value)
    if ok and type(resolved) == "string" then return resolved end
  end
  return nil
end

-- Gen 2 text carries control bytes the box interprets: a line break, a
-- paragraph break, the terminator. They are meaningless in a one-line field
-- and unreadable in a preview, so they become spaces there and the raw string
-- is never what is edited unless the player chooses to.
local function readable(str)
  if type(str) ~= "string" then return "" end
  return (str:gsub("[\r\n]+", " "):gsub("@+$", ""):gsub("%s+", " "))
end

local Objects = {}

-- THE SPRITE, FACING THE WAY THE FIELD SAYS -- and drawn by the same code the
-- map draws it with, so the two cannot disagree about the one thing this box
-- exists to show. The sheet layout, the row per facing, the mirror for RIGHT
-- and the one-frame fallback all live in Preview.spriteQuadFor.

function Objects.drawFacingPreview(S, Kit, obj, x, y)
  if not (love and love.graphics and obj) then return end
  local s = Kit.scale
  local box = 32 * s
  Kit.row(x, y, box, box, false)

  -- THROUGH THE MAP'S OWN RESOLVER, not a second copy of the sheet rules.
  --
  -- This used to load the PNG itself and cut its own quad, which meant two
  -- pieces of code deciding what row a facing is and what a one-frame sheet
  -- does -- and they can disagree, which is the worst possible outcome for a
  -- preview whose entire job is to say what the map will show. It also meant
  -- the preview was the raw greyscale sheet while the map beside it drew the
  -- same person in colour.
  local okP, Preview = pcall(require, "tools.map-editor.panels.Preview")
  if not (okP and type(Preview) == "table" and Preview.spriteQuadFor) then
    return
  end
  local okQ, image, quad, sw, sh, flip =
    pcall(Preview.spriteQuadFor, S, obj.sprite, obj.range)
  if not (okQ and image and quad) then return end

  pcall(function()
    local scale = (box - 6 * s) / math.max(sw or 16, sh or 16)
    love.graphics.setColor(1, 1, 1, 1)
    -- RIGHT is LEFT mirrored: negative x-scale, and the origin moves with it
    -- or the sprite draws one width to the left of its box.
    local sx = (flip or 1) < 0 and -scale or scale
    local dx = x + 3 * s + (sx < 0 and (sw * scale) or 0)
    love.graphics.draw(image, quad, dx, y + 3 * s, 0, sx, scale)
  end)
end

local MOVEMENTS = { "STAY", "WALK", "SPIN" }
local FACINGS = { "DOWN", "UP", "LEFT", "RIGHT" }

-- What a new object starts as. Deliberately a talkable NPC standing still and
-- facing the player's usual approach: the most common thing anyone adds, and
-- every other kind is one field away from it.
local function blankNPC()
  return { sprite = "SPRITE_GRAMPS", x = 0, y = 0,
           movement = "STAY", range = "DOWN", text = "" }
end

local function blankItem()
  return { sprite = "SPRITE_POKE_BALL", x = 0, y = 0,
           movement = "STAY", range = "DOWN", item = "ITEM_POTION" }
end

-- ---------------------------------------------------------------------------
-- store access
-- ---------------------------------------------------------------------------

local function store(S)
  if not S.mapEdits then
    local loaded, err = MapEdits.load()
    S.mapEdits = loaded
    S.mapEditsError = err
  end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

local function markDirty(S) S.mapEditsDirty = true end

-- An object the cartridge shipped is patched by INDEX; one the editor added is
-- rewritten in place in the `added` list. Keeping that distinction here is what
-- lets the rest of the panel treat both the same.
local function writeField(S, obj, key, value)
  local st, g, mapId = store(S), game(S), S.mapId
  obj[key] = value
  if obj.added then
    local m = MapEdits.bucket(st, g, mapId, true)
    local slot = m.added and m.added[obj.editorSlot]
    if slot then
      slot[key] = value
    else
      -- THE WRITE THAT WENT NOWHERE, SAID OUT LOUD.
      --
      -- `if slot then ... end` with no else is how an edit disappears in
      -- perfect silence: the field is set on the LIVE object, so the panel
      -- shows the new value and the map draws it, and nothing was written to
      -- the store -- so it is gone at the next load, and the reader's report
      -- is "I typed it, I saved, it did not stick".
      --
      -- Reaching here means `editorSlot` does not name a row: the object is
      -- flagged `added` but the store has no such slot. That is a bug in
      -- whatever added it, and the reader needs to know their typing is not
      -- being kept BEFORE they close the editor.
      S.objNotice = string.format(
        "'%s' could not be saved - this object is marked as editor-added but "
        .. "slot %s is not in the store. Delete and re-add it.",
        tostring(key), tostring(obj.editorSlot))
      pcall(function()
        require("src.core.Logger").warn(
          "map editor: object write dropped (%s on %s, editorSlot=%s, "
          .. "%d slot(s) in store)", tostring(key), tostring(mapId),
          tostring(obj.editorSlot), #((m and m.added) or {}))
      end)
    end
  else
    local m = MapEdits.bucket(st, g, mapId, true)
    m.objects = m.objects or {}
    local patch = m.objects[obj.index] or {}
    patch[key] = value
    m.objects[obj.index] = patch
  end
  markDirty(S)
end

-- Exposed so the party editor can write through the same door every other
-- field in this panel uses -- the added/patched split and the dropped-write
-- report live in there, and a second writer would have to reproduce both.
-- WHAT THE CARTRIDGE SAYS THIS TRAINER'S SIGHT RANGE IS, or nil.
--
-- Read straight out of the extracted trainer headers -- the same table
-- `checkTrainerSight` consults -- rather than from anything the editor keeps,
-- so the panel shows the number the game would actually use if the author had
-- never touched it.
--
-- Keyed by (map LABEL, object index), not by map id: `trainer_headers` is
-- filed under the label the extractor wrote (`AzaleaTown`), which is not the
-- id the editor works in (`AZALEA_TOWN`). Getting that wrong reads nil for
-- every trainer in the game and looks exactly like "the cartridge has no
-- data", which is the wrong lesson to teach the reader.
local function cartridgeSight(S, obj)
  if not (S and S.data and obj and obj.index) then return nil end
  local def = S.data.maps and S.data.maps[S.mapId or ""]
  local label = def and def.label
  if not label then return nil end
  local ok, header = pcall(function()
    if type(S.data.trainerHeader) == "function" then
      return S.data:trainerHeader(label, obj.index)
    end
    local per = S.data.trainer_headers and S.data.trainer_headers[label]
    return per and per[obj.index] or nil
  end)
  if not (ok and type(header) == "table") then return nil end
  return tonumber(header.range)
end

Objects.writeField = writeField

local function currentObjects(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId]
  return (def and def.objects) or {}
end

-- ---------------------------------------------------------------------------
-- mutations
-- ---------------------------------------------------------------------------

-- WHERE A NEW OBJECT GOES: THE CELL THAT IS SELECTED.
--
-- The blanks carry x = 0, y = 0, so every NPC and every item ever added landed
-- in the map's north-west corner -- inside the wall on most interiors and off
-- in the border ring on a route -- and had to be walked back to where it was
-- wanted with two steppers.  Meanwhile the reader had just clicked the cell
-- they meant.  The selection is what the whole editor points at: the voxel
-- brush, the tile painter and the warp editor all act on it, and this is the
-- one tool that ignored it.
--
-- CLAMPED to the map, because the selection outlives the map it was made on --
-- clicking a route cell at (37, 15) and switching to a house would otherwise
-- put an NPC outside a 4x4 room, where nothing can reach it.
local function placeAtSelection(S, template, def)
  local cell = S.pvCell
  if not (cell and def and def.width and def.height) then return template end
  local maxX = math.max(0, def.width * 2 - 1)
  local maxY = math.max(0, def.height * 2 - 1)
  template.x = math.max(0, math.min(math.floor(cell.cx or 0), maxX))
  template.y = math.max(0, math.min(math.floor(cell.cy or 0), maxY))
  return template
end

-- Published so a test can ask where a new object would land without driving
-- the panel's buttons: the placement is the part with a rule in it.
Objects.placeAtSelection = placeAtSelection

-- OPEN A PICKER AND IMPORT WHAT COMES BACK.
--
-- Published because there are two ways in and they must agree: this button,
-- and dropping a PNG on the window (App.filedropped). A drop is the more
-- natural gesture for "here is my art" and it is also the one that arrives
-- with no panel open, so the shared path is a function rather than a branch
-- inside the picker.
--
-- The picker comes from RomImporter -- the same `io.popen` every other dialog
-- in this project goes through, which releases the pointer grab SDL is still
-- holding from the click that opened it. A second copy here would be the
-- exception that makes the regression test about that a lie.
function Objects.importSheet(S, path)
  local okS, SpriteImport = pcall(require, "tools.map-editor.SpriteImport")
  if not (okS and type(SpriteImport) == "table") then
    return nil, "this build has no sprite import"
  end
  if not path then
    local okR, RomImporter = pcall(require, "src.import.RomImporter")
    if not (okR and type(RomImporter) == "table"
            and RomImporter.chooseFileByExt) then
      return nil, "no file picker on this platform - drop a PNG on the window"
    end
    local okP, picked = pcall(RomImporter.chooseFileByExt, { "png" },
                              "character sheet")
    if not okP then return nil, "the file picker could not open" end
    path = picked
    if not path then return nil, "no file chosen" end
  end
  -- second return is the SPEC on success and the REASON on failure; named for
  -- both so the frames read below cannot be mistaken for indexing an error
  local id, specOrWhy = SpriteImport.import(S, path)
  if not id then return nil, specOrWhy end
  local frames = (type(specOrWhy) == "table" and specOrWhy.frames) or 1
  S.objNotice = string.format("imported %s - %d frame%s, %s", id, frames,
    frames == 1 and "" or "s",
    frames >= 6 and "walks" or "stands still")
  return id
end

local function addObject(S, template)
  local def = S.data and S.data.maps and S.data.maps[S.mapId]
  if not def then return end
  placeAtSelection(S, template, def)
  def.objects = def.objects or {}
  local st, g = store(S), game(S)
  local slot = MapEdits.addObject(st, g, S.mapId, template)
  if not slot then return end

  local maxIndex = 0
  for _, o in ipairs(def.objects) do
    if type(o.index) == "number" and o.index > maxIndex then maxIndex = o.index end
  end
  local live = {}
  for k, v in pairs(template) do live[k] = v end
  live.index = maxIndex + 1
  live.id = string.format("%s_EDIT_%03d", S.mapId, slot)
  live.name = live.id
  live.added = true
  live.editorSlot = slot
  def.objects[#def.objects + 1] = live
  S.objSelected = #def.objects
  -- and say where it landed, because "added" with no coordinates is how a
  -- thing dropped in the corner goes unnoticed until you look for it
  S.objNotice = S.pvCell
    and string.format("added at %d,%d - the selected cell", live.x, live.y)
    or "added at 0,0 - click a map cell first to place it there"
  markDirty(S)
end

local function deleteObject(S, i)
  local def = S.data and S.data.maps and S.data.maps[S.mapId]
  local obj = def and def.objects and def.objects[i]
  if not obj then return end
  local st, g = store(S), game(S)
  if obj.added then
    -- Remove the stored entry, then renumber the slots of every addition after
    -- it: `editorSlot` is a position in the `added` list, so deleting one
    -- shifts the rest. Without this the next edit to a later addition writes
    -- into the wrong entry -- silently, and only visible after a reload.
    local m = MapEdits.bucket(st, g, S.mapId, true)
    if m.added and obj.editorSlot then
      table.remove(m.added, obj.editorSlot)
      for _, other in ipairs(def.objects) do
        if other.added and other.editorSlot and other.editorSlot > obj.editorSlot then
          other.editorSlot = other.editorSlot - 1
        end
      end
    end
  else
    MapEdits.removeObject(st, g, S.mapId, obj.index, true)
  end
  table.remove(def.objects, i)
  if S.objSelected and S.objSelected > #def.objects then
    S.objSelected = #def.objects > 0 and #def.objects or nil
  end
  markDirty(S)
end

local function revertObject(S, obj)
  if not obj or obj.added then return end
  MapEdits.setObject(store(S), game(S), S.mapId, obj.index, nil)
  markDirty(S)
  S.objNotice = "reverted on next reload"
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

local function cycle(list, current, dir)
  local at = 1
  for i, v in ipairs(list) do if v == current then at = i break end end
  return list[((at - 1 + (dir or 1)) % #list) + 1]
end

local function tagFor(obj)
  if obj.added then return "NEW" end
  if obj.edited then return "EDITED" end
  return nil
end

-- ITEM_007 IS NOT AN ITEM NAME, IT IS A ROW NUMBER.
--
-- The extractor keys items by index because that is what the cartridge stores,
-- and it carries the real name alongside -- so a panel showing the key is
-- showing the one field that means nothing to a reader. Catalog.itemLabel is
-- the resolver the save editor already uses for the same problem, and it knows
-- the fallbacks: the name, then the pret key, then the id, and never the
-- extractor's own "Item 7" placeholder.
local function itemLabel(S, id)
  if not id or id == "" then return nil end
  local ok, Catalog = pcall(require, "Catalog")
  if ok and type(Catalog) == "table" and Catalog.itemLabel then
    local okL, label = pcall(Catalog.itemLabel, S.data, id)
    if okL and label then return label end
  end
  local entry = S.data and S.data.items and S.data.items[id]
  return (entry and entry.name) or id
end

-- Every item the import produced, sorted by their INDEX rather than by name,
-- because that is the order the game's own lists are in and a reader looking
-- for POTION expects it where the game puts it.
local function itemIds(S)
  if S._itemIds then return S._itemIds end
  local out = {}
  for id, entry in pairs((S.data and S.data.items) or {}) do
    out[#out + 1] = { id = id, index = (type(entry) == "table" and entry.index) or 0 }
  end
  table.sort(out, function(a, b)
    if a.index ~= b.index then return a.index < b.index end
    return a.id < b.id
  end)
  local ids = {}
  for i, e in ipairs(out) do ids[i] = e.id end
  S._itemIds = ids
  return ids
end

-- ---------------------------------------------------------------------------
-- trainers, by name, from the table the battle engine actually reads
-- ---------------------------------------------------------------------------
--
-- `trainerClass` WAS A FREE-TEXT FIELD AND THAT WAS A CRASH, not a typo risk.
-- `BattleState.newTrainer` does `data.trainers[oppClass]` and then
-- `assert(self.trainer, "unknown trainer class " .. oppClass)` -- so a class
-- typed by hand had to match a key of that table exactly or the game died the
-- moment the player crossed the trainer's line of sight. The placeholder said
-- "e.g. YOUNGSTER"; the key is OPP_YOUNGSTER. Following the panel's own advice
-- produced the assert.
--
-- So the list is the table's own keys, which cannot be wrong by construction.
local function trainerClassIds(S)
  if S._trainerIds then return S._trainerIds end
  local out = {}
  for id in pairs((S.data and S.data.trainers) or {}) do
    if type(id) == "string" then out[#out + 1] = id end
  end
  table.sort(out)
  S._trainerIds = out
  return out
end

-- What to show for one. The class key is shouty and prefixed; the row's own
-- `name` is what the game prints over the battle box.
local function trainerLabel(S, id)
  if not id or id == "" then return nil end
  local row = S.data and S.data.trainers and S.data.trainers[id]
  local name = type(row) == "table" and row.name or nil
  if name and name ~= "" and name ~= id then
    return tostring(name) .. "  (" .. id .. ")"
  end
  return id
end

-- The rosters packed into one class. Gen 2 puts several trainers in a class
-- and names them individually; `trainerParty` is which one.
local function trainerParties(S, class)
  local row = S.data and S.data.trainers and S.data.trainers[class]
  local names = type(row) == "table" and row.partyNames or nil
  if type(names) ~= "table" then return {} end
  local out = {}
  for i, n in ipairs(names) do out[i] = tostring(n) end
  return out
end

local function trainerMatches(id, label, query)
  if not query or query == "" then return true end
  query = query:lower()
  return (id or ""):lower():find(query, 1, true) ~= nil
      or (label or ""):lower():find(query, 1, true) ~= nil
end

-- IN THE ORDER THE RUNTIME CHECKS THEM. OverworldController's talk handler
-- tests `item`, then `pokemon`, then `trainerClass`, and returns from the
-- first that answers -- so an object carrying two of them behaves as the
-- earlier one, and a list that named the later one would be lying about what
-- the object does.
local function kindOf(obj)
  if obj.item then return "ITEM" end
  if obj.pokemon then return "WILD" end
  if obj.trainerClass then return "TRAINER" end
  return "NPC"
end

function Objects.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad, gap = 16 * s, 20 * s

  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map on the MAPS tab first.")
    return
  end

  -- THE TWO COLUMNS SHARE THE WIDTH. THE LIST YIELDS FIRST.
  --
  -- This was `max(240, min(320, w * 0.34))` -- a FLOOR on the list and no
  -- floor at all on the editor beside it. In a drawer 460 units wide that
  -- leaves the editor 168, of which the label column takes 96 and the padding
  -- 32: a field width of forty, and every control laid out from `fieldX` past
  -- that runs off the card and is clipped away by the drawer.
  --
  -- FACING is the control that showed it. Its four direction buttons are a
  -- fixed 26 units each -- they do not shrink with the field the way a text
  -- box does -- so they were the first thing to march off the right-hand edge,
  -- and a clipped control is not a squashed control: it is an invisible one,
  -- and it reads as the editor not having the feature. Which is exactly how it
  -- was reported.
  --
  -- So the list gives ground down to a floor of its own, and never takes so
  -- much that the editor drops under a width its rows can be laid out in.
  local EDITOR_MIN = 210 * s
  local listW = math.max(150 * s, math.min(320 * s, w * 0.34))
  listW = math.min(listW, math.max(150 * s, w - gap - EDITOR_MIN))
  local sideX = x + listW + gap
  local sideW = w - listW - gap

  -- ------------------------------------------------------------- the list
  Kit.card(x, y, listW, h)
  Kit.caption(x + pad, y + pad, "OBJECTS - " .. tostring(S.mapId))

  local objs = currentObjects(S)
  local rowH = 34 * s
  local top = y + pad + Kit.textHeight("caption") + 10 * s
  local addH = 32 * s
  local listBottom = y + h - pad - addH - 8 * s
  local perPage = math.max(1, math.floor((listBottom - top) / rowH))
  S.objScroll = math.max(0, math.min(S.objScroll or 0, math.max(0, #objs - perPage)))

  if #objs == 0 then
    Kit.text("body", "Nothing on this map yet.", x + pad, top)
  end
  local shown = math.max(0, math.min(perPage, #objs - S.objScroll))
  for row = 1, shown do
    local i = row + S.objScroll
    local obj = objs[i]
    local ry = top + (row - 1) * rowH
    local selected = S.objSelected == i
    if Kit.press(x + pad, ry, listW - 2 * pad, rowH - 4 * s) then
      S.objSelected = i
      S.objNotice = nil
      -- an arm belongs to the row it was made on, and following it to another
      -- row is how a confirm ends up deleting something else
      S.objDeleteArmed = nil
    end
    Kit.row(x + pad, ry, listW - 2 * pad, rowH - 4 * s, selected)
    local kind = kindOf(obj)
    local label = string.format("%d  %s", i, kind)
    if kind == "ITEM" then
      label = string.format("%d  %s", i, itemLabel(S, obj.item) or "ITEM")
    elseif kind == "WILD" then
      -- The species, not the word: a row of five "WILD"s is a list you have to
      -- click through to read.
      label = string.format("%d  WILD %s", i, speciesLabel(S, obj.pokemon))
    end
    Kit.text("body", label, x + pad + 8 * s, ry + 7 * s)
    local where = string.format("(%d,%d)", obj.x or 0, obj.y or 0)
    Kit.textRight("body", where, x + listW - pad - 8 * s, ry + 7 * s)
    local tag = tagFor(obj)
    if tag then
      Kit.text("small", tag, x + pad + 8 * s, ry + 20 * s)
    end
    -- ON THE SELECTED ROW, because the list is where you are looking when you
    -- decide something should not be there. Same arm-then-confirm as the
    -- button below: one press marks it, the second removes it.
    if selected then
      local dw = 24 * s
      local dx = x + listW - pad - dw - 4 * s
      local rowArmed = S.objDeleteArmed == i
      if Kit.button(dx, ry + 4 * s, dw, rowH - 12 * s, rowArmed and "!" or "x",
                    { font = "small", radius = 6 * s,
                      kind = rowArmed and "danger" or nil }) then
        if rowArmed then
          deleteObject(S, i)
          S.objDeleteArmed = nil
          S.objNotice = "deleted - Ctrl-Z brings it back"
        else
          S.objDeleteArmed = i
          S.objNotice = "press x again to remove it"
        end
      end
    end
  end

  -- ---------------------------------------------------- add, under the list
  --
  -- FLOWED UNDER THE LAST OBJECT, not pinned to the foot of the page.
  --
  -- Pinned was right when this was a full tab, where the foot of the page and
  -- the bottom of the window were the same line.  In the drawer the panel is
  -- handed a page taller than the drawer, so the foot is somewhere below the
  -- bottom of the screen -- and + NPC and + ITEM went with it.  There was no
  -- way to add anything to a map without knowing to scroll past the end of a
  -- list that looked like it ended.
  --
  -- One row of clearance when the list is empty, so "Nothing on this map yet"
  -- has somewhere to sit and the buttons are not jammed against it.
  local addY = top + math.max(shown, 1) * rowH + 10 * s
  local halfW = (listW - 2 * pad - 8 * s) / 2
  if Kit.button(x + pad, addY, halfW, addH, "+ NPC") then
    addObject(S, blankNPC())
  end
  if Kit.button(x + pad + halfW + 8 * s, addY, halfW, addH, "+ ITEM") then
    addObject(S, blankItem())
  end
  -- How tall the LIST column came out, for the page measurement at the foot of
  -- this function: with forty objects on a map it is the taller of the two.
  local listFlowH = (addY + addH + 20 * s) - y

  -- WHERE THE LIST IS, for the wheel.  See Objects.wheelmoved: a notch over
  -- the list scrolls the list, and a notch over the EDITOR has to fall through
  -- to the drawer, or the editor column can never be scrolled at all.
  --
  -- The rows AS DRAWN, down to the add row -- not the whole page-tall card.
  -- Measured against the card the region reached the foot of a page that can
  -- be twice the drawer's height, so a notch aimed at empty space below a
  -- three-object list still counted as "over the list" and the drawer stayed
  -- stuck.
  S._objListRect = { x, top, listW, (addY + addH) - top }

  -- ------------------------------------------------------------ the editor
  Kit.card(sideX, y, sideW, h)
  local obj = objs[S.objSelected or 0]
  if not obj then
    Kit.emptyBox(sideX + pad, y + pad, sideW - 2 * pad, h - 2 * pad,
                 "Select an object, or add one.")
    -- and the page shrinks back: the measurement is kept across frames, so
    -- without this a trainer's tall form would leave a screenful of empty
    -- scroll behind after selecting an item with four fields.
    local okE, Sidebar = pcall(require, "tools.map-editor.Sidebar")
    if okE and type(Sidebar) == "table" and Sidebar.reportHeight then
      -- the list is all there is to see, so it is the whole measurement
      Sidebar.reportHeight(S, listFlowH)
    end
    return
  end

  local fy = y + pad
  Kit.caption(sideX + pad, fy, kindOf(obj) .. "  #" .. tostring(obj.index or "?"))
  fy = fy + Kit.textHeight("caption") + 10 * s

  local fieldH = 30 * s
  -- AND THE LABEL COLUMN GIVES GROUND TOO, for the same reason: 96 units of
  -- label is right beside a 300-unit field and absurd beside a 60-unit one.
  -- Floored at 44 so a label is still a word rather than an initial, and
  -- capped at the original 96 so nothing about a wide drawer changes.
  local avail = math.max(48 * s, sideW - 2 * pad)
  local labelW = math.max(0, math.min(96 * s, avail * 0.32))
  -- THE TWO ALWAYS SUM TO WHAT THERE IS. A floor under the field width -- the
  -- obvious guard against a negative one -- is how a control ends up wider
  -- than the card it is in, and the card is what the drawer clips to. So the
  -- field takes what is left and the LABEL gives up the difference; below the
  -- point where a label is a word at all it gives up everything, and the row
  -- is a control with no caption rather than a caption with no control.
  local fieldW = math.max(24 * s, avail - labelW)
  labelW = avail - fieldW
  local fieldX = sideX + pad + labelW

  local function field(label, id, value, placeholder)
    Kit.text("body", label, sideX + pad, fy + 7 * s)
    local out = Kit.textfield(id, fieldX, fy, fieldW, fieldH,
                              tostring(value or ""), placeholder)
    fy = fy + fieldH + 8 * s
    return out
  end

  -- Minus, the number, plus -- measured out of the field's own width rather
  -- than from three constants that add up to more than the card has.
  local function stepperRow(label, value, onMinus, onPlus)
    Kit.text("body", label, sideX + pad, fy + 7 * s)
    local bw = math.min(30 * s, fieldW / 3)
    local numW = math.max(0, fieldW - 2 * bw)
    if Kit.stepper(fieldX, fy, bw, fieldH, "-") then onMinus() end
    Kit.textCenter("body", tostring(value), fieldX + bw, fy + 7 * s, numW)
    if Kit.stepper(fieldX + bw + numW, fy, bw, fieldH, "+") then onPlus() end
    fy = fy + fieldH + 8 * s
  end

  local function numberRow(label, key)
    stepperRow(label, obj[key] or 0,
      function() writeField(S, obj, key, math.max(0, (obj[key] or 0) - 1)) end,
      function() writeField(S, obj, key, (obj[key] or 0) + 1) end)
  end

  -- THE SPRITE, ZOOMED, BESIDE ITS NAME.
  --
  -- A SPRITE_* constant is a name, not a picture -- SPRITE_GRAMPS and
  -- SPRITE_POKEFAN_M are both plausible old men, and the only way to find out
  -- which one you had picked was to close the panel and look at the map. At
  -- sixteen pixels a sheet is small enough that the honest fix is simply to
  -- show it big: this draws the standing frame at 6x, which is about the size
  -- the artwork was designed at on a GBC screen held at arm's length.
  --
  -- Nearest-neighbour is deliberate and has to be asked for: LOVE's default
  -- filter is linear, and a 16px sprite blown up smoothly is a smear. Set on
  -- the image rather than globally so nothing else in the editor changes.
  do
    local ZOOM = 6
    local image, quad, sw, sh = spritePreview(S, obj.sprite)
    local boxW = (sw or 16) * ZOOM * s
    local boxH = (sh or 16) * ZOOM * s
    local px0 = sideX + sideW - pad - boxW
    Kit.text("body", "SPRITE", sideX + pad, fy + 7 * s)
    local shownName = obj.sprite and spriteLabel(S, obj.sprite) or "(none)"
    -- Clamped to the field: `max(60, ...)` was a floor, and a floor is how a
    -- button ends up wider than the card the drawer clips to.
    if Kit.button(fieldX, fy,
                  math.max(24 * s, math.min(fieldW, px0 - fieldX - 10 * s)),
                  fieldH,
                  Kit.ellipsize("small", shownName,
                                math.max(40 * s, px0 - fieldX - 22 * s))) then
      S.objSpriteOpen = not S.objSpriteOpen
      S.objSpriteQuery = ""
    end
    if image then
      love.graphics.setColor(1, 1, 1, 0.06)
      love.graphics.rectangle("fill", px0, fy, boxW, boxH, 6 * s, 6 * s)
      pcall(image.setFilter, image, "nearest", "nearest")
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, quad, px0, fy, 0, ZOOM * s, ZOOM * s)
      love.graphics.setColor(1, 1, 1, 1)
    else
      Kit.text("small", "no sheet", px0, fy + 6 * s)
    end
    fy = fy + math.max(fieldH, boxH) + 8 * s
  end
  if S.objSpriteOpen then
    -- BRING YOUR OWN SHEET.
    --
    -- The cartridge has about a hundred and forty of these and they are all
    -- somebody else's characters. A map you invented wants a person nobody
    -- has seen, and until now the answer was "pick the closest gramps".
    --
    -- Sits ABOVE the search box because it is not one of the search results:
    -- it is the thing you do when none of them is what you want, and that is
    -- exactly the moment you are looking at an empty list.
    if Kit.button(fieldX, fy, fieldW, fieldH - 2 * s, "IMPORT A PNG...",
                  { font = "small", kind = "accent" }) then
      local id, why = Objects.importSheet(S)
      if id then
        writeField(S, obj, "sprite", id)
        S.objSpriteOpen = false
      else
        S.objNotice = tostring(why)
      end
    end
    fy = fy + fieldH + 4 * s
    -- WHAT IT HAS TO BE, in full, BEFORE the picker opens.
    --
    -- This was one line -- "16px wide, 16px frames stacked down" -- which
    -- covers the commonest refusal and none of the others: the frame ORDER,
    -- that right is a flip of the side frame and must not be drawn, and the
    -- 32x32 doll exception. A reader who draws a seventh frame for RIGHT is
    -- not refused at all; they get a sheet with a pose nothing ever shows.
    --
    -- From SpriteImport, so this list and the validator cannot disagree: a
    -- caption that has drifted from the rule it describes is worse than none,
    -- because the reader follows it, is refused anyway, and now trusts
    -- neither.
    do
      local okS, SpriteImport = pcall(require, "tools.map-editor.SpriteImport")
      local reqs = (okS and SpriteImport.requirements
                    and SpriteImport.requirements())
        or { "16px wide, 16px frames stacked down - 6 for a walker" }
      for _, line in ipairs(reqs) do
        Kit.text("small", Kit.ellipsize("small", "- " .. line, fieldW),
                 fieldX, fy, PAL.muted)
        fy = fy + 13 * s
      end
      fy = fy + 4 * s
    end

    S.objSpriteQuery = Kit.textfield("obj-sprite-q", fieldX, fy, fieldW,
      fieldH, S.objSpriteQuery or "", "search sprites...")
    fy = fy + fieldH + 4 * s
    local shown, all = 0, spriteIds(S)
    local sprites = (S.data and S.data.sprites) or {}
    for _, id in ipairs(all) do
      if spriteMatches(S, id, S.objSpriteQuery or "") then
        shown = shown + 1
        if shown <= 6 then
          local mine = (sprites[id] or {}).editorImported
          -- an imported sheet gets its own row treatment and a way OUT: it is
          -- the only kind that can be wrong because the reader made it, and
          -- the only kind that is theirs to remove
          local delW = mine and 30 * s or 0
          local rowLabel = spriteLabel(S, id)
          if Kit.button(fieldX, fy, fieldW - delW, fieldH - 4 * s,
                        Kit.ellipsize("small",
                                      mine and ("* " .. rowLabel) or rowLabel,
                                      fieldW - delW - 12 * s)) then
            writeField(S, obj, "sprite", id)
            S.objSpriteOpen = false
          end
          if mine and Kit.button(fieldX + fieldW - delW + 4 * s, fy,
                                 delW - 4 * s, fieldH - 4 * s, "x",
                                 { font = "small", radius = 5 * s }) then
            local okF, SpriteImport =
              pcall(require, "tools.map-editor.SpriteImport")
            if okF then SpriteImport.forget(S, id) end
            S.objNotice = id .. " removed - the PNG is still in your save folder"
          end
          fy = fy + fieldH - 2 * s
        end
      end
    end
    if shown == 0 then
      Kit.text("small", "no sprite matches that", fieldX, fy)
      fy = fy + 16 * s
    elseif shown > 6 then
      Kit.text("small", string.format("%d more - keep typing", shown - 6),
               fieldX, fy)
      fy = fy + 16 * s
    end
  end

  numberRow("X", "x")
  numberRow("Y", "y")

  -- MOVEMENT and FACING are closed sets, so they cycle rather than being typed:
  -- a free-text movement that is not one of the three silently becomes STAY at
  -- runtime, which is a bug the editor should make impossible rather than
  -- report.
  Kit.text("body", "MOVEMENT", sideX + pad, fy + 7 * s)
  if Kit.button(fieldX, fy, math.min(110 * s, fieldW), fieldH,
                tostring(obj.movement or "STAY")) then
    writeField(S, obj, "movement", cycle(MOVEMENTS, obj.movement or "STAY", 1))
  end
  fy = fy + fieldH + 8 * s

  -- FACING, AND THE NPC WEARING IT.
  --
  -- The cycle button alone made this the one field you had to guess at: a
  -- STAY object's `range` IS its facing, "DOWN" is a word, and whether the
  -- sprite you picked actually looks the way you meant was a question only the
  -- running game could answer. So the sprite is drawn here, in the direction
  -- the field currently says, and the four directions are four buttons rather
  -- than a cycle -- picking a facing should not mean pressing a button three
  -- times.
  Kit.text("body", "FACING", sideX + pad, fy + 7 * s)
  do
    local bgap = 4 * s
    local cur = tostring(obj.range or "DOWN"):upper()
    -- WHAT IS ACTUALLY LEFT, measured rather than assumed. The preview box and
    -- the spelled-out word are the two things that can be dropped: the
    -- direction buttons are the control, and the control does not get cut.
    local previewW = 32 * s + 6 * s
    local wordW = Kit.textWidth("small", "RIGHT") + 8 * s
    local room = fieldW
    local showPreview = room >= (4 * 26 * s + 3 * bgap) + wordW + previewW
    if showPreview then room = room - previewW end
    local showWord = room >= (4 * 22 * s + 3 * bgap) + wordW
    if showWord then room = room - wordW end

    local bw = (room - 3 * bgap) / 4
    if bw >= 18 * s then
      for i, dir in ipairs(FACINGS) do
        local bx = fieldX + (i - 1) * (bw + bgap)
        local glyph = ({ DOWN = "v", UP = "^", LEFT = "<", RIGHT = ">" })[dir]
        if Kit.button(bx, fy, bw, fieldH, glyph,
                      { font = "small",
                        kind = (cur == dir) and "accent" or nil })
        then
          writeField(S, obj, "range", dir)
        end
      end
      local after = fieldX + 4 * (bw + bgap)
      -- The word too: four arrows are quick to press and ambiguous to read
      -- back, and this field is stored as text an author may also see in an
      -- export.
      if showWord then
        Kit.text("small", cur, after + 6 * s, fy + 7 * s, PAL.muted)
        after = after + wordW
      end
      if showPreview then
        Objects.drawFacingPreview(S, Kit, obj, after + 6 * s, fy - 6 * s)
      end
    else
      -- A FLOOR, NOT A FAILURE. Below four buttons there is still one, and
      -- cycling through four directions is worse than pressing the one you
      -- want and far better than the control not being there -- which is what
      -- happened before, silently, off the edge of the card.
      if Kit.button(fieldX, fy, fieldW, fieldH, cur .. "  (tap to turn)",
                    { font = "small", kind = "accent" }) then
        writeField(S, obj, "range", cycle(FACINGS, cur, 1))
      end
    end
  end
  fy = fy + fieldH + 12 * s

  -- ------------------------------------------------------------- behaviour
  Kit.caption(sideX + pad, fy, "WHAT IT DOES")
  fy = fy + Kit.textHeight("caption") + 8 * s

  -- The resolved line first, wrapped, read-only: this is the thing the panel
  -- exists to show and it should not be behind a button.
  local says = resolveText(S, obj.text)
  if says then
    Kit.text("small", "SAYS", sideX + pad, fy)
    local body = readable(says)
    local width = sideW - 2 * pad - 46 * s

    -- MEASURED AGAINST THE FONT THAT WILL DRAW IT. See Kit.wrap for what the
    -- old count-the-characters version got wrong and why it could not be
    -- fixed by resizing anything.
    local shown = Kit.wrap("small", body, width)

    -- ALL OF IT, on request. Three lines with an ellipsis was the whole of
    -- what this ever showed, and the one question the panel is being asked --
    -- what does this person SAY -- cannot be answered by its first third.
    -- Collapsed by default so a long speech does not push the fields below it
    -- off the drawer, and the button says how much is hidden rather than
    -- merely that something is.
    local CAP = 4
    local expanded = S.objSaysOpen == true
    local lines = #shown
    local limit = expanded and lines or math.min(CAP, lines)
    for i = 1, limit do
      Kit.text("small", shown[i], sideX + pad + 46 * s, fy + (i - 1) * 15 * s)
    end
    fy = fy + math.max(1, limit) * 15 * s + 2 * s
    if lines > CAP then
      if Kit.button(sideX + pad + 46 * s, fy,
                    math.min(150 * s, sideW - 2 * pad - 46 * s), 20 * s,
                    expanded and "SHOW LESS"
                    or string.format("%d MORE LINES", lines - CAP),
                    { font = "small", radius = 5 * s }) then
        S.objSaysOpen = not expanded
      end
      fy = fy + 22 * s
    end
    fy = fy + 6 * s
  end

  -- The editable field is seeded with the resolved words, not the constant: a
  -- label is not something anyone means to edit, and leaving it in the box
  -- made the obvious action -- click, type -- silently replace the link to
  -- the cartridge line with whatever was typed over the top of its NAME.
  local seed = obj.text
  if says and not obj.edited and not obj.added then seed = readable(says) end
  -- A TEXTAREA, NOT A ONE-LINE FIELD. This is the only box in the editor that
  -- holds a PARAGRAPH -- everything else here is a name, a number or an id --
  -- and a single line showing the tail of the string is exactly wrong for it:
  -- the author could see "...2recomped" and had no way to read back what they
  -- had written, no selection, and a backspace that erased one character per
  -- press. See Kit.textarea.
  Kit.text("body", "TEXT", sideX + pad, fy + 7 * s)
  local textH = math.max(fieldH, math.min(96 * s, 5 * (Kit.textHeight("mono")
                                                       + 2 * s) + 16 * s))
  local text = Kit.textarea("obj-text", fieldX, fy, fieldW, textH,
                            tostring(seed or ""), "what they say...")
  fy = fy + textH + 8 * s
  if text ~= (seed or "") then writeField(S, obj, "text", text) end
  if says then
    Kit.text("small", "was: " .. tostring(obj.text), sideX + pad, fy, nil, 0.5)
    fy = fy + 15 * s
  end

  -- THE ITEM, BY NAME, FROM A LIST.
  --
  -- It was a free-text field holding the storage key: you had to already know
  -- that a Coin Case is ITEM_007, type it exactly, and a typo wrote a ball
  -- containing nothing with no complaint. The key is still what is stored --
  -- that is what the cartridge and every script mean by an item -- but nothing
  -- about choosing one has to be spelled in it.
  do
    Kit.text("body", "ITEM", sideX + pad, fy + 7 * s)
    if Kit.button(fieldX, fy, fieldW, fieldH,
                  obj.item and itemLabel(S, obj.item) or "(none)") then
      S.objItemOpen = not S.objItemOpen
      S.objItemQuery = ""
    end
    fy = fy + fieldH + 8 * s
    if S.objItemOpen then
      S.objItemQuery = Kit.textfield("obj-item-q", fieldX, fy, fieldW, fieldH,
        S.objItemQuery or "", "search items...")
      fy = fy + fieldH + 4 * s
      -- CLEARING is one of the answers: an object with no item is an NPC, and
      -- there has to be a way back from having made it a ball.
      if Kit.button(fieldX, fy, fieldW, fieldH - 4 * s, "(none) - not an item") then
        writeField(S, obj, "item", nil)
        S.objItemOpen = false
      end
      fy = fy + fieldH - 2 * s
      local q = (S.objItemQuery or ""):lower()
      local shown = 0
      for _, id in ipairs(itemIds(S)) do
        local label = itemLabel(S, id) or id
        if q == "" or label:lower():find(q, 1, true)
           or id:lower():find(q, 1, true) then
          shown = shown + 1
          if shown <= 8 then
            if Kit.button(fieldX, fy, fieldW, fieldH - 4 * s, label) then
              writeField(S, obj, "item", id)
              S.objItemOpen = false
            end
            fy = fy + fieldH - 2 * s
          end
        end
      end
      if shown == 0 then
        Kit.text("small", "no item matches that", fieldX, fy)
        fy = fy + 16 * s
      elseif shown > 8 then
        Kit.text("small", string.format("%d more - keep typing", shown - 8),
                 fieldX, fy)
        fy = fy + 16 * s
      end
    end
    -- the storage key, small, underneath: it is what a script names and what
    -- the save file holds, so hiding it entirely would break the one workflow
    -- that needs it
    if obj.item then
      Kit.text("small", tostring(obj.item), fieldX, fy, nil, 0.5)
      fy = fy + 15 * s
    end
  end

  -- A WILD BATTLE WHEN YOU TALK TO IT.
  --
  -- THE RUNTIME ALREADY DOES THIS AND THE EDITOR COULD NOT SAY SO. An
  -- object_event carrying `pokemon` and `level` is how the cartridge stands
  -- Ho-Oh on the Tin Tower, Suicune on Route 36, Sudowoodo in the way and the
  -- Lake of Rage Gyarados in the water: talking to it faces you, prints its
  -- line, and opens a wild battle -- and on a win the object is gone for good
  -- (OverworldController, the `if d.pokemon` branch). Two fields, both
  -- unreachable from here, so every one of those had to be edited by hand.
  --
  -- WHICH MAKES THIS A PANEL CHANGE AND NOT A FEATURE. Nothing new runs: an
  -- NPC given a species here is the same kind of object the cartridge already
  -- ships, and it behaves identically in play, in an export and after a
  -- reload. That is the whole reason to spend the two fields on the mechanism
  -- that exists rather than invent a second one.
  --
  -- IT SITS ABOVE TRAINER because an object is ONE of these things and the
  -- runtime checks in this order: item, then wild, then trainer. A reader who
  -- fills in both should see the one that wins first, and the note says which.
  do
    Kit.text("body", "WILD", sideX + pad, fy + 7 * s)
    if Kit.button(fieldX, fy, fieldW, fieldH,
                  obj.pokemon and speciesLabel(S, obj.pokemon)
                  or "(not a wild Pokemon)",
                  { kind = obj.pokemon and "accent" or nil }) then
      S.objWildOpen = not S.objWildOpen
      S.objWildQuery = ""
    end
    fy = fy + fieldH + 8 * s

    if S.objWildOpen then
      S.objWildQuery = Kit.textfield("obj-wild-q", fieldX, fy, fieldW, fieldH,
        S.objWildQuery or "", "search species...")
      fy = fy + fieldH + 4 * s
      -- CLEARING IS ONE OF THE ANSWERS, the same as it is for the item: an
      -- object with no species is an ordinary NPC again, and there has to be a
      -- way back from having made it a legendary.
      if Kit.button(fieldX, fy, fieldW, fieldH - 4 * s,
                    "(none) - just an NPC") then
        writeField(S, obj, "pokemon", nil)
        writeField(S, obj, "level", nil)
        S.objWildOpen = false
      end
      fy = fy + fieldH - 2 * s
      local okHits, hits = pcall(Ops.speciesSearch, S, S.objWildQuery or "")
      hits = (okHits and hits) or {}
      for hi = 1, math.min(6, #hits) do
        local id = hits[hi]
        if Kit.button(fieldX, fy, fieldW, fieldH - 4 * s,
                      speciesLabel(S, id)) then
          writeField(S, obj, "pokemon", id)
          -- A LEVEL COMES WITH IT. `BattleState.newWild` builds the mon from
          -- (species, level) and `Pokemon.new` has no default -- a species
          -- with no level is a battle against a level-nil Pokemon, which is
          -- an error deep in the stat maths rather than anything the reader
          -- could connect to the field they just filled.
          if not tonumber(obj.level) then
            writeField(S, obj, "level", 5)
          end
          S.objWildOpen = false
        end
        fy = fy + fieldH - 2 * s
      end
      if #hits == 0 then
        Kit.text("small", "no species matches that", fieldX, fy, PAL.muted)
        fy = fy + 16 * s
      elseif #hits > 6 then
        Kit.text("small", string.format("%d more - keep typing", #hits - 6),
                 fieldX, fy, PAL.muted)
        fy = fy + 16 * s
      end
    end

    if obj.pokemon then
      stepperRow("LEVEL", tonumber(obj.level) or 5,
        function()
          writeField(S, obj, "level",
                     math.max(1, (tonumber(obj.level) or 5) - 1))
        end,
        function()
          writeField(S, obj, "level",
                     math.min(100, (tonumber(obj.level) or 5) + 1))
        end)

      -- WHAT IT WILL DO, said here rather than found out by playing. All three
      -- sentences are behaviour the reader cannot see from the fields: the
      -- line comes from TEXT above, the object does not come back, and TRAINER
      -- below this is now dead for this object.
      for _, line in ipairs({
        "Talking to this NPC starts a wild battle.",
        "It says its TEXT first, then the battle opens.",
        "Beat it and it is gone for good, like a legendary.",
        "A wild Pokemon is never a trainer - TRAINER below is ignored.",
      }) do
        Kit.text("small", Kit.ellipsize("small", line, fieldW), fieldX, fy,
                 PAL.muted)
        fy = fy + 13 * s
      end
      fy = fy + 6 * s
    end
  end

  -- THE TRAINER CLASS, FROM THE TABLE, for the same reason the item is: the
  -- stored value is a key the battle engine asserts on, and nothing about
  -- choosing one has to be spelled in it. See trainerClassIds.
  do
    Kit.text("body", "TRAINER", sideX + pad, fy + 7 * s)
    if Kit.button(fieldX, fy, fieldW, fieldH,
                  obj.trainerClass and trainerLabel(S, obj.trainerClass)
                  or "(not a trainer)") then
      S.objTrainerOpen = not S.objTrainerOpen
      S.objTrainerQuery = ""
    end
    fy = fy + fieldH + 8 * s

    -- THE TEAM, once there is a trainer to give one to.
    --
    -- `trainerParty` picks one of the parties the CARTRIDGE shipped for this
    -- class, which is right for a ported trainer and useless for an NPC the
    -- author invented -- they had to borrow somebody else's six Pokemon. This
    -- opens the editor for a party of their own; see panels/PartyEditor.lua.
    if obj.trainerClass then
      local team = obj.trainerTeam
      local mine = (type(team) == "table" and #team > 0)
      -- THE CARTRIDGE'S COUNT, when the author has not overridden it. "Using
      -- the cartridge's" told the reader nothing about whether there was one
      -- to use -- and for a trainer whose class has no party there is not,
      -- which is worth knowing before opening an empty editor.
      local cart = nil
      if not mine then
        local okPE, PartyEditor =
          pcall(require, "tools.map-editor.panels.PartyEditor")
        if okPE and PartyEditor.cartridgeParty then
          local party = PartyEditor.cartridgeParty(S, obj)
          cart = party and #party or nil
        end
      end
      local label
      if mine then
        label = string.format("PARTY  -  %d POKEMON (yours)", #team)
      elseif cart then
        label = string.format("PARTY  -  %d from the cartridge", cart)
      else
        label = "PARTY  -  none yet"
      end
      Kit.text("body", "TEAM", sideX + pad, fy + 7 * s)
      if Kit.button(fieldX, fy, fieldW, fieldH, label,
                    { font = "small",
                      kind = mine and "accent" or nil }) then
        local okPE, PartyEditor =
          pcall(require, "tools.map-editor.panels.PartyEditor")
        if okPE and type(PartyEditor) == "table" then
          PartyEditor.open(S, obj)
        else
          S.objNotice = "the party editor could not be loaded"
        end
      end
      fy = fy + fieldH + 8 * s
    end

    -- ------------------------------------------------------- SIGHT RANGE
    --
    -- "Notices you walking past" is what makes a trainer a trainer, and it
    -- was unreachable from here: the cartridge files the range in a TRAINER
    -- HEADER keyed by (map label, object index), so an NPC the editor
    -- invented has no header, reads 0, and can only ever be fought by being
    -- talked to.
    --
    -- THE CARTRIDGE'S OWN NUMBER IS SHOWN whether or not it is being
    -- overridden. Editing a value you cannot see the original of is guessing,
    -- and "what did this trainer do before I touched it" is the question a
    -- reader asks the moment something plays differently.
    if obj.trainerClass then
      local cart = cartridgeSight(S, obj)
      local own = obj.sightRange
      local eff = own
      if eff == nil then eff = cart or 0 end

      stepperRow("SEES YOU",
        (eff == 0) and "talk only" or (tostring(eff) .. " block"
                                       .. (eff == 1 and "" or "s")),
        function() writeField(S, obj, "sightRange", math.max(0, eff - 1)) end,
        -- Eight is the widest the ROM's own headers use, and a sight line
        -- longer than the screen would engage from off-camera.
        function() writeField(S, obj, "sightRange", math.min(8, eff + 1)) end)
      fy = fy - 4 * s

      -- WHERE THAT NUMBER CAME FROM, and the way back to the cartridge's.
      local note
      if own == nil then
        note = cart and string.format("from the cartridge: %d block%s", cart,
                                      cart == 1 and "" or "s")
          or "this NPC has no cartridge header - set a range to make them "
             .. "notice you"
      else
        note = cart and string.format("yours: %d  -  the cartridge said %d",
                                      own, cart)
          or string.format("yours: %d  -  the cartridge had no header", own)
      end
      Kit.text("small", Kit.ellipsize("small", note, fieldW), fieldX, fy,
               PAL.muted)
      fy = fy + 15 * s
      if own ~= nil and Kit.button(fieldX, fy, fieldW, fieldH - 4 * s,
                                   "BACK TO THE CARTRIDGE'S",
                                   { font = "small" }) then
        writeField(S, obj, "sightRange", nil)
      end
      if own ~= nil then fy = fy + fieldH + 2 * s end

      Kit.text("small",
        (eff > 0)
          and "walks up and battles when you cross their line of sight"
          or "only battles when you talk to them",
        fieldX, fy, PAL.muted)
      fy = fy + 16 * s
    end
    if S.objTrainerOpen then
      S.objTrainerQuery = Kit.textfield("obj-tclass-q", fieldX, fy, fieldW,
        fieldH, S.objTrainerQuery or "", "search trainer classes...")
      fy = fy + fieldH + 4 * s
      -- CLEARING IS ONE OF THE ANSWERS. An object with no class is an
      -- ordinary NPC, and there has to be a way back from having made it a
      -- trainer.
      if obj.trainerClass then
        if Kit.button(fieldX, fy, fieldW, fieldH - 2 * s,
                      "NOT A TRAINER", { font = "small" }) then
          writeField(S, obj, "trainerClass", nil)
          writeField(S, obj, "trainerParty", nil)
          -- The team goes with it: a party on an NPC who is no longer a
          -- trainer is a table nothing will ever read, kept alive across
          -- every future save.
          writeField(S, obj, "trainerTeam", nil)
          S.objTrainerOpen = false
        end
        fy = fy + fieldH + 2 * s
      end
      local all = trainerClassIds(S)
      if #all == 0 then
        Kit.text("small", "this import has no trainer table", fieldX, fy,
                 PAL.muted)
        fy = fy + 16 * s
      end
      local shown = 0
      for _, id in ipairs(all) do
        local label = trainerLabel(S, id)
        if trainerMatches(id, label, S.objTrainerQuery or "") then
          shown = shown + 1
          if shown <= 6 then
            if Kit.button(fieldX, fy, fieldW, fieldH - 2 * s,
                          Kit.ellipsize("small", label, fieldW - 16 * s),
                          { font = "small",
                            kind = (obj.trainerClass == id) and "accent" or nil })
            then
              writeField(S, obj, "trainerClass", id)
              -- the party index belongs to the OLD class; keeping it would
              -- name a roster this class may not have
              writeField(S, obj, "trainerParty", nil)
              S.objTrainerOpen = false
            end
            fy = fy + fieldH - 2 * s + 2 * s
          end
        end
      end
      if shown == 0 and #all > 0 then
        Kit.text("small", "no trainer class matches that", fieldX, fy,
                 PAL.muted)
        fy = fy + 16 * s
      elseif shown > 6 then
        Kit.text("small", string.format("%d more - keep typing", shown - 6),
                 fieldX, fy, PAL.muted)
        fy = fy + 16 * s
      end
    end
  end

  if obj.trainerClass and obj.trainerClass ~= "" then
    -- WHICH ONE INSIDE THE CLASS, when the class holds more than one. Gen 2
    -- packs several rosters into a class and names them; the runtime reads
    -- `trainerParty` to tell them apart and the editor could not set it, so
    -- every trainer made here was silently the first.
    local parties = trainerParties(S, obj.trainerClass)
    if #parties > 1 then
      Kit.text("body", "WHICH", sideX + pad, fy + 7 * s)
      local at = math.max(1, math.min(#parties, obj.trainerParty or 1))
      if Kit.button(fieldX, fy, fieldW, fieldH,
                    string.format("%d/%d  -  %s", at, #parties,
                                  parties[at] or "?")) then
        at = (at % #parties) + 1
        writeField(S, obj, "trainerParty", at)
      end
      fy = fy + fieldH + 8 * s
    end

    local tname = field("NAME", "obj-tname", obj.trainerName, "trainer name")
    if tname ~= (obj.trainerName or "") then
      writeField(S, obj, "trainerName", tname ~= "" and tname or nil)
    end
    local party = obj.party or {}
    Kit.text("body", "TEAM", sideX + pad, fy + 7 * s)
    Kit.text("body", string.format("%d Pokemon", #party), fieldX, fy + 7 * s)
    -- Anchored to the field's RIGHT edge rather than to a constant offset from
    -- its left, so it is inside the card at every width the drawer can be.
    local addW = math.min(96 * s, fieldW / 2)
    if Kit.button(fieldX + fieldW - addW, fy, addW, fieldH, "+ MON") then
      party[#party + 1] = { species = "SPECIES_001", level = 5 }
      writeField(S, obj, "party", party)
    end
    fy = fy + fieldH + 8 * s
    for pi, mon in ipairs(party) do
      Kit.text("small", string.format("%d.", pi), sideX + pad, fy + 6 * s)
      -- Clicking the species opens a search below it rather than a modal: the
      -- roster is a list, and a modal over a list loses the place you were in.
      -- The level control keeps its width and the species name takes what is
      -- left, floored so the row never draws backwards.
      local lvW = math.min(88 * s, fieldW * 0.5)
      local sbw = math.min(26 * s, lvW / 3)
      if Kit.button(fieldX, fy, math.max(24 * s, fieldW - lvW - 4 * s), fieldH,
                    speciesLabel(S, mon.species)) then
        S.objSpeciesOpen = (S.objSpeciesOpen ~= pi) and pi or nil
        S.objSpeciesQuery = ""
      end
      if Kit.stepper(fieldX + fieldW - lvW, fy, sbw, fieldH, "-") then
        mon.level = math.max(1, (mon.level or 5) - 1)
        writeField(S, obj, "party", party)
      end
      Kit.textCenter("body", tostring(mon.level or 5),
                     fieldX + fieldW - lvW + sbw, fy + 7 * s, lvW - 2 * sbw)
      if Kit.stepper(fieldX + fieldW - sbw, fy, sbw, fieldH, "+") then
        mon.level = math.min(100, (mon.level or 5) + 1)
        writeField(S, obj, "party", party)
      end
      fy = fy + fieldH + 6 * s

      if S.objSpeciesOpen == pi then
        S.objSpeciesQuery = Kit.textfield("mon-search", fieldX, fy,
          fieldW, fieldH, S.objSpeciesQuery or "", "search species...")
        fy = fy + fieldH + 4 * s
        local okHits, hits = pcall(Ops.speciesSearch, S, S.objSpeciesQuery or "")
        hits = (okHits and hits) or {}
        -- Capped at six: this list sits INSIDE the roster, so an uncapped one
        -- would push every Pokemon after it off the panel. The search is how
        -- you narrow it, not the scroll.
        for hi = 1, math.min(6, #hits) do
          local id = hits[hi]
          if Kit.button(fieldX, fy, fieldW, fieldH - 4 * s,
                        speciesLabel(S, id)) then
            mon.species = id
            writeField(S, obj, "party", party)
            S.objSpeciesOpen = nil
          end
          fy = fy + fieldH - 2 * s
        end
        if #hits == 0 then
          Kit.text("small", "no species matches that", fieldX, fy)
          fy = fy + 16 * s
        elseif #hits > 6 then
          Kit.text("small", string.format("%d more - keep typing", #hits - 6),
                   fieldX, fy)
          fy = fy + 16 * s
        end
      end
    end
  end

  -- --------------------------------------------------------------- actions
  --
  -- FLOWED BELOW THE FIELDS, not pinned to the foot of the panel.
  --
  -- Pinned was right when this was a full tab. In the drawer the panel is
  -- handed a page taller than the drawer and scrolled -- so the foot is the
  -- bottom of that page, and DELETE sat below everything with the fields
  -- running down into it: on a short drawer TRAINER printed straight through
  -- the delete button, and reaching it meant scrolling past the end of the
  -- form. It sits under the last field now, and only falls back to the foot
  -- when the form is short enough to leave room.
  local actH = 34 * s
  local ay = math.max(fy + 10 * s, y + h - pad - actH)
  local third = (sideW - 2 * pad - 16 * s) / 3
  if Kit.button(sideX + pad, ay, third, actH, "SAVE") then
    -- SAVES THE WHOLE STORE, AND SAYS SO.
    --
    -- There is one edit file and one in-memory store behind every panel, so a
    -- save from here writes every edit in the session -- warps, tiles, voxels,
    -- the lot. That is not a side effect to be apologised for: a partial write
    -- of a Lua table file is not a thing that can be done safely, and a button
    -- that wrote only this NPC would leave the file describing a world that
    -- never existed.
    --
    -- It said "saved", which reads as "saved this NPC" beside an NPC form.
    -- Naming what actually went to disk is the difference between a reader
    -- trusting the button and wondering what else it touched.
    local ok, err = MapEdits.save(store(S))
    S.mapEditsDirty = not ok or nil
    if ok then
      local maps, added = 0, 0
      for _, m in pairs((MapEdits.mapsOf and MapEdits.mapsOf(store(S), game(S)))
                        or {}) do
        maps = maps + 1
        added = added + #((m and m.added) or {})
      end
      S.objNotice = string.format(
        "saved every map edit (%d map%s, %d added object%s) - there is one "
        .. "edit file, not one per panel", maps, maps == 1 and "" or "s",
        added, added == 1 and "" or "s")
    else
      S.objNotice = "save failed: " .. tostring(err)
    end
  end
  if not obj.added
     and Kit.button(sideX + pad + third + 8 * s, ay, third, actH, "REVERT") then
    revertObject(S, obj)
  end
  -- ARMED, THEN CONFIRMED. Undo can bring one back, but a list you are
  -- clicking around in is exactly where a stray press lands, and "the NPC I
  -- was looking at is gone" is a thing you notice several edits later. The arm
  -- clears on any other press and after a few seconds, so it can never sit
  -- waiting to fire at something else.
  local armed = S.objDeleteArmed == S.objSelected
  if Kit.button(sideX + pad + 2 * (third + 8 * s), ay, third, actH,
                armed and "SURE?" or "DELETE",
                armed and { kind = "danger" } or nil) then
    if armed then
      deleteObject(S, S.objSelected)
      S.objDeleteArmed = nil
      S.objNotice = "deleted - Ctrl-Z brings it back"
    else
      S.objDeleteArmed = S.objSelected
      S.objNotice = "press DELETE again to remove it"
    end
  elseif Kit.mouseClicked and armed then
    -- any other press disarms
    S.objDeleteArmed = nil
  end

  local note = S.objNotice or (S.mapEditsDirty and "unsaved changes" or nil)
  if note then
    Kit.text("small", note, sideX + pad, ay - 18 * s)
  end

  -- HOW TALL THIS ACTUALLY DREW, so the drawer can give it a page that fits.
  --
  -- Measured from the FLOWED bottom (`fy`), never from `ay`: `ay` falls back
  -- to the foot of the page when the form is short, so reporting it would make
  -- a taller page, which moves the foot down, which reports a taller page.
  -- The flowed height depends only on the fields, which is the thing that
  -- actually varies -- a trainer with a six-Pokemon roster and the species
  -- search open is several times the height of an item.
  local okSB, Sidebar = pcall(require, "tools.map-editor.Sidebar")
  if okSB and type(Sidebar) == "table" and Sidebar.reportHeight then
    -- THE TALLER OF THE TWO COLUMNS.  Reporting the editor's alone left a
    -- long object list running off the end of a page sized to a short form.
    Sidebar.reportHeight(S,
      math.max(listFlowH, (fy + 10 * s + actH + 30 * s) - y))
  end
end

-- TRUE when this panel took the notch, FALSE when it did not.
--
-- It used to scroll the object LIST wherever the pointer was, and Sidebar
-- offers the open panel the wheel first -- so with this tool open the drawer
-- could not scroll, and the editor column on the right, which is much taller
-- than the drawer once a sprite picker or a trainer roster is open, had no way
-- to be scrolled either.  The list keeps the wheel over the list.
function Objects.wheelmoved(S, dy)
  local r = S._objListRect
  if r then
    local okK, Kit = pcall(require, "Kit")
    if okK and type(Kit) == "table" and Kit.mouseX then
      if not (Kit.mouseX >= r[1] and Kit.mouseX <= r[1] + r[3]
              and Kit.mouseY >= r[2] and Kit.mouseY <= r[2] + r[4]) then
        return false
      end
    end
  end
  S.objScroll = math.max(0, (S.objScroll or 0) - (dy or 0))
  return true
end

function Objects.keypressed(S, key)
  if key == "delete" and S.objSelected then deleteObject(S, S.objSelected) end
end

return Objects
