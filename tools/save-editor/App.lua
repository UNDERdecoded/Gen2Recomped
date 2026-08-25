-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Save editor app shell.  Boots the game's generated Data plus a save file
-- and draws the chrome the design spec fixes (SaveEditor.dc.html): a version
-- rail, a title bar, a tab rail and a status bar, with one panel filling the
-- space between.  Panels own their tab's content; this module owns everything
-- around it.
--
-- The editor is reachable two ways and behaves the same in both:
--   * `love . --editor`      standalone window, Close quits
--   * Edit on a launcher save row (main.lua, embedded = true), Close returns
--     to the launcher with the slot list refreshed
--
-- Vertical rhythm (scaled by Kit's height/768 factor, everything else flexes):
--   0    6px   tri-colour version rail, identical to the launcher's
--   6    64px  title bar   identity, file chip, Save / Reload / Open / Close
--   70   66px  tab rail    6 tab tiles + right-aligned validation pill
--   136  flex  content     one panel per tab, 20px gutters
--   -38  38px  status bar  the last Ops message + the keyboard map

local Data = require("src.core.Data")
local TileRenderer = require("src.render.TileRenderer")
-- Face-button labels resolve through here so the Switch's physical A/B match
-- Nintendo's layout rather than SDL's positional naming (see GamepadMap).
local GamepadMap = require("src.core.GamepadMap")
local SaveIO = require("SaveIO")
local Catalog = require("Catalog")
local State = require("State")
local Kit = require("Kit")
local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local Party = require("Party")
local Boxes = require("Boxes")
local Items = require("Items")
local Events = require("Events")
local MapBrowser = require("MapBrowser")
local Dex = require("Dex")
-- chrome, not a tab panel, so deliberately kept out of PANELS below (#541)
local SpeciesPicker = require("SpeciesPicker")

local App = {}
local S
-- one loader per process: registries collide if a second load re-registers
-- vanilla records over an already-merged Data
local mods
local mouseClicked = false
-- Wheel notches queued by App.wheelmoved since the last draw, handed to Kit
-- there like mouseClicked is: LOVE delivers events before love.draw, so a
-- notch is always spent by the frame that follows it (#595).
local wheelY = 0

-- Gamepad virtual cursor state.  Declared up here with the other frame-input
-- locals rather than beside its own functions further down, because App.unload
-- (above them) has to reset it -- a local declared later is not in scope there
-- and would silently resolve to a nil global.
local pad = {
  x = 0, y = 0,
  active = false,
  inited = false,
  axis = { leftx = 0, lefty = 0, righty = 0 },
  dirs = {},
  scroll = 0,
}
local lastMouseX, lastMouseY

-- Which game's cache Data was loaded from.  main.lua checks this before
-- opening the editor on a save from the other version, because the two
-- caches cannot both be mounted in one process (see CacheFs.mountVersion).
App.dataVersion = nil

local TABS = {
  { id = "party",  glyph = "PT", label = "PARTY" },
  { id = "boxes",  glyph = "BX", label = "BOXES" },
  { id = "items",  glyph = "IT", label = "ITEMS" },
  { id = "events", glyph = "EV", label = "EVENTS" },
  { id = "map",    glyph = "MP", label = "MAP" },
  { id = "dex",    glyph = "DX", label = "DEX" },
  -- The map editor rides in this shell rather than opening a second window:
  -- the pad cursor, the console keyboard applet, the modal shield and the DPI
  -- layout are all solved here already, and a parallel tool would have to
  -- solve them again and get them wrong. MAP picks the map; OBJECTS edits what
  -- stands on it.
  { id = "objects", glyph = "OB", label = "OBJECTS" },
  { id = "voxels",  glyph = "VX", label = "VOXELS" },
  { id = "scripts", glyph = "SC", label = "SCRIPTS" },
  -- WARPS is last because it is the tab that can change which map is selected
  -- -- creating a map here makes it current -- and a tab that moves the ground
  -- under the others reads better as the end of the row than the middle.
  { id = "warps",   glyph = "WP", label = "WARPS" },
}

-- Loaded through pcall: the map editor lives outside tools/save-editor, so a
-- checkout or a package that does not carry it must lose the OBJECTS tab
-- rather than fail to open the save editor at all.
local okObjects, ObjectsPanel = pcall(require, "tools.map-editor.panels.Objects")
if not okObjects then ObjectsPanel = nil end
local okVoxels, VoxelsPanel = pcall(require, "tools.map-editor.panels.Voxels")
if not okVoxels then VoxelsPanel = nil end
local okScripts, ScriptsPanel = pcall(require, "tools.map-editor.panels.Scripts")
if not okScripts then ScriptsPanel = nil end
local okWarps, WarpsPanel = pcall(require, "tools.map-editor.panels.Warps")
if not okWarps then WarpsPanel = nil end
local okPreview, PreviewPanel = pcall(require, "tools.map-editor.panels.Preview")
if not okPreview then PreviewPanel = nil end
-- The tools as a DRAWER over the map rather than tabs beside it. Loaded the
-- same guarded way: without it the map editor still opens, with the tools back
-- on the rail.
local okWilds, WildsPanel = pcall(require, "tools.map-editor.panels.Wilds")
if not okWilds then WildsPanel = nil end
local okTiles, TilesPanel = pcall(require, "tools.map-editor.panels.Tiles")
if not okTiles then TilesPanel = nil end
local okColl, CollisionPanel = pcall(require,
                                     "tools.map-editor.panels.Collision")
if not okColl then CollisionPanel = nil end
local okPacks, PacksPanel = pcall(require, "tools.map-editor.panels.Packs")
if not okPacks then PacksPanel = nil end
local okHistory, History = pcall(require, "tools.map-editor.History")
if not okHistory then History = nil end
local okSidebar, Sidebar = pcall(require, "tools.map-editor.Sidebar")
if not okSidebar then Sidebar = nil end

local PANELS = {
  party = Party, boxes = Boxes, items = Items,
  events = Events, map = MapBrowser, dex = Dex,
  preview = PreviewPanel,
  objects = ObjectsPanel,
  voxels = VoxelsPanel,
  scripts = ScriptsPanel,
  warps = WarpsPanel,
  wilds = WildsPanel,
  tiles = TilesPanel,
  collision = CollisionPanel,
}

-- and if it did not load, take its chip back out. A tab that opens an empty
-- panel is worse than no tab: it reads as the feature being broken rather than
-- absent, which is a support question instead of a non-event.
for i = #TABS, 1, -1 do
  local id = TABS[i].id
  if (id == "objects" and not ObjectsPanel)
     or (id == "voxels" and not VoxelsPanel)
     or (id == "scripts" and not ScriptsPanel)
     or (id == "warps" and not WarpsPanel) then
    table.remove(TABS, i)
  end
end

-- AND THE SAME FOR THE DRAWER'S TOOLS. A tool button that opens an empty
-- drawer reads as the feature being broken rather than absent, which is a
-- support question instead of a non-event -- the same argument as the tab
-- pruning above, applied to the other list of panels.
if Sidebar and type(Sidebar.TOOLS) == "table" then
  for i = #Sidebar.TOOLS, 1, -1 do
    if PANELS[Sidebar.TOOLS[i].id] == nil then
      table.remove(Sidebar.TOOLS, i)
    end
  end
end

-- THE MAP EDITOR IS A MODE OF THIS SHELL, NOT A SECOND ONE.
--
-- Everything the map editor needs from a window -- the pad cursor, the console
-- keyboard applet, the modal shield, the DPI layout, the gamepad and joystick
-- plumbing, the deferred close -- is solved here and nowhere else. A parallel
-- tool would have to solve all of it again and would get some of it wrong; the
-- Switch and Android paths in particular are not obvious and are not tested
-- twice. So the map editor is this shell with a different tab set, a different
-- title, and a Save that writes the edit store instead of a .sav.
--
-- Every branch below is guarded on `S.mode`, and save mode is the default, so
-- an editor opened on a save behaves exactly as it did before.
local MAP_TABS = {
  { id = "preview", glyph = "MA", label = "MAP" },
  { id = "warps",   glyph = "WP", label = "WARPS" },
  { id = "objects", glyph = "OB", label = "NPCs" },
  { id = "scripts", glyph = "SC", label = "SCRIPTS" },
  { id = "voxels",  glyph = "VX", label = "VOXELS" },
}
for i = #MAP_TABS, 1, -1 do
  if PANELS[MAP_TABS[i].id] == nil then table.remove(MAP_TABS, i) end
end

-- WITH THE DRAWER, THE MAP IS THE ONLY TAB.
--
-- Every one of those four tools works on the map -- the warp editor puts a
-- door at the selected cell, the NPC editor drops a person next to it, the
-- voxel editor shapes the ground under it -- and a tab takes the map off the
-- screen to show you the tool for changing it. So they move into a drawer over
-- the map and the rail keeps one entry, which is also the whole rail's job in
-- this mode: there is nothing to switch between any more.
--
-- The old rail is kept as the fallback for a build with no Sidebar.lua, so the
-- tools are never simply unreachable.
if Sidebar then
  MAP_TABS = { { id = "preview", glyph = "MA", label = "MAP" } }
end

-- The tab set for whichever mode is up. Read by the rail, the pad's tab
-- cycling and the panel dispatch, so there is one answer rather than three.
local function activeTabs()
  return (S and S.mode == "map") and MAP_TABS or TABS
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

-- A NEW-GAME STUB THAT A MOD CANNOT TAKE THE TOOL DOWN WITH.
--
-- These two stubs ARE edited and saved, so `save.new_game` still runs over
-- them: a total conversion reshaping spawn, party and money belongs in a save
-- the user is about to write. But the handler is third-party code running
-- inside an editor, and one that assumes a booted game -- reaching for a
-- global the engine only sets during a real boot, say -- would otherwise stop
-- the save editor from opening at all.
local function newGameStub()
  local SaveData = require("src.core.SaveData")
  local ok, save = pcall(SaveData.newGame)
  if ok and type(save) == "table" then return save end
  print("save editor: a mod's save.new_game handler failed ("
        .. tostring(save) .. ") -- falling back to the unhooked stub")
  local ok2, bare = pcall(SaveData.newGame, { noHooks = true })
  if ok2 and type(bare) == "table" then return bare end
  return {
    meta = { mods = {} },
    player = {}, flags = {}, inventory = {}, party = {}, box = {},
    pokedex = { seen = {}, owned = {} },
  }
end

-- Apply a load attempt for `path` into the current State (S must exist).
local function applyLoaded(path, statusVerb)
  statusVerb = statusVerb or "Loaded"
  S.path = path
  local existed = fileExists(path)
  local save, err = SaveIO.load(path)
  if save then
    S.save = save
    S.status = statusVerb .. " " .. path
    S.mapId = save.player.map
    S.loadError = false
    S.allowSave = true
  elseif existed then
    -- File is present but SaveIO.load couldn't decode it: treat it as a
    -- real (corrupt) save, not a missing one. Editing a stub here is fine,
    -- but Save must stay disabled so we never clobber the corrupt file
    -- until the user fixes it and Reload succeeds.
    S.save = newGameStub()
    S.status = "Corrupt save at " .. path .. " (" .. tostring(err) ..
      "),  Save disabled, use Reload after fixing the file"
    S.mapId = S.save.player.map
    S.loadError = true
    S.allowSave = false
  else
    S.save = newGameStub()
    S.status = "No save at " .. path .. " (" .. tostring(err) ..
      "),  editing new game stub"
    S.mapId = S.save.player.map
    S.loadError = false
    S.allowSave = true
  end
  S.dirty = false
  S._quitArmed = false
  S._openArmed = false
  S.editingMon = nil
  Ops.disarm(S)
  local boxes = require("src.pokemon.Boxes").ensure(S.save)
  -- Imported .sav box mons have no stat block (box_struct stops before
  -- MON_STATS).  The game derives them in SaveData.validate; the editor
  -- only validates a copy, so hydrate here for Boxes/Party/MonEditor.
  local Stats = require("src.pokemon.Stats")
  local function ensureStats(mon)
    Stats.ensure(Data.pokemon and Data.pokemon[mon.species], mon)
  end
  for _, mon in ipairs(S.save.party or {}) do ensureStats(mon) end
  for _, box in ipairs(boxes) do
    for _, mon in ipairs(box) do ensureStats(mon) end
  end
  if S.save.daycare and S.save.daycare.mon then
    ensureStats(S.save.daycare.mon)
  end
  -- what the running game would quarantine, computed on a copy so the
  -- editor never mutates the file behind the user's back
  local SaveData = require("src.core.SaveData")
  local probe = require("src.mods.Merge").deepCopy(S.save)
  S.validation = SaveData.validate(probe, Data)
  if not SaveData.emptyReport(S.validation) then
    S.status = S.status .. string.format(",  game would quarantine: %d mons, %d items, %d maps",
      #S.validation.lostMons, #S.validation.lostItems, #S.validation.remappedMaps)
  end
end

-- pathOverride lets tests point App.load at a scratch file instead of the
-- real default save path (used to exercise the corrupt-save branch below).
-- opts carries what only the launcher knows: which game the save belongs to,
-- its slot id, and where Close should go back to.
function App.load(pathOverride, opts)
  opts = opts or {}
  S = State.new()
  S.data = Data
  -- "save" (the default) or "map". Set before anything else on S, because the
  -- tab set, the title bar and Save all branch on it.
  S.mode = opts.mode or "save"
  S.version = opts.version
  S.slotId = opts.slotId
  S.embedded = opts.embedded or false
  S.onClose = opts.onClose
  -- the same mod set the game loads, merged into Data before the catalogs
  -- build, so modded species/items/moves are editable and MonOps stops
  -- asserting on them
  if not mods then
    -- One loader per editor session.  A previous session leaves Data holding
    -- that session's merged registries (and possibly the other game's cache),
    -- and a second builtin registration over them collides -- "statuses
    -- already registered: FRZ".  _pristineKeys only exists once Data has been
    -- loaded at least once, so it doubles as the "needs evicting" marker.
    if Data._pristineKeys then Data:unloadGenerated() end
    Data:load()
    local ModLoader = require("src.mods.Loader")
    mods = ModLoader.new()
    mods:load(Data)
    -- AND THE EDIT OVERLAY AGAIN, EXACTLY AS Game:load DOES.
    --
    -- `Data:load` laid it down; `mods:load` has just patched over it. A map
    -- pack exported from this editor and installed back into it carries the
    -- whole `objects` array of every map it touches, as it stood at export --
    -- so `maps:patch` replaces the def, and every edit made SINCE that export
    -- disappears from the table the editor is about to draw.
    --
    -- THE EDITOR NEEDS THIS MORE THAN THE GAME DOES, not less. In the game a
    -- missing NPC is a bug you notice; here the editor opens showing the
    -- pack's snapshot, the reader edits THAT, and their next save is written
    -- against a picture of the world that is one export out of date. The
    -- report was "I made edits, they appeared in game, and when I reopened
    -- the editor they were gone" -- which is this line, missing.
    --
    -- Same call, same reason, same order: after the merge, before anything
    -- reads the tables.
    if Data.applyMapEditorOverlay then
      Data:applyMapEditorOverlay("editor, after mods")
    end
    App.dataVersion = opts.version
  end
  S.mods = mods
  S.cat = Catalog.build(Data)
  if S.mode == "map" then
    -- Open on the map picker, and hand the Preview panel the tool list the
    -- shell actually loaded. It offers a button per entry, so a panel whose
    -- require failed must not be in it -- a button that opens nothing reads as
    -- the feature being broken rather than absent.
    S.tab = MAP_TABS[1] and MAP_TABS[1].id or "preview"
    S.tools = {}
    if PreviewPanel then
      for _, tool in ipairs(PreviewPanel.TOOLS) do
        if PANELS[tool.tab] then S.tools[#S.tools + 1] = tool end
      end
    end
    S.mapEdits = nil       -- loaded lazily by the first panel that needs it
  end
  local modRoots = {}
  for _, mod in ipairs(S.mods:status().loaded) do
    modRoots[#modRoots + 1] = mod.path
  end
  S.events = Catalog.scrapeEvents("data/scripts", "data/generated/trainer_headers.lua",
                                  nil, modRoots)

  if S.mode == "map" then
    -- NO SAVE FILE IS READ. The map editor edits the game's maps, not anyone's
    -- playthrough, and reaching for the default save path here would produce
    -- either a "No save at ..." status the user cannot act on, or -- worse --
    -- a real save loaded and sitting one Ctrl+S away from being written by a
    -- tool that has no business touching it.
    --
    -- A stub still exists because the shell's chrome reads `S.save` (the tab
    -- rail's counters, the status bar). It is never written: App.save branches
    -- to the edit store in this mode, and there is no path to write to.
    --
    -- AND NO MOD HOOKS. `SaveData.newGame` ends in
    -- `Runtime.call("save.new_game", ...)`, so building this stub announced a
    -- new playthrough to every installed mod -- from inside the map editor,
    -- with no game booted and no world for a handler to reach. That is what
    -- `mods/gen2online/main.lua:54: attempt to index global 'Gen2Compat'`
    -- was: a new-game handler running somewhere its author could not have
    -- expected, and taking the editor down on the way.
    --
    -- Safe here in a way it would not be at the two call sites above: that
    -- stub is EDITED AND SAVED, so a total conversion's reshaping of spawn,
    -- party and money belongs in it. This one is never written -- see the
    -- paragraph above -- so it wants the shape and nothing else.
    --
    -- pcall as well. `noHooks` only silences OUR dispatch; a mod that has
    -- replaced SaveData.newGame itself is still in this call, and the map
    -- editor refusing to open is never the right answer to a third-party bug.
    local SaveData = require("src.core.SaveData")
    local okStub, stub = pcall(SaveData.newGame, { noHooks = true })
    if not okStub then
      print("map editor: new-game stub failed (" .. tostring(stub)
            .. ") -- using a bare one")
      stub = {
        meta = { mods = {} },
        player = {}, flags = {}, inventory = {}, party = {}, box = {},
        pokedex = { seen = {}, owned = {} },
      }
    end
    S.save = stub
    S.path = nil
    S.allowSave = false
    S.loadError = false
    S.mapId = S.save.player and S.save.player.map or nil
    S.status = "Map editor,  pick an area on the left and choose a tool"
    return
  end

  applyLoaded(pathOverride or SaveIO.defaultPath(), "Loaded")
end

-- Switch to another save file (Open button, drag-drop, or --save arg).
-- If there are unsaved edits, the first call arms a confirm; call again
-- (or pass force=true) to discard and open.
function App.openPath(path, force)
  if not path or path == "" then return false end
  if not S then return false end
  -- Map mode has no save file and no business loading one. Reached from the
  -- Open button (which map mode does not draw) and from a dropped file, which
  -- it cannot refuse -- so the refusal lives here, at the one door both use.
  if S.mode == "map" then
    S.status = "The map editor does not open save files"
    return false
  end
  if S.dirty and not force and not S._openArmed then
    S._openArmed = true
    S.status = "Unsaved changes,  open again to discard and load " .. path
    return false
  end
  applyLoaded(path, "Opened")
  return true
end

function App.chooseAndOpen()
  local path = SaveIO.choosePath()
  if path then
    App.openPath(path)
  else
    local osName = love and love.system and love.system.getOS
      and love.system.getOS()
    if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then
      S.status = "File picker unavailable,  drop a save.lua onto the window"
    end
  end
end

function App.filedropped(file)
  if not (file and S) then return end
  local path = file.getFilename and file:getFilename() or nil
  if not path or path == "" then
    S.status = "Could not read dropped file path"
    return
  end

  -- A PNG DROPPED ON THE MAP EDITOR IS A CHARACTER SHEET.
  --
  -- It is the gesture people already have for "here is my art", and it is the
  -- one that arrives with no panel open -- so it goes through the same
  -- function the NPC editor's IMPORT A PNG button calls rather than being a
  -- second implementation of it. Before `openPath`, because openPath's answer
  -- to anything in map mode is "the map editor does not open save files",
  -- which is true and unhelpful when what was dropped is plainly not one.
  if S.mode == "map" and path:lower():match("%.png$") then
    local okP, Objects = pcall(require, "tools.map-editor.panels.Objects")
    if okP and type(Objects) == "table" and Objects.importSheet then
      local id, why = Objects.importSheet(S, path)
      S.status = id and ("imported " .. id .. " - pick it on an NPC")
        or ("could not import that sheet: " .. tostring(why))
      return
    end
  end

  App.openPath(path)
end

-- Test hook: App.load keeps its state in a module-local so headless tests
-- can drive App.load/App.draw against a scratch path and then inspect the
-- resulting flags/status without loving a real save file.
function App.getState()
  return S
end

-- Tear the editor down far enough that a later App.load rebuilds from
-- scratch.  main.lua calls this after Close so the next Edit -- possibly on
-- the other game's save -- re-runs Data:load against whatever cache is
-- mounted by then, instead of reusing this session's merged registries.
function App.unload()
  S = nil
  mods = nil
  App.dataVersion = nil
  -- Kit is never evicted from package.loaded, so a Close taken while a text
  -- field still owns focus would leak Kit.focus and a raised soft keyboard
  -- (against a rect that is gone) into the launcher and the next session
  -- (#529).  A Close taken on the frame the species picker went up would
  -- likewise leave its modal shield raised, and the next session would open
  -- deaf to every click (#541).
  Kit.blur()
  Kit.blockClicks = false
  -- Same reasoning for the pad cursor: a direction held at the moment Close
  -- was taken never sees its release event (main.lua stops forwarding to the
  -- editor the instant editorMode drops), so the next session would open with
  -- the cursor already sliding. Position is deliberately kept -- reopening
  -- where you left the pointer is the friendlier behaviour.
  pad.dirs = {}
  pad.axis = { leftx = 0, lefty = 0, righty = 0 }
  pad.scroll = 0
end

function App.save()
  if S.mode == "map" then
    local MapEdits = require("tools.map-editor.MapEdits")
    if not S.mapEdits then
      S.status = "Nothing to save yet"
      return true
    end
    local okSave, err = MapEdits.save(S.mapEdits)
    if okSave then
      S.mapEditsDirty = nil
      S._quitArmed = false
      S.status = "Map edits saved"
      return true
    end
    S.status = "Map edits could not be saved: " .. tostring(err)
    return false
  end
  if not S.allowSave then
    return Ops.say(S, "Save disabled,  corrupt save loaded; fix the file and Reload first")
  end
  local ok, err = SaveIO.save(S.path, S.save)
  if ok then
    S.dirty = false
    S._quitArmed = false
    Ops.disarm(S)
    S.status = "Saved " .. S.path
    return true
  end
  S.status = "Save failed: " .. tostring(err)
  return false
end

function App.reload()
  local save, err = SaveIO.load(S.path)
  if save then
    S.save = save
    S.dirty = false
    S.loadError = false
    S.allowSave = true
    S._quitArmed = false
    S._openArmed = false
    S.editingMon = nil
    S.status = "Reloaded " .. S.path
    require("src.pokemon.Boxes").ensure(S.save)
    return true
  end
  S.status = "Reload failed: " .. tostring(err)
  return false
end

-- Close: back to the launcher when hosted there, otherwise quit.  Unsaved
-- edits arm a confirm exactly like Open does, so leaving can't lose work.
--
-- The teardown itself is DEFERRED to the end of the frame (App.draw calls
-- finishClose below).  Close is dispatched from inside drawTitleBar, and the
-- host's onClose runs App.unload, which drops S -- doing that inline left the
-- rest of the frame drawing against a nil state.
function App.close()
  -- Map mode has its own dirty flag, and the guard is the whole point of the
  -- flag: closing with unsaved map edits would lose them exactly as silently
  -- as closing with an unsaved party would.
  local dirty = (S.mode == "map") and S.mapEditsDirty or S.dirty
  if dirty and not S._quitArmed then
    S._quitArmed = true
    S.status = "Unsaved changes,  Save first or click Close again to discard"
    return false
  end
  S._closeRequested = true
  return true
end

local function finishClose()
  local embedded, onClose = S.embedded, S.onClose
  S._closeRequested = false
  if embedded and onClose then
    onClose()
  elseif love and love.event then
    love.event.quit()
  end
end

-- ------------------------------------------------------- gamepad virtual cursor
-- This editor is an immediate-mode UI driven entirely by one (x, y, clicked)
-- triple, and until now that triple could only come from love.mouse.  That was
-- fine while `love . --editor` was the only way in; it stopped being fine when
-- the launcher's Edit button made the editor reachable on the Switch, which has
-- no pointer of any kind.  The editor opened there and then accepted no input
-- at all -- not a stick, not the D-pad, not a face button -- so the only exit
-- was killing the app, and the tool read as "crashed".
--
-- Rather than teach Kit about a second input model, feed the same triple from a
-- virtual cursor, exactly as the launcher does (RomImporter:_activatePadCursor).
-- Everything downstream -- every panel, every button, the species picker --
-- keeps working with no changes.
local PAD_DEAD = 0.28
local PAD_SPEED = 560       -- px/s at full stick deflection
local PAD_DPAD_SPEED = 420
-- Right-stick scroll accumulates into whole wheel notches, because that is the
-- only scroll currency Kit has.
local PAD_SCROLL_RATE = 8   -- notches/s at full deflection
-- `pad` and lastMouse* are declared with the other frame-input locals near the
-- top of this file; see the note there.

local function padActivate()
  if not pad.inited then
    local w, h = love.graphics.getDimensions()
    pad.x, pad.y = w * 0.5, h * 0.5
    pad.inited = true
  end
  pad.active = true
end

local function padCycleTab(delta)
  if not S then return end
  local tabs = activeTabs()
  local idx = 1
  for i, t in ipairs(tabs) do
    if t.id == S.tab then idx = i break end
  end
  S.tab = tabs[((idx - 1 + delta) % #tabs) + 1].id
  -- Same bookkeeping the tab rail does on a click: a focused field must not
  -- keep eating keys for a tab that is no longer showing, and an armed
  -- destructive action must not survive the switch.
  Kit.blur()
  Ops.disarm(S)
end

local function padUpdate(dt)
  if not pad.active or not S then return end
  local w, h = love.graphics.getDimensions()
  local vx, vy = 0, 0
  local ax, ay = pad.axis.leftx or 0, pad.axis.lefty or 0
  if math.abs(ax) > PAD_DEAD then vx = vx + ax * PAD_SPEED end
  if math.abs(ay) > PAD_DEAD then vy = vy + ay * PAD_SPEED end
  if pad.dirs.left  then vx = vx - PAD_DPAD_SPEED end
  if pad.dirs.right then vx = vx + PAD_DPAD_SPEED end
  if pad.dirs.up    then vy = vy - PAD_DPAD_SPEED end
  if pad.dirs.down  then vy = vy + PAD_DPAD_SPEED end
  pad.x = math.max(0, math.min(w, pad.x + vx * dt))
  pad.y = math.max(0, math.min(h, pad.y + vy * dt))

  -- Right stick scrolls whatever list the cursor is over, via the same path a
  -- wheel notch takes.  Fractional travel is carried between frames so a
  -- half-deflected stick still scrolls smoothly instead of not at all.
  local ry = pad.axis.righty or 0
  if math.abs(ry) > PAD_DEAD then
    pad.scroll = pad.scroll - ry * PAD_SCROLL_RATE * dt
    while pad.scroll >= 1 do pad.scroll = pad.scroll - 1; App.wheelmoved(0, 1) end
    while pad.scroll <= -1 do pad.scroll = pad.scroll + 1; App.wheelmoved(0, -1) end
  else
    pad.scroll = 0
  end
end

-- Drawn last, above everything including the species picker, so it is never
-- hidden by the layer it is about to click.
local function padDraw()
  if not pad.active then return end
  local x, y = pad.x, pad.y
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.polygon("fill", x + 2, y + 2, x + 2, y + 22,
    x + 8, y + 16, x + 14, y + 26)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.polygon("fill", x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24)
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.setLineWidth(1)
  love.graphics.polygon("line", x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24)
  love.graphics.pop()
end

function App.gamepadpressed(button)
  if not S then return end
  padActivate()
  -- Through GamepadMap: SDL names face buttons by POSITION, and Nintendo's A
  -- and B sit opposite the Xbox layout SDL is named after, so on a Switch the
  -- button physically labelled A arrives as SDL "b".  Testing the raw name
  -- would confirm on the button labelled B.
  local action = GamepadMap.mapGamepadButton(button)
  if action == "a" then
    -- Click at the cursor; Kit consumes it on the next draw, which is the same
    -- path a real tap takes.
    mouseClicked = true
  elseif action == "b" then
    App.keypressed("escape")
  elseif action == "start" then
    App.save()
  elseif action == "select" then
    App.close()
  elseif button == "leftshoulder" then
    padCycleTab(-1)
  elseif button == "rightshoulder" then
    padCycleTab(1)
  elseif button == "dpup" then pad.dirs.up = true
  elseif button == "dpdown" then pad.dirs.down = true
  elseif button == "dpleft" then pad.dirs.left = true
  elseif button == "dpright" then pad.dirs.right = true
  end
end

function App.gamepadreleased(button)
  if button == "dpup" then pad.dirs.up = nil
  elseif button == "dpdown" then pad.dirs.down = nil
  elseif button == "dpleft" then pad.dirs.left = nil
  elseif button == "dpright" then pad.dirs.right = nil
  end
end

-- Only the three axes the cursor actually uses; triggers and the unused right
-- X would otherwise arm the cursor from a resting pad's noise.
local PAD_AXES = { leftx = true, lefty = true, righty = true }

function App.gamepadaxis(axis, value)
  if not PAD_AXES[axis] then return end
  pad.axis[axis] = value
  if math.abs(value or 0) > PAD_DEAD then padActivate() end
end

-- Raw-stick fallback, for a pad SDL has no game-controller mapping for (the
-- Linux handhelds this editor also ships to).  Skipped when SDL DOES map the
-- pad, or one press would arrive twice and click twice.
function App.joystickpressed(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  local name = GamepadMap.mapRawToGamepadButton(button)
  if name then return App.gamepadpressed(name) end
end

function App.joystickaxis(joystick, axis, value)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  local names = { [1] = "leftx", [2] = "lefty", [4] = "righty" }
  local name = names[axis]
  if name then return App.gamepadaxis(name, value) end
end

function App.joystickhat(joystick, hat, direction)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  pad.dirs.up    = direction:find("u") ~= nil or nil
  pad.dirs.down  = direction:find("d") ~= nil or nil
  pad.dirs.left  = direction:find("l") ~= nil or nil
  pad.dirs.right = direction:find("r") ~= nil or nil
  if direction ~= "c" then padActivate() end
end

-- Test/host hook: where the editor thinks the pointer is right now.
function App._pointer()
  if pad.active then return pad.x, pad.y, true end
  return nil, nil, false
end

function App.update(dt)
  -- Immediate-mode UI: nothing to simulate per-frame; input is sampled
  -- directly in App.draw() via Kit.beginFrame. Tile animation (water,
  -- flowers) still needs ticking so the Map tab isn't static.
  TileRenderer.tick()
  padUpdate(dt or 0)
  -- A mobile pack pick lands in the save dir seconds after the picker closes;
  -- MapPacks owns both halves of that (see its beginAdd/consumePending).
  if S then
    local okMP, MapPacks = pcall(require, "tools.map-editor.MapPacks")
    if okMP and type(MapPacks) == "table" then
      pcall(MapPacks.consumePending, S)
    end
  end
end

function App.mousepressed(x, y, button)
  if button == 1 then mouseClicked = true end
end

-- ------------------------------------------------------------------- pinch
-- TWO FINGERS, AND ONLY TWO FINGERS.
--
-- One finger already works and always has: SDL synthesizes mouse events for
-- the primary touch, so a tap is a click and a drag is a drag, through the
-- same (x, y, clicked) triple the rest of this editor runs on. Nothing here
-- interferes with that -- these handlers record contact points and act on the
-- SECOND one, which is the gesture a mouse cannot make and the wheel was
-- standing in for.
--
-- Reported as a RATIO, not a distance: the two things it drives -- the flat
-- view's `pvZoom` and the 3D camera's `pvDist` -- are both multiplicative, and
-- a ratio is the one currency that means the same thing at every scale.
local touches = {}
local pinchPrev = nil

local function pinchSpan()
  local a, b = nil, nil
  for _, pt in pairs(touches) do
    if not a then a = pt elseif not b then b = pt else return nil end
  end
  if not (a and b) then return nil end
  local dx, dy = a.x - b.x, a.y - b.y
  local d = math.sqrt(dx * dx + dy * dy)
  return d > 1 and d or nil
end

function App.touchpressed(id, x, y)
  touches[id] = { x = x, y = y }
  -- A new finger restarts the measurement rather than continuing it: the span
  -- jumps when the pair changes, and feeding that jump in as a ratio is a
  -- zoom lurch.
  pinchPrev = pinchSpan()
end

function App.touchmoved(id, x, y)
  local pt = touches[id]
  if not pt then return end
  pt.x, pt.y = x, y
  local span = pinchSpan()
  if not (span and pinchPrev) then pinchPrev = span return end
  local ratio = span / pinchPrev
  pinchPrev = span
  -- Ignore the noise floor; fingers resting on glass jitter by a pixel or two
  -- and a live ratio would drift the camera while nobody is moving.
  if ratio > 0.999 and ratio < 1.001 then return end
  if not S then return end
  local panel = PANELS[S.tab]
  if panel and panel.pinch then pcall(panel.pinch, S, ratio) end
end

function App.touchreleased(id, x, y)
  touches[id] = nil
  pinchPrev = pinchSpan()
end

function App.textinput(text)
  Kit.textinput(text)
end

-- ------------------------------------------------------------------ chrome
-- The file chip: the single source of truth for "which file am I editing".
-- The path truncates from the LEFT so the filename is always readable, and
-- an amber dot plus the word UNSAVED calls out dirty state from any tab.
local function drawFileChip(x, y, w, h)
  local s = Kit.scale
  Theme.row(x, y, w, h, 10 * s, 0.6)
  local inset = 14 * s
  local dot = 8 * s
  local cx = x + inset
  if S.dirty then
    Theme.col(PAL.yellow, 1)
    if love.graphics.circle then
      love.graphics.circle("fill", cx + dot / 2, y + h / 2, dot / 2)
    else
      love.graphics.rectangle("fill", cx, y + h / 2 - dot / 2, dot, dot)
    end
    cx = cx + dot + 8 * s
  end
  local label = S.dirty and "UNSAVED" or "SAVED"
  local labelW = Kit.textWidth("tiny", label)
  Kit.textRight("tiny", label, x + w - inset, y + (h - Kit.textHeight("tiny")) / 2,
    S.dirty and PAL.yellow or PAL.caption)
  local avail = (x + w - inset - labelW - 10 * s) - cx
  local shown = Theme.ellipsizeLeft(Kit.fonts.mono, S.path or "(no file)", avail)
  Kit.text("mono", shown, cx, y + (h - Kit.textHeight("mono")) / 2, PAL.detail)
end

local function drawTitleBar(x, y, w, h)
  local s = Kit.scale
  local inset = 22 * s
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y + h - 1, w, 1)

  local cx = x + inset
  -- SE badge, the same rounded-square chip shape the launcher's tabs use
  local badge = 34 * s
  local by = y + (h - badge) / 2
  local mapMode = S.mode == "map"
  Theme.gradRounded(cx, by, badge, badge, 9 * s, PAL.chipTop, PAL.chipBot, 1, 1)
  Kit.textCenter("tab", mapMode and "ME" or "SE", cx,
    by + (badge - Kit.textHeight("tab")) / 2, badge, { 159, 180, 221 })
  cx = cx + badge + 10 * s

  -- The right-aligned action cluster is laid out from the right edge inward
  -- BEFORE anything on the left is drawn: the buttons are the one thing in
  -- this bar that must always be reachable, so on a phone the identity block,
  -- the version chip and the file chip are what yield.  Measuring them last
  -- is why they used to paint straight through the buttons (#497).
  local btnH = 38 * s
  local btnY = y + (h - btnH) / 2
  local rightEdge = x + w - inset
  local gap = 8 * s
  local closeW = 22 * s + Kit.textWidth("button", "Close")
  -- THE MANUAL, as a chip in the one strip nothing covers. A square `?` and
  -- not a word: it sits beside Close on every window width, and a labelled
  -- "HELP" is the first control to be squeezed off a phone -- which is the
  -- width where somebody most needs it. Map mode only; the save editor's
  -- controls are a list of fields and have nothing to explain.
  local helpW = mapMode and (38 * s) or 0
  -- Reload and Open... are operations on a SAVE FILE. The map editor has none
  -- -- its edits live in the edit store, and "Open..." there would mean a file
  -- picker onto a file the user never chose. Absent rather than disabled: a
  -- greyed control invites a click and then explains itself, and there is
  -- nothing here to explain.
  local openW = mapMode and 0 or (22 * s + Kit.textWidth("button", "Open..."))
  local reloadW = mapMode and 0 or (22 * s + Kit.textWidth("button", "Reload"))

  -- EXPORT AND THE VOXEL SOURCE LIVE UP HERE, beside Save.
  --
  -- They were in the map panel's tools column, which is a column that scrolls,
  -- can be covered by a drawer, and is gone entirely on a narrow window -- and
  -- all three of these say the same kind of thing: what happens to the WORK.
  -- Save keeps it for you, Export keeps it for somebody else, and the source
  -- says whose world the heights being kept belong to.  The title bar is where
  -- this editor already puts that, and it is the one strip nothing covers.
  local voxLabel, voxW, exportW, importW, assetW, resetW = nil, 0, 0, 0, 0, 0
  if mapMode then
    exportW = 22 * s + Kit.textWidth("button", "EXPORT")
    importW = 22 * s + Kit.textWidth("button", "IMPORT")
    assetW = 22 * s + Kit.textWidth("button", "ASSETS")
    -- SIZED TO THE ARMED LABEL, ALWAYS. "RESET?" is wider than "RESET", and a
    -- button measured to whichever word it is showing changes width under the
    -- pointer between the arming press and the confirming one -- so the second
    -- press lands somewhere else. Reserve the wider of the two and the control
    -- stands still.
    resetW = 22 * s + math.max(Kit.textWidth("button", "RESET MAP"),
                               Kit.textWidth("button", "RESET?"))
    local okV, VC = pcall(require, "tools.map-editor.VoxelClasses")
    if okV and type(VC) == "table" and VC.sourceFor then
      local okS, cur = pcall(VC.sourceFor, S.voxelSource)
      voxLabel = (okS and cur and cur.label) or "VOXELS"
      -- Capped, and ellipsized to the cap: a mod may be called
      -- STADIUM2_OVERWORLD_MODELS, and a button sized to that name is the
      -- whole right-hand half of the bar.
      voxLabel = Kit.ellipsize("button", tostring(voxLabel), 150 * s)
      voxW = 30 * s + Kit.textWidth("button", voxLabel)
    end
  end

  local saveLabel, saveKind, saveEnabled = "SAVED", "disabled", false
  if mapMode then
    saveLabel = S.mapEditsDirty and "SAVE EDITS" or "SAVED"
    if S.mapEditsDirty then saveKind, saveEnabled = "primary", true end
  elseif not S.allowSave then
    saveLabel = "SAVE LOCKED"
  elseif S.dirty then
    saveLabel, saveKind, saveEnabled = "SAVE", "primary", true
  end
  local saveW = 30 * s + Kit.textWidth("button", saveLabel)

  local closeX = rightEdge - closeW
  local helpX = mapMode and (closeX - gap - helpW) or closeX
  local openX = closeX - gap - openW
  local reloadX = openX - gap - reloadW
  -- In map mode Save sits straight beside Close: reloadX/openX are only laid
  -- out at all so the save-mode branch below reads unchanged.
  local saveX = mapMode and (helpX - gap - saveW) or (reloadX - gap - saveW)
  local resetX = saveX - gap - resetW
  local exportX = resetX - gap - exportW
  -- BESIDE EXPORT, because they are the two ends of one thing: this is how a
  -- pack somebody else made gets in, and without it the only way to check that
  -- an export worked was to quit to the launcher and install it by hand.
  local importX = exportX - gap - importW
  local assetX = importX - gap - assetW
  local eventsW = 30 * s + Kit.textWidth("button", "EVENTS")
  local eventsX = assetX - gap - eventsW
  local voxX = eventsX - gap - voxW
  -- What the LEFT-hand block has to stay clear of.  It measured against saveX,
  -- which was the leftmost button before these two joined it -- leaving the
  -- identity block free to paint straight through them (the same bug #497 was
  -- about, one cluster later).
  local leftLimit = mapMode and voxX or saveX

  local wordH = Kit.textHeight("wordmark")
  local brandH = Kit.textHeight("brand")
  local blockY = y + (h - (wordH + 2 * s + brandH)) / 2
  local wordmark = mapMode and "MAP EDITOR" or "SAVE EDITOR"
  local wordW = math.max(
    Theme.spacedWidth(Kit.fonts.wordmark, wordmark, 2 * s),
    Theme.spacedWidth(Kit.fonts.brand, "GEN1RECOMP", 1 * s))
  if cx + wordW + 12 * s < leftLimit then
    love.graphics.setFont(Kit.fonts.wordmark)
    Theme.col(PAL.heading, 1)
    Theme.spaced(Kit.fonts.wordmark, wordmark, cx, blockY, 2 * s)
    love.graphics.setFont(Kit.fonts.brand)
    Theme.col(PAL.caption, 1)
    Theme.spaced(Kit.fonts.brand, "GEN1RECOMP", cx,
      blockY + wordH + 2 * s, 1 * s)
    cx = cx + wordW + 12 * s
  end

  -- version chip: which game this save belongs to (from the launcher slot,
  -- or the save's own header in a standalone run)
  if S.version then
    local name = S.version:upper()
    local c = (S.version == "blue") and PAL.blue or PAL.red
    local cw = Kit.textWidth("chip", name) + 16 * s
    local ch = 22 * s
    local cy = y + (h - ch) / 2
    if cx + cw + 12 * s < leftLimit then
      Theme.col(c, 0.1)
      love.graphics.rectangle("fill", cx, cy, cw, ch, 6 * s, 6 * s)
      Theme.stroke(cx, cy, cw, ch, 6 * s, c, 0.5, 1)
      Kit.textCenter("chip", name, cx, cy + (ch - Kit.textHeight("chip")) / 2,
        cw, c)
      cx = cx + cw + 12 * s
    end
  end

  -- Save is the only green-filled control in the chrome; a corrupt load
  -- renders it steel with the reason parked in the status bar rather than
  -- hiding it (rule 3 of the design spec).
  if Kit.button(saveX, btnY, saveW, btnH, saveLabel,
      { kind = saveKind, enabled = saveEnabled or (not mapMode and not S.allowSave),
        glow = (mapMode and S.mapEditsDirty and 0.6)
          or (S.dirty and S.allowSave and 0.6) or nil }) then
    App.save()
  end
  if mapMode then
    -- EXPORT AS A CONTENT MOD -- not a copy of the edit store, which is a
    -- private format that lands in a save directory the other player has to
    -- find and that their own edits then collide with.
    local okX, ModExport = pcall(require, "tools.map-editor.ModExport")
    -- DRAWN EITHER WAY, and disabled with a reason when the exporter is not
    -- here. A control that vanishes when its module fails to load is
    -- indistinguishable from one that is working and doing nothing -- which is
    -- exactly how a payload shipped without tools/map-editor presented (see
    -- scripts/pack_love.sh, where that is now a contract entry).
    if not (okX and type(ModExport) == "table" and ModExport.write) then
      if Kit.button(exportX, btnY, exportW, btnH, "EXPORT",
                    { kind = "ghost", enabled = false }) then end
      S._exportWhy = S._exportWhy or ("the exporter could not be loaded: "
        .. tostring(ModExport))
    else
      if Kit.button(exportX, btnY, exportW, btnH, "EXPORT", { kind = "ghost" }) then
        local id = "MAP_EDITS_" .. tostring(S.version or "gen2"):upper()
        local path, why, requires, unfinished = ModExport.write(S, {
          id = id,
          name = "Map edits (" .. tostring(S.version or "gen2") .. ")",
        })
        -- WHAT THIS EXPORT NEEDS, said to the person who made it.
        --
        -- A map pack built from imported maps works perfectly here and
        -- nowhere else: the maps reference another cartridge's tilesets, and
        -- the person installing it has to have imported that game. The author
        -- is the only one who can say so in their release notes and the only
        -- one who never sees the problem, so the export tells them.
        local note = nil
        -- DOORS THAT GO NOWHERE, said to the person who can still fix them.
        -- A warp with no destination cannot travel -- see
        -- ModExport.sanitiseWarps -- and the author is the only one who will
        -- ever know which door they meant.
        if path and (unfinished or 0) > 0 then
          note = string.format("%d warp%s had no destination and were left "
                               .. "out", unfinished,
                               unfinished == 1 and "" or "s")
        end
        if path and requires and requires[1] then
          local okA, AT = pcall(require, "src.import.AdoptedTileset")
          if okA then
            local req = AT.requirementText(requires, "This map pack")
            note = note and (note .. "  -- " .. req) or req
          end
        end
        S.pvNotice = path and ("exported to " .. tostring(path)
                               .. (note and ("  -- " .. note) or ""))
          or ("export failed: " .. tostring(why))
        S.status = S.pvNotice
        -- AND IN THE LOG, both ways round. The notice is one line of small
        -- muted text at the foot of a panel, which is the right weight for a
        -- success and much too quiet for a failure the reader is going to have
        -- to describe to somebody.
        pcall(function()
          require("src.core.Logger")[path and "info" or "warn"](
            "%s", tostring(S.pvNotice))
        end)
      end
    end

    -- BRING ONE IN. Same shape as EXPORT and for the same reason: drawn
    -- disabled with a reason rather than vanishing when the module is absent.
    -- ONE DOOR FOR BOTH JOBS. Pressing IMPORT opens the pack dialog rather
    -- than a file picker: what is already installed and what you are about to
    -- add are the same question asked twice, and the list nobody could find
    -- was the one that answers "why does this map look wrong". ADD A PACK
    -- inside it opens the platform's own picker.
    if not (PacksPanel and PacksPanel.raise) then
      if Kit.button(importX, btnY, importW, btnH, "PACKS",
                    { kind = "ghost", enabled = false }) then end
    elseif Kit.button(importX, btnY, importW, btnH, "PACKS",
                      { kind = "ghost" }) then
      PacksPanel.raise(S)
    end

    -- PUT THIS MAP BACK, beside SAVE because it is the other end of the same
    -- thing: one keeps the work, this throws it away.
    --
    -- ARMED, THEN CONFIRMED, in the button itself -- the same shape Close uses
    -- for unsaved changes and the object list uses for delete. A dialog would
    -- be a second modal to build and dismiss for a question with two answers,
    -- and the arm has the advantage that the label says exactly WHAT is about
    -- to happen and to which map, which "Are you sure?" never does.
    --
    -- The arm clears on any other press, so it can never sit waiting to fire
    -- at a map you switched to afterwards.
    local okR, MapReset = pcall(require, "tools.map-editor.MapReset")
    if okR and type(MapReset) == "table" and S.mapId then
      local armed = S._resetArmed == S.mapId
      local edits = 0
      pcall(function()
        edits = MapReset.describe(S.mapEdits, S.version or "", S.mapId) or 0
      end)
      local can = edits > 0 or armed
      if Kit.button(resetX, btnY, resetW, btnH,
                    armed and "RESET?" or "RESET MAP",
                    { kind = armed and "danger" or "ghost",
                      enabled = can, glow = armed and 0.5 or nil }) and can then
        if armed then
          local report, why = MapReset.reset(S, S.mapId)
          S._resetArmed = nil
          if report then
            S.status = string.format(
              "%s put back as the cartridge has it - %d edit%s discarded%s",
              S.mapId, report.dropped, report.dropped == 1 and "" or "s",
              report.how == "session"
                and " (restored to how it looked when you opened it)" or "")
          else
            S.status = tostring(why)
          end
        else
          S._resetArmed = S.mapId
          S.status = string.format(
            "Press RESET? again to discard %d edit%s on %s - this cannot be undone",
            edits, edits == 1 and "" or "s", S.mapId)
        end
      elseif armed and Kit.mouseClicked then
        -- any other press disarms
        S._resetArmed = nil
      end
    end

    -- THE ASSET LIBRARY, beside EXPORT and for the same reason: it is a thing
    -- you do to the WORK. A saved building belongs to the project rather than
    -- to the map it was cut from, so it cannot live in a tool drawer that is
    -- scoped to whichever map is open.
    local okA, MapAssets = pcall(require, "tools.map-editor.MapAssets")
    if okA and type(MapAssets) == "table" then
      local armed = S.assetPlacing ~= nil
      if Kit.button(assetX, btnY, assetW, btnH, "ASSETS",
                    { kind = armed and "accent" or "ghost" }) then
        S.assetMenuOpen = not S.assetMenuOpen
        -- opening the library while holding one puts it down: the list is
        -- where you choose, and choosing is not placing
        if S.assetMenuOpen then MapAssets.disarm(S) end
      end
      -- EVENTS, beside the asset library, for the same reason it is up here:
      -- an event belongs to the MAP rather than to whichever tool is open, and
      -- it is built by looking at a list of beats and a list of flags at once,
      -- which does not fit in a column beside a map.
      if Kit.button(eventsX, btnY, eventsW, btnH, "EVENTS",
                    { kind = S.eventMenuOpen and "accent" or "ghost" }) then
        S.eventMenuOpen = not S.eventMenuOpen
      end
    end

    -- WHICH MOD'S HEIGHTS ARE BEING EDITED.  Two installed mods pin the same
    -- tile to different classes on purpose, so a height shown without saying
    -- whose it is might belong to a world the player is not running.
    if voxLabel then
      if Kit.button(voxX, btnY, voxW, btnH, voxLabel,
                    { kind = "ghost", font = "button" }) then
        S.pvSourceOpen = not S.pvSourceOpen
      end
      -- DEFERRED. Kit has no z-order, so a list drawn from here would be
      -- painted over by the panel, the drawer and everything else in the
      -- frame. App.draw paints it last (see Preview.drawDeferred).
      if S.pvSourceOpen then
        local okV, VC = pcall(require, "tools.map-editor.VoxelClasses")
        S._pvSourceMenu = okV and {
          x = voxX, y = y + h + 4 * s,
          w = math.max(voxW, 240 * s), h = 28 * s,
          srcs = VC.sources(), cur = VC.sourceFor(S.voxelSource),
        } or nil
      else
        S._pvSourceMenu = nil
      end
    end
  else
    if Kit.button(reloadX, btnY, reloadW, btnH, "Reload") then App.reload() end
    if Kit.button(openX, btnY, openW, btnH, "Open...") then App.chooseAndOpen() end
  end
  if mapMode then
    local okH, Help = pcall(require, "tools.map-editor.panels.Help")
    -- Drawn either way, and disabled with the panel absent rather than
    -- vanishing: a control that disappears when its module fails to load is
    -- indistinguishable from one that is working and doing nothing.
    local live = okH and type(Help) == "table" and Help.toggle
    if Kit.button(helpX, btnY, helpW, btnH, "?",
                  { kind = (live and S.helpOpen) and "accent" or "ghost",
                    enabled = live and true or false }) and live then
      Help.toggle(S)
    end
  end
  if Kit.button(closeX, btnY, closeW, btnH,
      S._quitArmed and "Discard?" or "Close",
      { kind = S._quitArmed and "danger" or "ghost" }) then
    App.close()
  end

  local chipW = (leftLimit - 14 * s) - cx
  if chipW > 80 * s and not mapMode then
    drawFileChip(cx, y + (h - 38 * s) / 2, chipW, 38 * s)
  end
end

-- Per-tab counters shown under each tile, so the rail doubles as a summary.
local function tabCount(id)
  if S.mode == "map" then
    local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
    if id == "preview" then
      return Kit.ellipsize("tiny", S.mapId or "", 110 * Kit.scale)
    elseif id == "warps" then
      return def and tostring(#(def.warps or {})) or ""
    elseif id == "objects" then
      return def and tostring(#(def.objects or {})) or ""
    end
    return ""
  end
  if id == "party" then
    return ("%d/%d"):format(#S.save.party, require("src.pokemon.Party").MAX)
  elseif id == "boxes" then
    local n = 0
    for _, box in ipairs(Ops.boxes(S)) do n = n + #box end
    return tostring(n)
  elseif id == "items" then
    local Bag = require("src.inventory.Bag")
    return ("%d/%d"):format(Bag.slots(S.save), Bag.capacity(S.data))
  elseif id == "events" then
    local n = 0
    for _ in pairs(S.save.flags or {}) do n = n + 1 end
    return tostring(n)
  elseif id == "map" then
    -- map ids run long (REDS_HOUSE_2F); the rail is a summary, not a label
    return Kit.ellipsize("tiny", S.mapId or "", 110 * Kit.scale)
  elseif id == "dex" then
    local _, owned, total = Ops.dexCounts(S)
    return ("%d/%d"):format(owned, total)
  end
  return ""
end

-- The validation pill mirrors SaveData.validate: green when the report is
-- empty, yellow with counts when the running game would quarantine
-- something.  Returns what to draw plus the tab that owns the first problem,
-- so the rail can reserve the pill's width before laying out the tiles.
local function validationPill()
  if S.mode == "map" then
    -- "Save validates clean" is not false here so much as irrelevant, and a
    -- reassurance about a file this mode never opens is worse than nothing.
    -- The edit count is the fact that matters: it is the work at risk.
    local okCount, n = pcall(function()
      local ME = require("tools.map-editor.MapEdits")
      if not S.mapEdits then return 0 end
      local total = 0
      for mapId in pairs(S.data.maps or {}) do
        total = total + ME.count(S.mapEdits, tostring(S.version or ""), mapId)
      end
      return total
    end)
    n = (okCount and n) or 0
    if n == 0 then return "No map edits yet", PAL.caption, nil, true end
    return ("%d map edit%s"):format(n, n == 1 and "" or "s"),
      S.mapEditsDirty and PAL.yellow or PAL.green, nil, not S.mapEditsDirty
  end
  local SaveData = require("src.core.SaveData")
  local report = S.validation
  if not report or SaveData.emptyReport(report) then
    return "Save validates clean", PAL.green, nil, true
  end
  local parts = {}
  local target
  local function add(n, singular, plural, tab)
    if n <= 0 then return end
    parts[#parts + 1] = ("%d %s"):format(n, n == 1 and singular or plural)
    target = target or tab
  end
  add(#report.lostMons, "mon", "mons", "party")
  add(#report.lostItems, "item", "items", "items")
  add(#report.remappedMaps, "map", "maps", "map")
  return "Would quarantine " .. table.concat(parts, ", "), PAL.yellow, target, false
end

-- Tab tiles degrade rather than collide: at full width each tile carries its
-- glyph, label and counter; when the validation pill would overlap, the
-- counters drop first and then the labels, leaving the 2-letter glyphs.  A
-- tile is always at least its own square, so every tab stays clickable.
local function railDetail(x, pillX)
  local s = Kit.scale
  local tile = 40 * s
  local widths = { full = 0, nocount = 0, glyph = 0 }
  for _, t in ipairs(activeTabs()) do
    local labelW = Theme.spacedWidth(Kit.fonts.tab, t.label, 1.5 * s)
    local countW = Kit.textWidth("tiny", tabCount(t.id))
    widths.full = widths.full + tile + 9 * s + labelW + 8 * s + countW + 20 * s
    widths.nocount = widths.nocount + tile + 9 * s + labelW + 20 * s
    widths.glyph = widths.glyph + tile + 12 * s
  end
  local avail = pillX - 14 * s - (x + 22 * s)
  -- the widths come back too: the caller needs the glyph-mode figure to decide
  -- whether the pill still has room, and measuring the rail twice is waste
  if widths.full <= avail then return "full", widths end
  if widths.nocount <= avail then return "nocount", widths end
  return "glyph", widths
end

local function drawTabRail(x, y, w, h)
  local s = Kit.scale
  local inset = 22 * s
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y + h - 1, w, 1)

  local label, pillColor, target, clean = validationPill()
  local ph = 26 * s
  local pw = Kit.textWidth("small", label) + 28 * s
  local px = x + w - inset - pw
  local detail, widths = railDetail(x, px)
  -- Last stop before the tiles and the pill collide: at phone widths even the
  -- 2-letter glyph tiles need the room the pill is sitting in, and the pill
  -- only repeats a line the status bar already prints on load, so the pill is
  -- what goes (#497).  With it gone the tiles get the full bar back.
  local showPill = widths.glyph <= px - 14 * s - (x + 22 * s)
  if not showPill then
    detail = railDetail(x, x + w - inset)
  end

  local tile = 40 * s
  local cx = x + inset
  local tileY = y + h - 12 * s - tile
  for _, t in ipairs(activeTabs()) do
    local active = (S.tab == t.id)
    local count = (detail == "full") and tabCount(t.id) or ""
    local labelW = (detail == "glyph") and 0
      or Theme.spacedWidth(Kit.fonts.tab, t.label, 1.5 * s)
    local countW = Kit.textWidth("tiny", count)
    local cellW = (detail == "glyph") and (tile + 12 * s)
      or (tile + 9 * s + labelW + (count ~= "" and 8 * s + countW or 0) + 20 * s)

    Theme.gradRounded(cx, tileY, tile, tile, 11 * s, PAL.chipTop, PAL.chipBot, 1, 1)
    Kit.textCenter("tile", t.glyph, cx, tileY + (tile - Kit.textHeight("tile")) / 2,
      tile, PAL.chipInk)
    if not active then
      -- one tile style plus a scrim, the same trick the launcher uses
      Theme.col(PAL.bgBot, 0.55)
      love.graphics.rectangle("fill", cx, tileY, tile, tile, 11 * s, 11 * s)
    else
      Theme.stroke(cx, tileY, tile, tile, 11 * s, PAL.blue, 0.75, 1.5 * s)
    end

    if detail ~= "glyph" then
      local lx = cx + tile + 9 * s
      love.graphics.setFont(Kit.fonts.tab)
      Theme.col(active and PAL.heading or PAL.muted, 1)
      Theme.spaced(Kit.fonts.tab, t.label, lx,
        tileY + (tile - Kit.textHeight("tab")) / 2, 1.5 * s)
      if count ~= "" then
        Kit.text("tiny", count, lx + labelW + 8 * s,
          tileY + (tile - Kit.textHeight("tiny")) / 2, PAL.faint)
      end
    end

    if active then
      Theme.col(PAL.blue, 1)
      love.graphics.rectangle("fill", cx, y + h - 3 * s,
        math.max(tile, cellW - 20 * s), 3 * s)
    end
    if Kit.press(cx - 8 * s, y, cellW, h) then
      S.tab = t.id
      Kit.blur()
      Ops.disarm(S)
    end
    cx = cx + cellW
  end

  if showPill then
    local py = y + h - 14 * s - ph
    Theme.col(pillColor, clean and 0.08 or 0.1)
    love.graphics.rectangle("fill", px, py, pw, ph, ph / 2, ph / 2)
    Theme.stroke(px, py, pw, ph, ph / 2, pillColor, clean and 0.45 or 0.5, 1)
    Kit.textCenter("small", label, px, py + (ph - Kit.textHeight("small")) / 2,
      pw, pillColor)
    -- paint and hit target are suppressed together, so a hidden pill cannot
    -- still eat a tap meant for the DEX tile
    if target and Kit.press(px, py, pw, ph) then
      S.tab = target
      Ops.say(S, "Jumped to the tab holding the first quarantine warning")
    end
  end
end

local function drawStatusBar(x, y, w, h)
  local s = Kit.scale
  -- `inset`, not `pad`: the gamepad state is a file-level local called `pad`,
  -- and a padding local of the same name shadowed it -- so `pad.active` below
  -- indexed a number and the editor crashed the moment the status bar drew.
  local inset = 22 * s
  Theme.col(PAL.bgBot, 0.6)
  love.graphics.rectangle("fill", x, y, w, h)
  Theme.col(PAL.cardBorder, 0.22)
  love.graphics.rectangle("fill", x, y, w, 1)

  local ctrl = (love.system and love.system.getOS
    and love.system.getOS() == "OS X") and "Cmd" or "Ctrl"
  -- On a pad the keyboard hint is not just unhelpful, it is the only thing on
  -- screen telling you how to drive the editor -- and every shortcut in it
  -- needs a key the console does not have.  Swap it for the pad's own map
  -- whenever the virtual cursor is what is moving.
  local hint
  if pad.active then
    hint = "stick/dpad move . A click . B back . L/R switch tabs . "
      .. "Start save . Select close"
  else
    hint = S.embedded
      and (ctrl .. "+S save . " .. ctrl ..
           "+R reload . Esc clear selection . Close returns to the launcher")
      or (ctrl .. "+S save . " .. ctrl ..
          "+R reload . Esc clear selection . arrows pan map . wheel scrolls lists")
  end
  local hintW = Kit.textWidth("tiny", hint)
  Kit.textRight("tiny", hint, x + w - inset, y + (h - Kit.textHeight("tiny")) / 2, PAL.faint)
  local avail = w - 2 * inset - hintW - 14 * s
  Kit.text("mono", Kit.ellipsize("mono", S.status or "", avail), x + inset,
    y + (h - Kit.textHeight("mono")) / 2, PAL.detail)
end

function App.draw()
  -- Closing the editor unloads it, and the host may still deliver one more
  -- frame or a queued event before it re-routes; every entry point below
  -- tolerates that rather than indexing a torn-down state.
  if not S then return end
  local width, height = love.graphics.getDimensions()
  Kit.layout(width, height)
  local s = Kit.scale

  -- Where the pointer is.  love.mouse is read unconditionally on desktop, but
  -- it is not the only source any more: the virtual cursor above serves the
  -- Switch, and the nil-guard covers a build with the mouse module absent
  -- entirely (this line used to be an unguarded love.mouse.getPosition(), i.e.
  -- an error on the first frame there rather than a degraded editor).
  local mx, my
  local haveMouse = love.mouse and love.mouse.getPosition
  if haveMouse then
    local rx, ry = love.mouse.getPosition()
    -- Real mouse motion yields the pad cursor, so a desktop user who bumped a
    -- stick once gets their pointer straight back.
    if pad.active and lastMouseX
        and (math.abs(rx - lastMouseX) > 3 or math.abs(ry - lastMouseY) > 3) then
      pad.active = false
    end
    lastMouseX, lastMouseY = rx, ry
    mx, my = rx, ry
  end
  if pad.active or not haveMouse then
    padActivate()
    mx, my = pad.x, pad.y
  end
  -- WHOSE POINTER THIS IS, published for the one place that cannot use Kit's.
  --
  -- The map viewport polls love.mouse.isDown directly -- Kit records button 1
  -- only, and the orbit and pan drags need the other two. That poll is right
  -- for a real mouse and wrong for the virtual cursor: the pad's A button sets
  -- `mouseClicked` for Kit and never touches the OS mouse, so isDown(1) is
  -- false forever and the viewport's whole drag/select branch sits behind a
  -- condition that can never be true. On a handheld the map simply did not
  -- respond to the stick.
  --
  -- The viewport already has a select-on-press fallback written for exactly
  -- this; it was gated on `love.mouse.isDown` merely EXISTING, which on
  -- Android it does. This is the flag that gate actually wanted.
  Kit.virtualPointer = (pad.active or not haveMouse) and true or false
  Kit.beginFrame(mx, my, mouseClicked, wheelY)
  mouseClicked = false
  wheelY = 0
  -- Modal shield.  Kit has no z-order, so the picker cannot simply be drawn
  -- last: the chrome and the panel underneath would take the same tap.  The
  -- shield goes up before anything dispatches and comes down only for the
  -- picker's own layer at the bottom of this function (#541).
  -- BEFORE ANYTHING CAN EDIT. History captures the state at the top of the
  -- frame and pushes it when the edit stamp says something changed since the
  -- last one -- so the state on the stack is the one from before this frame's
  -- edits, without every tool having to remember to say "I am about to".
  if History and S.mode == "map" then History.tick(S) end

  -- THE PICKER SHIELDS EVERYTHING; THE DRAWER SHIELDS ITS OWN RECTANGLE.
  --
  -- A drawer covers the right-hand side and leaves the map visible on the
  -- left, and the whole point of a drawer rather than a tab is that you can go
  -- on working on the map -- the tile painter's clicks land there. Raising the
  -- global shield for it made that impossible: with a drawer open, every click
  -- on the panel was refused, so the one tool whose clicks belong to the map
  -- could never receive one, and the painter was unreachable.
  --
  -- THE VOXEL PICKERS ARE MODAL TOO, and for the same reason the species
  -- picker is: they are drawn after the whole frame (Voxels.drawDeferred), and
  -- Kit hit-tests raw coordinates with no z-order -- so without a shield every
  -- control under the popup takes the same tap as the row on top of it.
  local voxModal = (S.mode == "map")
    and (S.voxClassPick ~= nil or S.voxProfPick ~= nil
         or S.pvClassOpen == true or S.assetMenuOpen == true
         -- the pack dialog shields the same way, and has to: it carries a
         -- REMOVE button, and a tap that reached the map underneath it would
         -- be aimed at a control the reader cannot see
         or S.packsOpen == true) or false
  Kit.blockClicks = (S.speciesPicker ~= nil) or voxModal
  Kit.blockRect = nil

  Theme.field(width, height)

  local railH = 6 * s
  local titleH = 64 * s
  local tabH = 66 * s
  local statusH = 38 * s

  Theme.versionRail(0, 0, width, railH)
  drawTitleBar(0, railH, width, titleH)
  drawTabRail(0, railH + titleH, width, tabH)

  local contentY = railH + titleH + tabH
  local contentH = height - contentY - statusH

  -- Computed BEFORE the panel draws, because the shield has to be up while the
  -- panel lays out the controls the drawer is about to cover.
  if Sidebar and S.mode == "map" and Sidebar.isOpen(S) then
    local pw = width - 44 * s
    local dw = Sidebar.width(Kit, pw)
    Kit.blockRect = { 22 * s + pw - dw, contentY + 20 * s, dw, contentH - 38 * s }
  end

  local panel = PANELS[S.tab]
  if panel then
    panel.draw(S, Kit, 22 * s, contentY + 20 * s,
      width - 44 * s, contentH - 38 * s)
  end

  drawStatusBar(0, height - statusH, width, statusH)
  Kit.blockClicks = voxModal
  Kit.blockRect = nil
  -- The drawer, over the panel and under the species picker: it is modal to
  -- the map and the picker is modal to it.
  if Sidebar and S.mode == "map" then
    Kit.blockRect = nil          -- its own layer answers for itself
    Sidebar.draw(S, Kit, PANELS, 22 * s, contentY + 20 * s,
      width - 44 * s, contentH - 38 * s)
    Kit.blockClicks = voxModal
  end

  -- THE VOXEL TOOL'S POPUPS, over the drawer that opened them.
  --
  -- Drawn from inside the panel, they were laid out in the panel's PAGE -- and
  -- since the drawer, that page is taller than the drawer and scrolls inside
  -- it. So the class list centred itself in a page whose middle can be below
  -- the bottom of the screen, and the half of it that fell outside the drawer
  -- was clipped away. Here they are centred in the WINDOW and painted over
  -- everything, and the shield comes down only for this layer.
  if S.mode == "map" and PANELS.voxels and PANELS.voxels.drawDeferred then
    Kit.blockClicks = false
    PANELS.voxels.drawDeferred(S, Kit)
  end
  -- The voxel-source list, over the whole frame.  Its button is in the title
  -- bar and the list drops out of it across the tab rail and the panel, so
  -- "drawn last" is the only way it is on top -- Kit has no z-order.
  -- THE ASSET LIBRARY, over everything: its button is in the title bar and the
  -- list drops out of it across the tab rail, the panel and the drawer alike.
  if S.mode == "map" and S.assetMenuOpen then
    Kit.blockClicks = false
    local okA, MapAssetPanel = pcall(require, "tools.map-editor.panels.AssetMenu")
    if okA and type(MapAssetPanel) == "table" then
      MapAssetPanel.draw(S, Kit)
    end
  end

  -- THE EVENT BUILDER, over the frame like the asset library.
  if S.mode == "map" and S.eventMenuOpen then
    Kit.blockClicks = false
    local okE, EventMenu = pcall(require, "tools.map-editor.panels.EventMenu")
    if okE and type(EventMenu) == "table" and EventMenu.draw then
      EventMenu.draw(S, Kit)
    end
  end

  -- THE TILESET QUESTION, over even the asset library: it is modal, it was
  -- raised by a click somewhere underneath, and until it is answered nothing
  -- under it should be reachable.
  if S.mode == "map" and S.tilesetAsk then
    Kit.blockClicks = false
    local okTP, TilesetPrompt = pcall(require,
                                      "tools.map-editor.panels.TilesetPrompt")
    if okTP and type(TilesetPrompt) == "table" and TilesetPrompt.draw then
      TilesetPrompt.draw(S, Kit)
    end
  end

  -- THE TRAINER PARTY, over the panels that raised it.
  if S.mode == "map" and S.partyAsk then
    Kit.blockClicks = false
    local okPE, PartyEditor = pcall(require,
                                    "tools.map-editor.panels.PartyEditor")
    local okOB, ObjectsPanel = pcall(require,
                                     "tools.map-editor.panels.Objects")
    if okPE and type(PartyEditor) == "table" and PartyEditor.draw then
      -- Written through the Objects panel's own `writeField`, so an added
      -- NPC's team lands in the store beside its other fields rather than
      -- only on the live table.
      PartyEditor.draw(S, Kit,
        (okOB and ObjectsPanel and ObjectsPanel.writeField) or function() end)
    end
  end

  -- THE PACK LIST, over the editor and UNDER the import result: installing
  -- from inside it raises that dialog, and the answer to what you just did
  -- belongs on top of the thing you did it in.
  if S.mode == "map" and S.packsOpen and PacksPanel and PacksPanel.draw then
    Kit.blockClicks = false
    PacksPanel.draw(S, Kit)
  end

  -- THE IMPORT RESULT, over everything: it is the answer to the last thing the
  -- reader did, and until they have read it nothing under it should be
  -- reachable.
  if S.mode == "map" and S.importAsk then
    Kit.blockClicks = false
    local okIP, ImportPrompt = pcall(require,
                                     "tools.map-editor.panels.ImportPrompt")
    if okIP and type(ImportPrompt) == "table" and ImportPrompt.draw then
      ImportPrompt.draw(S, Kit)
    end
    -- CLOSE ONLY THROUGH `App.close`, which carries the unsaved-map-edits
    -- guard. The dialog asks; this is the only place that can answer, because
    -- it is the only one with App in scope.
    if S.importLeave then
      S.importLeave = nil
      App.close()
    end
  end

  -- THE MANUAL, over everything else this mode draws. It is raised from the
  -- title bar, it explains the things underneath it, and it is the one modal
  -- that is useful while another is up -- so it is last.
  if S.mode == "map" and S.helpOpen then
    Kit.blockClicks = false
    local okH, Help = pcall(require, "tools.map-editor.panels.Help")
    if okH and type(Help) == "table" and Help.draw then Help.draw(S, Kit) end
  end

  Kit.blockClicks = false
  if S.mode == "map" and PANELS.preview and PANELS.preview.drawDeferred then
    Kit.blockClicks = false
    PANELS.preview.drawDeferred(S, Kit)
  end
  SpeciesPicker.draw(S, Kit, width, height)
  Kit.endFrame()
  padDraw()

  -- Only now, with the whole frame painted, is it safe to drop the editor.
  if S._closeRequested then finishClose() end
end

function App.keypressed(key)
  if not S then return end
  -- The picker takes Enter and Escape before the focused field does: Kit maps
  -- both to the same "\r" edit (a blur), which cannot tell "commit the top
  -- match" apart from "give up" (#541).
  if S.speciesPicker then
    if key == "return" or key == "kpenter" then
      SpeciesPicker.commitFirst(S, Kit)
      return
    elseif key == "escape" then
      Ops.closeSpeciesPicker(S, Kit)
      return
    end
  end
  -- A focused text field eats the keys it cares about (typing "s" into the
  -- map filter must not trigger Save).
  if Kit.keypressed(key) then return end
  -- THE OPEN DRAWER TAKES THE KEY, and takes it whole. Its panel is what the
  -- reader is looking at; letting the key fall through as well would pan the
  -- map behind the coordinates being typed into it, which reads as the editor
  -- being possessed rather than as a dispatch order. Escape closes the drawer
  -- before it reaches the "clear the selection" branch below, because closing
  -- what is in front of you is what Escape means.
  -- The modifier is worked out HERE, above every branch that reads it. It used
  -- to be computed further down, next to Save -- so the undo chord added above
  -- it read a nil global, the condition was never true, and Ctrl-Z did nothing
  -- at all with no error to show for it.
  local mod = love.keyboard and love.keyboard.isDown
    and (love.keyboard.isDown("lgui", "rgui")
      or love.keyboard.isDown("lctrl", "rctrl"))

  -- ESCAPE PUTS DOWN WHAT IS HELD, before the drawer or the selection sees it.
  -- Closing what is in front of you is what Escape means, and an asset armed
  -- from the title bar is in front of everything -- a click anywhere on the
  -- map would otherwise drop a building.
  if S.mode == "map" then
    -- THE MANUAL IS ABOVE THE OTHER MODALS, in keys as in paint: it can be
    -- raised while one of them is up, and escape has to close what is in
    -- front of you rather than what is behind it.
    if S.helpOpen then
      local okH, Help = pcall(require, "tools.map-editor.panels.Help")
      if okH and type(Help) == "table" and Help.keypressed
         and Help.keypressed(S, key) then
        return
      end
    end
    -- The modal takes every key while it is up, escape included, so a stray
    -- shortcut cannot act on the map behind an unanswered question.
    if S.eventMenuOpen then
      local okE, EventMenu = pcall(require,
                                   "tools.map-editor.panels.EventMenu")
      if okE and type(EventMenu) == "table" and EventMenu.keypressed
         and EventMenu.keypressed(S, key) then
        return
      end
    end
    if S.partyAsk then
      local okPE, PartyEditor = pcall(require,
                                      "tools.map-editor.panels.PartyEditor")
      if okPE and type(PartyEditor) == "table" and PartyEditor.keypressed
         and PartyEditor.keypressed(S, key) then
        return
      end
    end
    if S.packsOpen and PacksPanel and PacksPanel.keypressed
       and PacksPanel.keypressed(S, key) then
      return
    end
    if S.importAsk then
      local okIP, ImportPrompt = pcall(require,
                                       "tools.map-editor.panels.ImportPrompt")
      if okIP and type(ImportPrompt) == "table" and ImportPrompt.keypressed
         and ImportPrompt.keypressed(S, key) then
        return
      end
    end
    if S.tilesetAsk then
      local okTP, TilesetPrompt = pcall(require,
                                        "tools.map-editor.panels.TilesetPrompt")
      if okTP and type(TilesetPrompt) == "table" and TilesetPrompt.keypressed
         and TilesetPrompt.keypressed(S, key) then
        return
      end
    end
    local okA, AssetMenu = pcall(require, "tools.map-editor.panels.AssetMenu")
    if okA and type(AssetMenu) == "table" and AssetMenu.keypressed
       and AssetMenu.keypressed(S, key) then
      return
    end
  end

  -- UNDO BEFORE THE DRAWER. The drawer consumes every key it is given -- it
  -- has to, or the arrows pan the map behind the coordinates being typed into
  -- it -- so Ctrl-Z never reached the branch below while a tool was open,
  -- which is exactly when somebody wants it. A modifier chord is not a key the
  -- drawer's panel could have meant.
  if History and S.mode == "map" and key == "z" and mod then
    local shift = love.keyboard and love.keyboard.isDown
      and love.keyboard.isDown("lshift", "rshift")
    if shift then
      S.status = History.redo(S) and "Redid" or "Nothing to redo"
    else
      S.status = History.undo(S) and "Undid" or "Nothing to undo"
    end
    return
  end
  if Sidebar and Sidebar.isOpen(S) and Sidebar.keypressed(S, PANELS, key) then
    return
  end
  if Kit.focus then
    if key == "escape" then Kit.blur() end
    return
  end
  -- Save and Reload both touch the file on disk (Reload discards unsaved
  -- edits), so they need a modifier.  A bare letter is one stray keystroke
  -- away from a write, and the editor has no undo.
  if key == "escape" then
    S.editingMon = nil
    Ops.disarm(S)
    Ops.say(S, "Selection cleared")
  elseif key == "s" and mod then
    App.save()
  elseif key == "r" and mod and S.mode ~= "map" then
    App.reload()
  end
  if S.tab == "map" and MapBrowser.keypressed then
    MapBrowser.keypressed(S, key)
  end
  -- and every other panel that wants keys. The map-editor panels each publish
  -- `keypressed` -- Voxels pans the grid with the arrows, the list panels take
  -- Delete -- and none of it ran, because this only ever dispatched to the map
  -- tab. Reached only after Kit.keypressed has returned above, so a panel can
  -- never steal a keystroke from a text field it is drawing.
  local panel = PANELS[S.tab]
  if panel and panel ~= MapBrowser and panel.keypressed then
    panel.keypressed(S, key)
  end
end

function App.wheelmoved(x, y)
  if not S then return end
  -- The manual scrolls its own body and swallows the notch, so a section
  -- longer than the card does not scroll the map behind it instead.
  if S.mode == "map" and S.helpOpen then
    local okH, Help = pcall(require, "tools.map-editor.panels.Help")
    if okH and type(Help) == "table" and Help.wheelmoved
       and Help.wheelmoved(S, y) then
      return
    end
  end
  -- THE ASSET LIBRARY OWNS THE WHEEL while it is up: it is drawn over the
  -- whole window, so anything the notch reached underneath would be scrolling
  -- something the reader cannot see.
  if S.mode == "map" and S.assetMenuOpen then
    -- A wheel over a modal scrolls nothing rather than scrolling the palette
    -- behind it.
    if S.tilesetAsk then return end
    if S.eventMenuOpen then
      local okE, EventMenu = pcall(require,
                                   "tools.map-editor.panels.EventMenu")
      if okE and type(EventMenu) == "table" and EventMenu.wheelmoved then
        if EventMenu.wheelmoved(S, y) then return end
      end
    end
    local okA, AssetMenu = pcall(require, "tools.map-editor.panels.AssetMenu")
    if okA and type(AssetMenu) == "table" and AssetMenu.wheelmoved then
      if AssetMenu.wheelmoved(S, y) then return end
    end
  end
  -- and the notch, for the same reason: a list in the drawer must not scroll
  -- the map underneath it instead of itself.
  if Sidebar and Sidebar.isOpen(S) and Sidebar.wheelmoved(S, PANELS, y) then
    return
  end
  -- The map tab spends the wheel on zoom; every other tab routes it through
  -- Kit so whichever list the pointer is over takes it next draw (#595).
  if S.tab == "map" and MapBrowser.wheelmoved then
    MapBrowser.wheelmoved(S, y)
    return
  end
  -- The map-editor panels scroll their own lists through their own offsets
  -- rather than Kit's, so the notch has to reach them directly; without this
  -- their lists simply stopped at whatever fitted on screen.
  local panel = PANELS[S.tab]
  if panel and panel.wheelmoved then
    panel.wheelmoved(S, y)
    return
  end
  wheelY = wheelY + (y or 0)
end

function App.quit()
  if not S then return false end
  if (S.mode == "map") and S.mapEditsDirty or S.dirty then
    -- simple: block quit once and set status; user saves or force-quits again
    if not S._quitArmed then
      S._quitArmed = true
      S.status = "Unsaved changes,  save or press quit again"
      return true
    end
  end
  return false
end

return App
