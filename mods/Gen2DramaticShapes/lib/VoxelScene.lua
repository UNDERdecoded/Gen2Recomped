-- Voxel world mode: assemble and draw one frame of the 3D scene.
--
-- World space is world pixels and shares its origin with the 2D paths, so
-- the terrain mesh needs no transform at all and a connected map just
-- translates by the same (ox, oy) the flat renderer already offsets it by.
--
-- Order is: the sun's shadow pass, then terrain, then characters, then a 2D
-- overlay for the field FX. There is no y-sort anywhere -- the depth buffer
-- resolves occlusion, which is the whole point of the mode. Walk behind a
-- building and the building is simply in front.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local SpriteBillboards = V.require("SpriteBillboards")
local TileShape = V.require("TileShape")
local Structures = V.require("Structures")
local TerrainAtlas = V.require("TerrainAtlas")
local Voxel = V.require("VoxelState")
local Sky = V.require("Sky")
local Water = V.require("Water")
local VoxelGrid = V.require("VoxelGrid")
local DayNight = V.require("DayNight")
local FirstPerson = V.require("FirstPerson")
local BattleBillboard = V.require("BattleBillboard")
local Pokedex = V.require("Pokedex")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local VoxelScene = {}

-- What the active display mode actually paints with.
--
-- paletteFor hands back a map's RAW SGB zone palette, and that is not what
-- any of the non-colour modes draw. The flat path runs it through
-- PaletteFX.effectiveColors on the way to the shade-remap shader, and that
-- call IS where GRAY, INVERTED and CLASSIC happen -- OG / OG INV replace
-- the palette with the DMG greys (inverted for the latter), CLASSIC
-- replaces it with the green DMG set, and GBC INV permutes the zone's own
-- shades. GBC and RED++ pass through untouched.
--
-- This pass has no shader to apply that in: colour is baked into the atlas
-- and into the sprite sheets ahead of the draw, so it has to run the same
-- transform itself. Without it every mode that is not already a colour mode
-- comes through wearing the SGB palette -- grey and inverted both rendering
-- as plain SGB blue.
local function modeColors(paletteFor, map)
  local c = paletteFor and paletteFor(map) or nil
  return PaletteFX.effectiveColors(c)
end

VoxelScene._modeColors = modeColors   -- named for the suite

-- ------------------------------------------------------------------ sky --
--
-- The void behind the diorama is SKY, at every rung -- so the world reads as
-- standing under something rather than floating on a black plate.
--
-- What is up there differs by rung, and the sky follows it rather than being
-- retuned for each. At 75 degrees the camera is pitched far enough over that
-- the horizon is genuinely in frame, and the bands run down to meet it. At the
-- steeper rungs the horizon is above the top edge and the void that shows is
-- where the ground runs OUT -- past the map edge, past the curve -- so the
-- bands take a fixed slice of the frame instead (lib/Sky.lua, Sky.SPAN) and the
-- haze below them fills the rest.
--
-- INDOORS THERE IS NO SKY. A house, a cave or a gym is a room with a
-- ceiling, and the void past its walls is the outside of a box, not open
-- air. Map.isOutdoor is the same test the engine uses for door SFX and the
-- town map, and the same one Structures already asks to decide whether a
-- map rings with trees.
--
-- The colour is a four-shade ramp shaped like a world palette so the
-- display mode can transform it exactly like one: GRAY gets a grey sky,
-- CLASSIC a green one, GBC INV a dark one, and the colour modes the blue.
-- A hardcoded blue would sit wrong in every non-colour mode -- the same
-- mismatch the terrain bake had.
--
-- This ramp is the FLAT sky -- what a caller clears the void to. The free-roam
-- camera's banded sky has a palette of its own (lib/Sky.lua), transformed the
-- same way by the same seam; they are separate because the flat one also has to
-- serve an indoor void and a battle's arena, which want a colour rather than a
-- sky.
local SKY_SHADES = { { 222, 242, 255 }, { 135, 196, 240 },
                     { 64, 120, 192 }, { 16, 40, 80 } }
local SKY_SHADE = 2       -- the ramp's "sky" proper; 1 is its highlight

-- the ramp as the display mode has it, which is the only form anything here
-- should be reading it in
local function skyRamp()
  return PaletteFX.effectiveColors(SKY_SHADES) or SKY_SHADES
end

-- Full strength at every rung: the sky is painted wherever the diorama is.
--
-- The ramp that is left is for ARRIVAL alone. Switching the mode on eases the
-- camera up from flat, and the sky comes up with it over the first few degrees
-- rather than appearing whole on the keypress -- which is also what keeps a
-- top-down camera, where there is no void worth speaking of, from painting one.
local SKY_FADE_DEG = 8

local function skyStrength(angleRad)
  local deg = math.deg(angleRad or 0)
  if deg <= 0 then return 0 end
  local t = deg / SKY_FADE_DEG
  return t < 1 and t or 1
end

-- One shade off the sky ramp, transformed by the display mode, as an
-- {r, g, b, a} in 0..1. `shade` picks the rung (SKY_SHADE is the sky
-- proper; 4 is its darkest, which is what an indoor void wants).
function VoxelScene.skyShade(shade, alpha)
  local shades = skyRamp()
  local c = shades[shade] or SKY_SHADES[shade] or SKY_SHADES[SKY_SHADE]
  return { c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1 }
end

-- The sky `map` stands under at strength `t`, or nil where there is no sky
-- to paint: indoors, or with the horizon out of frame.
--
-- One flat colour, which is what a caller that only needs something to clear the
-- void to wants -- the overworld battle's arena shot is one of those. The
-- gradient is added on top of this by skyFor, for the free-roam camera alone.
function VoxelScene.skyColor(map, t)
  if not (map and map.def and Map.isOutdoor(map.def)) then return nil end
  if not t or t <= 0 then return nil end
  local sky = VoxelScene.skyShade(SKY_SHADE, t)
  -- outdoors the flat fill follows the CLOCK: it becomes the hour's haze --
  -- gold at dusk, navy at night -- so a battle staged on the map at
  -- midnight is under a midnight void, not a noon one. Free-roam is
  -- unchanged by this: Sky.dress overwrites the fill with the same value.
  local haze = Sky.haze()
  if haze then sky[1], sky[2], sky[3] = haze[1], haze[2], haze[3] end
  return sky
end

-- The free-roam sky: the flat one above, dressed with the banded gradient
-- (lib/Sky.lua).
--
-- Only here, and deliberately. This is the sky the walking camera stands under,
-- where the horizon is a quarter of the way down the frame at the top rung and
-- one flat blue reads as a wall of paint. A battle is a staged shot with its own
-- placed camera whose horizon sits above the frame entirely, so it keeps the
-- flat fill it has always had -- there is no gradient to see from down there,
-- and the arena's look is not this rung's to change.
local function skyFor(map)
  local sky = VoxelScene.skyColor(map, skyStrength(Voxel.angle))
  if not sky then return nil end
  return Sky.dress(sky)
end

VoxelScene._skyFor = skyFor           -- named for the suite
VoxelScene._skyStrength = skyStrength

-- A facing as a yaw about +Y, kept for callers that reason about which way
-- an entity points (the mod exports it). The character cards themselves
-- never yaw -- they face south and lean, like the flat game.
local YAW = {
  down = 0,
  up = math.pi,
  right = math.pi / 2,
  left = -math.pi / 2,
}

-- The ground height a cell stands at, so a character on a ledge stands on
-- top of it rather than sunk into it. Uses the same bottom-left collision
-- tile the engine walks on (Map:cellTile).
local function groundAt(map, cellX, cellY)
  -- Off the map, cellTile border-extends into the map's borderBlock --
  -- which on maps ringed with trees is a RAISED tile. The only entity
  -- ever standing off-map is the player mid seam-step (placed one cell
  -- before the connection entry), and the ground actually rendered
  -- there is the departed neighbour's flat walkway: height 0. Without
  -- this, crossing into such a map hoisted the walker tree-high for
  -- exactly one step -- the "hops like a ledge" seam bug.
  if not map:inBounds(cellX, cellY) then return 0 end
  local shapes = TileShape.forMap(map)
  -- the same full resolution the mesher draws with, NOT the raw tile table:
  -- on Gen 2 map:cellTile answers a COLLISION CLASS rather than a tile id,
  -- so indexing the tile shapes with it read some unrelated tile's box and
  -- stood every character 16px above the ground they were walking on
  local tx, ty = cellX * 2, cellY * 2 + 1
  local s = TileShape.at(map, shapes, map:tileAt(tx, ty), tx, ty)
  if not s then return 0 end
  -- a box the walker passes THROUGH rather than onto: Gen 2 pins its
  -- doorways solid so the facade closes over them, and the cell they are
  -- cut into stays walkable
  if s.art == "upright" and map:isWalkableCell(cellX, cellY) then return 0 end
  -- a recessed class (water) still supports whatever stands on it; only
  -- raised ground lifts the model.  Stairs never do: the class height is
  -- the flight's TALL end, but the player enters at floor level and the
  -- warp fires as they step in -- lifting them onto the geometry read as
  -- climbing an invisible block
  if s.art == "stair" then return 0 end
  -- ...and a cell the mesher gave a MEASURED height to answers with that
  -- one, not with its class default: the river above a waterfall is drawn
  -- at the fall's crest (Structures.buildFalls), and a surfer reading the
  -- class height alone swam four cells under the sheet he was floating on.
  local measured = Structures.runHeight(map, tx, ty)
  if measured and measured > 0 then return measured end
  return s.h > 0 and s.h or 0
end

VoxelScene.YAW = YAW
-- shared with the overworld battle, which stands its mons on map cells and
-- needs the same answer about what height "the floor" is there
VoxelScene.groundAt = groundAt

-- Camera-ward pull distance for billboards (and the grass rows, which
-- must keep their relative depth to feet): just enough that a leaned-back
-- slab clears the wall it leans over. The lean flattens toward top-down,
-- so the needed pull grows exactly as real occlusion stops mattering.
function VoxelScene.pull(a)
  return 6 + math.max(0, 16 * math.cos(a) - 8) / math.max(math.sin(a), 0.2)
end

-- The sheet frame and mirror flag the 2D path would draw for this pose
-- (same tables as SpriteRenderer). Shared by the billboard pass and the
-- shadow pass so a walking character's shadow swings its legs too.
local function frameFor(def, facing, phase, flip)
  local SR = require("src.render.SpriteRenderer")
  local frame, mirror = 0, false
  -- SPRITE_POKEMON objects carry a 2-frame party icon with no facing at all,
  -- so the pose tables (which index up to 5) do not apply to them
  if def.monIcon then
    return math.floor((love.timer and love.timer.getTime() or 0) * 4) % 2, false
  end
  if (def.frames or 1) > 1 then
    frame = (def.walker and phase == 1) and SR.WALK[facing]
            or SR.STAND[facing]
    mirror = facing == "right"
      or ((facing == "down" or facing == "up") and phase == 1 and flip)
  end
  return frame, mirror
end

-- The facing a pose SHOWS this camera. The flat frames are "how this pose
-- looks from the south", which is where the orbit always stands; a
-- first-person eye stands anywhere, so deep enough into the blend the
-- facing is remapped to how the pose looks from THERE -- walk behind an
-- NPC and their card wears the back sprite. Used by the camera draw and
-- the sun pass BOTH: the card the sun stored and the transform a lit card
-- reads its own shadowing with must describe the same frame, or the
-- mirror-flip half of the pair asks the map about texels the sun filed
-- under the other cheek.
-- The player's own card asks a different function for the same answer:
-- their body's bearing is what the camera is derived FROM, so it is known
-- continuously rather than as one of four directions, and measuring
-- against the compass point instead flicks the card to a profile for a
-- frame or two when the camera is spun fast (see playerFacing).
local function viewFacing(p)
  if FirstPerson.cardBlend() > 0.5 then
    if p.isPlayer then
      return FirstPerson.playerFacing(p.facing, p.px + 8, p.py + 8)
    end
    return FirstPerson.apparentFacing(p.facing, p.px + 8, p.py + 8)
  end
  return p.facing
end

-- FALLBACK ONLY (see castShadows below). Draw one entity's drop shadow as
-- a decal: its current sprite frame as a single quad, flattened onto the
-- ground along the sun line (Voxel3D.shadowMatrix). Runs inside
-- beginShadows, which supplies the translucent black; the texture is only
-- consulted for its alpha, so no palette work is needed.
local function drawShadow(sprite, px, py, facing, phase, flip, gh, lift)
  local def = sprite.def
  local frame, mirror = frameFor(def, facing, phase, flip)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  Voxel3D.draw(mesh, sprite:resolveImage(),
               Voxel3D.shadowMatrix(px, py, gh, lift, mirror))
end

-- Where a billboard character's card stands: on the middle of its cell at
-- height `y`, pivoted at the feet and tipped back by exactly the camera's
-- pitch. The slab is built centred on its sprite plane (z = 0), so only the
-- x anchor shifts; the relief bulges symmetrically front and back of it.
--
-- Shared by the solid draw and the silhouette below, so the two can never
-- drift apart -- a silhouette standing anywhere but exactly behind the
-- figure would read as a second character.
--
-- IN FIRST PERSON the card stops leaning and starts TURNING: upright, yawed
-- about its feet to face the eye (cylindrical billboarding). A south-facing
-- card is invisible edge-on to an eye standing east of it, which no orbit
-- camera could ever do and a first-person one does constantly. The blend
-- carries one pose into the other -- the lean eases out as the yaw eases in
-- -- and cardBlend is zero for every camera that is not the first-person
-- rig, the battle's placed shot included, so nothing else moves.
-- The pitch the sprite cards lean back by -- normally the rung's own
-- camera angle, overridable in radians. VR sets the override to the top
-- rung's 75 degrees for every diorama and battle frame: a table watched
-- from a freely moving head has no one camera pitch for the cards to
-- match, and the near-upright top-rung lean is the pose that reads as
-- "standing" from anywhere around it. nil (the default, and the flat
-- screen always) leans with the rung as ever.
VoxelScene.spriteLean = nil

local function leanAngle()
  return VoxelScene.spriteLean or V.require("VoxelState").angle
end

local function billboardMatrix(px, py, y, mirror)
  local b = FirstPerson.cardBlend()
  local m = Mat4.translate(px + 8, y, py + 8)
  if b > 0 then
    m = Mat4.mul(m, Mat4.rotateY(FirstPerson.cardYaw(px + 8, py + 8) * b))
  end
  m = Mat4.mul(m, Mat4.rotateX((leanAngle() - math.pi / 2) * (1 - b)))
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  return Mat4.mul(m, Mat4.translate(-8, 0, 0))
end

local function billboardPull()
  return VoxelScene.pull(math.max(leanAngle(), 0.05))
end

-- An authored FIGURE's card -- a person the tileset draws INTO a piece of
-- furniture, cut out by the profile's mask (Structures.buildFigures). It is
-- a sprite, so it gets the sprite treatment: the mesh arrives in its own
-- local space with its feet on y = 0, and this stands it at its drawn
-- position and tips it back by exactly the camera's pitch -- the same
-- pivot-at-the-feet lean billboardMatrix gives a character, so the man on
-- the Pokemon Center couch reads face-on at every tilt like the NPCs
-- around him. No cell centring: unlike a character he is not standing on a
-- cell, he is standing where he was drawn, which may straddle two.
--
-- First person turns him at the eye like the walkers (see billboardMatrix)
-- -- about his own middle, because unlike a character card his local space
-- starts at x = 0 rather than being anchored by a -8 shift, and a yaw about
-- his edge would swing him off his seat. The width rode in on the record
-- for exactly this (ChunkMesher.buildFigureMeshes).
local function figureMatrix(f, offX, offZ)
  local b = FirstPerson.cardBlend()
  local wx, wz = f.wx + (offX or 0), f.wz + (offZ or 0)
  local m = Mat4.translate(wx, f.y, wz)
  if b > 0 and f.w and f.w > 0 then
    local half = f.w / 2
    m = Mat4.mul(m, Mat4.translate(half, 0, 0))
    m = Mat4.mul(m, Mat4.rotateY(FirstPerson.cardYaw(wx + half, wz) * b))
    m = Mat4.mul(m, Mat4.translate(-half, 0, 0))
  end
  return Mat4.mul(m, Mat4.rotateX((leanAngle() - math.pi / 2) * (1 - b)))
end

-- What the sun sees: the same card UNLEANED and flattened, exactly as
-- Voxel3D.casterMatrix does it for a character.
local function figureCaster(f, offX, offZ)
  return Mat4.mul(
    Mat4.translate(f.wx + (offX or 0), f.y, f.wz + (offZ or 0)),
    Mat4.scale(1, 1, 0))
end

-- Every figure on `map`, drawn with `draw(mesh, model, caster)`.
local function eachFigure(map, offX, offZ, draw)
  for _, f in ipairs(ChunkMesher.figures(map) or {}) do
    draw(f.mesh, figureMatrix(f, offX, offZ), figureCaster(f, offX, offZ))
  end
end

-- Draw one posed entity. Returns true if 3D geometry carried it, false
-- when nothing could be built and the caller should fall back.
-- `colors` is the 4-color world palette the entity stands under in the SGB
-- modes (nil under RED++/trueColor): the 2D path colorizes sprites with a
-- screen-space shader the voxel canvas never runs through, so the model's
-- texture gets the palette baked in instead (TerrainAtlas.forSprite).
-- `lift` raises the figure off the ground plane (ledge hops arc UP in 3D,
-- where the 2D path could only slide the sprite north).
local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,
                          lift)
  local def = sprite.def
  local tex = sprite:resolveImage()
  if colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, colors) or tex
  end
  local y = gh + (lift or 0)

  -- pick the very frame the 2D path would draw (same tables). The card
  -- always faces SOUTH -- the direction the 2D game implies -- and only
  -- LEANS BACK, pivoting at its feet, by exactly the camera's pitch, so
  -- at every tilt level the sprite reads face-on like the flat game.
  -- No camera-tracking yaw: every sprite leans in parallel.
  local frame, mirror = frameFor(def, facing, phase, flip)
  local mesh = SpriteBillboards.mesh(def, frame)
  if not mesh then return false end
  -- Camera-ward pull (applied per vertex in the shader, along each
  -- vertex's own eye ray, so it is a PURE depth bias with zero screen
  -- drift): lets the leaned-back head win against the wall it leans
  -- OVER while a character genuinely BEHIND a building is dozens of
  -- pixels deeper and still loses, so real occlusion works.
  -- the same card UNLEANED -- and SNUGGED, exactly as the sun stored it
  -- (castShadows draws this mesh through ShadowMap.snug) -- is where each
  -- vertex asks whether the light reached it; see ShadowMap.snug for why
  -- the lookup must match the stored transform to the letter
  Voxel3D.draw(mesh, tex, billboardMatrix(px, py, y, mirror),
               billboardPull(),
               ShadowMap.snug(Voxel3D.casterMatrix(px, py, y, mirror)))
  return true
end

VoxelScene.drawEntity = drawEntity

-- The player's silhouette, for wherever the scenery is standing in front of
-- them (Voxel3D.beginGhost inverts the depth test around this call).
--
-- The same flat card the solid pass and the sun pass draw. That it has no
-- self-overlap is what makes it safe here: with the depth test inverted, a
-- mesh carrying both front and back faces would read its own back faces as
-- "behind something" and repaint the figure on open ground, occluded or
-- not. One quad cannot do that, and cannot double-blend into a mottled
-- patch either. A silhouette is an outline, so an outline is the right
-- mesh for it.
local function drawGhost(p)
  local def = p.sprite.def
  local frame, mirror = frameFor(def, viewFacing(p), p.phase, p.flip)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  local tex = p.sprite:resolveImage()
  if p.colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, p.colors) or tex
  end
  local y = p.gh + (p.lift or 0)
  Voxel3D.draw(mesh, tex, billboardMatrix(p.px, p.py, y, mirror),
               billboardPull())
end

-- Render the world. `state` is the OverworldState; `vw`/`vh` the world view
-- size in world pixels; `w`/`h` the pixel size of the canvas to render
-- into; `paletteFor(map)` yields a map's 4-color world palette (nil in the
-- color modes whose atlas is already true color). Returns the finished
-- canvas, or nil if the 3D pass could not run (headless, no depth support)
-- so the caller can fall back to 2D.
-- The last live-set key, so eviction only runs when the neighbourhood
-- actually changes (a map crossing), not every frame.
local lastLiveKey = nil

-- Request everything `state`'s frame wants and evict what it no longer
-- does; returns the current map's terrain mesh (or nil while it builds)
-- and the neighbour meshes ready to draw. render() calls this for the
-- frame it is drawing, and the pipeline's update hook calls it EVERY
-- frame -- including the frames a warp's Transition covers, when the
-- world pass is off. That update-side call is what lets a door fade hide
-- the destination's build: the map swaps behind the fade, and waiting
-- for the first visible frame to request meshes would show the flat
-- fallback while the first slices run.
function VoxelScene.prefetch(state)
  local Voxel = V.require("VoxelState")

  -- The live set is the current map plus its rendered neighbours. When
  -- it changes, everything outside it (and the previous set, which
  -- ChunkMesher retains so stepping into a house keeps the town warm)
  -- is evicted -- meshes released, analysis dropped -- so memory stays
  -- bounded by the neighbourhood instead of growing with every area
  -- ever visited.
  local liveKey = state.map.id
  local live = { [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do
    live[nb.map.id] = true
    liveKey = liveKey .. "|" .. nb.map.id
  end
  if liveKey ~= lastLiveKey then
    lastLiveKey = liveKey
    ChunkMesher.setLive(live)
    -- RED++ bakes one atlas per map, so its animated copy is per map too
    -- and is bounded by the same neighbourhood
    TerrainAtlas.setLive(live)
  end

  -- masks: where connected neighbour BODIES sit, so the border ring is
  -- suppressed under them (see runGeometry)
  local masks = {}
  for _, nb in ipairs(state.neighbors or {}) do
    masks[#masks + 1] = { nb.ox, nb.oy,
                          nb.ox + nb.map.def.width * 32,
                          nb.oy + nb.map.def.height * 32 }
  end

  -- Builds are asynchronous (ChunkMesher.pump runs in the pipeline's
  -- update): request what this frame wants and draw what is ready.
  -- The current map draws its body-only mesh while the full one (the
  -- border ring) is still building -- a seam crossing promotes a
  -- neighbour whose body is already cached, and the ring pops in a few
  -- frames later, mostly hidden behind the map just left. A neighbour
  -- missing its body-only mesh draws its cached FULL mesh instead -- a
  -- crossing demotes the map just left, and it must not vanish from
  -- behind the player while its body variant builds; its ring is
  -- already masked out under this map's body, so the stand-in is safe.
  -- The water surface rides along with whichever variant answers: it was
  -- cut out of that build's own geometry (ChunkMesher.pair), so the two
  -- always come from the same slot and a lake is never drawn twice or left
  -- as a hole.
  ChunkMesher.request(state.map, false, masks, true)
  local terrain, water = ChunkMesher.pair(state.map, false)
  if not terrain then
    terrain, water = ChunkMesher.pair(state.map, true)
  end
  local nbMesh, nbWater = {}, {}
  for i, nb in ipairs(state.neighbors or {}) do
    ChunkMesher.request(nb.map, true)
    nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, true)
    if not nbMesh[i] then
      nbMesh[i], nbWater[i] = ChunkMesher.pair(nb.map, false)
    end
  end
  Voxel.ready = terrain ~= nil
  return terrain, nbMesh, water, nbWater
end

-- Capture every entity's pose for this frame. pose() advances the hop /
-- surf bob / spinner timers, so it must be called EXACTLY once per entity
-- per frame -- the sun pass and the character pass then read the same
-- answer instead of disagreeing by a tick. Ghost NPCs live on a neighbour
-- map, so their position, ground lookup and palette all belong to that
-- map. pose() returns the VISUAL y (ledge hops arc it, surfing bobs it);
-- the difference from the entity's base y becomes vertical LIFT in 3D, so
-- a hop rises off the ground instead of sliding north.
-- Returns the pose list and, separately, the PLAYER's entry in it (nil
-- during a Fly animation, which draws the player itself and is skipped
-- below). Only that one entry gets the see-through treatment: NPCs and the
-- ghosts standing on a neighbour map are left to honest occlusion, because
-- it is only your own character you cannot afford to lose behind a roof.
local function posesOf(state, spriteColors)
  local colors = spriteColors(state.map)
  local posed = {}
  local me = nil
  for _, g in ipairs(state.ghosts or {}) do
    local sprite, vx, vy, facing, phase, flip = g.npc:pose()
    posed[#posed + 1] = {
      sprite = sprite, px = vx + g.ox, py = g.npc.py + g.oy,
      facing = facing, phase = phase, flip = flip,
      gh = groundAt(g.map or state.map, g.npc.cellX, g.npc.cellY),
      lift = g.npc.py - vy, colors = spriteColors(g.map or state.map),
    }
  end
  for _, e in ipairs(state.entities or {}) do
    if not (state.flyAnim and e == state.player) then
      local sprite, vx, vy, facing, phase, flip = e:pose()
      posed[#posed + 1] = {
        sprite = sprite, px = vx, py = e.py,
        facing = facing, phase = phase, flip = flip,
        gh = groundAt(state.map, e.cellX, e.cellY),
        lift = e.py - vy, colors = colors,
      }
      if e == state.player then
        me = posed[#posed]
        -- marked so the camera draw can leave the card out in first
        -- person, where it would fill the lens from inside; the SUN pass
        -- reads the same list and deliberately does not check the mark
        me.isPlayer = true
      end
    end
  end
  return posed, me
end

-- ------- the glint's drive
--
-- A reflection is something the VIEWPOINT does, so the window glint is fed
-- by the camera's own travel rather than by a clock: its phase advances
-- with distance covered and its strength fades in over a few steps of
-- walking and back out within a beat of standing still. Stand still and
-- the glass is still; move and the light crosses it.
-- The rate is slow on purpose: the sweep pattern lives in the pane's own
-- texels (see the scene shader), so this is a FRACTION of a texel per world
-- pixel walked -- one full pass of the glint across a pane per eight or so
-- cells of travel, with no frame ever jumping it far enough to strobe.
VoxelScene.GLINT_RATE = 0.05     -- radians of sweep per world pixel travelled
VoxelScene.GLINT_IN = 0.12      -- strength gained per moving frame
VoxelScene.GLINT_OUT = 0.08     -- and lost per resting frame

function VoxelScene.glintStep(g, cx, cy)
  local dist = 0
  if g.x then
    dist = math.abs(cx - g.x) + math.abs(cy - g.y)
  end
  g.x, g.y = cx, cy
  g.phase = ((g.phase or 0) + dist * VoxelScene.GLINT_RATE) % (2 * math.pi)
  if dist > 0.05 then
    g.amp = math.min(1, (g.amp or 0) + VoxelScene.GLINT_IN)
  else
    g.amp = math.max(0, (g.amp or 0) - VoxelScene.GLINT_OUT)
  end
  return g
end

local glint = {}

-- ------- the cast
--
-- Everybody standing on the map: the walkers, and the authored FIGURES the
-- tileset draws into its own furniture (they ARE characters as far as the
-- artwork is concerned, just ones drawn by the tileset instead of by a
-- sprite sheet, so they get the same lean and the same camera-ward pull).
--
-- One function because it is drawn TWICE and the two must be identical: once
-- into the frame, and once into the water's reflection copy (see drawWater --
-- Gen 1 draws people over the world, and water is world, so the cast cannot
-- be composited before the water it has to appear in).
--
-- Characters carry no wireframe out here, whatever the V-GRID row says. The
-- seams are what makes the WORLD read as built out of voxels, and the people
-- walking around in it are the one thing that should read as drawn instead --
-- a grid over a 16x16 sprite lands a line every couple of display pixels and
-- turns a face into a mesh. (The battle pass makes the opposite call for its
-- own combatants, deliberately -- see BattleBillboard.)
--
-- Sprite sheets until the figure pass: their texture coordinates mean
-- nothing to the tileset-shaped glass mask, so the glass is off or the
-- panes' atlas positions stripe the cast with lamplight at night.
local function drawCast(state, posed, atlasFor)
  Voxel3D.glass(false)
  Voxel3D.seams(false)
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  --
  -- In first person two of them change: the player's own card is left out
  -- (the eye is standing in it), and every other card wears the frame its
  -- pose SHOWS this eye (viewFacing) rather than the one it shows the
  -- south. Both run through here, so the water's reflection copy -- drawn
  -- by this same function -- agrees with the frame to the pixel.
  local hideMe = FirstPerson.hidePlayer()
  for _, p in ipairs(posed) do
    if not (p.isPlayer and hideMe) then
      drawEntity(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,
                 p.colors, p.lift)
    end
  end
  -- back on for everything textured from the atlas again -- figures, grass
  -- and flowers all sample it, where the mask's coordinates are honest
  Voxel3D.glass(true)
  -- Figures after the walkers, so a player standing in front of the couch
  -- wins the overlap -- the order the flat game draws them in.
  local figPull = billboardPull()
  eachFigure(state.map, 0, 0, function(mesh, model, caster)
    Voxel3D.draw(mesh, atlasFor(state.map), model, figPull,
                 ShadowMap.snug(caster))
  end)
  for _, nb in ipairs(state.neighbors or {}) do
    eachFigure(nb.map, nb.ox, nb.oy, function(mesh, model, caster)
      Voxel3D.draw(mesh, atlasFor(nb.map), model, figPull,
                   ShadowMap.snug(caster))
    end)
  end
  -- and the seams are back on for the terrain art that follows: grass and
  -- flowers are the world's own drawing, not people
  Voxel3D.seams(true)
end

-- ------- the water pass
--
-- Between the terrain and everything that stands on it, because water is a
-- MIRROR and a mirror can only reflect what is already down: the ground, the
-- shoreline, the trees and buildings behind it, and the sky the frame opened
-- with.
--
-- THE CAST IS THE AWKWARD ONE, and it is settled by drawing it twice. Gen 1
-- draws people over the world and water is world, so a surfing player has to
-- composite OVER the water they are sitting on -- which puts them after it,
-- and a reflection can only hold what came before it. So `cast` is painted
-- into the reflection copy alone (Voxel3D.beginWater), where it is in the
-- picture the water reflects and not yet in the picture the water is drawn
-- into. Both draws go through drawCast, so they cannot come out different.
--
-- The ray march finds them the honest way round: a sprite is not in the
-- DEPTH buffer at that point, so a ray aimed at one passes through to the
-- terrain standing behind it and reads the copy there -- where the sprite is
-- already painted. The reflection lands a hair off the sprite's own depth
-- and exactly on its colour, which at a lake's worth of ripple is the same
-- picture.
--
-- `draws` is a list of { mesh, texture, model }. Nothing is a special case:
-- with the row OFF, no depth texture to read, or a shader that would not
-- build, the same meshes go through the ordinary scene shader and come out
-- as the flat animated water this mode always drew.
-- The overworld's alone: the staged battle draws its water plain, always --
-- its placed camera reads this pass wrong, and a stage set wants painted
-- water anyway (see BattleScene, where the choice is argued).
-- ------- and why the flat draw happens FIRST while the world is curved
--
-- The reflective pass writes no depth -- it cannot, the depth canvas is
-- detached for the length of it so the shader can READ it -- and it does its
-- own depth test against that texture instead. That test asks whether
-- something opaque is in front, and it answers correctly for every case but
-- one: WATER IN FRONT OF WATER. Nothing puts water in the depth buffer, so
-- no lake can hide another, and the pass simply paints them in mesh order.
--
-- On a flat world that never matters: every surface lies in the one plane
-- at its own recessed height, and a farther sheet always lands farther down
-- the screen. THE WORLD CURVE ENDS THAT. The bend drops the world by the
-- square of its distance, so the far side of the map swings down and back
-- up into the near field of view -- and a sheet of sea a hundred and fifty
-- tiles away, drawn later in the same mesh, paints straight over the pond
-- at the player's feet. Not a reflection of the far shore: the far shore
-- itself, rasterised on top of the water in front of you.
--
-- So WHILE THE CURVE IS ON, the meshes go down flat first, through the
-- ordinary scene shader with depth writes on, and the reflective pass draws
-- over the top of what survived: the depth buffer now holds the water
-- surface, so the pass's own test throws the far sheet away, and the
-- reflection COPY holds it too, so a ray grazing another part of the lake
-- reads water rather than the void behind it.
--
-- With the curve OFF the prepass is not just unnecessary, it is a LIABILITY,
-- and it stays off -- the reflective pass tests only against terrain, as it
-- always did. Painting the surface into the depth texture turns the pass's
-- test into a comparison of the surface against ITSELF, which asks the two
-- rasterisations to agree to within interpolation error -- and on mobile
-- GPUs they don't reliably (that fight is what put the Android port back on
-- flat water). Confined to the curve there is no regression to reach: the
-- flat world never had the far-shore bug in the first place.
function VoxelScene.drawWater(draws, cast)
  -- prepass only under the bend; see the header
  local curved = (Voxel3D.curveK or 0) > 0
  if curved then
    for _, d in ipairs(draws) do
      Voxel3D.draw(d[1], d[2], d[3])
    end
  end
  local plain = not curved
  if Water.enabled() and Voxel3D.depthReadable() then
    local mirror, depth = Voxel3D.beginWater(cast)
    local w, h = Voxel3D.size()
    local ok = mirror and depth and Water.begin({
      reflect = mirror, depth = depth,
      vp = Voxel3D.vp, eye = Voxel3D.eye, curve = { Voxel3D.curveX or 0,
                                                    Voxel3D.curveZ or 0,
                                                    Voxel3D.curveK or 0 },
      screen = { w, h }, cell = Voxel3D.cell, fov = Voxel3D.fovY,
      skyEdge = Voxel3D.skyEdge, grid = VoxelGrid.enabled(),
      lookFlat = Voxel3D.lookFlat, descent = Voxel3D.descent,
    })
    if ok then
      for _, d in ipairs(draws) do
        Water.draw(d[1], d[2], d[3])
      end
      Water.finish()
      plain = false
    end
    -- Unconditionally, and OUTSIDE the success branch: beginWater unbinds
    -- the shader and the depth mode BEFORE it can discover it cannot go on,
    -- so a frame that bails halfway through has to be put back together
    -- exactly like one that succeeded -- otherwise every pass after it runs
    -- with no shader and no depth test.
    Voxel3D.endWater()
  end
  -- the fallback flat draw -- unless the curve's prepass already put the
  -- same meshes down, in which case a bailed frame is already whole
  if plain then
    for _, d in ipairs(draws) do
      Voxel3D.draw(d[1], d[2], d[3])
    end
  end
end

-- A stamp of everything the sun pass depends on. Nothing in it moving
-- means the shadow map it produced last frame is still exactly right, and
-- redrawing the whole world from the sun would buy nothing -- which is
-- most of a dialog, a menu, or any moment standing still.
local sigBuf = {}
local function shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  local n = 0
  local function put(v)
    n = n + 1
    sigBuf[n] = v
  end
  -- quarter-pixel camera granularity: the light frustum is snapped to
  -- whole texels anyway, each a third of a world pixel
  put(math.floor(cx * 4))
  put(math.floor(cy * 4))
  -- the view size and the camera PITCH are both what the light frustum is
  -- fitted to (a lower camera sees further north, so the box grows), so a
  -- zoom step, a window resize or a rung change invalidates the map even
  -- standing perfectly still
  put(vw); put(vh)
  put(math.floor((V.require("VoxelState").angle or 0) * 512))
  -- the sun itself: the cycle swings the shear as the clock runs, and a map
  -- lit from somewhere new must be redrawn from there too. Quantised by the
  -- rig's own step (DayNight.rigTime), so a running cycle redraws the map a
  -- few times a minute rather than every frame.
  put(math.floor(ShadowMap.KX * 128))
  put(math.floor(ShadowMap.KZ * 128))
  -- and the first-person head: the box is fitted around wherever it looks
  -- and the sprite cards swap frames as it circles them, so a turn on the
  -- spot re-fits and redraws exactly like a camera move ("" outside 1ST)
  put(FirstPerson.signature())
  put(tostring(terrain))
  for i = 1, #nbMesh do put(tostring(nbMesh[i])) end
  for _, p in ipairs(posed) do
    put(p.sprite.def.image)
    put(p.px); put(p.py); put(p.gh); put(p.lift or 0)
    put(p.facing); put(p.phase); put(p.flip and 1 or 0)
  end
  for i = n + 1, #sigBuf do sigBuf[i] = nil end
  return table.concat(sigBuf, ",")
end

-- The sun pass: render the scene once from the light, so the main pass can
-- ask any fragment whether the sun reached it. Every caster the main pass
-- draws goes in -- the terrain mesh, which is where buildings, trees,
-- ledges, signs and every prop live, plus one UPRIGHT card per character
-- (Voxel3D.casterMatrix; the leaning slab is a trick for the camera, not
-- for the sun) -- so shadows land on walls, roofs, ledges and passing NPCs
-- as readily as on the floor.
--
-- Runs BEFORE Voxel3D.beginScene, because canvases do not nest. Grass is
-- left out on purpose: thousands of tufts would cast a speckle no bigger
-- than the pixels it lands on, at the cost of the mesh being drawn twice.
local function castShadows(state, terrain, nbMesh, posed, cx, cy, vw, vh,
                           atlasFor, water, nbWater, battleCards, battleToken)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  -- a staged fight's pics move every frame the animation does, and the sun
  -- has to follow them (VR frames only; see render)
  if battleToken then sig = sig .. "|btl" .. tostring(battleToken) end
  if not ShadowMap.stale(sig) then return end
  if not ShadowMap.begin(cx, cy, vw, vh) then return end

  ShadowMap.draw(terrain, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    ShadowMap.draw(nbMesh[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- The water surface, which the terrain mesh no longer carries (it is its
  -- own reflective pass now -- see Water). The sun still has to see it, or
  -- the map the light records has a hole at every lake and the frustum's
  -- far plane answers for the surface a shoreline tree's shadow falls on.
  ShadowMap.draw(water, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    ShadowMap.draw(nbWater and nbWater[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- flower billboards live outside the terrain mesh (they draw after the
  -- characters, pulled -- see render), but the sun still sees them: a
  -- handful of cutouts per meadow, unlike the grass left out below.
  -- Every thin card from here down is SNUGGED toward the sun along its own
  -- ray (ShadowMap.snug) so its shadow keeps contact with its feet instead
  -- of starting a bias-width away.
  ShadowMap.draw(ChunkMesher.flowers(state.map), atlasFor(state.map),
                 ShadowMap.snug(nil))
  for _, nb in ipairs(state.neighbors or {}) do
    ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end
  -- From here down it is the CAST, marked as such in the map (see
  -- ShadowMap.sprites) so water can decline them: everything the world casts
  -- still shades a lake, a silhouette of somebody standing beside it does
  -- not. Ground, roofs and the characters themselves take them as before.
  ShadowMap.sprites(true)
  -- authored figures cast too, for the same reason the flowers do: a
  -- handful of cards per map, and a person with no shadow reads as pasted on
  eachFigure(state.map, 0, 0, function(mesh, _, caster)
    ShadowMap.draw(mesh, atlasFor(state.map), ShadowMap.snug(caster))
  end)
  for _, nb in ipairs(state.neighbors or {}) do
    eachFigure(nb.map, nb.ox, nb.oy, function(mesh, _, caster)
      ShadowMap.draw(mesh, atlasFor(nb.map), ShadowMap.snug(caster))
    end)
  end
  for _, p in ipairs(posed) do
    local def = p.sprite.def
    -- viewFacing, exactly as the camera draw picks it (see viewFacing for
    -- why the two passes must agree): in first person the sun's card
    -- swaps frame as the eye circles, which costs a redraw the signature
    -- already charges for (FirstPerson.signature) and keeps a card from
    -- fringing against a mirror-flipped record of itself
    local frame, mirror = frameFor(def, viewFacing(p), p.phase, p.flip)
    local mesh = SpriteBillboards.shadowQuad(def, frame)
    if mesh then
      ShadowMap.draw(mesh, p.sprite:resolveImage(),
                     ShadowMap.snug(
                       Voxel3D.casterMatrix(p.px, p.py, p.gh + (p.lift or 0),
                                            mirror)))
    end
  end
  -- a staged fight's mons (VR frames only): the same cards the eye pass
  -- stands on the arena, snugged like every thin card, marked as the cast
  -- so the water can decline them like everybody else's silhouette
  for _, card in ipairs(battleCards or {}) do
    ShadowMap.draw(BattleBillboard.mesh(), card.tex, ShadowMap.snug(card.model))
  end
  ShadowMap.sprites(false)

  ShadowMap.finish(sig)
end

-- Render the world. Without `eyes`, one frame into one canvas -- the flat
-- path every rung has always taken. With `eyes` -- a list of
-- { camera, w, h, slot, adopt } records, plus optional cx/cy for the
-- scene centre -- the same frame is drawn once per entry and the list of
-- canvases comes back: the VR path, two eyes over one shared shadow map,
-- pose capture and glint step.
function VoxelScene.render(state, w, h, vw, vh, paletteFor, eyes)
  -- With nothing cached at all (the first frame of a fresh toggle),
  -- return nil: the engine keeps the 2D path for the frame and
  -- Voxel.ready holds the camera tween at flat, so the switch waits
  -- invisibly instead of freezing or tilting an empty stage.
  local terrain, nbMesh, water, nbWater = VoxelScene.prefetch(state)
  if not terrain then return nil end

  local cam = state.camera
  local cx, cy = cam.x + vw / 2, cam.y + vh / 2

  -- the hour's light, before anything is cast or drawn: point the shared
  -- rig at the clock (or at noon, indoors -- a cave at midnight is exactly
  -- as dark as a cave at noon) and set the tint the scene shader multiplies
  -- every surface by. A CANOPY map (Viridian Forest) is the case between:
  -- the rig stays at noon and no sky is painted, but the hour's tint still
  -- falls through the leaves -- night reaches a forest floor.
  local outdoor = state.map.def and Map.isOutdoor(state.map.def) or false
  DayNight.applyRig(outdoor)
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(state.map))
  -- and the window glass: the tileset's own panes (found in its art --
  -- GlassMask), lit after dark. Outdoors only, like everything the clock
  -- touches, which also keeps any pane-shaped art in an interior tileset
  -- from picking up a glint.
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(state.map.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  local g = VoxelScene.glintStep(glint, cx, cy)
  Voxel3D.glassPhase, Voxel3D.glassGlint = g.phase, g.amp

  local function atlasFor(map)
    return TerrainAtlas.forMap(map, modeColors(paletteFor, map))
  end

  -- sprite palettes only exist in the SGB modes; under RED++ the OBP bake
  -- inside sprite:resolveImage() already colors the sheet
  local function spriteColors(map)
    if PaletteFX.usesGbcPack() then return nil end
    return modeColors(paletteFor, map)
  end

  local posed, me = posesOf(state, spriteColors)

  -- The first-person rig, built (or blended) for this frame and handed to
  -- Voxel3D BEFORE either pass runs: the sun's box is fitted around this
  -- camera, and every card matrix asks it which way to turn. With the
  -- blend fully out the call clears the placed camera and the orbit is
  -- exactly what it always was. The scene centre it returns walks from
  -- the orbit's view centre into the head, so the curve's focus and the
  -- depth reference follow the camera actually in charge.
  --
  -- A VR frame skips all of it: the caller brought its own cameras, and
  -- its own idea of the scene centre with them.
  if not eyes then
    local fpRig, fpCx, fpCy = FirstPerson.frame(me, cx, cy, vw, vh)
    if fpRig then cx, cy = fpCx, fpCy end
  elseif eyes.cx then
    cx, cy = eyes.cx, eyes.cy
  end

  -- A staged fight, seen by the VR eyes: the flat screen draws the battle
  -- SCREEN while one is up (this pass never runs), but the headset keeps
  -- looking at the world, so the world had better have the fight on it.
  -- Fetched per frame for the sun, and again per EYE in drawScene, because
  -- the cards yaw toward whichever eye is asking.
  local battleCards, battleTex, battleToken = nil, nil, nil
  if eyes then
    local okB, cards, tex, token = pcall(function()
      return V.require("OverworldBattle").worldCards()
    end)
    if okB and cards then
      battleCards, battleTex, battleToken = cards, tex, token
    end
  end

  -- The sun's box, pushed along the first-person look so it covers the
  -- ground THIS camera sees (a no-op at blend zero): the orbit's fit
  -- reaches far north and barely south, which is right for every rung
  -- but a head free to face south.
  local shCx, shCy = FirstPerson.shadowCenter(cx, cy, vh)
  castShadows(state, terrain, nbMesh, posed, shCx, shCy, vw, vh, atlasFor,
              water, nbWater, battleCards, battleToken)

  -- Everything between beginScene and endScene, as one function: the flat
  -- path runs it once, a VR frame runs it once PER EYE -- same posed
  -- list, same shadow map, same glint, so the two eyes can never disagree
  -- about anything but their viewpoint.
  local function drawScene()

  Voxel3D.draw(terrain, atlasFor(state.map), nil)
  for i, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(nbMesh[i], atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy))
  end

  -- Without a shadow map (headless, or a driver that could not make the
  -- canvas) the old flat decals stand in: ground-only, characters only,
  -- but better than a world with nothing under anybody. They go down
  -- first, as decals the characters then stand over -- depth-tested
  -- against the terrain just drawn (a shadow behind a building stays
  -- hidden) but never depth-writing, so the grass pass at the end of the
  -- frame still wins its feet-overdraw fights.
  if not Voxel3D.shadowsActive() then
    Voxel3D.beginShadows()
    for _, p in ipairs(posed) do
      drawShadow(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,
                 p.lift)
    end
    Voxel3D.endShadows()
  end

  -- and the water over the top of it, reflecting everything just drawn plus
  -- the sky the frame opened with (see drawWater).
  --
  -- After the fallback decals deliberately: those are the stand-in drop
  -- shadows for a frame with no shadow map, they write no depth, and a
  -- lake would otherwise wear one as a black smear. Water covers them,
  -- which is the same answer the shadow map's own pass gives (see
  -- ShadowMap.sprites) -- people do not shadow water either way.
  local waterDraws = {}
  if water then
    waterDraws[#waterDraws + 1] = { water, atlasFor(state.map), nil }
  end
  for i, nb in ipairs(state.neighbors or {}) do
    if nbWater and nbWater[i] then
      waterDraws[#waterDraws + 1] = { nbWater[i], atlasFor(nb.map),
                                      Mat4.translate(nb.ox, 0, nb.oy) }
    end
  end
  -- the cast goes into the reflection copy only -- see drawWater for why it
  -- cannot be composited yet and why it is drawn through the same function
  -- the real pass below uses
  if #waterDraws > 0 then
    VoxelScene.drawWater(waterDraws, function()
      drawCast(state, posed, atlasFor)
    end)
  end


  -- Sprite sheets from here to the figure pass: their texture coordinates
  -- mean nothing to the tileset-shaped glass mask, so the glass is off or
  -- the panes' atlas positions stripe the cast with lamplight at night
  Voxel3D.glass(false)

  -- The player's silhouette goes down BEFORE the characters, so the only
  -- thing it can meet in the depth buffer is the WORLD -- terrain, buildings,
  -- trees. Drawn after the solid pass it would meet the player's own card
  -- instead, and every fragment of a figure sits behind the one that just
  -- wrote it, so the silhouette would paint over the player at all times.
  -- Every character then draws on top as usual, which leaves the silhouette
  -- showing in exactly one situation: where the world hides them.
  --
  -- Not in first person: the card it silhouettes is the one the camera is
  -- standing inside, and "the world is in front of the player" is every
  -- wall the player faces.
  if me and not FirstPerson.hidePlayer() then
    Voxel3D.beginGhost()
    drawGhost(me)
    Voxel3D.endGhost()
  end

  -- Characters carry no wireframe out here, whatever the V-GRID row says.
  -- The seams are what makes the WORLD read as built out of voxels, and
  -- the people walking around in it are the one thing that should read as
  -- drawn instead -- a grid over a 16x16 sprite lands a line every couple
  -- of display pixels and turns a face into a mesh. (The battle pass makes
  -- the opposite call for its own combatants, deliberately: that is a
  -- staged shot rather than the world being walked around in -- see
  -- BattleBillboard.)
  --
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  drawCast(state, posed, atlasFor)
  -- The staged fight's mons, standing on their arena cells in THIS eye's
  -- view (VR frames only; battleTex is nil otherwise). Rebuilt per eye
  -- because the cards yaw toward the eye that is looking. No wireframe
  -- and no glass on them for the reasons BattleBillboard and the battle
  -- pass each argue: the cards are not on the voxel grid, and their
  -- texcoords mean nothing to the tileset's pane mask. The hit flash
  -- rides the same flatten the battle pass uses, held short of solid.
  if battleTex then
    local okB, cards = pcall(function()
      return V.require("OverworldBattle").worldCards()
    end)
    if okB and cards then
      local BattleScene = V.require("BattleScene")
      Voxel3D.glass(false)
      Voxel3D.seams(false)
      if battleTex.flash then
        Voxel3D.flatten(BattleScene.FLASH_COLOR, BattleScene.FLASH_STRENGTH)
      end
      for _, card in ipairs(cards) do
        Voxel3D.draw(BattleBillboard.mesh(), card.tex, card.model,
                     BattleBillboard.PULL)
      end
      if battleTex.flash then Voxel3D.flatten(nil) end
      -- and the MOVE ANIMATIONS, standing on the same arena: the
      -- engine's own effects layer on the plane through both cells
      -- (BattleScene.fxCard), pulled a little harder than the mons so
      -- a burst plays over the card it is bursting on
      local okA, fxTex, fxModel = pcall(function()
        return V.require("OverworldBattle").worldAnim()
      end)
      if okA and fxTex and fxModel then
        Voxel3D.draw(BattleBillboard.mesh(), fxTex, fxModel,
                     BattleBillboard.PULL + 6)
      end
      Voxel3D.seams(true)
      Voxel3D.glass(true)
    end
  end
  -- tall grass last, pulled camera-ward exactly as far as the characters
  -- were (same per-vertex shader bias, so grass never drifts either):
  -- relative depth between a walker and the tuft row south of their feet
  -- is preserved, so the row still overdraws feet -- the 3D version of
  -- the GB's grass-over-feet trick -- while grass keeps losing to the
  -- buildings it genuinely stands behind (far deeper than the pull).
  -- the same angle the cards leaned by (leanAngle honours VR's override),
  -- so the tuft rows keep exactly the characters' own depth handicap
  local lean = math.max(leanAngle(), 0.05)
  local pull = VoxelScene.pull(lean)
  Voxel3D.draw(ChunkMesher.grass(state.map), atlasFor(state.map), nil, pull)
  for _, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(ChunkMesher.grass(nb.map), atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy), pull)
  end
  -- flower billboards: pulled like the characters and the grass, MINUS
  -- the depth of 8 world pixels along the view (8 sin a -- the camera
  -- looks along (0, -cos a, -sin a), so that is exactly one tile row of
  -- northness). A pure depth handicap with zero screen drift: every
  -- flower is judged as if it stood one tile row further north. The
  -- character card's feet plane sits at its cell's MIDDLE (py + 8), so
  -- a flower on the walker's own cell (z +4 or +12 across the cell)
  -- lands behind the card and the player obscures the patch they stand
  -- ON, while the nearest flower of the cell south (+20) stays in front
  -- and keeps overdrawing their feet.
  local fpull = math.max(0, pull - 8 * math.sin(lean))
  -- flowers are snugged casters too, so they read their own shadowing
  -- through the same snugged transform the sun stored them with
  Voxel3D.draw(ChunkMesher.flowers(state.map), atlasFor(state.map), nil,
               fpull, ShadowMap.snug(nil))
  for _, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy), fpull,
                 ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end

  -- The VR pokedex in the player's left hand, last of all: a prop over
  -- the world drawn with real depth, so leaning it into a wall still
  -- occludes honestly. Its frame only exists while a session is live and
  -- the left hand is tracked (VR.lua sets it), so every flat frame skips
  -- this in one field read. No wireframe and no glass, like the cast:
  -- the device is a drawing riding the scene, not part of the terrain.
  if Pokedex.frame then
    Voxel3D.glass(false)
    Voxel3D.seams(false)
    Pokedex.draw()
    Voxel3D.seams(true)
    Voxel3D.glass(true)
  end

  -- HORDE MODE's handgun, in the same slot and for the same reasons: a
  -- prop over the world with real depth, no wireframe and no glass. In VR
  -- it rides the tracked right hand (lib/VR placed it this frame); on the
  -- flat screen it is carried by the camera, which is why it draws here
  -- rather than in the overlay -- a view model that is 2D cannot be
  -- occluded by the wall the player just backed into.
  do
    local HordeGun = V.require("HordeGun")
    if HordeGun.visible() then
      Voxel3D.glass(false)
      Voxel3D.seams(false)
      HordeGun.draw()
      Voxel3D.seams(true)
      Voxel3D.glass(true)
    end
  end

  end   -- drawScene

  if not eyes then
    if not Voxel3D.beginScene(w, h, cx, cy, vw, vh, skyFor(state.map)) then
      return nil
    end
    drawScene()
    return Voxel3D.endScene()
  end

  -- The VR frame: the same scene once per eye, each into its own named
  -- canvas slot under its own placed camera. `adopt` hands the eye's
  -- record to FirstPerson as the live rig, which is what turns the
  -- billboards toward THIS eye in first person (cardBlend keys on rig
  -- identity -- see FirstPerson) and leaves them leaning in the diorama,
  -- where the blend is zero.
  local out = {}
  for i, eye in ipairs(eyes) do
    Voxel3D.camera = eye.camera
    if eye.adopt then FirstPerson.adoptVReye(eye.camera) end
    if not Voxel3D.beginScene(eye.w, eye.h, cx, cy, vw, vh,
                              skyFor(state.map), eye.slot) then
      return nil
    end
    drawScene()
    out[i] = Voxel3D.endScene()
  end
  return out
end

return VoxelScene
