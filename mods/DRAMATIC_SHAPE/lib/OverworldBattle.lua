-- Overworld battles: fights that happen on the map you were standing on.
--
-- The engine's battle is a screen: a white field with two pics on it, pushed
-- over a frozen overworld that stops drawing. This turns that white field
-- into the world -- the same terrain the free-roam mode extrudes, shot from
-- a placed over-the-shoulder camera at a clear patch of ground nearby --
-- while leaving the battle ITSELF alone. Every pic, HUD, HP bar, move
-- animation, faint slide and text box is the engine's own, drawn in the
-- engine's own order. What changes is what is behind them, and where the two
-- pics stand.
--
-- The sequence, from the moment something picks a fight:
--
--   1. the overworld cast is culled -- every NPC vanishes, so the wipe
--      plays over an empty map and no bystander is left standing in the
--      arena shot
--   2. the engine's own transition wipes the screen (untouched: it is the
--      right wipe, picked by the right three bits)
--   3. the battle draws over a live, window-resolution render of the arena,
--      with each mon PINNED to the cell it is standing on, the camera
--      drifting slowly enough to read as parallax, and a depth-of-field pass
--      holding the slab of world the two of them occupy sharp
--   4. the battle ends, the cast comes back, and the player is exactly
--      where they were standing
--
-- WHAT DOES NOT MOVE. The arena is where the CAMERA goes, not where the
-- player goes: nothing here writes a cell, a facing, a flag or a warp. A
-- real warp would have to survive trainer sight-lines, post-battle
-- dialogue, the blackout path and every script that assumes the player is
-- where it left them -- and it would have to put them back afterwards.
-- Moving the camera buys the whole shot and owes nothing back.
--
-- The feature declines cleanly rather than half-working: no depth support,
-- no open ground on the map, the row switched off, or a mesh still building
-- all end at the same place, which is the battle screen the engine has
-- always drawn.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local BattleArena = V.require("BattleArena")
local BattleCam = V.require("BattleCam")
local BattleScene = V.require("BattleScene")
local BattleDOF = V.require("BattleDOF")
local BattleHud = V.require("BattleHud")
local BattlePics = V.require("BattlePics")
local Voxel3D = V.require("Voxel3D")
local ChunkMesher = V.require("ChunkMesher")

local OverworldBattle = {}

-- DS_BATTLE_DEBUG=1 logs what the HUD's brightness probe is reading, once a
-- second, which is how the glyph flip is checked from a shot run. Read
-- through pcall: the loader's sandbox does not hand a mod `os`, and a
-- diagnostic must never be the reason the mod fails to load.
local DEBUG = select(2, pcall(function() return os.getenv("DS_BATTLE_DEBUG") end))
if DEBUG == nil or DEBUG == false then DEBUG = nil end

OverworldBattle.KEY = "battles"
OverworldBattle.LABEL = "3D-BTL"

-- On by default: a mod whose headline is "the world in 3D" should not need
-- the player to go and find the switch before the world shows up in a
-- battle. ON is first, so it is also what an unreadable stored value falls
-- back to.
OverworldBattle.setting = ModSetting.new(OverworldBattle.KEY,
                                         OverworldBattle.LABEL,
                                         { true, false }, { "ON", "OFF" })

-- Whether the VR row is ON -- read lazily, because VR requires modules
-- that sit above this one. While it is, this mode stops being optional:
-- the headset's battle seat, the pokedex screen and the effects plane
-- all assume a fight standing on the world, and a white-field battle
-- inside a headset is exactly the flat screen VR exists to replace.
local function vrOn()
  local ok, vr = pcall(V.require, "VR")
  return ok and vr and vr.enabled and vr.enabled() or false
end

function OverworldBattle.enabled()
  if vrOn() then return true end
  return OverworldBattle.setting:get() and true or false
end

-- ------- BACK SPRITES: the player's own mon stays on the menu
--
-- The staged shot stands BOTH mons on the map, which is the mode's whole
-- claim -- but it costs the one piece of framing Gen 1 is most recognisable
-- by: your own Pokemon, seen from behind, sitting on top of the battle menu
-- with its feet on the box. That silhouette is the series' shot.
--
-- So BACK SPRITES is offered as a middle setting rather than a compromise
-- imposed on everyone. With it on the foe is still geometry standing on its
-- tile at the far end of the arena, and the player's side goes back to being
-- the GB's own flat back pic in the GB's own slot: same art, same 2x, same
-- feet on row 96.
-- Nothing else about the shot moves -- the arena, the camera and the drift are
-- solved exactly as they were, so the foe stands where it always stood and the
-- player's cell is simply empty ground in the foreground.
--
-- OFF by default: what the mode advertises is the pair of them out there.
OverworldBattle.BACK_KEY = "battleBack"
OverworldBattle.BACK_LABEL = "BACK SPRITES"

OverworldBattle.backSetting = ModSetting.new(OverworldBattle.BACK_KEY,
                                             OverworldBattle.BACK_LABEL,
                                             { false, true }, { "OFF", "ON" })

-- Gated on 3D-BTL rather than read alone: with staged battles off there is no
-- staged shot for a back pic to be pinned in FRONT of, and the engine's own
-- battle screen already draws exactly this. And held OFF under VR: the
-- headset stands both mons on the world -- a flat back pic pinned to the
-- 2D frame would keep your own mon off the arena the battle seat looks at.
function OverworldBattle.backPinned()
  if not OverworldBattle.enabled() then return false end
  if vrOn() then return false end
  return OverworldBattle.backSetting:get() and true or false
end

-- Whether a pic is the one drawn in the GB's own slot with its feet on the
-- text box, rather than geometry standing out on the map.
--
-- Exactly the player's side under BACK SPRITES -- its mon, or the trainer back
-- that holds the slot until "Go!" -- because that is the only pic this mod
-- ever leaves flat (see drawPicsLayer below). The foe is a billboard on its
-- tile whichever mode is on, and with the mode off the player's side is one
-- too, so both of those keep the open bottom that lets the arena through a
-- stride. What the answer buys is in BattlePics: a pic on the box has nothing
-- behind its lowest row, so its bottom edge seals.
-- Read by TRUTHINESS rather than against nil, because sideTexture blanks the
-- side it is not rendering by setting the field to FALSE (see OFF) and holds
-- it that way for the whole render -- during which the pic layer runs, and
-- picImage asks this. A nil test passes a `false` straight through to the
-- index below, and the error comes out of sideTexture into the pcall that
-- calls it: the foe's billboard is dropped for the frame and the Pokemon
-- simply is not there.
function OverworldBattle.pinnedPic(battle, img)
  if not (battle and img) then return false end
  if not OverworldBattle.backPinned() then return false end
  if img == battle.playerBackPic then return true end
  local player = battle.player
  return (player and img == player.sprite) and true or false
end

-- ------- both mons face you
--
-- Standing on a map, seen from in front, a Pokemon showing you its BACK is
-- wrong twice over: it is turned away from the camera that is looking at it,
-- and the back pics are a different, smaller drawing made for a slot the
-- player never really sees. So the player's side asks for the FRONT pic too,
-- through the engine's own pokemon.sprite hook -- the seam that exists for
-- exactly this, so no battle code has to be touched to get it.
--
-- Unless BACK SPRITES is on, the setting that asks for the back pic back:
-- that mon is drawn in its own slot on the menu, seen from behind, and the
-- front art would be it turned round to face the player it belongs to.
--
-- Answered BEFORE a battle exists, because the battler is built before the
-- battle is pushed. So it cannot ask whether this fight is staged; it asks
-- whether one on this map WOULD be -- the row is on, the 3D pass is
-- available, and the map has an arena -- which is the same question with the
-- same answer a moment later. Cached per map, because the arena search walks
-- the whole grid and this runs once per battler.
local staged = { mapId = nil, ok = false }

function OverworldBattle.wantsFront()
  if not OverworldBattle.enabled() then return false end
  if OverworldBattle.backPinned() then return false end
  if not Voxel3D.available() then return false end
  -- required here rather than through the file's own helper: this runs
  -- while a battler is being built, which is before that helper is defined
  local g = require("src.core.Game")
  local ow = g and g.overworld
  if not (ow and ow.map and ow.player) then return false end
  if staged.mapId ~= ow.map.id then
    local ok, arena = pcall(BattleArena.find, ow.map,
                            ow.player.cellX, ow.player.cellY,
                            ow.player.surfing)
    staged = { mapId = ow.map.id, ok = (ok and arena) and true or false }
  end
  return staged.ok
end

-- ------- where the engine's own pics stand
--
-- The GB draws the player's back pic with its feet on the text box at row 96
-- and its 7x7-tile slot centred on x=40, and the enemy's front pic
-- bottom-aligned in a 7x7 slot centred on x=124 ending at row 56. Those two
-- points are the pics' FEET, they hold for every species at every scale (the
-- engine's placement helpers pin the bottom edge and the centre), and they
-- are what BattleCam is solved to put the two arena cells under.
--
-- Which makes the pin a subtraction: whatever the drift has done to the
-- camera this frame, each pic moves by its own cell's projected position
-- minus its anchor. At the middle of the drift that is zero.
OverworldBattle.ANCHOR = {
  player = { 26, 96 },
  enemy = { 124, 56 },
}

-- ------- how big a mon is
--
-- Not a decision made here. A pic is drawn at its own integer scale -- 1x for
-- a 56px front pic, 2x for a 32px back one -- because that is the only way it
-- keeps every pixel the artist drew, and the CAMERA is solved so that one
-- overworld square is that big on screen (see BattleCam). The mon fits its
-- tile because the tile was sized to the mon, not the other way round.
OverworldBattle.SLOT_W = { front = 56, back = 32 }

-- The two HUD blocks, as the pixel spans DrawEnemyHUDAndHPBar and
-- DrawPlayerHUDAndHPBar actually reach. Neither overlaps its side's pic at
-- the anchors above.
OverworldBattle.HUD_RECT = {
  enemy = { 8, 0, 80, 32 },
  player = { 72, 56, 88, 40 },
}

-- ------- the box at the bottom, on the same glass
--
-- The HUDs got frosted panels because black glyphs on grass are not readable.
-- The battle's text box and its menu had the opposite problem and the same
-- cause: they are drawn as an OPAQUE WHITE slab with a black border, which was
-- the field's own colour when the field was white and is a sheet of paper laid
-- over the bottom third of the diorama now that it is not.
--
-- So the box gets exactly what the HUDs get: the world behind it, blurred to
-- frosted glass and laid back down translucent, with the border and the text
-- drawn over it unchanged, and the same brightness verdict flipping the ink
-- when the ground under it is dark. Only the FILL is taken away -- every glyph
-- the engine draws inside the box is still the engine's own, in its own place.
--
-- These are the boxes BattleState:drawTextArea lays down, as GB-frame rects.
-- READ-ONLY duplicates of that function's own branches, the same kind of
-- mirror hudLive is and for the same reason: there is no seam that reports "a
-- move menu is up", and glass has to go down BEFORE the box that sits on it.
-- The worst a future engine change can do is frost a rectangle nothing lands
-- on, or leave a box unfrosted -- never break a battle.
--
-- Each rect stops where the next one starts rather than overlapping it: two
-- panels over the same pixels would frost it twice and leave a visible step
-- along the seam.
OverworldBattle.TEXT_RECT = {
  box = { 0, 96, 160, 48 },       -- Font.drawBox(0, 12, 20, 6), always
  -- moveSelect's TYPE/PP box, Font.drawBox(0, 8, 11, 5), trimmed to the rows
  -- above the box above -- its last tile row sits inside that one
  moves = { 0, 64, 88, 32 },
  -- mimicSelect's copy menu, Font.drawBox(0, 7, 16, 6), trimmed the same way
  mimic = { 0, 56, 128, 40 },
}

-- How far apart the two anchors are: the spacing every move animation was
-- authored against, and so the yardstick the live pair is measured with.
OverworldBattle.ANCHOR_SPAN = math.sqrt(
  (OverworldBattle.ANCHOR.enemy[1] - OverworldBattle.ANCHOR.player[1]) ^ 2
  + (OverworldBattle.ANCHOR.enemy[2] - OverworldBattle.ANCHOR.player[2]) ^ 2)

-- The effects layer's scale for this shot: how far apart the two mons
-- actually are on screen, over how far apart the slots they were authored
-- for were. Clamped hard at both ends -- an effect is pixel art and a wild
-- factor is worse than a slightly wrong one -- and held at exactly 1 when
-- the marks coincide, which is a projection about to degenerate rather
-- than a pair that has genuinely closed up.
OverworldBattle.ANIM_SCALE_MIN = 0.5
OverworldBattle.ANIM_SCALE_MAX = 2.0

-- `anchors` is the pair the effects were authored against on THIS layout --
-- the Game Boy's 98 GB pixels apart, Emerald's 170 -- so a hit still lands on
-- the mon it was aimed at on either screen. Absent, the Game Boy's, which is
-- the identical arithmetic (and the identical float) ANCHOR_SPAN was.
function OverworldBattle.animScale(shot, px, py, anchors)
  if not (shot and shot.enemy and px and py) then return 1 end
  local dx, dy = shot.enemy[1] - px, shot.enemy[2] - py
  local span = math.sqrt(dx * dx + dy * dy)
  if not (span > 1) then return 1 end
  local a = anchors or OverworldBattle.ANCHOR
  local base = math.sqrt((a.enemy[1] - a.player[1]) ^ 2
                         + (a.enemy[2] - a.player[2]) ^ 2)
  if not (base > 1) then base = OverworldBattle.ANCHOR_SPAN end
  local k = span / base
  return math.max(OverworldBattle.ANIM_SCALE_MIN,
                  math.min(OverworldBattle.ANIM_SCALE_MAX, k))
end

function OverworldBattle.textRects(battle)
  if not battle or battle.blankForAskName then return {} end
  -- the layout's own strip, not the Game Boy's (OverworldBattle.geometry,
  -- defined below beside snapRects -- resolved at call time, so the order in
  -- the chunk does not matter)
  local r = OverworldBattle.geometry(battle).textRect
  local out = { box = r.box }
  -- moves / mimic are the Game Boy's second rectangle further up the screen.
  -- Emerald has ONE strip and publishes no such rect, so nothing is frosted
  -- there rather than a slab of glass being laid over open arena.
  if battle.phase == "moveSelect" then
    if r.moves then out.moves = r.moves end
  elseif battle.phase == "mimicSelect" then
    if r.mimic then out.mimic = r.mimic end
  end
  return out
end

-- ------- the HUDs, out at the window's own edges
--
-- The battle screen is 160x144 in the MIDDLE of the window and the world is the
-- whole of it. That left both HUD blocks huddled together in the middle of the
-- frame with map showing on either side of them, which reads as a Game Boy
-- screenshot pasted over a diorama rather than as the diorama's own furniture.
--
-- So each block is snapped to its own side: the foe's to the left edge of the
-- window, the player's to the right. Nothing about either block changes -- same
-- tiles, same size, same rows, drawn by the engine's own DrawEnemyHUDAndHPBar
-- and DrawPlayerHUDAndHPBar -- only where the pair sits. On a window the shape
-- of the GB screen there is nowhere to go and the snap is a no-op.
--
-- They cannot simply be MOVED there: the engine draws them into the 160x144 UI
-- canvas and everything outside it is clipped away. So the layer is rendered to
-- a texture and composited into the WORLD image instead, which is the one
-- surface in this mode that covers the whole window.

-- The rows each block is cut out of, full width. Generous on purpose:
-- AnimationShakeEnemyHUD nudges the foe's block sideways, a long name reaches
-- further than the panel does, and the pokeball rows and the safari ball count
-- belong to the block whose rows they sit in. Nothing drawHUDs draws lies
-- outside rows 0-96, and the two bands split that between them.
OverworldBattle.HUD_BAND = {
  enemy = { 0, 0, 160, 48 },
  player = { 0, 48, 160, 48 },
}

-- Where each block lands, in WORLD-canvas pixels: the panel rect the frosted
-- glass is cut to, plus the x its band is blitted at.
--
-- The foe's panel starts at the window's left edge and the player's ends at the
-- right one. The vertical is untouched, so both stay on the rows the GB put
-- them on. A band's own origin sits outside the window by the panel's inset --
-- the couple of pixels a HUD shake can push past the edge are clipped there,
-- which is the whole cost of the snap and is invisible.
-- ------- ONE SOURCE FOR WHERE EVERYTHING IS
--
-- Every constant above -- the two ANCHORs, the HUD_RECTs, the HUD_BANDs and
-- the TEXT_RECTs -- is a READ-ONLY MIRROR of the Game Boy battle screen, and
-- each was copied out of the drawing code it describes. That was the only
-- screen there was.
--
-- It is not any more. A Gen 3 cache fights on Emerald's own 240x160 surface,
-- where the foe's status box is at (8,8) and not (8,0), the player's is at
-- (112,64) and 15 tiles wide rather than 11, the two mons stand 170 pixels
-- apart rather than 98, and the message strip is one full-width band at row
-- 120 with no separate TYPE/PP panel above it at all. Composing that screen
-- from the numbers below put the frosted glass beside the blocks it was for,
-- laid a slab of it over open arena where a move menu was never going to be,
-- and -- because the scratch canvases were sized to match -- cut 68% off the
-- player's status block and 60% off the message box.
--
-- The engine PUBLISHES all of it (BattleState:layoutGeometry, added for
-- exactly this mod: see the "WHERE EVERYTHING IS, PUBLISHED" block in
-- src/battle/BattleState.lua and its twin in src/battle/Gen3Battle.lua), so
-- the numbers are asked for rather than assumed and a layout that moves
-- anything moves it in ONE place. What comes back on a Game Boy battle is
-- BattleState.CLASSIC_GEOMETRY, which is these tables literally -- so Gen 1,
-- Gen 2 and Prism take exactly the numbers they always took.
--
-- The fallback is the tables themselves rather than an error: an engine
-- without the seam (an older build, another fork) still gets the Game Boy
-- battle it always got instead of no battle at all.
OverworldBattle.CLASSIC_GEOMETRY = {
  width = 160, height = 144,
  anchor = OverworldBattle.ANCHOR,
  hudRect = OverworldBattle.HUD_RECT,
  hudBand = OverworldBattle.HUD_BAND,
  textRect = OverworldBattle.TEXT_RECT,
}

function OverworldBattle.geometry(battle)
  if battle and type(battle.layoutGeometry) == "function" then
    local ok, g = pcall(battle.layoutGeometry, battle)
    -- every field this file reads, checked before any of it is trusted: a
    -- half-populated table would be worse than the fallback, because it
    -- would fail one rect at a time in the middle of a fight
    if ok and type(g) == "table"
       and type(g.width) == "number" and type(g.height) == "number"
       and type(g.anchor) == "table" and g.anchor.player and g.anchor.enemy
       and type(g.hudRect) == "table" and g.hudRect.enemy and g.hudRect.player
       and type(g.hudBand) == "table" and g.hudBand.enemy and g.hudBand.player
       and type(g.textRect) == "table" and g.textRect.box then
      return g
    end
  end
  return OverworldBattle.CLASSIC_GEOMETRY
end

-- Whether this layout's windows bring their own background with them.
--
-- The Game Boy's do not: its HUD is black glyphs on whatever is behind them,
-- which over a route is unreadable, which is why the frosted panels and the
-- ink flip exist at all. Emerald's status box is the cartridge's own opaque
-- cream sprite and its message strip the cartridge's own window frame -- so
-- glass behind them is invisible work and the flip is actively wrong: it
-- repaints black glyphs white ON CREAM, which is how the foe's name, the Lv
-- and the HP and EXP bars came out blank. The engine says which it is
-- (Gen3Battle.geometry's `opaqueWindows`); absent is the honest answer for
-- the Game Boy layouts, whose windows really are transparent.
function OverworldBattle.opaqueWindows(battle)
  return OverworldBattle.geometry(battle).opaqueWindows and true or false
end

-- ------- WHERE THE TWO BANDS ARE CUT
--
-- snapHUDs blits the HUD layer as TWO horizontal bands at TWO DIFFERENT x
-- offsets -- the foe's out to the left edge of the window, the player's out to
-- the right. That is the whole point of the snap, and it has a consequence
-- nothing states: any drawing that CROSSES the cut is torn in half and one
-- half is thrown to the other side of the window.
--
-- IN-GAME: a wild WURMPLE on a Hoenn route, the player's ABSOL. The published
-- cut is FIELD_BOTTOM / 2 -- row 60 (src/battle/Gen3Battle.lua) -- which is a
-- BATTLEFIELD number: it says where the ground ends, not where the sprites
-- are. Emerald's player healthbox is the cartridge's own sprite and its art
-- reaches ABOVE the rectangle the layout states for it (hudRect.player starts
-- at row 64, only four rows below the cut). Measured off the reported frame:
-- the box's olive lid -- two whole rows of it -- came out 20 GB pixels to the
-- LEFT of the rest of the box, hanging over open world, with the cream body
-- starting below where the lid ended. That is the report "a weird misaligned
-- piece at the top of the player's HUD", and the displacement is exactly
-- bandX.player - bandX.enemy, which is the signature of this cut and of
-- nothing else in the pipeline: the engine draws that box with ONE
-- love.graphics.draw call and one call cannot tear.
--
-- So the cut is moved OFF the blocks. It stays exactly where the layout put
-- it whenever it already clears both blocks by a whole tile row -- 8 pixels,
-- the granularity every one of these boxes is composed in, and the least
-- clearance that means anything on this hardware. Where it does not, it goes
-- to the MIDDLE of the gap between the two blocks, which is the furthest from
-- both that any cut can be, rather than to a tuned offset.
--
-- GEN 1 / GEN 2 / PRISM ARE UNTOUCHED BY CONSTRUCTION: their cut is row 48
-- with the foe's block ending at 32 and the player's starting at 56 -- 16
-- pixels of clearance above and 8 below -- so the test passes and the
-- published table is handed straight back, the same table, not a copy.
-- Emerald's is row 60 with the blocks at 40 and 64: 20 above, 4 below, so the
-- cut moves to row 52 and clears the healthbox's own art (whose top the frame
-- puts at row 58) by six rows.
OverworldBattle.BAND_CLEARANCE = 8      -- one tile row

function OverworldBattle.bands(geom)
  local band, rect = geom.hudBand, geom.hudRect
  local e, p = band.enemy, band.player
  -- only the shape this function understands: two full-width bands meeting on
  -- one row. Anything else is handed back untouched rather than guessed at.
  if e[2] + e[4] ~= p[2] then return band end
  local cut = p[2]
  local eb = rect.enemy[2] + rect.enemy[4]     -- where the foe's block ends
  local pt = rect.player[2]                    -- where the player's begins
  if not (pt > eb) then return band end        -- blocks overlap: no cut is safe
  local m = OverworldBattle.BAND_CLEARANCE
  if (cut - eb) >= m and (pt - cut) >= m then return band end
  local mid = math.floor((eb + pt) / 2)
  if mid == cut then return band end
  return {
    enemy  = { e[1], e[2], e[3], mid - e[2] },
    player = { p[1], mid, p[3], (p[2] + p[4]) - mid },
  }
end

-- ------- where each block lands (unchanged in shape; the rects it cuts are
-- the layout's own now)
function OverworldBattle.snapRects(shot, battle)
  local s = shot.scale
  local hud = OverworldBattle.geometry(battle).hudRect
  local e, p = hud.enemy, hud.player
  local ex = -e[1] * s                       -- foe: panel's left edge to 0
  local px = shot.pw - (p[1] + p[3]) * s     -- player: right edge to the far side
  local rects = {
    enemy = { ex + e[1] * s, shot.ly + e[2] * s, e[3] * s, e[4] * s },
    player = { px + p[1] * s, shot.ly + p[2] * s, p[3] * s, p[4] * s },
  }
  return rects, { enemy = ex, player = px }
end

-- A rect measured in the GB frame, in WORLD-canvas pixels: where the letterbox
-- blit will actually put it. The text box has not moved anywhere -- it is drawn
-- where it always was -- but its glass is laid into the world image alongside
-- the HUDs' (see snapHUDs), which is the surface that reaches the screen a
-- pixel to a pixel rather than magnified out of a 160x144 canvas.
local function toWorld(rect, shot)
  local s = shot.scale
  return { shot.lx + rect[1] * s, shot.ly + rect[2] * s,
           rect[3] * s, rect[4] * s }
end

-- ------- the live battle
--
-- nil when no overworld battle is running. Never more than one: battles do
-- not nest.
local session = nil

local function isIOS()
  return love.system and love.system.getOS and love.system.getOS() == "iOS"
end

local function game()
  return require("src.core.Game")
end

-- Whether this frame's HUDs went out to the window's edges instead of being
-- drawn in the GB frame. False whenever the composite could not be made, which
-- is what leaves the in-frame HUD as the fallback rather than no HUD at all.
local function snapped()
  return (session and session.snapped) and true or false
end

-- Put the map's cast back. Both lists are handed back by identity, so
-- anything that captured one before the battle still sees the same table.
local function restoreCast()
  if not (session and session.state) then return end
  if session.entities then session.state.entities = session.entities end
  if session.ghosts then session.state.ghosts = session.ghosts end
  session.entities, session.ghosts = nil, nil
end

-- Cull them. The player stays -- they are not an NPC, they are who the
-- battle belongs to, and Fly/surf animations and the save's own capture read
-- state.player through this list.
--
-- Only the DRAW lists are touched, and only while the overworld is frozen
-- underneath a battle: StateStack updates the top state alone, so nothing
-- walks, wanders, triggers or collides against a list that is short for
-- these frames. The originals go back at battle.ended.
local function cullCast(state)
  session.entities = state.entities
  session.ghosts = state.ghosts
  state.entities = { state.player }
  state.ghosts = {}
end

-- ------- one right battle layout
--
-- Everything this file composes is measured in the GB's own 160x144 frame: the
-- two ANCHORs the arena camera is solved to put a cell under, the HUD_RECTs
-- the frosted panels are cut to, and the full-frame white intercepted to let
-- the world through. BATTLE LAYOUT's WIDE lays the same battle out on a
-- 304x144 surface (src/battle/WideBattle.lua), which moves every one of those
-- -- the mons would stand where no camera was solved for them, and the panels
-- would land beside the HUDs they are supposed to be under.
--
-- So while a fight can be staged on the map there is one right answer, and it
-- is SET rather than worked around. The engine reads the option live
-- (BattleState:isWideBattleLayout is asked per frame, and Renderer asks the
-- top state for its surface the same way), so writing it here lands on the
-- battle being pushed as well as every one after it.
--
-- This is the last line rather than the first: the OPTIONS menu takes the row
-- off the list and pins the value while 3D-BTL is on (see main.lua), so a
-- player is never offered a switch that gets reverted under them. What reaches
-- here is a value that arrived some other way -- a save written before the mod
-- was installed, the mod manager's own page, another mod.
function OverworldBattle.forceOG(g)
  g = g or game()
  local opts = g and g.save and g.save.options
  if not opts or opts.battleLayout ~= "wide" then return false end
  opts.battleLayout = "og"
  if g.writeOptions then pcall(g.writeOptions, g) end
  return true
end

-- Stage a battle triggered from `state`, if this mode can. Returns true when
-- a session started -- which is also the only case where anything visible
-- changes, so a map with no room for an arena plays exactly the vanilla
-- battle it always did, cast and all.
function OverworldBattle.begin(state, battle)
  OverworldBattle.finish()
  if not OverworldBattle.enabled() then return false end
  if not (state and state.map and state.player) then return false end
  if not Voxel3D.available() then return false end

  local ok, arena = pcall(BattleArena.find, state.map,
                          state.player.cellX, state.player.cellY,
                          state.player.surfing)
  if not (ok and arena) then return false end

  -- the fight is staged from here on, so the layout it is composed for is not
  -- optional any more (see forceOG)
  OverworldBattle.forceOG()

  session = { state = state, arena = arena, battle = battle, shot = nil,
              armed = false, token = "-" }
  cullCast(state)
  BattleCam.reset()
  return true
end

-- The fallback entry point: a battle that arrived without going through the
-- overworld's own pushBattle (a link battle, a script pushing a BattleState
-- directly). Nothing visible depends on the cull for those -- the wipe has
-- already been and gone -- but the arena still has to be picked.
function OverworldBattle.ensure(battle)
  if session then
    -- a battle pushed through the overworld reaches begin() before it is
    -- built far enough to draw; battle.started is where it is finished
    if battle and not session.battle then session.battle = battle end
    return
  end
  local g = game()
  local ow = g and g.overworld
  if ow and ow.map then OverworldBattle.begin(ow, battle) end
end

-- The arena this battle is staged on, or nil. Read by the shot driver so a
-- screenshot can be labelled with the ground it was taken on.
function OverworldBattle.arena()
  return session and session.arena or nil
end

function OverworldBattle.finish()
  if not session then return end
  restoreCast()
  session = nil
  Voxel3D.camera = nil
end

-- ------- per-frame
--
-- Driven from the voxel pipeline's update hook, which the engine ticks every
-- frame regardless of which state is on top -- including the frames the
-- transition wipe covers, which is what gets the arena's meshes built before
-- the first battle frame needs them.
--
-- The scene is rendered HERE rather than inside the battle's draw, because
-- update runs with no canvas bound: a 3D pass that binds a depth target and
-- unbinds to the screen when it is done cannot do that in the middle of
-- someone else's frame without putting the frame back itself.
function OverworldBattle.update(dt)
  if not session then return end

  local g = game()
  local top = g and g.stack and g.stack:top()
  local ow = g and g.overworld
  -- A battle that ended without saying so (a script tearing the state down,
  -- a path that never emits battle.ended) would otherwise leave the cast
  -- culled for good. Armed only once something has actually covered the
  -- overworld, because begin() runs while the overworld is still on top.
  if top ~= nil and top ~= ow then
    session.armed = true
  elseif session.armed then
    OverworldBattle.finish()
    return
  end

  -- Whether the shot is the player's to steer at all. BACK SPRITES pins
  -- their own mon to the GB's slot on the menu while the foe stands out on
  -- the map, and there is no angle that half-framed, half-solid
  -- composition survives -- so under it the camera holds the shot the rig
  -- was solved for (the slow drift aside, which was always there). Polled
  -- per frame rather than latched at battle start: the row is reachable
  -- from the mod manager's page mid-session.
  BattleCam.steerable = not OverworldBattle.backPinned()
  -- the right stick, read as a rate before the rig is built from it: the
  -- wheel, the keys, the mouse and a drag all arrive as events and have
  -- already landed, but a stick is a HELD position and only a tick can
  -- turn it into travel (CamControl, which owns every one of those inputs)
  pcall(V.require("CamControl").tick, dt)
  BattleCam.update(dt)
  -- the battle only exists once it has been pushed; a session opened at
  -- pushBattle time has it, one opened from battle.started was handed it
  session.battle = session.battle or (top ~= ow and top or nil)
  -- the world pass is hidden behind the battle, so mesh builds get the wide
  -- slice: nothing visible can hitch on them
  ChunkMesher.pump(true)

  -- The mons' textures are rendered HERE, with no canvas bound, for the same
  -- reason the scene is: the pics layer binds its own targets, and doing that
  -- inside somebody else's frame means putting the frame back afterwards.
  local okTex, textures = pcall(OverworldBattle.textures, session.battle)
  if not okTex then textures = nil end
  -- stashed for the VR eye pass, which stands these same pics on the map
  -- in ITS view of the world (VoxelScene's eyes path). Stashed HERE
  -- because rendering them binds canvases, which the eye pass -- mid-scene
  -- when it wants them -- must never do; reading a stashed canvas is free.
  session.textures = textures
  -- and the move-animation layer, for the same eyes -- rendered only
  -- while a headset is actually watching, because only the VR world
  -- pass draws it (the flat screen has the animations in-frame already)
  session.animTex = nil
  local okVR, vrOn = pcall(function()
    local vr = V.require("VR")
    return vr.active and vr.active() or false
  end)
  if okVR and vrOn and session.battle then
    local okA, anim = pcall(OverworldBattle.animTexture, session.battle)
    if okA then session.animTex = anim end
  end
  -- The stamp the sun keys on: what the two pics layers actually drew this
  -- frame (see sideTexture).  Equal to last frame's on every frame the pair
  -- is standing still, which is what lets ShadowMap.stale answer "no" and the
  -- arena's sun pass be skipped instead of redrawn -- the free-roam mode's own
  -- behaviour, which a per-frame counter had been defeating.
  session.token = table.concat({
    textures and textures.enemy and textures.enemy.stamp or "-",
    textures and textures.player and textures.player.stamp or "-",
    (textures and textures.flash) and "F" or "-",
  }, "|")
  local ok, shot = pcall(BattleScene.render, session.state, session.arena,
                         textures, session.token)
  if not ok then
    -- One failure retires the arena for THIS battle and nothing else: the
    -- battle screen carries on as the engine's own, the free-roam pipeline
    -- this runs inside keeps rendering the overworld, and the next battle
    -- tries again. Rethrowing would hand the whole voxel mode to Pipelines'
    -- guard, which retires a pipeline for the session.
    session.shot = nil
    session.snapped = false
    session.broken = true
    V.mod.log:warn("overworld battle scene failed: %s -- this battle draws "
                   .. "on the plain battle background", tostring(shot))
    return
  end
  session.snapped = false
  if shot and shot.canvas then
    -- the depth of field is measured off the two marks: the slab in focus is
    -- the one the mons are standing in, at whatever the drift has done to
    -- where that lands
    local y1 = shot.ly + shot.player[2] * shot.scale
    local y2 = shot.ly + shot.enemy[2] * shot.scale
    local focusY, band, range = BattleDOF.bandFor(y1, y2, shot.ph)
    local okDof, blurred = pcall(BattleDOF.apply, shot.canvas,
                                 focusY, band, range)
    if okDof and blurred then shot.canvas = blurred end
    -- the frosted glass the HUDs sit on is built from the FINISHED backdrop,
    -- so a panel over a blurred far field is frosted from what is actually
    -- behind it
    pcall(BattleHud.build, shot.canvas)
    -- and then the HUDs go ON that backdrop, snapped out to the window's own
    -- edges (snapHUDs). Here rather than in the battle's draw for the same
    -- reason the scene is: it binds a canvas of its own. After the frost, so
    -- the glass is frosted from the world alone and never from the glyphs
    -- about to sit on it.
    local ios = isIOS()
    local okHud, up = false, false
    if not ios then
      okHud, up = pcall(OverworldBattle.snapHUDs, session.battle, shot)
    end
    session.snapped = (okHud and up) and true or false
    -- once per battle, not once per frame: a driver that cannot do this cannot
    -- do it sixty times a second either, and the fallback is silent and fine
    if not ios and not okHud and not session.hudWarned then
      session.hudWarned = true
      V.mod.log:warn("overworld battle HUD snap failed: %s -- the HUDs draw "
                     .. "in the battle frame this battle", tostring(up))
    end
  end
  session.shot = shot
end

-- The finished shot for this frame, or nil when there is none and the battle
-- should draw the way it always did.
function OverworldBattle.shot()
  if not session or session.broken then return nil end
  local s = session.shot
  if s and s.canvas then return s end
  return nil
end

-- The staged fight's WORLD-side pieces, for a pass that stands the mons in
-- its own view of the map rather than in the arena's composed shot -- the
-- VR eyes. Returns the two cards as BattleScene.monCards builds them (yawed
-- toward whatever Voxel3D.eye is at CALL time, so a per-eye caller gets
-- per-eye cards), the live textures table (for the hit-flash flag), and the
-- token the shadow signature keys on. nil while nothing is staged, the
-- arena is broken, or the pics have not been rendered yet.
function OverworldBattle.worldCards()
  if not (session and session.arena and not session.broken) then return nil end
  local tex = session.textures
  if not tex then return nil end
  local host = (session.state and session.state.map) or nil
  if not host then return nil end
  local groundY = BattleScene.groundY(host, session.arena)
  return BattleScene.monCards(session.arena, groundY, tex), tex, session.token
end

-- The live session's BATTLE STATE, once the pushed battle has been met
-- (session.battle fills in from the stack in update). The VR quad reads
-- it to tell "the battle screen is on top" from "a menu is over the
-- battle" -- the UI-only panel is right for the first and wrong for the
-- second. nil with no session, a broken one, or a battle not yet pushed.
function OverworldBattle.battle()
  if not (session and not session.broken) then return nil end
  return session.battle
end

-- The move-animation layer as a texture: the engine's own drawAnimLayer,
-- rendered UNSHIFTED (slot-authored coordinates) into a GB-sized
-- transparent canvas of its own. This is what stands the effects up in
-- the VR eyes' world -- see worldAnim below -- the same move the pics
-- made through sideTexture: let the engine draw what it always draws,
-- catch it on a canvas, stand the canvas in the scene.
local animLayer = nil
-- the engine's own drawAnimLayer, captured by install(). Declared HERE,
-- above the function that reads it: a local declared further down the
-- chunk would leave this function reading a global of the same name --
-- nil forever, and the effects silently absent from the eyes (the bug
-- this comment is the tombstone of).
local innerAnim = nil

function OverworldBattle.animTexture(battle)
  if not (innerAnim and battle) then return nil end
  if not (love.graphics and love.graphics.newCanvas) then return nil end
  if not animLayer then
    -- THE OAM AUTHORING SPACE, AND IT STAYS THERE.
    --
    -- Asked again with the Zigzagoon frame in hand, and the answer is still
    -- 160x144 -- deliberately, not by omission. Every move animation in the
    -- port is authored against the original 160-pixel OAM coordinates;
    -- Gen3Battle.drawAnimationLayer shifts a whole frame into Emerald's wider
    -- field as one rigid group (animationOffset) rather than re-authoring it,
    -- and animTexture calls the layer DIRECTLY, before any of that. So what
    -- lands in this canvas is 160-space by construction, and BattleScene.fxCard
    -- -- which maps it onto its plane -- divides by GB_W / GB_H for the same
    -- reason. Sizing it from the surface would stretch every effect.
    local ok, c = pcall(love.graphics.newCanvas,
                        BattleScene.GB_W, BattleScene.GB_H)
    if not (ok and c) then return nil end
    pcall(c.setFilter, c, "nearest", "nearest")
    animLayer = c
  end
  local g = love.graphics
  local prevCanvas = g.getCanvas()
  local ok = pcall(function()
    g.push("all")
    g.origin()
    g.setCanvas(animLayer)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    g.setColor(1, 1, 1, 1)
    innerAnim(battle, false)
    g.pop()
  end)
  if not ok then pcall(g.pop, g) end
  if prevCanvas then pcall(g.setCanvas, g, prevCanvas)
  else pcall(g.setCanvas, g) end
  return ok and animLayer or nil
end

-- The staged fight's effects, for the VR eyes: the animation layer plus
-- the plane to stand it on (BattleScene.fxCard -- anchored so a hit
-- authored at a slot lands on the mon standing in for that slot). nil
-- while nothing is staged or no layer was rendered this frame.
function OverworldBattle.worldAnim()
  if not (session and session.arena and not session.broken) then return nil end
  local tex = session.animTex
  if not tex then return nil end
  local host = (session.state and session.state.map) or nil
  if not host then return nil end
  local groundY = BattleScene.groundY(host, session.arena)
  local model = BattleScene.fxCard(session.arena, groundY,
                                   OverworldBattle.ANCHOR)
  if not model then return nil end
  return tex, model
end

-- Where the staged fight STANDS -- the arena and its floor height -- for a
-- camera that wants to look at it rather than draw it (the VR battle
-- mount). Answered as soon as the stage exists, textures or not: the
-- camera should be seated behind the fade before the first pic lands.
-- nil whenever no fight is staged on the world.
function OverworldBattle.stage()
  if not (session and session.arena and not session.broken) then return nil end
  local host = (session.state and session.state.map) or nil
  if not host then return nil end
  return session.arena, BattleScene.groundY(host, session.arena)
end

function OverworldBattle.invalidate()
  BattleDOF.invalidate()
  BattleHud.invalidate()
  BattlePics.invalidate()
end

-- ------- the battle screen's background
--
-- BattleState opens by filling 160x144 white -- that fill IS the battle's
-- background, and in the colorized pipeline it is also the BG canvas's clear
-- (nothing else clears it, so skipping it outright would ghost last frame).
-- So for the length of one draw, that one call is intercepted: on the two
-- offscreen canvases it becomes a transparent clear, so the shade-remap pass
-- composites the HUD and the text box over the arena and leaves the empty
-- field showing it; on the screen it is simply dropped, because the UI canvas
-- has already been cleared transparent for the world to show through.
--
-- Matched exactly -- fill, the full frame, at the origin, in opaque white --
-- so the text box (a 20x6 box lower down), a mon pic, an HP bar and the
-- move-animation flash (which is white at 0.85) all pass through untouched.
--
-- This is a shim over love.graphics and it is the one invasive thing here,
-- so it is scoped as tightly as it can be: installed around a single call,
-- removed on the way out including on error, and never live outside a battle
-- frame this mode is drawing.
local function withoutBackgroundFill(battle, fn)
  local g = love.graphics
  local rectangle = g.rectangle
  -- the WHOLE FRAME, whatever size that frame is this battle: Emerald's field
  -- fill and its hit flash are 240x160, and a 160x144 test let both of them
  -- straight through -- the flash whiting out the diorama, the HUD and the
  -- text box together twice a second
  local fw, fh = BattleScene.surface()
  g.rectangle = function(mode, x, y, w, h, ...)
    if mode == "fill" and x == 0 and y == 0
       and w == fw and h == fh then
      local r, gr, b, a = g.getColor()
      if r > 0.99 and gr > 0.99 and b > 0.99 then
        -- Two different full-frame whites, both replaced rather than drawn.
        --
        -- OPAQUE is the battle's background, and on the offscreen canvases it
        -- doubles as their clear, so there it becomes a transparent one.
        --
        -- TRANSLUCENT is the hit flash. Over a white field that reads as a
        -- flash; over a world it whites out the map, the HUD and the text box
        -- together. BattleScene puts it back on the mons alone.
        if a > 0.99 then
          local target = g.getCanvas()
          if target ~= nil
             and (target == battle.bgCanvas or target == battle.waveCanvas) then
            g.clear(0, 0, 0, 0)
          end
        end
        return
      end
    end
    return rectangle(mode, x, y, w, h, ...)
  end
  local ok, err = pcall(fn, battle)
  g.rectangle = rectangle
  if not ok then error(err, 0) end
end

-- ------- the box, without its paper
--
-- Font.drawBox is a white fill and then six border glyphs, and the fill is the
-- opaque slab the frosted panel underneath is there to replace. So for the
-- length of one drawTextArea the white fills are dropped and everything else
-- -- the border, the text, the cursor, the down arrow -- draws exactly as it
-- always did, over the glass instead of over paper.
--
-- Every fill drawTextArea issues is one of those: the box's own, and the two
-- eight-pixel cells MoveSelectionMenu wipes back to box white before it writes
-- the border glyphs that hardware would have overwritten. Both are opaque
-- white, both are paper, and both go.
--
-- The same shim shape as withoutBackgroundFill above, and scoped as tightly:
-- installed around a single call, removed on the way out including on error,
-- never live outside a battle frame this mode is drawing.
local function withoutBoxFill(battle, fn)
  local g = love.graphics
  local rectangle = g.rectangle
  g.rectangle = function(mode, ...)
    if mode == "fill" then
      local r, gr, b, a = g.getColor()
      if r > 0.99 and gr > 0.99 and b > 0.99 and a > 0.99 then return end
    end
    return rectangle(mode, ...)
  end
  local ok, err = pcall(fn, battle)
  g.rectangle = rectangle
  if not ok then error(err, 0) end
end

-- ------- the hour's light, on a pic that is not geometry
--
-- Everything standing in the arena goes through the voxel shader, and that
-- shader multiplies by the hour's tint: at dusk the whole diorama warms, at
-- night it goes blue, and the two mons' cards go with it because they are
-- drawn in the same pass as the ground they stand on.
--
-- A back pic pinned to the menu is not in that pass. It is the engine's own
-- flat blit over the finished shot, so it arrived at noon while the world
-- behind it was at midnight -- a mon lit by nothing in the frame.
--
-- So the tint is applied by hand, to that one draw. Every colour the pics
-- layer sets is multiplied on its way past, which is the whole of it: the
-- layer draws the pic with love.graphics.draw and LOVE multiplies by the draw
-- colour, so tinting the colour tints the pixels -- and the alpha, the faint
-- slide's fade and the blink's own colour all compose with it rather than
-- being overwritten.
--
-- What this does NOT get is the sun: the cards are shadow-mapped, so one
-- standing under a tree is darker than the tint alone, and this pic has no
-- position in the scene to be shadowed at. It carries the hour and not the
-- weather, which is the part the eye reads.
local function withTint(tint, fn, ...)
  if not tint then return fn(...) end
  local r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
  if r > 0.999 and g > 0.999 and b > 0.999 then return fn(...) end
  local gfx = love.graphics
  local setColor = gfx.setColor
  gfx.setColor = function(cr, cg, cb, ca, ...)
    if type(cr) == "table" then
      return setColor({ (cr[1] or 1) * r, (cr[2] or 1) * g, (cr[3] or 1) * b,
                        cr[4] }, cg, ...)
    end
    if cr == nil then return setColor(cr, cg, cb, ca, ...) end
    return setColor(cr * r, (cg or 1) * g, (cb or 1) * b, ca, ...)
  end
  local ok, err = pcall(fn, ...)
  gfx.setColor = setColor
  -- the layer leaves whatever colour it last set, and that one is tinted;
  -- hand the next caller plain white rather than a dimmed one
  setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
end

-- ------- the mons, as textures for the 3D pass
--
-- The two Pokemon are not composited over the world any more: they are quads
-- standing in it (see BattleBillboard). What that needs from the battle
-- screen is a TEXTURE per side -- and the honest way to get one is to let the
-- engine draw its own pics layer, unchanged, into a canvas.
--
-- So the layer is rendered twice, once per side, with the other side
-- falsified out of existence by nulling exactly the fields its branches
-- test. Everything the engine does to a pic comes along for free that way:
-- the trainer pic before the send-out, the grow-out-of-the-ball scale, the
-- faint slide, the damage blink, the squish, every SE displacement. None of
-- it is reimplemented and none of it can drift.
--
-- Two things are forced during that render. The scale, to 1, so the texture
-- carries the artwork's own pixels and the BILLBOARD does the sizing; and the
-- placement, so the pic lands centred on a known column with its feet on a
-- known row. That known point is what the quad is then hung from.
local TEX_AX, TEX_AY = 80, 96          -- forced pic centre and baseline
local TRAINER_AX, TRAINER_AY = 124, 56 -- the intro trainer pic's own slot
-- ...and the pic size that slot is the bottom-centre OF: enemyPicXY puts a
-- 7x7-tile pic at (96, 0), and (96 + 56/2, 0 + 56) is (124, 56). Named here so
-- the test that keeps the constant says why it is keeping it.
local TRAINER_PIC = 56

OverworldBattle.TEX_AX, OverworldBattle.TEX_AY = TEX_AX, TEX_AY

-- Which side is being rendered, or nil. The placement wrappers read it.
local texturing = nil

local texCanvas = {}
-- What the placement helpers actually put this side's pic at, while a texture
-- was being rendered, and the pose that was last reported for it. Read-only
-- bookkeeping: nothing downstream steers on these, they exist so a frame that
-- comes out wrong names its own cause (see the log line in sideTexture).
local placed, placeLog = {}, {}
-- Where this side's pic was OBSERVED to be drawn in its own
-- billboard canvas, as {x, y, w, h}, for the one pic that never
-- passes a placement helper (the intro trainer). Read-only
-- bookkeeping, filled by the stamp hook in sideTexture.
local drawnAt = {}
local innerPics = nil                   -- captured by install()
local innerHUDs = nil                   -- likewise, for the snapped HUD layer
-- (innerAnim, their sibling, is declared up beside animTexture, which
-- sits earlier in the chunk than this group and must see the local)

-- ------- THE BILLBOARD CANVAS IS BIG ENOUGH FOR THE LAYOUT THAT DRAWS INTO IT
--
-- IN-GAME: a wild ZIGZAGOON on a Hoenn route, drawn as a narrow vertical strip
-- -- head, ruff and forelegs -- ending in a clean vertical edge partway
-- through the body. A clean straight edge through a sprite is a canvas or a
-- scissor, never an atlas rect and never alpha.
--
-- This canvas was 160x144 because that is the frame the Game Boy's pics layer
-- draws in, and the placement helpers are overridden while a texture is being
-- rendered so the pic lands centred on TEX_AX with its feet on TEX_AY -- which
-- fits, with room to spare, for every pic this port has. What does NOT fit is
-- anything the pics layer draws that does NOT go through those two helpers,
-- and on a Gen 3 cache the layer is composing for a 240x160 surface: an
-- overlay, a second pass, a doll, a future layout's own placement, any of
-- them lands past column 160 or row 144 and is simply cut off at the canvas
-- edge with a straight edge exactly like the reported one.
--
-- So the canvas is the SURFACE the battle is laid out in, never smaller than
-- the Game Boy frame the helpers still target. On Gen 1, Gen 2 and Prism
-- BattleScene.surface() answers 160x144, so the canvas is the same 160x144 it
-- has always been and every number downstream is unchanged.
--
-- Growing it is free of consequences ONLY because monMatrix now divides by the
-- canvas's own dimensions (see the invariant proved there): a canvas pixel is
-- k world pixels whatever the canvas is, so a bigger canvas is more empty
-- margin and not a bigger Pokemon. Reallocated when the size changes, the way
-- every other canvas in this mod is, so a layout swap mid-session cannot leave
-- the old one behind.
local function texCanvasFor(side)
  local sw, sh = BattleScene.surface()
  if sw < BattleScene.GB_W then sw = BattleScene.GB_W end
  if sh < BattleScene.GB_H then sh = BattleScene.GB_H end
  local c = texCanvas[side]
  if c and c:getWidth() == sw and c:getHeight() == sh then return c end
  if c and c.release then pcall(c.release, c) end
  texCanvas[side] = nil
  local ok, made = pcall(love.graphics.newCanvas, sw, sh, { dpiscale = 1 })
  if not ok then return nil end
  made:setFilter("nearest", "nearest")
  texCanvas[side] = made
  return made
end

-- Whether this side has anything to draw at all. Mirrors drawPicsLayer's own
-- guards, so an empty canvas is never hung on a quad: a fainted, hidden or
-- not-yet-sent-out mon simply has no billboard this frame.
local function sideVisible(battle, side)
  if side == "enemy" then
    if battle.showEnemyTrainer and battle.trainerPic then return true end
    return (battle.enemy and battle.enemy.sprite and not battle.enemyHidden
            and not battle.enemySendingOut
            and not battle:fxHidden(battle.enemy)) and true or false
  end
  if battle.showPlayerBack and battle.playerBackPic then return true end
  local hide = battle.safari or battle.demo
  return (battle.player and battle.player.sprite and not hide
          and not battle.sendingOut
          and not battle:fxHidden(battle.player)) and true or false
end

-- Published, because the draw side needs the same answer: see
-- OverworldBattle.flatFallback, which asks "would the engine have drawn a pic
-- for this side?" about a side that ended up with no billboard.
OverworldBattle.sideVisible = sideVisible

local OFF = {
  enemy = { player = false, showPlayerBack = false },
  player = { enemy = false, showEnemyTrainer = false },
}

-- Render one side's pics layer into its canvas and report where the pic's
-- feet ended up, in canvas coordinates.
function OverworldBattle.sideTexture(battle, side)
  if not (innerPics and battle) then return nil end
  if not sideVisible(battle, side) then return nil end
  local canvas = texCanvasFor(side)
  if not canvas then return nil end

  local g = love.graphics
  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  -- The pic-window scissors are in the battle screen's fixed coordinates and
  -- would clip a pic that has been moved to the middle of its own canvas.
  -- There is nothing here for them to protect -- no HUD, no text box, just
  -- the one pic -- so they are switched off for the render.
  local setScissor, intersectScissor = g.setScissor, g.intersectScissor
  local getScissor = g.getScissor
  g.setScissor = function() end
  g.intersectScissor = function() end
  g.getScissor = function() return nil end

  -- ------- AND WHAT IT DREW, AS A STAMP
  --
  -- The sun has to re-cast the mons' shadows whenever a pic changes, and the
  -- only thing that ever knew whether one HAD was a counter bumped once per
  -- frame -- so the whole arena, terrain and neighbours and water and flowers,
  -- was redrawn from the light sixty times a second for two cards that spend
  -- almost every frame perfectly still.  (See BattleScene.shadowSignature; the
  -- free-roam pass has always keyed on the poses themselves and skips the sun
  -- entirely while nothing moves.)
  --
  -- What this layer draws IS a list of draw calls -- one pic, sometimes a
  -- second tinted pass over it -- so the honest test of "did the picture
  -- change" is whether that list changed.  Recorded by standing in front of
  -- love.graphics.draw for the length of the render, the same way the pic
  -- window's scissors are stood in front of just above, so nothing has to
  -- mirror which battle fields a pic happens to depend on: the idle
  -- animation's frame swap, a damage blink's alpha, an SE displacement, the
  -- faint slide's quad and a substitute doll all arrive as different draw
  -- arguments and all say so here.
  --
  -- A MINIMIZED mon is the one thing in the layer that is not a draw call --
  -- it is a run of rectangles -- and it needs no hook: its blob is the same
  -- fixed shape at the same fixed place for as long as it is up, and going
  -- into and out of it takes the pic's own draw call with it, which this
  -- sees.
  --
  -- Numbers are quantised to a sixteenth of a pixel so a float that lands one
  -- ulp apart on two frames does not read as movement.
  local stampN, stamp = 0, {}
  local realDraw = g.draw
  local realGetColor = g.getColor
  local function put(v)
    stampN = stampN + 1
    stamp[stampN] = (type(v) == "number") and math.floor(v * 16) or tostring(v)
  end
  -- ...AND WHERE IT PUT IT.
  --
  -- The intro trainer pic is the one pic in this layer that does NOT go
  -- through a placement helper: drawPicsLayer draws it straight at
  -- enemyPicXY (src/battle/BattleState.lua:7357-7359), so the override that
  -- pins every other pic to TEX_AX/TEX_AY cannot reach it and `placed` stays
  -- nil for it. Its slot was therefore ASSUMED -- TRAINER_AX/TRAINER_AY, the
  -- bottom-centre of the classic 7x7 slot for a 56x56 pic. That is exact on a
  -- Game Boy trainer and wrong for Emerald's 64x64 one, whose bottom-centre
  -- in this canvas is (128,64), eight rows lower and four columns right.
  --
  -- This hook is already standing in front of every draw the layer makes, so
  -- the rect is there to be READ rather than worked out a second time. The
  -- LAST full draw wins: a pic drawn once is that pic, and a pic drawn twice
  -- (the tinted second pass) is the same rect both times.
  --
  -- Only x and y are taken, and only when they are plain numbers -- a quad
  -- draw, a rotated draw or an origin-offset draw is left alone rather than
  -- half-understood, and the assumed slot still covers those.
  g.draw = function(drawable, ...)
    put(drawable)
    local r, gg, b, a = realGetColor()
    put(r); put(gg); put(b); put(a)
    for i = 1, select("#", ...) do put((select(i, ...))) end
    local a1, a2, a3 = ...
    if type(a1) == "number" and type(a2) == "number" and a3 == nil
       and type(drawable) == "userdata" and drawable.getDimensions then
      local okD, dw, dh = pcall(drawable.getDimensions, drawable)
      if okD and dw and dh then drawnAt[side] = { a1, a2, dw, dh } end
    end
    return realDraw(drawable, ...)
  end

  local saved = {}
  for k, v in pairs(OFF[side]) do saved[k] = battle[k]; battle[k] = v end
  placed[side] = nil
  drawnAt[side] = nil
  texturing = side

  local ok, err = pcall(function()
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    g.setColor(1, 1, 1, 1)
    innerPics(battle, 0, 0, 0)
  end)

  texturing = nil
  g.draw = realDraw
  for k in pairs(OFF[side]) do battle[k] = saved[k] end
  g.setScissor, g.intersectScissor, g.getScissor =
    setScissor, intersectScissor, getScissor
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  if not ok then error(err, 0) end

  local ax, ay = TEX_AX, TEX_AY
  local trainer = false
  -- The intro trainer pic draws itself straight into its own 7x7 slot rather
  -- than through the placement helpers, so it is hung from that slot instead
  -- -- from the slot it was OBSERVED to land in (drawnAt, recorded by the hook
  -- above), falling back to the classic slot when nothing usable was seen.
  --
  -- On a Game Boy trainer the two are the same number and this is exactly
  -- neutral: a 56x56 pic at enemyPicXY lands at (96,0), whose bottom-centre is
  -- (96+28, 0+56) = (124,56) = TRAINER_AX, TRAINER_AY. On Emerald's 64x64 one
  -- the observed bottom-centre is (128,64), which is where the card should
  -- hang and where the assumed constant does not.
  if side == "enemy" and battle.showEnemyTrainer and battle.trainerPic then
    ax, ay, trainer = TRAINER_AX, TRAINER_AY, true
    -- TRAINER_AX, TRAINER_AY IS A 56x56 PIC'S BOTTOM-CENTRE AND NOTHING ELSE.
    -- enemyPicXY puts a 7x7-tile pic at (96, 0), and (96 + 56/2, 0 + 56) is
    -- (124, 56) exactly -- which is the constant. So a pic that IS 56x56 keeps
    -- it, slide and all, and Gen 1, Gen 2 and Prism never reach the branch
    -- below; a pic that is not has a different bottom-centre and the observed
    -- one is used instead.
    local d = drawnAt[side]
    if d and not (d[3] == TRAINER_PIC and d[4] == TRAINER_PIC) then
      ax, ay = d[1] + d[3] / 2, d[2] + d[4]
    end
  elseif side == "player" and battle.showPlayerBack and battle.playerBackPic then
    trainer = true
  end

  -- ------- THE FOE'S ANCHOR IS ITS BASELINE, NOT ITS BUFFER'S BOTTOM EDGE
  --
  -- ONLY THE FRONT PIC, because only the front pic is missing a correction the
  -- engine already makes everywhere else.
  --
  -- BattleState.getImage measures every pic it decodes for GROUND PADDING --
  -- the transparent rows under the artwork -- and keeps it in imagePadBottom.
  -- backPlacement subtracts it, so the player's mon is drawn with its FEET on
  -- row 96 whatever its buffer is doing.  frontPlacement has no such argument:
  -- on the flat screen a front pic is bottom-aligned in its own 7x7 slot
  -- against a white field, and empty rows under the mon are white on white.
  --
  -- Stand that same buffer up on the map and they become daylight, on the foe
  -- alone.  A Gen 3 front pic is a 64x64 frame with the artwork placed inside
  -- it -- the cartridge's alignment lives in gMonFrontPicCoords, which this
  -- port extracts and nothing reads -- and 344 of Emerald's 379 fronts carry
  -- empty rows under the mon: a median of 8, up to 24 (Luvdisc, Wingull).
  -- Measured in the harness, Bulbasaur's fourteen put the enemy card four
  -- world pixels off the floor and its feet on GB row 41 instead of the row
  -- 56 the shot is composed around; Luvdisc's twenty-four put them on row 30
  -- with its head off the top edge, which zooming out brings back.  That is
  -- the "the enemy is floating and off the screen" report, and the player
  -- standing correctly beside it is backPlacement's pad doing its job.
  --
  -- So the same measurement is made for the foe (BattlePics.footPad, once per
  -- pic per session, by the same rule: the lowest row with any ink in it) and
  -- the anchor moves up the buffer by exactly the empty frame under the mon.
  -- A pic with none -- Gen 1 and Gen 2 art, decoded to its own tile box, and
  -- 35 of Hoenn's fronts -- answers 0 and nothing moves.
  --
  -- Not the enemy TRAINER pic: that one never goes through frontPlacement at
  -- all, it draws itself straight into its own 7x7 slot, and it is hung from
  -- that slot above.
  if side == "enemy" and not trainer then
    local pic = battle.enemy and battle.enemy.sprite
    -- the RAW sprite rather than the one picImage handed the draw: the paper
    -- fill only ever closes holes the background cannot reach, so it cannot
    -- add ink below the lowest row that already had some, and the two answer
    -- the same baseline
    local okPad, pad = pcall(BattlePics.footPad, pic)
    if okPad and type(pad) == "number" and pad > 0 then ay = ay - pad end
  end
  -- THE CANVAS'S OWN SIZE TRAVELS WITH THE TEXTURE.
  --
  -- monMatrix hangs the card off (ax, ay) measured in THESE dimensions, and it
  -- used to read GB_W / GB_H for them -- correct only while the canvas happened
  -- to be the Game Boy frame. Now the canvas says how big it is and the matrix
  -- reads that, so the two cannot drift apart again.
  local cw, ch = canvas:getDimensions()
  -- ...and the placement is stated ONCE PER POSE, because the one number that
  -- separates "the pic is off the edge of its canvas" from "the pic is where
  -- it should be and something else cut it" is where the pic actually landed,
  -- and nothing has ever said. Keyed on the stamp -- the list of draw calls the
  -- layer made -- so it prints when the pose changes and not sixty times a
  -- second, exactly like the shadow signature it is built from.
  local out = { canvas = canvas, ax = ax, ay = ay, trainer = trainer,
                cw = cw, ch = ch,
                stamp = table.concat(stamp, ",", 1, stampN) }
  if placeLog[side] ~= out.stamp then
    placeLog[side] = out.stamp
    local p = placed[side]
    V.mod.log:info("overworld battle pic: %s canvas %dx%d  placed %s  "
                   .. "anchor (%s,%s) trainer=%s",
                   side, cw, ch,
                   p and ("(%d,%d) %dx%d"):format(p[1], p[2], p[3], p[4])
                     or "NOT THROUGH THE PLACEMENT HELPERS",
                   tostring(ax), tostring(ay), tostring(trainer))
  end
  return out
end

-- Whether the hit flash is showing this frame.
--
-- Mirrors BattleState:draw's own test, because the flash is a DRAW-time
-- decision there (a counter plus the frame parity that makes it flicker) and
-- there is no seam that reports it. Read-only, so the worst a future engine
-- change can do is flash on a frame the engine would not have.
function OverworldBattle.flashing(battle)
  local fx = battle and battle.fx
  if not (fx and fx.flash and fx.flash > 0) then return false end
  return (battle.frame or 0) % 4 < 2
end

-- Both sides, or nil when neither has anything to show.
--
-- One side under BACK SPRITES: the player's mon is not standing on the map at all
-- there, it is on the menu, so it has no card to be a texture for -- and
-- nothing downstream has to know that. No billboard, and no shadow on the
-- ground under a mon that is not on it.
-- ...AND A SIDE THAT FAILS SAYS SO.
--
-- These two pcalls used to throw the reason away. That is why "the enemy
-- Pokemon is not there" was unanswerable from a screenshot: the card geometry
-- is provably innocent (it is in front of the camera, inside the near and far
-- planes, non-degenerate, and its feet land inside the window -- see
-- tests offline), the arena's floor is provably level under both cells, and
-- the billboard is drawn in the 3D pass rather than into any HUD layer -- so
-- the only thing left is that the TEXTURE was never built, and the one place
-- that knew which of the guards refused it was silent.
--
-- Once per battle, like the HUD snap's own warning and for the same reason: a
-- driver that cannot build a pic cannot build one sixty times a second
-- either, and a per-frame line would bury the log. `sideVisible` is reported
-- alongside, because "the side had nothing to show" and "the render raised"
-- are completely different faults and the fix is different for each.
local texWarned = nil

function OverworldBattle.textures(battle)
  if not battle then return nil end
  local out = {}
  local okE, enemy = pcall(OverworldBattle.sideTexture, battle, "enemy")
  local okP, player = true, nil
  if not OverworldBattle.backPinned() then
    okP, player = pcall(OverworldBattle.sideTexture, battle, "player")
  end
  out.enemy = okE and enemy or nil
  out.player = okP and player or nil
  if texWarned ~= battle then
    -- `enemy` / `player` hold the TEXTURE when the pcall succeeded and the
    -- ERROR when it did not, which is exactly the pair each line wants
    local pinned = OverworldBattle.backPinned()
    local said = { { "enemy", okE, enemy, true },
                   { "player", okP, player, not pinned } }
    for _, row in ipairs(said) do
      local side, ok, why, asked = row[1], row[2], row[3], row[4]
      if asked and not out[side] then
        texWarned = battle
        local okV, want = pcall(sideVisible, battle, side)
        V.mod.log:warn("overworld battle: no %s billboard -- sideVisible=%s "
                       .. "render=%s (%s); that side draws as the flat pic",
                       side, tostring(okV and want), tostring(ok), tostring(why))
      end
    end
  end
  if not (out.enemy or out.player) then return nil end
  out.flash = OverworldBattle.flashing(battle)
  return out
end

-- Whether `side` has NO billboard standing on the map this frame although the
-- engine would have drawn a pic for it -- which is the one case where the flat
-- pics layer still has work to do (see the drawPicsLayer wrapper).
--
-- Answered off the SAME textures table the scene was drawn from, not a fresh
-- render, so it cannot disagree with what is actually on the canvas.
function OverworldBattle.flatFallback(battle, side)
  if not (session and not session.broken and battle) then return false end
  -- the pinned player already has its own branch, and it is not a failure
  if side == "player" and OverworldBattle.backPinned() then return false end
  local tex = session.textures
  if tex and tex[side] then return false end
  local ok, want = pcall(sideVisible, battle, side)
  return (ok and want) and true or false
end

-- ------- engine seams
--
-- Four wraps, each idempotent so a hot reload cannot stack them.

function OverworldBattle.install()
  local OverworldState = require("src.world.OverworldController")
  if not OverworldState.dramaticShapeBattleHook then
    local inner = OverworldState.pushBattle
    -- The one place the overworld starts a battle, and it runs BEFORE the
    -- transition is pushed -- which is what lets the cull happen off-screen
    -- and the wipe play over a map with nobody on it.
    function OverworldState:pushBattle(battle)
      pcall(OverworldBattle.begin, self, battle)
      return inner(self, battle)
    end
    OverworldState.dramaticShapeBattleHook = true
  end

  local BattleState = require("src.battle.BattleState")
  if BattleState.dramaticShapeBattleHook then return end

  -- Integer scales only. The camera is solved to make one overworld square
  -- exactly big enough for a pic at its own integer scale (see BattleCam), so
  -- the fit never has to come out of the pixels -- and a species override or
  -- a battle_sprite_scales entry that asks for 1.7x would undo that and
  -- resample the sprite into mush. Rounded rather than refused, so such a mod
  -- still gets the bigger or smaller mon it asked for, on the pixel grid.
  local innerScale = BattleState.resolveBattleScale
  function BattleState.resolveBattleScale(data, side, path, species)
    local base = innerScale(data, side, path, species)
    -- 1:1 into the billboard texture: the artwork's own pixels, with the
    -- quad's world size doing every bit of the scaling. Anything else would
    -- resample the sprite twice -- once into the texture and again on the way
    -- to the screen -- and a twice-resampled Gen 1 pic is mush.
    if texturing then return 1 end
    if not OverworldBattle.shot() then return base end
    return math.max(1, math.floor((tonumber(base) or 1) + 0.5))
  end

  -- Keyed-out whites inside a pic used to be filled by the white field
  -- behind it. There is a world back there now, so they are filled here
  -- instead -- see BattlePics, which puts the paper back without touching
  -- the silhouette.
  --
  -- The pinned pic is told that its feet are on the box, which is what lets
  -- the pale-bodied back sprites be filled at all: their bellies leak out
  -- through an opening too wide to read as a drain, and only the box under
  -- them settles that it is not a hole. Passed the pre-bake image, because
  -- that is the one the battle holds a reference to.
  local innerPic = BattleState.picImage
  function BattleState:picImage(img)
    local out = innerPic(self, img)
    if not OverworldBattle.shot() then return out end
    return BattlePics.filled(out, OverworldBattle.pinnedPic(self, img))
  end

  -- While a billboard texture is being rendered both pics are put in the same
  -- known place -- centred on TEX_AX with their feet on TEX_AY -- so the quad
  -- has one anchor to hang from whichever side and whichever species it is
  -- carrying. Outside that render both helpers answer exactly as they always
  -- did.
  local innerBack = BattleState.backPlacement
  function BattleState.backPlacement(w, h, pad, padL, scale)
    local x, y, s = innerBack(w, h, pad, padL, scale)
    if not texturing then return x, y, s end
    local bx, by = TEX_AX - w * scale / 2, TEX_AY - (h - pad) * scale
    placed[texturing] = { bx, by, w * scale, h * scale }
    return bx, by, s
  end

  local innerFront = BattleState.frontPlacement
  function BattleState.frontPlacement(ex, ey, w, h, scale)
    local x, y, s = innerFront(ex, ey, w, h, scale)
    if not texturing then return x, y, s end
    local fx, fy = TEX_AX - w * scale / 2, TEX_AY - h * scale
    placed[texturing] = { fx, fy, w * scale, h * scale }
    return fx, fy, s
  end

  local innerDraw = BattleState.draw
  function BattleState:draw()
    local shot = OverworldBattle.shot()
    -- AskName blanks the field on purpose (the nickname prompt is meant to
    -- sit on nothing); leave that one alone.
    if not shot or self.blankForAskName then
      -- nil, not false: the class default is inherited again, so a battle
      -- that loses its arena mid-fight goes back to white voids
      self.letterboxWhite = nil
      self.dramaticShapeShot = nil
      return innerDraw(self)
    end
    self.dramaticShapeShot = shot
    -- The world reaches the screen through the seam a render pipeline's
    -- finished world image already uses: one window-resolution canvas,
    -- blitted a pixel to a pixel, with the 160x144 UI canvas composited over
    -- it in the classic letterbox afterwards. That is what makes the backdrop
    -- as crisp as the free-roam diorama while the pics and text stay GB art.
    local renderer = game().renderer
    if renderer and renderer.setWorldOverride then
      renderer:setWorldOverride(shot.canvas)
    end
    -- beginFrame clears the UI canvas white for an opaque state; the world is
    -- under it now, so clear it back to nothing and let it through. Safe to
    -- do here: an opaque battle is the lowest state drawn, so nothing has
    -- drawn into this canvas yet.
    love.graphics.clear(0, 0, 0, 0)
    -- the white letterbox exists so the window matches the white battle
    -- canvas; there is a world out to the window edges now
    self.letterboxWhite = false
    OverworldBattle.drawHudPanels(self)
    withoutBackgroundFill(self, innerDraw)
  end

  -- The mons are geometry standing on the map now, drawn in the 3D pass
  -- before this screen is composited at all, so the flat pics layer has
  -- nothing left to do here. Skipped rather than left to draw underneath, or
  -- every Pokemon would appear twice: once on its tile and once in its slot.
  --
  -- Except under BACK SPRITES, where the player's side never became geometry and this
  -- layer is the only thing that draws it. The engine's own onlySide argument
  -- does the whole job: one call, the player's branches alone, in the slot and
  -- at the scale the GB always put them -- feet on the box, 2x, back view.
  innerPics = BattleState.drawPicsLayer
  function BattleState:drawPicsLayer(slide, sx, sy, onlySide, skipMenuClip)
    local shot = self.dramaticShapeShot
    if not shot then
      return innerPics(self, slide, sx, sy, onlySide, skipMenuClip)
    end
    if OverworldBattle.backPinned() and onlySide ~= "enemy" then
      -- under the hour's own light, like everything else in the frame -- see
      -- withTint, and the tint BattleScene hands over with the shot.
      --
      -- Except on the wavy path, where the pic is baked into the GRAYSCALE bg
      -- canvas for the zone pass to colour by region. That pass keys off the
      -- red channel, and a night tint pulls red down -- it would not darken
      -- the mon, it would remap it to the wrong shade. SE_WAVY_SCREEN lasts a
      -- second and the hour survives it fine.
      local tint = not self.grayPics and shot.tint or nil
      return withTint(tint, innerPics, self, slide, sx, sy, "player",
                      skipMenuClip)
    end
    -- ------- AND A SIDE WITH NO CARD IS NOT DELETED FROM THE FIGHT
    --
    -- IN-GAME: a wild WURMPLE that was simply not in the frame -- empty grass
    -- where Emerald stands the foe -- while the player's ABSOL stood on the
    -- ground with its shadow.
    --
    -- Suppressing this layer outright is right while BOTH mons are geometry:
    -- drawing them here as well would show each one twice. It is wrong the
    -- moment a side has no billboard, because then NOTHING draws that
    -- Pokemon: the card is missing from the 3D pass and the flat pic was
    -- taken away here. A battle is allowed to look less special; it is not
    -- allowed to lose a combatant.
    --
    -- So a side whose texture did not build falls back to the engine's own
    -- pic, in the engine's own slot, at the engine's own scale -- exactly what
    -- the flat battle screen would have drawn -- under the hour's tint like
    -- everything else in the frame. This changes NOTHING on a frame where both
    -- cards exist, which is every healthy frame: flatFallback reads the very
    -- textures table the scene was built from and answers false for a side
    -- that is standing out there.
    -- ------- ...AND IT STANDS ON THE GROUND, NOT IN A SLOT
    --
    -- IN-GAME, the user's words: "in battle pokemon should appear where the
    -- enemy trainers sprite appears, currently the enemy pokemon is floating
    -- upward and to the right of where it should be."
    --
    -- It appears where the trainer's sprite appears EXACTLY -- that is the
    -- problem. drawPicsLayer draws the enemy trainer straight at enemyPicXY
    -- and this fallback mon at frontPlacement(ex, ey, w, h, 1), which is the
    -- same (ex, ey): one point, two pics. On the flat battle screen that is
    -- right, because the whole screen is the slot. Here the rest of the frame
    -- is a diorama and the mon is supposed to be standing on a CELL, which
    -- projects somewhere else entirely -- up and to the right of it for the
    -- over-the-shoulder framing, because the cell is low and centre-left while
    -- the slot is high and right.
    --
    -- So the pic rides to the mark, the way the move-animation layer already
    -- rides to it (see drawAnimLayer, which subtracts the same anchors for the
    -- same reason): the delta is the side's projected mark less the slot the
    -- layout publishes for that side. That anchor is the right one HERE and
    -- was the wrong one for the billboard texture, and the difference is the
    -- whole of it -- this draw goes through Gen3Battle.draw's region translate
    -- and the texture render does not, so here the published anchor IS the
    -- slot the pic lands in, and there it was not.
    --
    -- NOT A CONSTANT, deliberately. `mark - anchor` moves with the camera, the
    -- arena and the window; a fixed offset would be right on one shot and
    -- wrong on every other. Skipped outright when the shot has no mark for
    -- that side, which leaves the old slot rather than a guess.
    local geo = OverworldBattle.geometry(self)
    local drew = false
    for _, side in ipairs({ "enemy", "player" }) do
      if (onlySide == nil or onlySide == side)
         and OverworldBattle.flatFallback(self, side) then
        local tint = not self.grayPics and shot.tint or nil
        local mark, slot = shot[side], geo.anchor[side]
        local dx, dy = 0, 0
        if mark and slot and mark[1] and mark[2] then
          dx, dy = mark[1] - slot[1], mark[2] - slot[2]
        end
        local g = love.graphics
        g.push()
        g.translate(dx, dy)
        local okP, errP = pcall(withTint, tint, innerPics, self, slide, sx, sy,
                                side, skipMenuClip)
        g.pop()
        if not okP then error(errP, 0) end
        drew = true
      end
    end
    return drew
  end

  -- The battle's text box and its menus, over the frosted glass laid down for
  -- them rather than over their own white paper -- and their ink flipped with
  -- the HUD's when the ground under the frame is dark, by the same rule and
  -- off the same verdict.
  local innerText = BattleState.drawTextArea
  function BattleState:drawTextArea()
    if not self.dramaticShapeShot then return innerText(self) end
    if isIOS() then return innerText(self) end
    local battle = self
    -- a layout whose message strip is the cartridge's own window frame keeps
    -- it: there is no white slab to take away and no black ink to whiten
    if OverworldBattle.opaqueWindows(battle) then return innerText(self) end
    if not self.dramaticShapeDark then return withoutBoxFill(battle, innerText) end
    local fw, fh = BattleScene.surface()
    BattleHud.flipGlyphs(fw, fh, function()
      withoutBoxFill(battle, innerText)
    end)
  end

  -- Move animations are authored against the pics' fixed slots, and a single
  -- animation reaches across both sides, so there is no per-side offset to
  -- give them. They ride the average, which is where the pair's centre went
  -- -- a few pixels at most, and it keeps a hit landing on the mon it is
  -- aimed at instead of drifting off it.
  innerAnim = BattleState.drawAnimLayer
  function BattleState:drawAnimLayer(colorized)
    local shot = self.dramaticShapeShot
    if not shot then return innerAnim(self, colorized) end
    -- Move animations are authored against the pics' old fixed slots, and one
    -- animation reaches across both sides, so there is no per-side offset to
    -- give them. They ride to where the PAIR went: the midpoint of the two
    -- mons' projected positions, less the midpoint of the slots they used to
    -- sit in. A hit still lands on the mon it is aimed at.
    --
    -- And they ride the pair's SEPARATION as well, because the mons
    -- themselves do. Both are geometry standing on the map, so the camera
    -- sizes them: zoom in and they grow, swing round to side-on and the two
    -- marks close up as the axis foreshortens. A layer that only slid would
    -- have held the authored 106-pixel spacing through all of it -- a beam
    -- fired between two mons that are no longer that far apart, ending in
    -- the air beside the one it was aimed at. Scaling about the same
    -- midpoint keeps every authored offset the same fraction of the gap it
    -- was authored as.
    local a = OverworldBattle.geometry(self).anchor
    -- BACK SPRITES leaves the player's mon exactly where the GB put it, so that side
    -- contributes no movement at all and the pair's centre has gone half as
    -- far as the foe's mark did.
    local px, py = shot.player[1], shot.player[2]
    if OverworldBattle.backPinned() then px, py = a.player[1], a.player[2] end
    local cx, cy = (shot.enemy[1] + px) / 2, (shot.enemy[2] + py) / 2
    local ax = (a.enemy[1] + a.player[1]) / 2
    local ay = (a.enemy[2] + a.player[2]) / 2
    love.graphics.push()
    love.graphics.translate(cx - ax, cy - ay)
    -- Clamped, and skipped outright if the marks ever coincide: a
    -- degenerate projection must leave the effects the size they were
    -- rather than collapse them to nothing or blow them across the screen.
    local k = OverworldBattle.animScale(shot, px, py, a)
    if k ~= 1 then
      love.graphics.translate(ax, ay)
      love.graphics.scale(k, k)
      love.graphics.translate(-ax, -ay)
    end
    local ok, err = pcall(innerAnim, self, colorized)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end

  -- The engine's flash has a SECOND half, and it is the one that reaches the
  -- menu. Beside the white rectangle (dropped above) the flash moves are
  -- driven by a BGP palette fade -- BGP_LIGHT and friends -- which the
  -- colorized pipeline applies in drawZonePass to the WHOLE background
  -- canvas. That canvas carries the HUD glyphs and the text box, so a fade
  -- meant for the two mons washed the menu out with them.
  --
  -- The fade is left switched on for the pics, which read it through
  -- picImage, and switched off for the zone pass alone. So the mons flash
  -- and the furniture around them does not.
  --
  -- The zone pass has a SECOND thing it paints, and this is the one that
  -- reads as the menu box flashing. A screen shake makes it fill every zone
  -- with the zone's own color 0 before it draws the offset copy -- the
  -- hardware showing empty BG in the strip the shake vacated. On a white
  -- battle field that fill is invisible; over a world it is an opaque white
  -- sheet across the whole frame, and since a shake program alternates
  -- offset and no-offset frames (SE_SHAKE_SCREEN steps dx 1, 0, 1, 0...) it
  -- switches on and off a few times a second. It is dropped: the background
  -- here is the map, so what the shake vacates should show the map.
  local innerZone = BattleState.drawZonePass
  function BattleState:drawZonePass(src, sx, sy)
    if not self.dramaticShapeShot then return innerZone(self, src, sx, sy) end
    -- shadow the method on the instance for this call only; putting the
    -- field back to whatever it was (normally nil) lets the class method be
    -- found again
    local had = rawget(self, "activeBgp")
    self.activeBgp = function() return nil end
    local g = love.graphics
    local rectangle = g.rectangle
    g.rectangle = function(mode, ...)
      -- the pass draws no other rectangle; the shake still shifts the copy
      if mode == "fill" then return end
      return rectangle(mode, ...)
    end
    local ok, err = pcall(innerZone, self, src, sx, sy)
    g.rectangle = rectangle
    self.activeBgp = had
    if not ok then error(err, 0) end
  end

  -- Black glyphs on grass are not readable; over a frosted panel measured
  -- dark they are not readable either, so they go white. Mapped rather than
  -- rewritten: the HUD sets pure black for its text and nothing else, and in
  -- the colorized pipeline this lands in the grayscale BG canvas, where
  -- white IS shade 0 and the zone pass then colours it like every other
  -- lightest-shade surface. One rule, both pipelines.
  --
  -- The HP bar is untouched: it is drawn in its own greens and reds, and
  -- only an exactly-black set is remapped.
  innerHUDs = BattleState.drawHUDs
  function BattleState:drawHUDs(slide)
    -- Normally the HUDs have already been drawn this frame, snapped out to the
    -- window's edges and composited into the world image (snapHUDs). Drawing
    -- them here as well would show each block twice, once in each place.
    if self.dramaticShapeShot and snapped() then return end
    if not (self.dramaticShapeShot and self.dramaticShapeDark) then
      return innerHUDs(self, slide)
    end
    local battle = self
    local fw, fh = BattleScene.surface()
    BattleHud.flipGlyphs(fw, fh, function()
      innerHUDs(battle, slide)
    end)
  end

  BattleState.dramaticShapeBattleHook = true
end

-- Whether each HUD block is on screen this frame.
--
-- READ-ONLY duplicates of drawHUDs' own two guards, because there is no seam
-- that reports "the enemy HUD is up". A panel under a HUD that is not there
-- would be a frosted slab floating in the arena, so it is worth mirroring;
-- the worst a future engine change can do is show an empty one for a frame,
-- never break a battle.
function OverworldBattle.hudLive(battle, slide)
  local enemy = battle.enemy and not battle.showEnemyTrainer
                and not battle.enemySendingOut
                and not battle:growInScale(battle.enemy) and slide == 0
                and not battle.enemy.fainted
  local player = battle.player and not (battle.safari or battle.demo)
                 and not battle.showPlayerBack and slide == 0
  return enemy and true or false, player and true or false
end

-- ------- the snapped composite
--
-- The engine's own HUD layer, rendered into a texture.
--
-- One thing is falsified for the render, and it is falsified because this layer
-- never reaches the battle's zone pass -- it is composited into the world image,
-- outside the frame that pass covers. In the colorized pipeline drawHUDs leaves
-- the HP bar's fill as DMG gray for the zone pass to colour by region (#229);
-- answered false, it tints its own greens and reds instead, exactly as it does
-- on the flat path. The glyphs are pure black either way, which is what the
-- flip in BattleHud.layerTexture is measured against.
--
-- Shadowed on the instance for this call only, the way drawZonePass shadows
-- activeBgp: putting the field back to whatever it was (normally nil) lets the
-- class method be found again.
-- ------- THE ROW HEIGHT THE STATUS PANEL MEASURES ITS OWN ROWS WITH
--
-- IN-GAME: ABSOL's status box on a Hoenn route. The HP mark and the HP bar are
-- drawn ON the name row, running straight through "Lv50"; "21/126" sits where
-- the bar should be; the bottom half of the cream box is empty; and the EXP
-- bar alone stays on the box's lower step, because it is the one row placed
-- from the panel's own y rather than from the name's height. ("also the hp
-- bar, and hp num/num is moved too high".)
--
-- WHOSE FAULT IT IS. Gen3Battle.drawStatusPanel pushes the cartridge's
-- FONT_SMALL for this box and then asks how tall a row of it is:
--
--     local faced = Font.pushFace("small")
--     local nameH = Font.glyphHeight()
--     local barY  = iy + nameH
--
-- Font.glyphHeight does not read the face stack. It answers
-- `state.order[1].cellHeight`, and `state.order` is sorted by BASE DESCENDING
-- -- so order[1] is whichever page starts at the highest code, a symbol page,
-- and not the face that was just pushed. Measured off the reported frame at 6
-- against a `small` face that the dataset itself says is 11 tall
-- (data.font.faces.small.glyphHeight). Eleven is not a guess and not tuned to
-- the crop: the engine's own comment beside those lines says "eleven plus the
-- bar's eight is exactly nineteen", and nineteen is HUD_INTERIOR.h.
--
-- NONE OF THAT IS THIS MOD'S, and the panel must not be re-laid-out here --
-- owning the layout again is exactly what g3-viewport-254 undid. So this is a
-- SHIM, in the shape this file already uses twice in this very function and in
-- withoutBackgroundFill: stand in front of one call for the length of one
-- render and take it away again on the way out, including on error.
--
-- IT RETIRES ITSELF. If the engine's answer already matches the face the panel
-- pushes, nothing is installed and `fn` runs untouched -- so the day
-- Font.glyphHeight learns about the face stack this becomes a no-op rather
-- than a second opinion.
--
-- GEN 1, GEN 2 AND PRISM ARE UNTOUCHED BY CONSTRUCTION. The height is read off
-- the DATASET rather than out of the font module, and the datasets those games
-- ship have no `small` face at all -- the Game Boy has one font. No face, no
-- height, and the very first line hands `fn` straight back.
local function panelFaceHeight()
  local okG, g = pcall(game)
  if not okG then return nil end
  local faces = g and g.data and g.data.font and g.data.font.faces
  local small = faces and faces.small
  local h = small and tonumber(small.glyphHeight)
  if not (h and h > 0) then return nil end
  return math.floor(h)
end

local function withPanelRows(fn)
  local h = panelFaceHeight()
  if not h then return fn() end
  local okF, Font = pcall(require, "src.render.Font")
  if not (okF and Font and type(Font.glyphHeight) == "function") then return fn() end
  local inner = Font.glyphHeight
  local okH, have = pcall(inner)
  if okH and have == h then return fn() end          -- the engine agrees: stand aside
  Font.glyphHeight = function() return h end
  local ok, res = pcall(fn)
  Font.glyphHeight = inner
  if not ok then error(res, 0) end
  return res
end

function OverworldBattle.hudTexture(battle, slide, dark)
  if not (innerHUDs and battle) then return nil end
  local had = rawget(battle, "colorMode")
  battle.colorMode = function() return false end
  -- THE LAYER IS THE SURFACE, not the Game Boy's screen. drawHUDs draws in
  -- the surface's own coordinates -- Emerald's player block starts at x=112
  -- and is 120 wide, so it runs to 232 -- and a 160x144 canvas simply cut
  -- everything past 160 and past 144 away: 72 of those 120 columns and 8 of
  -- its 40 rows, 68% of the block, which is the "the HP bar, the EXP bar, the
  -- Lv and the name are chopped off" report.
  local lw, lh = BattleScene.surface()
  local ok, layer = pcall(withPanelRows, function()
    return BattleHud.layerTexture(lw, lh, dark,
                                  function() innerHUDs(battle, slide) end)
  end)
  battle.colorMode = had
  return ok and layer or nil
end

-- Draw both HUD blocks into the world image at the window's edges, each on its
-- own frosted panel. Returns true when the frame's HUDs are up there and the
-- in-frame draw must be skipped; false leaves the battle screen's own HUD
-- exactly as it was before any of this existed.
--
-- Both bands are blitted whether or not that side's HUD is LIVE, because a band
-- carries more than the HUD: the pokeball rows of the intro and of an enemy
-- faint, and the safari ball count, all draw in these rows and belong at the
-- same edge as the block they share it with. The panels are the ones that
-- follow hudLive -- frosted glass under nothing is a slab floating in the arena.
function OverworldBattle.snapHUDs(battle, shot)
  if not (battle and shot and shot.canvas and (shot.scale or 0) > 0) then
    return false
  end
  -- With a headset live the HUDs stay IN the GB frame -- the classic
  -- slots, on the glass drawHudPanels lays for the unsnapped path. Both
  -- of VR's battle screens (the floating panel and the pokedex's) crop
  -- to the letterbox, and a block snapped out to the window's edge would
  -- be cropped away with the window around it.
  local okV, vr = pcall(V.require, "VR")
  if okV and vr and vr.active and vr.active() then return false end
  local slide = (battle.introSlide or 0) * 4
  local geom = OverworldBattle.geometry(battle)
  local opaque = geom.opaqueWindows and true or false
  local rects, bandX = OverworldBattle.snapRects(shot, battle)
  local enemy, player = OverworldBattle.hudLive(battle, slide)
  local live = {}
  if enemy then live.enemy = rects.enemy end
  if player then live.player = rects.player end
  -- and the text box's own glass, on the same pass. It stays in the middle of
  -- the frame where the engine draws it -- only the HUDs were snapped out --
  -- so its GB rect is mapped into the letterbox rather than to an edge.
  for key, rect in pairs(OverworldBattle.textRects(battle)) do
    live[key] = toWorld(rect, shot)
  end
  -- measured under the SNAPPED rects: the panels are over whatever the world
  -- shows at the window's edges now, which is not what was behind them in the
  -- middle of the frame. ONE verdict over all of them, HUDs and box together,
  -- for the reason BattleHud.verdict gives: a frame with white glyphs in the
  -- corner and black ones on the menu reads as a bug rather than as adaptation.
  -- ...unless this layout's windows are opaque, in which case there is
  -- nothing behind the glyphs to measure and nothing for a flip to fix: the
  -- panel IS a cream sprite and white-on-cream is not contrast, it is the
  -- text gone. Measured and flipped only where the window is transparent.
  local dark = (not opaque) and BattleHud.verdict(live, shot, true) or false
  -- the box's own ink is flipped where the engine draws it, in the GB frame,
  -- so the answer has to outlive this function (see drawHudPanels)
  if session then session.dark = dark end
  local layer = OverworldBattle.hudTexture(battle, slide, dark)
  if not layer then return false end
  local lw, lh = BattleScene.surface()

  local g = love.graphics
  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok, err = pcall(function()
    g.setCanvas(shot.canvas)
    g.setBlendMode("alpha")
    if not opaque then
      for _, rect in pairs(live) do BattleHud.panel(rect, shot, dark, true) end
    end
    g.setColor(1, 1, 1, 1)
    for side, band in pairs(OverworldBattle.bands(geom)) do
      local quad = g.newQuad(band[1], band[2], band[3], band[4], lw, lh)
      g.draw(layer, quad, bandX[side] + band[1] * shot.scale,
             shot.ly + band[2] * shot.scale, 0, shot.scale, shot.scale)
    end
  end)
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
  return true
end

-- Lay the frosted glass down under whichever HUD and box are about to draw,
-- and record which way the glyphs have to flip.
--
-- The panels are the fallback path only: normally the HUDs are snapped out to
-- the window's edges and their glass, and the box's, went into the world image
-- with them (snapHUDs). The VERDICT is needed either way -- the box's ink is
-- drawn here, in the GB frame, whichever path laid the glass under it.
function OverworldBattle.drawHudPanels(battle)
  local shot = battle.dramaticShapeShot
  battle.dramaticShapeDark = nil
  if not shot then return end
  -- A LAYOUT WHOSE WINDOWS BRING THEIR OWN BACKGROUND GETS NEITHER.
  --
  -- No glass, because Emerald's status box is the cartridge's own opaque cream
  -- sprite and its message strip the cartridge's own window frame -- frosted
  -- glass behind an opaque sprite is invisible work. And no flip, because the
  -- flip whitens near-black ink, and white ink on a cream panel is the foe's
  -- name, the Lv, the HP bar's outline and the EXP bar simply GONE. Leaving
  -- dramaticShapeDark nil is what turns the flip off downstream (drawHUDs and
  -- drawTextArea both read it). See OverworldBattle.opaqueWindows.
  if OverworldBattle.opaqueWindows(battle) then return end
  if isIOS() then
    local slide = (battle.introSlide or 0) * 4
    local enemy, player = OverworldBattle.hudLive(battle, slide)
    local rect = OverworldBattle.geometry(battle).hudRect
    love.graphics.setColor(1, 1, 1, 0.84)
    if enemy then love.graphics.rectangle("fill", rect.enemy[1], rect.enemy[2], rect.enemy[3], rect.enemy[4]) end
    if player then love.graphics.rectangle("fill", rect.player[1], rect.player[2], rect.player[3], rect.player[4]) end
    love.graphics.setColor(1, 1, 1, 1)
    battle.dramaticShapeDark = nil
    return
  end
  if snapped() then
    battle.dramaticShapeDark = session and session.dark or nil
    return
  end
  local slide = (battle.introSlide or 0) * 4
  local enemy, player = OverworldBattle.hudLive(battle, slide)
  local rect = OverworldBattle.geometry(battle).hudRect
  local live = {}
  if enemy then live.enemy = rect.enemy end
  if player then live.player = rect.player end
  for key, r in pairs(OverworldBattle.textRects(battle)) do live[key] = r end
  if not next(live) then return end
  local dark = BattleHud.verdict(live, shot)
  battle.dramaticShapeDark = dark
  for _, r in pairs(live) do BattleHud.panel(r, shot, dark) end
end

return OverworldBattle
