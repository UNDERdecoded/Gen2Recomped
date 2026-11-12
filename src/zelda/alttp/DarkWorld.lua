-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DARK WORLD'S MECHANICS (round 26, team A): the warp tiles, the Magic
-- Mirror's crossing, the mirror portal (sprite 0x6C), the bump back
-- ("mirror bonk") and the bunny Link becomes without the Moon Pearl. The
-- routines are the SNES ones the GBA keeps (zelda3 names); the tables are
-- the GBA's own (offsets in OFF, found by value and checked by the code that
-- reads them):
--
--   warp tile             TileDetect_MainHandler(0): the attribute under
--                         (x + 8, y + 20) is 0x4B (TileBehavior_Warp) while
--                         x & 15 is < 4 or >= 12 and (y + 8) & 15 < 4 or
--                         >= 11, Link not blinking and not recoiling ->
--                         DoSwordInteractionWithTiles_Mirror (submodule 35),
--                         unless link_triggered_by_whirlpool_sprite (set by
--                         a crossing, cleared once Link is off the tile).
--                         The tiles under rocks are the secrets 0x82
--                         (Overworld_RevealSecret -> map16 0x212, Escape.lua).
--   LinkItem_Mirror       in the Dark World (not in a doorway): keep Link's
--                         spot (bird_travel_x/y[15]) and cross (submodule
--                         35); in the Light World only the error sound.
--                         Indoors Mirror_SaveRoomData: in a palace back to
--                         its entrance (Module07_19_MirrorFade -> module 5).
--   Module09_MirrorWarp   case 0: savegame_is_darkworld ^= 0x40, the area
--                         keeps its x / y; InitializeMirrorHDMA and
--                         PaletteFilter_InitializeWhiteFilter; then the
--                         waving (MirrorWarp_BuildWavingHDMATable) and
--                         de-waving tables every other frame, the white
--                         filter one step every 2 frames after 8
--                         (MirrorWarp_RunAnimationSubmodules: to white in 31
--                         steps, back in 35 to step 66); MirrorWarp_Finalize
--                         AndLoadDestination: the area's music, song 4 (the
--                         bunny's) in the Dark World without the pearl.
--   MirrorWarp_LoadSpritesAndColors  arriving in the Light World:
--                         Sprite_InitializeMirrorPortal at bird_travel[15]
--                         (y + 8); also on every load of the Light World
--                         from a building (PreOverworld_LoadProperties).
--   LinkState_CrossingWorlds  TileCheckForMirrorBonk (x + 2 / 13, y + 10 /
--                         21): a top point and two points solid in the other
--                         world, or deep water there without the flippers,
--                         cross back at once (submodule 44); deep water with
--                         them: swimming (Swim.lua); else Link stands, a
--                         bunny in the Dark World without the Moon Pearl.
--   Sprite_6C_MirrorPortal  gone in the Dark World; flags | kSprite_Warp
--                         Vortex_Flags[frame >> 2 & 3] (GBA 0x1750AC, read
--                         by 0x080D5526); touching Link (Sprite_CheckDamage
--                         ToLink_same_layer) once A is set (A: Link not on it
--                         once, or B wrapped) crosses to the Dark World.
--   the bunny             PlayerHandler_17_Bunny: walks (no sword, no R
--                         action, no dash); Link_HandleYItem only the bottle
--                         and the mirror; LinkOam_Main yt 0x21, rt = steps &
--                         3, no sword / shield; LoadGearPalettes_bunny =
--                         armour palette 3 (Gear.lua: blob row 0xE0).
--
-- OURS (docs/zelda/alttp.md "Round 26 (team A)"): the HDMA wave is
-- simulated for its timing only (the BGs are not drawn waving); the white
-- filter is drawn as a "lighten" fill over the play field with Link redrawn
-- on top (the cartridge whitens BG and sprite palettes 0x40-0x1DF and keeps
-- Link's); the bunny's poof (AncillaAdd_BunnyPoof) and its 20 frames are not
-- drawn; no sound; the indoor mirror skips the mosaic fade.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local DW = {}

DW.OFF = { vortexFlags = 0x1750AC }   -- kSprite_WarpVortex_Flags (4)
DW.WARP_ATTR = 0x4B
DW.PORTAL = 0x6C
DW.MIRROR_SLOT = 23
DW.PEARL_BYTE = 0x3B                  -- GBA inventory (SNES link_item_moon_pearl 0x357)
DW.BUNNY_SONG = 4

function DW.extract(rom, R, check)
  local t = { vortexFlags = rom:bytesU8(DW.OFF.vortexFlags, 4) }
  check(t.vortexFlags[1] == 0 and t.vortexFlags[2] == 0x40 and t.vortexFlags[3] == 0xC0, "kSprite_WarpVortex_Flags")
  return t
end

local function T(game) return game.data.t and game.data.t.dw end

-- ------------------------------------------------------------ helpers
local function s16(v) v = v % 65536 if v >= 32768 then v = v - 65536 end return v end

function DW.hasPearl(game)
  local inv = require("src.zelda.alttp.Menu").inventory(game)
  return (inv[DW.PEARL_BYTE] or 0) ~= 0
end

function DW.hasFlippers(game)
  local inv = require("src.zelda.alttp.Menu").inventory(game)
  return (inv[0x3A] or 0) ~= 0
end

-- the attribute set TileCheckForMirrorBonk counts (R12 | R14: walls,
-- slopes, liftables; deep water is its own bit)
local function bonkSolid(a)
  if a == 0x08 then return false end
  return require("src.zelda.alttp.Overworld").isSolid(a)
end

-- TileCheckForMirrorBonk: bits 8 (x+2, y+10), 2 (x+2, y+21), 4 (x+13, y+10),
-- 1 (x+13, y+21); returns the solid bits and the deep-water bits
function DW.bonkProbe(game, world, x, y)
  local ow = game.ow
  local pts = { { 2, 10, 8 }, { 2, 21, 2 }, { 13, 10, 4 }, { 13, 21, 1 } }
  local solid, deep = 0, 0
  for _, p in ipairs(pts) do
    local a = ow:attrAt(world, x + p[1], y + p[2])
    if bonkSolid(a) then solid = bor(solid, p[3]) end
    if a == 0x08 then deep = bor(deep, p[3]) end
  end
  return solid, deep
end
local function bitSum4(v) local n = 0 for i = 0, 3 do if band(v, lshift(1, i)) ~= 0 then n = n + 1 end end return n end
DW.bitSum4 = bitSum4

-- the warp tile test (TileDetect_MainHandler(0) -> TileBehavior_Warp)
function DW.onWarpTile(game)
  local lk = game.link
  return game.ow:attrAt(lk.world, lk.x + 8, lk.y + 20) == DW.WARP_ATTR
end
function DW.warpAligned(lk)
  local tx, ty = band(lk.x, 15), band(lk.y + 8, 15)
  return (ty < 4 or ty >= 11) and (tx < 4 or tx >= 12)
end

-- ------------------------------------------------------------ the crossing
function DW.start(game, kind)
  local lk = game.link
  if game.dropCarry then game:dropCarry() end
  require("src.zelda.alttp.Dash").cancel(game)
  game.swing, game.bowUse = nil, nil
  lk.steps, lk.moving = 0, false
  game.warpGuard = true                                     -- link_triggered_by_whirlpool_sprite
  if kind ~= "bonk" then game.lastWorld = lk.world end      -- last_light_vs_dark_world
  game.mirrorWarp = { kind = kind, sub = 0, from = lk.world }
  game.crossings = (game.crossings or 0) + 1
end

-- one frame of Module09_MirrorWarp (returns when done)
local function runAnimation(w)
  -- MirrorWarp_RunAnimationSubmodules -> PaletteFilter_BlindingWhite
  w.ctr = w.ctr - 1
  if w.ctr ~= 0 then return end
  w.ctr = 2
  if w.dls == 0xFF then return end
  w.countdown = w.countdown + 1
  if w.dls == 0 then
    if w.countdown == 66 then w.dls = 0xFF; w.ctr = 32 end
  elseif w.countdown == 31 then
    w.dls = 0
  end
end

-- the white level 0..31 the palette filter has reached
function DW.whiteLevel(w)
  if not w or not w.countdown then return 0 end
  if w.dls == 2 then return math.min(31, w.countdown) end
  if w.dls == 0xFF then return 0 end
  return math.max(0, 31 - (w.countdown - 31))
end

local function shiftBlocks(w)
  for i = 29, 1, -1 do w.blocks[i] = w.blocks[i - 1] end
end

local function waving(game, w)
  runAnimation(w)
  if band(game.frame, 1) ~= 0 then return end
  shiftBlocks(w)
  local i = rshift(w.var0, 1) + 1
  local t = s16(w.var6 + w.var3[i])
  -- !sign16((t - var1[i]) ^ var1[i])
  if band(bxor((t - w.var1[i]) % 65536, w.var1[i] % 65536), 0x8000) == 0 then
    t = w.var1[i]
    w.var5, w.var7 = 0, 0
    w.var0 = bxor(w.var0, 2)
  end
  w.var6 = t
  t = (t + w.var7) % 65536
  w.var7 = band(t, 0xFF)
  if t >= 0x8000 then t = bor(t, 0xFF) else t = band(t, 0xFF00) end
  local sw = bor(rshift(t, 8), lshift(band(t, 0xFF), 8))       -- swap16
  t = (w.var5 + sw) % 65536
  w.var5 = t
  if w.countdown >= 0x30 and band(t, 0xFFF8) == 0 then
    w.var1 = { -0x100, 0x100 }
    w.sub = 3
    t = 0
  end
  w.blocks[0] = s16(t)
end

local function dewaving(game, w)
  runAnimation(w)
  if band(game.frame, 1) ~= 0 then return end
  shiftBlocks(w)
  if w.blocks[24] == 0 and w.blocks[25] == 0 and w.blocks[26] == 0 and w.blocks[27] == 0 then
    w.sub = 4
  end
end

function DW.frame(game)
  local w = game.mirrorWarp
  local lk = game.link
  if w.sub == 0 then
    -- case 0: the other world, same spot
    w.ctr, w.countdown, w.dls = 8, 0, 2                     -- PaletteFilter_InitializeWhiteFilter
    w.var0, w.var5, w.var6, w.var7 = 0, 0, 0, 0             -- InitializeMirrorHDMA
    w.var1, w.var3 = { -0x200, 0x200 }, { -0x40, 0x40 }
    w.blocks = {}
    for i = 0, 29 do w.blocks[i] = 0 end
    lk.world = (lk.world == "dw") and "lw" or "dw"
    game.ow.attrCache = {}
    game.area = game.ow:area(game:screen())
    game.cam = game:cameraFor(game.area)
    game.scroll = nil
    if game.music and game.music.stop then game.music:stop() end
    -- MirrorWarp_LoadSpritesAndColors: the portal, arriving in the Light World
    if lk.world == "lw" and game.portalPos then DW.spawnPortal(game) end
    if lk.world == "dw" then game.portal = nil end
    w.sub = 2                                               -- case 1 falls into case 2
    return waving(game, w)
  elseif w.sub == 2 then
    return waving(game, w)
  elseif w.sub == 3 then
    return dewaving(game, w)
  end
  -- MirrorWarp_FinalizeAndLoadDestination
  game.mirrorWarp = nil
  game.crossing = true                                      -- kPlayerState_Mirror
  game.musicStarted = nil
  if game.music and game.music.playForScreen then
    game.music.bunny = DW.isBunny(game)
    game.music:playForScreen(game.area.parent, lk.world)
  end
end

-- LinkState_CrossingWorlds (the first player frame after the crossing)
function DW.land(game)
  game.crossing = nil
  local lk = game.link
  local solid, deep = DW.bonkProbe(game, lk.world, lk.x, lk.y)
  local changed = lk.world ~= game.lastWorld
  if changed and band(solid, 0xC) ~= 0 and bitSum4(solid) >= 2 then
    game.mirrorBonks = (game.mirrorBonks or 0) + 1
    return DW.start(game, "bonk")
  end
  if bitSum4(deep) >= 2 then
    if DW.hasFlippers(game) then
      local Swim = package.loaded["src.zelda.alttp.Swim"]
      if Swim and Swim.enter then Swim.enter(game) end
      return
    end
    if changed then
      game.mirrorBonks = (game.mirrorBonks or 0) + 1
      return DW.start(game, "bonk")
    end
  end
  game.landed = (game.landed or 0) + 1
end

-- ------------------------------------------------------------ the portal
function DW.spawnPortal(game)
  local p = game.portalPos
  if not p then return end
  game.portal = { x = p.x, y = p.y + 8, A = 0, B = 0, type = DW.PORTAL }
end

function DW.portalFrame(game)
  local p = game.portal
  if not p or game.link.world ~= "lw" then return end
  local lk = game.link
  local Actors = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local touching = false
  if cb then
    local hx, hy, hw, hh = Actors.hitbox(cb, p)
    local lx, ly, lw, lh = Actors.linkBox(lk)
    touching = Actors.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh)
  end
  if touching then
    if p.A ~= 0 and (game.blink or 0) == 0 and not game.recoil then
      game.portal = nil
      game.portalCrossings = (game.portalCrossings or 0) + 1
      return DW.start(game, "portal")
    end
  else
    p.A = 1
  end
  p.B = (p.B + 1) % 256
  if p.B == 0 then p.A = 1 end
end

function DW.drawPortal(game, spr, cx, cy)
  local p = game.portal
  local tb = T(game)
  if not (p and spr and tb) or game.link.world ~= "lw" then return end
  if game.mirrorWarp then return end                        -- submodule 0x23
  local j = band(rshift(game.frame, 2), 3)
  spr:single(p, p.x - cx, p.y - cy, 0, tb.vortexFlags[j + 1])
end

-- ------------------------------------------------------------ the bunny
function DW.isBunny(game)
  local w = game.mirrorWarp
  local world = game.link.world
  if w then world = w.from end
  return world == "dw" and not DW.hasPearl(game)
end

-- ------------------------------------------------------------ install
function DW.install(G)
  local Items = require("src.zelda.alttp.Items")
  Items.SLOT[DW.MIRROR_SLOT] = "mirror"

  function G:isBunny() return DW.isBunny(self) end

  -- the crossing runs alone (the module's own frames: no sprites, no input)
  local update0 = G.update
  function G:update(dt)
    if self.mirrorWarp and self.state == "play" and not self.textBox and not self.menu then
      self.frame = self.frame + 1
      require("src.zelda.alttp.AnimTiles").tick(self.frame)
      if self.music then self.music:update() end
      DW.frame(self)
      return
    end
    if self.music then self.music.bunny = DW.isBunny(self) end
    return update0(self, dt)
  end

  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if self.crossing then DW.land(self); if self.mirrorWarp then return true end end
    local lk = self.link
    -- the warp tile
    if lk.world == "lw" then
      if DW.onWarpTile(self) then
        if not self.warpGuard and DW.warpAligned(lk) and (self.blink or 0) == 0 and not self.recoil
           and not lk.hop and not self.carry and not self.dash then
          self.warpTiles = (self.warpTiles or 0) + 1
          DW.start(self, "tile")
          return true
        end
      else
        self.warpGuard = nil
      end
      DW.portalFrame(self)
      if self.mirrorWarp then return true end
    else
      self.warpGuard = nil
    end
    -- the bunny: no sword (HandleSwordControls is not called)
    if DW.isBunny(self) then inp.b = false end
    return owFrame(self, inp)
  end

  local roomFrame = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if DW.isBunny(self) then inp.b = false end
    return roomFrame(self, inp)
  end

  -- Link_HandleYItem: the bunny keeps the bottle and the mirror
  local itemFrame0 = G.itemFrame
  function G:itemFrame(inp)
    if inp.y and not self.bowUse then
      local item, slot = self:yItem()
      if DW.isBunny(self) and item ~= "mirror" and not (slot and slot % 6 == 0) then
        inp.y = false
      elseif item == "mirror" then
        self.mirrorUses = (self.mirrorUses or 0) + 1
        DW.useMirror(self)
        return false
      end
    end
    return itemFrame0(self, inp)
  end

  -- no lifting, no dash as a bunny
  local tryLift0 = G.tryLift
  function G:tryLift()
    if DW.isBunny(self) then return false end
    return tryLift0(self)
  end
  local Dash = require("src.zelda.alttp.Dash")
  local dashStart0 = Dash.start
  function Dash.start(game)
    if game.isBunny and DW.isBunny(game) then return false end
    return dashStart0(game)
  end

  -- the bunny's picture (LinkOam_Main yt 0x21)
  local pose0 = G.linkPose
  function G:linkPose()
    if DW.isBunny(self) and not (self.mirrorWarp and self.mirrorWarp.sub == 0) then
      return 0x21, band(self.link.steps or 0, 3)
    end
    return pose0(self)
  end
  local drawLink0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk == self.link and not tint and self.state == "play" and self.portal then
      DW.drawPortal(self, self:shadowSprites(), self.cam.x, self.cam.y)
    end
    if lk == self.link and not tint and DW.isBunny(self) then
      local pr = self.progress
      local s = pr.sword
      pr.sword = nil
      drawLink0(self, lk, tint)
      pr.sword = s
      return
    end
    return drawLink0(self, lk, tint)
  end

  -- the white filter over the field (Link keeps his palette)
  local xf0 = G.drawCrossfade
  function G:drawCrossfade()
    if xf0 then xf0(self) end
    local w = self.mirrorWarp
    if not (w and w.countdown and self.state == "play") then return end
    local lv = DW.whiteLevel(w)
    if lv <= 0 then return end
    local lg = love.graphics
    lg.push("all")
    lg.setBlendMode("lighten", "premultiplied")
    lg.setColor(lv / 31, lv / 31, lv / 31, 1)
    lg.rectangle("fill", -4096, -4096, 8192, 8192)
    lg.pop()
    drawLink0(self, self.link)
  end

  -- the Light World's load from a building re-makes the portal
  local leave0 = G.leaveRoom
  function G:leaveRoom()
    local r = leave0(self)
    if self.state == "play" and self.link.world == "lw" and self.portalPos then DW.spawnPortal(self) end
    return r
  end

  -- the bunny's song in the Dark World without the pearl
  local Audio = require("src.zelda.alttp.Audio")
  local pfs0 = Audio.playForScreen
  function Audio:playForScreen(screen, world)
    if self.bunny and (world == "dw" or (screen or 0) >= 0x40) then return self:play(DW.BUNNY_SONG) end
    return pfs0(self, screen, world)
  end
end

-- LinkItem_Mirror
function DW.useMirror(game)
  local lk = game.link
  if game.state == "room" and game.interior then
    -- Mirror_SaveRoomData: a palace only (cur_palace_index_x2 != 0xFF)
    local Items = require("src.zelda.alttp.Items")
    if Items.palaceOf(game) == nil then return false end
    local e = game.palaceEntrance or game.interior.entranceId
    if not e then return false end
    game:syncKeys()
    game.mirrorExits = (game.mirrorExits or 0) + 1
    game:enterRoom(e)
    return true
  end
  if game.state ~= "play" or (lk.doorway or 0) ~= 0 then return false end
  if lk.world ~= "dw" then return false end                 -- sound 60 only
  game.portalPos = { x = lk.x, y = lk.y }                   -- bird_travel_x/y[15]
  DW.start(game, "mirror")
  return true
end

return DW
