-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BATTLE SCREEN EMERALD DRAWS.
--
-- The simulation, the timing, the animations and every rule stay
-- BattleState's.  This module replaces the COMPOSITION only -- what size the
-- surface is, where the two sides stand, and what the boxes along the bottom
-- say -- exactly the way WideBattle does for the widescreen option.  Pictures,
-- font pages, border glyphs and HP tiles all still resolve through the engine,
-- so a display mode or an asset mod keeps owning the look.
--
-- WHAT WAS WRONG.  Hoenn was fighting on the Game Boy's screen: a 160x144
-- surface letterboxed inside a 240x160 window, with Gen 1's four-word menu on
-- it --
--
--     FIGHT   <PK><MN>              FIGHT     BAG
--     ITEM    RUN         against   POKeMON   RUN
--
-- -- which is not a wording difference.  Two of the four words are wrong, and
-- the two that survive have swapped diagonals: the cell that says PACK in
-- Emerald is the one that opened the party in this port, and the other way
-- round.  A player who has learned where BAG is presses it and gets the party.
--
-- THE MENU IS NOT WRITTEN HERE.  constants.gen3BattleMenu is one string off
-- the cartridge -- "FIGHT{CLEAR_TO 56}BAG\nPOKeMON{CLEAR_TO 56}RUN" -- so the
-- four words, the fact that there are two columns and the 56 pixels between
-- them are all the cartridge's own.  A dataset without the record falls back
-- to the Game Boy's words rather than refusing to draw a menu.
--
-- WHAT IS RECONSTRUCTED, and should be corrected against a recording rather
-- than argued about: where the two sides stand on the wider field, and where
-- the window edges fall.  Those are staging, and they are marked below.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
local Theme = require("src.ui.Theme")
local Font = require("src.render.Font")
local HudTiles = require("src.render.HudTiles")
local PaletteFX = require("src.render.PaletteFX")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")
local TypeChart = require("src.battle.TypeChart")
local GameVersion = require("src.core.GameVersion")

local Gen3Battle = {
  WIDTH = 240,
  HEIGHT = 160,
  -- everything above this line is battlefield; the five tile rows below it
  -- are the message / command / move windows
  FIELD_BOTTOM = 120,
  -- the bottom strip, in tiles
  STRIP_TOP = 15,
  STRIP_ROWS = 5,
}

-- the two text rows inside the bottom strip
local ROW1 = (Gen3Battle.STRIP_TOP + 1) * 8      -- 128
local ROW2 = ROW1 + 16                            -- 144

-- ---------------------------------------------------------------------------
-- BATTLE LAYOUT = WIDE, ON A HOENN CARTRIDGE
--
-- Reported from play: "with the wide mode selection in options for battle, its
-- not filling the screen like it does in my dramatic shapes voxel mod please
-- make it do so".  The frame that came with it is a flat Emerald battle 1440
-- pixels wide in a 1920-pixel window with a pale band 240 pixels wide down
-- each side -- the letterbox Renderer puts around a 240x160 UI surface, and
-- exactly what the option was doing about it: NOTHING.  BattleState
-- :isWideBattleLayout answers false on Gen 3 and says why (an earlier attempt
-- took Emerald's screen away and put the Game Boy's composition up in its
-- place, stretched to 304x144), so the switch had no effect at all on Hoenn.
--
-- That verdict stands.  What the option buys HERE is not WideBattle's
-- composition, it is Emerald's own -- made as wide as the window can show it.
--
-- THE HEIGHT DOES NOT MOVE.  160 is the cartridge's row count and every piece
-- of art on this screen is authored against it: the healthbox blobs, the
-- 48-row bottom panel, the battle backgrounds, the four-row window templates.
-- Only the WIDTH is a free variable, and it is DERIVED from the window rather
-- than chosen:
--
--   BATTLE SIZE = FIXED (the default) blits at a whole-number scale, and the
--     scale the window allows is S = floor(windowHeight / 160).  So the width
--     that covers the window is the widest whole number of 8-pixel tiles that
--     still fits S whole pixels each: W = floor8(windowWidth / S).  At
--     1920x1080 that is S = 6 and W = 320, and 320 x 6 = 1920 EXACTLY -- the
--     side bands are gone, with the pixels still square and whole.
--
--   BATTLE SIZE = FILL blits at a fractional scale, so the width that covers
--     the window is simply the window's own shape: W = round8(160 * aspect).
--     At 1920x1200 that is 256, and 256:160 IS 16:10 -- no bands on either
--     axis at all.
--
-- Clamped to [240, Renderer.MAX_UI_WIDTH] at both ends.  A window NARROWER
-- than the GBA's own 3:2 -- a 5:4 monitor, a portrait phone -- has nothing to
-- fill across and gets the cartridge's own 240 back, so the option is inert
-- there rather than cropping the screen it was asked to widen.
--
-- A MULTIPLE OF 8, because every window on this screen is placed in TILES:
-- Font.drawBox and the cartridge's own window templates count in them, and
-- Gen3Battle.zones publishes the SGB remap region in them.  A width that is
-- not a whole number of tiles leaves that region short of the surface it is
-- meant to cover, and the forced-mono display modes then show a strip of
-- un-remapped columns down one side -- which is the reason WideBattle.zones
-- exists at all.
-- ---------------------------------------------------------------------------

-- DERIVED: the surface width for a window of pw x ph framebuffer pixels.
-- Pure arithmetic and no state, so the derivation above is checkable without
-- a window to look at.
function Gen3Battle.surfaceWidth(pw, ph, fill, maxWidth)
  local least = Gen3Battle.WIDTH
  local most = math.floor(tonumber(maxWidth) or 640)
  if most < least then most = least end
  pw, ph = tonumber(pw), tonumber(ph)
  if not (pw and ph and pw > 0 and ph > 0) then return least end
  local want
  if fill then
    -- the window's own proportions, to the nearest whole tile
    want = math.floor(Gen3Battle.HEIGHT * pw / ph / 8 + 0.5) * 8
  else
    -- whole pixels: S of them per surface pixel, and floor8 so the last tile
    -- is still inside the window rather than half off the edge of it
    local s = math.max(1, math.floor(ph / Gen3Battle.HEIGHT))
    want = math.floor(pw / s / 8) * 8
  end
  if want < least then return least end
  if want > most then return most end
  return want
end

-- The width of the surface THIS battle is drawing into: the cartridge's own
-- 240 unless the state answers wider, which only a Gen 3 battle with BATTLE
-- LAYOUT = WIDE ever does (BattleState:gen3SurfaceWidth).
--
-- Every widening below is gated on `extra` being non-zero, so a Hoenn battle
-- on the OG layout runs the arithmetic it has always run, from the same
-- constants, and puts the same picture on the screen.
function Gen3Battle.width(battle)
  local fn = battle and battle.gen3SurfaceWidth
  if type(fn) ~= "function" then return Gen3Battle.WIDTH end
  local ok, w = pcall(fn, battle)
  if not (ok and type(w) == "number" and w > Gen3Battle.WIDTH) then
    return Gen3Battle.WIDTH
  end
  return math.floor(w / 8) * 8
end

-- How much wider than the cartridge's screen this surface is.  0 on OG, and
-- always a whole number of tiles.
function Gen3Battle.extra(battle)
  return Gen3Battle.width(battle) - Gen3Battle.WIDTH
end

-- WHERE THE BATTLEFIELD SITS IN A WIDER SURFACE.
--
-- The field is not spread apart.  The two platforms are painted INTO the
-- cartridge's own battle background, the two Pokemon stand on them (measured,
-- not stated -- see measurePlatforms), and pulling the pair apart means
-- cutting that picture between them.  So the field keeps its own 240 pixels,
-- centred, and the space either side is filled by repeating the background's
-- own edge column (Gen3Battle.drawField).  That is exact rather than a
-- stretch, because a Gen 3 battle background IS horizontal bands and every
-- one of them already runs to the picture's edge -- the same property the
-- platform measurement is built on.
--
-- What DOES go to the surface's edges is the furniture: the foe's healthbox
-- stays the cartridge's distance from the left edge, the player's the
-- cartridge's distance from the right, and the bottom strip spans the lot.
function Gen3Battle.fieldOffset(battle)
  return math.floor(Gen3Battle.extra(battle) / 2)
end

-- A WINDOW RECORD THAT SPANS THE SURFACE, and one that RIDES ITS RIGHT EDGE.
--
-- sStandardBattleWindowTemplates states four windows on a 240-wide screen and
-- in doing so states which edge each one belongs to: the prompt runs from
-- tile 0 to 16, the command menu from 16 to 30 -- hard against the right edge
-- -- the message box is inset exactly one tile at each end, and the four move
-- slots sit against the left.  So widening the surface moves each window by
-- what its OWN edge moved: the prompt and the move slots by nothing, the
-- command menu and the move-detail box by the whole of the extra width, and
-- the message box grows into it.
--
-- The text inside a spanned box stays at the cartridge's own textX, which is
-- what was asked for: "leave the text where it is ... words stay at the left
-- of a wider box".
--
-- Copies rather than mutates: STRIP_FALLBACK is a shared module table and the
-- window records come out of the dataset.
local function spanBox(rec, battle)
  local tiles = Gen3Battle.extra(battle) / 8
  if tiles == 0 or type(rec) ~= "table" then return rec end
  local out = {}
  for k, v in pairs(rec) do out[k] = v end
  out.tw = (rec.tw or 0) + tiles
  out.cols = (rec.cols or 0) + tiles
  return out
end

local function shiftBox(rec, battle)
  local d = Gen3Battle.extra(battle)
  if d == 0 or type(rec) ~= "table" then return rec end
  local out = {}
  for k, v in pairs(rec) do out[k] = v end
  out.tx = (rec.tx or 0) + d / 8
  out.textX = (rec.textX or 0) + d
  return out
end

-- the per-path slice measurement and the quads cut from it, both cleared by
-- invalidatePlacement when Assets reloads
local stripCache = {}
local stripQuads = {}
local bandQuads = setmetatable({}, { __mode = "k" })
local moveBgIndexShaderCache = nil

local function moveBgIndexShader()
  if moveBgIndexShaderCache ~= nil then return moveBgIndexShaderCache or nil end
  if not (love.graphics and love.graphics.newShader) then
    moveBgIndexShaderCache = false
    return nil
  end
  local uniforms, choices = {}, {}
  for i = 0, 15 do uniforms[#uniforms + 1] = ("extern vec3 c%d;"):format(i) end
  for i = 0, 15 do
    choices[#choices + 1] = ((i == 0) and "if" or "else if")
      .. (" (idx < %.1f) rgb = c%d;"):format(i + 0.5, i)
  end
  local src = table.concat(uniforms, "\n") .. [[
    vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen) {
      vec4 px = Texel(tex, uv);
      number idx = floor(px.r * 15.0 + 0.5);
      vec3 rgb = c0;
  ]] .. table.concat(choices, "\n") .. [[
      return vec4(rgb, px.a) * colour;
    }
  ]]
  local ok, shader = pcall(love.graphics.newShader, src)
  moveBgIndexShaderCache = ok and shader or false
  return ok and shader or nil
end

local function drawIndexedMoveBg(g, battle, layer)
  if not (layer and layer.indexed and layer.indexImage and layer.palette) then
    return false
  end
  local okImage, image = pcall(Assets.image, layer.indexImage)
  local shader = moveBgIndexShader()
  if not (okImage and image and shader) then return false end
  for i = 0, 15 do
    local c = layer.palette[i + 1] or { 0, 0, 0 }
    shader:send("c" .. i, { c[1] or 0, c[2] or 0, c[3] or 0 })
  end
  local oldShader = g.getShader and g.getShader() or nil
  local sx, sy, sw, sh
  if g.getScissor then sx, sy, sw, sh = g.getScissor() end
  local ox = Gen3Battle.fieldOffset(battle)
  local w, h = tonumber(layer.width) or 256, tonumber(layer.height) or 256
  local scrollX = (tonumber(layer.scrollX) or 0) % w
  local scrollY = (tonumber(layer.scrollY) or 0) % h
  if g.setScissor then g.setScissor(ox, 0, Gen3Battle.WIDTH, Gen3Battle.HEIGHT) end
  g.setShader(shader)
  local b = tonumber(layer.brightness) or 1
  g.setColor(b, b, b, 1)
  for x = ox - scrollX - w, ox + Gen3Battle.WIDTH, w do
    for y = -scrollY - h, Gen3Battle.HEIGHT, h do g.draw(image, x, y) end
  end
  g.setColor(1, 1, 1, 1)
  g.setShader(oldShader)
  if g.setScissor then
    if sx then g.setScissor(sx, sy, sw, sh) else g.setScissor() end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- THE BOTTOM STRIP, OFF THE CARTRIDGE'S OWN WINDOW RECORD
--
-- Every number this strip used was reconstructed: a box at tile (0,15), 30
-- wide and 5 tall, with its text at x=8 and its two rows at 128 and 144.  The
-- cartridge says otherwise, and it says it in a record the import already
-- reads -- sWindowTemplate_Message, 26 columns by 4 rows at tile (2,15).  The
-- FIELD text box has been drawn from that record all along (Data folds it
-- into field.theme.textBox); the battle's was the one place still guessing.
--
-- The difference is visible: the reconstruction put the box eight pixels
-- lower and eight wider on each side, and its first line of text eight pixels
-- below where the cartridge puts it.  Two boxes on the same screen, drawn to
-- two different rules.
--
-- The frame sits one tile out from the window on every side, which is how
-- this cartridge draws all of them -- the same arithmetic Data does.
local STRIP_FALLBACK = {
  tx = 0, ty = Gen3Battle.STRIP_TOP, tw = 30, th = Gen3Battle.STRIP_ROWS,
  textX = 8, row1 = ROW1, row2 = ROW2, cols = 28,
}

-- how much of the strip the question takes when the command menu is up; the
-- rest is the menu's own window

-- One window as the screen draws it: the cartridge's template gives the TEXT
-- area, and the frame sits one tile out from it on every side -- the same
-- arithmetic Data does for the field box, and how this cartridge draws all of
-- them.
local function frameOf(win, fallback)
  if type(win) ~= "table" or not (win.width and win.height) then
    return fallback
  end
  local left = math.floor(tonumber(win.left) or 2)
  local top = math.floor(tonumber(win.top) or 15)
  return {
    tx = math.max(0, left - 1), ty = math.max(0, top - 1),
    tw = math.floor(win.width) + 2, th = math.floor(win.height) + 2,
    textX = left * 8, row1 = top * 8, row2 = top * 8 + 16,
    cols = math.floor(win.width),
  }
end

-- EVERY WINDOW THE STRIP HAS, off the cartridge's own array.
--
-- The message box is INSET -- its frame runs tile 1 to 29 -- while the prompt
-- and the command menu together span the full width, edge to edge.  A single
-- reconstructed strip could not say that, so both were drawn to the message
-- box's shape and the menu sat in from the sides.
function Gen3Battle.windows(battle)
  local consts = battle and battle.data and battle.data.constants
  local rec = consts and consts.gen3BattleWindows
  local message = Gen3Battle.strip(battle)
  if type(rec) ~= "table" then
    -- no record: the prompt and the menu split the message box, which is what
    -- this screen did before the array was read
    local split = message.tx + 16
    return {
      message = message,
      prompt = { tx = message.tx, ty = message.ty, tw = 16, th = message.th,
                 textX = message.textX, row1 = message.row1,
                 row2 = message.row2 },
      action = { tx = split, ty = message.ty,
                 tw = message.tx + message.tw - split, th = message.th,
                 textX = (split + 1) * 8, row1 = message.row1,
                 row2 = message.row2 },
      moves = nil,
    }
  end
  local moves
  if type(rec.moves) == "table" and rec.moves[4] then
    moves = {}
    for i = 1, 4 do moves[i] = frameOf(rec.moves[i], nil) end
  end
  -- WHICH EDGE EACH WINDOW BELONGS TO IS IN THE RECORD (see spanBox above).
  -- The message box is inset a tile at each end, so it SPANS; the command
  -- menu's frame ends on tile 30, the screen's own right edge, so it RIDES
  -- that edge; the prompt starts on tile 0 and the four move slots sit
  -- against the left, so neither moves at all.
  local msg = frameOf(rec.message, nil)
  return {
    message = msg and spanBox(msg, battle) or message,
    prompt = frameOf(rec.prompt, message),
    action = shiftBox(frameOf(rec.action, message), battle),
    moves = moves,
  }
end

function Gen3Battle.strip(battle)
  local consts = battle and battle.data and battle.data.constants
  local win = consts and consts.gen3MessageWindow
  if type(win) ~= "table" or not (win.width and win.height) then
    return spanBox(STRIP_FALLBACK, battle)
  end
  local left = math.floor(tonumber(win.left) or 2)
  local top = math.floor(tonumber(win.top) or 15)
  local w = math.floor(tonumber(win.width) or 26)
  local h = math.floor(tonumber(win.height) or 4)
  return spanBox({
    tx = math.max(0, left - 1), ty = math.max(0, top - 1),
    tw = w + 2, th = h + 2,
    textX = left * 8,
    row1 = top * 8,
    row2 = top * 8 + 16,
    cols = w,
  }, battle)
end

-- THE ORDER THE FOUR CELLS SELECT IN.  Gen 1 reads them
-- fight / party / item / run across the grid; Emerald reads
-- fight / bag / party / run, which is the same four actions in a different
-- pair of diagonals.  Everything else about the menu -- the index, the
-- navigation, what each action does -- is BattleState's and untouched.
Gen3Battle.ACTIONS = { "fight", "item", "pkmn", "run" }

-- ---------------------------------------------------------------------------
-- THE GROUND THE FIGHT HAPPENS ON
--
-- Without it a Hoenn battle is fought on a sheet of white paper -- which is
-- what the Game Boy's battle screen IS, and is why Emerald's layout drawn on
-- it reads as being in black and white.  The pale green field and its two
-- platforms are most of the pixels on the screen.
--
-- Ten backgrounds come off the cartridge (extractBattleBackgrounds).  WHICH
-- THE CARTRIDGE ASKS THE GROUND, and now so does this.
--
-- pokeemerald picks the terrain from the METATILE BEHAVIOUR under the player,
-- falling back on the map's own type -- a chain of questions about the cell
-- being stood on, in a fixed order.  What this port used to have was the map
-- type plus "is this a water cell", which could not tell long grass from
-- tall, sand from plain, or a pond from the sea, so a battle in the desert
-- and a battle on a lawn drew the same picture.
--
-- The behaviour byte was already there -- Map:cellBehaviour reads it off the
-- metatile, and the import stage names all 143 of them -- so the chain below
-- is the cartridge's, asked in the cartridge's order, of the cartridge's own
-- named behaviours.  The map type is still what answers indoors, underground
-- and underwater, which is what it answers on the cartridge too.
local BEHAVIOUR_TERRAIN = {
  TALL_GRASS = "GRASS",
  ASHGRASS = "GRASS",
  SHORT_GRASS = "GRASS",
  LONG_GRASS = "LONG_GRASS",
  LONG_GRASS_SOUTH_EDGE = "LONG_GRASS",
  SAND = "SAND",
  DEEP_SAND = "SAND",
  FOOTPRINTS = "SAND",
  MOUNTAIN_TOP = "MOUNTAIN",
  CAVE = "CAVE",
  INDOOR_ENCOUNTER = "BUILDING",
}

-- the water it is standing in, told apart the way the cartridge tells it:
-- the open sea from a pond
local DEEP_WATER = {
  DEEP_WATER = true, OCEAN_WATER = true, SOOTOPOLIS_DEEP_WATER = true,
  INTERIOR_DEEP_WATER = true,
}
local SURFABLE = {
  POND_WATER = true, SHALLOW_WATER = true, PUDDLE = true, SEAWEED = true,
  SEAWEED_NO_SURFACING = true, NO_SURFACING = true, WATERFALL = true,
  REFLECTION_UNDER_BRIDGE = true, WATER_DOOR = true,
  WATER_SOUTH_ARROW_WARP = true,
}
for name in pairs(DEEP_WATER) do SURFABLE[name] = true end

local TERRAIN_BY_MAP_TYPE = {
  INDOOR = "BUILDING",
  SECRET_BASE = "BUILDING",
  UNDERWATER = "UNDERWATER",
}

-- FireRed's metatile helpers are not the Emerald set above.  In particular,
-- SHALLOW_WATER is sand for battle-terrain purposes, cycling-road pull-down
-- grass is tall grass, and long-grass/bridge predicates are hard false in
-- pokefirered.  Keep the exact FireRed surfable table separate so Camouflage
-- and the battle background ask the same cartridge question.
local FR_SURFABLE = {
  POND_WATER = true, FAST_WATER = true, DEEP_WATER = true,
  WATERFALL = true, OCEAN_WATER = true, UNUSED_WATER = true,
  CYCLING_ROAD_WATER = true, EASTWARD_CURRENT = true,
  WESTWARD_CURRENT = true, NORTHWARD_CURRENT = true,
  SOUTHWARD_CURRENT = true,
}
local FR_DEEP_WATER = {
  FAST_WATER = true, DEEP_WATER = true, OCEAN_WATER = true,
}

-- the name the import stage gave the behaviour under the player, or nil
function Gen3Battle.behaviourUnder(game)
  local ow = game and game.overworld
  local map = ow and ow.map
  if not (map and map.cellBehaviour) then return nil end
  local player = ow.player
  local cx = player and (player.cellX or player.x)
  local cy = player and (player.cellY or player.y)
  if not (cx and cy) then return nil end
  local ok, byte = pcall(map.cellBehaviour, map, cx, cy)
  if not (ok and byte) then return nil end
  local names = game.data and game.data.constants
                and game.data.constants.gen3Behaviours
  return names and names[byte] or nil
end

function Gen3Battle.terrainFor(game)
  local ow = game and game.overworld
  local map = ow and ow.map
  local def = map and map.def
  if not def then return "PLAIN" end

  local player = ow.player
  local cx = player and (player.cellX or player.x)
  local cy = player and (player.cellY or player.y)
  local behaviour = Gen3Battle.behaviourUnder(game)

  if GameVersion.get() == "firered" then
    -- BattleSetup_GetTerrainId, in source order.
    if behaviour == "TALL_GRASS"
       or behaviour == "CYCLING_ROAD_PULL_DOWN_GRASS" then
      return "GRASS"
    end
    -- MetatileBehavior_IsLongGrass is literally FALSE in FireRed.
    if behaviour == "SAND" or behaviour == "SHALLOW_WATER" then
      return "SAND"
    end

    local mapType = def.mapType
    if mapType == "UNDERGROUND" then
      if behaviour == "INDOOR_ENCOUNTER" then return "BUILDING" end
      if behaviour and FR_SURFABLE[behaviour] then return "POND" end
      return "CAVE"
    elseif mapType == "INDOOR" or mapType == "SECRET_BASE" then
      return "BUILDING"
    elseif mapType == "UNDERWATER" then
      return "UNDERWATER"
    elseif mapType == "OCEAN_ROUTE" then
      if behaviour and FR_SURFABLE[behaviour] then return "WATER" end
      return "PLAIN"
    end

    if behaviour and FR_DEEP_WATER[behaviour] then return "WATER" end
    if behaviour and FR_SURFABLE[behaviour] then return "POND" end
    if behaviour == "MOUNTAIN_TOP" then return "MOUNTAIN" end
    -- FireRed's bridge predicates are also hard FALSE, so the surfing bridge
    -- arm cannot change this answer.
    return "PLAIN"
  end

  local function onWater()
    if player and player.surfing then return true end
    if behaviour and SURFABLE[behaviour] then return true end
    if not (map.isWaterCell and cx and cy) then return false end
    local ok, wet = pcall(map.isWaterCell, map, cx, cy)
    return ok and wet or false
  end

  -- FIRST the three the cartridge asks about before it looks at the map at
  -- all: grass, long grass and sand are what you are standing on wherever
  -- you are standing on them.
  if behaviour then
    local ground = BEHAVIOUR_TERRAIN[behaviour]
    if ground == "GRASS" or ground == "LONG_GRASS" or ground == "SAND" then
      return ground
    end
  end

  local byType = TERRAIN_BY_MAP_TYPE[def.mapType]
  if byType then return byType end

  -- a cave, and the sea inside one is a pond rather than the ocean
  if def.mapType == "UNDERGROUND" or def.cave then
    if behaviour == "INDOOR_ENCOUNTER" then return "BUILDING" end
    if onWater() then return "POND" end
    return "CAVE"
  end

  -- ...then the water, and the open sea is not a pond
  if behaviour and DEEP_WATER[behaviour] then return "WATER" end
  if onWater() then
    if behaviour and SURFABLE[behaviour] then return "POND" end
    return "WATER"
  end

  -- ...and last the ground the map is made of
  if behaviour then
    local ground = BEHAVIOUR_TERRAIN[behaviour]
    if ground then return ground end
  end
  if map.isGrassCell and cx and cy then
    local ok, grass = pcall(map.isGrassCell, map, cx, cy)
    if ok and grass then return "GRASS" end
  end
  return "PLAIN"
end

-- THE MAP'S OWN ROOM, WHEN IT HAS ONE.
--
-- terrainFor answers "what am I standing on", which is the right question in
-- long grass and the wrong one in a gym: sixty-five maps in Hoenn carry a
-- BATTLE SCENE byte in their header saying the fight happens somewhere the
-- ground does not describe -- a gym floor, a hideout, one of the four Elite
-- Four rooms, the Battle Frontier -- and the cartridge checks that byte first
-- and only falls through to the terrain when it is zero.  Every gym leader in
-- the region was being fought standing in grass because nothing asked.
--
-- Returns the scene's own name, or nil for MAP_BATTLE_SCENE_NORMAL and for a
-- cache imported before the stage existed.
function Gen3Battle.sceneFor(game)
  local ow = game and game.overworld
  local def = ow and ow.map and ow.map.def
  local index = def and tonumber(def.battleScene)
  if not index or index == 0 then return nil end
  local constants = game and game.data and game.data.constants
  local record = constants and constants.gen3BattleScenes
  local order = type(record) == "table" and record.order
  local name = order and order[index + 1]
  if name and type(record.images) == "table" and record.images[name] then
    return name
  end
  return nil
end

-- The picture for that terrain, or nil on a cache imported before the stage
-- existed -- in which case the field is painted flat, exactly as it was.
function Gen3Battle.backdrop(battle)
  local constants = battle and battle.data and battle.data.constants
  local scenes = constants and constants.gen3BattleScenes
  local scene = battle and battle.gen3Scene
  if scene == nil then
    scene = Gen3Battle.sceneFor(battle and battle.game) or false
    if battle then battle.gen3Scene = scene end
  end
  if scene and type(scenes) == "table" and type(scenes.images) == "table" then
    local path = scenes.images[scene]
    if path then
      local ok, image = pcall(Assets.image, path)
      if ok and image then return image end
    end
  end

  local record = constants and constants.gen3BattleTerrain
  if type(record) ~= "table" or type(record.images) ~= "table" then return nil end
  local terrain = battle.gen3Terrain
  if not terrain then
    terrain = Gen3Battle.terrainFor(battle.game)
    battle.gen3Terrain = terrain
  end
  local path = record.images[terrain] or record.images.PLAIN
  if not path then return nil end
  local ok, image = pcall(Assets.image, path)
  return ok and image or nil
end

-- the same question the overworld asks, answered in one place
local function monoMode()
  return PaletteFX.monoMode()
end

local function shownHP(battler)
  return math.max(0, math.floor(battler.shownHP or battler.mon.hp or 0))
end

-- a name truncated to `pixels` with a trailing '.', measured through the
-- font's own advances so the cartridge's variable-width page measures right.
-- Lives on Font now: the party screen needs exactly the same cut, and two
-- copies of it would drift.
local function fitName(text, pixels) return Font.fit(text, pixels) end

local function saveScissor()
  if not love.graphics.getScissor then return nil end
  local x, y, w, h = love.graphics.getScissor()
  if x == nil then return false end
  return { x, y, w, h }
end

local function restoreScissor(saved)
  if not love.graphics.setScissor then return end
  if saved and saved ~= false then
    love.graphics.setScissor(saved[1], saved[2], saved[3], saved[4])
  else
    love.graphics.setScissor()
  end
end

-- Draw fn's content translated by (dx, dy) and clipped to a surface rect.
-- The scissor is in canvas space, so it bounds the region itself while the
-- translate moves the classic 160x144 coordinates into it.
local function inRegion(x, y, w, h, dx, dy, fn)
  local g = love.graphics
  local saved = saveScissor()
  g.setScissor(x, y, w, h)
  g.push()
  g.translate(dx, dy)
  fn()
  g.pop()
  restoreScissor(saved)
end

-- ---------------------------------------------------------------------------
-- the status panels
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- EMERALD'S OWN STATUS PANEL
--
-- This screen used to draw the Game Boy's: Font.drawBox for the panel and
-- HudTiles for the bar.  Both are Gen 1/Gen 2 art indexed out of a `hud` font
-- page, and a Gen 3 cache HAS no such page.  So the panel came up as the
-- DIALOGUE WINDOW -- square, bordered, the wrong thing entirely -- and the HP
-- bar drew no tiles at all and read as a black slot.  There was no EXP bar,
-- because the Game Boy's is a different shape and Emerald's had never been
-- extracted.
--
-- The geometry below is MEASURED off the extracted panels rather than chosen:
-- both are 100 pixels of opaque box with an 86x19 cream interior, and the
-- player's interior starts eight pixels further right because its tail is on
-- the left.  Everything inside is placed against that interior, so the two
-- panels share one set of numbers.
-- ---------------------------------------------------------------------------

-- the cream interior of each panel, in the panel image's own pixels
local HUD_INTERIOR = {
  player = { x = 12, y = 5, w = 86, h = 19 },
  opponent = { x = 4, y = 5, w = 86, h = 19 },
}
-- the HP bar is six tiles of the ramp, as it is on the cartridge
local HUD_HP_TILES = 6
local HUD_EXP_TILES = 8
local HUD_BAR_H = 8

local function hudRecord(battle)
  local constants = battle and battle.data and battle.data.constants
  local record = constants and constants.gen3BattleHud
  if type(record) ~= "table" then return nil end
  return record
end

local function hudImage(path)
  if type(path) ~= "string" then return nil end
  local ok, image = pcall(Assets.image, path)
  return ok and image or nil
end

-- WHAT THE FRAME NO LONGER ASKS FOR.  Each of these was resolved from inside
-- a function that runs on every battle frame; none of them can be a plain
-- top-level require, because each reaches back into the battle.
local NO_ROWS = {}
local NOOP = function() end

local WeatherMod, FieldWeatherMod
local function weatherMod()
  if WeatherMod == nil then
    local ok, mod = pcall(require, "src.battle.Weather")
    WeatherMod = (ok and mod) or false
  end
  return WeatherMod or nil
end
local function fieldWeatherMod()
  if FieldWeatherMod == nil then
    local ok, mod = pcall(require, "src.world.Gen3Weather")
    FieldWeatherMod = (ok and mod) or false
  end
  return FieldWeatherMod or nil
end

local TimingMod
local function timing()
  TimingMod = TimingMod or require("src.core.Timing")
  return TimingMod
end

local DayCareMod
local function dayCare()
  DayCareMod = DayCareMod or require("src.pokemon.DayCare")
  return DayCareMod
end

-- a colour triple to LOVE's 0..1, hoisted out of the per-healthbox draw
local function normInk(c)
  if type(c) ~= "table" then return nil end
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1 }
end

-- One bar, drawn out of its nine-step ramp: each tile shows as many pixels of
-- fill as are left to it, and the ramp has a frame for every count from none
-- to eight.  That is how the cartridge draws it, and it is why a bar moves in
-- single pixels rather than whole tiles.
-- NINE QUADS, NOT NINE PER TILE PER FRAME.  A ramp has exactly nine steps and
-- a strip has one height, so the quads are a function of (height, step) and
-- nothing else -- built fresh they were twenty to thirty Quad objects on every
-- battle frame, which is ~1900 a second for a picture that never changes.
local rampQuads = setmetatable({}, { __mode = "v" })
local function rampQuad(sh, step)
  local row = rampQuads[sh]
  if not row then row = {} rampQuads[sh] = row end
  local quad = row[step]
  if not quad then
    quad = love.graphics.newQuad(step * 8, 0, 8, sh, 72, sh)
    row[step] = quad
  end
  return quad
end

local function drawRamp(strip, x, y, tiles, filled)
  if not strip then return end
  local _, sh = strip:getDimensions()
  for i = 0, tiles - 1 do
    local step = math.max(0, math.min(8, filled - i * 8))
    love.graphics.draw(strip, rampQuad(sh, step), x + i * 8, y)
  end
end

-- The recoloured pill for whatever this battler is carrying, or nil.
--
-- Keyed by the label the status system already produces -- PSN, PAR, SLP,
-- FRZ, BRN -- which is the same seam the text HUD used, so a mod that adds a
-- status with one of those hud labels gets its badge for free and one with a
-- label the cartridge has no art for falls back to the text.
local function statusBadge(record, battle, battler)
  local status = battler and battler.shownStatus
  if not (status and record and record.status) then return nil end
  local ok, key = pcall(battle.statusLabel, battle, { status = status })
  if not (ok and type(key) == "string") then return nil end
  return hudImage(record.status[key])
end

-- WHERE THE INSIDE OF A PANEL IS.  The import measures it off the panel's
-- own pixels; the fallbacks are what this drew before it did, so a cache
-- imported earlier keeps exactly what it had -- including its bug, which is
-- better than a cache-dependent surprise.
local function hudInterior(record, player)
  local geo = record and record.geometry
  local row = geo and geo[player and "player" or "opponent"]
  local inner = row and row.interior
  if inner and inner.w and inner.h then return inner end
  return player and HUD_INTERIOR.player or HUD_INTERIOR.opponent
end

-- ...and where its EXP strip is, for the one panel that has one.
local function hudExpStrip(record)
  local geo = record and record.geometry
  local row = geo and geo.player
  local exp = row and row.exp
  if exp and exp.x and exp.y and exp.w then return exp end
  return nil
end

-- THE GENDER SYMBOL, and the ink the cartridge prints it in.
--
-- Reported from play: "im also not nseeing the symbols for pokemons gender in
-- blue or red in battle next to their names".  There were none at all.  The
-- cartridge appends one to the nickname before it prints the row, and the
-- colour rides in the STRING rather than in the call -- `{COLOR 11}` for a
-- male and `{COLOR 10}` for a female, which swaps the letter's ink and leaves
-- the shadow where it is.  Both indices and both colours come from the
-- import, off those two strings and the healthbox's own palette.
--
-- ...AND A NIDORAN GETS NONE, because its name already ends in one.  The
-- cartridge compares the species against the two and skips the symbol when
-- the nickname has not been changed; a renamed one shows a symbol again.
local function genderSymbol(record, battle, battler)
  local rows = record and record.gender
  local mon = battler and battler.mon
  if not (type(rows) == "table" and mon) then return nil end
  -- GetGenderFromSpeciesAndPersonality, which the day care already asks --
  -- one derivation for the whole engine rather than a second opinion here.
  -- pcall TAKES ARGUMENTS: the closure form allocated one per healthbox per
  -- frame, and did a package.loaded lookup inside it
  local ok, gender = pcall(dayCare().gender, battle.data, mon)
  if not ok or type(gender) ~= "string" then return nil end
  local row = rows[gender]
  if not (type(row) == "table" and type(row.text) == "string") then
    return nil
  end
  -- the two whose own name carries the symbol
  local order = battle.data and battle.data.constants
                and battle.data.constants.speciesOrder
  for _, id in ipairs(rows.namedSpecies or NO_ROWS) do
    if order and order[id] == mon.species and not mon.nickname then
      return nil
    end
  end
  local ink = record.text or {}
  return row.text, { text = normInk(row.color), shadow = normInk(ink.shadow) }
end
Gen3Battle.genderSymbol = genderSymbol

local function hpRampFor(record, battler)
  local bars = record and record.bars or {}
  local max = math.max(1, battler.mon.stats.hp or 1)
  local frac = shownHP(battler) / max
  -- GetHPBarLevel's own thresholds
  local key = (frac > 0.5 and "green") or (frac > 0.2 and "yellow") or "red"
  return hudImage(bars[key]), key
end

-- `text` is what the caller already measured, so the string that was sized
-- and the string that is drawn cannot disagree.  Without one this falls back
-- to the Game Boy healthbox's rule -- status text IN PLACE OF the level --
-- which is what the no-cartridge-art path above still draws.
-- The ink the cartridge's own font stage bakes into every glyph page
-- (RomExtractorGen3.FONT_TEXT).  Stated here because the healthbox has to
-- paint its letters rather than blit them -- see the note in drawStatusPanel.
-- KEPT, AND NO LONGER USED BY THIS SCREEN.  The healthbox pushed this and it
-- was the wrong answer: a style paints a pre-tinted page through the tint
-- shader, which flattens the letter and its drop shadow into one ink and
-- makes every name a pixel thicker down and right.  The page already carries
-- both tones.  It stays exported because it is the ink the font stage bakes,
-- and a screen that genuinely has to state it should state the same one.
local HUD_TEXT_STYLE = { text = { 0.16, 0.16, 0.16, 1 } }
Gen3Battle.HUD_TEXT_STYLE = HUD_TEXT_STYLE

local function levelAt(battle, battler, x, y, text)
  if text then
    Font.draw(text, x, y)
  elseif battler.shownStatus then
    Font.draw(battle:statusLabel({ status = battler.shownStatus }), x, y)
  else
    Font.draw("Lv" .. tostring(battler.mon.level), x, y)
  end
end

local function drawStatusPanel(battle, battler, x, y, player)
  local record = hudRecord(battle)
  local images = record and record.images or {}
  local panel = hudImage(player and images.player or images.opponent)

  if not panel then
    -- NO CARTRIDGE PANEL: a cache imported before the stage existed.  The old
    -- boxed drawing is what it had and is what it keeps, rather than nothing.
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local tw, th = player and 15 or 14, player and 5 or 4
    Font.drawBox(tx, ty, tw, th)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(fitName(battler.name, 56), x + 8, y + 8)
    levelAt(battle, battler, x + tw * 8 - 40, y + 8)
    if player then
      Font.draw(("%3d/%3d"):format(shownHP(battler), battler.mon.stats.hp),
                x + tw * 8 - 64, y + 24)
    end
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(panel, x, y)

  -- THE SMALL FACE, which is what the cartridge sets a healthbox in.
  --
  -- The dialogue face is fifteen pixels tall and the panel's cream interior
  -- is NINETEEN: a name row and a bar do not both fit in it, and drawn in the
  -- dialogue face the name filled the box edge to edge and the HP numbers
  -- landed outside it altogether.  Emerald uses FONT_SMALL here, eleven tall,
  -- and eleven plus the bar's eight is exactly nineteen.  The face is already
  -- in the cache -- the font stage rips all five of the cartridge's Latin
  -- faces -- and this is the screen that needed one.
  local faced = Font.pushFace("small")

  -- THE LETTERS ON THIS BOX ARE BLITTED, NOT PAINTED.
  --
  -- Reported twice, and the second report is the answer to the first.  "The
  -- pokemon names and lvl text in battle is white but it shouldnt be" made
  -- this state an ink, which a style does by running the glyph through the
  -- tint shader.  Then: "their names are looking a little too bold not
  -- matching the rom" -- because that shader takes the glyph's ALPHA and
  -- paints every opaque pixel one colour, so a page whose glyph is a dark
  -- letter with a LIGHT drop shadow came back as letter and shadow in one
  -- ink.  That is a letter a pixel thicker down and right.
  --
  -- A Gen 3 font page is PRE-TINTED: it already carries the two tones the
  -- cartridge prints in, and Font blits it as it is whenever nothing is
  -- painting it.  The white was never the page -- it was a style left in
  -- force by another screen -- so what this box needs is not an ink of its
  -- own but the guarantee that no ink is set at all.
  -- ...AND NOTHING IS TO PAINT THEM.
  --
  -- Reported from play: "their names are looking a little too bold not
  -- matching the rom".  They were.  A style turns the tint shader on, and
  -- that shader takes the glyph's ALPHA and paints every opaque pixel one
  -- colour -- so a page whose glyph is a dark letter with a LIGHT drop
  -- shadow came out as letter and shadow in the same dark ink, which is a
  -- letter one pixel thicker down and right.  Bold, exactly as reported.
  --
  -- The page already carries the two tones the cartridge prints in.  Pushing
  -- NO style is what lets them through: Font's pre-tinted path blits the
  -- page as it is, which is the whole reason it bakes two tones.
  Font.pushStyle(nil)

  -- WHERE THE INSIDE OF THIS PANEL IS, measured by the import off the
  -- panel's own pixels rather than assumed to be the same on both.  It is
  -- not: the foe's cream box is nineteen tall and the player's is
  -- TWENTY-SEVEN, because the player's is the tall box and has a third row
  -- for the current-and-max numbers.
  -- THE CARTRIDGE'S OWN WINDOWS, when the import recorded them: every piece
  -- of text goes where UpdateNickInHealthbox / UpdateLvlInHealthbox /
  -- UpdateHpTextInHealthbox copy it, and the bar where SpriteCB_HealthBar
  -- puts its sprite.  See RomExtractorGen3.HUD_WINDOWS.
  local win = record and record.windows
    and record.windows[player and "player" or "opponent"]
  if win and win.name and win.level and win.bar then
    local strip = hpRampFor(record, battler)
    local maxHp = math.max(1, battler.mon.stats.hp or 1)
    local barW = HUD_HP_TILES * 8
    local filled = 0
    if shownHP(battler) > 0 then
      filled = math.max(1, math.floor(shownHP(battler) * barW / maxHp))
    end
    local badge = statusBadge(record, battle, battler)
    local label = hudImage(record.bars and record.bars.label)
    love.graphics.setColor(1, 1, 1, 1)
    if badge then
      love.graphics.draw(badge, x + win.label.x, y + win.label.y)
    elseif label then
      love.graphics.draw(label, x + win.label.x, y + win.label.y)
    end
    drawRamp(strip, x + win.bar.x, y + win.bar.y, HUD_HP_TILES, filled)

    local symbol, symbolInk = genderSymbol(record, battle, battler)
    local symbolW = symbol and Font.width(symbol) or 0
    local shown = fitName(battler.name, win.name.w - symbolW)
    Font.draw(shown, x + win.name.x, y + win.name.y)
    if symbol then
      Font.pushStyle(symbolInk)
      Font.draw(symbol, x + win.name.x + Font.width(shown), y + win.name.y)
      Font.popStyle()
    end
    -- "{LV_2}" then the number left-aligned, shifted right five pixels for
    -- every digit short of three
    local digits = #tostring(battler.mon.level)
    levelAt(battle, battler, x + win.level.x + 5 * (3 - digits),
            y + win.level.y, "Lv" .. tostring(battler.mon.level))

    if player and win.hpCurrent and win.hpMax then
      -- both right-aligned in three digit cells, the current one with its
      -- slash, exactly as ConvertIntToDecimalStringN pads them
      local cell = Font.width("0")
      local cur = tostring(shownHP(battler))
      local max = tostring(battler.mon.stats.hp)
      Font.draw(cur .. "/", x + win.hpCurrent.x + cell * (3 - #cur),
                y + win.hpCurrent.y)
      Font.draw(max, x + win.hpMax.x + cell * (3 - #max), y + win.hpMax.y)
    end
    if player then
      local exp = hudImage(record.bars and record.bars.exp)
      local place = hudExpStrip(record)
      if exp and place then
        local filledExp = 0
        if battle.expFraction then
          local okFill, value = pcall(battle.expFraction, battle)
          filledExp = (okFill and tonumber(value)) or 0
        end
        local top = (record.bars and tonumber(record.bars.expTop)) or 0
        drawRamp(exp, x + place.x, y + place.y - top, math.floor(place.w / 8),
                 math.floor(place.w * math.max(0, math.min(1, filledExp))))
      end
    end
    Font.popStyle()
    if faced then Font.popFace() end
    return
  end

  local inner = hudInterior(record, player)
  local ix, iy = x + inner.x, y + inner.y

  -- THE BAR FIRST, so the name row can sit above it and neither has to guess
  -- where the other ended up.
  local barW = HUD_HP_TILES * 8
  local barX = ix + inner.w - barW - 1
  -- WHERE THE THREE ROWS SIT, AND WHY THEY ARE LIFTED.
  --
  -- Reported from play: "the exp bar, hp bar and the hp number/number need to
  -- go up slightly to fit properly".  They did: the current-and-max numbers
  -- came out through the panel's own bottom border and onto the EXP strip.
  --
  -- The arithmetic says why, and it says it for the player's panel only.  The
  -- small face's cell is ELEVEN rows -- the import measures it, it is not a
  -- constant here -- and the paper it is printed on is measured too: nineteen
  -- on the foe's box and TWENTY-SEVEN on the player's.  The foe's has two
  -- rows, a name and the bar: 11 + 8 is exactly its nineteen and it has never
  -- overflowed.  The player's has three, because it is the box that shows the
  -- numbers: 11 + 8 + 11 is THIRTY, and thirty does not go into twenty-seven.
  --
  -- The three that do not fit come out of the rows above, and they can: a
  -- glyph cell's last rows are descender space, and a Pokemon's name and a
  -- pair of numbers use none of it -- Hoenn prints both in capitals and
  -- digits.  So the bar and everything under it are lifted by exactly the
  -- overflow, which is zero on the foe's panel and needs no case of its own.
  local nameH = Font.glyphHeight()
  local wanted = nameH + HUD_BAR_H + (player and nameH or 0)
  local lift = math.max(0, wanted - inner.h)
  local barY = iy + nameH - lift
  local strip = hpRampFor(record, battler)
  local max = math.max(1, battler.mon.stats.hp or 1)
  local filled = 0
  if shownHP(battler) > 0 then
    filled = math.max(1, math.floor(shownHP(battler) * barW / max))
  end
  drawRamp(strip, barX, barY, HUD_HP_TILES, filled)

  -- THE STATUS BADGE, if this mon is carrying one.
  --
  -- Emerald does not write the status where the LEVEL goes -- that is Gen 1's
  -- healthbox, which has no room for anything else.  Emerald draws a little
  -- recoloured pill (PSN purple, PAR yellow, SLP grey, FRZ blue, BRN orange)
  -- in the strip to the left of the HP bar, and keeps the level where it was.
  -- That strip is where the box's own "HP" mark sits, and it is the mark the
  -- badge replaces -- the cartridge draws one or the other, never both.
  local badge = statusBadge(record, battle, battler)
  if badge then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(badge, barX - badge:getWidth() - 1, barY - 2)
  else
    local label = hudImage(record and record.bars and record.bars.label)
    if label then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(label, barX - 17, barY)
    end
  end

  -- THE NAME AND THE LEVEL, on the row above, and they do not collide: the
  -- name is cut to whatever is left after the level has taken its own width,
  -- measured through the font rather than assumed.  They used to be placed at
  -- two fixed offsets and a long nickname ran straight through "Lv100".
  love.graphics.setColor(1, 1, 1, 1)
  -- the level STAYS.  With the badge drawn beside the bar there is nowhere
  -- the status has to displace it to, and Emerald shows both.
  local level = (not badge) and battler.shownStatus
    and battle:statusLabel({ status = battler.shownStatus })
    or ("Lv" .. tostring(battler.mon.level))
  local levelW = Font.width(level)
  -- THE GENDER SYMBOL, which goes on the end of the name and not in a slot
  -- of its own -- the cartridge appends it to the nickname before it prints.
  local symbol, symbolInk = genderSymbol(record, battle, battler)
  local symbolW = symbol and Font.width(symbol) or 0
  local nameW = inner.w - levelW - symbolW - 6
  local nameY = iy
  local shown = fitName(battler.name, nameW)
  Font.draw(shown, ix + 1, nameY)
  if symbol then
    -- ...AND IT IS THE ONE THING ON THIS BOX THAT IS PAINTED.  The cartridge
    -- prints it with a colour code in the string itself -- `{COLOR 11}` for
    -- a male and `{COLOR 10}` for a female -- which swaps the LETTER's ink
    -- and leaves the shadow alone.  So this asks for both: the two-tone
    -- style paints the letter tone and the shadow tone separately, which is
    -- what keeps the symbol from coming out a pixel thick all round.
    Font.pushStyle(symbolInk)
    Font.draw(symbol, ix + 1 + Font.width(shown), nameY)
    Font.popStyle()
  end
  levelAt(battle, battler, ix + inner.w - levelW - 1, nameY, level)

  -- the foe's exact HP is never shown, as on every cartridge
  if player then
    local text = ("%d/%d"):format(shownHP(battler), battler.mon.stats.hp)
    love.graphics.setColor(1, 1, 1, 1)
    -- THE THIRD ROW, which is why the player's box is the tall one.  The
    -- name takes the first eleven of the interior and the bar the next
    -- eight; twenty-seven leaves exactly one more row, and that is where the
    -- numbers go.  Laid out for the FOE's nineteen they landed eight pixels
    -- low, which is on the EXP strip -- "the exp bar is also overlapping the
    -- hp text", and it was the interior height that was wrong rather than
    -- either of them.
    Font.draw(text, barX + barW - Font.width(text), barY + HUD_BAR_H)
    -- ...AND THE EXP BAR IS ALREADY IN THE PANEL.
    --
    -- It is not something to hang off the bottom edge: the player's blob is
    -- sixty-four rows tall and the empty dotted bar is drawn into it, so the
    -- fill goes exactly on top of that strip.  Drawn below the box instead,
    -- there were TWO bars on screen and the upper one ran through the
    -- numbers.  Where the strip is comes from the import, which measures it.
    local exp = hudImage(record and record.bars and record.bars.exp)
    local place = hudExpStrip(record)
    if exp and place then
      love.graphics.setColor(1, 1, 1, 1)
      local filled = 0
      if battle.expFraction then
        local okFill, value = pcall(battle.expFraction, battle)
        filled = (okFill and tonumber(value)) or 0
      end
      -- ...AND THE FRAME IS TALLER THAN THE GROOVE IT FILLS.
      --
      -- Reported from play: "the EXP icon is not lined up".  It was three
      -- pixels low.  `place` is the dotted GROOVE in the panel art -- two
      -- rows -- while a ramp frame is a whole 8x8 tile with three rows of the
      -- box's own edge above the bar, so laying the tile's top on the
      -- groove's top puts the bar under the groove.  The import reads that
      -- offset off the empty frame and proves it by the row count matching
      -- the groove's; with no offset in the record this draws where it did.
      local top = (record.bars and tonumber(record.bars.expTop)) or 0
      drawRamp(exp, x + place.x, y + place.y - top,
               math.floor(place.w / 8),
               math.floor(place.w * math.max(0, math.min(1, filled))))
    end
  end
  Font.popStyle()
  if faced then Font.popFace() end
end

-- THE PARTY BALLS THAT SLIDE IN AT THE START.
--
-- Reported from play, with a picture: "Theres an odd pokeball appearing to the
-- right above the text box".  There was.  BattleState:drawBallRow draws
-- `assets/generated/battle/balls.png`, which is the GAME BOY's row: four 8x8
-- DMG tiles meant to be recoloured by the shade-remap shader on the way past.
-- A Gen 3 cache has no such sheet and no such shader pass, so what reached the
-- screen was whatever those quads found -- six smeared red blobs above the
-- text box, which is exactly what the report shows.  This drew nothing at all
-- while the right art was still unripped; now it draws Emerald's.
--
-- WHAT EMERALD DRAWS is not four tiles in a line.  It is a status summary BAR
-- -- one 128x8 strip per side, the foe's mirrored -- with one 8x8 icon per
-- party member standing on it, and there are FOUR icons rather than the Game
-- Boy's three-and-a-blank: a ball (alive), a hollow outline (that slot is
-- empty, or holding an egg), a filled one (carrying a status) and a grey one
-- (fainted).  Every number below comes off the cartridge; see PARTY_SUMMARY in
-- the extractor for how.
--
-- BOTH ROWS PACK TOWARDS THE MIDDLE OF THE SCREEN, which is the detail that
-- makes a four-Pokemon party look right: the icons are laid out from the end
-- nearest the centre and the empty slots are pushed to the far end, so the
-- foe's four sit on the RIGHT of its row and yours on the LEFT of yours.  The
-- cartridge does that with two counters walking towards each other
-- (CreatePartyStatusSummarySprites, 0873AA4 for the foe and 08738F4 for you)
-- and so does this.
--
-- AND THE FOE'S ROW IS A TRAINER'S ONLY.  A wild battle has no party to show,
-- so BattleIntroDrawPartySummaryScreens raises the player's alone.
local function summaryRecord(battle)
  local record = hudRecord(battle)
  local summary = record and record.partySummary
  if type(summary) ~= "table" then return nil end
  if not (summary.bar and summary.balls) then return nil end
  return summary
end

-- Which of the four icons this slot shows.  An egg is not a Pokemon as far as
-- this row is concerned -- the cartridge marks SPECIES_NONE and SPECIES_EGG
-- with the same 0xFFFF sentinel -- so it takes the hollow outline and gets
-- pushed to the far end with the empty slots.
local function summaryIcon(mon)
  if not mon or not mon.species then return "empty" end
  local okEgg, egg = pcall(function()
    return require("src.pokemon.Party").isEgg(mon)
  end)
  if okEgg and egg then return "empty" end
  if (mon.hp or 0) <= 0 then return "fainted" end
  if mon.status then return "status" end
  return "alive"
end

-- Which icon stands in each of the six places, which is NOT the party in
-- order.  Two counters walk towards each other: a real Pokemon takes the next
-- place from the end nearest the middle of the screen, an empty slot takes one
-- from the far end.  A party of four therefore leans inwards on both rows
-- rather than both rows leaning left.
--
-- Exported because it is the whole rule and it is worth a test that does not
-- need a screen.
function Gen3Battle.summarySlots(summary, side, party)
  local slots = {}
  local count = (summary and summary.count) or 6
  local step = (side and side.packStep) or 1
  local near = (side and side.packFrom) or 1
  local far = step > 0 and count or 1
  for i = 1, count do
    local key = summaryIcon(party and party[i])
    if key == "empty" then
      slots[far] = key
      far = far - step
    else
      slots[near] = key
      near = near + step
    end
  end
  return slots
end

-- ...AND THEY ARRIVE, THEY DO NOT APPEAR.
--
-- Reported from play: "when it shows the pokeballs for you and the enemy in
-- the rom it usually plays an animation of the balls sliding into place and
-- the menu for them sliding into place".  Both rows were drawn complete on
-- the first frame they existed.
--
-- On the cartridge (CreatePartyStatusSummarySprites) each row is built
-- OFF-SCREEN against the edge it belongs to and slid inward, and the icons
-- are then set down one at a time rather than all at once -- which is what
-- makes a six-Pokemon party read as six.
--
-- RECONSTRUCTED, and said so: the two timings below are measured off the
-- scene, not read out of the image.  What IS the cartridge's is the shape --
-- which edge each row comes from (its own, so the foe's enters from the left
-- and yours from the right), and that the icons follow the bar rather than
-- riding on it.
Gen3Battle.SUMMARY_SLIDE_FRAMES = 14
Gen3Battle.SUMMARY_BALL_FRAMES = 4

-- `extra` is how much wider than the cartridge's 240 the surface is.  The
-- two rows belong to opposite edges and the cartridge says so as plainly as
-- it does for the healthboxes: the foe's bar starts at x = -24, twenty-four
-- pixels off the LEFT of its screen, and the player's runs 136..264, the same
-- twenty-four off the RIGHT of it.  So on a wider surface the foe's row does
-- not move and the player's moves out by the whole of the extra width, which
-- is the flip flag this function already reads for the mirroring.
local function drawSummaryRow(summary, side, party, age, extra)
  local edge = side.flip and 0 or math.floor(tonumber(extra) or 0)
  local bar, balls = hudImage(summary.bar), hudImage(summary.balls)
  if not (bar and balls) then return end
  local cell = summary.ballSide or 8
  local barW = summary.barWidth or bar:getWidth()
  -- how far in the row has travelled: 0 is fully off its own edge, 1 home
  local slide = Gen3Battle.SUMMARY_SLIDE_FRAMES
  local p = 1
  if age and slide > 0 then p = math.max(0, math.min(1, age / slide)) end
  -- eased so it settles rather than stopping dead
  local eased = 1 - (1 - p) * (1 - p)
  -- the foe's row lives on the left of the screen and enters from there; the
  -- player's lives on the right and enters from the right
  local dir = side.flip and -1 or 1
  local dx = dir * (1 - eased) * (barW + 16)
  love.graphics.setColor(1, 1, 1, 1)
  -- the strip, mirrored for the foe: drawn from its far corner with a
  -- negative x scale, which is what ST_OAM_HFLIP does to the four pieces
  if side.flip then
    love.graphics.draw(bar, side.barX + barW + dx, side.barY, 0, -1, 1)
  else
    love.graphics.draw(bar, side.barX + edge + dx, side.barY)
  end
  -- ...and the icons, laid out from the middle of the screen outwards
  local slots = Gen3Battle.summarySlots(summary, side, party)
  local count = summary.count or 6
  local icons = summary.icons or {}
  local bw, bh = balls:getDimensions()
  for slot = 1, count do
    local column = icons[slots[slot] or "empty"]
    -- each icon waits for the bar to land and then for its own turn; with no
    -- age at all (a caller that does not track one) every icon is already down
    local due = slide + (slot - 1) * Gen3Battle.SUMMARY_BALL_FRAMES
    if column and (age == nil or age >= due) then
      local quad = love.graphics.newQuad(column * cell, 0, cell, cell,
                                         bw, bh)
      love.graphics.draw(balls, quad,
                         side.ballX + edge
                           + (slot - 1) * (summary.step or 10) + dx,
                         side.ballY)
    end
  end
end

-- Both teams when two trainers walked up; see BattleState:foeSummaryParty.
-- Hoenn only: Gen 1 and Gen 2 have no double battles, so their row below is
-- the one trainer it has always been.
local function foeRowParty(battle)
  if type(battle.foeSummaryParty) == "function" then
    return battle:foeSummaryParty()
  end
  return battle.enemyParty
end

local function drawIntroBalls(battle)
  if not battle.introBalls then return end
  if not require("src.core.GameVersion").isGen3() then
    if battle.enemyParty and
        (battle.kind == "trainer" or battle.kind == "link") then
      battle:drawBallRow(battle.enemyParty, 72, 36, -8)
    end
    battle:drawBallRow(battle.playerParty or battle.game.save.party, 168, 104,
                       8)
    return
  end
  local summary = summaryRecord(battle)
  if not summary then return end
  -- WHEN THE ROWS WENT UP, stamped on the first frame they are actually
  -- drawn rather than on the frame the flag was raised: the flag is set in
  -- BattleState:enter, while the two silhouettes are still sliding in and
  -- these rows are not on screen yet, so counting from there would have the
  -- whole slide happen behind the intro and land the rows already home.
  if battle.introBallsFrom == nil then
    battle.introBallsFrom = battle.frame or 0
  end
  local age = battle.frame and (battle.frame - battle.introBallsFrom) or nil
  if battle.enemyParty and summary.opponent
      and (battle.kind == "trainer" or battle.kind == "link") then
    drawSummaryRow(summary, summary.opponent, foeRowParty(battle), age,
                   Gen3Battle.extra(battle))
  end
  if summary.player then
    drawSummaryRow(summary, summary.player,
                   battle.playerParty or battle.game.save.party, age,
                   Gen3Battle.extra(battle))
  end
end

-- RECONSTRUCTED: the foe's box upper left, the player's lower right, which
-- is the arrangement Emerald uses and the opposite corner pair from Gen 1's.
--
-- WHERE A HEALTHBOX GOES, from the cartridge rather than from taste.
--
-- InitBattlerHealthboxCoords (072B18) loads a pair of immediates per case,
-- and the import reads them back off those instructions.  They are sprite
-- POS1 values, and a GBA sprite's pos1 is its CENTRE: the OAM corner is
-- pos1 + pos2 + centerToCornerVec.  A healthbox is two sprites side by side,
-- each 64 wide, so the panel's top-left is
--
--     x = pos1.x - 32          half of the FIRST sprite
--     y = pos1.y - height / 2
--
-- and the height is the panel's own -- 64 for the player's single-battle
-- box, which is the tall one with the EXP bar, 32 for every other.
--
-- The fallbacks are the places this drew before any of this was read, so a
-- cache imported before the stage existed keeps exactly what it had.
-- WHERE THE TWO PANELS SAT BEFORE THE CARTRIDGE WAS ASKED.
--
-- Kept as ONE table because the drawing and the published geometry both need
-- it and two constants that agree with each other and not with the screen
-- are worth nothing -- which is the rule the rest of this layout already
-- follows for the platforms.
Gen3Battle.HUD_PLACE_FALLBACK = {
  opponent = { x = 8, y = 8, height = 32 },
  player = { x = 112, y = 64, height = 32 },
}

-- ...and where they go once it has been.  `constants` is the dataset's, so
-- this answers the same numbers to the drawing code and to a mod asking the
-- layout where things are.
--
-- `extra` is how much wider than the cartridge's 240 the surface is (0 on the
-- OG layout, and then every line below is the arithmetic it always was).
--
-- THE TWO PANELS BELONG TO OPPOSITE EDGES, and the cartridge says so: it puts
-- the foe's box 12 pixels in from the left of its screen and the player's box
-- against the right of it (InitBattlerHealthboxCoords via
-- gen3BattlerCoords.healthbox -- singlesOpponent x=44, singlesPlayer x=158,
-- each the centre of the first of two 64-wide sprites).  So on a wider
-- surface the foe's box does not move and the player's moves out by the whole
-- of the extra width, keeping the cartridge's own margin from each edge.  No
-- new number: this is the same pair of places, measured from the same two
-- edges, on a screen that has more room between them.
function Gen3Battle.hudPlace(constants, which, height, extra)
  local fb = Gen3Battle.HUD_PLACE_FALLBACK[which]
  local d = (which == "player") and math.floor(tonumber(extra) or 0) or 0
  local coords = constants and constants.gen3BattlerCoords
  local key = which == "player" and "singlesPlayer" or "singlesOpponent"
  local pos = coords and coords.healthbox and coords.healthbox[key]
  if not pos then return fb.x + d, fb.y end
  -- pos1 is the sprite's CENTRE and a healthbox is two 64-wide sprites side
  -- by side, so the panel's corner is pos1 minus half of the FIRST one
  return pos.x - 32 + d, pos.y - math.floor((height or fb.height) / 2)
end

local function healthboxAt(battle, key, panel, fx, fy)
  local constants = battle and battle.data and battle.data.constants
  local which = key == "singlesPlayer" and "player" or "opponent"
  local h
  if panel and panel.getHeight then
    local okH, got = pcall(panel.getHeight, panel)
    if okH and type(got) == "number" then h = got end
  end
  return Gen3Battle.hudPlace(constants, which, h, Gen3Battle.extra(battle))
end

local function drawHUDs(battle, slide)
  local record = hudRecord(battle)
  local images = record and record.images or {}
  local double = battle.isDouble and battle:isDouble()
  if not double and battle.enemy and not battle.showEnemyTrainer
      and not battle.enemySendingOut and not battle:growInScale(battle.enemy)
      and slide == 0 and not battle.introBalls and not battle.enemy.fainted then
    local x, y = healthboxAt(battle, "singlesOpponent",
                             hudImage(images.opponent), 8, 8)
    drawStatusPanel(battle, battle.enemy, x, y, false)
  end
  if not double and not battle.safari and battle.player and not battle.demo
      and not battle.showPlayerBack and slide == 0 then
    local x, y = healthboxAt(battle, "singlesPlayer",
                             hudImage(images.player), 112, 64)
    drawStatusPanel(battle, battle.player, x, y, true)
  end
  -- ...AND THE OTHER TWO PANELS.
  --
  -- InitBattlerHealthboxCoords (072B18) gives all four places, and the
  -- doubles ones are not the singles ones nudged: the right-hand player's
  -- box hangs BELOW the left's (y 101 against 76) and the right-hand foe's
  -- below its own left (44 against 19), which is what keeps four panels off
  -- each other on a screen 160 tall.
  --
  -- The player's doubles panel is its own art too -- shorter, and with no
  -- EXP bar, which is why the cartridge ships five healthbox blobs and not
  -- two.
  if double and slide == 0 then
    local pairs_ = {
      { pos = 0, key = "playerLeft",    img = images.player,        player = true },
      { pos = 2, key = "playerRight",   img = images.playerDoubles
                                              or images.player,     player = true },
      { pos = 1, key = "opponentLeft",  img = images.opponent,      player = false },
      { pos = 3, key = "opponentRight", img = images.opponentDoubles
                                              or images.opponent,   player = false },
    }
    -- ...AND THE ONE BEING AIMED AT FLASHES.  The name in the text panel says
    -- which Pokemon; this says WHERE it is standing, which is the half the
    -- name cannot give you.
    local aimed = nil
    if battle.phase == "targetSelect" then
      aimed = (battle.targetChoices or {})[battle.targetIndex or 1]
    end
    -- A PANEL BELONGS TO A POKEMON THAT IS ON THE FIELD.
    --
    -- Reported from play, with a screenshot of TWINS GINA & MIA: at the
    -- "wants to fight!" message, before anybody has been thrown out, all four
    -- panels were already up -- and drawn over the Poke Ball party counts,
    -- which own that space during the intro.  Some carried a placeholder name
    -- ("A", "Bal") because they were built from a battler the intro had not
    -- filled in yet.
    --
    -- The single-battle branches above have always asked this: the foe's
    -- panel waits on showEnemyTrainer / enemySendingOut / growInScale /
    -- introBalls, and the player's on showPlayerBack.  The doubles branch
    -- asked only `slide == 0` and then whether the Pokemon had HP -- so every
    -- gate the intro relies on was simply absent on the one layout that draws
    -- four of them.
    --
    -- Same conditions, per side, so a double intro reads like two singles
    -- happening at once, which is what it is.
    local enemyReady = not battle.showEnemyTrainer
                       and not battle.enemySendingOut
                       and not battle.introBalls
    local playerReady = not battle.showPlayerBack
    for _, row in ipairs(pairs_) do
      local b = battle:battlerAt(row.pos)
      local ready = row.player and playerReady
                    or (not row.player and enemyReady
                        and not (b and battle:growInScale(b)))
      -- ...AND IT STAYS UP WHILE THE BAR EMPTIES.
      --
      -- Reported from play: in a double battle a Pokemon's panel vanishes the
      -- instant the move lands rather than showing the health run out.  This
      -- asked `hp > 0`, and hp is set to zero by the move itself -- so the
      -- panel was gone a frame before stepHPDrain had drained a single point
      -- of the bar that is supposed to show it happening.
      --
      -- `fainted` is the gate the single-battle draws above already use, and
      -- it is the right one: it is set inside the queued step that plays the
      -- cry and starts the slide, which runs AFTER the drain, so the bar has
      -- emptied by the time it turns true.  Both layouts now answer the same
      -- question, and an empty slot is still nil rather than a zeroed one.
      if ready and b and b.mon and not b.fainted then
        local panel = hudImage(row.img)
        local h = 32
        if panel and panel.getHeight then
          local okH, got = pcall(panel.getHeight, panel)
          if okH and type(got) == "number" then h = got end
        end
        local constants = battle.data and battle.data.constants
        local coords = constants and constants.gen3BattlerCoords
        local pos = coords and coords.healthbox and coords.healthbox[row.key]
        if pos then
          -- ...and in a DOUBLE the same edge rule, per side: playerLeft and
          -- playerRight are the right-hand pair (x 159 and 171 of 240) and
          -- ride the right edge; opponentLeft and opponentRight are the
          -- left-hand pair (44 and 32) and stay put.
          local edge = row.player and Gen3Battle.extra(battle) or 0
          local px, py = pos.x - 32 + edge, pos.y - math.floor(h / 2)
          drawStatusPanel(battle, b, px, py, row.player)
          if b == aimed and math.floor((battle.frame or 0) / 8) % 2 == 0 then
            love.graphics.setColor(1, 1, 0.3, 1)
            love.graphics.rectangle("line", px - 1, py - 1, 66, h + 2)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      end
    end
  end
  drawIntroBalls(battle)
end

-- ---------------------------------------------------------------------------
-- the bottom strip
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- THE CARTRIDGE'S OWN BOTTOM PANEL
--
-- Reported from play: "the text in battle doesnt seem to be correct its really
-- dark but its not like that in the real rom, and the text box in battle has a
-- background in the real game but not in ours".
--
-- Both halves are the same missing thing.  Emerald's bottom strip is a
-- PICTURE -- one 240x48 panel with its own tiles, tilemap and palette -- and
-- the message on it is WHITE with a dark violet shadow on a teal ground, not
-- black on white.  This screen drew Game Boy boxes and printed pure black,
-- which is the one combination the cartridge never uses down there.
--
-- Three panels, chosen by what the player is being asked:
--
--     message   one full-width teal box
--     action    that box on the left, the menu frame on the right
--     moves     two framed boxes, names on the left and PP on the right
--
-- On the cartridge they are three bands of one 32x64 tilemap and it scrolls
-- between them; here they are three pictures and the screen picks one.
--
-- The MENU half of the strip is the player's OPTIONS frame, so its colours
-- come from a different palette than the message half -- which is why there
-- are two colour records and not one.
-- ---------------------------------------------------------------------------
function Gen3Battle.textbox(battle)
  local constants = battle and battle.data and battle.data.constants
  local record = constants and constants.gen3BattleTextbox
  if type(record) ~= "table" or type(record.images) ~= "table" then
    return nil
  end
  return record
end

local warnedNoPanel = false
local function panelImage(battle, which)
  local record = Gen3Battle.textbox(battle)
  local path = nil
  if record then
    local options = battle.game and battle.game.save and battle.game.save.options
                    or battle.save and battle.save.options
                    or {}
    local frame = math.floor(tonumber(options.gen3Frame) or 1)
    local count = math.floor(tonumber(record.frames and record.frames.count) or 0)
    if count > 0 then frame = math.max(1, math.min(count, frame)) end
    local perFrame = record.frameImages and record.frameImages[frame]
    path = perFrame and perFrame[which]
    if type(path) ~= "string" then
      path = record.images and record.images[which]
    end
  end
  if type(path) ~= "string" then
    if not warnedNoPanel then
      warnedNoPanel = true
      Logger.warn("gen3 battle: this cache carries no bottom panel -- "
                    .. "re-import to get the cartridge's own text box")
    end
    return nil, record
  end
  local ok, img = pcall(Assets.image, path)
  return (ok and img) or nil, record
end

-- ---------------------------------------------------------------------------
-- ...AND ON A WIDER SURFACE IT IS THREE-SLICED
--
-- The strip is a PICTURE -- one 240x48 panel with the cartridge's own tiles,
-- tilemap and palette -- so a wider surface cannot be answered by arithmetic:
-- the panel has corners, a frame and a drop shadow, and stretching the lot
-- turns the frame into a smear.  It does have a repeatable middle, and the
-- middle is MEASURED rather than stated, because the three panels are not
-- shaped alike.  DRAMATIC_SHAPE scanned the same three bitmaps and got:
--
--     textbox_message  one panel   0..239   identical columns  11..228
--     textbox_action   panel       0..119   identical columns  11..119
--                      panel     121..238   identical columns 127..232
--     textbox_moves    panel       1..158   identical columns   7..152
--                      panel     161..238   identical columns 167..232
--
-- and this re-measures it at run time for the same reason that mod does: a
-- cache whose panels are shaped differently gets ITS slices, and one whose
-- panel has no repeatable middle gets no widening at all and keeps exactly
-- today's picture.  Same rule measurePlatforms already follows, and cached
-- per path for the same reason -- it is a per-pixel scan.
--
-- A PANEL IS A RUN OF COLUMNS WITH INK IN THEM.  The cartridge separates the
-- message half of the action strip from the menu half with a column of
-- nothing, which is what makes the two halves findable without knowing which
-- strip this is.
--
-- THE FIRST PANEL ABSORBS THE WIDTH; EVERY PANEL AFTER IT MOVES OUT WHOLE.
-- That is the same left/right rule the window templates state (see spanBox):
-- the message half and the move grid are the left-hand furniture and grow or
-- stay, the menu half and the move-detail box are the right-hand furniture
-- and travel with the right edge.  The gap the art leaves between two panels
-- travels with them, so nothing is filled in that the cartridge left empty.
--
-- The middle is ONE source column repeated -- not a resample.  The columns
-- either side of it are identical to it by construction, so there is nothing
-- for a texture filter to bleed in.
-- ---------------------------------------------------------------------------
local function stripSlices(path)
  if type(path) ~= "string" then return nil end
  local hit = stripCache[path]
  if hit ~= nil then return hit or nil end
  stripCache[path] = false
  local okD, id = pcall(Assets.imageData, path)
  if not (okD and id and id.getPixel and id.getDimensions) then return nil end
  local ok, panels = pcall(function()
    local w, h = id:getDimensions()
    if not (w and h and w > 1 and h > 0) then return nil end
    local ink, same = {}, {}
    for x = 0, w - 1 do
      local any = false
      for y = 0, h - 1 do
        local _, _, _, a = id:getPixel(x, y)
        if a > 0 then any = true; break end
      end
      ink[x] = any
    end
    for x = 0, w - 2 do
      local eq = true
      for y = 0, h - 1 do
        local r1, g1, b1, a1 = id:getPixel(x, y)
        local r2, g2, b2, a2 = id:getPixel(x + 1, y)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 or a1 ~= a2 then eq = false; break end
      end
      same[x] = eq
    end
    local out, st = {}, nil
    for x = 0, w - 1 do
      if ink[x] then
        if st == nil then st = x end
      elseif st ~= nil then
        out[#out + 1] = { st, x - 1 }; st = nil
      end
    end
    if st ~= nil then out[#out + 1] = { st, w - 1 } end
    -- ...and inside each panel, the longest run of columns each identical to
    -- the next: that is the one the middle repeats
    for _, p in ipairs(out) do
      local best, bestAt, run = 0, nil, nil
      for x = p[1], p[2] - 1 do
        if same[x] then
          run = run or x
          local len = x + 1 - run + 1
          if len > best then best, bestAt = len, run end
        else
          run = nil
        end
      end
      -- a middle worth repeating, not a two-pixel coincidence
      if best >= 8 then p[3], p[4] = bestAt, bestAt + best - 1 end
    end
    return out
  end)
  if not (ok and panels and #panels > 0) then return nil end
  -- only the FIRST panel is ever cut, so only the first one needs a middle;
  -- a strip whose left-hand panel has none cannot be widened at all
  if not panels[1][3] then return nil end
  stripCache[path] = panels
  return panels
end

-- the quads are fixed per path (the slices and the image size are), so they
-- are cut once rather than per frame
local function stripQuad(path, key, x, y, w, h, iw, ih)
  local per = stripQuads[path]
  if not per then per = {}; stripQuads[path] = per end
  local q = per[key]
  if not q then
    q = love.graphics.newQuad(x, y, w, h, iw, ih)
    per[key] = q
  end
  return q
end

-- Lays the panel across a wider surface, or answers false -- for a 240
-- surface, for a cache whose art cannot be sliced, and for a LOVE without
-- quads (the headless stub) -- and then the caller blits it as it always did.
local function spanPanel(battle, img, path, y)
  local grow = Gen3Battle.width(battle)
  local g = love.graphics
  if Gen3Battle.extra(battle) == 0 or type(g.newQuad) ~= "function" then
    return false
  end
  local panels = stripSlices(path)
  if not panels then return false end
  local okD, iw, ih = pcall(img.getDimensions, img)
  if not (okD and iw and ih and iw > 0 and ih > 0) then return false end
  grow = grow - iw
  if grow <= 0 then return false end
  for i, p in ipairs(panels) do
    local p0, p1, m0, m1 = p[1], p[2], p[3], p[4]
    if i == 1 then
      -- left cap 1:1 where it was, right cap 1:1 at the new right edge, the
      -- one repeatable column stretched across everything between
      local lw, rw = m0 - p0, p1 - m1
      local right = p1 + 1 + grow
      local mid = (right - rw) - (p0 + lw)
      if mid < 0 then mid = 0 end
      if lw > 0 then
        g.draw(img, stripQuad(path, "1L", p0, 0, lw, ih, iw, ih), p0, y)
      end
      if mid > 0 then
        g.draw(img, stripQuad(path, "1M", m0, 0, 1, ih, iw, ih),
               p0 + lw, y, 0, mid, 1)
      end
      if rw > 0 then
        g.draw(img, stripQuad(path, "1R", m1 + 1, 0, rw, ih, iw, ih),
               right - rw, y)
      end
    else
      -- right-hand furniture: moved, never cut
      g.draw(img, stripQuad(path, "W" .. i, p0, 0, p1 - p0 + 1, ih, iw, ih),
             p0 + grow, y)
    end
  end
  return true
end

-- Draws the panel and answers whether it did, so a caller can fall back to
-- its own drawn box on a cache that has none.
local function drawPanel(battle, which)
  local img, record = panelImage(battle, which)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  local y = math.floor(tonumber(record.y) or 112)
  if not spanPanel(battle, img, record.images and record.images[which], y) then
    love.graphics.draw(img, 0, y)
  end
  return true
end

-- THE TEXT IS PRINTED TWICE.  Every string in a Gen 3 battle is a foreground
-- pass over a shadow pass one pixel down and right; the shadow is what makes
-- white legible on teal, and dropping it is most of why black-on-white was
-- reached for in the first place.
local function paintPair(battle, key)
  local record = Gen3Battle.textbox(battle)
  local row = record and record.text and record.text[key]
  local function norm(c)
    if type(c) ~= "table" then return nil end
    return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
  end
  if not row then return nil, nil end
  return norm(row.foreground), norm(row.shadow)
end

-- ...ONCE, THROUGH THE PAGE'S OWN TWO TONES.
--
-- Reported from play: "the textbox in battle doesnt seem to be using the
-- emerald font make it match the rom".  The glyphs WERE the cartridge's --
-- right face, right widths, right panel -- and they did not look like it,
-- because of what was done to them on the way to the screen.
--
-- This used to draw every line TWICE: once in the shadow colour at (1,1) and
-- again in the foreground at (0,0), each pass through the flat tint shader.
-- That shader takes a glyph's ALPHA and paints every opaque pixel one colour,
-- and an Emerald glyph is not one colour -- the page is PRE-TINTED and
-- already carries the letter and its drop shadow as two separate tones.  So
-- the first pass stamped the letter AND its baked shadow in the shadow ink,
-- the second stamped both again one pixel up and left in the foreground ink,
-- and what reached the screen was a four-way smear of a two-tone letter: too
-- thick, too dark, and the shadow in the wrong place on the far side.  That
-- is the same mistake the healthbox was reported for -- "their names are
-- looking a little too bold not matching the rom" -- and it was fixed there
-- and left standing here.
--
-- Font.beginTwoTone is what the fix put in: it recolours the page's two baked
-- tones SEPARATELY, so the letter keeps the shape the cartridge drew and only
-- the two inks change -- which is all the battle window's palette is.  One
-- pass, at (0,0), and the offsets stay in the signature because a cache
-- without the palette still has nothing to recolour with and falls back to
-- plain black-on-white.
local function shadowed(battle, key, fn)
  local fg, shadow = paintPair(battle, key)
  if not fg then
    love.graphics.setColor(0, 0, 0, 1)
    return fn(0, 0)
  end
  Font.pushStyle({ text = fg, shadow = shadow })
  fn(0, 0)
  Font.popStyle()
end

-- The selection arrow: the cartridge's own two tiles when the import has
-- them, and the font's marker when it does not.
local function drawArrow(battle, x, y)
  local record = Gen3Battle.textbox(battle)
  local path = record and record.images and record.images.cursor
  if type(path) == "string" then
    local ok, img = pcall(Assets.image, path)
    if ok and img then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, x, y)
      return
    end
  end
  Font.drawCode(Theme.cursor, x, y)
end

local function drawMessageBox(battle)
  local s = Gen3Battle.strip(battle)
  if not drawPanel(battle, "message") then
    Font.drawBox(s.tx, s.ty, s.tw, s.th)
    love.graphics.setColor(0, 0, 0, 1)
  end
  if battle.scrollPx and battle.scrollPx > 0 then
    battle.scrollPx = battle.scrollPx - 2
    if battle.scrollPx <= 0 then battle.scrollPx = nil end
  end
  local off = battle.scrollPx or 0
  -- THE PEN MOVES BY THE GLYPH'S OWN WIDTH.
  --
  -- This walked the line at a fixed eight pixels a character, which is right
  -- for a Game Boy font -- every glyph there IS eight pixels -- and wrong for
  -- this one.  Emerald's face is proportional and the cartridge ships a width
  -- per glyph (gFontNormalLatinGlyphWidths, which the font stage reads), so a
  -- fixed pitch spaced an 'i' as widely as a 'W' and the whole line came out
  -- gappy and unlike the game.  advanceOf answers 8 on a Game Boy font, so
  -- this is the same drawing there and the right one here.
  shadowed(battle, "message", function(dx, dy)
    for li, line in ipairs(battle.shown or {}) do
      local y = (li == 1 and s.row1 or s.row2) + off + dy
      local pen = s.textX + dx
      for i = 1, #line do
        Font.drawCode(line[i], pen, y)
        pen = pen + Font.advanceOf(line[i])
      end
    end
    if (battle.msgWaiting or battle.msgPrompt) and battle.frame % 60 < 30 then
      Font.drawCode(Theme.moreArrow, (s.tx + s.tw - 2) * 8 + dx, s.row2 + 4 + dy)
    end
  end)
end

-- The menu's own record, or nil on a cache imported before it existed.
function Gen3Battle.menuRecord(battle)
  local constants = battle and battle.data and battle.data.constants
  local record = constants and constants.gen3BattleMenu
  if type(record) ~= "table" or type(record.rows) ~= "table" then return nil end
  if not (record.rows[1] and record.rows[2]) then return nil end
  return record
end

-- THE CURSOR IS NOT $ED HERE.
--
-- $ED is the filled arrow in Gen 1's charmap and a LOWER-CASE 'y' in Gen 3's,
-- and $EC and $EE are 'x' and 'z'.  Emerald draws its menu cursor as a sprite
-- rather than a glyph, so the font stage draws the three markers itself into
-- cells 2F-31 and the font record says where they are; Theme reads that.
-- Every other screen in the port asks Theme.  This one asked for $ED, so a
-- lower-case 'y' sat in front of FIGHT, in front of the selected move, and a
-- 'z' blinked where the more-below arrow belongs.
--
-- RECONSTRUCTED: the split between the prompt window and the command window.

local function drawCommandMenu(battle)
  local col = (battle.menuIndex - 1) % 2
  local row = math.floor((battle.menuIndex - 1) / 2)
  local s = Gen3Battle.strip(battle)

  if battle.safari then
    if not drawPanel(battle, "action") then
      Font.drawBox(s.tx, s.ty, s.tw, s.th)
      love.graphics.setColor(0, 0, 0, 1)
    end
    -- the SAFARI strip is the one set of cells this screen places itself
    -- (the cartridge's menu record has no safari rows), and its two columns
    -- sit on the two halves of the action panel -- so the right-hand column
    -- rides the panel's menu half out to the right edge with everything else
    -- that belongs to it (see spanBox / spanPanel).
    local right = 128 + Gen3Battle.extra(battle)
    shadowed(battle, "menu", function(dx, dy)
      Font.draw(Strings("BALLx"), s.textX + 8 + dx, s.row1 + dy)
      Font.draw(("%2d"):format(battle.safari.balls), s.textX + 48 + dx, s.row1 + dy)
      Font.draw(Strings("BAIT"), s.textX + right + dx, s.row1 + dy)
      Font.draw(Strings("THROW ROCK"), s.textX + 8 + dx, s.row2 + dy)
      Font.draw(Strings("RUN"), s.textX + right + dx, s.row2 + dy)
    end)
    drawArrow(battle, s.textX + (col == 0 and 0 or right - 8),
              s.row1 + row * 16)
    return
  end

  local w = Gen3Battle.windows(battle)
  if not drawPanel(battle, "action") then
    Font.drawBox(w.prompt.tx, w.prompt.ty, w.prompt.tw, w.prompt.th)
    Font.drawBox(w.action.tx, w.action.ty, w.action.tw, w.action.th)
    love.graphics.setColor(0, 0, 0, 1)
  end

  -- THE QUESTION.  The catch demo has no party of its own -- the wild mon is
  -- parked in battle.player as a placeholder -- so it is left unasked there,
  -- exactly as the classic layout leaves it.
  local record = Gen3Battle.menuRecord(battle)
  if not battle.demo then
    -- THE QUESTION SITS ON THE TEAL HALF, so it takes the message's colours;
    -- the four actions sit in the framed box beside it and take the menu's.
    -- One colour for both is what made the whole strip read wrong.
    shadowed(battle, "message", function(dx, dy)
      local prompt = record and record.prompt
      local who = battle.player and battle.player.name or ""
      if prompt and prompt[1] and prompt[2] then
        Font.draw(prompt[1], w.prompt.textX + dx, w.prompt.row1 + dy)
        local second = tostring(prompt[2]):gsub("{MON}", fitName(who, 88))
        Font.draw(second, w.prompt.textX + dx, w.prompt.row2 + dy)
      else
        Font.draw(Strings("What will"), w.prompt.textX + dx, w.prompt.row1 + dy)
        Font.draw(fitName(who, 88) .. Strings(" do?"), w.prompt.textX + dx,
                  w.prompt.row2 + dy)
      end
    end)
  end

  local left = w.action.textX
  local gap = math.floor(tonumber(record and record.columnX) or 56)
  local rows = record and record.rows
  local cells
  if rows then
    cells = { rows[1][1], rows[1][2], rows[2][1], rows[2][2] }
  else
    cells = { Strings("FIGHT"), Strings("ITEM"), Strings("PKMN"),
              Strings("RUN") }
  end
  shadowed(battle, "menu", function(dx, dy)
    for i, label in ipairs(cells) do
      local c = (i - 1) % 2
      local r = math.floor((i - 1) / 2)
      Font.draw(label, left + c * gap + dx, w.action.row1 + r * 16 + dy)
    end
  end)
  drawArrow(battle, left - 8 + col * gap, w.action.row1 + row * 16)
end

-- `panelDrawn` is the move panel's own picture: it covers BOTH boxes, so the
-- second one must not draw a frame over it.
local function drawMoveDetails(battle, move, panelDrawn)
  local s = Gen3Battle.strip(battle)
  local w = Gen3Battle.windows(battle)
  local tx = s.tx + 20
  if w.moves then
    tx = math.max(w.moves[2].tx + w.moves[2].tw,
                  w.moves[4].tx + w.moves[4].tw)
  end
  -- RIGHT-HAND FURNITURE.  This box is whatever the move grid leaves between
  -- itself and the screen's right edge, and on a wider surface that edge is
  -- further out by the whole of the extra width -- while the grid it sits
  -- beside does not move at all (see spanBox).  Its width is unchanged:
  -- both of its edges travel together.
  local edge = Gen3Battle.extra(battle) / 8
  tx = tx + edge
  if not panelDrawn then
    Font.drawBox(tx, s.ty, 30 + edge - tx, s.th)
    love.graphics.setColor(0, 0, 0, 1)
  end
  if not move then return end
  local def = battle.data.moves[move.id]
  if not def then return end
  local maxPP = def.pp + (move.ppUps or 0) * math.floor(def.pp / 5)
  local x = (tx + 1) * 8
  shadowed(battle, "menu", function(dx, dy)
    Font.draw(("PP %2d/%2d"):format(move.pp or 0, maxPP), x + dx, s.row1 + dy)
    Font.draw(fitName(TypeChart.displayName(def.type), 56), x + dx, s.row2 + dy)
  end)
end

local function drawMoveGrid(battle, moves, selected)
  local s = Gen3Battle.strip(battle)
  local w = Gen3Battle.windows(battle)
  -- THE FOUR MOVE NAMES sit in four windows of their own -- 8 by 2, in two
  -- columns and two rows -- and the box around them covers all four.  Their
  -- columns are the cartridge's, not a pair of offsets measured off the
  -- message box.
  local slots = w.moves
  local boxRight = 20
  if slots then
    boxRight = math.max(slots[2].tx + slots[2].tw, slots[4].tx + slots[4].tw)
              - s.tx
  end
  local panelDrawn = drawPanel(battle, "moves")
  if not panelDrawn then
    Font.drawBox(s.tx, s.ty, boxRight, s.th)
    love.graphics.setColor(0, 0, 0, 1)
  end
  local function slotAt(i)
    if slots then return slots[i] end
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    return { textX = s.textX + (col == 0 and 8 or 88),
             row1 = s.row1 + row * 16 }
  end
  shadowed(battle, "menu", function(dx, dy)
    for i, move in ipairs(moves or {}) do
      local slot = slotAt(i)
      local def = battle.data.moves[move.id]
      Font.draw(fitName(def and def.name or move.id or "", 64),
                slot.textX + dx, slot.row1 + dy)
    end
  end)
  local chosen = slotAt(selected)
  drawArrow(battle, chosen.textX - 8, chosen.row1)
  drawMoveDetails(battle, moves and moves[selected], panelDrawn)
end

local function drawMoveMenu(battle)
  -- THE SLOT BEING ASKED, not the left one.  In a double the menu opens twice
  -- and the second pass is for the partner; drawing `battle.player`'s moves
  -- both times is what made it look like the same question asked again.
  local chooser = (battle.menuBattler and battle:menuBattler()) or battle.player
  drawMoveGrid(battle, chooser.curMoves, battle.moveIndex)
  if battle.moveSwapIndex then
    local w = Gen3Battle.windows(battle)
    local slot = w.moves and w.moves[battle.moveSwapIndex]
    if slot then
      Font.drawCode(Theme.cursorHollow, slot.textX - 8, slot.row1)
    end
  end
end

-- WHICH ONE THIS IS AIMED AT.
--
-- Reported from play: "i cant select which pokemon i want to attack."  The
-- selector was there and had been since doubles landed -- LEFT and RIGHT walk
-- the candidates, A takes one -- and NOTHING DREW IT.  `targetSelect` was not
-- one of the phases this switch knows, so it fell to the empty message panel:
-- the move grid vanished, no cursor appeared anywhere, and the only way to
-- find out you were being asked was to press A and see what got hit.
--
-- What goes on screen is the candidate's NAME, which is the one thing the
-- player cannot work out from the field on their own -- two Pokemon of the
-- same species are common in a double, and the healthbox that lights up says
-- which SIDE but not which of the pair.
local function drawTargetPrompt(battle)
  local s = Gen3Battle.strip(battle)
  if not drawPanel(battle, "message") then
    Font.drawBox(s.tx, s.ty, s.tw, s.th)
    love.graphics.setColor(0, 0, 0, 1)
  end
  local list = battle.targetChoices or {}
  local pick = list[battle.targetIndex or 1]
  if not pick then return end
  local user = (battle.menuBattler and battle:menuBattler()) or battle.player
  local mine = user and pick.isPlayer == user.isPlayer
  shadowed(battle, "message", function(dx, dy)
    Font.draw(Strings("Attack who?"), s.textX + dx, s.row1 + dy)
    -- an ally is named as one: aiming at the Pokemon beside yours is legal
    -- and is almost never what you meant by accident
    Font.draw(mine and Strings("%s (ally)", pick.name) or pick.name,
              s.textX + dx, s.row2 + dy)
  end)
end

local function drawTextArea(battle)
  if battle.phase == "messages" and (battle.current or battle.animPlaying) then
    drawMessageBox(battle)
  elseif battle.phase == "menu" then
    drawCommandMenu(battle)
  elseif battle.phase == "moveSelect" then
    drawMoveMenu(battle)
  elseif battle.phase == "targetSelect" then
    drawTargetPrompt(battle)
  elseif battle.phase == "mimicSelect" then
    drawMoveGrid(battle, battle.mimicMoves, battle.mimicIndex)
  else
    -- no prompt of any kind: the empty message panel, which is what the
    -- cartridge leaves on screen between one line and the next
    if not drawPanel(battle, "message") then
      local s = Gen3Battle.strip(battle)
      Font.drawBox(s.tx, s.ty, s.tw, s.th)
    end
  end
end

-- ---------------------------------------------------------------------------
-- WHERE EVERYTHING IS, PUBLISHED
--
-- A composition is not only for the player: DRAMATIC_SHAPE stages a fight on
-- the map and has to know where the two Pokemon stand, where the HUD blocks
-- are (it frosts the ground behind them) and which rows the text box owns.
-- It had those numbers as its OWN constants, measured against the Game Boy
-- screen, and its answer to a second layout existing was to switch that
-- layout off -- which works for an option and cannot work for this one,
-- because Emerald's screen is not a preference.
--
-- So the geometry is the ENGINE'S to state, and a layout that moves anything
-- moves it here.  All in the surface's own pixels.
--
-- WHERE THE TWO POKEMON STAND, when there is no background to measure.
--
-- Gen3Battle.platforms reads these places out of the cartridge's own battle
-- background (see measurePlatforms below); this is the same answer stated,
-- for a dataset whose backgrounds did not import -- and it is what the
-- geometry a mod reads is built from, so the anchors cannot drift from where
-- the mons are actually drawn.
--
-- Each is the point the Pokemon's FEET land on: its horizontal centre and
-- the platform's surface.
Gen3Battle.PLATFORM_FALLBACK = {
  opponent = { x = 176, y = 62 },
  player = { x = 64, y = 111 },
}

-- The classic layout's own anchors, in the same terms -- a Game Boy battle
-- has no platforms, so its two mons sit at the bottom of the tile slots the
-- hardware gives them.  The deltas below are the difference, which is what
-- the animation layer shifts an OAM frame by.
Gen3Battle.CLASSIC_ANCHOR = { player = { 26, 96 }, enemy = { 124, 56 } }

Gen3Battle.PLAYER_REGION_DX =
  Gen3Battle.PLATFORM_FALLBACK.player.x - Gen3Battle.CLASSIC_ANCHOR.player[1]
Gen3Battle.PLAYER_REGION_DY =
  Gen3Battle.PLATFORM_FALLBACK.player.y - Gen3Battle.CLASSIC_ANCHOR.player[2]
Gen3Battle.ENEMY_REGION_DX =
  Gen3Battle.PLATFORM_FALLBACK.opponent.x - Gen3Battle.CLASSIC_ANCHOR.enemy[1]
Gen3Battle.ENEMY_REGION_DY =
  Gen3Battle.PLATFORM_FALLBACK.opponent.y - Gen3Battle.CLASSIC_ANCHOR.enemy[2]

-- `constants` is the dataset's, so the published rectangles can be the same
-- ones the drawing uses.  Absent on a cache imported before the healthbox
-- places were read, and then the fallbacks answer -- which is exactly what
-- this returned before they were.
--
-- `width` is the surface actually in use.  BATTLE LAYOUT = WIDE makes that
-- wider than the cartridge's 240, and the published rectangles have to say so
-- or a mod reading them lays its work out for a screen that is not the one
-- being drawn -- DRAMATIC_SHAPE frosts the ground behind the HUD blocks and
-- cuts the HUD layer on the row between them, both off these numbers.
-- Absent: the cartridge's own width, which is what this answered before the
-- option reached Hoenn.
function Gen3Battle.geometry(classic, constants, width)
  local c = classic or {}
  local ca = c.anchor or Gen3Battle.CLASSIC_ANCHOR
  local surface = math.floor(tonumber(width) or Gen3Battle.WIDTH)
  if surface < Gen3Battle.WIDTH then surface = Gen3Battle.WIDTH end
  local extra = surface - Gen3Battle.WIDTH
  local field = math.floor(extra / 2)
  return {
    width = surface,
    height = Gen3Battle.HEIGHT,
    -- THIS LAYOUT'S WINDOWS BRING THEIR OWN BACKGROUND.
    --
    -- The Game Boy's HUD is glyphs on whatever is behind them, so a mod
    -- staging a battle over a world has to lay something opaque down first or
    -- the numbers sit on grass -- which is what DRAMATIC_SHAPE's frosted
    -- panels are for, and why it repaints black glyphs white when the glass
    -- under them comes out dark.
    --
    -- Emerald's do not.  The status panel is the cartridge's own sprite, an
    -- opaque cream box, and the text strip is the cartridge's own window
    -- frame.  Glass behind them is invisible and the repaint is actively
    -- wrong: white glyphs on a cream panel is white on cream, which is how
    -- the HUD text disappeared entirely in that mode.
    --
    -- So the layout says so, and a mod that lays glass can ask rather than
    -- assume.  Absent on the Game Boy layouts, which is the honest answer for
    -- them: their windows really are transparent.
    opaqueWindows = true,
    -- the two standing places move with the field, exactly as
    -- Gen3Battle.platforms moves the measured ones
    anchor = {
      player = { ca.player[1] + Gen3Battle.PLAYER_REGION_DX + field,
                 ca.player[2] + Gen3Battle.PLAYER_REGION_DY },
      enemy = { ca.enemy[1] + Gen3Battle.ENEMY_REGION_DX + field,
                ca.enemy[2] + Gen3Battle.ENEMY_REGION_DY },
    },
    -- the two status panels drawHUDs lays down, as the boxes they occupy --
    -- from the SAME hudPlace the drawing uses, so the published geometry and
    -- the screen cannot say different things
    hudRect = (function()
      local ex, ey = Gen3Battle.hudPlace(constants, "opponent", 32, extra)
      -- the player's single-battle panel is the tall one, 64 rather than 32:
      -- it is the only healthbox with an EXP bar under it
      local px, py = Gen3Battle.hudPlace(constants, "player", 64, extra)
      return { enemy = { ex, ey, 14 * 8, 4 * 8 },
               player = { px, py, 15 * 8, 5 * 8 } }
    end)(),
    -- the rows each block is cut out of: the battlefield split in two, which
    -- is what a mod compositing them at the window's edges needs
    hudBand = {
      enemy = { 0, 0, surface, Gen3Battle.FIELD_BOTTOM / 2 },
      player = { 0, Gen3Battle.FIELD_BOTTOM / 2, surface,
                 Gen3Battle.FIELD_BOTTOM / 2 },
    },
    -- ONE STRIP.  Every window this layout draws -- the message, the prompt,
    -- the command menu, the moves and their details -- lives inside it, so
    -- unlike the Game Boy's there is no second rectangle further up the
    -- screen for the move menu's own panel.
    textRect = {
      box = { 0, Gen3Battle.STRIP_TOP * 8, surface,
              Gen3Battle.HEIGHT - Gen3Battle.STRIP_TOP * 8 },
    },
  }
end

-- ---------------------------------------------------------------------------
-- the animation layer
-- ---------------------------------------------------------------------------

-- Battle animations are authored in the original 160px coordinate space.
-- Shift each complete OAM frame as one rigid group between the new player and
-- enemy anchors rather than drawing it through both side regions, which would
-- duplicate any tiles overlapping the other side's source range.
function Gen3Battle.animationOffset(sprites)
  if not sprites or #sprites == 0 then return 0, 0 end
  local minX, maxX = math.huge, -math.huge
  for _, sprite in ipairs(sprites) do
    minX = math.min(minX, sprite.x - 8)
    maxX = math.max(maxX, sprite.x)
  end
  local center = (minX + maxX) / 2
  local t = math.max(0, math.min(1, (center - 40) / 80))
  return math.floor(12 + 64 * t + 0.5), math.floor(12 * (1 - t) + 0.5)
end

local function currentAnimationSprites(battle)
  if battle.animPlaying and battle.animPlayer then
    local step = battle.animPlayer.steps[battle.animPlayer.stepIndex]
    return step and step.sprites
  end
  if battle.lockedBall and battle.animPlayer then
    return battle.lockedBall
  end
end

local function drawAnimationLayer(battle)
  -- EMERALD'S OWN move animations first, and NOT through the region below:
  -- that region exists to squeeze a Game Boy animation's 160x144 coordinates
  -- into this field, and a Gen 3 particle already knows where it goes.
  if battle.gen3AnimPlaying and battle.gen3Anim then
    local skipEvents = battle._gen3OamCompositedFrame == battle.frame
    local ok = pcall(battle.gen3Anim.draw, battle.gen3Anim, battle, skipEvents)
    if ok then return end
  end
  local sprites = currentAnimationSprites(battle)
  if not sprites or #sprites == 0 then return end
  local dx, dy = Gen3Battle.animationOffset(sprites)
  -- ...and the Game Boy animation's own offset is into the FIELD, which moved
  -- with the background (fieldOffset), while the region it is clipped to is
  -- the whole surface -- a particle thrown across a widened screen must not
  -- be cut off at the cartridge's 240th column.
  inRegion(0, 0, Gen3Battle.width(battle), Gen3Battle.FIELD_BOTTOM,
    dx + Gen3Battle.fieldOffset(battle), dy,
    function() battle:drawAnimLayer(false) end)
end

-- FireRed does not have a separate "Pokemon then particles" layer.  Battler
-- pics and ordinary createsprite particles are OBJ and BuildOamBuffer sorts
-- them together by priority/subpriority/live Y.  In a single battle we can
-- preserve BattleState's full per-side drawing path while treating each side
-- as one OAM object, then insert direct particles between them.
--
-- Doubles are intentionally left residual here: drawPicsLayer's side selector
-- draws both partners together, while FireRed gives them distinct subpriorities
-- (20/30 and 40/50).  In singles, monbg copies are inserted between the exact
-- OBJ priority bands: same-priority OBJ wins over BG, while splitbgprio can
-- promote BG1 from priority 2 to priority 1.
function Gen3Battle.drawMoveOamObjects(battle, slide, sx, sy)
  local anim = battle and battle.gen3AnimPlaying and battle.gen3Anim
  if not (anim and anim.oamEventDescriptors) then return false, "inactive" end
  if battle.isDouble then
    local ok, double = pcall(battle.isDouble, battle)
    if ok and double then return false, "double-battler-slot" end
  end

  local events, reason = anim:oamEventDescriptors(battle, Gen3Battle)
  if not events then return false, reason end
  local copies = anim.monBgCopies and anim:monBgCopies(battle, "oam") or {}
  if #events == 0 and #copies == 0 then return false, "no-active-particles" end

  local objects = {}
  local function addBattler(battler, side, seed)
    if not battler then return true end
    if anim.monBgHidesBattler and anim:monBgHidesBattler(battle, battler) then
      return true
    end
    local key = anim:battlerPriorityKey(battler)
    local y = anim:battlerOamY(battle, battler)
    if not (key and y ~= nil) then return false end
    objects[#objects + 1] = {
      kind = "battler", battler = battler, side = side,
      key = key, oamY = y, seed = seed,
    }
    return true
  end
  if not addBattler(battle.player, "player", 1)
     or not addBattler(battle.enemy, "enemy", 2) then
    return false, "unknown-battler-oam"
  end
  for _, item in ipairs(events) do
    item.seed = 1000 + (item.index or 0)
    objects[#objects + 1] = item
  end

  -- We can preserve FireRed's stable order once an object has a prior rank,
  -- but the first exact key+Y tie depends on the global gSpriteOrder history
  -- (free sprite slot reuse across the whole battle), which this compact
  -- renderer does not model.  Keep that residual explicit instead of claiming
  -- the deterministic seed below is cartridge-proven.
  local exactTie = false
  for i = 1, #objects - 1 do
    for j = i + 1, #objects do
      if objects[i].key == objects[j].key
         and objects[i].oamY == objects[j].oamY then
        exactTie = true
        break
      end
    end
    if exactTie then break end
  end
  battle._gen3OamGlobalTieResidual = exactTie and "global-sprite-slot-history" or nil

  local previous = battle._gen3OamObjectRanks or setmetatable({}, { __mode = "k" })
  table.sort(objects, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    if a.oamY ~= b.oamY then return a.oamY > b.oamY end
    local ar = previous[a.event or a.battler] or a.rank or a.seed
    local br = previous[b.event or b.battler] or b.rank or b.seed
    if ar ~= br then return ar < br end
    return a.seed < b.seed
  end)
  for i, item in ipairs(objects) do
    previous[item.event or item.battler] = i
    if item.event and anim.oamRanks then anim.oamRanks[item.event] = i end
  end
  battle._gen3OamObjectRanks = previous

  local function drawObject(item)
    if item.kind == "battler" then
      battle:drawPicsLayer(slide, sx, sy, item.side, true)
    else
      anim:drawEvent(item.event, battle, Gen3Battle, Assets, item.pose, true)
    end
  end
  -- Hardware order above is front-to-back (low OAM index first); LOVE needs
  -- back-to-front.  A copied BG at priority N is behind every OBJ at priority N
  -- but in front of every OBJ at priority N+1.  Draw exactly those four bands.
  for priority = 3, 0, -1 do
    for _, copy in ipairs(copies) do
      if (tonumber(copy.priority) or 2) == priority
         and battle.drawGen3MonBgState then
        battle:drawGen3MonBgState(copy)
      end
    end
    for i = #objects, 1, -1 do
      local item = objects[i]
      if math.floor((tonumber(item.key) or 0) / 256) == priority then
        drawObject(item)
      end
    end
  end
  battle._gen3OamCompositedFrame = battle.frame
  return true
end

-- ---------------------------------------------------------------------------
-- the whole 240x160 composition for one frame
-- ---------------------------------------------------------------------------

-- THE FIELD: the paper and the ground on it.
--
-- A LAYER OF ITS OWN, because a mod may be drawing something behind this
-- battle and a battle that paints its own ground erases it.  The classic
-- layout has no equivalent -- it has no backdrop at all -- so nothing in the
-- engine had ever needed the seam, and DRAMATIC_SHAPE's in-world 3D battle
-- staged a voxel arena and then had Emerald's flat terrain painted straight
-- over the top of it.
--
-- `letterboxWhite == false` is the engine's own published "something else is
-- behind this battle": Renderer reads it to decide whether to fill the voids
-- around the screen with paper, and a state that answers false is saying it
-- is not the ground.  A battle that is not the ground must not paint one.
-- That is the flag DRAMATIC_SHAPE already sets, so it needs no change to work
-- -- and a mod that wants the field back simply leaves the flag alone.
-- THE BANDS REACH THE SURFACE'S EDGES.
--
-- A Gen 3 battle background is horizontal BANDS with two platforms drawn over
-- them.  That is not an assumption here, it is the measurement the platform
-- finder below is already built on: "a band reaches the edge of the screen
-- and a platform never does, so the colour of the longer of a row's two edge
-- runs IS that row's band".
--
-- So the picture's first column is the left band of every row it has, and
-- repeating that ONE column outward fills the space beside a centred field
-- EXACTLY -- no stretch, no resample, and the platforms, the sky and the
-- dithering keep every pixel they were drawn with.  The same on the right
-- with the last column.  The rows the background leaves transparent -- the
-- strip along the bottom where the message window goes -- repeat as
-- transparent, so the paper still shows through there.
local function spanGround(g, ground, ox, surface)
  if type(g.newQuad) ~= "function" then return end
  local okD, iw, ih = pcall(ground.getDimensions, ground)
  if not (okD and iw and ih and iw > 0 and ih > 0) then return end
  local q = bandQuads[ground]
  if not q then
    q = { left = g.newQuad(0, 0, 1, ih, iw, ih),
          right = g.newQuad(iw - 1, 0, 1, ih, iw, ih) }
    bandQuads[ground] = q
  end
  if ox > 0 then g.draw(ground, q.left, 0, 0, 0, ox, 1) end
  local rx = ox + iw
  if rx < surface then
    g.draw(ground, q.right, rx, 0, 0, surface - rx, 1)
  end
end

function Gen3Battle.drawField(battle)
  if battle.letterboxWhite == false then return end
  local g = love.graphics
  local surface = Gen3Battle.width(battle)
  if monoMode() then
    g.setColor(1, 1, 1, 1)
  else
    g.setColor(PaletteFX.paperShade(battle.data))
  end
  g.rectangle("fill", 0, 0, surface, Gen3Battle.HEIGHT)

  -- THE GROUND, over the paper.  A dataset with no backgrounds keeps the flat
  -- field it had, and a transparent strip along the bottom is the paper
  -- showing through where the message window goes -- which is what the
  -- cartridge does with it too.
  local ground = Gen3Battle.backdrop(battle)
  local groundBrightness = 1
  local moveBgLayer = nil
  -- FireRed move backgrounds replace BG3 itself.  Ask the active Gen3 move
  -- player for that underlay here, before battlers/HUD/particles are drawn;
  -- drawing it later as an animation sprite would put it over the Pokemon.
  if battle.gen3AnimPlaying and battle.gen3Anim
     and battle.gen3Anim.backgroundLayer then
    local okLayer, layer = pcall(battle.gen3Anim.backgroundLayer, battle.gen3Anim)
    if okLayer and layer then
      moveBgLayer = layer
      groundBrightness = tonumber(layer.brightness) or 1
      if not layer.default and not layer.indexed and layer.image then
        local okImage, image = pcall(Assets.image, layer.image)
        if okImage and image and image.getDimensions then ground = image end
      end
    end
  end
  if ground then
    g.setColor(groundBrightness, groundBrightness, groundBrightness, 1)
    -- BATTLE LAYOUT = WIDE: keep the cartridge field centred and fill only
    -- the bands beside it.  The FireRed intro then slides its two scanline
    -- halves inside that field without changing their cartridge timing.
    local ox = Gen3Battle.fieldOffset(battle)
    if surface > Gen3Battle.WIDTH then spanGround(g, ground, ox, surface) end
    local slide = battle.frlgIntro and (battle.introSlide or 0) * 2 or 0
    if slide > 0 then
      -- BattleIntroSlide1's scanline split: the foe's half (rows 0-79) comes
      -- in from the left, the player's half from the right
      local W, H = Gen3Battle.WIDTH, Gen3Battle.HEIGHT
      local top = g.newQuad(0, 0, W, 80, ground:getDimensions())
      local bottom = g.newQuad(0, 80, W, H - 80, ground:getDimensions())
      -- the background layer wraps, so the far side is never bare paper
      g.draw(ground, top, ox - slide, 0)
      g.draw(ground, top, ox + W - slide, 0)
      g.draw(ground, bottom, ox + slide, 80)
      g.draw(ground, bottom, ox + slide - W, 80)
    else
      g.draw(ground, ox, 0)
    end
    g.setColor(1, 1, 1, 1)
  end
  if moveBgLayer and moveBgLayer.indexed then
    drawIndexedMoveBg(g, battle, moveBgLayer)
  end
  -- AnimTask_Flash touches the battle-background palettes only.  Draw this
  -- after the field and before weather/battlers/HUD so the rest of the UI does
  -- not become a generic white rectangle.  flashState is the exact 16-level
  -- palette coefficient: full through cb8, 15/16 at cb9 ... zero at cb39.
  if battle.gen3AnimPlaying and battle.gen3Anim
     and battle.gen3Anim.flashState then
    local okFlash, white = pcall(battle.gen3Anim.flashState, battle.gen3Anim)
    if okFlash and type(white) == "number" and white > 0 then
      g.setColor(1, 1, 1, math.max(0, math.min(1, white)))
      g.rectangle("fill", 0, 0, surface, Gen3Battle.HEIGHT)
      g.setColor(1, 1, 1, 1)
    end
  end
  Gen3Battle.drawWeather(battle)
end

-- ---------------------------------------------------------------------------
-- THE WEATHER, WHICH WAS NOT DRAWN AT ALL
--
-- Reported from play: "in battle when there are weather effects theyre not
-- showing properly".  Nothing was showing: the battle has modelled weather
-- for a long time -- it drives the damage multipliers, THUNDER's accuracy,
-- the residual chip on SANDSTORM and HAIL, and CLOUD NINE and AIR LOCK
-- suppress it -- and no part of the screen ever asked what it was.  A RAIN
-- DANCE was four turns of text on a dry field.
--
-- The field already had a renderer for exactly this (src/world/Gen3Weather),
-- built when Route 113's ash and Route 120's fog went in, and a battle's
-- weather is the same handful of names.  So this is a wiring, not a new
-- effect: Weather.current gives the battle's own state -- ALREADY past the
-- suppressors, so Air Lock stops the rain being drawn as well as being felt
-- -- and Gen3Weather.forBattle turns it into the look the cartridge's own
-- map-weather table says it is.
--
-- It goes on over the ground and under the Pokemon, which is where the
-- hardware's weather layer sits.
function Gen3Battle.drawWeather(battle)
  -- both modules are resolved once and kept; this ran two requires and four
  -- pcalls on every battle frame, weather or not
  local Weather = weatherMod()
  if not (Weather and Weather.current) then return end
  local okW, current = pcall(Weather.current, battle)
  if not (okW and current) then return end
  local Gen3Weather = fieldWeatherMod()
  if not Gen3Weather then return end
  local data = battle and battle.data
  local name = Gen3Weather.forBattle(current, data and data.constants)
  if not name then return end
  -- the weather is a full-width layer, so it is the SURFACE's width and not
  -- the cartridge's: rain that stops 240 pixels in is a rectangle of dry
  -- field down each side of a widened screen
  pcall(Gen3Weather.draw, name, battle.frame or 0,
        Gen3Battle.width(battle),
        Gen3Battle.FIELD_BOTTOM or Gen3Battle.HEIGHT)
end

Gen3Battle.drawHUDs = drawHUDs
Gen3Battle.drawTextArea = drawTextArea
Gen3Battle.drawAnimationLayer = drawAnimationLayer

-- ---------------------------------------------------------------------------
-- WHERE THE TWO POKEMON STAND
--
-- The pics used to be placed by Gen 1's rule -- a 7x7 tile slot at a fixed
-- tile coordinate -- and then the whole slot was translated bodily into the
-- Gen 3 field with two reconstructed offsets.  On a 160x144 letterbox that
-- rule is the hardware's; on Emerald's 240x160 field it is nothing, and it
-- showed: the foe sat up in the corner well above its platform, and the
-- player's back pic was drawn at the Game Boy's 2x and ran off the bottom of
-- the screen through the message window.
--
-- SO THE PLATFORMS ARE MEASURED, out of the cartridge's own battle
-- background, and nothing here knows a coordinate.
--
-- A Gen 3 battle background is horizontal BANDS -- each row of the sky and
-- the ground is one colour all the way across -- with the two platforms
-- drawn over them.  A band reaches the edge of the screen and a platform
-- never does, so the colour of the longer of a row's two edge runs IS that
-- row's band, and everything else in the row is platform.  That is the whole
-- test: no palette, no address, and it re-measures itself for every one of
-- the cartridge's terrains.  The widest row of each blob is where its
-- surface faces the camera, which is where a Pokemon's feet go.
--
-- The measurement puts the foe's platform centred on x = 175.5 of 240, which
-- is a number this port did not choose.
-- ---------------------------------------------------------------------------

local platformCache = setmetatable({}, { __mode = "k" })
local opaqueCache = setmetatable({}, { __mode = "k" })

local function invalidatePlacement()
  platformCache = setmetatable({}, { __mode = "k" })
  opaqueCache = setmetatable({}, { __mode = "k" })
  -- ...and the strip slices, for the same reason: they are a per-pixel
  -- measurement of an asset an asset mod is allowed to replace
  stripCache = {}
  stripQuads = {}
  bandQuads = setmetatable({}, { __mode = "k" })
end
Assets.register(invalidatePlacement)

local function measurePlatforms(path)
  local hit = platformCache[path]
  if hit ~= nil then return hit or nil end
  local ok, id = pcall(Assets.imageData, path)
  if not (ok and id) then
    platformCache[path] = false
    return nil
  end
  local okScan, result = pcall(function()
    local w, h = id:getDimensions()
    local blobs = {
      opponent = { minx = w, maxx = -1, rows = {}, best = 0, y = nil },
      player = { minx = w, maxx = -1, rows = {}, best = 0, y = nil },
    }
    local function keyAt(px, py)
      local r, g, b, a = id:getPixel(px, py)
      return ("%d,%d,%d,%d"):format(math.floor(r * 255 + 0.5),
                                    math.floor(g * 255 + 0.5),
                                    math.floor(b * 255 + 0.5),
                                    a > 0.5 and 1 or 0)
    end

    local keys = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do keys[x] = keyAt(x, y) end

      -- THE BAND IS WHATEVER REACHES AN EDGE.  A band runs the whole width;
      -- a platform never does, so at least one end of every row is
      -- background.  (Asking for the row's most COMMON colour looks simpler
      -- and is wrong: at its widest the foe's platform is more than half the
      -- row, and the rule inverts -- it reports the sky as the platform.)
      local leftRun, rightRun = 1, 1
      while leftRun < w and keys[leftRun] == keys[0] do leftRun = leftRun + 1 end
      while rightRun < w and keys[w - 1 - rightRun] == keys[w - 1] do
        rightRun = rightRun + 1
      end
      local band = (leftRun >= rightRun) and keys[0] or keys[w - 1]

      local side = (y < h / 2) and "opponent" or "player"
      local blob = blobs[side]
      local run, rowMin, rowMax = 0, w, -1
      for x = 0, w - 1 do
        if keys[x] ~= band then
          run = run + 1
          if x < rowMin then rowMin = x end
          if x > rowMax then rowMax = x end
        end
      end
      -- Keep the horizontal bounds from the same widest row that supplies
      -- the platform surface.  FireRed backdrops have edge detail on other
      -- rows; folding those pixels into global min/max shifts both battlers
      -- away from the actual platform even though the chosen y is correct.
      if run > blob.best then
        blob.best, blob.y = run, y
        blob.minx, blob.maxx = rowMin, rowMax
      end
    end
    local out = {}
    for side, blob in pairs(blobs) do
      -- a blob has to be a platform's worth of pixels, not a stray dither
      if blob.maxx >= 0 and blob.best >= 32 and (blob.maxx - blob.minx) >= 48 then
        out[side] = { x = (blob.minx + blob.maxx) / 2, y = blob.y }
      end
    end
    if not (out.opponent and out.player) then return nil end
    return out
  end)
  local answer = okScan and result or nil
  platformCache[path] = answer or false
  return answer
end

-- Where this battle's two Pokemon stand, measured or (failing that) stated.
--
-- MEASURED FROM WHATEVER IS ACTUALLY DRAWN.  A gym's platforms are not where
-- a grass field's are, so this has to ask the same question backdrop() does
-- and in the same order -- the map's own scene first, the terrain second.
-- Reading the terrain here while the screen drew a gym is how a Pokemon ends
-- up standing beside its platform rather than on it.
function Gen3Battle.platforms(battle)
  local constants = battle and battle.data and battle.data.constants
  local path

  local scenes = constants and constants.gen3BattleScenes
  local scene = battle and battle.gen3Scene
  if scene == nil then
    scene = Gen3Battle.sceneFor(battle and battle.game) or false
    if battle then battle.gen3Scene = scene end
  end
  if scene and type(scenes) == "table" and type(scenes.images) == "table" then
    path = scenes.images[scene]
  end

  local record = constants and constants.gen3BattleTerrain
  if not path and type(record) == "table" and type(record.images) == "table" then
    local terrain = battle.gen3Terrain
    if not terrain then
      terrain = Gen3Battle.terrainFor(battle.game)
      battle.gen3Terrain = terrain
    end
    path = record.images[terrain] or record.images.PLAIN
  end
  local measured = path and measurePlatforms(path)
  local spots = measured or Gen3Battle.PLATFORM_FALLBACK
  -- BATTLE LAYOUT = WIDE: the background is drawn at fieldOffset rather than
  -- at 0 (Gen3Battle.drawField), and these places are measured in the
  -- background's OWN pixels -- so the offset belongs here too or the two
  -- Pokemon stand beside their platforms instead of on them.  One place adds
  -- it, and picPlacement, battlerCentre and every caller of theirs inherit
  -- it; 0 on the OG layout, where this is the table it always was.
  local ox = Gen3Battle.fieldOffset(battle)
  if ox == 0 then return spots end
  return { opponent = { x = spots.opponent.x + ox, y = spots.opponent.y },
           player = { x = spots.player.x + ox, y = spots.player.y } }
end

-- The opaque bounds of a pic, so a Pokemon is placed by where its FEET are
-- rather than by where its 64x64 frame ends -- the empty space under the art
-- runs from one row (CHARIZARD) to fourteen (BULBASAUR), and using the frame
-- leaves the small ones hovering.
-- `source` is the asset PATH where the engine knows one, and the image
-- itself where it does not -- a pic composed at run time (a colourised build,
-- a mod's own) has no path to look up, and it still has to stand on the
-- ground.
function Gen3Battle.opaqueBounds(source)
  if source == nil then return nil end
  local hit = opaqueCache[source]
  if hit ~= nil then return hit or nil end
  local ok, bounds = pcall(function()
    local id = (type(source) == "string") and Assets.imageData(source) or source
    if type(id) ~= "table" and type(id) ~= "userdata" then return nil end
    if not id.getPixel then return nil end
    local w, h = id:getDimensions()
    local minx, miny, maxx, maxy = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = id:getPixel(x, y)
        if a > 0 then
          if x < minx then minx = x end
          if x > maxx then maxx = x end
          if y < miny then miny = y end
          if y > maxy then maxy = y end
        end
      end
    end
    if maxx < 0 then return nil end
    return { minx = minx, miny = miny, maxx = maxx, maxy = maxy,
             w = w, h = h }
  end)
  local answer = ok and bounds or nil
  opaqueCache[source] = answer or false
  return answer
end

-- The top-left corner to draw `img` at, so the Pokemon stands on its own
-- platform.  `lift` is the cartridge's own per-species elevation: the
-- species that never touch the ground.
function Gen3Battle.picPlacement(battle, battler, img, path, scale)
  scale = scale or 1
  local spots = Gen3Battle.platforms(battle)
  local spot = battler.isPlayer and spots.player or spots.opponent
  -- AND IN A DOUBLE, WHICH OF THE TWO PLACES ON THAT SIDE.
  --
  -- sBattlerCoords (0525F58) is indexed by BATTLE_TYPE_DOUBLE and then by
  -- battler position, and the doubles row is NOT the singles row spread
  -- out: the foes move outward and the right-hand pair sit off the left
  -- pair's line, which is what stops four sprites overlapping on a screen
  -- 240 wide.
  --
  -- The platform stays the anchor for the LEFT of each pair, because the
  -- platform is measured out of the drawn background and the table agrees
  -- with it -- the single-battle foe is x=176 both ways.  So a slot is
  -- placed by the table's OFFSET from its own row's left entry, which keeps
  -- the measured ground truth and adds only what the table alone knows.
  --
  -- A battler with no `position` -- which is how the placement test calls
  -- this -- takes the left of its side, exactly as before.
  local coords = battle.data and battle.data.constants
                 and battle.data.constants.gen3BattlerCoords
  local pos = tonumber(battler.position) or (battler.isPlayer and 0 or 1)
  if coords and coords.doubles and coords.singles
     and battle.isDouble and battle:isDouble() then
    local mine = coords.doubles[pos + 1]
    -- the SAME SIDE's single-battle place, which is the one the measured
    -- platform corresponds to
    local was = coords.singles[(pos % 2) + 1]
    if mine and was then
      spot = { x = spot.x + (mine.x - was.x),
               y = spot.y + (mine.y - was.y) }
    end
  end
  local w, h = img:getWidth(), img:getHeight()
  local bounds = Gen3Battle.opaqueBounds(path)
                 or Gen3Battle.opaqueBounds(img)
  local footX, footY
  if bounds then
    footX = (bounds.minx + bounds.maxx + 1) / 2
    footY = bounds.maxy + 1
  else
    footX, footY = w / 2, h
  end
  local lift = 0
  local species = battler.species or (battler.mon and battler.mon.species)
  local table_ = battle.data and battle.data.constants
                 and battle.data.constants.gen3Elevation
  -- only the FOE is lifted: the player's own Pokemon is seen from behind and
  -- the cartridge keeps its own table for that side
  if species and table_ and not battler.isPlayer then
    lift = table_[species] or 0
  end
  return spot.x - footX * scale,
         spot.y - lift - footY * scale
end

-- WHERE A BATTLER'S BODY IS ON SCREEN, which the move animations need and
-- picPlacement above does not give: that returns the pic's top-left corner,
-- and a particle belongs over the middle of the Pokemon.  Measured off the
-- pic's own opaque pixels for the same reason its feet are -- the sheets have
-- different amounts of blank around them and a fixed lift puts the effect on
-- the ground for one species and above the head for another.
function Gen3Battle.battlerCentre(battle, battler)
  if not (battler and battler.sprite and battle and battle.picImage) then
    return nil
  end
  local ok, img = pcall(battle.picImage, battle, battler.sprite)
  if not (ok and img and img.getWidth) then return nil end
  local BattleState = require("src.battle.BattleState")
  local scale = 1
  local species = battler.species or (battler.mon and battler.mon.species)
  local okScale, s = pcall(BattleState.resolveBattleScale, battle.data,
                           battler.isPlayer and "back" or "front", nil,
                           species)
  if okScale and type(s) == "number" and s > 0 then scale = s end
  local x, y = Gen3Battle.picPlacement(battle, battler, img, battler.sprite,
                                       scale)
  if not (x and y) then return nil end
  local bounds = Gen3Battle.opaqueBounds(battler.sprite)
                 or Gen3Battle.opaqueBounds(img)
  local cx, cy
  if bounds then
    cx = (bounds.minx + bounds.maxx + 1) / 2
    cy = (bounds.miny + bounds.maxy + 1) / 2
  else
    cx, cy = img:getWidth() / 2, img:getHeight() / 2
  end
  return x + cx * scale, y + cy * scale
end

-- ---------------------------------------------------------------------------
-- THE POKéBALL, DRAWN
--
-- The timeline is src/battle/Gen3BallAnim.lua; this is only what it looks
-- like.  Three pieces, in the order they go down: the particle ring the ball
-- throws off when it opens, the ball itself, and the stars a capture spends.
--
-- The Pokémon's own shrink is NOT here -- it is a property of the pic, so
-- drawPicsLayer reads the same animation for its scale and its blend.  Two
-- places reading one timeline is what keeps the ball and the Pokémon it is
-- swallowing on the same frame.
-- ---------------------------------------------------------------------------
function Gen3Battle.ballRecord(battle)
  local anim = battle and battle.gen3Ball
  if not anim then return nil end
  local record = (battle.data.constants or {}).gen3BallAnim
  if type(record) ~= "table" or type(record.images) ~= "table" then
    return nil, anim
  end
  return record, anim
end

local function ballSheet(battle, key)
  local record = (battle.data.constants or {}).gen3BallAnim
  local path = record and record.images and record.images[key]
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return (ok and img) or nil
end

function Gen3Battle.drawBall(battle)
  local record, anim = Gen3Battle.ballRecord(battle)
  if not anim then return end
  local g = love.graphics
  local size = (record and record.size) or 16
  local frames = (record and record.frames) or 3

  -- the ring, which is the same eight-frame sheet for every ball
  local particles = anim.particles
  if particles then
    local sheet = ballSheet(battle, "particles")
    local which = 0
    if record and record.balls and record.balls[anim.ball + 1] then
      which = math.floor(tonumber(record.balls[anim.ball + 1].particle) or 0)
    end
    local t = particles.age / math.max(1, particles.life)
    local r = t * particles.radius
    for i = 0, particles.count - 1 do
      -- one particle a frame around two full eight-point rings, which is
      -- what the cartridge's own spawn loop does
      if i <= particles.age then
        local a = (i % 8) * 2 * math.pi / 8
        local px = particles.x + math.sin(a) * r
        local py = particles.y + math.cos(a) * r
        if sheet then
          local iw, ih = sheet:getDimensions()
          local n = math.floor((record and record.particleFrames) or 8)
          local q = love.graphics.newQuad((which % n) * 8, 0, 8, 8, iw, ih)
          g.setColor(1, 1, 1, 1 - t)
          g.draw(sheet, q, px - 4, py - 4)
        else
          g.setColor(1, 1, 0.7, 1 - t)
          g.rectangle("fill", px - 2, py - 2, 4, 4)
        end
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  -- the ball
  local sheet = ballSheet(battle, "balls")
  local bx = anim.x - size / 2 + (anim.shakeOffset or 0)
  local by = anim.y - size / 2
  g.setColor(1, 1, 1, 1 - (anim.whiteout or 0))
  if sheet then
    local iw, ih = sheet:getDimensions()
    local f = math.max(1, math.min(frames, anim.ballFrame or 1)) - 1
    local q = love.graphics.newQuad(f * size, anim.ball * size, size, size,
                                    iw, ih)
    g.draw(sheet, q, bx, by)
  else
    g.setColor(0.9, 0.2, 0.2, 1 - (anim.whiteout or 0))
    g.rectangle("fill", bx + 2, by + 2, size - 4, size - 4)
  end

  -- ...THE SHINY SPARKLE, which is not the capture's stars.
  --
  -- Task_ShinyStars (08172FEC) runs TWO streams of five sparkles, one every
  -- four frames, and each sprite is offset from the mon rather than sitting
  -- on it (the second stream carries the -32 / +32 pair written at 0817312C).
  -- Drawn over the Pokemon, above the ball layer, because that is where it is
  -- on the cartridge: the ball sprite is freed the moment the mon is out.
  if anim.shinyStars then
    local Gen3BallAnim = require("src.battle.Gen3BallAnim")
    local sp = anim.shinyStars
    local cx, cy = anim.x, anim.y
    for stream = 0, 1 do
      for i = 1, sp.made do
        local born = (i - 1) * Gen3BallAnim.SHINY_EVERY
        local age = sp.age - Gen3BallAnim.SHINY_DELAY - born
        local life = 18
        if age >= 0 and age < life then
          local t = age / life
          -- one stream rises out of the mon's left shoulder, the other its
          -- right, which is the pair of x offsets the task writes
          local dx = (stream == 0 and -1 or 1) * (10 + 14 * t)
          local dy = -8 - 22 * t + (stream == 0 and 0 or 6)
          local a = 1 - t
          local px, py = cx + dx, cy + dy
          -- a four-pointed twinkle: two bars rather than a square, so it
          -- reads as a sparkle and not as the capture's gold pip
          g.setColor(1, 1, 0.75, a)
          g.rectangle("fill", px - 1, py - 4, 2, 8)
          g.rectangle("fill", px - 4, py - 1, 8, 2)
          g.setColor(1, 1, 1, a)
          g.rectangle("fill", px - 1, py - 1, 2, 2)
        end
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  -- ...and the three stars a capture throws, which are the MASTER BALL's own
  -- particle frame on a twenty-four frame arc
  if anim.stars then
    local t = anim.stars.age / 24
    for i, d in ipairs({ { 10, 2 }, { 15, 0 }, { -10, 2 } }) do
      if (anim.stars.age + i) % 2 == 0 then
        local px = anim.x + d[1] * t
        local py = anim.y + d[2] * t - math.sin(t * math.pi) * 12
        g.setColor(1, 0.95, 0.4, 1)
        g.rectangle("fill", px - 2, py - 2, 4, 4)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Gen3Battle.draw(battle)
  local g = love.graphics
  battle:drawBattleField()
  if battle.blankForAskName then return end

  local fx = battle.fx
  local sx = (fx and fx.shakeX) or 0
  local sy = (fx and fx.shakeY) or 0
  if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
    sx = battle.frame % 4 < 2 and 2 or -2
  end
  local slide = (battle.introSlide or 0)
                * timing().BATTLE_SLIDE_PX_PER_FRAME

  -- THE PICS ARE PLACED, NOT SHUNTED.
  --
  -- Each side used to keep the Game Boy's own 160x144 placement maths and
  -- then have the whole result translated bodily into the field by a pair of
  -- reconstructed offsets.  That is a fudge on top of a rule that does not
  -- apply: Gen 1 puts the foe in a 7x7 tile slot because its screen has no
  -- platforms to stand on, and Emerald's does.  So the offsets are gone and
  -- BattleState asks Gen3Battle.picPlacement instead, which measures the
  -- platforms out of the cartridge's own battle background.
  --
  -- ...AND THE REGION DOES NOT SURVIVE EITHER.
  --
  -- Reported from play, with a screenshot: "there seems to be a smaller box
  -- that's obscuring my pokemon", and then exactly what it was -- "its
  -- cutting him in half when i zoom in as if theres a smaller viewport just
  -- for the battle sprites".  That is precisely what this was: a scissor
  -- around the pics layer and nothing else, which is why only the two
  -- Pokemon were ever cut while the panels and the text were whole.
  --
  -- What it was for was "so nothing reaches the message window", and on THIS
  -- layout that job is already done twice over: drawTextArea runs after this,
  -- and Emerald's message strip is an opaque panel out of the cartridge (a
  -- cache without one falls back to Font.drawBox, which is opaque too).  A
  -- pic that reaches under it is covered, not shown.
  --
  -- And the scissor is in the DRAW TARGET's pixels, which are only the
  -- battle's own 240x160 while this engine owns the frame.  A mod that
  -- composes the battle into a surface of its own size -- a 3D field, which
  -- is what the report is from -- gets a 240x120 rectangle cut out of the
  -- top-left corner of something much bigger, and the sprite is sheared
  -- wherever that line falls.  The redundant clip was the whole bug.
  --
  -- `wideRegion` STAYS.  It is not about this scissor: it tells
  -- drawBattlerPic not to apply the GAME BOY's per-side tile windows (80x96
  -- and 88..160) during a displacement effect, and those windows describe a
  -- 160x144 screen that this layout is not.
  -- ACID ARMOR's monbg copy is a priority-2 BG.  It sits behind ordinary
  -- priority-2 OBJ battlers, so draw that copied layer before the pic pass;
  -- BattleState suppresses only the attacker-side OBJ sprites that monbg moved
  -- into BG1/BG2.
  if battle.drawGen3MonBg then battle:drawGen3MonBg("pre") end
  battle.wideRegion = true
  local composited, residual = Gen3Battle.drawMoveOamObjects(battle, slide, sx, sy)
  if not composited then
    battle._gen3OamResidual = residual
    battle:drawPicsLayer(slide, sx, sy, nil, true)
  else
    battle._gen3OamResidual = nil
  end
  battle.wideRegion = nil

  -- MEMENTO forces every battler OBJ to priority 3 while its black copied BG
  -- remains priority 2.  The shadow therefore belongs above the Pokemon but
  -- below HUD/window layers.
  if battle.drawGen3MonBg then battle:drawGen3MonBg("post") end

  -- A battle sets rWY to 0, so the window the shakes move IS the whole
  -- screen: the HUDs and the message window travel with the pics.  The OAM
  -- animation layer stays put, as it does in the classic layout.
  local function shaken(fn)
    if sx == 0 and sy == 0 then return fn() end
    g.push()
    g.translate(sx, sy)
    fn()
    g.pop()
  end
  -- THROUGH THE BATTLE'S OWN METHODS, not the locals above.
  --
  -- Every layer of the classic screen is a BattleState method, and that is
  -- not decoration: it is the entire seam a mod has for suppressing or
  -- replacing one.  DRAMATIC_SHAPE wraps drawPicsLayer, drawHUDs,
  -- drawTextArea and drawAnimLayer by name.  This screen called three of the
  -- four as file-local functions, so on a Gen 3 battle those three wrappers
  -- never fired -- the mod's own HUD panels drew, and then the flat ones drew
  -- over them.  The methods dispatch back here (BattleState:drawHUDs and
  -- friends), so the implementation is still this file's; what changed is
  -- that there is now a door in front of it.
  shaken(function() battle:drawHUDs(slide) end)
  -- the ball rides with the pics rather than with the windows: it is thrown
  -- across the field, and a screen shake moves the field
  shaken(function() Gen3Battle.drawBall(battle) end)
  battle:drawAnimLayer()
  shaken(function() battle:drawTextArea() end)

  -- the window opening out of the middle: 1 row a side for 32 frames, then 4
  -- (BattleIntroSlide1 cases 2 and 3); nothing shows outside it
  local fi = battle.frlgIntro
  if fi and fi.t < 60 then
    local half = fi.t <= 32 and fi.t or (32 + (fi.t - 32) * 4)
    if half < 80 then
      local W, H = Gen3Battle.WIDTH, Gen3Battle.HEIGHT
      g.setColor(0, 0, 0, 1)
      g.rectangle("fill", 0, 0, W, 80 - half)
      g.rectangle("fill", 0, 80 + half, W, H - 80 - half)
      g.setColor(1, 1, 1, 1)
    end
  end

  if fx and fx.flash and fx.flash > 0 and battle.frame % 4 < 2 then
    g.setColor(1, 1, 1, 0.85)
    -- the whole SCREEN flashes, so the whole surface does
    g.rectangle("fill", 0, 0, Gen3Battle.width(battle), Gen3Battle.HEIGHT)
  end
  g.setColor(1, 1, 1, 1)
  if Runtime.wantsHook("battle.overlay") then
    Runtime.call("battle.overlay", NOOP, battle)
  end
end

-- The palette zones for this surface.  The composition resolves species
-- colours, paper shade and HP-bar colours itself, so the colourised modes take
-- the trueColor opt-out over the whole surface; the forced-mono modes still
-- want their whole-screen remap, sized to THIS surface rather than the
-- 160x144 rectangle PaletteFX.ensureZones would invent.
--
-- `width` is the surface in use: a zone list sized to the cartridge's 240
-- while the surface is wider leaves the extra columns un-remapped, which in
-- the forced-mono modes is a strip of full-colour art down one side of a grey
-- screen.  That is the same trap WideBattle.zones was written for.
function Gen3Battle.zones(width)
  local w = math.floor(tonumber(width) or Gen3Battle.WIDTH)
  if w < Gen3Battle.WIDTH then w = Gen3Battle.WIDTH end
  w = math.floor(w / 8) * 8
  local h = Gen3Battle.HEIGHT
  if monoMode() then
    return { PaletteFX.zone(PaletteFX.GRAYS, 0, 0, w / 8 - 1, h / 8 - 1) }
  end
  return { { colors = false, x = 0, y = 0, w = w, h = h } }
end

return Gen3Battle
