-- Voxel world mode: characters as flat forward-facing sprite billboards.
--
-- Gen2 patch: SPRITE_BIG_SNORLAX / SPRITE_BIG_LAPRAS (and any def.big sheet)
-- are 32x32 over a 2x2 cell footprint.  The stock card was hard-coded 16x16
-- and only sampled the top-left face tile — that is why DramaticShapes showed
-- a quarter of Snorlax.  Big sheets get a 32x32 card; 16-wide mirrored strips
-- get a dual-quad card that mirrors the left half in UV space.

local V = ...

local Assets = require("src.render.Assets")
local Voxel3D = V.require("Voxel3D")

local SpriteBillboards = {}

local meshes = {}

local function isBigDef(def)
  if not def then return false end
  if def.big then return true end
  local id = def.id or ""
  return id == "SPRITE_BIG_SNORLAX"
    or id == "SPRITE_BIG_LAPRAS"
    or id == "SPRITE_BIG_DOLL"
end

-- Standard 16x16 walker frame (Gen1 / normal Gen2 NPCs).
local function buildCard16(img, frame)
  local iw, ih = img:getDimensions()
  local fy = frame * 16
  if fy + 16 > ih then fy = 0 end
  local u0, u1 = 0.02 / iw, (16 - 0.02) / iw
  local v0, v1 = (fy + 0.05) / ih, (fy + 15.95) / ih
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { 16, 0, 0, u1, v1, 1 },
    { 16, 16, 0, u1, v0, 1 }, { 0, 16, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

-- Full 32x32 body (extractor already mirrored the left half into the sheet).
local function buildCard32(img)
  local iw, ih = img:getDimensions()
  local u0, u1 = 0.02 / iw, (math.min(32, iw) - 0.02) / iw
  local v0, v1 = 0.05 / ih, (math.min(32, ih) - 0.05) / ih
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { 32, 0, 0, u1, v1, 1 },
    { 32, 32, 0, u1, v0, 1 }, { 0, 32, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

-- 16x32 left-half strip: two side-by-side quads, right one mirrors U.
local function buildCardMirrored16x32(img)
  local iw, ih = img:getDimensions()
  local h = math.min(32, ih)
  local u0, u1 = 0.02 / iw, (16 - 0.02) / iw
  local v0, v1 = 0.05 / ih, (h - 0.05) / ih
  -- left half
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { 16, 0, 0, u1, v1, 1 },
    { 16, h, 0, u1, v0, 1 }, { 0, h, 0, u0, v0, 1 },
    -- right half = mirror of left (u1→u0)
    { 16, 0, 0, u1, v1, 1 }, { 32, 0, 0, u0, v1, 1 },
    { 32, h, 0, u0, v0, 1 }, { 16, h, 0, u1, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  Voxel3D.pushQuad(indices, 4)
  return Voxel3D.newMesh(verts, indices)
end

-- ---------------------------------------------------------------------------
-- A CARD FROM A SHEET THAT STATES ITS OWN FRAME BOX.
--
-- Everything above assumes the Gen 1/Gen 2 shape: a one-frame-wide sheet of
-- SQUARE frames, so a 16-wide sheet has 16px rows and `frame * 16` finds the
-- one you want.  Gen 3 breaks both halves of that. Its overworld sprites come
-- in 16x32, 32x32 and 16x16, and the common walker -- the player included --
-- is 16 wide and THIRTY-TWO tall.
--
-- Read as 16px rows, frame 3 (walk south) lands at y=48, which is the middle
-- of frame 1: the card showed the bottom of "stand north" and the top of
-- "stand west" at once, in a 16px box that cropped it to the hair. On screen
-- that is a small brown smudge on the ground that changes to a DIFFERENT
-- wrong smudge as you walk -- which reads exactly like a sprite facing the
-- wrong way, and is really a sprite sliced between two frames.
--
-- The defs say so themselves (`frameWidth` / `frameHeight`, straight off
-- gObjectEventGraphicsInfo), so where they do, believe them. Where they do
-- not -- every Gen 1, Gen 2 and Prism sheet -- nothing below this line runs
-- and the original path is taken unchanged.
local function statedFrame(def)
  local fw = tonumber(def.frameWidth)
  local fh = tonumber(def.frameHeight)
  if fw and fh and fw > 0 and fh > 0 then return fw, fh end
  return nil
end

local function buildCardStated(img, frame, fw, fh)
  local iw, ih = img:getDimensions()
  fw, fh = math.min(fw, iw), math.min(fh, ih)
  local fy = (tonumber(frame) or 0) * fh
  if fy + fh > ih then fy = 0 end
  local u0, u1 = 0.02 / iw, (fw - 0.02) / iw
  local v0, v1 = (fy + 0.05) / ih, (fy + fh - 0.05) / ih
  -- The card is fw x fh in WORLD pixels, so a 16x32 walker stands two courses
  -- tall on a one-cell footprint -- which is what the flat game draws too.
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { fw, 0, 0, u1, v1, 1 },
    { fw, fh, 0, u1, v0, 1 }, { 0, fh, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  return Voxel3D.newMesh(verts, indices)
end

local function buildCard(def, frame)
  local ok, img = pcall(Assets.image, def.image)
  if not (ok and img) then return nil end
  local iw, ih = img:getDimensions()

  -- a sheet that states its frame box answers first, whatever its width
  local fw, fh = statedFrame(def)
  if fw then return buildCardStated(img, frame or 0, fw, fh) end

  if isBigDef(def) or iw >= 32 then
    if iw >= 32 and ih >= 32 then
      return buildCard32(img)
    end
    -- Still a 16-wide FacingBigDollSymmetric strip
    return buildCardMirrored16x32(img)
  end

  return buildCard16(img, frame or 0)
end

function SpriteBillboards.mesh(def, frame)
  local big = isBigDef(def)
  local key = def.image .. "#" .. (big and "big" or tostring(frame))
  if meshes[key] == nil then
    local ok, m = pcall(buildCard, def, frame)
    meshes[key] = (ok and m) or false
  end
  return meshes[key] or nil
end

SpriteBillboards.shadowQuad = SpriteBillboards.mesh

function SpriteBillboards.invalidate()
  meshes = {}
end

-- WHERE THE FEET ARE, WHICH IS NOT THE SAME QUESTION AS HOW WIDE THE CARD IS.
--
-- In-game location: THE SEA OFF ROUTE 118 -- a surfing player wears
-- SPRITE_G3_003, a 32x32 sheet, and stands on ONE 16px cell; and every bike
-- lane in Hoenn, where SPRITE_G3_001 / _002 do the same thing.
--
-- The flat path states the rule itself. SpriteRenderer.new gives a sheet that
-- DECLARES its frame box `offsetX = (frameWidth - 16) / 2` and
-- `offsetY = frameHeight - 16`, i.e. it centres the frame on the 16px cell and
-- hangs the surplus over the edges -- so a 32-wide sheet is blitted from
-- px - 8 and its middle lands on the middle of the cell, at px + 8.
--
-- `halfWidth` above is the card's OWN half, and billboardMatrix used that one
-- number for two different things: how far to slide the card left to centre
-- it, and which point to centre it ON. Those coincide for a Gen 2 BIG DOLL,
-- whose footprint really is 2x2 cells (Snorlax, Lapras stand on four), and
-- for nothing else. 61 of Hoenn's 256 overworld sheets are wider than 16px --
-- 55 at 32 wide, one 48, three 64, one 88, one 96 -- and every one of them was
-- drawn (frameWidth/2 - 8) px EAST and the same distance SOUTH of the cell the
-- flat game draws it on: half a cell for the surfing and cycling player, two
-- and a half cells for the widest.
--
-- nil for a sheet that does not state a frame box, and every Gen 1, Gen 2 and
-- Prism sheet is one of those (see statedFrame above -- nothing below that
-- line runs for them). A nil answer leaves both the card matrix and the sun's
-- record built from exactly the arithmetic they were built from before, big
-- dolls included.
function SpriteBillboards.footAnchor(def)
  local fw = def and tonumber(def.frameWidth)
  if fw and fw > 0 then return 8 end
  return nil
end

-- World-space half-width used by VoxelScene to centre the card on the
-- footprint (8 for 16px walkers, 16 for 32px big dolls).
function SpriteBillboards.halfWidth(def)
  -- A stated frame width is the truth: Gen 3 mixes 16- and 32-wide sprites in
  -- one cast, and a 32-wide card centred as if it were 16 stands half a cell
  -- to the side of the feet it belongs to.
  local fw = def and tonumber(def.frameWidth)
  if fw and fw > 0 then return fw / 2 end
  if isBigDef(def) then return 16 end
  return 8
end

Assets.register(SpriteBillboards.invalidate)

return SpriteBillboards
