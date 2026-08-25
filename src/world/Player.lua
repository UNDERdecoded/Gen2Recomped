-- The player: tile-grid movement with pixel interpolation, faithful to the
-- original's feel: facing changes on a short tap, movement is tile-by-tile
-- at 1px per frame (16 frames per step), input locked while stepping.

local Collision = require("src.world.Collision")
local FieldDefaults = require("src.world.FieldDefaults")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Player = {}
Player.__index = Player

local STEP_FRAMES = 16
-- a turn in place blocks movement for the one extra OverworldLoop pass the
-- original spends after a direction change: .handleDirectionButtonPress ends
-- `jp OverworldLoop` (home/overworld.asm), and OverworldLoop burns two
-- DelayFrame calls before the next JoypadOverworld, so the step can only
-- commit at the following poll -- the same 2-frames-per-iteration cadence
-- that makes STEP_FRAMES 16 above (wWalkCounter = 8, 2px per
-- AdvancePlayerSprite).
-- Those polls sit on a 2-frame grid, so the hardware samples a press 0 or 1
-- frames after the d-pad physically goes down and the release deadline lands
-- 2 or 3 frames after that.  We sample on the frame the button goes down
-- with none of that poll latency, so a flat 2 handed every tap the tightest
-- case the original could produce; 4 covers the grid instead of
-- undercutting it (#415).
local TURN_FRAMES = 4
-- The on-screen d-pad cannot produce a 60ms tap: a finger press and release
-- run well past it even before the OS batches the touch events, so the
-- overlay gets a longer window than a physical pad (#415).
local TOUCH_TURN_FRAMES = 8

local FALLBACK_SPRITE = {
  id = "SPRITE_FALLBACK",
  source = "runtime fallback",
  image = "assets/generated/sprites/placeholder.png",
  frames = 6,
  walker = true,
}

local function pickSpriteDef(data, preferred)
  local sprites = (data and data.sprites) or {}
  if type(preferred) == "string" and sprites[preferred] then
    return sprites[preferred]
  end
  local priority = { "SPRITE_RED", "SPRITE_SEEL", "SPRITE_RED_BIKE", "SPRITE_BIRD" }
  for _, id in ipairs(priority) do
    if sprites[id] then return sprites[id] end
  end
  for _, def in pairs(sprites) do
    if type(def) == "table" then return def end
  end
  sprites.SPRITE_FALLBACK = sprites.SPRITE_FALLBACK or FALLBACK_SPRITE
  return sprites.SPRITE_FALLBACK
end

function Player.new(data, cx, cy, facing)
  local self = setmetatable({}, Player)
  self.stepFrames = FieldDefaults.world(data, "stepFrames") or STEP_FRAMES
  self.bikeStepFrames = FieldDefaults.world(data, "bikeStepFrames")
  -- HOLD-B RUNNING is a per-version feature, not Prism's alone: Polished
  -- Crystal has running shoes too (its DoPlayerMovement takes the .run
  -- branch on B like Prism's).  The gate is the version record's
  -- `hasRunning` flag rather than a hardcoded id, so a new build opts in by
  -- declaring it -- Gold and Crystal, which have no running at all, leave it
  -- unset and keep nil here.
  local GV = require("src.core.GameVersion")
  local info = GV.get and GV.info and GV.info(GV.get())
  self.runStepFrames = (info and info.hasRunning)
    and FieldDefaults.world(data, "runStepFrames") or nil
  self.turnFrames = FieldDefaults.world(data, "turnFrames") or TURN_FRAMES
  -- field.playerSprites: which sprite ids the player wears on foot, on the
  -- water and on the bicycle (LoadPlayerSpriteGraphics /
  -- LoadSurfingPlayerSpriteGraphics, home/overworld.asm)
  local surfId = FieldDefaults.fieldValue(data, "playerSprites", "surf")
  local surfPikaId = FieldDefaults.fieldValue(data, "playerSprites", "surfPikachu")
  self:refreshForm(data)
  self.surfSprite = SpriteRenderer.new(pickSpriteDef(data, surfId), "player")
  -- Yellow's surfing-Pikachu ride (Yellow LoadSurfingPlayerSpriteGraphics2,
  -- paired with field.playerSprites.surfPikachu). rotated in at pose()
  -- when the SURF-mon is a Pikachu.
  self.surfPikachuSprite = SpriteRenderer.new(pickSpriteDef(data, surfPikaId), "player")
  -- refreshForm above ran before surfSprite existed, so the surf sheet has not
  -- been through refreshPalette yet; do the set again now they all exist.
  self:refreshPalette(data)
  -- the ledge-hop shadow quarter-tile (gfx/overworld/shadow.png,
  -- LedgeHoppingShadow, engine/overworld/ledges.asm)
  local fx = data.field and data.field.overworldFx
  if fx and fx.shadow then
    local ok, img = pcall(love.graphics.newImage, fx.shadow.path)
    self.shadowImg = ok and img or nil
  end
  -- FishingAnim (engine/overworld/player_animations.asm) patches tiles
  -- $02/$06/$0a -- the bottom tile row of each standing frame -- with the
  -- fishing pose before it parks the rod OAM, so the rod stroke meets a pair
  -- of hands instead of ending in mid air (#384).  refreshForm above already
  -- built those strips: the pose belongs to the CHARACTER, so it is rebuilt
  -- wherever the character can change (Player:refreshFishTiles).
  self.cellX, self.cellY = cx, cy
  self.px, self.py = cx * 16, cy * 16
  self.facing = facing or "down"
  self.moving = false
  self.progress = 0
  self.stepFlip = false
  self.turnTimer = 0
  -- wCheckFor180DegreeTurn (home/overworld.asm): the original only lets a
  -- turn in place happen on a poll whose previous pass found no direction
  -- held.  It starts armed, tryMove spends it, and OverworldState:handleInput
  -- re-arms it from a standstill.
  self.turnArmed = true
  self.inputLocked = false
  return self
end

-- Pick the on-foot and bicycle sheets for the character the save says we are.
--
-- Crystal: KRIS walks and rides on her own sheets (SPRITE_KRIS /
-- SPRITE_KRIS_BIKE, OverworldSprites rows $60/$61).  field.playerForms only
-- exists there, and only the ids it actually registered are taken, so a rip
-- that failed to write one of Kris's sheets keeps Chris's rather than naming
-- a sprite that does not exist.
--
-- Separate from Player.new because the Oak speech asks the question AFTER the
-- overworld state -- and therefore this Player -- has already been built:
-- Game:makeTitleState pushes OverworldState first and the new-game screen
-- second.  OakSpeech calls this back once the answer is in.
-- Prism's "Pokemon mode": the player IS a Pokemon.
--
-- GetPlayerSprite (engine/overworld.asm) tests ENGINE_POKEMON_MODE BEFORE it
-- reaches the character table and answers SPRITE_POKEONLY_PLAYER, which
-- GetMonSprite then resolves through PokemonOWSpritePointers into that
-- species' own walking sheet.  The species is wPokeonlyMainSpecies, and when
-- that byte is clear the routine walks the party for the first member that is
-- neither an egg nor fainted and latches it there -- which is why the sections
-- that set the flag without naming a species still work.
--
-- Answers nil for every other game and whenever the sheet is missing, so the
-- caller keeps the character it already had.
local function pokemonModeSprite(data)
  local ok, Game = pcall(require, "src.core.Game")
  local save = ok and Game and Game.save or nil
  if not save then return nil end
  if not require("src.script.Flags").get(save, "ENGINE_POKEMON_MODE") then
    return nil
  end
  local species = save.g2PokeonlySpecies
  if not species then
    for _, mon in ipairs(save.party or {}) do
      if mon and not mon.isEgg and (mon.hp or 0) > 0 then
        species = mon.species
        break
      end
    end
  end
  if type(species) ~= "string" then return nil end
  -- the extractor names these sheets by the species NUMBER
  -- (gen2MonSpriteId), which is what a Gen 2 species id already carries
  local n = tonumber(species:match("^SPECIES_(%d+)$"))
  if not n then
    local order = data and data.constants and data.constants.speciesOrder
    for i, id in ipairs(order or {}) do
      if id == species then n = i break end
    end
  end
  if not n then return nil end
  local id = string.format("SPRITE_MON_%03d", n)
  return (data.sprites or {})[id] and id or nil
end

-- The fishing pose strips for whoever we are right now.
--
-- Gen2 picks the sheet off wPlayerGender (LoadFishingGFX: `bit
-- PLAYERGENDER_FEMALE_F, a / jr z, .got_gender / ld de, KrisFishingGFX`), so
-- Kris fishes on her own art.  The extractor puts those three strips on the
-- player FORM record, beside her card / back / intro pics, which is the only
-- place a per-character asset belongs -- overworldFx has one slot and cannot
-- hold two characters.
--
-- Falls back to overworldFx.redFish* so Gen1 is untouched, and so a Gen2 rip
-- that produced the shared strips but no form records still shows a pose.
-- Gold and Silver have no KrisFishingGFX at all; the extractor gives the girl
-- record Chris's strips there rather than naming files it never wrote.
function Player:refreshFishTiles(data)
  local function pathOf(v)
    if type(v) == "string" then return v end
    return type(v) == "table" and v.path or nil
  end
  local pose
  local form = require("src.pokemon.Sprites").playerForm(data)
  local fish = form and form.fish
  if fish then
    pose = { down = pathOf(fish.down), up = pathOf(fish.up),
             left = pathOf(fish.side) }
  end
  if not (pose and (pose.down or pose.up or pose.left)) then
    local fx = data.field and data.field.overworldFx
    if fx then
      pose = { down = pathOf(fx.redFishFront), up = pathOf(fx.redFishBack),
               left = pathOf(fx.redFishSide) }
    end
  end
  if pose and (pose.down or pose.up or pose.left) then
    -- the side pose mirrors like the sprite does (OAM_XFLIP)
    pose.right = pose.left
    self.fishTiles = pose
  else
    self.fishTiles = nil
  end
end

function Player:refreshForm(data)
  local walkId = FieldDefaults.fieldValue(data, "playerSprites", "walk")
  local bikeId = FieldDefaults.fieldValue(data, "playerSprites", "bike")
  local form = require("src.pokemon.Sprites").playerForm(data)
  if form then
    local sprites = data.sprites or {}
    if form.walk and sprites[form.walk] then walkId = form.walk end
    if form.bike and sprites[form.bike] then bikeId = form.bike end
  end
  -- after the character, because it REPLACES the character: in Pokemon mode
  -- there is no bicycle either, so both sheets become the mon's
  local monId = pokemonModeSprite(data)
  if monId then walkId, bikeId = monId, monId end
  -- The pose follows the character, so it is refreshed even when the walking
  -- sheets did not change (a rip that only produced Kris's fish art).
  self:refreshFishTiles(data)
  if walkId ~= self.walkId or bikeId ~= self.bikeId then
    self.walkId, self.bikeId = walkId, bikeId
    self.sprite = SpriteRenderer.new(pickSpriteDef(data, walkId), "player")
    self.bikeSprite = SpriteRenderer.new(pickSpriteDef(data, bikeId), "player")
  end
  -- ...and the COLOURS, every time, whether or not the sheets changed.
  --
  -- Prism's customiser mixes a skin tone and an outfit colour into the
  -- player's OBJ palette (PlayerCust_SetPalettes), and changing either one
  -- leaves the model -- and therefore the sheet ids -- exactly as they were.
  -- Behind the early return this used to take, re-picking a colour refreshed
  -- nothing at all: the choice was saved and the player kept walking around in
  -- the palette they started with.
  self:refreshPalette(data)
end

-- The player's mixed palette, pushed onto both sheets. A dataset that does not
-- customise clears the override instead, so this is safe to call anywhere.
function Player:refreshPalette(data)
  local ok, PlayerPalette = pcall(require, "src.render.PlayerPalette")
  if not ok then return end
  local Game = require("src.core.Game")
  local save = Game and Game.save
  pcall(PlayerPalette.apply, self.sprite, data, save)
  pcall(PlayerPalette.apply, self.bikeSprite, data, save)
  pcall(PlayerPalette.apply, self.surfSprite, data, save)
end

function Player:position()
  return self.cellX, self.cellY
end

-- How long a fresh turn holds the step off for; see TURN_FRAMES.  The
-- overlay is detected per source rather than by whether the touch controls
-- are on screen, so a phone with a controller attached still gets the
-- physical pad's window (Input:isTouchDown, src/core/Input.lua).
function Player:turnWindow()
  local frames = self.turnFrames or TURN_FRAMES
  local input = require("src.core.Game").input
  if input and input.isTouchDown and input:isTouchDown(self.facing) then
    return math.max(frames, TOUCH_TURN_FRAMES)
  end
  return frames
end

-- Attempt to start a step; returns "moved"|"turned"|"blocked"|nil.
function Player:tryMove(dir, map, entities)
  if self.moving or self.inputLocked then return nil end
  if self.facing ~= dir then
    self.facing = dir
    self.bumpFrames = nil -- turning to a new facing ends any wall-bonk cycle
    -- .handleDirectionButtonPress only reaches the turn while
    -- wCheckFor180DegreeTurn is still set, and .noDirectionButtonsPressed is
    -- the one place that sets it (home/overworld.asm), so a facing change
    -- made without the d-pad ever coming up steps straight away rather than
    -- paying the turn delay at every corner (#415)
    if self.turnArmed then
      self.turnArmed = false
      self.turnTimer = self:turnWindow()
      return "turned"
    end
  end
  if self.turnTimer > 0 then return nil end
  local ok, why = Collision.canMove(map, entities, self, dir)
  if not ok then
    -- Gen1: a blocked step still animates the player walking in place --
    -- the collision path spends the step's worth of frames running
    -- UpdateSprites before returning control, so the legs cycle without
    -- the cell changing (home/overworld.asm collision handling; issue
    -- #230).  Re-armed every frame the direction is held into the wall;
    -- Player:update ticks the walk clock while it counts down, so releasing
    -- returns to the standing pose within a step's length.
    self.bumpFrames = self.stepFrames or STEP_FRAMES
    return "blocked", why
  end
  local tx, ty = Collision.target(self.cellX, self.cellY, dir)
  self.targetX, self.targetY = tx, ty
  self.moving = true
  self.bumpFrames = nil -- a real step supersedes any in-place bonk
  self.progress = 0
  -- the bicycle doubles walking speed (8 frames per step); movement.speed
  -- lets a mod multiply or replace that (running shoes, dash, etc.)
  local Game = require("src.core.Game")
  local save = Game.save
  local frames = (save and save.onBike) and self.bikeStepFrames
                 or self.stepFrames or STEP_FRAMES
  -- "Downhill riding is slower when not moving down" (DoPlayerMovement .DoStep:
  -- on a bike with BIKEFLAGS_DOWNHILL_F set, only a DOWN step gets STEP_BIKE;
  -- every other direction drops to STEP_WALK).  Cycling Road is the only place
  -- it applies, and it is what makes climbing back up the slope feel heavy.
  if save and save.onBike and dir ~= "down" then
    local G2F = require("src.script.Gen2Flags")
    local key = G2F.bikeFlag and G2F.bikeFlag("downhill")
    if key and require("src.script.Flags").get(save, key) then
      frames = self.stepFrames or STEP_FRAMES
    end
  end
  -- RUNNING, which only Prism has -- and it has no running SHOES
  -- either.  DoPlayerMovement's .walk branch falls straight through to
  -- .run whenever B is held (engine/player_movement.asm .maybe_run),
  -- gated on nothing but ENGINE_POKEMON_MODE: there is no item to find
  -- and no flag to earn, so nothing here waits on one.  8 frames is the
  -- ROM's own figure: its step-vector table's running-shoes row is
  -- `db 0, 2, 8, 2`, two pixels a frame over eight -- the bicycle's rate
  -- on foot.  Riding wins (the branch above), surfing and Pokemon mode
  -- refuse, exactly as the original refuses them.
  local run = self.runStepFrames
  if run and not (save and save.onBike) and not self.surfing
     and Game.input and Game.input:isDown("b")
     and not require("src.script.Flags").get(save, "ENGINE_POKEMON_MODE")
  then
    frames = run
  end
  if Runtime.wantsHook("movement.speed") then
    frames = Runtime.call("movement.speed", function(f) return f end, frames, {
      onBike = save and save.onBike or false,
      surfing = self.surfing and true or false,
      player = self,
      input = Game.input,
      save = save,
    })
  end
  self.stepFramesCur = math.max(1, math.floor(tonumber(frames) or STEP_FRAMES))
  return "moved"
end

-- Advance one fixed step; returns true when a step just completed.
function Player:update()
  -- land-frame walk pose lasts only through the draw after completion;
  -- the next update (idle or a chained step) clears it
  self.stepLanded = false
  -- Ledge-hop arc is cosmetic but must track the fixed 60Hz logic step,
  -- not love.draw's display refresh (issue #4: >59fps ended early).
  if self.hopFrames and self.hopFrames > 0 then
    self.hopFrames = self.hopFrames - 1
  end
  if self.turnTimer > 0 then
    self.turnTimer = self.turnTimer - 1
  end
  if self.spinFrames then
    self.spinFrames = self.spinFrames - 1
    if self.spinFrames <= 0 then
      self.spinFrames = nil
      self.spinDrop = nil
      self.spinRise = nil -- teleport-out departure lift (#196)
      self.spinning = false
    end
  end
  -- wall-bonk walk-in-place (issue #230): while pushing into a wall the
  -- collision path keeps the walk clock running without moving the cell,
  -- so the sprite animates against the wall.  Guarded on not-moving so a
  -- real step (which clears bumpFrames and advances animClock itself
  -- below) can never double-tick the leg cadence.
  if not self.moving and self.bumpFrames and self.bumpFrames > 0 then
    self.bumpFrames = self.bumpFrames - 1
    self.animClock = (self.animClock or 0) + 1
  end
  if not self.moving then return false end
  local stepLen = self.stepFramesCur or self.stepFrames or STEP_FRAMES
  self.progress = self.progress + 1
  -- the walk-cycle clock ticks once per real frame while moving, so the
  -- leg cadence stays constant when the bike halves stepFramesCur (only
  -- translation speed doubles, like UpdatePlayerSprite's frame counters)
  self.animClock = (self.animClock or 0) + 1
  local d = Collision.DELTA[self.facing]
  local px = math.floor(self.progress * 16 / stepLen)
  self.px = self.cellX * 16 + d[1] * px
  self.py = self.cellY * 16 + d[2] * px
  if self.progress >= stepLen then
    self.cellX, self.cellY = self.targetX, self.targetY
    self.targetX, self.targetY = nil, nil
    self.px, self.py = self.cellX * 16, self.cellY * 16
    self.moving = false
    self.stepFlip = not self.stepFlip
    -- keep animClock's pose on this frame (issue #82): bike steps land
    -- mid-cycle (animClock % 16 == 8), and walkPhase used to snap to
    -- stand whenever moving cleared -- a stand flash every tile on the
    -- bike, and sometimes after dismount when the clock is desynced
    self.stepLanded = true
    return true
  end
  return false
end

function Player:facingCell()
  return Collision.target(self.cellX, self.cellY, self.facing)
end

function Player:walkPhase()
  -- moving, the land-frame after a completed step, or an active wall-bonk
  -- (issue #230) animate; a standing sprite otherwise
  if not self.moving and not self.stepLanded
     and not (self.bumpFrames and self.bumpFrames > 0) then
    return 0
  end
  -- walk frame during the middle of each 16-frame animation cycle
  local p = (self.animClock or self.progress) % 16
  return (p >= 4 and p < 12) and 1 or 0
end

local SPIN_ORDER = { "down", "left", "up", "right" }

-- What this frame renders to: the sheet, where it sits, which way it faces
-- and how far through a step it is.  Shared by the 2D draw below and by a
-- render pipeline's own geometry (src/render/Pipelines.lua), so the two can
-- never disagree about which sprite or facing is current.
--
-- The last return says the player is mid-ledge-hop, which is what the 2D
-- path draws the ground shadow from and a 3D path turns into vertical lift.
--
-- This ADVANCES the surf-bob and spinner timers, so exactly one of pose()
-- and draw() may run per frame -- and draw() is written in terms of pose()
-- to keep that true by construction.  (hopFrames counts down in
-- Player:update, on the fixed step, so it is safe to read here.)
function Player:pose()
  local py = self.py
  local hopping = false
  -- ledge hops arc (set for 2 cells by the ledge handler); surfing bobs
  if self.hopFrames and self.hopFrames > 0 then
    local total = self.hopTotal or 32
    -- update runs before draw, so remaining N means N steps already
    -- consumed this hop → t matches the old draw-side post-decrement phase
    local t = 1 - self.hopFrames / total
    py = py - math.floor(10 * math.sin(t * math.pi) + 0.5)
    hopping = true
  elseif self.surfing then
    self.bobTimer = ((self.bobTimer or 0) + 1) % 32
    py = py + (self.bobTimer < 16 and 0 or 1)
  end
  local facing = self.facing
  local phase = self:walkPhase()
  -- alternate walk cycles mirror the up/down frame; derived from the
  -- fixed-rate animation clock so the bike's shorter steps don't double
  -- the leg cadence
  local flip = math.floor((self.animClock or 0) / 16) % 2 == 1
  if self.spinning then
    -- spinner tiles whirl the sprite on its standing pose, one facing
    -- per frame (LoadSpinnerArrowTiles runs every OverworldLoop frame)
    self.spinTimer = (self.spinTimer or 0) + 1
    facing = SPIN_ORDER[self.spinTimer % 4 + 1]
    phase, flip = 0, false
    -- teleport arrivals spin the sprite down into place
    -- (EnterMapAnim PlayerSpinWhileMovingDown)
    if self.spinFrames and self.spinDrop then
      py = py - math.floor(self.spinFrames * 24 / (self.spinTotal or 64))
    elseif self.spinFrames and self.spinRise then
      -- Dig/Teleport/Escape-Rope departures spin the sprite UP out of the
      -- map before the fade (LeaveMapAnim PlayerSpinWhileMovingUp) -- the
      -- mirror of the arrival spin-down: the lift grows from 0 as spinFrames
      -- counts down to 0 (#196), opposite sign to spinDrop above.
      local total = self.spinTotal or 64
      py = py - math.floor((total - self.spinFrames) * 24 / total)
    end
  end
  -- RodResponse (engine/items/item_effects.asm) zeroes wWalkBikeSurfState
  -- across FishingAnim, so casting from the water shows the on-foot sheet
  local sprite = (self.fishing and self.sprite)
                 or (self.surfing and self.surfingPikachu and self.surfPikachuSprite)
                 or (self.surfing and self.surfSprite)
                 or (self.onBike and self.bikeSprite) or self.sprite
  return sprite, self.px, py, facing, phase, flip, hopping
end

function Player:draw(camX, camY)
  local sprite, px, py, facing, phase, flip, hopping = self:pose()
  -- the shadow stays on the ground under the jumper, mirrored out of the
  -- single 8x8 tile the ROM stores -- but the two engines lay it out
  -- differently, and their shadow.png tiles differ to match.
  --   RED/BLUE: a 2x2 block (normal/XFLIP/YFLIP/both) whose top-left sits
  --   8px below the sprite's standing top-left (LoadHoppingShadowOAM +
  --   LedgeHoppingShadowOAMBlock at "lb bc, $54, $48",
  --   engine/overworld/ledges.asm); its tile is blank above the bottom
  --   four rows, so the four copies make one 16x16 ellipse.
  --   YELLOW: a single 16x8 row 4px lower.  Its LoadHoppingShadowOAM
  --   copies only two entries (LedgeHoppingShadowOAM: dbsprite 9,11 and
  --   dbsprite 10,11 OAM_XFLIP, raw OAM y=88 against RED's $54=84) and
  --   parks sprites 38/39 offscreen at y=$a0, because its tile is a
  --   full-height half-ellipse that already fills the row.  Mirroring
  --   that tile downward stacked a second blob under the first (#408).
  if hopping and self.shadowImg then
    local yellow = GameVersion.isYellow()
    local sx = math.floor(self.px - camX)
    local sy = math.floor(self.py - camY) - 4 + 8 + (yellow and 4 or 0)
    love.graphics.draw(self.shadowImg, sx, sy)
    love.graphics.draw(self.shadowImg, sx + 16, sy, 0, -1, 1)
    if not yellow then
      love.graphics.draw(self.shadowImg, sx, sy + 16, 0, 1, -1)
      love.graphics.draw(self.shadowImg, sx + 16, sy + 16, 0, -1, -1)
    end
  end
  -- Fishing pose: the standing frame with its bottom tile row swapped for
  -- RedFishingTiles, which is where the hands and the near half of the rod
  -- live; the far half is the rod OAM OverworldState draws (FishingRodOAM,
  -- engine/overworld/player_animations.asm) -- #384
  local fishTile = self.fishing and self.fishTiles and self.fishTiles[facing]
  if fishTile then
    sprite:draw(px, py, camX, camY, facing, 0, false, true)
    sprite:drawTile(fishTile, math.floor(px - camX),
                    math.floor(py - camY) - 4 + 8, facing == "right")
    return
  end
  sprite:draw(px, py, camX, camY, facing, phase, flip)
end

return Player
