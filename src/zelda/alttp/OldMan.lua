-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OLD MAN ON THE MOUNTAIN (round 25): Sprite_AD_OldMan and follower 4
-- (zelda3 names; the GBA's tables read at import, file offsets in OFF):
--
--   SpritePrep_OldMan: in room 0xE4 he sits at home (subtype2 2); else he
--   is the lost old man while no one follows Link (gone once Link has the
--   mirror), gone while someone does.
--   Lost (room 0xF0): faces Link (Sprite_DirectionToFaceLink ^ 3); touching
--   him shows message 0x9C (Sprite_ShowMessageOnContact), then he becomes
--   follower 4 (Sprite_BecomeFollower) and which_starting_point = 5.
--   Follower 4 (Follower_OldMan): Link walks at link_speed_setting 12; the
--   follower keeps Link's last 20 steps (Follower_CheckGameMode) and trails
--   20 behind while Link walks, closing to 9 behind (every 4th frame) while
--   he stands. Follower_HandleTrigger: the GBA's kTagalong_IndoorInfos /
--   OutdoorInfos (y, x, bit, message, follower; the GBA message numbers,
--   Text.bmgIndex) by room / area (kTagalong_IndoorRooms / OutdoorRooms,
--   the offsets tables): a spot within 24 x 28 of Link + 12 shows its
--   message once (tagalong_event_flags); message 0x9D (outdoors, area 3,
--   by his house) turns him back into the sprite (OldMan_RevertToSprite,
--   subtype2 1) at the trail's next spot + 2.
--   Entering his house (subtype2 1): Link_ReceiveItem(0x1A) the Magic
--   Mirror, which_starting_point = 1, Link held (OldMan_EnableCutscene);
--   48 frames at (8, 4); then towards the area's overlord (the 0xF9 entry
--   of the area list: his door) at 8 until it is no lower than him; gone,
--   Link free.
--   At home (subtype2 2): Sprite_ShowSolicitedMessage of
--   kOldMountainManMsgs[sram_progress >= 3 ? 2 : moon pearl] (the GBA's
--   0xA1-0xA3), then link_hearts_filler = 160.
--   OldMountainMan_Draw: kOldMountainMan_Dmd1 (by D * 4 + gfx * 2) with the
--   follower tiles kOldMountainMan_Dma (dma_var6 / 7) of follower 4's sheet;
--   at home kOldMountainMan_Dmd0.
--
-- OURS: the follower is drawn with his own sprite picture (Tagalong_Draw's
-- per-follower tables are not ported), always under Link; the trail is
-- reset to Link's spot when a room or area loads (Follower_Initialize);
-- the sitting old man is not a barrier; no sound.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local OM = {}

OM.TYPE = 0xAD
OM.FOLLOWER = 4
OM.MIRROR = 0x1A
OM.MSG_LOST = 0x9C
OM.MSG_REVERT = 0x9D

OM.OFF = {
  msgs = 0x176178,          -- kOldMountainManMsgs (3 u16, GBA numbers)
  dmd0 = 0x176180, dmd1 = 0x176190, dma = 0x176210,
  inRooms = 0x17EC48, inInfos = 0x17EC56, outRooms = 0x17ECCE, outInfos = 0x17ECD4,
  inOffs = 0x17ED06, outOffs = 0x17ED0E,
}

local function dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end
local function infos(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local w = rom:bytesU16(o + i * 10, 5)
    t[i + 1] = { y = w[1], x = w[2], bit = w[3], msg = w[4], follower = w[5] }
  end
  return t
end

function OM.extract(rom, R, check)
  local O = OM.OFF
  local t = {
    msgs = rom:bytesU16(O.msgs, 3), dmd0 = dmd(rom, O.dmd0, 2), dmd1 = dmd(rom, O.dmd1, 16),
    dma = rom:bytesU8(O.dma, 16),
    inRooms = rom:bytesU16(O.inRooms, 7), inInfos = infos(rom, O.inInfos, 12), inOffs = rom:bytesU8(O.inOffs, 8),
    outRooms = rom:bytesU16(O.outRooms, 3), outInfos = infos(rom, O.outInfos, 5), outOffs = rom:bytesU8(O.outOffs, 4),
  }
  check(t.msgs[2] == t.msgs[1] + 1 and t.dmd0[1][5] == 2 and t.dmd1[16][5] == 2 and t.dma[1] ~= t.dma[2],
        "old man tables")
  check(t.inRooms[1] == 0xF1 and t.inOffs[8] == 12 and t.outRooms[1] == 3 and t.outOffs[4] == 5
        and t.inInfos[1].follower == 4 and t.outInfos[1].follower == 4, "follower trigger tables")
  return t
end
local function T(game) return game.data.t and game.data.t.oldman end
OM.tabs = T
local function bmg(n) return require("src.zelda.alttp.Text").bmgIndex(n) end

local function hasItem(game, id)
  for _, v in ipairs(game.progress.items or {}) do if v == id then return true end end
  return false
end
OM.hasItem = hasItem

-- ------------------------------------------------------------ the follower
-- Sprite_BecomeFollower / Follower_Initialize: the 20 steps at (x, y)
local function initTrail(game, x, y, facing)
  local tr = {}
  for i = 0, 19 do tr[i] = { x, y, facing or 2 } end
  game.omTrail = { t = tr, v1 = 0, v2 = 0, key = game.omKey and game:omKey() }
end
function OM.becomeFollower(game, x, y)
  game.progress.follower = OM.FOLLOWER
  game.progress.startPoint = 5   -- which_starting_point
  initTrail(game, x, y, game.link.facing)
end

-- the absolute spot of Link (indoors: the room's place in the 16 x 16 grid)
local function linkAbs(game)
  local lk = game.link
  if game.state == "room" and game.interior then
    local r = game.interior.room
    return (r % 16) * 512 + lk.x, math.floor(r / 16) * 512 + lk.y
  end
  return lk.x, lk.y
end

-- Follower_HandleTrigger for follower 4
local function trigger(game)
  local tb = T(game)
  local list, offs, ix
  if game.state == "room" and game.interior then
    list, offs = tb.inInfos, tb.inOffs
    for j, r in ipairs(tb.inRooms) do if r == game.interior.room then ix = j - 1 break end end
  else
    list, offs = tb.outInfos, tb.outOffs
    local scr = game.area and game.area.parent
    if game.link.world == "dw" then scr = scr and scr + 0x40 end
    for j, r in ipairs(tb.outRooms) do if r == scr then ix = j - 1 break end end
  end
  if not ix then return end
  local lx, ly = linkAbs(game)
  for i = offs[ix + 1] + 1, offs[ix + 2] do
    local e = list[i]
    if e.follower == OM.FOLLOWER then
      local dx, dy = math.abs(lx + 12 - (e.x + 8)), math.abs(ly + 12 - (e.y + 8))
      if dx < 24 and dy < 28 then
        local fl = game.omFlags or 0
        if band(e.bit, fl) ~= 0 then return end
        game.omFlags = bor(fl, e.bit)
        local msg = bmg(e.msg)
        if msg == OM.MSG_REVERT then OM.revert(game) end
        game:showMessage(msg)
        game.omMsgs = (game.omMsgs or 0) + 1
        return
      end
    end
  end
end

-- OldMan_RevertToSprite: the sprite at the trail's next spot + 2
function OM.revert(game)
  local tr = game.omTrail
  local st = (tr.v2 + 1) % 20
  local p = tr.t[st]
  local oa = game:owActorList()
  local a = { type = OM.TYPE, x = p[1] + 2, y = p[2] + 2, lower = false, t = 0, index = -1, dir = 1, state = "idle",
              oldman = true, sub2 = 1, ai = 0, D = math.floor((p[3] or 2) / 2), gfx = 0, delay = 0, vx = 0, vy = 0,
              fx = 0, fy = 0, hp = 255, k = 0 }
  oa.list[#oa.list + 1] = a
  game.progress.follower = 0
  game.omTrail = nil
  game.omCutscene = true
  game.link.speedSetting = 0
end

-- one frame of follower 4 (Follower_CheckGameMode + Follower_OldMan)
function OM.followerFrame(game)
  if (game.progress.follower or 0) ~= OM.FOLLOWER then return end
  local lk = game.link
  local key = game:omKey()
  -- tagalong_event_flags (RAM) are cleared going in or out of doors
  -- (Dungeon_ResetTorchBackgroundAndPlayerInner, ResetAncillaAndCutscene)
  if game.omState ~= game.state then game.omState, game.omFlags = game.state, 0 end
  if not game.omTrail or game.omTrail.key ~= key then initTrail(game, lk.x, lk.y, lk.facing) end
  local tr = game.omTrail
  local moved = tr.lx and (tr.lx ~= lk.x or tr.ly ~= lk.y)
  tr.lx, tr.ly = lk.x, lk.y
  if moved then
    tr.v1 = (tr.v1 + 1) % 20
    tr.t[tr.v1] = { lk.x, lk.y - (lk.z or 0), lk.facing }
  end
  if lk.speedSetting ~= 4 then lk.speedSetting = 12 end
  if not game.textBox then trigger(game) end
  if (game.progress.follower or 0) ~= OM.FOLLOWER then return end
  if moved then
    if tr.v1 == tr.v2 then tr.v2 = (tr.v2 + 1) % 20 end
    tr.walkT = (tr.walkT or 0) + 1
  elseif band(game.frame or 0, 3) == 0 and tr.v1 ~= tr.v2 then
    local t = (tr.v1 - 9) % 20
    if t ~= tr.v2 then tr.v2 = (tr.v2 + 1) % 20; tr.walkT = (tr.walkT or 0) + 1 end
  end
end

-- ------------------------------------------------------------ the sprite
local function towards(a, tx, ty, vel)
  local A = require("src.zelda.alttp.Actors")
  return A.project(a.x, a.y, tx, ty, vel)
end
local function moveXY(a)
  local px = a.x * 16 + (a.fx or 0) + (a.vx or 0)
  local py = a.y * 16 + (a.fy or 0) + (a.vy or 0)
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
end

-- the area list's overlord 0xF9 (his door), world spot
local function doorSpot(game)
  local t = game.data.t and game.data.t.npc
  if not (t and game.area) then return nil end
  local prog = game:storyProgress()
  local phase = (prog == 2 and 2) or (prog == 3 and 3) or 1
  local list = t.ow[phase] and t.ow[phase][game.area.parent + 1]
  for _, e in ipairs(list or {}) do
    if e[3] == 0xF9 then return game.area.x + e[2] * 16, game.area.y + e[1] * 16 end
  end
end

function OM.prep(self, a)
  local game = self.game
  a.oldman, a.prepped = true, true
  a.ai, a.delay, a.gfx, a.vx, a.vy, a.fx, a.fy = 0, 0, 0, 0, 0, 0, 0
  a.D, a.k = 1, a.k or 0
  if self.room == 0xE4 then a.sub2 = 2 return end
  a.sub2 = a.sub2 or 0
  if (game.progress.follower or 0) == 0 then
    if hasItem(game, OM.MIRROR) then a.dead = true end
  else
    a.dead = true
  end
end

function OM.update(self, a, lk)
  local game = self.game
  if not a.prepped and a.sub2 ~= 1 then OM.prep(self, a) end
  a.prepped = true
  if a.dead then return end
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  if game.textBox then return end
  if a.sub2 == 0 then
    if a.ai == 0 then
      -- head (and body) towards Link
      local dx, dy = lk.x - a.x, lk.y + 8 - a.y
      local d
      if math.abs(dx) >= math.abs(dy) then d = dx < 0 and 1 or 0 else d = dy < 0 and 3 or 2 end
      a.D = bxor(d, 3)
      -- Sprite_ShowMessageOnContact: Link's box on his
      local A = require("src.zelda.alttp.Actors")
      local cb = game.data.roomIdx.combat
      local hx, hy, hw, hh = A.hitbox(cb, a)
      local lx, ly, lw, lh = A.linkBox(lk)
      if A.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) then
        game:showMessage(OM.MSG_LOST)
        a.ai = 1
      end
    else
      OM.becomeFollower(game, a.x, a.y)
      a.dead = true
      game.omFollowed = (game.omFollowed or 0) + 1
    end
  elseif a.sub2 == 1 then
    moveXY(a)
    if a.ai == 0 then
      a.ai = 1
      game:getItem(OM.MIRROR)
      game.progress.startPoint = 1
      game.omCutscene = true
      a.delay, a.vx, a.vy, a.D = 48, 8, 4, 3
      local rm = game:receiptMessage(OM.MIRROR)
      game.holdItem = { item = OM.MIRROR, t = 0 }
      if rm and game:showMessage(rm) then
        game.onTextDone = function(g) g.holdItem = nil end
      else
        game.holdItem = nil
      end
      game.omMirror = true
    elseif a.ai == 1 then
      game.omCutscene = true
      if a.delay == 0 then a.ai = 2 end
      a.gfx = band(rshift(bxor(a.k or 0, self.frame), 3), 1)
    elseif a.ai == 2 then
      a.D = 0
      local tx, ty = doorSpot(game)
      if not tx or ty >= a.y then
        a.ai, a.vx, a.vy = 3, 0, 0
      else
        a.vx, a.vy = towards(a, tx, ty, 8)
        a.gfx = band(rshift(bxor(a.k or 0, self.frame), 3), 1)
        game.omCutscene = true
      end
    else
      a.dead = true
      game.omCutscene = nil
      game.omHome = true
    end
  end
end

-- the sitting old man's message (A in front of him)
function OM.talk(game, a)
  local tb = T(game)
  local j = (game:storyProgress() >= 3) and 2 or (hasItem(game, 0x1F) and 1 or 0)   -- 0x1F: the Moon Pearl
  game:showMessage(bmg(tb.msgs[j + 1]))
  game.onTextDone = function(g) g.stats.health = g.stats.healthMax end   -- link_hearts_filler 160
  game.omTalks = (game.omTalks or 0) + 1
  return true
end

-- ------------------------------------------------------------ drawing
local function rgba(c)
  return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31
end
-- follower 4's 16 x 16 tiles at DMA offset var (the follower sheet, as
-- Sprites.followerImage for Zelda; GBA 0x0812F9A8)
local function followerImage(spr, var, palRow)
  local key = "om" .. var .. ":" .. palRow
  local im = spr.cache[key]
  if im ~= nil then return im or nil end
  local info = spr.info
  local v = info.follower[OM.FOLLOWER + 1] or 0
  -- the GBA's 0x0812F9A8: the follower's base sheet is 0x64 for Zelda (1),
  -- 0x65 for followers 2-8, 0x59 for 9-11, 0x58 else
  local sheet = 0x65 + rshift(v, 11)
  local base = sheet * 4096 + band(v, 0x7FF) + var * 2
  local img = love.image.newImageData(16, 16)
  local src, pal = spr.data.spr, spr.pal[palRow]
  for ty = 0, 1 do
    for tx = 0, 1 do
      local off = base + ty * 0x200 + tx * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local b = src:byte(off + y * 4 + xb + 1) or 0
          local lo, hi = b % 16, math.floor(b / 16)
          if lo ~= 0 then local r, g, bb = rgba(pal[lo]) img:setPixel(tx * 8 + xb * 2, ty * 8 + y, r, g, bb, 1) end
          if hi ~= 0 then local r, g, bb = rgba(pal[hi]) img:setPixel(tx * 8 + xb * 2 + 1, ty * 8 + y, r, g, bb, 1) end
        end
      end
    end
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  spr.cache[key] = im
  return im
end

local function oamFlags(spr) return band(spr.info.flags3[OM.TYPE + 1] or 0, 0x0F) end
function OM.drawMan(spr, tb, D, gfx, x, y)
  local f = oamFlags(spr)
  local j = (D or 1) * 4 + (gfx or 0) * 2
  for part = 1, 0, -1 do
    local e = tb.dmd1[j + part + 1]
    local var = tb.dma[j + part + 1] or 0
    local fl = bxor(e[4], f)
    local im = followerImage(spr, var, band(rshift(fl, 1), 7))
    local hf = band(fl, 0x40) ~= 0
    love.graphics.draw(im, x + e[1] + (hf and 16 or 0), y + e[2], 0, hf and -1 or 1, 1)
  end
end

function OM.draw(spr, a, x, y, frame)
  local tb = spr.data.t and spr.data.t.oldman
  if not tb then return false end
  if a.sub2 == 2 then
    spr:drawDmd(a, tb.dmd0, 0, 2, x, y, oamFlags(spr))
  else
    OM.drawMan(spr, tb, a.D, a.gfx, x, y)
  end
  return true
end

-- ------------------------------------------------------------ install
function OM.install(G)
  function G:omKey()
    if self.state == "room" and self.interior then return "r" .. self.interior.room end
    return "a" .. tostring(self.area and self.area.parent) .. self.link.world
  end
  local Actors = require("src.zelda.alttp.Actors")
  local up0 = Actors.update
  function Actors:update()
    local game = self.game
    if game and T(game) then
      for _, a in ipairs(self.list) do
        if a.type == OM.TYPE and not a.dead then OM.update(self, a, game.link) end
      end
    end
    return up0(self)
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if a.type == OM.TYPE and self.data.t and self.data.t.oldman then return OM.draw(self, a, x, y, frame) end
    return da0(self, a, x, y, frame, room)
  end
  -- the follower, each frame (rooms and the overworld)
  local upd0 = G.update
  function G:update(dt)
    local r = upd0(self, dt)
    if (self.state == "play" or self.state == "room") and T(self) and not self.roomScroll and not self.scroll then
      OM.followerFrame(self)
    end
    return r
  end
  -- held while the old man walks home (OldMan_EnableCutscene)
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if self.omCutscene then self.link.moving = false return true end
    return owFrame(self, inp)
  end
  -- A in front of the old man at home (Sprite_ShowSolicitedMessage)
  local roomFrame = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if inp and inp.a and not self.textBox and self.actors and self.interior and self.interior.room == 0xE4 and T(self) then
      local C = require("src.zelda.alttp.Carry")
      local q = C.QUERY[self.link.facing]
      local px, py = self.link.x + q[1], self.link.y + q[2]
      for _, a in ipairs(self.actors.list) do
        if a.type == OM.TYPE and not a.dead and a.sub2 == 2 and px >= a.x - 2 and px < a.x + 18 and py >= a.y - 2 and py < a.y + 18 then
          OM.talk(self, a)
          return true
        end
      end
    end
    return roomFrame(self, inp)
  end
  -- the follower drawn under Link
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk == self.link and not tint and (self.progress.follower or 0) == OM.FOLLOWER and self.omTrail and T(self) then
      local spr = self:shadowSprites()
      if spr then
        local tr = self.omTrail
        local p = tr.t[tr.v2]
        local moving = tr.v1 ~= tr.v2
        OM.drawMan(spr, T(self), math.floor((p[3] or 2) / 2), moving and band(rshift(tr.walkT or 0, 3), 1) or 0,
                   p[1] - self.cam.x, p[2] - self.cam.y)
      end
    end
    return dl0(self, lk, tint)
  end
end

return OM
