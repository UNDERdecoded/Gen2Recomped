-- Central game object: owns the data, renderer, input, state stack, world
-- and save state.  Everything else reaches shared services through here.

local Data = require("src.core.Data")
local FixedStep = require("src.core.FixedStep")
local Input = require("src.core.Input")
local Logger = require("src.core.Logger")
local Platform = require("src.core.Platform")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local FrameProfile = require("src.core.FrameProfile")
local TouchControls = require("src.core.TouchControls")
local ModLoader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")

local Game = {}

-- dev-mode gate for the F5/backtick hotkeys; false keeps every src/dev
-- module unloaded, so a player boot never touches a byte of dev code
local devMode = os.getenv("POKEPORT_DEV") == "1" or _G.POKEPORT_DEV_MODE == true

-- the boot screen ids (field.boot.screens); a plain function so the
-- headless harness can borrow makeTitleState onto a stub game
local function bootScreens(game)
  local boot = game.data and game.data.field and game.data.field.boot
  return (boot and boot.screens) or {}
end

function Game:load()
  self.pointerOwners={}
  self.secondScreenPointerOwner=nil
  self.secondScreenOverworldPoketch=nil
  self.data = Data
  Data:load()

  -- Mods are a native engine subsystem.  They load after the verified ROM
  -- data exists, so mods can register or override the same definitions that
  -- the rest of the game consumes.  A broken mod is reported and skipped by
  -- the loader without preventing the base game from booting.
  self.mods = ModLoader.new()
  self.mods:load(Data)
  self.modStatus = self.mods:status()
  -- AND THE MAP EDITOR'S OVERLAY AGAIN, ON TOP OF THE MERGE.
  --
  -- Data:load laid it down before this, and a content mod that patches a map
  -- has just replaced it. That is not a corner case: `ModExport` writes a map
  -- pack whose patch carries the whole `objects` array as it stood at export,
  -- and installing your own pack back into the editor -- which is exactly what
  -- the IMPORT button is for, and the honest way to check an export works --
  -- makes every later edit to those maps invisible. Added an NPC, saved,
  -- launched: the overlay put him there, the pack's snapshot took him away
  -- again, and all three steps reported success.
  --
  -- THE WORKING COPY WINS. A mod is published content; the edit store is what
  -- the reader is editing right now. Where the two describe the same map, the
  -- one they can still see and change is the one that should be on screen --
  -- and the alternative is an editor whose saves silently stop taking effect
  -- once you have shared your work once.
  --
  -- Cheap on a machine with no edits: the store is absent, applyAll finds
  -- nothing, and this is a file check.
  Data:applyMapEditorOverlay("after mods")
  -- Re-derive the Gen 2 palette view over the MERGED tileset table.  A
  -- mod that adds or replaces a tileset adds or replaces its colours with
  -- it, and the view is only useful to a 3D pipeline if it covers those
  -- too: an uncovered tileset renders that ONE map grey while its
  -- neighbours are in colour, which is harder to diagnose than a whole
  -- grey world because it reads as a bug in that map.
  Data:publishGen2Palettes()
  -- render pipelines dispatch off the merged dataset; point them at the
  -- one the mods just merged into before anything can draw a frame
  require("src.render.Pipelines").install(Data)

  self.input = Input
  Input:init()

  self.touchControls = TouchControls
  TouchControls:init()

  self.renderer = Renderer
  Renderer:init()

  require("src.render.Font").load(Data)
  -- menu cursor/border/geometry constants; field.theme restyles them
  require("src.ui.Theme").load(Data)
  -- the engine's own text, after the merge so a translation mod's catalog
  -- is already in Data.strings; empty on a mod-free boot and skipped
  require("src.core.Strings").load(Data)

  self.stack = StateStack
  StateStack:init()

  self.save = SaveData.newGame(self:bootConfig())
  -- seed=true keeps what entry chunks wrote through mod.save before any
  -- save existed; the skeleton fires save.created exactly once
  self:adoptSave(self.save, true)
  ModRuntime.emit("save.created", { save = self.save })
  -- apply the persisted audio + display options before anything plays
  self:applyOptions(self.save.options)

  FixedStep:init(function(step) self:step(step) end)
  self.fixedStep = FixedStep

  local OverworldState = require("src.world.OverworldController")
  self.overworld = OverworldState

  -- Discord Rich Presence: map name / battle status on the player's profile.
  -- Soft-fail: missing Discord / IPC errors must never block boot.
  pcall(function() require("src.core.DiscordPresence").init(self) end)

  -- Every service is up but nothing is on the stack yet; this payload is the
  -- sanctioned way for a mod to obtain the Game object.
  --
  -- It reads through to the Game as well as carrying it under `.game`.  Half
  -- the mods written against this event treat the payload AS the game --
  --
  --     mod.events:on("game.ready", function(game) ... game.input ... end)
  --
  -- which is a fair reading of an event called "game ready", and against a
  -- bare `{ game = self }` it silently yields nil for every field they want.
  -- STADIUM2_OVERWORLD_MODELS' battle-controller shortcuts refused to install
  -- with "live Game2 host has no input object" for exactly this reason, and
  -- its party-follower bridge reads `game.world` the same way.  The metatable
  -- costs nothing, keeps `payload.game` working for everyone who reads it the
  -- documented way, and adds no keys -- `pairs(payload)` is unchanged.
  ModRuntime.emit("game.ready",
    setmetatable({ game = self }, { __index = self }))

  -- boot into the title screen (engine/movie/title.asm); NEW GAME runs
  -- the Oak speech + naming, CONTINUE restores the save.  The headless
  -- autopilot skips straight into the overworld.
  if os.getenv("POKEPORT_AUTOPILOT") then
    StateStack:push(OverworldState, self.save.player.map,
                    self.save.player.x, self.save.player.y, self.save.player.facing)
  else
    local titleState = self:makeTitleState()
    -- the copyright splash + attract movie plays before the title
    -- (engine/movie/splash.asm + intro.asm; Yellow swaps in its own
    -- 18-scene movie, engine/movie/intro_yellow.asm, and Gold/Silver
    -- theirs, engine/movie/intro.asm GoldSilverIntro); the ids come from
    -- field.boot.screens so a total conversion owns the whole boot
    local Version = require("src.core.GameVersion")
    local splash = Version.isGen2() and "Gen2Intro"
      or (Version.isYellow() and "YellowIntro" or "IntroMovie")
    local chosen = bootScreens(self).splash
    if chosen == nil then chosen = splash end
    if chosen then
      Screens.push(self, chosen, function() StateStack:push(titleState) end)
    else
      -- `false`, not merely absent: a dataset whose attract movie this engine
      -- does not have yet (Gen 3's) says so rather than being handed Red's,
      -- and `or splash` would have handed it Red's -- which is precisely how
      -- an Emerald boot ended up watching the Kanto intro.
      StateStack:push(titleState)
    end
  end

  Logger.info("game loaded")
  -- Scaling bug reports (#87, #208) are unanswerable without these three
  -- numbers: LOVE units, drawable pixels, and the integer physical pixels
  -- per GB pixel the renderer settled on.  Cheap, once, and it turns "it
  -- looks stretched" into something reproducible.
  if love.graphics and love.graphics.getDimensions then
    local ww, wh = love.graphics.getDimensions()
    local pw, ph = ww, wh
    if love.graphics.getPixelDimensions then
      pw, ph = love.graphics.getPixelDimensions()
    end
    Logger.info(string.format(
      "display: %dx%d units, %dx%d px, fit scale %d px/GB px",
      ww, wh, pw, ph, Renderer:fitScale()))
  end
end

-- the merged field.boot: spawn, names, money and the naming presets a
-- total conversion overrides.  Threaded into SaveData so persistence stays
-- free of a Data dependency.
function Game:bootConfig()
  local boot = self.data and self.data.field and self.data.field.boot
  -- stamp the running game version onto the boot config so a New Game records
  -- it (SaveData.newGame reads boot.version); this is what routes a Blue
  -- playthrough to save_blue.lua and Blue's version-gated content
  if boot then boot.version = require("src.core.GameVersion").get() end
  -- ...and the map scenes that do NOT open at zero.  InitializeEvents writes
  -- three scene bytes directly on this cartridge (Goldenrod City among them),
  -- and a scene left at 0 arms a cutscene that has already been retired.
  local field = self.data and self.data.field
  if boot and field and type(field.initialScenes) == "table" then
    boot.initialScenes = field.initialScenes
  end
  -- THE STARTING PC ITEM, NAMED IN THIS DATASET'S OWN IDS.
  --
  -- players_pc.asm seeds one Potion, and SaveData.newGame wrote the literal
  -- id "POTION" for it. A Gen 2 import names every item off the cartridge as
  -- ITEM_nnn, so that literal is an id nothing else in the game ever uses --
  -- and the bag is a map keyed by id, so the PC's potion and the one Elm's
  -- aide hands over sat in TWO SEPARATE SLOTS, both printing "POTION".
  -- Resolved here, where the item table is in hand: a real "POTION" id when
  -- the dataset has one (Gen 1), otherwise the id whose printed name is
  -- Potion (Gen 2's ITEM_nnn).
  if boot and boot.pcItems == nil then
    local items = self.data and self.data.items
    if type(items) == "table" then
      local id = items.POTION and "POTION" or nil
      if not id then
        for key, def in pairs(items) do
          if type(def) == "table"
             and tostring(def.name or ""):upper():gsub("[^%a]", "") == "POTION" then
            id = key
            break
          end
        end
      end
      if id then boot.pcItems = { [id] = 1 } end
    end
  end
  return boot
end

-- the title screen with its NEW GAME / CONTINUE wiring; used at boot
-- and by the START-menu QUIT confirmation
function Game:makeTitleState()
  local OverworldState = require("src.world.OverworldController")
  local factory = Screens.get(self, bootScreens(self).title or "TitleState")
  local title = factory.new(self, {
    onNewGame = function()
      while self.stack:top() do self.stack:pop() end
      -- New Game keeps the standalone options.lua preferences
      self.save = SaveData.newGame(self:bootConfig())
      -- no bucket carry-over: mod state from an abandoned session must
      -- not leak into a fresh slot; mods seed via save.created instead
      self:adoptSave(self.save)
      ModRuntime.emit("save.created", { save = self.save })
      self:applyOptions(self.save.options)
      self.stack:push(OverworldState, self.save.player.map,
                      self.save.player.x, self.save.player.y,
                      self.save.player.facing)
      local newGameScreen = bootScreens(self).newGame
      if newGameScreen == nil and not require("src.core.GameVersion").isGen2() then
        newGameScreen = "OakSpeech"
      end
      if newGameScreen then
        Screens.push(self, newGameScreen, function() end)
      else
        -- PRISM HAS NO OAK SPEECH, and that is why its character customisation
        -- never appeared.  Data.lua sets boot.screens.newGame = false for any
        -- dataset with no OakText* -- Prism writes its own introduction in
        -- engine/intro_menu.asm rather than replaying the professor's -- so
        -- OakSpeech does not run, and the `customize_player` step lives INSIDE
        -- OakSpeech.  The step was correct and simply unreachable.
        --
        -- IntroductionSpeech calls PlayerCustomization before it asks the
        -- player's name, and the name prompt on this path comes from the
        -- intro map's own script, so pushing it here puts it in the same
        -- place: after New Game, before the map runs.
        -- pcall, not a bare require: a dataset can want this screen without
        -- the build shipping it (that is exactly how NEW GAME on Prism went
        -- from "no customisation menu" to "module not found" the moment the
        -- branch became reachable).  A missing screen must cost the player
        -- the customisation, not the save file they were starting.
        local okCust, Cust = pcall(require, "src.ui.PrismCustomization")
        if okCust and type(Cust) == "table" and Cust.available(self) then
          Screens.push(self, "PrismCustomization", function() end)
        elseif not okCust then
          require("src.core.Logger").error(
            "player customisation screen unavailable: %s", tostring(Cust))
        end
      end
    end,
    onContinue = function()
      local loaded, recovered = SaveData.load()
      if loaded then
        self:restoreSave(loaded, recovered)
      end
    end,
  })
  title.screenId = title.screenId or "TitleState"
  return title
end

-- QUIT from the START menu: back to the title like a power-cycle,
-- unsaved progress discarded.  TitleState:enter restarts the title
-- theme; stop() keeps the map song from bleeding over in the meantime.
function Game:returnToTitle()
  require("src.core.Music").stop()
  while self.stack:top() do self.stack:pop() end
  self.stack:push(self:makeTitleState())
end

function Game:step(dt)
  -- THE WHOLE LOGIC STEP, because `stack:update` alone accounted for under
  -- 2 ms of a 43 ms update and everything else in here was invisible.  Run 4
  -- to 6 times per rendered frame while the accumulator catches up, so a cost
  -- in here is multiplied before it reaches the frame.
  local closeStep = FrameProfile.section("  step: whole")
  self:_step(dt)
  closeStep()
end

function Game:_step(dt)
  -- Tool mods (autoplay, accessibility drivers, input visualizers) act on
  -- the same fixed-step boundary as a physical controller.  Run them before
  -- Input:step promotes queued edges so a button chosen here is visible to
  -- this logic tick, not one tick later.  With no wrapper this is a no-op.
  do
    -- A MOD SEAM ON THE LOGIC STEP.  Timed at the call site rather than inside
    -- the hook chain: a hook calls `next` into the rest of the chain, so a
    -- timer around one link charges it with everything downstream.  One number
    -- for the whole seam is honest; per-link numbers there would not be.
    local close = FrameProfile.section("    step: mod input.step")
    ModRuntime.call("input.step", function() end, self, dt)
    close()
  end
  self.input:step()
  -- A+B+SELECT+START held for 16 steps: SoftReset (home/init.asm) stops the
  -- audio, whites the palettes out and falls through into Init, i.e. the
  -- power-on boot, so everything unsaved is gone and the title sequence
  -- comes back -- exactly what returnToTitle does for the START menu's QUIT.
  -- The check lives here, above stack:update, so it fires from any state:
  -- overworld, battle, a menu or a cutscene, the way _Joypad's does (#563).
  -- Input:reset clears the four still-physically-held buttons so the title
  -- screen does not read A as a menu choice on its first frame.
  -- a tool mod (or a harness) may hand Game a stand-in input with no
  -- chord bookkeeping; those simply never soft reset
  if self.input.softResetStep and self.input:softResetStep() then
    Input:reset()
    TouchControls:reset()
    self:returnToTitle()
    return
  end
  -- serviced unconditionally: a link battle's ENet transport must not
  -- stall just because PartyMenu/ChoiceBox/NamingScreen is temporarily
  -- on top of BattleState (see LinkBattle.new)
  if self.linkNet and not self.linkNet.closed then
    self.linkNet:update()
  end
  -- AN EMPTY STACK IS NOT A GAME.
  if self:ensureStack() then return end
  local closeStep = FrameProfile.section("  logic: stack:update")
  self.stack:update(dt)
  closeStep()
  -- play time for the trainer card / save screen.  A save written by an older
  -- build carries the broken-down { hours, minutes, ... } form, which would
  -- throw here on its first frame; playSeconds normalises it, and the field is
  -- a number from this assignment onward (SaveData.validate does the same on
  -- load, so this is the belt to that brace).
  local clock = self.save.playTime
  if clock ~= nil and tonumber(clock) == nil then
    clock = require("src.core.SaveData").playSeconds(self.save)
  end
  self.save.playTime = (tonumber(clock) or 0) + dt
  -- Music.update is NOT serviced here: it decrements fade counters and
  -- drives ChipAudio once per call, so running it inside the logic step
  -- would pitch music and sfx up under fast-forward. Game:update advances
  -- it on its own real-time 60Hz accumulator instead.
end

-- The logic multiplier for this frame. Read live rather than cached so the
-- Options row takes effect immediately; speedOverride is the --speed /
-- POKEPORT_SPEED run argument, which wins over the saved option so a bot
-- or screenshot run does not depend on whatever the player last chose.
function Game:logicSpeed()
  local GameSpeed = require("src.core.GameSpeed")
  -- Link play is always 1X on both machines, and this wins over every other
  -- source including POKEPORT_SPEED.  Fast-forward multiplies the logic
  -- clock, so a peer at 10X burned a tournament shot clock ten times faster
  -- than the opponent it is racing, and drove its own animation/message
  -- queue at a different rate than the peer it is locked to.  Nothing about
  -- a match should depend on what either player set this to.
  if self.linkSession or (self.linkNet and not self.linkNet.closed) then
    return 1
  end
  if self.speedOverride then return GameSpeed.clamp(self.speedOverride) end
  local opts = self.save and self.save.options
  return GameSpeed.clamp(opts and opts.speed or GameSpeed.DEFAULT)
end

-- THE FREE CAMERA, when one owns the frame -- otherwise nil.
--
-- Nil on every Gen 1/2/3 map and on every Gen 4 map whose tilt ladder is not on
-- `third` or `first`, so every control below is inert everywhere else without
-- needing to know what else is bound.
function Game:freeView()
  local ow = self.overworld
  local renderer = ow and ow.map and ow.map.renderer
  local ground = renderer and renderer.gen4Ground
  local view = ground and ground.view3d
  -- ORBITAL, not merely 3D: a tilt rung is a real camera too, and the mouse
  -- must not swing it.  `isFree` is the rendering question; this is the
  -- control one.  The `isOrbital` test is on the METHOD as well as its answer,
  -- so a view built before it existed still behaves.
  if view and view.orbit and view.isOrbital and view:isOrbital() then
    return view
  end
  return nil
end

-- Zoom can dolly the field camera without enabling mouse orbit on it.
function Game:zoomView()
  local ground=self.overworld and self.overworld.map and self.overworld.map.renderer
  ground=ground and ground.gen4Ground
  local view=ground and ground.view3d
  if view and view.zoomBy and view.mode~='first' then return view end
end

-- Degrees of camera per pixel of mouse, and per second at full stick.
--
-- Requested: *"the orbit ... should be mouse and right analog stick
-- controlled"*.  `Gen4View:orbit` already takes arbitrary degrees -- the four
-- keys just hand it fixed steps -- so these are the only new numbers, and they
-- are taste rather than measurement.  Mouse down and stick down swing the camera
-- UP and over, looking further down; say so if you want it the other way.
Game.LOOK_PER_PIXEL = 0.20
Game.LOOK_RISE_PER_PIXEL = 0.12
Game.LOOK_PER_SECOND = 150
Game.LOOK_RISE_PER_SECOND = 80
-- Below this the stick is treated as centred, and past it the response starts
-- from zero rather than jumping -- otherwise a worn stick drifts the camera
-- round on its own and a small push snaps.
Game.STICK_DEADZONE = 0.22

-- Mouse look.  Returns true when it consumed the movement.
-- THE LARGEST TURN ONE MOUSE EVENT MAY ASK FOR, in degrees.
--
-- A hand cannot move the mouse this far between two frames.  At 60 Hz a fast
-- flick of a thousand pixels a second is about sixteen pixels an event, which
-- at `LOOK_PER_PIXEL` is 3.3 degrees; twelve is nearly four times that, so no
-- real movement is ever refused.  What DOES produce a delta this size is the
-- pointer being warped, and SDL emits exactly one enormous `mousemoved` when
-- relative mode is turned on or off.
Game.LOOK_MAX_DEGREES = 12

-- How many events to ignore after relative mode is toggled.
Game.LOOK_SETTLE_EVENTS = 2

function Game:cameraLook(dx, dy)
  local view = self:freeView()
  if not view then return false end
  if (dx == 0 or dx == nil) and (dy == 0 or dy == nil) then return true end

  -- A WARP IS NOT A LOOK.
  --
  -- HONESTY FIRST: this guard was added as a proposed cause of the reported
  -- camera flip, and that proposal was WRONG.  The flip was two maps each
  -- owning a `Gen4View` and the frame being drawn through whichever one was
  -- current -- see the note in `Gen4View:follow`, which measures the two
  -- disagreeing by 84 degrees.  The guard was instrumented to say so, and the
  -- play test that found the real cause never printed its line.
  --
  -- It is kept, and only for what it is: relative mouse mode is toggled every
  -- time the overworld stops or starts being the top screen, each toggle warps
  -- the pointer, and SDL reports a warp as one `mousemoved` carrying a delta
  -- the width of the window.  That is a real event whether or not it was the
  -- flip.  A hand cannot move twelve degrees between two frames -- a fast
  -- flick of a thousand pixels a second is 3.3 degrees an event -- so this
  -- cannot refuse a real movement.  If it ever does, delete it rather than
  -- raise the cap: it is a net, not a feature.
  --
  -- DROPPED rather than clamped: a clamped warp still turns the camera twelve
  -- degrees for no reason, and the event is not a small movement that got too
  -- big, it is not a movement at all.
  if (self.lookSettle or 0) > 0 then
    self.lookSettle = self.lookSettle - 1
    return true
  end
  local turn = math.abs((dx or 0) * Game.LOOK_PER_PIXEL)
  local lift = math.abs((dy or 0) * Game.LOOK_RISE_PER_PIXEL)
  if turn > Game.LOOK_MAX_DEGREES or lift > Game.LOOK_MAX_DEGREES then
    -- SAID ONCE, because this is a hypothesis about a report and the next play
    -- test is what confirms it.  If the flip stops and this line never
    -- appears, the cause was something else and this guard is dead weight.
    if not Game.saidLookSpike then
      Game.saidLookSpike = true
      Logger.info("gen4 camera: dropped a mouse look of %.1f/%.1f degrees "
                  .. "(cap %.1f) -- a pointer warp, not a hand",
                  turn, lift, Game.LOOK_MAX_DEGREES)
    end
    return true
  end

  view:orbit((dx or 0) * Game.LOOK_PER_PIXEL,
             (dy or 0) * Game.LOOK_RISE_PER_PIXEL)
  return true
end

local function stickAxis(pad, name, dead)
  local ok, v = pcall(pad.getGamepadAxis, pad, name)
  v = (ok and tonumber(v)) or 0
  if v > dead then return (v - dead) / (1 - dead) end
  if v < -dead then return (v + dead) / (1 - dead) end
  return 0
end

-- The right stick, polled rather than evented.
--
-- `love.gamepadaxis` fires on CHANGE, so a stick held at full deflection sends
-- nothing and the camera would stop turning while the player is still asking it
-- to.  An analog control that means "keep going" has to be read per frame.
function Game:updateCameraStick(dt)
  local view = self:freeView()
  if not view then
    if self.lookRelative and love.mouse and love.mouse.setRelativeMode then
      pcall(love.mouse.setRelativeMode, false)
      self.lookRelative = false
      self.lookSettle = Game.LOOK_SETTLE_EVENTS
    end
    return
  end
  -- RELATIVE MODE, or the pointer hits the edge of the window and the look
  -- stops dead.  Only while the overworld itself is on top: a menu over a free
  -- camera still wants a real cursor.
  local wantRelative = (self.stack and self.stack:top()) == self.overworld
  if wantRelative and love.window and love.window.hasFocus then
    local ok, focused = pcall(love.window.hasFocus)
    wantRelative = ok and focused or false
  end
  local actualRelative = self.lookRelative
  if love.mouse and love.mouse.getRelativeMode then
    local ok, relative = pcall(love.mouse.getRelativeMode)
    if ok then actualRelative = relative end
  end
  if love.mouse and love.mouse.setRelativeMode and actualRelative ~= wantRelative then
    local ok = pcall(love.mouse.setRelativeMode, wantRelative)
    self.lookRelative = ok and wantRelative or false
    -- ...and ignore what the warp this causes is about to report.
    self.lookSettle = Game.LOOK_SETTLE_EVENTS
  else
    self.lookRelative = actualRelative
  end
  if not (love.joystick and love.joystick.getJoysticks) then return end
  local ok, pads = pcall(love.joystick.getJoysticks)
  if not ok then return end
  for _, pad in ipairs(pads or {}) do
    local isPad = pad.isGamepad and select(2, pcall(pad.isGamepad, pad))
    if isPad then
      local rx = stickAxis(pad, "rightx", Game.STICK_DEADZONE)
      local ry = stickAxis(pad, "righty", Game.STICK_DEADZONE)
      if rx ~= 0 or ry ~= 0 then
        view:orbit(rx * Game.LOOK_PER_SECOND * (dt or 0),
                   ry * Game.LOOK_RISE_PER_SECOND * (dt or 0))
        return
      end
    end
  end
end

function Game:update(dt)
  require('src.pokemon.Gen4PoketchState').tick(self, dt)
  local panel=self.secondScreenPointerOwner
  local top=self.stack and self.stack.top and self.stack:top()
  if panel and panel~=top and panel.updatePresentation then
    panel:updatePresentation(dt)
  end
  -- Fast-forward scales only the logic clock (see src/core/GameSpeed.lua).
  -- Give the accumulator room for one full frame at the current speed,
  -- or the anti-spiral clamp quietly caps every level above ~15X.
  self:updateCameraStick(dt)
  local speed = self:logicSpeed()
  FixedStep.maxAccum = math.max(0.25, speed * FixedStep.STEP * 1.5)
  do
    local close = FrameProfile.section("  update: fixed steps")
    FixedStep:update(dt * speed)
    close()
  end
  -- Audio runs off real time at a fixed 60Hz regardless of game speed or
  -- display refresh, so fades and chip synthesis keep their intended tempo
  -- whether we are at 1X, 10X, or running with vsync disabled.
  local step = FixedStep.STEP
  self.audioAccum = math.min((self.audioAccum or 0) + dt, 0.25)
  do
    local close = FrameProfile.section("  update: music")
    while self.audioAccum >= step do
      self.audioAccum = self.audioAccum - step
      require("src.core.Music").update(Data)
    end
    close()
  end
  -- Overworld tilt toggle tween: presentational, so it runs on the real
  -- frame dt (not the fixed logic step) for a smooth ~0.25s glide.
  do
    local close = FrameProfile.section("  update: tilt")
    require("src.render.Tilt").update(dt)
    close()
  end
  -- mod render pipelines tween on the same real-frame clock, for the same
  -- reason: they are presentational, so fast-forward must not speed them up
  do
    local close = FrameProfile.section("  pipelines: update")
    require("src.render.Pipelines").update(dt)
    close()
  end
  do
    local close = FrameProfile.section("  update: discord")
    pcall(function() require("src.core.DiscordPresence").update(dt) end)
    close()
  end
  -- Steady-state memory backstop: advance the incremental collector one
  -- small step every rendered frame.  The heavy GPU objects are now freed
  -- explicitly (map eviction, battle exit, canvas/renderer swaps), so this
  -- only has to keep ordinary Lua-heap garbage (per-frame tables/closures)
  -- from drifting upward over a long session, and to spread collection out
  -- so the default lazy schedule never batches it into a visible pause.
  -- ONE INCREMENTAL GC STEP PER FRAME.  Cheap on a small heap and not
  -- obviously cheap under a mod that allocates a world's worth of geometry,
  -- which is exactly the case being measured -- so it is named rather than
  -- assumed.
  if collectgarbage then
    local close = FrameProfile.section("  update: gc step")
    collectgarbage("step", 1)
    close()
  end
end

-- render.zones' identity default: unhooked, the zone list reaches the blit
-- exactly as the owning state computed it
local function sameZones(_, zones) return zones end

-- Dim alpha for a BATTLE BG "world" battle anywhere in the stack, or nil.
-- Same whole-stack rule as fillScaleInStack: a party menu or text box opened
-- during the battle must not drop the dim for a frame.
function Game.worldBgBattleDim(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.bgMode and state:bgMode() == "world" then
      return state.BG_WORLD_DIM or 0.55
    end
  end
  return nil
end

-- Does anything on the stack want the surface scaled to FILL the window
-- (aspect preserved, bars on the long axis) rather than sit at the fixed
-- integer scale?
--
-- Asked of the WHOLE stack, not just the top.  For BATTLE SIZE "fill" that is
-- because the party menu, bag and text boxes a battle opens must not snap the
-- surface back to the fixed scale for a frame; the title screen and intro want
-- it unconditionally, since neither has a world behind it and neither has any
-- reason to sit in a small box in the middle of a large window.
function Game.fillScaleInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.wantsFillScale and state:wantsFillScale() then
      return true
    end
  end
  return false
end

-- A wide battle owns the surface until it leaves the stack.  The party,
-- bag, choice and text states it opens still draw their original 160px UI,
-- but the canvas must not snap to 160px between those states.
function Game.wideBattleInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.isWideBattleLayout and state:isWideBattleLayout() then
      return state
    end
  end
  return nil
end

-- ...AND A STATE THAT WIDENED ITS OWN SURFACE HOLDS IT THE SAME WAY.
--
-- Whole-stack, for the reason above, and separate from wideBattleInStack
-- because it is not the same layout: BATTLE LAYOUT = WIDE on a Hoenn
-- cartridge keeps EMERALD's composition and grows its surface to the window
-- (BattleState:holdsUISurface), and every menu, bag and dialogue box that
-- battle opens is itself a Gen 3 screen asking for the GBA's 240x160.
-- nativeSurfaceInStack takes the TOPMOST state with a uiSize, so without this
-- the surface would snap back to 240 for exactly those frames and the battle
-- underneath would redraw its wider composition clipped at the right edge.
--
-- Nothing in Gen 1, Gen 2 or Prism answers this, so nothing there changes.
function Game.heldSurfaceInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.holdsUISurface and state:holdsUISurface() then
      return state
    end
  end
  return nil
end

-- THE SURFACE A STATE ASKS FOR, held for the whole stack above it.
--
-- Same shape and the same reason as wideBattleInStack: a screen that wants a
-- surface other than the Game Boy's keeps it while the menus and boxes it
-- opens are on top, or the canvas snaps back to 160x144 for exactly those
-- frames and the screen underneath redraws at the wrong size.  A Gen 3 screen
-- asks for the GBA's 240x160; nothing in Gen 1 or Gen 2 asks for anything.
-- Does this state want exactly the surface currently in use?  See the
-- ownsSurface note in Game:draw -- more than one state can want the same
-- surface, and every one of them draws in it rather than being centred in it.
function Game.wantsThisSurface(state)
  if not (state and state.uiSize) then return false end
  local ok, w, h = pcall(state.uiSize, state)
  if not ok then return false end
  local uw, uh = Renderer:uiSize()
  return w == uw and h == uh
end

function Game.nativeSurfaceInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.uiSize then return state end
  end
  return nil
end

-- Whether a state on the stack composes its own screen and so wants the
-- edge anchors held off (BattleState.holdsUIAnchors).  Whole-stack, like
-- everything else here: the text box and YES/NO a battle puts up are states
-- of their own sitting above it, and they are exactly the elements that must
-- stay inside the battle's composition rather than dock to the window.
-- UI LAYOUT: is edge docking switched on?  Only the explicit "dynamic" turns
-- it on, so a save written before the option existed -- and any caller with no
-- save at all, which is most of the headless suites -- gets CENTERED, the
-- behaviour the port shipped with.
function Game.dynamicUI(save)
  local options = save and save.options
  return options ~= nil and options.uiLayout == "dynamic"
end

function Game.uiAnchorsHeldInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.holdsUIAnchors then return true end
  end
  return false
end

-- MAY THE LETTERBOX BE PAINTED WITH THE SURFACE'S OWN EDGE?
--
-- Renderer:bleedEdges pulls the outermost row and column of a Gen 3 screen
-- outward so a menu's border appears to run to the edge of the window.  That
-- is right for a PANEL -- a window frame drawn over something -- because its
-- outermost column IS the frame, and wrong for anything that composes a
-- picture of its own, because there the outermost column is artwork and
-- smearing it duplicates artwork instead of extending a border.
--
-- The battle was the first screen to say so and says it through holdsUIAnchors
-- (see Renderer).  The rest say it here: the title, the attract movie, the
-- main menu and the START menu are all composed screens, and all four were
-- being stretched.  Reported from play: "fix the stretching of borders on the
-- start menu, main menu, main menu intro and the continue, new game, options,
-- exit menus -- instead make them full screen/fit the screen without
-- stretching".  They already fill as far as they can without distorting;
-- wantsFillScale scales the surface to the window with the aspect kept.  What
-- was left over was the smear, and this is what turns it off.
--
-- Asked of the WHOLE stack and answered by the first refusal, for the same
-- reason the other two are: a menu opened over one of these -- OPTION from
-- the main menu, SAVE from the START menu, a text box over either -- must not
-- switch the smear back on for the frames it is up.
function Game.edgeBleedAllowedInStack(stack)
  for i = #(stack and stack.states or {}), 1, -1 do
    local state = stack.states[i]
    if state and state.wantsEdgeBleed and not state:wantsEdgeBleed() then
      return false
    end
  end
  return true
end

-- Where Game:draw starts drawing this frame.  Normally the topmost opaque
-- state (StateStack:visibleBase) -- but BATTLE BG "world" composes the battle
-- over the LIVE map, and an opaque state pushed on top of it (the party menu,
-- the bag) becomes that base, cutting the overworld -- and with it the world
-- pass -- out of the frame entirely.  The backdrop the battle established
-- then collapses to endFrame's flat black clear for as long as the menu is
-- up.  So a world-bg battle keeps the frame starting from underneath itself
-- until it leaves the stack, the same hold uiFill and the dim already use.
--
-- Only the START of the draw moves.  The clear stays keyed to the real
-- visibleBase, so the menu still gets its opaque canvas and draws exactly as
-- before; what changes is the window AROUND its letterbox, which keeps
-- showing the map instead of going black.  Both menus fill their own
-- 160x144 field first, so nothing beneath them shows through it.
function Game.drawBaseInStack(stack, visibleBase)
  local states = stack and stack.states or {}
  for i = visibleBase - 1, 1, -1 do
    local state = states[i]
    if state and state.bgMode and state:bgMode() == "world" then
      -- restart the search from under the battle: the highest opaque state at
      -- or below it (the overworld), not the menu sitting over it
      for j = i, 1, -1 do
        if states[j].isOpaque then return j end
      end
      return 1
    end
  end
  return visibleBase
end

-- Shift classic SGB zones to the centred UI. A full-width base zone extends
-- into both margins, keeping the canvas' paper color continuous; narrower
-- sprite and status zones move with the classic UI content.
local function centerClassicZones(zones, offset)
  if not zones or offset == 0 then return zones end
  local surfaceW = select(1, Renderer:uiSize())
  local shifted = {}
  for i, zone in ipairs(zones) do
    local copy = {}
    for key, value in pairs(zone) do copy[key] = value end
    if copy.x == 0 and copy.w == Renderer.WIDTH then
      copy.w = copy.w + offset * 2
    elseif (copy.x or 0) == 0 and (copy.w or 0) >= surfaceW then
      -- ALREADY IN SURFACE COORDINATES, and nothing needs to be known about
      -- who drew it to say so: a zone that starts at the left edge and is at
      -- least as wide as the surface was laid out across the surface.  Moving
      -- it can only take it OFF the thing it covers.
      --
      -- The guard above decides this by asking the owner, and that is the
      -- right question; this is the same answer read off the zone itself, so
      -- a caller that gets the owner wrong cannot slide a whole-screen zone
      -- out from under the screen.  What that cost when it happened: Emerald's
      -- battle publishes exactly one zone, a full-screen `colors == false`
      -- true-colour opt-out, and shifted by 40 it stopped covering the frame
      -- it was exempting -- so the shade-remap shader ran over a full-colour
      -- GBA battle and every pixel of it came out grey.
    else
      copy.x = (copy.x or 0) + offset
    end
    shifted[i] = copy
  end
  return shifted
end

-- Published so the rule can be stated without driving a whole frame: this
-- decision is invisible in a screenshot -- the symptom is a colour, not an
-- offset -- so it needs to be checkable on its own.
function Game.zonesNeedCentering(zoneOwner, classicOffset)
  if (classicOffset or 0) == 0 or not zoneOwner then return false end
  if zoneOwner.isWideBattleLayout and zoneOwner:isWideBattleLayout() then
    return false
  end
  return not Game.wantsThisSurface(zoneOwner)
end

-- WHERE A STATE THAT DOES NOT OWN THE SURFACE IS CENTRED IN IT.
--
-- Every such state used to be centred as though it were 160x144, because
-- every such state WAS one: the only surfaces wider than the Game Boy's were
-- the wide battle's 304x144 and the GBA's 240x160, and anything that did not
-- own one of those was a Game Boy screen drawn in Game Boy coordinates.
--
-- BATTLE LAYOUT = WIDE on a Hoenn cartridge ends that.  The battle asks for a
-- surface derived from the window -- 320 pixels on a 1920x1080 screen -- and
-- the party menu, the bag and the dialogue box it opens are GEN 3 screens:
-- they ask for 240x160, which is neither the surface in use nor the Game
-- Boy's.  Centring one of those by (320 - 160) / 2 = 80 puts a 240-wide
-- screen at x = 80 and hangs eighty pixels of it off the right edge.  Its own
-- centre is (320 - 240) / 2 = 40.
--
-- So the offset is asked of the STATE, by the size it actually laid itself out
-- in.  A state with no uiSize -- every Game Boy screen, and every state on a
-- Gen 1, Gen 2 or Prism cartridge -- answers 160x144 and gets the arithmetic
-- it always got, to the pixel.
local function homeOffset(state, uw, uh)
  local sw, sh = Renderer.WIDTH, Renderer.HEIGHT
  if state and state.uiSize then
    local ok, w, h = pcall(state.uiSize, state)
    if ok and type(w) == "number" and type(h) == "number" then sw, sh = w, h end
  end
  return math.floor((uw - sw) / 2), math.floor((uh - sh) / 2)
end

Game.homeOffset = homeOffset

Game.centerClassicZones = centerClassicZones

function Game:draw()
  local closeDraw = FrameProfile.section("draw: whole frame")

  -- A specialized lower-screen state (battle menu, mining, Poketch screen)
  -- claims the panel by calling SecondScreen.draw during _draw(). If nothing
  -- claims it, a Gen 4 overworld still needs Platinum's always-present Poketch.
  self.secondScreenDrawnThisFrame = false
  self.secondScreenPointerOwner = nil
  self:_draw()

  -- Single-screen generations use the physical Android lower panel as a live
  -- save companion without changing the game's own screen mode.
  do
    local okC, Companion = pcall(require, "src.ui.SaveCompanion")
    if okC and Companion and Companion.tick then pcall(Companion.tick, self) end
  end

  do
    local okSS, SS = pcall(require, "src.ui.SecondScreen")
    if okSS and SS.mode and SS.mode(self) == "display"
       and not self.secondScreenDrawnThisFrame then
      local okP, Poketch = pcall(require, "src.ui.Gen4Poketch")
      if okP and Poketch and Poketch.new then
        if not self.secondScreenOverworldPoketch then
          local okNew, p = pcall(Poketch.new, self, {})
          if okNew then self.secondScreenOverworldPoketch = p end
        end
        local p = self.secondScreenOverworldPoketch
        if p and p.drawWatch then
          local drawn=pcall(SS.draw, self, function() p:drawWatch() end)
          if drawn then self.secondScreenPointerOwner=p end
        end
      end
    end
  end

  closeDraw()
  -- THE SECOND PANEL'S FRAME LEAVES LAST.
  --
  -- In `display` mode the bottom screen was rendered to an offscreen canvas
  -- somewhere inside the draw above, and this is what hands it to the device's
  -- own panel.  It has to be after the whole frame rather than inside it,
  -- because a screen that draws late -- anything pushed over the battle -- still
  -- has to get out, and because the GPU readback wants the drawing finished.
  -- A no-op in every other mode and on every machine with one screen.
  do
    local okSS, SS = pcall(require, "src.ui.SecondScreen")
    if okSS and SS.flush then pcall(SS.flush, self) end
  end
  FrameProfile.frame()
end

-- F11 turns the profiler on and off.  Read in keypressed above the delegation,
-- with the other escape hatches, for the same reason they are: the frames you
-- most want to measure are the ones where something is holding the keyboard.
function Game:toggleFrameProfile()
  return FrameProfile.toggle()
end

function Game:_draw()
  -- the UI canvas clears transparent when the overworld's world pass
  -- shows through beneath it; opaque full-screen states get the classic
  -- white clear
  local base = self.stack:visibleBase()
  local worldBelow = self.stack.states[base] == self.overworld
  -- a world-bg battle keeps the map drawing under whatever it opened, so the
  -- world pass can run for a frame whose CLEAR is still an opaque menu's
  local drawFrom = Game.drawBaseInStack(self.stack, base)
  local worldDrawn = self.stack.states[drawFrom] == self.overworld
  -- A wide battle holds its 304px surface through every menu or prompt it
  -- opens. States that do not draw the wide battle composition are centred
  -- in that surface below, so their classic coordinates and hit testing stay
  -- unchanged. Outside a battle, including the title screen, the option is
  -- intentionally inactive because it is a battle-layout setting.
  local wideBattle = Game.wideBattleInStack(self.stack)
  -- ...and a Gen 3 battle that widened its own screen holds it the same way,
  -- ahead of the topmost-uiSize pick (see Game.heldSurfaceInStack).
  local held = not wideBattle and Game.heldSurfaceInStack(self.stack) or nil
  local native = not wideBattle
    and (held or Game.nativeSurfaceInStack(self.stack)) or nil
  local classicOffset, classicOffsetY = 0, 0
  if wideBattle and wideBattle.uiSize then
    Renderer:setUISize(wideBattle:uiSize())
    classicOffset = math.floor((select(1, Renderer:uiSize()) - Renderer.WIDTH) / 2)
  elseif native then
    Renderer:setUISize(native:uiSize())
    -- ...and a state that did NOT ask for the bigger surface is centred in
    -- it, the way the wide battle centres its menus: its layout is in Game
    -- Boy coordinates and must land in the middle rather than in a corner.
    local uw, uh = Renderer:uiSize()
    classicOffset = math.floor((uw - Renderer.WIDTH) / 2)
    classicOffsetY = math.floor((uh - Renderer.HEIGHT) / 2)
  else
    Renderer:setUISize(Renderer.WIDTH, Renderer.HEIGHT)
  end
  -- the surface every state below is either drawing in or being centred
  -- inside, resolved before any of them draws
  local surfW, surfH = Renderer:uiSize()
  -- BATTLE SIZE: scale the battle surface to the window instead of the
  -- classic integer letterbox.  Read from the whole stack, not just the top,
  -- so a party menu or text box opened mid-battle keeps the same surface.
  Renderer.uiFill = Game.fillScaleInStack(self.stack)
  -- BATTLE BG "world": dim the overworld the battle is drawn over.  Read off
  -- the stack for the same reason as uiFill above -- a prompt opened during
  -- the battle must not drop the dim for a frame.
  Renderer.battleDim = Game.worldBgBattleDim(self.stack)
  -- ...and for the same reason the UI's own scale has to know the world is
  -- still the backdrop while an opaque menu covers it.  Renderer:uiScale
  -- steps the UI down with the survey zoom only while a world is behind it,
  -- gated on this frame's world pass -- which the party menu and the bag end
  -- by being opaque.  Without this hold they lose the step-down and blit at
  -- full fit scale over a battle drawn at the zoomed-out one.
  Renderer.uiWorldHold = Renderer.battleDim ~= nil
  -- ...and a battle keeps its dialogue box and YES/NO inside its own screen
  -- instead of letting them dock to the window edge.
  -- UI LAYOUT: CENTERED (the default) is a fixed letterbox -- every element
  -- stays inside the 160x144 canvas and the UI does not follow the survey
  -- zoom, so the screen furniture never moves or resizes under the player.
  -- That is the composition the port shipped with.  DYNAMIC opts into both
  -- halves: the dialogue box docks to the window's bottom edge, the START
  -- menu to its top right, and the whole UI steps down with the zoom.
  Renderer.uiCentered = not Game.dynamicUI(self.save)
  Renderer.uiAnchorHold = Game.uiAnchorsHeldInStack(self.stack)
  Renderer:beginFrame(worldBelow)
  for i = drawFrom, #self.stack.states do
    local state = self.stack.states[i]
    local wideState = state and state.isWideBattleLayout
      and state:isWideBattleLayout()
    -- A STATE THAT ASKED FOR THIS SURFACE DRAWS IN IT DIRECTLY; everything
    -- else is Game Boy sized and gets centred.
    --
    -- "Asked for it" used to mean "is the one nativeSurfaceInStack picked",
    -- which is the TOPMOST state with a uiSize.  That was fine while exactly
    -- one state ever wanted the bigger surface.  It stopped being fine when
    -- the field started asking for the same one as the dialogue box over it:
    -- the box was the topmost, so the FIELD -- drawing in the very
    -- coordinates it had just asked for -- was treated as a Game Boy layout
    -- and shoved forty pixels sideways the moment anybody spoke.
    --
    -- So ask each state instead of trusting the pick: a state owns the
    -- surface when the size it wants IS the size in use.
    local ownsSurface = wideState
      or (native ~= nil and state == native)
      or Game.wantsThisSurface(state)
    if state and state.draw then
      -- ...and it is centred by ITS OWN size, not by the Game Boy's (see
      -- Game.homeOffset).  classicOffset still gates it: a surface that is
      -- the Game Boy's centres nothing, which is every frame outside a wide
      -- battle and every Gen 1 / Gen 2 / Prism frame inside one.
      local ox, oy = 0, 0
      if (classicOffset ~= 0 or classicOffsetY ~= 0) and not ownsSurface then
        ox, oy = homeOffset(state, surfW, surfH)
      end
      if ox ~= 0 or oy ~= 0 then
        love.graphics.push()
        love.graphics.translate(ox, oy)
        state:draw()
        love.graphics.pop()
      else
        state:draw()
      end
    end
  end
  -- SGB colorization: the topmost state that knows its palette owns the
  -- screen (overlays like text boxes inherit from what's beneath them);
  -- the overworld's world pass colors each visible map area separately
  local zones, worldZones, zoneOwner
  for i = #self.stack.states, 1, -1 do
    local s = self.stack.states[i]
    if s.sgbPalettes then
      zones = s:sgbPalettes(self)
      zoneOwner = s
      break
    end
  end
  -- Zones are in the coordinates of whatever DREW them, so only a Game Boy
  -- sized state's zones need re-centring in a wider surface.  A state that
  -- asked for the surface already laid its zones out across all of it, and
  -- shifting those by the centring offset moves the exemption off the thing
  -- it was exempting -- which on the Gen 3 title is the whole screen.
  --
  -- ASKED BY SIZE, NOT BY IDENTITY.  This used to test `zoneOwner == native`,
  -- and `native` is the TOPMOST state carrying a uiSize -- so the moment
  -- anything sat above the state that owns the zones and answered the same
  -- 240x160, the two stopped being the same object and every zone slid 40
  -- pixels right.  On Emerald's battle screen that is the whole bug: its zone
  -- list is one full-screen `colors == false` rect, the true-colour opt-out,
  -- and shifted by 40 it no longer covers the screen it was exempting.  The
  -- shade-remap shader then ran over the lot, and a full-colour GBA battle --
  -- the extracted terrain, the mon, the panels -- came out in four shades of
  -- grey.  Nothing about it looked like an offset, because the offset was
  -- applied to the exemption rather than to the art.
  --
  -- The DRAW path a dozen lines up already asks the right question
  -- (`Game.wantsThisSurface`): does this state lay itself out across the
  -- surface currently in use?  More than one state can, and every one of them
  -- draws in it rather than being centred in it.  Zones follow their drawer,
  -- so they have to be asked the same question, and now they are.
  -- ...and by the ZONE OWNER's own size, for the same reason the draw above
  -- is: a 240-wide Gen 3 menu laid its zones out across 240 pixels and they
  -- belong forty pixels into a 320-wide surface, not eighty.  The gate is
  -- still classicOffset, so a Game Boy surface shifts nothing.
  local zoneOffset = classicOffset
  if classicOffset ~= 0 and zoneOwner then
    zoneOffset = select(1, homeOffset(zoneOwner, surfW, surfH))
  end
  if Game.zonesNeedCentering(zoneOwner, zoneOffset) then
    zones = centerClassicZones(zones, zoneOffset)
  end
  -- 14's render.zones: weather/lighting overlays and custom colorization
  -- recolor or add zones before the blit
  if ModRuntime.wantsHook("render.zones") then
    zones = ModRuntime.call("render.zones", sameZones, self, zones)
  end
  -- Keyed to whether the map actually DREW, not to whether it is the clear's
  -- base: an opaque menu over a world-bg battle still renders the world pass
  -- (drawBaseInStack), and leaving worldZones nil there drops endFrame's
  -- world blit onto the UI zone list instead -- the party menu's own HP-bar
  -- palettes, in 160x144 space, smeared across a world-canvas-sized image.
  -- That is the offset, red-for-green map behind the menu.
  if worldDrawn and self.overworld.sgbWorldZones then
    worldZones = self.overworld:sgbWorldZones()
  end
  local viewport = Renderer:endFrame(zones, worldZones)
  -- Persistent tool status is screen-space UI: draw it over the completed
  -- render pipeline with exact playfield/margin geometry, but below mobile
  -- controls. It never becomes an updating game state.
  if ModRuntime.wantsHook("render.hud") then
    ModRuntime.call("render.hud", function() end, self, viewport)
  end
  -- on-screen mobile controls: pure screen-space, over the finished frame
  TouchControls:draw()
end

-- overworld survey zoom: wheel up / '=' zooms in, wheel down / '-' out
function Game:zoomStep(delta)
  local view=self:zoomView()
  if view and self.stack:top()==self.overworld then view:zoomBy(-delta);return end
  local Zoom = require("src.render.Zoom")
  if not Zoom.gateOK(self.stack:top(), self.overworld) then return end
  local offset = Zoom.step(delta, Renderer:fitScale())
  if self.save and self.save.options then
    self.save.options.zoom = offset
    self:writeOptions()
  end
end

function Game:wheelmoved(_, dy)
  -- THE WHEEL ZOOMS THE FREE CAMERA when one owns the frame, and the
  -- window otherwise.
  --
  -- Requested: *"add the zoom in and out feature to the third person"*.
  -- `Game:freeView` is nil on every other map and camera, so the display
  -- zoom below keeps every case it had -- and in third person the wheel
  -- means the thing the player is looking at rather than the size of the
  -- window it is in, which is what a wheel means in every 3D game.
  local view = self:zoomView()
  if view and view.zoomBy then
    view:zoomBy(dy > 0 and -1 or 1)
    return
  end
  if dy > 0 then
    self:zoomStep(1)
  elseif dy < 0 then
    self:zoomStep(-1)
  end
end

-- WHEN THE STACK IS EMPTIED AND NOBODY PUSHES ANYTHING BACK.
--
-- Traced from play, straight out of the log:
--
--   push src/ui/Menu.lua:111 (depth 2)    <- a mod's battle-settings menu
--   pop  src/ui/Menu.lua:111 (depth 1)    <- CANCEL closes it, correctly
--   [DRAMATIC_SHAPE] CANCEL in Gen3 battle settings
--   pop  mods/.../follower/control_engine.lua:2578 (depth 0)   <- and again
--
-- The second pop took the OVERWORLD off.  With nothing on the stack nothing
-- updates and nothing draws, so the frame keeps whatever the last clear left:
-- a white screen that never goes away, with no error in the log, because
-- popping is not an error.  Cancelling a menu that has already cancelled
-- itself is an easy mistake for a mod to make and an invisible one from the
-- inside -- reported three times as "a white screen that doesnt go away".
--
-- The engine empties the stack deliberately in exactly two places -- New Game
-- and Load -- and both push the replacement in the same breath, so an empty
-- stack ACROSS A FRAME BOUNDARY is always a fault.  That is why this is
-- checked at the top of the logic step and not inside pop(): here it cannot
-- mistake a drain for a leak, and it needs no cooperation from the caller.
--
-- The world is put BACK rather than entered again: it never exited (the
-- overworld has no exit), and entering it would call setMap and boot the map
-- over the top of the player.  Returns true when the step should stop.
function Game:ensureStack()
  local stack = self.stack
  if not (stack and stack.states) or stack.states[1] ~= nil then return false end
  local world = self.overworld
  if world and world.map then
    Logger.warn("the state stack was emptied and nothing pushed anything back "
      .. "-- with no state there is nothing to update and nothing to draw, "
      .. "which is a screen that never changes. Restoring the overworld; "
      .. "something popped one state too many, and the push/pop trace above "
      .. "names it.")
    stack:restore(world)
    return false
  end
  Logger.warn("the state stack was emptied and there is no world to put back; "
    .. "returning to the title screen")
  self:returnToTitle()
  return true
end

-- F10, as its own method so the escape-hatch block above can reach it without
-- going through the delegation it exists to jump over.  Toggle: the manager no
-- longer swallows the keyboard, so a second press closes it rather than
-- stacking another.  This is the route to turning a misbehaving mod OFF, which
-- is why it must not be swallowable.
function Game:toggleModManager()
  local top = self.stack and self.stack:top()
  if top and top.screenId == "ManagerState" then
    self.stack:pop()
  else
    Screens.push(self, "ManagerState")
  end
end

-- THE WAY OUT OF A STATE THAT WILL NOT LET GO.
--
-- Reported twice from play, both times under a mod that draws the field in 3D:
-- "no input is working at all ... i cant look around walk or open any menus".
-- Nothing had crashed.  A state was sitting on top of the stack that should
-- have been popped and was not, and the first line of keypressed below hands
-- EVERY key to the top state's onKeyPressed without condition -- so the mod
-- manager, the save keys, the zoom, the dev console and the only route to
-- turning the offending mod off all went into the same hole as the D-pad.
--
-- F9 says what is on the stack and takes the top of it off.  It is above the
-- delegation on purpose: an escape hatch a state can swallow is not one.  And
-- it refuses to pop the overworld, because "input is dead while the overworld
-- is on top" is a different fault with a different answer, and closing the
-- world would replace a stuck game with no game.
function Game:unstick()
  local stack = self.stack
  if not (stack and stack.states) then return end
  Logger.warn("unstick (F9): %s", stack:describeAll())
  local top = stack:top()
  if not top then
    Logger.warn("unstick: the stack is empty; nothing to pop")
    Logger.flush()
    return
  end
  if top == self.overworld or top.isOverworld then
    Logger.warn("unstick: the overworld is already on top, so no state is "
      .. "holding input -- whatever is eating it is inside the world itself")
    Logger.flush()
    return
  end
  local name = StateStack.describe(top)
  local before = #stack.states
  -- A state whose exit throws -- or whose screen.popped listener does -- must
  -- not be able to stay on top BECAUSE it threw; that is the same trap twice.
  local ok, err = pcall(stack.pop, stack)
  if not ok then
    if #stack.states == before then table.remove(stack.states) end
    Logger.warn("unstick: %s threw on the way out (%s); removed it anyway",
                name, tostring(err))
  end
  Logger.warn("unstick: popped %s -- stack is now %s", name,
              stack:describeAll())
  Logger.flush()
end

-- STEP THE GEN 4 FIELD CAMERA, or say it was not ours to step.
--
-- One implementation for two ways in: the "3" hotkey below, and the R button,
-- which the overworld routes here so a phone can reach the ladder at all
-- (requested: "allow user to use the R button to switch between camera tilt
-- options"). Returns false off a Sinnoh map, which is what lets "3" fall
-- through to the Game Boy tilt it has always cycled.
function Game:cycleGen4CameraTilt()
  local ow = self.overworld
  local renderer = ow and ow.map and ow.map.renderer
  if not (renderer and renderer.gen4Ground) then return false end
  local Gen4Camera = require("src.render.Gen4Camera")
  local Tilt = require("src.render.Tilt")
  -- not `next`: that is a Lua global and shadowing it here is a trap for
  -- whoever edits this next
  local nextIndex = (Gen4Camera.chosen % #Gen4Camera.TILTS) + 1
  local _, index = Gen4Camera.setTilt(nextIndex)
  self.save.options.gen4CameraTilt = index
  -- ...and the other tilt goes to OFF and stays there, so a save that carried
  -- a tilt level in from a Johto session cannot warp Sinnoh.
  if Tilt.level > 0 then
    Tilt.setLevel(0)
    self.save.options.tilt = 0
  end
  return true
end

function Game:keypressed(key)
  -- ...ahead of the delegation below, which is unconditional.
  if key == "f9" then return self:unstick() end
  if key == "f11" then return self:toggleFrameProfile() end
  if key == "f10" then return self:toggleModManager() end
  if self.stack and self.stack:top() and self.stack:top().onKeyPressed then
    self.stack:top():onKeyPressed(key)
    return
  end
  if devMode and key == "f5" then
    require("src.dev.HotReload").run(self)
    return
  end
  if devMode and key == "`" then
    self.stack:push(require("src.dev.Console").new(self))
    return
  end
  if key == "f1" then
    self:writeSave()
    return
  elseif key == "f2" then
    local loaded, recovered = SaveData.load()
    if loaded then self:restoreSave(loaded, recovered) end
    return
  elseif key == "-" then
    self:zoomStep(-1)
    return
  elseif key == "=" then
    self:zoomStep(1)
    return
  elseif key == "2" then
    -- cycle COLORS (GBC / OG / OG INV / GBC INV / CLASSIC); the pack change
    -- forces Game.overworld:reloadMap, which rebuilds the live NPC array, so
    -- hold it while a warp/transition or an on-screen scripted cutscene is
    -- driving the overworld rather than tear the escort's NPCs out mid-move
    local ow = self.overworld
    local top = self.stack:top()
    local busy = ow and (ow.transitioning
      or (top == ow and (
           (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
        or (ow.scriptMoves and #ow.scriptMoves > 0)
        or ow.engaging or ow.emote)))
    if not busy then
      local PaletteFX = require("src.render.PaletteFX")
      self.save.options.colors = PaletteFX.cycleMode()
      self:writeOptions()
    end
    return
  elseif key == "3" then
    -- cycle TILT OFF → 15 → 35 → 50 → OFF (mnemonic: 3D), free-roam only
    local Tilt = require("src.render.Tilt")
    if Tilt.gateOK(self.stack:top(), self.overworld) then
      -- ON A SINNOH MAP THIS KEY MOVES THE GEN 4 CAMERA INSTEAD.
      --
      -- There are two tilts in this engine and they are not alternatives: the
      -- one above is the Gen 1/2 warp applied to a finished flat picture, and
      -- `Gen4Camera` is the actual field camera the cartridge's own header
      -- names.  Pressing "3" in Sinnoh used to run the first, which warped a
      -- world that had already been projected and dragged the ground out from
      -- under the sprites -- reported as *"messes up the placement of sprites
      -- and isnt changing the in game camera tilt/angle"*.  Both complaints,
      -- one cause.
      -- LIFTED INTO A METHOD so the R button can step the same ladder without
      -- a second copy of it -- see `Game:cycleGen4CameraTilt`.
      if self:cycleGen4CameraTilt() then
        -- handled
      else
        self.save.options.tilt = Tilt.cycle()
      end
      self:writeOptions()
    end
    return
  elseif key == "," or key == "." or key == ";" or key == "'" then
    -- THE ORBIT CONTROLS, and they exist only where there is a camera to orbit.
    --
    -- Reported from play: *"theres no free movement or orbital camera"*.  The
    -- free camera was pinned to the player's own facing, so it could only ever
    -- look the way they were walking -- never AT them, never round a building.
    --
    -- Four keys rather than a modifier because the arrows already move the
    -- player, and these two pairs sit together under the right hand.  They do
    -- NOTHING unless the tilt ladder is on `third` or `first`, so they stay free
    -- for everything else in the engine and on every other cartridge.
    local ow = self.overworld
    local renderer = ow and ow.map and ow.map.renderer
    local ground = renderer and renderer.gen4Ground
    local view = ground and ground.view3d
    if view and view.isFree and view:isFree() and view.orbit then
      local Gen4View = require("src.render.Gen4View")
      if key == "," then view:orbit(-Gen4View.ORBIT_YAW_STEP, 0)
      elseif key == "." then view:orbit(Gen4View.ORBIT_YAW_STEP, 0)
      elseif key == ";" then view:orbit(0, Gen4View.ORBIT_RISE_STEP)
      else view:orbit(0, -Gen4View.ORBIT_RISE_STEP) end
      -- The ground places the camera from the player every frame, so nothing
      -- has to be redrawn here -- the next `follow` reads the new angles.
    end
    return
  elseif key == "4" then
    -- cycle ZOOM through every integer level (survey → FIT → close-up → wrap)
    local Zoom = require("src.render.Zoom")
    if Zoom.gateOK(self.stack:top(), self.overworld) then
      self.save.options.zoom = Zoom.cycle(Renderer:fitScale())
      self:writeOptions()
    end
    return
  elseif key == "5" then
    -- cycle GBC FX OFF → 1 → 2 → 3 → 4 (unlit-GBC ladder); always on
    -- desktop.  Mobile refuses the present shader (issue #136).
    local GBCFX = require("src.render.GBCFX")
    if not GBCFX.isSupported() then return end
    self.save.options.gbcfx = GBCFX.cycle()
    self:writeOptions()
    return
  end
  -- Mod render pipelines claim their hotkeys last, so one can never shadow
  -- an engine display key however a mod declares it (12 §rendering
  -- pipelines).  syncOptions writes the whole ladder back, including the
  -- tilt exclusion a world pipeline forces.
  local Pipelines = require("src.render.Pipelines")
  if Pipelines.hotkey(key, self.stack:top(), self.overworld) then
    Pipelines.syncOptions(self.save.options)
    require("src.render.Tilt").setLevel(self.save.options.tilt or 0)
    self:writeOptions()
    return
  end
  Input:keypressed(key)
end

function Game:textinput(text)
  local top = self.stack and self.stack:top()
  if top and top.onTextInput then
    top:onTextInput(text)
  end
end

-- Mod enablement is stored with persistent options.  Restarting the actual
-- LÖVE process ensures scripts, registries, and assets are all rebuilt from
-- the newly selected mod state.
function Game:restartWithMods()
  require("src.core.HostShell").restart()
end

-- Leave this game and go back to the launcher's game list.
--
-- Not returnToTitle's neighbour by accident: the two are the two halves of
-- "put this down".  returnToTitle stays inside the cartridge and lands on its
-- own CONTINUE / NEW GAME menu; this one leaves the cartridge entirely.  The
-- menus that used to call love.event.quit for the second case were killing
-- the process instead, which is only the right answer on a build with no
-- launcher behind it -- and HostShell decides that, not the menu.
function Game:returnToLauncher()
  require("src.core.Music").stop()
  require("src.core.HostShell").toLauncher()
end

-- Releases reach Input even while a top state captures raw input: a
-- swallowed key-up would strand a held-state flag for a key Input saw go
-- down before the capture armed (the stuck-flag hazard Input:reset
-- exists for).  The top state only OBSERVES the release afterwards,
-- unlike onKeyPressed above which owns the press, so BindingsMenu can
-- commit a capture on the key-up (#589).
function Game:keyreleased(key)
  Input:keyreleased(key)
  local top = self.stack and self.stack:top()
  if top and top.onKeyReleased then top:onKeyReleased(key) end
end

function Game:gamepadpressed(joystick, button)
  -- a controller is being used: the touch overlay steps aside until the
  -- next screen touch (mobile only; a no-op elsewhere)
  TouchControls:noteGamepad()
  -- BindingsMenu's pad capture rides the same top-state routing as keys
  local top = self.stack and self.stack:top()
  if top and top.onGamepadPressed then
    top:onGamepadPressed(button)
    return
  end
  Input:gamepadpressed(joystick, button)
end

function Game:gamepadreleased(joystick, button)
  -- same observe-after-Input contract as Game:keyreleased (#589)
  Input:gamepadreleased(joystick, button)
  local top = self.stack and self.stack:top()
  if top and top.onGamepadReleased then top:onGamepadReleased(button) end
end

function Game:gamepadaxis(joystick, axis, value)
  -- past-deadzone only, so resting-stick drift can't hide the overlay
  if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
  Input:gamepadaxis(joystick, axis, value)
end

-- conf.lua turns the mobile accelerometer-joystick off (#468), but guard the
-- generic joystick path anyway: any sensor-style device that still reaches us
-- has gravity pinning an axis past the deadzone, which would hide the touch
-- overlay every instant and steer the player by tilt through the axis-1/2
-- mapping (#459).  Real controllers arrive as SDL gamepads or named sticks,
-- never as "* Accelerometer".
local function isAccelerometer(joystick)
  local name = joystick and joystick.getName and joystick:getName()
  return name ~= nil and name:lower():find("accelerometer", 1, true) ~= nil
end

-- BindingsMenu's raw-stick capture rides the same top-state routing as the
-- keyboard and gamepad paths (#632).  Only a stick SDL does not recognize
-- as a gamepad reaches the capture: a recognized pad raises BOTH
-- joystickpressed and gamepadpressed for one press, and the joystick half
-- would otherwise beat its own gamepadpressed to the armed row and record
-- "JOY1" for a button the player can plainly see is A.  Same predicate as
-- Input's, kept local here so Game never reaches into Input's internals.
local function isRawStick(joystick)
  return not (joystick and joystick.isGamepad and joystick:isGamepad())
end

function Game:joystickpressed(joystick, button)
  if isAccelerometer(joystick) then return end
  TouchControls:noteGamepad()
  local top = self.stack and self.stack:top()
  if isRawStick(joystick) and top and top.onJoystickPressed then
    top:onJoystickPressed(button)
    return
  end
  Input:joystickpressed(joystick, button)
end

function Game:joystickreleased(joystick, button)
  if isAccelerometer(joystick) then return end
  -- same observe-after-Input contract as Game:keyreleased (#589): the
  -- capture watches the release, it never owns it, so a held-state flag
  -- Input saw go down before the capture armed cannot be stranded
  Input:joystickreleased(joystick, button)
  local top = self.stack and self.stack:top()
  if isRawStick(joystick) and top and top.onJoystickReleased then
    top:onJoystickReleased(button)
  end
end

function Game:joystickaxis(joystick, axis, value)
  if isAccelerometer(joystick) then return end
  if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
  Input:joystickaxis(joystick, axis, value)
end

function Game:joystickhat(joystick, hat, direction)
  if isAccelerometer(joystick) then return end
  if direction ~= "c" then TouchControls:noteGamepad() end
  Input:joystickhat(joystick, hat, direction)
end

-- Window focus/visibility flips: a release due while unfocused/hidden can
-- be swallowed by the OS. Reset on both edges -- gaining focus with a
-- physically held key won't re-fire keypressed, so trusting leftover
-- state is worse than asking the player to re-press.
function Game:focus(f)
  Input:reset()
  TouchControls:reset()
  self:audioSession(f, "focus")
end

function Game:visible(v)
  Input:reset()
  TouchControls:reset()
  self:audioSession(v, "visibility")
end

-- AN INCOMING PHONE CALL IS AN AUDIO-SESSION LOSS, NOT A WINDOW EVENT.
--
-- Reported from play: "on iOS when they got a phone call the game would
-- crash".  iOS gives the audio session to the phone app for the length of the
-- call, and SDL reports that to the app as SDL_APP_WILLENTERBACKGROUND /
-- SDL_APP_DIDENTERBACKGROUND -- which arrives *here*, because LOVE maps those
-- onto love.focus(false) / love.visible(false).  OpenAL's device is
-- invalidated at that moment, and the chip music path queues into its
-- QueueableSource on EVERY frame (ChipAudio.update, driven from Game:update
-- above), so within one frame the game is making AL calls against a device
-- that no longer exists; LOVE raises OpenAL's refusal as a Lua error thrown
-- out of Music.update, and that is the crash.  Android delivers the same app
-- events -- and there GL context loss is the normal case rather than the
-- exception -- so it gets the same handling even though nobody has reported it
-- there yet.
--
-- MOBILE ONLY, deliberately.  On desktop, alt-tab has always kept the music
-- playing and there is no session to lose; Platform.detect().mobile is false
-- for Windows / macOS / Linux and for the console builds, and false under the
-- headless test stub (which has no love.system at all), so every line this
-- reaches is inert off a phone.  It is inert while focused too: both edges are
-- latched on self.audioSuspended, so the focus+visible pair that a single
-- transition delivers is acted on once.
function Game:audioSession(active, why)
  if not Platform.detect().mobile then return end
  local Music = require("src.core.Music")
  if active then
    if not self.audioSuspended then return end
    self.audioSuspended = false
    Logger.info("audio session: %s regained -- rebuilding audio", why)
    Music.resume(Data)
    -- The app was parked inside SDL's event loop for the whole call, so the
    -- first love.timer.step() after it returns the LENGTH OF THE CALL.
    -- FixedStep already clamps its accumulator (FixedStep.maxAccum, 0.25s =
    -- 15 steps), so an unbounded dt cannot spiral into thousands of catch-up
    -- ticks here -- but 15 logic steps inside one frame still plays out as a
    -- lurch, and a direction held when the call arrived walks the player most
    -- of a tile before anything is drawn.  discardCatchup is the machinery
    -- that already exists for exactly this (it absorbs one oversized frame as
    -- a single step, for map seams); a resume from an interruption is the
    -- largest hitch this engine will ever be handed.
    FixedStep:discardCatchup()
  else
    if self.audioSuspended then return end
    self.audioSuspended = true
    Logger.info("audio session: %s lost -- suspending audio", why)
    Music.suspend()
  end
end

-- A disconnected/dropped controller can't send the button-up for whatever
-- it was holding, so drop all input state rather than try to guess which
-- flags it owned.
function Game:joystickremoved(joystick)
  Input:reset()
  TouchControls:joystickremoved()
end

-- A POINTER GOES TO THE SCREEN FIRST, AND TO THE PAD ONLY IF NOBODY WANTED IT.
--
-- Every pointer event in this engine went straight to `TouchControls` and
-- nowhere else, so no game state could ever be touched -- which is fine for
-- eleven years of Game Boy screens driven by a d-pad, and is not fine for a DS
-- one. Platinum's Underground mining game is played entirely by tapping the
-- bottom screen; there is no button for it to bind.
--
-- THE FALL-THROUGH IS THE WHOLE DESIGN. A state claims a press by defining the
-- handler and returning true; anything else -- no handler, or a handler that
-- returns false because the point was outside it -- and `TouchControls` receives
-- exactly what it received before. Claimed gestures stay with their screen
-- through release, including the watch drawn on Android's lower panel.
--
-- `pcall` because a state that raises inside a touch handler would otherwise
-- take the d-pad down with it, and losing the controls is worse than losing the
-- tap.
local function offerPointer(self, method, id, x, y)
  self.pointerOwners=self.pointerOwners or {}
  local captured=self.pointerOwners[id]
  local function offer(screen)
    if not (screen and type(screen[method])=='function') then return false end
    local ok,claimed=pcall(screen[method],screen,id,x,y)
    if not ok then
      require('src.core.Logger').warn('%s raised in a touch handler: %s',
        tostring(screen.name or 'a screen'),tostring(claimed))
      return false
    end
    if claimed==true and method=='touchpressed' then self.pointerOwners[id]=screen end
    return claimed==true
  end
  if captured then
    offer(captured)
    if method=='touchreleased' then self.pointerOwners[id]=nil end
    return true
  end
  local top = self.stack and self.stack.top and self.stack:top()
  if offer(top) then return true end
  -- The always-present Android lower-panel watch is drawn outside the stack.
  -- Its coordinate mapper rejects main-window input in display mode.
  local panel=self.secondScreenPointerOwner
  return panel~=top and offer(panel) or false
end

function Game:touchpressed(id, x, y)
  if offerPointer(self, "touchpressed", id, x, y) then return end
  TouchControls:touchpressed(id, x, y)
end

function Game:hasPointerScreen()
  if self.pointerOwners and self.pointerOwners.mouse then return true end
  local top=self.stack and self.stack.top and self.stack:top()
  return top and type(top.touchpressed)=='function' or false
end

function Game:touchmoved(id, x, y)
  if offerPointer(self, "touchmoved", id, x, y) then return end
  TouchControls:touchmoved(id, x, y)
end

function Game:touchreleased(id, x, y)
  if offerPointer(self, "touchreleased", id, x, y) then return end
  TouchControls:touchreleased(id, x, y)
end

-- Point the loader's mod.save backing at this save's modData so per-mod
-- state persists with the slot.  seedBuckets is boot-only: it keeps what
-- entry chunks wrote before any save existed, while NEW GAME and
-- CONTINUE replace the backing outright.
function Game:adoptSave(save, seedBuckets)
  self.pointerOwners={}
  self.secondScreenPointerOwner=nil
  self.secondScreenOverworldPoketch=nil
  save.modData = save.modData or {}
  local loader = self.mods
  if not loader then return end
  -- A mod whose id changed takes its per-playthrough state with it.  Per save
  -- rather than once at boot, because each slot carries its own modData and a
  -- player may open several -- and here, rather than in SaveData, because this
  -- is the first point that has both the save and the manifests.
  pcall(function()
    require("src.mods.ModRename").adoptModData(save.modData, loader.mods)
  end)
  if seedBuckets then
    for id, bucket in pairs(loader.modSave or {}) do
      if save.modData[id] == nil then save.modData[id] = bucket end
    end
  end
  loader.modSave = save.modData
end

-- Capture the live world state into the save table and persist it.
-- Options are flushed to options.lua as part of SaveData.save.
function Game:writeSave()
  -- Tool sessions can be deliberately ephemeral. Give them one narrow veto
  -- before captureSave mutates the snapshot or any progress bytes reach disk.
  if ModRuntime.call("save.write", function() return true end, self) == false then
    return false
  end
  if self.overworld and self.overworld.captureSave then
    self.overworld:captureSave(self.save)
  end
  -- stamp here so the save.writing payload carries the exact meta the
  -- file gets; mods snapshot runtime state into their namespace now
  self.save.meta = SaveData.buildMeta(
    self.modStatus and self.modStatus.loaded, self.save.meta)
  if ModRuntime.wants("save.writing") then
    ModRuntime.emit("save.writing", { save = self.save, meta = self.save.meta })
  end
  return SaveData.save(self.save)
end

-- Persist options.lua only (Options menu / hotkeys 2-5).  Keeps settings
-- across New Game without touching the progress save.
function Game:writeOptions()
  if not (self.save and self.save.options) then return end
  -- The generation this playthrough belongs to, so a row it overrides is
  -- written back into that override rather than over everyone else's shared
  -- value (SaveData.saveOptions / src/core/GenOptions.lua).  Nil for a game
  -- with no overrides in play, which is the pre-existing behaviour.
  local gen = SaveData.generationOf and SaveData.generationOf(nil) or nil
  SaveData.saveOptions(self.save.options, nil, gen)
end

-- Push the live options table into audio + display subsystems.
function Game:applyOptions(opts)
  opts = opts or (self.save and self.save.options) or {}
  local Music = require("src.core.Music")
  local Sound = require("src.core.Sound")
  if Music.applyOptions then Music.applyOptions(opts) end
  if Sound.applyOptions then Sound.applyOptions(opts) end
  -- EMERALD'S BUTTON MODE, which decides what L and R do.  Applied here
  -- rather than read at the input site so that a mode set on the OPTION
  -- screen takes effect the moment it is chosen, like every other row.
  if self.input and self.input.setButtonMode then
    self.input:setButtonMode(opts.gen3ButtonMode or 1)
  end
  require("src.render.PaletteFX").applyOptions(opts)
  require("src.render.Tilt").applyOptions(opts)
  -- after Tilt, so a persisted world pipeline can switch the tilt level it
  -- just restored back off (the two are mutually exclusive)
  require("src.render.Pipelines").applyOptions(opts)
  require("src.render.Zoom").applyOptions(opts)
  require("src.render.TileRenderer").applyOptions(opts)
  -- returns true when a persisted GBC FX level was cleared on mobile
  local gbcCleared = require("src.render.GBCFX").applyOptions(opts)
  require("src.core.VideoMode").applyOptions(opts)
  -- after VideoMode: a faithful-resolution lock is an exact window size, so
  -- it has to be the last word on the window (it drops fullscreen to hold)
  require("src.core.FaithfulRes").applyOptions(opts)
  -- normalizes a nil/garbage cap to the 60 default, so old saves with no
  -- fpsCap key pace at the standard rate (issue #88)
  require("src.core.FrameCap").applyOptions(opts)
  -- Scale the optional presentation extras to the device's performance
  -- tier.  Every heavy feature was just applied from the stored options
  -- above; here we clamp the *live* state down for a weaker device without
  -- rewriting what the player saved, so raising the tier later restores
  -- their exact TILT / GBC FX / ZOOM / MAX FPS choices.  A HIGH tier (the
  -- default on a normal desktop, and every options.lua predating this
  -- option) clamps nothing, so it is a no-op for the common case.
  local caps = require("src.core.Performance").applyOptions(opts)
  if not caps.tilt then require("src.render.Tilt").setLevel(0) end
  if not caps.gbcfx then require("src.render.GBCFX").setLevel(0) end
  local Zoom = require("src.render.Zoom")
  Zoom.allowSurvey = caps.survey
  if not caps.survey and Zoom.offset < 0 then Zoom.offset = 0 end
  if caps.fpsMax then
    local FrameCap = require("src.core.FrameCap")
    if FrameCap.current > caps.fpsMax then FrameCap.apply(caps.fpsMax) end
  end
  Input:applyBindings(opts.bindings)
  TouchControls:applyOptions(opts)
  -- heal soft-bricked APK installs that already saved gbcfx > 0 (#136)
  if gbcCleared then self:writeOptions() end
end

function Game:restoreSave(loaded, recovered)
  if ModRuntime.wants("save.loading") then
    ModRuntime.emit("save.loading", { raw = loaded })
  end
  -- mod chains replay before validation so a mod repairs its own data
  -- instead of watching it get quarantined; core steps already ran in
  -- SaveData.load and skip on the format guard
  local activeMods = self.modStatus and self.modStatus.loaded
  SaveData.runMigrations(loaded, self.mods and self.mods.migrations, activeMods)
  -- PR #60 taught future FireRed League wins to keep the cartridge-native
  -- FLAG_DEFEATED_* bits and the older port EVENT_BEAT_* names in sync.  Saves
  -- already partway through the Elite Four predate that bridge and may have
  -- only one side, leaving the next room sealed after an update.  Reconcile
  -- those run-scoped flags before the room's ON_LOAD script evaluates them.
  if require("src.core.GameVersion").get() == "firered" then
    local okG3, G3 = pcall(require, "src.script.Gen3Commands")
    if okG3 and G3 and G3.repairFireRedLeagueFlags
       and G3.repairFireRedLeagueFlags(loaded) then
      Logger.info("FireRed save repair: synchronized in-progress Elite Four flags")
    end
  end
  -- Pre-fix FireRed port saves could already own a TM/HM without ITEM_TM_CASE.
  -- Repair that impossible-on-cartridge state before validation/UI adoption.
  local okBag, Bag = pcall(require, "src.inventory.Bag")
  if okBag and Bag and Bag.repairFireRedTMCase
     and Bag.repairFireRedTMCase(loaded, self.data) then
    Logger.info("FireRed save repair: restored missing TM CASE for existing machines")
  end
  -- ...AND SINNOH'S OPENING FLAGS, for a save written while they were not
  -- reaching the engine.  Only the ones this save has never recorded a value
  -- for are restored, so a story already advanced past is left alone; see
  -- SaveData.repairOpeningFlags for why that test is the whole of it.
  SaveData.repairOpeningFlags(loaded, self:bootConfig())
  -- Issue #103: 0.1.11 softlocks left CONTINUE in HALL_OF_FAME with
  -- lastOutdoor on Indigo.  One-shot relocate + heal before validate.
  if SaveData.needsPostGameRescue(loaded) then
    SaveData.applyPostGameHome(loaded, self:bootConfig())
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(loaded.party or {}) do Pokemon.heal(mon) end
  end
  -- Emerald's CHAMPION_SAVEWARP (special 343): the Hall of Fame saved with
  -- the player standing in a room that has no exit, and this is the load
  -- that spends the bit and puts them back in their own bedroom.
  if SaveData.hasChampionSaveWarp(loaded) then
    local home = SaveData.applyChampionSaveWarp(loaded, self:bootConfig())
    Logger.info("champion save warp: resuming at %s",
                home and tostring(loaded.player and loaded.player.map)
                     or "the saved spot (this dataset has no start map)")
  end
  local modsDiff = SaveData.modsDiff(loaded, activeMods)
  local report = SaveData.validate(loaded, self.data)
  report.recovered = recovered
  report.modsDiff = modsDiff
  self.save = loaded
  self:adoptSave(loaded)
  -- SaveData.load already attached the standalone options.lua table
  self:applyOptions(loaded.options)
  -- saves from before OT/ID stamping: backfill with the player's (after
  -- the scrub, so every mon the stamp loop sees is known)
  local stamp = require("src.battle.BattleState").stampOT
  for _, mon in ipairs(loaded.party or {}) do stamp(loaded, mon) end
  for _, box in ipairs(loaded.boxes or {}) do
    for _, mon in ipairs(box) do stamp(loaded, mon) end
  end
  -- rebuild the state stack from the save
  while self.stack:top() do self.stack:pop() end
  self.stack:push(self.overworld, loaded.player.map,
                  loaded.player.x, loaded.player.y, loaded.player.facing)
  self.saveReport = report
  if not SaveData.emptyReport(report) then
    -- the report screen is a Screens id so mods (or the ui milestone) own
    -- its looks; until one exists the log keeps a quarantine from being
    -- silent
    local ok = pcall(Screens.push, self, "QuarantineReport", report)
    if not ok then
      Logger.warn("load report: %d mons quarantined, %d items removed, %d maps remapped%s",
        #report.lostMons, #report.lostItems, #report.remappedMaps,
        recovered and (", recovered from " .. recovered) or "")
      local notice = SaveData.modsDiffNotice(modsDiff, loaded.meta)
      if notice then Logger.warn("%s", notice) end
    end
  end
  if ModRuntime.wants("save.loaded") then
    ModRuntime.emit("save.loaded",
      { save = loaded, meta = loaded.meta, modsDiff = modsDiff })
  end
end

return Game
