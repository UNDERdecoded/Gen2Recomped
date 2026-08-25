-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Native LÖVE2D port of Pokemon Red. A packaged build creates its private
-- game-data cache from a user-provided ROM on first boot.
--
-- The save editor (tools/save-editor/) ships inside every build and is
-- reachable two ways:
--   * standalone: POKEPORT_EDITOR=1 or `love . --editor`, its own window
--   * from the launcher: Edit on a save row, which suspends the launcher,
--     opens the editor on that slot's file, and restores the launcher when
--     the editor's Close button is pressed (openEditor / closeEditor below)

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true

local Game, EditorApp, Importer, TouchEditor

local autopilot -- optional scripted-input dev tool (tests/autopilot.lua)
local driverCo  -- optional frame-driver (POKEPORT_DRIVER=file.lua): a
                -- coroutine that receives `Game` and yields once per
                -- frame; used headless (xvfb) for scripted screenshots

-- --speed N / POKEPORT_SPEED=N: run the logic clock N times faster without
-- touching audio (src/core/GameSpeed.lua).  Overrides the saved option so a
-- bot or screenshot run is not at the mercy of the player's last choice.
local speedOverride = tonumber(os.getenv("POKEPORT_SPEED"))

-- POKEPORT_TOUCH=1 forces the mobile on-screen controls on and lets the
-- mouse stand in for a finger, so the overlay can be exercised on desktop
-- (see src/core/TouchControls.lua).
local mouseTouch = os.getenv("POKEPORT_TOUCH") == "1"

-- How many times to run a scripted act+step loop per rendered frame.  Only
-- scripted runs use this; interactive play fast-forwards through
-- Game.speedOverride / the GAME SPEED option instead.
local function scriptedIterations()
  if not (autopilot or driverCo) then return 1 end
  return math.max(1, math.floor(require("src.core.GameSpeed").clamp(speedOverride)))
end

-- ------------------------------------------------------------ save editor
-- The launcher instance parked while the editor is up, plus the version whose
-- cache the editor mounted (so closing can put the read path back).
local editorHost, editorVersion, editorWindow
local closeEditor  -- forward declaration: openEditor hands it to the editor

-- The editor's modules use flat names (require("Kit"), require("Party")), so
-- their directories have to be on the require path.  It must be
-- love.filesystem's path, not package.path: in a packaged build these files
-- live inside the .love archive, which the stock Lua searcher cannot open.
local function addEditorRequirePath()
  local fs = love.filesystem
  if not (fs.setRequirePath and fs.getRequirePath) then
    -- very old LOVE: a source checkout still resolves through package.path
    package.path = fs.getSource() .. "/tools/save-editor/?.lua;"
                .. fs.getSource() .. "/tools/save-editor/panels/?.lua;"
                .. package.path
    return
  end
  local current = fs.getRequirePath()
  if current:find("tools/save%-editor") then return end
  fs.setRequirePath("tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
    .. current)
end

-- Desktop only: the launcher window (1024x768) is tighter than the editor's
-- design size, so grow it while editing and put it back on Close.  Never
-- shrinks, never touches a fullscreen or mobile window.
local function resizeForEditor()
  if not (love.window and love.window.getMode and love.window.setMode) then return end
  local osName = love.system.getOS()
  if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then return end
  local w, h, flags = love.window.getMode()
  if flags.fullscreen then return end
  local dw, dh = love.window.getDesktopDimensions()
  local wantW = math.max(w, math.min(1360, math.floor((dw or w) * 0.92)))
  local wantH = math.max(h, math.min(860, math.floor((dh or h) * 0.88)))
  if wantW <= w and wantH <= h then return end
  editorWindow = { w = w, h = h }
  love.window.setMode(wantW, wantH, flags)
end

local function restoreWindow()
  if not editorWindow then return end
  local _, _, flags = love.window.getMode()
  love.window.setMode(editorWindow.w, editorWindow.h, flags)
  editorWindow = nil
end

-- Open the editor on a launcher save row.  The version's cache has to be
-- mounted before the editor's Data:load runs, or a Blue save would be edited
-- against Red's species/item tables.
local function openEditor(version, slotId)
  local SaveData = require("src.core.SaveData")
  local path = SaveData.slotDiskPath(version, slotId)
  if not path then
    if Importer then
      Importer.saveNotice = Importer.saveNotice or {}
      Importer.saveNotice[version] =
        { ok = false, text = "Could not resolve that save slot on disk." }
    end
    return
  end
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  -- Not optional, and the return value is not decoration.  A failed overlay
  -- surfaces several frames later inside the editor's Data:load as "missing
  -- generated data module 'data/generated/constants.lua'" -- an uncaught error
  -- raised out of a mouse handler, which on the Switch and on Android means
  -- the app is simply gone.  bootGame already checks this; the editor path was
  -- the one that did not, so pressing Edit was a crash rather than a message.
  local mounted, mountErr =
    require("src.import.CacheFs").mountVersion(version)
  if not mounted then
    if Importer then
      Importer.saveNotice = Importer.saveNotice or {}
      Importer.saveNotice[version] = { ok = false, text =
        ("Cannot edit %s saves: its imported data is not loadable (%s). " ..
         "Import the ROM again."):format(
          GameVersion.info(version).displayName,
          tostring(mountErr or "unknown reason")) }
    end
    return
  end
  editorVersion = version
  editorHost = Importer
  Importer = nil
  editorMode = true
  resizeForEditor()
  addEditorRequirePath()
  EditorApp = require("App")
  EditorApp.load(path, { version = version, slotId = slotId, embedded = true,
                         onClose = function() closeEditor() end })
end

-- Open the MAP EDITOR on a game.  Same shell, same mount discipline, same way
-- back -- the only differences are that there is no save slot to resolve (the
-- map editor edits the game's maps, not a playthrough) and that App.load is
-- told which mode to open in.
--
-- The mount is not optional here either, and for a sharper reason than in the
-- save path: without the version's cache the editor's Data:load finds no
-- generated map data at all, so the map list would come up EMPTY rather than
-- failing -- an editor that looks like it works and has nothing in it.
local function openMapEditor(version)
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  local mounted, mountErr =
    require("src.import.CacheFs").mountVersion(version)
  if not mounted then
    if Importer then
      Importer.saveNotice = Importer.saveNotice or {}
      Importer.saveNotice[version] = { ok = false, text =
        ("Cannot edit %s maps: its imported data is not loadable (%s). " ..
         "Import the ROM again."):format(
          GameVersion.info(version).displayName,
          tostring(mountErr or "unknown reason")) }
    end
    return
  end
  editorVersion = version
  editorHost = Importer
  Importer = nil
  editorMode = true
  resizeForEditor()
  addEditorRequirePath()
  EditorApp = require("App")
  EditorApp.load(nil, { version = version, mode = "map", embedded = true,
                        onClose = function() closeEditor() end })
end

-- Back to the launcher.  Everything the editor mounted or cached has to come
-- back out: the version overlay (CacheFs) and the generated modules require
-- cached behind it (Data), or pressing Play on the OTHER game would boot it
-- with this one's data.
function closeEditor()
  local version = editorVersion
  editorMode = false
  if EditorApp and EditorApp.unload then EditorApp.unload() end
  EditorApp = nil
  if version then
    require("src.import.CacheFs").unmountVersion(version)
    require("src.core.Data"):unloadGenerated()
  end
  editorVersion = nil
  restoreWindow()
  Importer = editorHost
  editorHost = nil
  if Importer and version and Importer.savesChanged then
    Importer:savesChanged(version)
  end
end

-- ------------------------------------------------------------ touch controls editor
-- Suspends the launcher while the player drags on-screen buttons / toggles
-- the overlay off (#327).  No ROM cache needed -- options.lua only.
local touchEditorHost
local closeTouchControlsEditor  -- forward declaration

local function openTouchControlsEditor()
  touchEditorHost = Importer
  Importer = nil
  TouchEditor = require("src.ui.TouchControlsEditor")
  TouchEditor.load({ onClose = function() closeTouchControlsEditor() end })
end

function closeTouchControlsEditor()
  if TouchEditor and TouchEditor.unload then TouchEditor.unload() end
  TouchEditor = nil
  Importer = touchEditorHost
  touchEditorHost = nil
end

-- Boot breadcrumbs (src/core/BootTrace.lua).  On Android and the Switch a
-- failed launch is a window that exists for a second and then does not, with
-- nothing to read afterwards: crash.txt below only ever catches a LUA error,
-- and a native abort -- an OOM kill, a JNI check, a driver fault -- reaches no
-- Lua handler and leaves it empty, which is indistinguishable from a clean
-- run.  So record progress instead of failure: the last line in boot_trace.txt
-- is the stage the process did not survive.
local BootTrace = require("src.core.BootTrace")
-- Counts love.graphics.push/pop for the life of the process and unwinds
-- anything a frame forgot, at the top of the next update and draw.  Installed
-- here, before anything can draw, because the failure it guards against is not
-- local: ONE unmatched push anywhere -- engine, mod, a menu preview that bailed
-- early -- leaves the shared stack a notch deeper every frame until some
-- unrelated push overflows it and ends the process with a traceback pointing at
-- innocent code.  See src/render/GraphicsStack.lua.
local GraphicsStack = require("src.render.GraphicsStack")
-- Declared HERE rather than further down beside its first mark: bootGame below
-- calls BootTrace.booted(), and a `local` declared after a function's body is
-- not in scope inside it -- the name resolved to the nil GLOBAL instead and
-- killed the boot the moment an import finished (onComplete -> bootGame).

local function bootGame(version)
  -- The launcher hands us the chosen game (Red / Blue / Yellow); scripted and
  -- headless runs fall back to POKEPORT_VERSION, then Red.  Set the active
  -- version and overlay its extracted cache BEFORE anything requires generated
  -- data, so data/generated + assets/generated resolve to that version's files.
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version or os.getenv("POKEPORT_VERSION") or "red")
  -- A failed overlay is fatal a few lines later, inside Data:load, as
  -- "missing generated data module 'data/generated/constants.lua'" -- an
  -- error that names the symptom and hides the cause.  Report the cause
  -- here, where mountVersion can still say which mechanism failed and what
  -- the player can do about it.
  local mounted, mountErr =
    require("src.import.CacheFs").mountVersion(GameVersion.get())
  if not mounted then
    error(("could not load %s's imported data (%s).\n\n" ..
           "The import wrote it to:\n  %s%s\n\n" ..
           "If that folder is missing or empty, import the ROM again."):format(
      GameVersion.info().displayName,
      tostring(mountErr or "unknown reason"),
      love.filesystem.getSaveDirectory and
        (love.filesystem.getSaveDirectory() .. "/") or "",
      GameVersion.cachePrefix(GameVersion.get())), 0)
  end
  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title(
      GameVersion.info().displayName .. " (Gen 1 Recompilation Project)"))
  end
  Game = require("src.core.Game")
  Game:load()
  BootTrace.booted()
  if os.getenv("POKEPORT_AUTOPILOT") then
    autopilot = require("tests.autopilot")
  end
  local driverPath = os.getenv("POKEPORT_DRIVER")
  if driverPath then
    local fn = assert(loadfile(driverPath))()
    driverCo = coroutine.create(fn)
  end
  -- After the two above are known: a scripted run drives the multiplier
  -- from love.update's loop, so the in-engine one must stay at 1 or the
  -- two would compound (10x10 = 100 steps per observation).
  Game.speedOverride = (autopilot or driverCo) and 1 or speedOverride
end

-- Chunk level, not inside love.load: this is the earliest point Lua code of
-- ours runs with a writable save directory (conf.lua has already applied
-- t.identity by now).  So NO boot_trace.txt at all is itself a result -- it
-- means the failure was in conf.lua or below it in the engine, before any of
-- this file ran.
BootTrace.mark("main.lua chunk")

-- ------------------------------------------------------- boot failure report
-- What the player sees after a launch that died, INSTEAD of booting.
--
-- The trace and crash.txt only help if someone can read them, and on Android
-- nobody can: t.externalstorage puts the save directory under
-- Android/data/<package>/files/, and Android 11 closed that path to every
-- third-party file manager.  The app writes there fine and the player gets
-- "permission denied".  adb is the only other way out, and asking a player for
-- adb is asking them to give up.
--
-- So the report comes back through the screen.  Launch N dies; launch N+1
-- notices the trace has no "clean exit", shows it, and -- critically -- does
-- NOT run the boot path that just failed, so the report cannot be taken down
-- by the same crash.  A tap dismisses it and boots normally, so a one-off is
-- not a lock-out.
local bootReport = nil        -- { text = string, args = table }
local realLoad                -- forward declaration: the actual boot

local function drawBootReport()
  local w, h = love.graphics.getDimensions()
  love.graphics.clear(0.08, 0.09, 0.13)
  love.graphics.setColor(1, 0.55, 0.35)
  local pad = math.max(12, math.floor(w * 0.03))
  if not bootReport.font then
    -- Small, because a traceback on a phone is long and legibility here means
    -- "fits", not "looks nice".
    bootReport.font = love.graphics.newFont(math.max(9, math.floor(h / 62)))
  end
  love.graphics.setFont(bootReport.font)
  love.graphics.printf(bootReport.text, pad, pad, w - pad * 2, "left")
  love.graphics.setColor(0.6, 0.7, 0.9)
  love.graphics.printf("tap / press any key to continue booting",
    pad, h - pad - bootReport.font:getHeight() * 2, w - pad * 2, "left")
end

local function dismissBootReport()
  local args = bootReport.args
  bootReport = nil
  BootTrace.mark("boot report dismissed")
  realLoad(args)
end

function love.load(args)
  BootTrace.mark("love.load enter")
  GraphicsStack.install()

  -- Teach SDL about the pads its built-in database misses (Switch Pro over
  -- Bluetooth, Joy-Cons, GameSir) before any joystick is opened, so they
  -- arrive as real gamepads with leftx/lefty instead of as raw numbered axes
  -- nothing was listening to.  See GamepadMap.loadMappings.
  pcall(function() require("src.core.GamepadMap").loadMappings() end)

  -- Before anything else, and before anything that could fail: did the last
  -- launch finish?  POKEPORT_NO_BOOT_REPORT=1 skips this for CI and scripted
  -- runs, which have no one to show it to and must not stop on it.
  --
  -- POKEPORT_PAYLOAD_MOUNTED skips it too, and that one is not an opt-out: it
  -- means we ARE the chainloaded payload and this love.load is the second one
  -- of a single launch (src/update/Boot.lua's chainload runs the payload's
  -- main.lua and then calls its love.load).  The bundled half already asked
  -- this question a few milliseconds ago, with the real previous trace in
  -- front of it.  Asking again diagnosed the launch in progress as a failed
  -- one -- an updated Android build opened with "PREVIOUS LAUNCH DID NOT
  -- FINISH" every single time, showing its own bundled prefix ending at
  -- "save identity".  BootTrace inherits the verdict across the handoff too,
  -- so this is belt and braces rather than the fix.
  if os.getenv("POKEPORT_NO_BOOT_REPORT") ~= "1"
     and not _G.POKEPORT_PAYLOAD_MOUNTED then
    local report = BootTrace.previousFailureReport()
    if report then
      BootTrace.mark("showing previous failure report")
      bootReport = { text = report, args = args }
      return
    end
  end
  return realLoad(args)
end

function realLoad(args)
  -- Before anything can shell out (update check, mod index, ROM picker),
  -- claim one hidden console on Windows so those children inherit it instead
  -- of each flashing their own cmd.exe window (#606).  No-op elsewhere.
  require("src.core.HostShell").hideHostConsole()
  BootTrace.mark("host console")

  -- Gen2Recomped used to share the LÖVE identity "pokemon-love2d" with the
  -- Gen 1 port, so both games wrote one save folder.  We own "Gen2Recomp"
  -- now; copy an existing player's saves across the first time.  Must run
  -- before Boot.run or anything else reads the save directory.
  pcall(function() require("src.core.SaveIdentity").migrateLegacy() end)
  BootTrace.mark("save identity")

  -- Self-updater boot shell: a fused build may mount and chainload a newer
  -- downloaded payload here.  True means it took over, so we must stop.  A
  -- dev / source checkout no-ops (see src/update/Boot.lua).
  local Boot = require("src.update.Boot")
  if Boot.run(args) then
    BootTrace.mark("payload chainloaded")
    return
  end
  BootTrace.mark("boot shell")

  local savePath
  for i, a in ipairs(args or {}) do
    if a == "--editor" then
      editorMode = true
    elseif a == "--developer" then
      _G.POKEPORT_DEV_MODE = true
    elseif a == "--save" and args[i + 1] and args[i + 1] ~= "" then
      savePath = args[i + 1]
    elseif a == "--speed" and tonumber(args[i + 1]) then
      speedOverride = tonumber(args[i + 1])
    end
  end
  love.graphics.setDefaultFilter("nearest", "nearest")

  -- Standalone editor.  A bare `--editor` run has no launcher behind it, so
  -- Close quits; --save points it at a specific file, otherwise it opens the
  -- default save path for POKEPORT_VERSION (Red unless overridden), whose
  -- cache has to be mounted before the editor's Data:load.
  if editorMode then
    local version = os.getenv("POKEPORT_VERSION") or "red"
    require("src.core.GameVersion").set(version)
    require("src.import.CacheFs").mountVersion(version)
    addEditorRequirePath()
    EditorApp = require("App")
    EditorApp.load(savePath, { version = version })
    return
  end

  local RomImporter = require("src.import.RomImporter")
  BootTrace.mark("RomImporter required")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  local importPath = os.getenv("POKEPORT_IMPORT_ROM")
  -- Scripted / headless runs pick their game from POKEPORT_VERSION (default
  -- Red); the launcher's per-column choice does not apply to them.
  local scriptedVersion = os.getenv("POKEPORT_VERSION") or "red"
  local ready = RomImporter.isReady(scriptedVersion)
  -- Scripted / headless runs have to reach the game with no human pressing
  -- Play: an autopilot, a frame driver, an import-only build step, or an
  -- explicit ROM path all bypass the interactive launcher and keep today's
  -- import-then-boot (or boot-straight-in) behavior.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or importPath ~= nil

  if scripted then
    if forceImport or not ready then
      -- The importer detects the dropped/loaded ROM's version by SHA-1 and
      -- passes it to onComplete; boot that version.
      Importer = RomImporter.new(function(version)
        if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
          love.event.quit()
          return
        end
        Importer = nil
        bootGame(version or scriptedVersion)
      end)
      if importPath then Importer:startPath(importPath) end
      return
    end
    bootGame(scriptedVersion)
    return
  end

  -- Interactive: the launcher always runs.  Red, Blue, and Yellow are each
  -- live: a column shows Play when that game's ROM is already imported, or
  -- Choose ROM / drag-drop when it is not.  Any dropped .gb is routed by its
  -- SHA-1 (GameVersion.forSha1); pressing Play boots that game.  Edit on a
  -- save row opens the bundled editor on that slot (openEditor).
  BootTrace.mark("launcher: constructing")
  Importer = RomImporter.new(function(version)
    Importer = nil
    bootGame(version)
  end, {
    launcher = true,
    forceImport = forceImport,
    onEditSave = openEditor,
    onEditMaps = openMapEditor,
    onEditTouchControls = openTouchControlsEditor,
  })
  BootTrace.mark("launcher: ready")
  BootTrace.booted()
end

function love.update(dt)
  -- Unwind anything the previous frame left on the graphics stack before this
  -- one starts building on top of it.
  GraphicsStack.drain()
  -- The report deliberately runs nothing else: the boot path it is reporting on
  -- is the code that just died.
  if bootReport then return end
  if editorMode then return EditorApp.update(dt) end
  if TouchEditor then return TouchEditor.update(dt) end
  if Importer then return Importer:update(dt) end

  -- Scripted runs (autopilot / POKEPORT_DRIVER) observe and act exactly
  -- once per Game:update, so they must keep a 1:1 relationship with the
  -- logic step.  Fast-forwarding them by scaling the step inside
  -- Game:update would run N steps per observation: a held direction walks
  -- through all N, the player slides past the waypoint, and the script
  -- re-plans from an overshot cell.  So iterate the whole act+step loop
  -- instead -- same script, just more of it per rendered frame.
  local iterations = scriptedIterations()

  if autopilot then
    for _ = 1, iterations do
      autopilot.update()
      Game:update(1 / 60) -- deterministic stepping for the autopilot
    end
    return
  end
  if driverCo then
    for _ = 1, iterations do
      local ok, err = coroutine.resume(driverCo, Game)
      if not ok then
        print("driver error: " .. tostring(err))
        love.event.quit(1)
        return
      end
      if coroutine.status(driverCo) == "dead" then
        love.event.quit()
        return
      end
      Game:update(1 / 60)
    end
    return
  end
  -- Game is nil until a ROM has been imported and Play pressed, and it is nil
  -- again for any window in which neither the launcher nor the game owns the
  -- frame: while the boot report is up, after Boot.run chainloads a payload,
  -- and between the launcher clearing Importer and bootGame assigning Game.
  -- Android delivers focus/visible events during all of those, so an
  -- unguarded dereference here is not a theoretical race -- it is
  -- "attempt to index upvalue 'Game' (a nil value)" a second after launch.
  if not Game then return end
  Game:update(dt)
end

function love.draw()
  GraphicsStack.drain()
  if bootReport then return drawBootReport() end
  if editorMode then return EditorApp.draw() end
  if TouchEditor then return TouchEditor.draw() end
  if Importer then return Importer:draw() end

  if not Game then return end
  Game:draw()
  -- frame capture requested by a driver
  if Game.capturePath then
    local path = Game.capturePath
    Game.capturePath = nil
    love.graphics.captureScreenshot(function(imagedata)
      local fd = imagedata:encode("png")
      local f = io.open(path, "wb")
      if f then
        f:write(fd:getString())
        f:close()
      end
    end)
  end
end

function love.keypressed(key, scancode, isrepeat)
  if bootReport then return dismissBootReport() end
  if editorMode then return EditorApp.keypressed(key) end
  if TouchEditor then return TouchEditor.keypressed(key) end
  if Importer then return Importer:keypressed(key) end
  if not Game then return end
  Game:keypressed(key)
end

function love.keyreleased(key)
  if editorMode or TouchEditor then return end
  if Importer then return end
  if not Game then return end
  Game:keyreleased(key)
end

-- The editor gets the pad events too.
--
-- These handlers all began with `if editorMode ... then return end`, which was
-- written when the editor was a desktop-only tool reached by `love . --editor`
-- and a mouse was a given.  It is now reachable from the launcher on every
-- platform, including two with no pointer at all: on the Switch the editor
-- opened, drew, and then ignored every button, stick and D-pad input the
-- console can produce -- the only way out was to kill the app.  The launcher
-- already solves this with a virtual cursor (RomImporter:_activatePadCursor);
-- the editor now has the same one, and these forwards are what feed it.
function love.gamepadpressed(joystick, button)
  -- and the dismissal that matters on the Switch.
  if bootReport then return dismissBootReport() end
  if TouchEditor then return end
  if editorMode then
    if EditorApp.gamepadpressed then return EditorApp.gamepadpressed(button) end
    return
  end
  if Importer then return Importer:gamepadpressed(joystick, button) end
  if not Game then return end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  if TouchEditor then return end
  if editorMode then
    if EditorApp.gamepadreleased then return EditorApp.gamepadreleased(button) end
    return
  end
  if Importer then return Importer:gamepadreleased(joystick, button) end
  if not Game then return end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  if TouchEditor then return end
  if editorMode then
    if EditorApp.gamepadaxis then return EditorApp.gamepadaxis(axis, value) end
    return
  end
  if Importer then return Importer:gamepadaxis(joystick, axis, value) end
  if not Game then return end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickpressed(joystick, button)
  if bootReport then return dismissBootReport() end
  if TouchEditor then return end
  if editorMode then
    if EditorApp.joystickpressed then
      return EditorApp.joystickpressed(joystick, button)
    end
    return
  end
  if Importer then return Importer:joystickpressed(joystick, button) end
  if not Game then return end
  Game:joystickpressed(joystick, button)
end

function love.joystickreleased(joystick, button)
  if editorMode or TouchEditor then return end
  if Importer then return Importer:joystickreleased(joystick, button) end
  if not Game then return end
  Game:joystickreleased(joystick, button)
end

function love.joystickaxis(joystick, axis, value)
  if TouchEditor then return end
  if editorMode then
    if EditorApp.joystickaxis then
      return EditorApp.joystickaxis(joystick, axis, value)
    end
    return
  end
  if Importer then return Importer:joystickaxis(joystick, axis, value) end
  if not Game then return end
  Game:joystickaxis(joystick, axis, value)
end

function love.joystickhat(joystick, hat, direction)
  if TouchEditor then return end
  if editorMode then
    if EditorApp.joystickhat then
      return EditorApp.joystickhat(joystick, hat, direction)
    end
    return
  end
  if Importer then return Importer:joystickhat(joystick, hat, direction) end
  if not Game then return end
  Game:joystickhat(joystick, hat, direction)
end

function love.joystickremoved(joystick)
  if editorMode or TouchEditor then return end
  if Importer then return end
  if not Game then return end
  Game:joystickremoved(joystick)
end

-- f is true on focus gained, false on focus lost (e.g. alt-tab). A held
-- direction's key-up can be delivered to the OS instead of the game while
-- unfocused, so reset input on either transition rather than trust it.
function love.focus(f)
  if bootReport then return end
  if editorMode or TouchEditor then return end
  if Importer then
    if Importer.focus then Importer:focus(f) end
    return
  end
  if not Game then return end
  Game:focus(f)
end

-- v is true when the window becomes visible again, false on minimize.
function love.visible(v)
  if bootReport then return end
  if editorMode or TouchEditor then return end
  if Importer then return end
  if not Game then return end
  Game:visible(v)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  -- The dismissal that matters on a phone: there is no keyboard behind this.
  if bootReport then return dismissBootReport() end
  -- THE EDITOR SEES TOUCHES NOW, and only for the gestures a mouse cannot
  -- make. It is driven by SDL's synthesized mouse events -- one finger is a
  -- pointer and always has been -- so these handlers track contact points and
  -- act on TWO of them (pinch to zoom) and nothing else. Returning without
  -- consuming keeps every existing single-finger path exactly as it was.
  if editorMode then
    if EditorApp.touchpressed then EditorApp.touchpressed(id, x, y) end
    return
  end
  if TouchEditor then
    -- iOS synthesizes mousepressed for the primary touch (same as the
    -- launcher); Android drives the editor through love.touch directly.
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchpressed(id, x, y)
  end
  if Importer then
    -- iOS: LÖVE already synthesizes a mousepressed for the primary touch,
    -- and love.mousepressed below forwards that to the Importer, so
    -- forwarding here too fires every launcher button twice per tap.  The
    -- resulting double-present was fatal for the document picker: the
    -- second sheet stole the first one's weakly-held delegate, so picking
    -- a file silently did nothing.  Android keeps the forward for upstream
    -- parity (its SAF picker is a separate activity and tolerates the
    -- re-launch).
    if love.system.getOS() == "iOS" then return end
    return Importer:mousepressed(x, y, 1)
  end
  if not Game then return end
  Game:touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  if editorMode then
    if EditorApp.touchmoved then EditorApp.touchmoved(id, x, y) end
    return
  end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchmoved(id, x, y)
  end
  if Importer then return end
  if not Game then return end
  Game:touchmoved(id, x, y)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  if editorMode then
    if EditorApp.touchreleased then EditorApp.touchreleased(id, x, y) end
    return
  end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchreleased(id, x, y)
  end
  if Importer then return end
  if not Game then return end
  Game:touchreleased(id, x, y)
end

function love.wheelmoved(x, y)
  if editorMode then
    if EditorApp.wheelmoved then return EditorApp.wheelmoved(x, y) end
    return
  end
  if TouchEditor then return end
  if Importer then return end
  if not Game then return end
  Game:wheelmoved(x, y)
end

function love.mousepressed(x, y, button, istouch)
  if bootReport then return dismissBootReport() end
  if TouchEditor then
    -- Android primary touch already arrived via love.touchpressed; a second
    -- mouse path would double-fire Done / begin a second drag.
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousepressed(x, y, button)
  end
  if Importer then
    -- The same double-fire TouchEditor guards against, which the launcher was
    -- missing: love.touchpressed above forwards the primary touch to the
    -- Importer on Android, and LÖVE ALSO synthesizes a mouse press for that
    -- same touch, so one tap ran every launcher button twice.  On Import that
    -- meant two choose() calls and two stacked SAF picker activities: the
    -- player picked their ROM, the top picker closed, and the second was still
    -- underneath asking for it again, which is the "import the file twice"
    -- in #553.  Filtering on istouch keeps a real mouse (DeX, a Chromebook, a
    -- USB mouse) working, which an Android-wide return would have broken.
    --
    -- ANDROID ONLY, and the OS test is load bearing: love.touchpressed above
    -- returns early on iOS and never forwards, so there the synthesized mouse
    -- press is the ONLY event the launcher gets.  Filtering istouch on both
    -- killed every tap on iOS outright.
    if istouch and love.system.getOS() == "Android" then return end
    return Importer:mousepressed(x, y, button)
  end
  if editorMode and EditorApp.mousepressed then
    return EditorApp.mousepressed(x, y, button)
  end
  if mouseTouch and Game and button == 1 then
    Game:touchpressed("mouse", x, y)
  end
end

function love.mousereleased(x, y, button)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousereleased(x, y, button)
  end
  if Importer then return end
  if editorMode and EditorApp.mousereleased then
    return EditorApp.mousereleased(x, y, button)
  end
  if mouseTouch and Game and button == 1 then
    Game:touchreleased("mouse", x, y)
  end
end

function love.mousemoved(x, y)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousemoved(x, y)
  end
  if editorMode or Importer then return end
  if mouseTouch and Game and love.mouse.isDown(1) then
    Game:touchmoved("mouse", x, y)
  end
end

function love.textinput(text)
  if TouchEditor then return end
  if Importer then return Importer:textinput(text) end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

-- Write every Lua error to a file before showing it.
--
-- On desktop the blue error screen IS the bug report -- you read it and you
-- know.  On Android and the Switch you cannot: the app closes, and the
-- traceback only ever existed in logcat or on a screen that was up for a
-- second.  Appending it to the save directory puts it somewhere a player can
-- actually reach: on Android that folder is the app's external-files
-- directory, browsable in any file manager under
-- Android/data/<package>/files/crash.txt, no USB and no adb.
--
-- Deliberately additive: the default handler still runs afterwards, so
-- desktop behaviour is unchanged.
--
-- AND the app must never disappear without saying why.  "It shows for a second
-- and closes, with no error" is not evidence of a native crash -- it is what an
-- ORDINARY Lua error looks like here, because of how LOVE's own boot code is
-- written.  From the engine vendored in this repo:
--
--   boot.lua        func = handler(...)   ...   while func do ... end   return 1
--   callbacks.lua   function love.errhand(msg)
--                     if not love.window or not love.graphics or not love.event
--                       then return end                      -- returns NIL
--                     if not love.graphics.isCreated() ... then
--                       local success, status = pcall(love.window.setMode, 800, 600)
--                       if not success or not status then return end   -- NIL
--
-- The error handler is expected to RETURN THE ERROR SCREEN'S main loop.  Every
-- one of those bare `return`s hands back nil, and boot.lua's `while func do`
-- then falls straight through to `return 1`: the process ends, having drawn
-- nothing.  Worse, boot.lua's deferErrhand sets `inerror = true` before calling
-- the handler, so if drawing the error screen ITSELF errors -- one nil index in
-- setMode, isCursorSupported, setNewFont -- the second error is routed to
-- error_printer, which prints to stdout (logcat, invisible on a phone) and also
-- returns nil.  Same silent exit.
--
-- So: write the traceback to a file the player can reach, and then guarantee a
-- visible screen even when the stock handler bails.  A crash that leaves NO
-- crash.txt AND no screen is then genuinely below Lua.
local defaultErrorHandler = love.errorhandler or love.errhand

-- Last-resort error screen: no fonts we did not just create, no modules beyond
-- graphics/event, no reliance on anything the failed frame left behind.  Draws
-- the traceback and waits, so the message can be read (and photographed) on a
-- device with no console and no file manager to hand.
local function minimalErrorScreen(text)
  if not (love.graphics and love.event) then return nil end
  local ok = pcall(function()
    love.graphics.reset()
    love.graphics.setNewFont(14)
    love.graphics.setBackgroundColor(0.35, 0.06, 0.06)
  end)
  if not ok then return nil end
  return function()
    if love.event then
      love.event.pump()
      for name, a in love.event.poll() do
        if name == "quit" then return 1 end
        if name == "keypressed" and (a == "escape" or a == "q") then return 1 end
      end
    end
    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(0.35, 0.06, 0.06)
      love.graphics.setColor(1, 1, 1)
      local w = love.graphics.getWidth()
      love.graphics.printf(text, 20, 20, math.max(120, w - 40), "left")
      love.graphics.present()
    end
    if love.timer then love.timer.sleep(0.02) end
  end
end

function love.errorhandler(msg)
  local trace = "gen2recomp error\n\n" .. tostring(msg)
  pcall(function()
    local parts = {
      "---- " .. tostring(os.date and os.date("%Y-%m-%d %H:%M:%S") or "?") .. " ----",
      "os: " .. tostring(love.system and love.system.getOS and love.system.getOS() or "?"),
      "fused: " .. tostring(love.filesystem.isFused and love.filesystem.isFused()),
    }
    local okv, Version = pcall(require, "src.core.Version")
    if okv and Version then parts[#parts + 1] = "engine: " .. tostring(Version.engine) end
    parts[#parts + 1] = ""
    parts[#parts + 1] = debug.traceback(tostring(msg), 2)
    parts[#parts + 1] = ""
    trace = table.concat(parts, "\n")
    love.filesystem.append("crash.txt", trace .. "\n")
  end)
  -- Also into the boot trace, so the breadcrumb file ends with the reason and
  -- not merely with the last stage that succeeded.
  pcall(function() BootTrace.mark("ERROR " .. tostring(msg)) end)

  -- The stock handler first, so desktop keeps the screen everyone knows.  It is
  -- pcall'd because it is exactly the thing that can fail here, and a raise
  -- inside it would otherwise be the second error that ends the process.
  if defaultErrorHandler then
    local ok, stepper = pcall(defaultErrorHandler, msg)
    if ok and stepper then return stepper end
  end
  return minimalErrorScreen(trace)
end

-- A thread that dies must not take the game with it.
--
-- LÖVE's DEFAULT love.threaderror re-raises on the main thread, so an error
-- inside any worker is a hard crash of the whole app a frame or two later.
-- RomImporter starts the update check behind a pcall with the comment "a
-- broken or absent updater can never take the launcher down with it" -- but
-- pcall only guards Check.start(), not what the thread does afterwards, so
-- that intent was not actually being met.  The same applies to the audio
-- chip worker.
--
-- Nothing here is load-bearing enough to be worth a crash: the updater just
-- stops offering updates, and the launcher keeps running.  Log it and carry
-- on.
function love.threaderror(thread, errorstring)
  local Logger = package.loaded["src.core.Logger"]
  local msg = "thread error: " .. tostring(errorstring)
  if Logger and Logger.warn then Logger.warn("%s", msg) else print(msg) end
  pcall(function()
    love.filesystem.append("crash.txt",
      "---- thread error ----\n" .. tostring(errorstring) .. "\n\n")
  end)
end

function love.quit()
  if editorMode and EditorApp.quit then
    return EditorApp.quit() -- return true to abort quit
  end
  -- Marks the trace as an orderly shutdown.  A trace that ends mid-boot with
  -- no "clean exit" and no crash.txt beside it is the signature of a native
  -- abort rather than a Lua error -- which is exactly the distinction that is
  -- otherwise invisible on a phone.
  BootTrace.finish()
  pcall(function()
    require("src.core.DiscordPresence").shutdown()
  end)
  -- LOVE waits for every live love.thread before the process exits, and both
  -- background workers idle in a loop that only a "quit" command breaks, so
  -- without this the process outlived the window and the next launch re-entered
  -- the dead one instead of starting fresh (#339)
  if package.loaded["src.core.ChipAudio"] then
    pcall(package.loaded["src.core.ChipAudio"].shutdown)
  end
  if package.loaded["src.update.Check"] then
    pcall(package.loaded["src.update.Check"].shutdown)
  end
end

function love.filedropped(file)
  if editorMode and EditorApp and EditorApp.filedropped then
    return EditorApp.filedropped(file)
  end
  if Importer then Importer:filedropped(file) end
end

local function pacingEnabled()
  if os.getenv("POKEPORT_AUTOPILOT") then return false end
  if os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

function love.run()
  BootTrace.mark("love.run enter")
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
  BootTrace.mark("love.load returned")

  -- don't let love.load's cost land in the first frame's dt
  if love.timer then love.timer.step() end

  local FrameCap = require("src.core.FrameCap")
  local paced = pacingEnabled()
  -- The deadline the next present() should not beat.  Carried forward one
  -- budget per frame so pacing stays even instead of drifting with the
  -- per-frame sleep-granularity jitter.
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0

  return function()
    -- process events
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            -- Android keeps the process and its task alive after LOVE's own
            -- teardown, so the relaunched task re-enters an activity whose
            -- native main already returned; end the process outright once the
            -- love.quit hook has run (#339)
            if love.system and love.system.getOS() == "Android" then
              os.exit(a or 0)
            end
            return a or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end

    -- update dt
    if love.timer then dt = love.timer.step() end

    -- call update and draw
    if love.update then love.update(dt) end

    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end
    -- Counted after present, so a frame in the trace means a frame that was
    -- actually put on screen.  Thins out fast (see BootTrace.frame): the
    -- interesting range for a launch that dies "about a second in" is frames
    -- 1..60, and past that the trace only needs to prove it kept running.
    BootTrace.frame()

    if love.timer then
      if paced then
        -- Sleep out the remainder of the frame budget, measured from the
        -- carried deadline, in small chunks so the OS timer stays
        -- responsive.  vsync is untouched: when it already paces slower
        -- than the cap the remainder is <= 0 and this rounds to a no-op.
        local budget = 1 / FrameCap.current
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        -- A stall (alt-tab, a GC pause, a blocked import) can leave the
        -- deadline more than a full budget in the past; re-anchor to now so
        -- we pace the next frame rather than burst uncapped to catch up.
        if now - nextFrame > budget then
          nextFrame = now
        end
        while true do
          local remaining = nextFrame - love.timer.getTime()
          if remaining <= 0 then break end
          love.timer.sleep(remaining < 0.001 and remaining or 0.001)
        end
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
