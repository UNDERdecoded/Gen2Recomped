-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MASTER SWORD GROVE (round 29; scaffolded in round 27, team A).
--
-- Special overworld area 0x80. Everything below is read from the GBA ROM:
--
--   Overworld_CheckSpecialSwitchArea (0x08071D7C), called by the overworld
--   transition handler (0x08071E7C) every frame Link is not crossing an
--   edge: the map8 word under (link_x, link_y) (0x08071CCC: the area's map
--   at y - top, x - left, NO +8 / +12) & 0x1FF against
--   kSpecialSwitchArea_Map8 0x14CEBC with the area 0x14CEC4; on a match the
--   room index (+0x9DA) = kSpecialSwitchArea_Exit 0x14CED4 (0x180 for the
--   grove), the direction = 0x14CECC, module 0x0B / submodule 0x17. Room
--   0x180 is an exit-table entry (RomMap exits): area 0x80, Link at
--   (128, 488), scroll (0, 352).
--   The special area's setup (0x08078274): kSpExit_Dir 0x150CC0 (a BYTE
--   table indexed by room - 0x180: Link's facing, the grove 0 = up),
--   kSpExit_SprGfx 0x150CD0 (0x0C), kSpExit_AuxGfx 0x150CE0 (0x2F),
--   Overworld_LoadPalettes(kSpExit_PalSpr 0x150D00, kSpExit_PalBg 0x150CF0)
--   (0x0813084C: sprite set 1, BG set 0x0A), the area origin kSpExit_Top
--   0x150C80 / kSpExit_LeftEdge 0x150CA0 (u16, grove 0 / 0).
--   The way back (0x08078708): map8 & 0x1FF against kSpecialSwitchAreaB
--   0x150D10 with the area 0x150D16 (grove 0x17C / 0x80), direction 0x150D1C
--   (4 = down), submodule 0x24.
--
--   Sprite 0x62 (MasterSword, routine 0x080D52D0, subtypes via 0x174FB4):
--   subtype 0 = the sword in the pedestal (0x080D52FC): gone when the
--   area's event bit 0x40 is set (0x02002280 + area); drawn by
--   MasterSword_Draw (0x080D4FAC: six 8x8 OAMs, X 0x175084, Y 0x17508A,
--   chars 0x175090, the sprite's own flags) except in state 5; states
--   (0x174FCC):
--     0 (0x080D4660): not while Link is busy (0x0809E3CC); Link touching it
--       (Sprite_CheckDamageToLink_same_layer 0x080C500C), Link's facing
--       (+0x16D5) == 2, the pendants byte (0x02002354) & 7 == 7, then the
--       action button -> Link held (+0x180D = 1), three pendants (0x080D4DA4
--       with flags 9, 0x0B, 0x0F), the light ball (0x080D5414, subtype 4),
--       state 1, delay 0xF0;
--     1: at delay 0 -> the light well (0x080D5464, subtype 1), state 2,
--       delay 0xC0, Link's pose byte (+0x1809) 0x0A;
--     2: at 0 -> light beams set 0 (0x080D4AC4), state 3, delay 8;
--     3: at 0 -> light beams set 1, state 4, delay 0x10, pose 0x0B;
--     4: at 0 -> event bit 0x40, receipt of item 1 (0x080A1588: the Master
--       Sword, sword level 2), pose 0, state 5.
--   subtype 3 = a pendant (0x080D5370; states 0x175078): spawned at
--   (link_x, link_x + 8) -- the GBA reads link_x for both (+0x16C4) --
--   with velocities kPendant_Xv / Yv 0x175070 / 0x175074 [(flags >> 1) & 3],
--   delay 0xE4; state 0 moves until the delay ends (delay 0xD0); state 1
--   flashes its palette ((slot * 2 ^ frame) & 0x0E); state 2 moves, every
--   6 frames doubling its 8-bit velocities. Drawn with the sprite's single
--   graphic 4 (0x080C6240) in its own flags.
--   subtype 4 = the light ball (0x080D492C) and subtype 1 = the light well
--   (0x080D4898): a counter each frame (dies when it wraps), frame
--   (counter >> 2) & 3, drawn with one 8-byte entry of 0x174FF8 [gfx * 4 +
--   frame] (12 entries; gfx 0 for the ball, kMasterSword_Gfx1 0x174FE4
--   [counter >> 5] for the well).
--
-- OURS / NOT PORTED: the switch is instant (the GBA's submodule 0x17 /
-- 0x24 fades are not traced); on the way back Link is put on the spot he
-- left the Lost Woods from and walks 16 px down (the GBA's restore is not
-- traced); in the grove, the 32 px under the map are walkable so Link can
-- reach the 0x17C row (our down probe is y + 23); the music cue (+0xA3C =
-- 0x19) is not played. r32: the light beams (subtype 2) and Link's pull
-- poses (+0x1809) are drawn.
--
-- r53: ZORA'S WATERFALL (special area 0x81). The switch table's entry 2 is
-- area 0x0F's map8 0xAD -> exit 0x182 (screen 0x81, Link at (0x29E,
-- 0x3E8)); the way back is kSpecialSwitchAreaB entry 2 (map8 0xAD in area
-- 0x81, direction 4). The special areas sit on their own 8-wide grid of
-- 512 px screens 0x80.. (kSpExit_Top / LeftEdge [room - 0x180] are the
-- area's origin: 0x182 -> (0x200, 0)); 0x81 is a large area (the parent
-- table 0x14FC30 gives 0x82 / 0x89 / 0x8A -> 0x81), so its map is the four
-- screens' own BG2 / BG1 maps. The per-area tables (sprite set, aux gfx,
-- palettes, facing) are read at [room - 0x180] of the room Link came in by
-- (the GBA's 0x08078274 indexes them with the room, not the area). Ported
-- entries: M.PORTED (0x181 under the bridge and 0x189 are not followed).
-- OURS: as for the grove, the switch is instant, the way back puts Link on
-- the spot he left from (walking 16 px down), and 32 px under the area are
-- walkable so the exit row can be reached; the music is Audio.musicFor's
-- rule for area 0x81 (the GBA's special-area music cue not traced).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = {}

M.AREA, M.TYPE, M.ROOM = 0x80, 0x62, 0x180
M.EVENT = 0x40
M.ZORA = 0x81                                   -- r53
M.PORTED = { [0x180] = true, [0x182] = true }   -- r53: the special exits followed
M.cur = nil   -- r53: the special area Link is in (screenAt is static)
M.SWORD = 1        -- receipt id: the Master Sword

M.OFF = {
  swMap8 = 0x14CEBC, swArea = 0x14CEC4, swDir = 0x14CECC, swExit = 0x14CED4,
  bMap8 = 0x150D10, bArea = 0x150D16, bDir = 0x150D1C,
  top = 0x150C80, left = 0x150CA0, dir = 0x150CC0, sprGfx = 0x150CD0, auxGfx = 0x150CE0,
  palBg = 0x150CF0, palSpr = 0x150D00,
  gfx1 = 0x174FE4, numBeams = 0x174FED, ballDmd = 0x174FF8,
  pendXv = 0x175070, pendYv = 0x175074,
  beams = 0x175058,   -- r32: kMasterSword_LightBeam_Xv0..3 / Yv0..3 / Gfx0 / Gfx2 / Flags0 / Flags2 (2 each)
  drawX = 0x175084, drawY = 0x17508A, drawChar = 0x175090,
}

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end

function M.extract(rom, R, check)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local u16 = function(o, n) return rom:bytesU16(o, n) end
  local t = {
    swMap8 = u16(O.swMap8, 4), swArea = u16(O.swArea, 4), swDir = u16(O.swDir, 4), swExit = u16(O.swExit, 4),
    bMap8 = u16(O.bMap8, 3), bArea = u16(O.bArea, 3), bDir = u16(O.bDir, 3),
    top = u16(O.top, 16), left = u16(O.left, 16), dir = u8(O.dir, 16), sprGfx = u8(O.sprGfx, 16),
    auxGfx = u8(O.auxGfx, 16), palBg = u8(O.palBg, 16), palSpr = u8(O.palSpr, 16),
    gfx1 = u8(O.gfx1, 9), numBeams = u8(O.numBeams, 8),
    pendXv = s8(u8(O.pendXv, 4)), pendYv = s8(u8(O.pendYv, 4)),
    drawX = s8(u8(O.drawX, 6)), drawY = s8(u8(O.drawY, 6)), drawChar = u8(O.drawChar, 6),
    ball = {},
    beams = u8(O.beams, 24),   -- r32
  }
  for i = 1, 16 do if t.beams[i] >= 128 then t.beams[i] = t.beams[i] - 256 end end
  for i = 0, 11 do
    local x, y = s16(u16(O.ballDmd + i * 8, 2))[1], s16(u16(O.ballDmd + i * 8, 2))[2]
    local b = u8(O.ballDmd + i * 8 + 4, 4)
    t.ball[i + 1] = { x, y, b[1], b[2], b[4] }
  end
  check(t.swMap8[1] == 0x105 and t.swArea[1] == 0 and t.swExit[1] == M.ROOM and t.bMap8[1] == 0x17C
        and t.bArea[1] == M.AREA and t.sprGfx[1] == 0x0C and t.palBg[1] == 0x0A, "grove switch tables")
  check(t.drawChar[1] == 0x93 and t.drawChar[6] == 0xF0 and t.drawX[1] == -8 and t.drawY[6] == 8
        and t.pendXv[1] == -4 and t.pendYv[4] == -4 and t.ball[1][3] == 0x82 and t.ball[1][5] == 2, "master sword tables")
  check(t.swArea[3] == 0x0F and t.swExit[3] == 0x182 and t.bArea[3] == M.ZORA and t.bMap8[3] == t.swMap8[3]
        and t.top[3] == 0 and t.left[3] == 0x200, "zora switch tables")   -- r53
  return t
end

local function T(game) local t = game.data.t and game.data.t.grove return t and t.swMap8 and t end
M.tabs = T

-- --------------------------------------------------------------- the world
-- the map8 tile number under (x, y) of the world's base map (0x08071CCC)
function M.map8(game, world, x, y)
  local O = require("src.zelda.alttp.Overworld")
  local s = O.screenAt(world, x, y)
  if not s then return nil end
  local n = game.data:mapNumber("bg2", s)
  if not n then return nil end
  return band(game.data:mapWord(n, O.cellIndex(math.floor((x % 512) / 8), math.floor((y % 512) / 8))), 0x1FF)
end

local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
function M.swordTaken(game)
  return band(events(game)[tostring(M.AREA)] or 0, M.EVENT) ~= 0
end

local function exitOf(game, room)
  local ex = game.data.roomIdx and game.data.roomIdx.exits
  if not ex then return nil end
  for k = #ex.rooms, 1, -1 do
    if ex.rooms[k] == room then return { x = ex.x[k], y = ex.y[k], screen = ex.screens[k] } end
  end
end

-- r53: the kSpExit_* index ([room - 0x180]) of a special area: the first
-- ported switch exit whose screen belongs to it
function M.idxOf(data, area)
  local tb = data.t and data.t.grove
  local ex = data.roomIdx and data.roomIdx.exits
  if not (tb and ex) then return area - M.AREA end
  data.spIdx53 = data.spIdx53 or {}
  local c = data.spIdx53[area]
  if c then return c end
  for j = 1, #tb.swExit do
    local room = tb.swExit[j]
    if M.PORTED[room] then
      for k = #ex.rooms, 1, -1 do
        if ex.rooms[k] == room and data.t.owParent[ex.screens[k] + 1] == area then
          data.spIdx53[area] = room - M.ROOM
          return room - M.ROOM
        end
      end
    end
  end
  return area - M.AREA
end

-- r53: the special grid's screen at (x, y) (8 screens a row from 0x80)
function M.gridScreen(x, y)
  local sx, sy = math.floor(x / 512), math.floor(y / 512)
  if sx < 0 or sy < 0 or sx > 7 or sy > 3 then return nil end
  return M.AREA + sy * 8 + sx
end

-- r53: M.cur = the area rectangle Link is in (from the parent table);
-- `s` a screen of it, else Link's own spot (a game loaded in the area)
function M.setCur(game, s)
  local lk = game.link
  if lk.world ~= "sp" then M.cur = nil return nil end
  s = s or M.gridScreen(lk.x + 8, math.min(lk.y + 16, 4 * 512 - 1))
  if not s then M.cur = nil return nil end
  local p = game.ow:parent(s)
  if p == M.AREA then M.cur = { area = M.AREA, x = 0, y = 0, w = 512, h = 512, game = game } return M.cur end
  local a = game.ow:area(s)
  M.cur = { area = a.parent, x = a.x, y = a.y, w = a.w, h = a.h, game = game }
  return M.cur
end

local function newArea(game)
  game.owActors, game.oweState = nil, nil
  game.drops, game.debris, game.anc = nil, nil, nil
  game.area = game.ow:area(game:screen())
  game.cam = game:cameraFor(game.area)
  game.ow.attrCache = {}
  if game.music and game.music.playForScreen then pcall(game.music.playForScreen, game.music, game.area.parent, game.link.world) end
end

-- into the grove (submodule 0x17's end state)
function M.enter(game, i)
  local tb = T(game)
  local room = tb.swExit[i]
  local e = exitOf(game, room)
  if not (e and M.PORTED[room] and e.screen >= M.AREA) then return false end   -- r53: any ported special exit
  local lk = game.link
  game.groveBack = { world = lk.world, x = lk.x, y = lk.y }
  if game.dropCarry then game:dropCarry() end
  game.dash, game.swing, game.recoil = nil, nil, nil
  lk.world, lk.x, lk.y = "sp", e.x, e.y
  lk.facing = tb.dir[room - M.ROOM + 1] or 0
  lk.steps, lk.moving = 0, false
  game.exitWalk = nil
  M.setCur(game, e.screen)   -- r53
  newArea(game)
  game.spEntered53 = room
  game.groveEntered = (game.groveEntered or 0) + 1
  return true
end

-- back to the Lost Woods (submodule 0x24's end state)
function M.leave(game, i)
  local tb = T(game)
  local lk = game.link
  local back = game.groveBack
  if not back then
    -- OURS: a game loaded in the grove: the first 0x105 cell of area 0
    -- r53: (any special area: the switch whose exit leads into it)
    local j = 1
    for k = 1, #tb.swExit do
      local e = exitOf(game, tb.swExit[k])
      if M.PORTED[tb.swExit[k]] and e and game.ow:parent(e.screen) == tb.bArea[i] then j = k break end
    end
    back = M.switchSpot(game, j)
    if not back then return false end
  end
  if game.dropCarry then game:dropCarry() end
  game.dash, game.swing, game.recoil = nil, nil, nil
  lk.world, lk.x, lk.y = back.world or "lw", back.x, back.y
  local d = tb.bDir[i] or 4
  lk.facing = (d == 8 and 0) or (d == 4 and 2) or (d == 2 and 4) or 6
  lk.steps = 0
  game.groveBack = nil
  M.cur = nil   -- r53
  newArea(game)
  game.exitWalk, game.exitWalkTail = 16, nil
  game.groveLeft = (game.groveLeft or 0) + 1
  return true
end

-- the spot of switch i's tile in its area (top-left of the first cell)
function M.switchSpot(game, i)
  local tb = T(game)
  local O = require("src.zelda.alttp.Overworld")
  local area = tb.swArea[i]
  local world = area >= 0x40 and "dw" or "lw"
  for _, s in ipairs({ area, area + 1, area + 8, area + 9 }) do
    if game.ow:parent(s) == area then
      local n = game.data:mapNumber("bg2", s)
      local ox, oy = O.screenOrigin(s)
      for c = 0, 4095 do
        if band(game.data:mapWord(n, c), 0x1FF) == tb.swMap8[i] then
          local tx = (math.floor(c / 1024) % 2) * 32 + c % 32
          local ty = math.floor(c / 2048) * 32 + math.floor((c % 1024) / 32)
          return { world = world, x = ox + tx * 8, y = oy + ty * 8 }
        end
      end
    end
  end
end

-- the per-frame checks (0x08071D7C outside, 0x08078708 in the grove)
function M.switchCheck(game)
  local tb = T(game)
  if not tb or game.exitWalk and game.exitWalk > 0 then return end
  local lk = game.link
  local a = game.area and game.area.parent
  if not a then return end
  local m = M.map8(game, lk.world, lk.x, lk.y)
  if not m then return end
  if lk.world == "sp" then
    for i = #tb.bMap8, 1, -1 do
      if tb.bMap8[i] == m and tb.bArea[i] == a then return M.leave(game, i) end
    end
  else
    for i = #tb.swMap8, 1, -1 do
      -- the grove's and (r53) Zora's exits are ported (0x181 / 0x189 lead
      -- to the other special areas)
      if tb.swMap8[i] == m and tb.swArea[i] == a and M.PORTED[tb.swExit[i]] then return M.enter(game, i) end
    end
  end
end

-- --------------------------------------------------------------- the sword
local function spawnSprite(oa, sub, x, y, extra)
  local a = { type = M.TYPE, grove = true, sub = sub, x = x, y = y, t = 0, hp = 255, lower = false,
              state = "idle", ai = 0, delay = 0, cnt = 0, gfx = 0, frame = 0, untouchable = true, noTouch = true }
  for k, v in pairs(extra or {}) do a[k] = v end
  a.k = #oa.list
  oa.list[#oa.list + 1] = a
  return a
end

function M.spawnArea(game, oa)
  if oa.groveDone then return end
  oa.groveDone = true
  if not (game.area and game.area.parent == M.AREA and game.link.world == "sp") then return end
  if M.swordTaken(game) then return end
  local t = game.data.t and game.data.t.npc
  local prog = game:storyProgress()
  local phase = (prog == 3 and 3) or 2
  local list = t and t.ow[phase] and t.ow[phase][M.AREA + 1]
  for _, e in ipairs(list or {}) do
    -- r43: SpritePrep_MasterSword (GBA 0x080D52A4, prep table 0x17451C
    -- entry 0x62): sprite_x_lo / sprite_y_lo += 6 (the low bytes only); the
    -- port had left it out, so Link at the stone's notch did not touch the
    -- sword's 4 x 8 hit box and the pedestal could not be pulled
    if e[3] == M.TYPE then
      local x, y = e[2] * 16, e[1] * 16
      spawnSprite(oa, 0, band(x, 0xFF00) + band(x + 6, 0xFF), band(y, 0xFF00) + band(y + 6, 0xFF))
    end
  end
end

local function touching(actors, a, lk)
  return require("src.zelda.alttp.Desert").touching(actors, a, lk)
end

local function busy(game)
  return game.textBox or game.carry or game.swing or game.dash or game.recoil or game.holdItem or game.receipt
end

-- the pedestal (subtype 0)
local function pedestal(actors, a, lk)
  local game = actors.game
  if M.swordTaken(game) and a.ai ~= 5 then a.dead = true return end
  if a.ai == 0 then
    if busy(game) then return end
    if not touching(actors, a, lk) then return end
    if lk.facing ~= 2 then return end
    if band(game.progress.pendants or 0, 7) ~= 7 then return end
    local inp = game.owInp
    if not (inp and inp.a) then return end
    inp.a = false
    game.groveHold = true
    for _, f in ipairs({ 9, 0x0B, 0x0F }) do
      local j = band(rshift(f, 1), 3)
      local tb = T(game)
      spawnSprite(actors, 3, lk.x, lk.x + 8, { flags = f, vx = tb.pendXv[j + 1], vy = tb.pendYv[j + 1],
                                              delay = 0xE4, gfx = 4, fx = 0, fy = 0 })
    end
    spawnSprite(actors, 4, a.x, a.y, { flags = 5 })
    a.ai, a.delay = 1, 0xF0
    game.groveSwordPulls = (game.groveSwordPulls or 0) + 1
  elseif a.delay == 0 then
    if a.ai == 1 then
      spawnSprite(actors, 1, a.x, a.y, { flags = 5 })
      a.ai, a.delay, game.grovePose = 2, 0xC0, 0x0A
    elseif a.ai == 2 then
      a.ai, a.delay, game.grovePose = 3, 8, 0x0A
      M.spawnBeams(actors, a, 0, 0xFF)   -- r32
    elseif a.ai == 3 then
      M.spawnBeams(actors, a, 1, 0xFF)   -- r32
      a.ai, a.delay, game.grovePose = 4, 0x10, 0x0B
    elseif a.ai == 4 then
      local ev = events(game)
      ev[tostring(M.AREA)] = bor(ev[tostring(M.AREA)] or 0, M.EVENT)
      game.grovePose = 0
      a.ai = 5
      M.receive(game)
    end
  end
end

-- receipt of the Master Sword (Link holds it up; the message; freed after)
function M.receive(game)
  game:getItem(M.SWORD)
  local msg = game.receiptMessage and game:receiptMessage(M.SWORD)
  game.holdItem = { item = M.SWORD, t = 0 }
  if msg and game:showMessage(msg) then
    local prev = game.onTextDone
    game.onTextDone = function(g) g.holdItem = nil; g.groveHold = nil; if prev then prev(g) end end
  else
    game.holdItem, game.groveHold = nil, nil
  end
end

-- 8-bit velocity steps (Sprite_MoveXY: 1/16 px)
local function moveXY(a)
  a.fx, a.fy = (a.fx or 0) + a.vx, (a.fy or 0) + a.vy
  local mx = a.fx >= 0 and math.floor(a.fx / 16) or -math.floor(-a.fx / 16)
  local my = a.fy >= 0 and math.floor(a.fy / 16) or -math.floor(-a.fy / 16)
  a.fx, a.fy = a.fx - mx * 16, a.fy - my * 16
  a.x, a.y = a.x + mx, a.y + my
end
local function sbyte(v) v = band(v, 0xFF) return v >= 128 and v - 256 or v end

local function pendant(actors, a)
  local game = actors.game
  if a.ai == 0 then
    moveXY(a)
    if a.delay == 0 then a.ai, a.delay, a.saved = 1, 0xD0, a.flags end
  elseif a.ai == 1 then
    a.flags = bor(band(a.flags, 0xF1), band(bxor(a.k * 2, game.frame or 0), 0x0E))
    if a.delay == 0 then a.ai, a.flags = 2, a.saved end
  else
    moveXY(a)
    if a.delay == 0 then
      a.vx, a.vy, a.delay = sbyte(a.vx * 2), sbyte(a.vy * 2), 6
      a.cnt = band(a.cnt + 1, 0xFF)
      if a.cnt == 0 then a.dead = true end
    end
  end
end

-- r32: the light beams (subtype 2; the GBA's 0x080D4AC4 spawn / 0x080D4998
-- routine = MasterSword_SpawnLightBeam / Sprite_MasterSword_LightBeam): four
-- beams from (x - 4, y + 4), velocities / pictures / flags by `ain` from the
-- cartridge's table; a moving beam leaves a still copy (3 frames) every 4th
-- frame and only counts its life down on those frames. Spawns fail once 16
-- sprites are out (the sprite slots; OURS: slot order not modelled).
local function slotsFull(actors)
  local n = 0
  for _, b in ipairs(actors.list) do if not b.dead then n = n + 1 end end
  return n >= 16
end
function M.spawnBeams(actors, p, ain, life)
  local tb = T(actors.game)
  local B = tb and tb.beams
  if not B then return end
  -- per beam: x velocity, y velocity, picture, flags (tables of two by ain)
  local rows = {
    { B[1 + ain], B[9 + ain], B[17 + ain], B[21 + ain] },
    { B[3 + ain], B[11 + ain], B[17 + ain], B[21 + ain] },
    { B[5 + ain], B[13 + ain], B[19 + ain], B[23 + ain] },
    { B[7 + ain], B[15 + ain], B[19 + ain], B[23 + ain] },
  }
  for _, r in ipairs(rows) do
    if slotsFull(actors) then return end
    spawnSprite(actors, 2, p.x - 4, p.y + 4, { vx = r[1], vy = r[2], gfx = r[3], flags = r[4], life = life,
                                             beamMoving = true, fx = 0, fy = 0 })
  end
end

local function beam(actors, a)
  if a.beamMoving then   -- (Actors clears a.moving)
    moveXY(a)
    if band(actors.game.frame or 0, 3) ~= 0 then return end
    if not slotsFull(actors) then
      spawnSprite(actors, 2, a.x, a.y, { gfx = a.gfx, flags = a.flags, life = 3 })
    end
  end
  a.life = band((a.life or 1) - 1, 0xFF)
  if a.life == 0 then a.dead = true end
end

local function light(actors, a)
  local tb = T(actors.game)
  a.cnt = band(a.cnt + 1, 0xFF)
  if a.cnt == 0 then a.dead = true return end
  a.frame = band(rshift(a.cnt, 2), 3)
  if a.sub == 1 then a.gfx = tb.gfx1[rshift(a.cnt, 5) + 1] or 0 else a.gfx = 0 end
  -- r32: the fountain's beams (kMasterSword_NumLightBeams[cnt >> 5])
  local n = a.sub == 1 and tb.numBeams[rshift(a.cnt, 5) + 1] or 0
  if n > 0 and tb.beams then M.spawnBeams(actors, a, band(rshift(a.cnt, 2), 1), n) end
end

function M.update(actors, a, lk)
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  if a.sub == 0 then return pedestal(actors, a, lk)
  elseif a.sub == 3 then return pendant(actors, a)
  elseif a.sub == 2 then return beam(actors, a)   -- r32
  else return light(actors, a) end
end

function M.draw(spr, a, x, y)
  local tb = spr.data.t and spr.data.t.grove
  if not (tb and tb.drawChar) then return false end
  if a.sub == 0 then
    if a.ai == 5 then return true end
    local f = band(spr.info.flags3[M.TYPE + 1] or 0, 0x0F)
    for i = 6, 1, -1 do spr:oam(x + tb.drawX[i], y + tb.drawY[i], tb.drawChar[i], f, 0) end
  elseif a.sub == 3 or a.sub == 2 then   -- r32: the beams are SpriteDraw_SingleLarge too
    local info = spr.info
    local ch = info.single2[(info.single1[M.TYPE + 1] or 0) + (a.gfx or 4) + 1]
    if ch then spr:oam(x, y, ch, a.flags or 0, 2) end
  else
    local e = tb.ball[(a.gfx or 0) * 4 + (a.frame or 0) + 1]
    if e then spr:oam(x + e[1], y + e[2], e[3], bxor(e[4], a.flags or 0), e[5]) end
  end
  return true
end

-- --------------------------------------------------------------- install
function M.install(G)
  local O = require("src.zelda.alttp.Overworld")
  local P = require("src.zelda.alttp.Palette")
  -- world "sp": the special area's map (area 0x80 at kSpExit_Top / Left 0, 0)
  local screenAt0 = O.screenAt
  function O.screenAt(world, x, y)
    if world == "sp" then
      -- r53: the area Link is in (M.cur), on the special grid, with 32 px
      -- under it
      local c = M.cur
      if c and c.area ~= M.AREA then
        if x < c.x or y < c.y or x >= c.x + c.w or y >= c.y + c.h + 32 then return nil end
        return M.gridScreen(x, math.min(y, c.y + c.h - 1))
      end
      if x < 0 or y < 0 or x >= 512 or y >= 544 then return nil end
      return M.AREA
    end
    return screenAt0(world, x, y)
  end
  local attrAt0 = O.attrAt
  function O:attrAt(world, x, y)
    if world == "sp" then
      local c = M.cur
      if c and c.area ~= M.AREA then   -- r53
        if x >= c.x and x < c.x + c.w and y >= c.y + c.h and y < c.y + c.h + 32 then return 0x00 end
      elseif y >= 512 and y < 544 and x >= 0 and x < 512 then return 0x00 end
    end
    return attrAt0(self, world, x, y)
  end
  local area0 = O.area
  function O:area(screen)
    if screen and screen >= 0x80 then
      -- r53: a large special area (0x81) from the parent table
      if self:parent(screen) ~= M.AREA then return area0(self, screen) end
      return { parent = M.AREA, x = 0, y = 0, w = 512, h = 512, big = false }
    end
    return area0(self, screen)
  end
  local sheets0 = O.sheets
  function O:sheets(screen)
    local tb = self.data.t and self.data.t.grove
    local p = self:parent(screen)
    if p and p >= 0x80 and tb and tb.auxGfx then
      local t = self.data.t
      local mt = t.mainTilesets[0x20 + 1]
      local at = t.auxTilesets[tb.auxGfx[M.idxOf(self.data, p) + 1] + 1]   -- r53: by the entry room
      local s = { mt[1], mt[2], mt[3] }
      for k = 1, 4 do s[3 + k] = (at[k] ~= 0xFF) and at[k] or mt[3 + k] end
      s[8] = mt[8]
      return s
    end
    return sheets0(self, screen)
  end
  -- Overworld_LoadPalettes(kSpExit_PalSpr, kSpExit_PalBg): the BG set
  local sel0 = P.selection
  function P.selection(data, screen, phase)
    local s = sel0(data, screen, phase)
    local tb = data.t and data.t.grove
    if screen >= 0x80 and tb and tb.palBg then
      local bg = tb.palBg[M.idxOf(data, data.t.owParent[screen + 1] or screen) + 1]   -- r53
      local info = data.t.owBgPalInfo[bg + 1]
      s.bg, s.aux1, s.aux2, s.aux3 = bg, 3, 3, 0
      if info[1] ~= 0xFF then s.aux1 = info[1] end
      if info[2] ~= 0xFF then s.aux2 = info[2] end
      if info[3] ~= 0xFF then s.aux3 = info[3] end
    end
    return s
  end
  local function fixList(self, list)
    if self.link.world ~= "sp" then return list end
    local out = {}
    -- r53: the special grid's screens of the area Link is in
    local p = self.area and self.area.parent or M.AREA
    for _, v in ipairs(list) do
      if v.s < 32 then
        local s = M.AREA + v.s
        if s == M.AREA and p == M.AREA or p ~= M.AREA and self.ow:parent(s) == p then v.s = s; out[#out + 1] = v end
      end
    end
    return out
  end
  local vis0 = G.visibleScreens
  function G:visibleScreens() return fixList(self, vis0(self)) end
  if G.viewScreens then
    local view0 = G.viewScreens
    function G:viewScreens() return fixList(self, view0(self)) end
  end
  local sset0 = G.owSpriteSet
  function G:owSpriteSet()
    local tb = T(self)
    local p = self.area and self.area.parent
    if p and p >= 0x80 and tb then
      local j = M.idxOf(self.data, p) + 1   -- r53: by the entry room
      return tb.sprGfx[j], tb.palSpr[j]
    end
    return sset0(self)
  end
  -- the switch tiles, after Link's move each frame
  local upd0 = G.update
  function G:update(dt)
    -- r53: which special area (a game loaded or made in one)
    if self.link and self.link.world == "sp" then
      if not M.cur or M.cur.game ~= self then
        M.setCur(self)
        if M.cur then M.cur.game = self end
      end
    elseif M.cur and M.cur.game == self then M.cur = nil end
    local r = upd0(self, dt)
    if self.state == "play" and not self.scroll and not self.textBox and not self.menu and not self.owmap
       and not self.gameOver and not self.gate and not self.exitDoor and T(self) then
      M.switchCheck(self)
    end
    return r
  end
  -- r32: Link's pull poses (+0x1809 = link_unk_master_sword 0x0A / 0x0B:
  -- LinkOam row 0x17 at step pose - 1)
  local pose0 = G.linkPose
  function G:linkPose()
    local p = self.grovePose or 0
    if p > 0 then return 0x17, p - 1 end
    return pose0(self)
  end
  -- Link is held from the pull to the end of the receipt (+0x180D)
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if self.groveHold then self.link.moving = false return true end
    return owFrame(self, inp)
  end
  -- the sprites
  -- (after the people's list: Npc.lua makes it only when it is missing)
  local updOw = G.updateOwActors
  function G:updateOwActors()
    local r = updOw(self)
    if self.state == "play" and self.link.world == "sp" and T(self) and self.area and not self.scroll then
      M.spawnArea(self, self:owActorList())
    end
    return r
  end
  local Actors = require("src.zelda.alttp.Actors")
  local up0 = Actors.update
  function Actors:update()
    local game = self.game
    if self.room == -1 and game and T(game) then
      local lk = game.link
      for _, a in ipairs(self.list) do
        if a.grove and not a.dead then M.update(self, a, lk) end
      end
    end
    return up0(self)
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if a.grove then return M.draw(self, a, x, y) end
    return da0(self, a, x, y, frame, room)
  end
end

return M
