-- HORDE MODE: the code, the dark, and the way back.
--
-- Up Up Down Down Left Right Left Right B A, standing in the overworld,
-- and Kanto turns on you: the sky goes to a starless violet night, the
-- Lavender Town theme comes up, the camera locks into the player's own
-- head, a handgun appears in their right hand, and waves of people walk
-- out of the dark to kill them. Score goes up per kill; when the health
-- runs out a GAME OVER screen offers a score and PRESS A, and pressing it
-- puts everything back exactly as it was.
--
-- WHAT THIS FILE OWNS: the code detector, the state machine, the snapshot
-- and its restore, and every hook that holds the world still while the
-- mode runs. The gun is lib/HordeGun, the crowd is lib/HordeMobs, the
-- readout is lib/HordeHud, the sounds are lib/HordeSfx and the ending is
-- lib/HordeGameOver.
--
-- IT IS NOT A STACK STATE, and that is the load-bearing decision. Pushing
-- a state over the overworld stops StateStack ticking the overworld,
-- which stops OverworldState:handleInput, which stops FreeMove -- the
-- player would be unable to walk. So horde mode is a MODE FLAG driven
-- from the voxel pipeline's update hook, exactly as lib/OverworldBattle
-- rides it: the one tick that keeps running through menus, transitions
-- and battles. The GAME OVER screen IS a pushed state, because by then
-- the walking is over and freezing the world under it is the point.
--
-- THE CODE IS READ OFF GAME BOY BUTTONS, not off keys. Every input device
-- the engine has -- keyboard, gamepad, raw joystick, the touch overlay,
-- and the VR controllers (lib/VR.driveControls feeds Input:overlayPressed
-- and the stick path) -- lands in src/core/Input as one of eight buttons.
-- One detector on that abstraction is therefore a detector on ALL of
-- them, which is why the code works on a headset with no keyboard in the
-- room. It reads Input.pressQueue from the `input.step` hook, the fixed
-- step's own boundary, so it sees every edge exactly once whatever the
-- frame rate did.
--
-- THE DARK is not a new renderer. DayNight is pinned to NIGHT and then
-- its two public colour functions are WRAPPED and multiplied down toward
-- violet -- so the sky bands, the world tint, the flat 2D world (DayTint
-- paints the same multiply), the water's reflection and the shadow rig
-- all darken together, because every one of them already reads those two
-- functions. Wrapped rather than edited in place because both memoise
-- into file-local caches this module cannot reach.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local DayNight = V.require("DayNight")
local FirstPerson = V.require("FirstPerson")
local HordeSfx = V.require("HordeSfx")

local Horde = {}

-- lib modules that require THIS one back (the mobs read the session, the
-- gun reports kills). Loaded on first use rather than at the top, so the
-- require cycle never closes.
local Mobs, Gun, Hud
local function parts()
  Mobs = Mobs or V.require("HordeMobs")
  Gun = Gun or V.require("HordeGun")
  Hud = Hud or V.require("HordeHud")
  return Mobs, Gun, Hud
end

-- ------- tuning
--
-- Every number the mode is balanced on, in one place.

Horde.MAX_HP = 100
Horde.CONTACT_DAMAGE = 9        -- one mob's touch
Horde.INTRO_TIME = 3.6          -- the beat before the first wave
Horde.DYING_TIME = 1.1          -- from the last hit to the GAME OVER card
Horde.SONG = "Music_Lavender"

-- how far down NIGHT is dragged. The sky's bands and the world tint are
-- multiplied by these; the third is how much of the colour is pulled out
-- on the way (1 keeps it, 0 is greyscale) -- a little desaturation is
-- what turns "dark" into "grim".
Horde.GLOOM_SKY = { 0.34, 0.30, 0.46 }
Horde.GLOOM_WORLD = { 0.42, 0.38, 0.56 }
Horde.GLOOM_INDOOR = { 0.55, 0.50, 0.68 }
Horde.GLOOM_SAT = 0.72
Horde.SHADOW_BOOST = 1.45       -- the moon presses harder than it should

-- ------- state

Horde.active = false            -- every hook in this file gates on it
Horde.state = "idle"            -- idle | intro | active | dying | gameover
Horde.session = nil

-- Whether the combat is live: mobs move, the gun fires, damage lands.
-- False during the intro beat, the death fade, the GAME OVER card -- and
-- while ANYTHING is on the stack above the overworld, which is what
-- stops the trigger from firing into a world the player has stopped
-- looking at while the exit prompt asks them a question.
function Horde.playing()
  if not (Horde.active and Horde.state == "active") then return false end
  local ok, live = pcall(function()
    local G = require("src.core.Game")
    local ow = G.overworld
    return G.stack and ow and G.stack:top() == ow and not ow.transitioning
  end)
  return ok and live == true
end

-- Whether the mode owns the camera rung right now, which is the whole of
-- what "locked to first person" means: main.lua's cycleVoxel refuses
-- while this is true, and that one function is what the 3 key, the pad's
-- SELECT and the VR stick click all call.
function Horde.viewLocked()
  return Horde.active
end

-- Whether the free walk should skip its A (talk) and START (menu)
-- branches. Nobody stops to read a sign mid-firefight, and START has a
-- different job here (see askExit).
function Horde.suppressWorldInput()
  return Horde.active
end

local function game()
  local ok, G = pcall(require, "src.core.Game")
  return ok and G or nil
end

local function overworld(G)
  G = G or game()
  return G and G.overworld or nil
end

-- The way out, on demand. START -- the pad's, the keyboard's ESCAPE, the
-- touch overlay's -- and the VR left stick click all ask this, and it
-- asks the player. Nothing here ends the mode; the prompt does that
-- through Horde.finish if the answer is yes.
--
-- Refused while anything is already on top of the overworld, so the
-- question cannot stack on itself or arrive over the GAME OVER card.
--
-- BELOW the two helpers above, deliberately: a Lua local is only in
-- scope after its declaration, so a function written above them captures
-- the GLOBAL of that name instead -- which is nil, and only says so when
-- somebody presses the button.
function Horde.askExit(G)
  G = G or game()
  if not (Horde.active and Horde.state ~= "gameover") then return false end
  local ow = overworld(G)
  if not (G and G.stack and ow and G.stack:top() == ow) then return false end
  if ow.transitioning then return false end
  local pushed = false
  pcall(function()
    require("src.ui.Screens").push(G, "HordeExitPrompt")
    pushed = true
  end)
  return pushed
end

-- ------- the code
--
-- Advance on the expected button; on a wrong one, fall back to the
-- longest run already entered that is still a valid start of the code,
-- and try again from there. That fallback is why this is a table rather
-- than a counter: the code STARTS with a repeat, so a player who presses
-- Up three times has, on the third, still entered "Up Up" -- and a naive
-- "wrong button, back to the beginning" rule would throw one of them
-- away and refuse a code that was in fact typed correctly. (It is the
-- prefix function from Knuth-Morris-Pratt, over ten buttons.)
--
-- The timeout is in fixed steps, 60 to the second: a code is a deliberate
-- act, and a stray Up a minute ago should not be half of one.

local SEQUENCE = { "up", "up", "down", "down",
                   "left", "right", "left", "right", "b", "a" }
local IDLE_STEPS = 150          -- two and a half seconds between buttons

-- FALLBACK[n] = how much of the code is still entered after n matched
-- buttons and then a wrong one
local FALLBACK = { [0] = 0, [1] = 0 }
do
  local k = 0
  for i = 2, #SEQUENCE do
    while k > 0 and SEQUENCE[k + 1] ~= SEQUENCE[i] do k = FALLBACK[k] end
    if SEQUENCE[k + 1] == SEQUENCE[i] then k = k + 1 end
    FALLBACK[i] = k
  end
end

local progress = 0
local sinceLast = 0

-- Named for the suite: how far into the code the detector has got.
function Horde._progress()
  return progress
end

local function resetCode()
  progress, sinceLast = 0, 0
end

-- Can the mode start from where the player is standing? The overworld has
-- to be the live state (not a menu, not a battle, not a transition wipe),
-- the 3D pass has to exist to put a camera inside, and the world has to be
-- free-roaming rather than mid-cutscene.
--
-- MID-STEP IS ALLOWED, and that is not an oversight. Six of the code's ten
-- buttons are directions, so entering it on a d-pad walks the player four
-- cells across the map -- and at the moment the closing A lands they are
-- very often still animating the last of those steps. Refusing a code for
-- being mid-step would refuse most of the codes anyone actually enters.
-- The snapshot records the cell the step began from, which is where the
-- restore puts them back.
function Horde.canStart(G)
  G = G or game()
  if not G or Horde.active then return false end
  local ow = overworld(G)
  if not (ow and ow.map and ow.player) then return false end
  if not (G.stack and G.stack:top() == ow) then return false end
  if ow.transitioning or ow.scripted or ow.engaging then return false end
  if ow.player.inputLocked then return false end
  if not Voxel3D.available() then return false end
  return true
end

-- One fixed step of the detector, over the edges about to be promoted.
-- Separated from the hook so the suite can drive it with a plain list.
function Horde.feed(queue)
  if Horde.active then
    resetCode()
    return false
  end
  sinceLast = sinceLast + 1
  if progress > 0 and sinceLast > IDLE_STEPS then resetCode() end
  local fired = false
  for _, btn in ipairs(queue or {}) do
    sinceLast = 0
    while progress > 0 and SEQUENCE[progress + 1] ~= btn do
      progress = FALLBACK[progress]
    end
    if SEQUENCE[progress + 1] == btn then
      progress = progress + 1
      if progress >= #SEQUENCE then
        resetCode()
        fired = true
      end
    end
  end
  return fired
end

-- ------- the snapshot
--
-- Everything the mode changes, read back before it changes any of it.
-- Presentational settings included: the rung, the two engine FX levels the
-- rung clearing would zero, and the clock -- a player who was watching a
-- CYCLE sunset gets their sunset back.

local function snapshot(G)
  local ow = overworld(G)
  local p = ow.player
  local Pipelines = require("src.render.Pipelines")
  local opts = G.save and G.save.options or {}
  local snap = {
    mapId = ow.map.id,
    cellX = p.cellX, cellY = p.cellY,
    px = p.px, py = p.py,
    facing = p.facing,
    viewLevel = Pipelines.level("voxel"),
    tilt = opts.tilt or 0,
    gbcfx = opts.gbcfx or 0,
    fpYaw = FirstPerson.yaw,
    fpPitch = FirstPerson.pitch,
    dayIndex = DayNight.setting:read(),
    dayClock = DayNight.clock,
  }
  return snap
end

-- ------- the gloom
--
-- Installed once and inert while the mode is off: each wrapper calls
-- through and returns the base answer untouched unless Horde.active.

local gloomInstalled = false

local function desaturate(r, g, b, keep)
  local lum = 0.30 * r + 0.59 * g + 0.11 * b
  return lum + (r - lum) * keep,
         lum + (g - lum) * keep,
         lum + (b - lum) * keep
end

local function installGloom()
  if gloomInstalled then return end
  gloomInstalled = true

  -- The sky's bands. Sky.bands caches BY COLOUR VALUE, so darkening what
  -- this returns rebuilds the band ramp on its own -- and puts it back the
  -- same way when the mode ends.
  do
    local base = DayNight.palette
    local cacheIn, cacheOut = nil, nil
    DayNight.palette = function(t)
      local pal = base(t)
      if not Horde.active then return pal end
      if cacheIn == pal then return cacheOut end
      local k = Horde.GLOOM_SKY
      local out = {}
      for i, c in ipairs(pal) do
        local r, g, b = c[1] * k[1], c[2] * k[2], c[3] * k[3]
        r, g, b = desaturate(r, g, b, Horde.GLOOM_SAT)
        out[i] = { math.floor(r), math.floor(g), math.floor(b) }
      end
      cacheIn, cacheOut = pal, out
      return out
    end
  end

  -- The world multiply -- the voxel shader's tint uniform AND, through
  -- DayTint, the flat 2D world. Indoors normally returns neutral white;
  -- under the horde it does not, because a Pokemon Centre with the horde
  -- in it should not look like a Pokemon Centre.
  do
    local base = DayNight.tint
    local cacheIn, cacheOut, cacheOutdoor = nil, nil, nil
    DayNight.tint = function(outdoor, t)
      local c = base(outdoor, t)
      if not Horde.active then return c end
      if cacheIn == c and cacheOutdoor == outdoor then return cacheOut end
      local k = outdoor and Horde.GLOOM_WORLD or Horde.GLOOM_INDOOR
      local r, g, b = c[1] * k[1], c[2] * k[2], c[3] * k[3]
      r, g, b = desaturate(r, g, b, Horde.GLOOM_SAT)
      cacheIn, cacheOutdoor, cacheOut = c, outdoor, { r, g, b }
      return cacheOut
    end
  end

  -- and the shadows press harder: applyRig writes SHADOW_ALPHA from the
  -- hour, so the boost goes on after it has had its say
  do
    local base = DayNight.applyRig
    DayNight.applyRig = function(outdoor)
      local t = base(outdoor)
      if Horde.active then
        Voxel3D.SHADOW_ALPHA = math.min(0.75,
          (Voxel3D.SHADOW_ALPHA or 0) * Horde.SHADOW_BOOST)
      end
      return t
    end
  end
end

-- ------- starting

-- The banner over the world: text, and how long it holds before fading.
function Horde.banner(text, hold)
  local s = Horde.session
  if not s then return end
  s.bannerText = text
  s.bannerT = 0
  s.bannerHold = hold or 2.2
end

function Horde.begin(G)
  G = G or game()
  if not Horde.canStart(G) then return false end
  local Pipelines = require("src.render.Pipelines")
  local mobs, gun = parts()

  local snap = snapshot(G)
  Horde.session = {
    hp = Horde.MAX_HP, maxHp = Horde.MAX_HP,
    score = 0, wave = 0, kills = 0,
    t = 0, introT = Horde.INTRO_TIME, dyingT = 0,
    damageFlash = 0, hitMarker = 0, hurtCooldown = 0,
    bannerText = nil, bannerT = 0, bannerHold = 0,
    snapshot = snap,
    spawned = {},          -- mapId -> { [objIndex] = true }, for the scrub
    mobs = {},
    waveRemaining = 0, waveGap = 0, spawnGap = 0, followQueue = 0,
    startedAt = os and os.time and os.time() or 0,
  }
  Horde.active = true
  Horde.state = "intro"

  -- the rung, forced and then held: FP_LEVEL is the one rung with a camera
  -- inside the world, and cycleVoxel refuses to leave it while active
  Pipelines.setLevel("voxel", Voxel.FP_LEVEL)
  Pipelines.syncOptions(G.save.options)
  G.save.options.tilt, G.save.options.gbcfx = 0, 0
  pcall(function() require("src.render.Tilt").setLevel(0) end)
  pcall(function() require("src.render.GBCFX").setLevel(0) end)
  pcall(G.writeOptions, G)

  -- night, pinned; the gloom wrappers do the rest on top of it
  local nightIndex = 3          -- DayNight.setting values: sync/day/NIGHT/...
  for i, v in ipairs(DayNight.setting.values) do
    if v == "night" then nightIndex = i end
  end
  DayNight.setting:setIndex(nightIndex, G)

  pcall(function()
    require("src.core.Music").play(G.data, Horde.SONG, true,
                                   { reason = "horde" })
  end)

  gun.reset()
  mobs.begin(G)
  Horde.banner("A DARKNESS APPROACHES", 2.6)
  return true
end

-- ------- damage and score

function Horde.addScore(n)
  local s = Horde.session
  if not s then return end
  s.score = s.score + (n or 0)
end

-- A mob reached the player. Returns true when the hit landed (it is on a
-- cooldown, so a crowd of six does not delete the player in one frame).
function Horde.damage(n)
  local s = Horde.session
  if not (s and Horde.playing()) then return false end
  if s.hurtCooldown > 0 then return false end
  s.hurtCooldown = 0.55
  s.hp = math.max(0, s.hp - (n or Horde.CONTACT_DAMAGE))
  s.damageFlash = 1
  HordeSfx.play(HordeSfx.HURT)
  if s.hp <= 0 then
    Horde.state = "dying"
    s.dyingT = Horde.DYING_TIME
    pcall(function() require("src.core.Sound").stopLoop("Low_Health_Alarm") end)
  end
  return true
end

-- ------- the ending

local function pushGameOver(G)
  Horde.state = "gameover"
  local s = Horde.session
  local best = 0
  pcall(function() best = V.mod.save:get("hordeBest", 0) or 0 end)
  if s.score > best then
    best = s.score
    pcall(function() V.mod.save:set("hordeBest", best) end)
  end
  s.best = best
  pcall(function() require("src.core.Music").stop() end)
  pcall(function()
    require("src.ui.Screens").push(G, "HordeGameOver")
  end)
end

-- Put everything back. Called from the GAME OVER card's A press.
--
-- Order matters: active goes false FIRST, so the music hook, the gloom
-- wrappers and the mob spawner have all stood down before anything is
-- restored under them. The warp home is taken even when the player never
-- left the map they started on -- setMap rebuilds the cast from the map
-- record, which is what puts every NPC the horde ate back on its feet.
function Horde.finish(G)
  G = G or game()
  local s = Horde.session
  if not s then return false end
  local mobs = parts()
  local snap = s.snapshot or {}

  Horde.active = false
  Horde.state = "idle"
  resetCode()

  mobs.cleanup(G)
  pcall(function() require("src.core.Sound").stopLoop("Low_Health_Alarm") end)

  -- the clock, back to the hour and the setting the player kept
  if snap.dayIndex then DayNight.setting:setIndex(snap.dayIndex, G) end
  if snap.dayClock then DayNight.clock = snap.dayClock end

  -- the rung and the two FX levels the rung clearing zeroed
  pcall(function()
    local Pipelines = require("src.render.Pipelines")
    Pipelines.setLevel("voxel", snap.viewLevel or 0)
    Pipelines.syncOptions(G.save.options)
    G.save.options.tilt = snap.tilt or 0
    G.save.options.gbcfx = snap.gbcfx or 0
    require("src.render.Tilt").setLevel(snap.tilt or 0)
    require("src.render.GBCFX").setLevel(snap.gbcfx or 0)
    G:writeOptions()
  end)

  if snap.fpYaw then FirstPerson.yaw = snap.fpYaw end
  if snap.fpPitch then FirstPerson.pitch = snap.fpPitch end

  Horde.session = nil

  -- home, through the engine's own warp: a fade, a setMap, and the map's
  -- own music coming back up on the other side (the hook that was forcing
  -- Lavender is inert now)
  local ow = overworld(G)
  if ow and snap.mapId then
    pcall(function()
      ow:startWarpTo(snap.mapId, snap.cellX, snap.cellY, snap.facing or "down",
                     function()
                       -- the pixel position and the facing, restated on
                       -- the far side of the fade. setMap already placed
                       -- both, but the free walk owns them while the rung
                       -- is still easing out of the head, and the head was
                       -- looking wherever the last shot was aimed
                       local p = overworld(G) and overworld(G).player
                       if not p then return end
                       if snap.px then p.px, p.py = snap.px, snap.py end
                       if snap.facing then p.facing = snap.facing end
                     end,
                     { via = "warp" })
    end)
  end
  return true
end

-- ------- the tick
--
-- Rides the voxel pipeline's update hook, which Game:update calls every
-- frame whatever the level and whatever is on the stack -- so the mode
-- keeps thinking through a warp's transition wipe and under the GAME OVER
-- card, which is exactly what a mode that owns the whole screen needs.

function Horde.update(dt)
  if not Horde.active then return end
  local s = Horde.session
  if not s then
    Horde.active = false
    return
  end
  dt = math.min(dt or 0, 0.1)         -- a hitch must not teleport the wave
  local G = game()
  local mobs, gun, hud = parts()

  s.t = s.t + dt
  s.damageFlash = math.max(0, s.damageFlash - dt * 2.2)
  s.hitMarker = math.max(0, s.hitMarker - dt * 4)
  s.hurtCooldown = math.max(0, s.hurtCooldown - dt)
  if s.bannerText then
    s.bannerT = s.bannerT + dt
    if s.bannerT > s.bannerHold + 1.1 then s.bannerText = nil end
  end
  hud.update(dt)

  if Horde.state == "intro" then
    s.introT = s.introT - dt
    if s.introT <= 0 then
      Horde.state = "active"
      mobs.nextWave(G)
    end
    return
  end

  if Horde.state == "dying" then
    s.dyingT = s.dyingT - dt
    mobs.update(dt, G)             -- the crowd keeps coming while you fall
    if s.dyingT <= 0 then pushGameOver(G) end
    return
  end

  if Horde.state ~= "active" then return end

  -- the world only ticks while the overworld is actually the live state:
  -- during a warp's wipe there is no map under the mobs to walk on
  local ow = overworld(G)
  local live = G and G.stack and ow and G.stack:top() == ow
                 and not ow.transitioning
  gun.update(dt, live)
  if live then mobs.update(dt, G) end

  -- the siren the game already owns, for the last third of the health bar
  local low = s.hp <= s.maxHp * 0.3
  if low ~= s.alarmOn then
    s.alarmOn = low
    pcall(function()
      local Sound = require("src.core.Sound")
      if low then Sound.startLoop(G.data, "Low_Health_Alarm")
      else Sound.stopLoop("Low_Health_Alarm") end
    end)
  end
end

-- ------- the seams
--
-- Every engine and mod hook the mode needs, installed once. main.lua
-- calls this AFTER FreeMove.install and the SELECT wrap, so the
-- handleInput wrap this adds sits outside both of theirs.

local installed = false

function Horde.install()
  if installed then return end
  installed = true
  local mod = V.mod

  installGloom()

  -- THE CODE. `input.step` runs once per fixed step, immediately before
  -- Input:step promotes the queue into this step's edges -- so pressQueue
  -- is exactly "the buttons that were pressed since last time", in order,
  -- from every device at once. Read, never consumed: the game still gets
  -- every one of them.
  mod.hooks:wrap("input.step", function(next, G, dt)
    local inp = G and G.input
    if inp and inp.pressQueue and Horde.feed(inp.pressQueue) then
      pcall(Horde.begin, G)
    elseif Horde.playing() and inp and inp.pressQueue then
      -- B is a trigger while the horde is up (the pad's B, the keyboard's,
      -- the touch overlay's). Read here rather than in the frame tick
      -- because THIS is the boundary that sees each press exactly once.
      for _, btn in ipairs(inp.pressQueue) do
        if btn == "b" then
          local _, gun = parts()
          gun.fire()
        end
      end
    end
    return next(G, dt)
  end)

  -- Lavender, and it stays Lavender. Every song choice in the engine goes
  -- through this hook, so a door into a building cannot change the record.
  mod.hooks:wrap("music.select", function(next, chosen, ctx)
    if Horde.active and Horde.state ~= "gameover" then
      return next(Horde.SONG, ctx)
    end
    return next(chosen, ctx)
  end)

  -- no wild encounters: returning nil from this hook suppresses the roll
  -- outright, which is the documented way to do it
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if Horde.active then return nil end
    return next(encDef, ctx)
  end)

  -- and no trainer walking up to talk. Wrapped rather than set through
  -- self.engaging, which would also freeze the player's own input.
  do
    local OverworldState = require("src.world.OverworldController")
    if not OverworldState.dramaticShapeHordeSight then
      local inner = OverworldState.checkTrainerSight
      function OverworldState:checkTrainerSight(...)
        if Horde.active then return end
        return inner(self, ...)
      end
      OverworldState.dramaticShapeHordeSight = true
    end
  end

  -- THE BUTTONS THE WORLD MAY NOT HAVE. A, START, SELECT and B are the
  -- mode's, and this wrap is where they are taken -- the OUTERMOST wrap on
  -- handleInput, installed after FreeMove's and after the SELECT hook, so
  -- the edges are gone before either of them looks.
  --
  -- It has to be here rather than inside the free walk, because the free
  -- walk is not always the one reading: the rung is forced to 1ST at the
  -- moment the code completes, but the camera takes a few frames to blend
  -- into the head, and until it does the GRID walk still owns the frame.
  -- That is not a corner case -- it is the very first frame of every run,
  -- and the code's own closing A was landing in it and opening a dialogue
  -- with whoever the player happened to be standing next to.
  --
  -- The EDGE is cleared, not the hold: pressed[] is rebuilt from scratch
  -- every fixed step, so this reaches exactly this step's presses and
  -- nothing downstream of it can revive one.
  do
    local OverworldState = require("src.world.OverworldController")
    if not OverworldState.dramaticShapeHordeInput then
      local inner = OverworldState.handleInput
      function OverworldState:handleInput(...)
        if Horde.active then
          local G = game()
          local inp = G and G.input
          if inp and inp.pressed then
            -- START is the way out, and it is asked rather than taken:
            -- read here, BEFORE the edge is cleared, so the engine's own
            -- START menu never sees it
            if inp.pressed.start then Horde.askExit(G) end
            inp.pressed.a = nil        -- no talking
            inp.pressed.b = nil        -- the trigger, already read
            inp.pressed.start = nil    -- and no start menu
            inp.pressed.select = nil   -- no changing the view
          end
        end
        return inner(self, ...)
      end
      OverworldState.dramaticShapeHordeInput = true
    end
  end

  -- the crowd follows the player through the door: a warp lands a new map
  -- with none of the old one's actors on it, so the roster is re-seeded on
  -- the far side (lib/HordeMobs)
  mod.events:on("map.entered", function(payload)
    if not Horde.active then return end
    local mobs = parts()
    pcall(mobs.onMapEntered, payload)
  end)
end

return Horde
