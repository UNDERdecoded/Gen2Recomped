-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 46: KIKI THE MONKEY AND THE PALACE OF DARKNESS'S DOOR (zelda3
-- names; every routine traced on the GBA, its tables read at import).
--
-- Sprite 0xB6 (main 0x080FAFCC: by subtype2 through 0x17A4DC; prep
-- 0x080FAF80: gone once save_ow_event_info[area] & 0x20). Area 0x5E's list
-- (phases 2 / 3) holds him at cell (21, 17).
--   0 Kiki_LyingInWait (0x080FA724): not drawn. On the screen, not paused,
--     +0x176C clear (read here as the bunny, not traced), no blink
--     (countdown_for_blink +0x17AA) and no link_disable_sprite_damage
--     (+0x180D), the follower not already 10 and the area's bit 0x20 clear:
--     touching him (Sprite_CheckDamageToLink_same_layer 0x080C500C) makes him
--     follower 10 (+0x1663), the follower's graphics loaded and its trail
--     made (0x0812F9A8 / 0x08114600). The sprite stays (invisible).
--   1 Kiki_OfferEntrance (0x080FA7CC; spawned by the follower's trigger at
--     the palace, follower 0): drawn; Sprite_MoveXYZ, z speed - 1, landed ->
--     0; by ai_state (0x17A504):
--       0 message 0x11E ("100 Rupees?") -> 1
--       1 choice 0 and 100 Rupees paid (0x0810EF98): 0x120, Link held
--         (+0x1770), D 0 -> 2; else 0x11F, subtype2 3 (he flees)
--       2/4/6 walk at 9 (Sprite_ProjectSpeedTowardsLocation) to the path's
--         spot (x 0x17A538, y 0x17A532, u16 by (ai - 2) / 2); within -2..1
--         of both low bytes: stop, delay_aux1 32 -> ai + 1
--       3/5 D = 6 | (ai >> 1 & 1) while delay_aux1 runs; then ai + 1, z
--         speed 0x17A530[ai >> 1 & 1], D = 4 | (ai >> 1 & 1) (a hop up)
--       7 landed and delay 0: the walk list 0x17A53E (D) / 0x17A541 (delay)
--         by sprite_A, speeds 0x17A543 / 0x17A547 by D; its end (0x80):
--         speeds 0, overworld event 1 (+0xB6E: the door), D 0 -> 8
--       8 D 8, graphics 0, z speed (rng & 15) + 16 -> 9
--       9 landed (z speed negative, z 0) -> 10 (stays)
--   2 Kiki_OfferInitialService (0x080FA53C; spawned by the follower's
--     trigger on the way, the follower stays): drawn from ai 2; move as 1;
--     graphics = frame >> 3 & 1; by ai_state (0x17A4F0):
--       0 message 0x121 ("10 Rupees?") -> 1
--       1 choice 0 and 10 Rupees paid: 0x122, tagalong_event_flags |= 3,
--         the sprite goes (he keeps following); else 0x123, flags & 0xFC,
--         follower 0, Link held -> 2
--       2 towards (0xCF5, 0x6FE) at 9, D = (x speed >> 7) ^ 3, delay 32 -> 3
--       3 delay 0: z speed 16, delay 16 -> 4
--       4 delay 0 and landed: gone, Link free
--   3 Kiki_Flee (0x080FA36C; refused at the palace, or Link hurt while he
--     follows): landed inside x 0xC98 + 0..0xCF, y 0x6A5 + 0..0xCF, or off
--     the screen: gone; z speed - 2, Sprite_MoveXYZ, landed -> hop (z speed
--     (rng & 15) | 16); speeds towards (0xCF5, 0x6FE) at 16, doubled;
--     tagalong_event_flags & 0xFC; D by the larger speed (x: (x >> 7) ^ 3,
--     y: (y >> 7) ^ 1); graphics = frame >> 3 & 1.
-- Kiki_Draw (0x080FACFC): D >= 8: 0x17A65C + graphics * 48 (6 OAM); else
--   j = (D * 2 + graphics) * 2: DMA vars 0x17A54B[j], [j + 1] (follower 10's
--   sheet, chars 0x40 / 0x42) and 0x17A55C + j * 8 (2 OAM; D 4..7 use the
--   sprite sheet's chars); the shadow.
-- THE FOLLOWER (Follower_Main 0x08114DC4, Follower_HandleTrigger
--   0x08115CA4 / 0x08115D30): area 0x5E's rows of the outdoor trigger table
--   (OldMan.lua's outInfos): within 24 x 28 of Link + 12, a row of follower
--   10 that is not marked in tagalong_event_flags marks it; message 0xFFFF
--   is Kiki's (0x08115FA8): bit & 3 == 0 -> Kiki_SpawnHandler_A (subtype2 1,
--   follower 0), else unless save_ow_event_info[area] & 1 ->
--   Kiki_SpawnHandler_B (subtype2 2); spawned at the trail's next spot + 2
--   (0x080FAC20). Link hurt (link_auxiliary_state +0x1702 and the blink)
--   while follower 10 -> Kiki_SpawnHandler_C (subtype2 3, z 1, z speed 16,
--   follower 0).
-- THE DOOR (overworld event 1: 0x0808F148 / 0x0808F2F0, steps 0x153B3C):
--   Link held; step 0 after 0x40 frames sets save_ow_event_info[0x5E] |=
--   0x20 and draws the first map16 change, three steps of 0x20 frames draw
--   the rest, the last 0x20 frames end it (0x0808D788: Link free). The
--   opened door is the area's event overlay (0x153C04[0x5E] = 0x08092038,
--   shared by 0x5E / 0x5F / 0x66 / 0x67), run at import by Castle44's Thumb
--   evaluator; drawn whenever the area loads with the bit.
--
-- OURS: the door's map16 steps are drawn as the finished overlay at the
-- first step; no sounds; +0x176C read as the bunny; Link hurt = the
-- port's recoil while the blink runs.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "kiki46" }

M.TYPE, M.FOLLOWER, M.AREA, M.EV_DOOR = 0xB6, 10, 0x5E, 0x20

M.OFF = {
  hopZv = 0x17A530, pathY = 0x17A532, pathX = 0x17A538, walkDir = 0x17A53E, walkDelay = 0x17A541,
  walkXv = 0x17A543, walkYv = 0x17A547, dma = 0x17A54B, dmd = 0x17A55C, dmdJump = 0x17A65C,
  overlayFns = 0x153C04, bg2 = 0x02018000,
}
-- the code's own numbers (GBA addresses): the messages' calls, the prices,
-- the flee spot and the box where a fleeing Kiki is gone
M.SITES = {
  msg = { offer100 = 0x080FB17A, paid100 = 0x080FA862, refuse100 = 0x080FA8A2,
          offer10 = 0x080FB0B4, paid10 = 0x080FA65C, refuse10 = 0x080FA608 },
  price100 = 0x080FA850, price10 = 0x080FA5F8,           -- movs r0, #n
  fleeXlo = 0x080FA43A, fleeXhi = 0x080FA442, fleeYlo = 0x080FA44A, fleeYhi = 0x080FA452,
  boxX = 0x080FA3A8, boxY = 0x080FA3C4, boxW = 0x080FA3B0,  -- ldr (-x0), ldr (-y0), cmp #w
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
local function s8(t) for i, v in ipairs(t) do if v >= 128 then t[i] = v - 256 end end return t end
-- Thumb `movs rN, #imm8` / `cmp rN, #imm8` at a GBA address
local function imm8(rom, at, want)
  local op = rom:u16(at - 0x08000000)
  if band(op, 0xF800) ~= want then return nil end
  return band(op, 0xFF)
end
-- Thumb `ldr rN, [pc, #]`: the literal
local function lit(rom, at)
  local op = rom:u16(at - 0x08000000)
  if band(op, 0xF800) ~= 0x4800 then return nil end
  local la = band(at + 4, 0xFFFFFFFC) + band(op, 0xFF) * 4
  return rom:u32(la - 0x08000000)
end

function M.extract(rom, R, check)
  local O, S = M.OFF, M.SITES
  local RT = require("src.zelda.alttp.RomTables")
  local t = {
    hopZv = rom:bytesU8(O.hopZv, 2), pathY = rom:bytesU16(O.pathY, 3), pathX = rom:bytesU16(O.pathX, 3),
    walkDir = rom:bytesU8(O.walkDir, 3), walkDelay = rom:bytesU8(O.walkDelay, 2),
    walkXv = s8(rom:bytesU8(O.walkXv, 4)), walkYv = s8(rom:bytesU8(O.walkYv, 4)),
    dma = rom:bytesU8(O.dma, 32), dmd = dmd(rom, O.dmd, 32), dmdJump = dmd(rom, O.dmdJump, 12),
    msg = {}, door = {},
  }
  local ok = true
  for k, at in pairs(S.msg) do
    t.msg[k] = RT.msgAt(rom, at)
    ok = ok and t.msg[k] ~= nil
  end
  t.price100, t.price10 = imm8(rom, S.price100, 0x2000), imm8(rom, S.price10, 0x2000)
  local xl, xh = imm8(rom, S.fleeXlo, 0x2000), imm8(rom, S.fleeXhi, 0x2000)
  local yl, yh = imm8(rom, S.fleeYlo, 0x2000), imm8(rom, S.fleeYhi, 0x2000)
  local bx, by, bw = lit(rom, S.boxX), lit(rom, S.boxY), imm8(rom, S.boxW, 0x2800)
  ok = ok and t.price100 and t.price10 and xl and xh and yl and yh and bx and by and bw and true
  if ok then
    t.fleeX, t.fleeY = xh * 256 + xl, yh * 256 + yl
    t.boxX, t.boxY, t.boxW = 0x100000000 - bx, 0x100000000 - by, bw
  end
  check(ok, "Kiki's code numbers (messages, prices, flee spot)")
  -- the palace door's event overlay (0x153C04[0x5E]), run as Castle44 does
  local C44 = require("src.zelda.alttp.Castle44")
  local fn = rom:u32(O.overlayFns + M.AREA * 4)
  local stores, why = C44.runThumb(rom, band(fn, 0xFFFFFFFE) - 0x08000000)
  local good = stores ~= nil
  for _, s in ipairs(stores or {}) do
    local off = s[1] - O.bg2
    if off < 0 or off >= 0x8000 or off % 2 ~= 0 then good = false break end
    local cx, cy = C44.cellOf(off / 2)
    t.door[#t.door + 1] = { cx, cy, s[2] }
  end
  check(good and #t.door == 16, "palace of darkness door overlay (0x153C04[0x5E]) ran: " .. tostring(why or #t.door))
  check(t.walkDir[3] == 0xFF and t.dmd[1][5] == 2 and t.dmdJump[1][5] == 0 and t.pathX[1] > 0xC00,
        "Kiki's tables")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.kiki46 end
M.tabs = T

-- ------------------------------------------------------------ helpers
local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
function M.event(game, area) return events(game)[tostring(area)] or 0 end
local function setEvent(game, area, b)
  local e = events(game)
  e[tostring(area)] = bor(e[tostring(area)] or 0, b)
end
local function A() return require("src.zelda.alttp.Actors") end
local function rnd(game) return require("src.zelda.alttp.Drops").rng(game:dropRng()) end
local function moveXYZ(a)
  local px = a.x * 16 + (a.fx or 0) + (a.vx or 0)
  local py = a.y * 16 + (a.fy or 0) + (a.vy or 0)
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
  local pz = (a.z or 0) * 16 + (a.fz or 0) + (a.vz or 0)
  a.z, a.fz = math.floor(pz / 16), pz % 16
end
local function s8v(v) v = v % 256 return v >= 128 and v - 256 or v end
local function pay(game, n)
  local st = game.stats
  if (st.rupees or 0) - n < 0 then return false end
  st.rupees = st.rupees - n
  return true
end
local function frame(game) return game.frame or 0 end

-- ------------------------------------------------------------ the follower
local function initTrail(game, x, y, facing)
  local tr = {}
  for i = 0, 19 do tr[i] = { x, y, facing or 2 } end
  game.kkTrail = { t = tr, v1 = 0, v2 = 0, key = game.omKey and game:omKey() }
end
function M.becomeFollower(game)
  game.progress.follower = M.FOLLOWER
  local lk = game.link
  initTrail(game, lk.x, lk.y, lk.facing)
  game.kikiJoined = (game.kikiJoined or 0) + 1
end

-- a Kiki sprite at the trail's next spot + 2 (0x080FAC20)
local function spawn(game, sub2)
  local tr = game.kkTrail
  local p = tr and tr.t[(tr.v2 + 1) % 20] or { game.link.x, game.link.y, game.link.facing }
  local oa = game:owActorList()
  local a = { type = M.TYPE, x = p[1] + 2, y = p[2] + 2, lower = false, t = 0, index = -1, dir = 1,
              state = "idle", k = 0 }
  require("src.zelda.alttp.OwEnemies").prep(game, a)
  a.kiki, a.sub2, a.untouchable = true, sub2, true
  a.D = math.floor((p[3] or 2) / 2)
  a.D = ({ [0] = 0, 1, 2, 3 })[a.D] or 1
  oa.list[#oa.list + 1] = a
  game.kikiSpawns = (game.kikiSpawns or 0) + 1
  return a
end

-- Follower_HandleTrigger for follower 10 (area 0x5E's outdoor rows)
local function trigger(game)
  local om = game.data.t and game.data.t.oldman
  if not om or game.state ~= "play" or not game.area then return end
  local scr = game.area.parent
  if game.link.world == "dw" then scr = scr % 64 + 0x40 end
  local ix
  for j, r in ipairs(om.outRooms) do if r == scr then ix = j - 1 break end end
  if not ix then return end
  local lx, ly = game.link.x, game.link.y
  for i = om.outOffs[ix + 1] + 1, om.outOffs[ix + 2] do
    local e = om.outInfos[i]
    if e.follower == M.FOLLOWER then
      local dx, dy = math.abs(lx + 12 - (e.x + 8)), math.abs(ly + 12 - (e.y + 8))
      if dx < 24 and dy < 28 then
        local fl = game.kkFlags or 0
        if band(e.bit, fl) ~= 0 then return end
        game.kkFlags = bor(fl, e.bit)
        if e.msg == 0xFFFF then
          if band(e.bit, 3) == 0 then
            spawn(game, 1)
            game.progress.follower = 0
            game.kkTrail = nil
          elseif band(M.event(game, scr), 1) == 0 then
            spawn(game, 2)
          end
        else
          game:showMessage(require("src.zelda.alttp.Text").bmgIndex(e.msg))
        end
        return
      end
    end
  end
end

-- one frame of follower 10 (Follower_Main's trail, its trigger, the hurt test)
function M.followerFrame(game)
  if (game.progress.follower or 0) ~= M.FOLLOWER then game.kkTrail = nil return end
  local lk = game.link
  if game.kkState ~= game.state then game.kkState, game.kkFlags = game.state, 0 end
  local key = game.omKey and game:omKey()
  if not game.kkTrail or game.kkTrail.key ~= key then initTrail(game, lk.x, lk.y, lk.facing) end
  if game.kkHold or game.kkEvent then return end
  local tr = game.kkTrail
  local moved = tr.lx and (tr.lx ~= lk.x or tr.ly ~= lk.y)
  tr.lx, tr.ly = lk.x, lk.y
  if moved then
    tr.v1 = (tr.v1 + 1) % 20
    tr.t[tr.v1] = { lk.x, lk.y - (lk.z or 0), lk.facing }
    if tr.v1 == tr.v2 then tr.v2 = (tr.v2 + 1) % 20 end
    tr.walk = true
  elseif band(frame(game), 3) == 0 and tr.v1 ~= tr.v2 then
    local t = (tr.v1 - 9) % 20
    if t ~= tr.v2 then tr.v2 = (tr.v2 + 1) % 20 else tr.walk = false end
  else
    tr.walk = tr.v1 ~= tr.v2 and tr.walk
  end
  if not game.textBox then trigger(game) end
  if (game.progress.follower or 0) ~= M.FOLLOWER then return end
  -- Link hurt (link_auxiliary_state and countdown_for_blink): he flees
  if game.recoil and (game.blink or 0) > 0 then
    local a = spawn(game, 3)
    a.z, a.vz = 1, 16
    game.progress.follower = 0
    game.kkTrail = nil
    game.kikiFled = (game.kikiFled or 0) + 1
  end
end

-- ------------------------------------------------------------ the sprite
function M.prep(game, a)
  a.kiki, a.untouchable = true, true
  a.sub2 = a.sub2 or 0
  if band(M.event(game, game.area and game.area.parent or M.AREA), M.EV_DOOR) ~= 0 then a.dead, a.gone = true, true end
end

local function onScreen(game, a)
  local sx, sy = a.x - game.cam.x, a.y - game.cam.y
  return sx >= 0 and sx < 256 and sy >= 0 and sy < 256
end

local function lyingInWait(game, a, lk)
  if not onScreen(game, a) then return end
  if game.isBunny and game:isBunny() then return end
  if (game.blink or 0) > 0 or game.holdItem then return end
  if (game.progress.follower or 0) == M.FOLLOWER then return end
  if band(M.event(game, game.area.parent), M.EV_DOOR) ~= 0 then return end
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not cb then return end
  local hx, hy, hw, hh = A().hitbox(cb, a)
  local lx, ly, lw, lh = A().linkBox(lk)
  if A().overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) then M.becomeFollower(game) end
end

local function moveLand(a)
  moveXYZ(a)
  a.vz = (a.vz or 0) - 1
  if (a.z or 0) < 0 then a.z, a.fz, a.vz = 0, 0, 0 end
end

local function offerEntrance(game, a, tb)
  moveLand(a)
  local ai = a.ai
  if ai == 0 then
    game:showMessage(tb.msg.offer100); a.ai = 1
  elseif ai == 1 then
    if (game.lastChoice or 0) == 0 and pay(game, tb.price100) then
      game:showMessage(tb.msg.paid100)
      game.kkHold = true
      a.ai, a.D = 2, 0
      game.kikiPaid100 = (game.kikiPaid100 or 0) + 1
    else
      game:showMessage(tb.msg.refuse100)
      a.sub2 = 3
    end
  elseif ai == 2 or ai == 4 or ai == 6 then
    a.gfx = band(rshift(frame(game), 3), 1)
    local j = (ai - 2) / 2 + 1
    local tx, ty = tb.pathX[j], tb.pathY[j]
    local ddx = (band(tx, 0xFF) - band(a.x, 0xFF) + 2) % 256
    local ddy = (band(ty, 0xFF) - band(a.y, 0xFF) + 2) % 256
    if ddx <= 3 and ddy <= 3 then
      a.ai, a.vx, a.vy, a.aux1 = ai + 1, 0, 0, 0x20
    else
      a.vx, a.vy = A().project(a.x, a.y, tx, ty, 9)
    end
  elseif ai == 3 or ai == 5 then
    if (a.aux1 or 0) ~= 0 then
      a.D = bor(band(rshift(ai, 1), 1), 6)
      a.gfx = band(rshift(frame(game), 3), 1)
    else
      a.ai = ai + 1
      local b = band(rshift(a.ai, 1), 1)
      a.vz = tb.hopZv[b + 1]
      a.D = bor(b, 4)
    end
  elseif ai == 7 then
    a.gfx = band(rshift(frame(game), 3), 1)
    if (a.z or 0) == 0 and (a.delay or 0) == 0 then
      local idx = a.A or 0
      a.A = idx + 1
      local v = tb.walkDir[idx + 1] or 0xFF
      if band(v, 0x80) ~= 0 then
        a.ai, a.vx, a.vy, a.D = 8, 0, 0, 0
        game.kkHold = nil
        game.kkEvent = { t = 0, step = 0 }   -- overworld event 1: the door
      else
        a.D = v
        a.delay = tb.walkDelay[idx + 1] or 0
        a.vx, a.vy = tb.walkXv[v + 1] or 0, tb.walkYv[v + 1] or 0
      end
    end
  elseif ai == 8 then
    a.D, a.gfx = 8, 0
    a.vz = band(rnd(game), 15) + 16
    a.ai = 9
  elseif ai == 9 then
    if (a.vz or 0) < 0 and (a.z or 0) == 0 then a.ai = 10 end
  end
end

local function offerInitial(game, a, tb)
  moveLand(a)
  a.gfx = band(rshift(frame(game), 3), 1)
  local ai = a.ai
  if ai == 0 then
    game:showMessage(tb.msg.offer10); a.ai = 1
  elseif ai == 1 then
    if (game.lastChoice or 0) == 0 and pay(game, tb.price10) then
      game:showMessage(tb.msg.paid10)
      game.kkFlags = bor(game.kkFlags or 0, 3)
      a.dead, a.gone = true, true
      game.kikiPaid10 = (game.kikiPaid10 or 0) + 1
    else
      game:showMessage(tb.msg.refuse10)
      game.kkFlags = band(game.kkFlags or 0, 0xFC)
      game.progress.follower = 0
      game.kkTrail = nil
      game.kkHold = true
      a.ai = 2
    end
  elseif ai == 2 then
    a.ai = 3
    local vx, vy = A().project(a.x, a.y, tb.fleeX, tb.fleeY, 9)
    a.vx, a.vy = vx, vy
    a.D = bxor(vx < 0 and 1 or 0, 3)
    a.delay = 0x20
  elseif ai == 3 then
    if (a.delay or 0) == 0 then a.ai, a.vz, a.delay = 4, 16, 16 end
  elseif ai == 4 then
    if (a.delay or 0) == 0 and (a.z or 0) == 0 then a.dead, a.gone = true, true; game.kkHold = nil end
  end
end

local function flee(game, a, tb)
  if (a.z or 0) == 0 and (a.x - tb.boxX) % 0x10000 <= tb.boxW and (a.y - tb.boxY) % 0x10000 <= tb.boxW then
    a.dead, a.gone = true, true
    return
  end
  if not onScreen(game, a) then a.dead, a.gone = true, true return end
  a.vz = (a.vz or 0) - 2
  moveXYZ(a)
  if (a.z or 0) < 0 then a.z, a.fz = 0, 0; a.vz = bor(band(rnd(game), 15), 0x10) end
  local px, py = A().project(a.x, a.y, tb.fleeX, tb.fleeY, 0x10)
  a.vx, a.vy = s8v(px * 2), s8v(py * 2)
  game.kkFlags = band(game.kkFlags or 0, 0xFC)
  if math.abs(px) >= math.abs(py) then a.D = bxor(a.vx < 0 and 1 or 0, 3)
  else a.D = bxor(a.vy < 0 and 1 or 0, 1) end
  a.gfx = band(rshift(frame(game), 3), 1)
end

function M.update(self, a, lk)
  local game = self.game
  local tb = T(game)
  if not tb or a.dead then return end
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  if (a.aux1 or 0) > 0 then a.aux1 = a.aux1 - 1 end
  if game.textBox then return end
  if a.sub2 == 0 then lyingInWait(game, a, lk)
  elseif a.sub2 == 1 then offerEntrance(game, a, tb)
  elseif a.sub2 == 2 then offerInitial(game, a, tb)
  elseif a.sub2 == 3 then flee(game, a, tb) end
end

-- ------------------------------------------------------------ the door
local function setCell(game, x, y, word)
  local O = require("src.zelda.alttp.Overworld")
  local screen = O.screenAt("dw", x, y)
  if not screen then return end
  local n = game.data:mapNumber("bg2", screen)
  if not n then return end
  game.data.mapPatch = game.data.mapPatch or {}
  local p = game.data.mapPatch[n] or {}
  game.data.mapPatch[n] = p
  p[O.cellIndex((x % 512) / 8, (y % 512) / 8)] = word
  if game.ow and game.ow.attrCache then game.ow.attrCache[screen] = nil end
  if game.view and game.view.screens then game.view.screens[screen] = nil end
end
function M.applyOverlay(game)
  local tb = T(game)
  if not (tb and game.area) or game.link.world ~= "dw" then return false end
  if game.area.parent % 64 ~= M.AREA % 64 then return false end
  if band(M.event(game, M.AREA), M.EV_DOOR) == 0 then return false end
  for _, c in ipairs(tb.door) do setCell(game, game.area.x + c[1] * 8, game.area.y + c[2] * 8, c[3]) end
  game.kikiOverlays = (game.kikiOverlays or 0) + 1
  return true
end

-- overworld event 1: 0x40, then 4 x 0x20 frames
local function eventFrame(game)
  local ev = game.kkEvent
  ev.t = ev.t + 1
  local len = (ev.step == 0) and 0x40 or 0x20
  if ev.t < len then return end
  ev.t = 0
  if ev.step == 0 then
    setEvent(game, M.AREA, M.EV_DOOR)
    M.applyOverlay(game)
    game.kikiDoorOpened = (game.kikiDoorOpened or 0) + 1
  end
  ev.step = ev.step + 1
  if ev.step > 4 then game.kkEvent = nil end
end
M.eventFrame = eventFrame
M.trigger = trigger

-- ------------------------------------------------------------ drawing
local function rgba(c) return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31 end
-- follower 10's 16 x 16 tiles at DMA offset var (0x0812F9A8: the sheet is
-- 0x59 + (v >> 11) for followers 9-11)
local function followerImage(spr, var, palRow)
  local key = "kk46:" .. var .. ":" .. palRow
  local im = spr.cache[key]
  if im ~= nil then return im or nil end
  local v = spr.info.follower[M.FOLLOWER + 1] or 0
  local base = (0x59 + rshift(v, 11)) * 4096 + band(v, 0x7FF) + var * 2
  local img = love.image.newImageData(16, 16)
  local src, pal = spr.data.spr, spr.pal[palRow] or spr.pal[4]
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
local function tile16(spr, var, row, x, y, hf, vf)
  local im = followerImage(spr, var, row)
  if not im then return end
  love.graphics.draw(im, x + (hf and 16 or 0), y + (vf and 16 or 0), 0, hf and -1 or 1, vf and -1 or 1)
end
local function oamFlags(spr) return band(spr.info.flags3[M.TYPE + 1] or 0, 0x0F) end

-- Tagalong_Draw for follower 10 (Smiths.lua's tables: kTagalongDmaAndFlags,
-- kTagalongDraw_SprXY / Offs / Pals)
function M.drawFollower(spr, tb, dir, walk, step, x, y)
  local av = walk and band(step, 4) or 4
  local fr = dir + av
  local d = tb.tagDma
  local dma6, dma7, fl = d[fr * 3 + 1], d[fr * 3 + 2], d[fr * 3 + 3]
  local xy = tb.tagXY[fr + rshift(tb.tagOffs[M.FOLLOWER + 1] or 0, 3) + 1]
  if not (dma6 and xy) then return end
  local pal = tb.tagPals[M.FOLLOWER + 1] or 4
  local bf = band(fl, 0x0F) * 16
  tile16(spr, dma7, pal, x + xy[4], y + xy[3] + 8, band(bf, 0x40) ~= 0, band(bf, 0x80) ~= 0)
  local hfl = band(fl, 0xF0)
  tile16(spr, dma6, pal, x + xy[2], y + xy[1], band(hfl, 0x40) ~= 0, band(hfl, 0x80) ~= 0)
end

-- Kiki_Draw
function M.draw(spr, a, x, y)
  local tb = spr.data.t and spr.data.t.kiki46
  if not tb then return false end
  if a.sub2 == 0 or (a.sub2 == 2 and (a.ai or 0) < 2) then return true end
  local f = oamFlags(spr)
  local D, g = a.D or 0, a.gfx or 0
  if D > 7 then
    spr:drawDmd(a, tb.dmdJump, g * 6, 6, x, y, f)
  else
    local j = (D * 2 + g) * 2
    if D <= 3 then
      for part = 1, 0, -1 do
        local e = tb.dmd[j + part + 1]
        local fl = bxor(e[4], f)
        tile16(spr, tb.dma[j + part + 1] or 0, band(rshift(fl, 1), 7), x + e[1], y + e[2], band(fl, 0x40) ~= 0, band(fl, 0x80) ~= 0)
      end
    else
      spr:drawDmd(a, tb.dmd, j, 2, x, y, f)
    end
  end
  spr:drawShadow(x, y + (a.z or 0), M.TYPE)
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local OE = require("src.zelda.alttp.OwEnemies")
  OE.TYPES[M.TYPE] = true
  local prep0 = OE.prep
  function OE.prep(game, a)
    prep0(game, a)
    if a.type == M.TYPE and T(game) then M.prep(game, a) end
    return a
  end
  local up0 = OE.update
  function OE.update(self, a, lk)
    if a.type == M.TYPE and a.kiki and T(self.game) then return M.update(self, a, lk) end
    return up0(self, a, lk)
  end
  local dr0 = OE.draw
  function OE.draw(spr, a, x, y, frame)
    if a.type == M.TYPE and a.kiki and a.owe then return M.draw(spr, a, x, y) end
    return dr0(spr, a, x, y, frame)
  end
  -- the follower, each frame (outdoors and in rooms)
  local upd0 = G.update
  function G:update(dt)
    local r = upd0(self, dt)
    if T(self) and (self.state == "play" or self.state == "room") and not self.roomScroll and not self.scroll then
      M.followerFrame(self)
    end
    return r
  end
  -- the overlay when the area loads; the door event; Link held
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if T(self) and self.area then
      local key = self.area.parent .. ":" .. self.link.world
      if self.kiki46Key ~= key then
        self.kiki46Key = key
        M.applyOverlay(self)
        -- the follower's trail is made again in a new area (Follower_Initialize)
      end
      if self.kkEvent then
        eventFrame(self)
        self.link.moving = false
        return true
      end
      if self.kkHold then self.link.moving = false return true end
    end
    return owFrame(self, inp)
  end
  -- the follower drawn under Link
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk == self.link and not tint and (self.progress.follower or 0) == M.FOLLOWER and self.kkTrail and T(self) then
      local Sm = require("src.zelda.alttp.Smiths")
      local tbs = Sm.tabs(self)
      local spr = self:shadowSprites()
      if spr and tbs then
        local tr = self.kkTrail
        local p = tr.t[tr.v2]
        local d = ({ [0] = 0, 1, 2, 3 })[math.floor((p[3] or 2) / 2)] or 1
        M.drawFollower(spr, tbs, d, tr.walk, band(rshift(self.frame or 0, 1), 0xFF), p[1] - self.cam.x, p[2] - self.cam.y)
      end
    end
    return dl0(self, lk, tint)
  end
end

return M
