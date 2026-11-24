-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MINIGAMES AND SHOPS LEFT OVER (round 31).
--
-- 1. The shooting gallery (room 0x111, Sprite_65_ArcheryGame). The host
--    (Townsfolk30 draws him) runs ArcheryGame_Host: R touching -> 0x85;
--    "yes" with 20 Rupees -> 0x86 and the game, else 0x87; the game
--    (ArcheryGame_Host_ProctorGame): 5 arrows (archery_game_arrows_left),
--    20 Rupees taken, the arrows-left display from the GBA's X / Y / char /
--    flags tables (0x1767F2 / 0x176804 / 0x176816 / 0x176828, count
--    kArcheryGame_NumSpr 0x1767EC while delay_aux1 runs); out of arrows and
--    nothing flying -> R touching -> 0x88 ("again?") -> the choice again.
--    SpritePrep_ArrowGame puts the seven targets (0x1767C0 X, 0x1767C8 Y,
--    0x1767D0 A: 1 good, 2 bad, x vel 0x1767D8 {-8, 12}) in Link's 256-px
--    column; each moves, and on a wall waits 16 frames then jumps to x_lo
--    {-24, 8}. An arrow on a good target: delay_aux2 0x80, the streak
--    (byte_7E0B88, max 9) is its prize index, at aux2 96 Rupees +
--    kArcheryGame_CashPrize (0x17683A: 4 8 16 32 64 99..), five hits on one
--    target -> 99; a bad target or a wall breaks the streak. Inside the room
--    the bow costs no arrows during a game (link_num_arrows is put back each
--    frame) and shoots nothing outside one (archery_game_out_of_arrows).
-- 2. The super bomb (Sprite_BombShop_SuperBomb): R at the ware -> 100
--    Rupees (0x17C) -> follower 13 and 0x11A. Outdoors R sets it down
--    (super_bomb_indicator 3, first tick 0xBB frames, then every 62); Link
--    near it again after 64 frames picks it up; at 0 with Link away it
--    explodes (Ancilla3A: 9 blasts at kSuperBombExplode_X / Y, the
--    destructibles under the centre at blast step 3 with follower 13 --
--    the only bomb that opens the pyramid's crack in area 0x5B:
--    Overworld_RevealSecret's "screen 0x5B and follower != 13 -> fail").
-- 3. The quarrelling brothers' door: Townsfolk30's 0x32 in the odd room
--    says 0x130 once a door of index 8+ is open there (dung_door_opened &
--    0xFF00); the bombed wall between them now counts.
-- 4. The Light World flute boy (0x2E subtype 0 in area 0x2A,
--    FluteKid_Human): gone with the flute (link_item_flute >= 2),
--    kFluteBoy_Dmd (0x174C6C, D * 8 + graphics * 4), graphics =
--    frame_counter >> 5 & 1, a quaver every 25 frames (0x2E head_dir 1:
--    +4 / -4, z vel 8, 96 frames, x vel +-1 every other frame); Link within
--    48 of (x, y - 16) -> 176 frames held, then he fades (16-frame filter
--    steps, OURS: 31 steps) and is gone.
-- 5. The dug-up flute (AncillaAdd_DugUpFlute / Ancilla36_Flute): it pops
--    out at (0x490, 0xA8A) with z vel 24, x vel -8 facing left else 8,
--    gravity 2, bounces with 0x18 / 0x10 / 0x0A / 0; resting, Link touching
--    it -> receipt 0x14 (the flute, its message). Tools.lua calls
--    Games31.dugUpFlute.
--
-- OURS: the gallery's prize picture and the host's "won" pose sounds are not
-- drawn / played; the super bomb's HUD countdown is not drawn (the count is
-- game.superBomb.count), it is drawn as an unlit bomb (Bomb_Draw); the
-- flute boy's music is not played; the flute shows its menu icon.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = {}

M.GALLERY = 0x111
M.FLUTE_AREA = 0x2A
M.SUPER_BOMB = 13
M.PYRAMID = 0x5B

M.OFF = {
  ggX = 0x1767C0, ggY = 0x1767C8, ggA = 0x1767D0, ggXv = 0x1767D8, hostGfx = 0x1767E8, numSpr = 0x1767EC,
  arX = 0x1767F2, arY = 0x176804, arChar = 0x176816, arFlags = 0x176828, cash = 0x17683A,
  fluteBoy = { 0x174C6C, 16 },
}

local function s8(t) for i, v in ipairs(t) do if v >= 128 then t[i] = v - 256 end end return t end
local function dmd(rom, spec)
  local t = {}
  for i = 0, spec[2] - 1 do
    local p = spec[1] + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = {
    ggX = rom:bytesU8(O.ggX, 8), ggY = rom:bytesU8(O.ggY, 8), ggA = rom:bytesU8(O.ggA, 8),
    ggXv = s8(rom:bytesU8(O.ggXv, 2)), hostGfx = rom:bytesU8(O.hostGfx, 4), numSpr = rom:bytesU8(O.numSpr, 6),
    arX = s8(rom:bytesU8(O.arX, 18)), arY = s8(rom:bytesU8(O.arY, 18)), arChar = rom:bytesU8(O.arChar, 18),
    arFlags = rom:bytesU8(O.arFlags, 18), cash = rom:bytesU8(O.cash, 10),
    fluteBoy = dmd(rom, O.fluteBoy),
  }
  check(t.ggX[2] == 0x40 and t.ggY[5] == 0x5A and t.ggA[8] == 2 and t.ggXv[1] == -8 and t.hostGfx[2] == 4
        and t.numSpr[1] == 5 and t.arX[5] == 48 and t.arY[1] == -8 and t.arFlags[1] == 0x33 and t.cash[5] == 64
        and t.fluteBoy[3][2] == -10, "round 31 minigame tables")
  return t
end

local function T(game) return game.data.t and game.data.t.games31 end
M.tabs = T

local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
local function facingNear(game, a) return require("src.zelda.alttp.Sprites31").facingNear(game, a) end

-- ------------------------------------------------------------ 1. the shooting gallery
local function host(actors)
  for _, a in ipairs(actors.list) do if a.type == 0x65 and not a.target and not a.dead then return a end end
end

function M.galleryPrep(actors, h)
  local game = actors.game
  local tb = T(game)
  h.g31, h.ai, h.hd, h.ha1, h.ha4 = true, 0, 0, 0, 0
  h.y = h.y - 9
  h.arrowsSaved = game.stats.arrows or 0
  game.archeryStreak, game.archeryLeft = 0, 0
  local lk = game.link
  local bx, by = band(lk.x, 0xFF00), band(lk.y, 0xFF00)
  for i = 7, 1, -1 do
    local A = tb.ggA[i + 1]
    actors.list[#actors.list + 1] = {
      type = 0x65, target = A, x = bx + tb.ggX[i + 1], y = by + tb.ggY[i + 1], lower = h.lower, t = 0, index = -1,
      dir = 1, hp = 255, state = "idle", g31 = true, p30 = true, tg = A - 1, vx = tb.ggXv[A], fx = 0,
      td = 0, ta1 = 0, ta2 = 0, ta3 = 0, G = 0, B = 0, sub2 = band(i * 53 + (game.frame or 0), 255),
      noBarrier = true, untouchable = true, noTouch = true }
  end
end

local function walkable(actors, a, x, y)
  local A = require("src.zelda.alttp.Actors")
  if not A._walkable then return true end
  return A._walkable(actors.inside, a, x, y)
end

local function targetFrame(actors, a, h)
  local game = actors.game
  local tb = T(game)
  for _, k in ipairs({ "td", "ta1", "ta2", "ta3" }) do if (a[k] or 0) > 0 then a[k] = a[k] - 1 end end
  if a.target == 1 then
    if (a.G or 0) >= 5 then a.B = 6 end
    if a.ta2 == 96 then
      h.hd = 112
      game.stats.rupees = math.min(999, (game.stats.rupees or 0) + (tb.cash[(a.B or 1)] or 0))
      game.archeryWon = (game.archeryWon or 0) + (tb.cash[(a.B or 1)] or 0)
    end
  end
  a.sub2 = band((a.sub2 or 0) + 1, 255)
  local px = a.x * 16 + (a.fx or 0) + a.vx
  a.x, a.fx = math.floor(px / 16), px % 16
  if a.ta1 == 0 then
    if a.td == 0 then
      if not walkable(actors, a, a.x, a.y) then a.td, a.ta2 = 16, 0 end
    elseif a.td == 1 then
      local X = { [0] = -24, 8 }
      a.x = band(game.link.x, 0xFF00) + band(X[a.tg] or 8, 0xFF)
      a.ta1, a.G = 32, 0
    end
  end
end

-- an arrow at (x, y): Arrow's Ancilla_CheckSpriteCollision special case
function M.arrowAt(game, x, y, lower)
  local acts = game.actors
  if not acts or acts.room ~= M.GALLERY then return false end
  local A = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx.combat
  for _, s in ipairs(acts.list) do
    if s.target and not s.dead and (s.td or 0) == 0 then
      -- kArcheryGameGuy_Flags4 {0x1C, 0x15}: the targets' own hit boxes
      local i = band(s.target == 1 and 0x1C or 0x15, 0x1F) + 1
      local function sw(v) v = v % 65536 return v >= 0x8000 and v - 0x10000 or v end
      local bx = s.x + sw((cb.hitXLo[i] or 0) % 256 + (cb.hitXHi[i] or 0) * 256)
      local by = s.y + sw((cb.hitYLo[i] or 0) % 256 + (cb.hitYHi[i] or 0) * 256)
      local bw, bh = cb.hitXSize[i] or 16, cb.hitYSize[i] or 16
      local yo = s.target == 1 and -3 or 3
      if x >= bx and x < bx + bw and y >= by + yo and y < by + yo + bh then
        if s.target == 1 then
          s.ta2 = 0x80
          local h = host(acts)
          if h then h.ha4 = 128 end
          if (game.archeryStreak or 0) < 9 then game.archeryStreak = (game.archeryStreak or 0) + 1 end
          s.B, s.G = game.archeryStreak, (s.G or 0) + 1
          game.archeryHits = (game.archeryHits or 0) + 1
        else
          s.ta3 = 4
          game.archeryStreak = 0
        end
        return s
      end
    end
  end
  return false
end

local function hostFrame(actors, h)
  local game = actors.game
  local tb = T(game)
  for _, k in ipairs({ "hd", "ha1", "ha4" }) do if (h[k] or 0) > 0 then h[k] = h[k] - 1 end end
  if (game.archeryLeft or 0) == 0 then game.archeryOut = true end
  if h.hd > 0 then h.g31gfx = rshift(band(h.hd, 4), 2)
  else h.g31gfx = tb.hostGfx[(h.ai ~= 0 and band(rshift(game.frame or 0, 5), 3) or 0) + 1] end
  if h.ai == 2 then
    if not h.started then
      h.started = true
      game.archeryLeft, game.archeryOut = 5, false
      h.ha1 = 39
      game.stats.rupees = game.stats.rupees - 20
      game.archeryGames = (game.archeryGames or 0) + 1
    end
  end
  -- link_num_arrows = sprite_subtype (the count Link came in with)
  game.stats.arrows = h.arrowsSaved
end

function M.galleryTalk(game, h)
  local A = require("src.zelda.alttp.RomTables").get("msg.archery")   -- r37
  local function offer(g)
    if (g.lastChoice or 0) == 0 and (g.stats.rupees or 0) >= 20 then
      h.started, game.archeryStreak = false, 0
      h.ai = 2
      g:showMessage(A.start)
    else
      h.ai = 0
      g:showMessage(A.no)
    end
  end
  if h.ai == 0 then
    h.ai = 1
    game:showMessage(A.hello)
    game.onTextDone = offer
    return true
  elseif h.ai == 2 then
    if (game.archeryLeft or 0) ~= 0 or (h.ha4 or 0) ~= 0 then return true end
    for _, a in ipairs(game.anc or {}) do if a.kind == "arrow" then return true end end
    h.ai = 3
    game:showMessage(A.again)
    game.onTextDone = offer
    return true
  end
  return true
end

-- ------------------------------------------------------------ 2. the super bomb
local function trailInit(game, x, y, facing)
  local tr = {}
  for i = 0, 19 do tr[i] = { x, y, facing or 2 } end
  game.sbTrail = { t = tr, v1 = 0, v2 = 0, key = game.omKey and game:omKey() }
end
function M.buySuperBomb(game, a)
  local st = game.stats
  if (st.rupees or 0) < 100 then game:showMessage(require("src.zelda.alttp.RomTables").get("msg.shop").poor) return true end
  st.rupees = st.rupees - 100
  game.progress.follower = M.SUPER_BOMB
  trailInit(game, a.x, a.y, game.link.facing)
  a.dead = true
  game:showMessage(require("src.zelda.alttp.RomTables").get("msg.games31").bombShop)
  game.superBombsBought = (game.superBombsBought or 0) + 1
  return true
end

local function trailFrame(game)
  local lk = game.link
  local key = game.omKey and game:omKey()
  if not game.sbTrail or game.sbTrail.key ~= key then trailInit(game, lk.x, lk.y, lk.facing) end
  local tr = game.sbTrail
  local moved = tr.lx and (tr.lx ~= lk.x or tr.ly ~= lk.y)
  tr.lx, tr.ly = lk.x, lk.y
  if moved then
    tr.v1 = (tr.v1 + 1) % 20
    tr.t[tr.v1] = { lk.x, lk.y - (lk.z or 0), lk.facing }
    if tr.v1 == tr.v2 then tr.v2 = (tr.v2 + 1) % 20 end
    tr.walk = true
  elseif band(game.frame or 0, 3) == 0 and tr.v1 ~= tr.v2 then
    local t = (tr.v1 - 9) % 20
    if t ~= tr.v2 then tr.v2 = (tr.v2 + 1) % 20 else tr.walk = false end
  else
    tr.walk = tr.v1 ~= tr.v2 and tr.walk
  end
end

-- (r35: read from the ROM at import, RomTablesSpec "games31.*")
local RT = require("src.zelda.alttp.RomTables")
local EXPLODE_X = RT.get("games31.explodeX")
local EXPLODE_Y = RT.get("games31.explodeY")
local BOUNCE_ZV = RT.get("games31.bounceZv")

function M.explode(game, sb)
  local IT = game.data.roomIdx and game.data.roomIdx.items
  game.anc = game.anc or {}
  for i = 8, 0, -1 do
    game.anc[#game.anc + 1] = { kind = "bomb", superFx = true, center = i == 0, dir = 0, x = sb.x + EXPLODE_X[i],
                                y = sb.y + EXPLODE_Y[i], itl = 1, t = IT and IT.bombTab0 and IT.bombTab0[2] or 4, z = 0,
                                lower = false }
  end
  game.superBomb = nil
  game.progress.follower = 0
  game.sbTrail = nil
  game.superBlasts = (game.superBlasts or 0) + 1
end

-- Follower_NotFollowing / Hud_SuperBombIndicator, outdoors
local function superBombFrame(game)
  local sb = game.superBomb
  if not sb then return end
  if sb.reacquire > 0 then sb.reacquire = sb.reacquire - 1 end
  -- the HUD counter
  if sb.count >= 0 then
    if sb.tick == 0 then sb.count, sb.tick = sb.count - 1, 62 end
    sb.tick = sb.tick - 1
  end
  local lk = game.link
  local near = math.abs(lk.x - sb.x) < 16 and math.abs(lk.y - sb.y) < 16
  if sb.reacquire == 0 and near and not game.dash then
    game.superBomb = nil
    trailInit(game, sb.x, sb.y, lk.facing)
    game.superPickups = (game.superPickups or 0) + 1
  elseif sb.count == 0 and game.state == "play" then
    M.explode(game, sb)
  end
end

-- ------------------------------------------------------------ 4. the Light World flute boy
function M.spawnFluteBoy(game, oa)
  local t = game.data.t and game.data.t.npc
  if not (T(game) and t and game.area and game.area.parent == M.FLUTE_AREA and game.link.world == "lw") then return end
  if (inv(game)[0x2E] or 0) >= 2 then return end            -- SpritePrep_FluteKid: gone with the flute
  local prg = game:storyProgress()
  local phase = (prg == 2 and 2) or (prg == 3 and 3) or 1
  local list = t.ow[phase] and t.ow[phase][M.FLUTE_AREA + 1]
  local bx, by = (M.FLUTE_AREA % 8) * 512, math.floor((M.FLUTE_AREA % 64) / 8) * 512
  for _, e in ipairs(list or {}) do
    if e[3] == 0x2E then
      oa.list[#oa.list + 1] = { type = 0x2E, x = bx + e[2] * 16 + 7, y = by + e[1] * 16, lower = false, dir = 1, t = 0,
                                state = "idle", hp = 255, index = -1, fluteBoy = true, npc = true, ai = 0, gfx = 0,
                                delay = 0, D = 0, quavers = {} }
    end
  end
end

local function fluteBoyFrame(game, a)
  for i = #a.quavers, 1, -1 do
    local q = a.quavers[i]
    q.t = q.t - 1
    if band(game.frame or 0, 1) == 0 then q.vx = q.vx + ((band(bxor(rshift(game.frame or 0, 5), i), 1) == 1) and -1 or 1) end
    q.fx = q.fx + q.vx; q.fz = q.fz + 8
    if q.t <= 0 then table.remove(a.quavers, i) end
  end
  a.gfx = band(rshift(game.frame or 0, 5), 1)
  if a.delay > 0 then a.delay = a.delay - 1 end
  local lk = game.link
  if a.ai == 0 then
    local x, y = lk.x - a.x, lk.y - (a.y - 16)
    if (inv(game)[0x2E] or 0) >= 2 or (math.abs(x) < 48 and math.abs(y) < 48) then
      a.ai, a.D, a.delay = 1, 1, 176
      game.fluteBoyHold = true
    end
    if a.ai == 0 and a.delay == 0 then
      a.delay = 25
      a.quavers[#a.quavers + 1] = { x = 4, y = -4, fx = 0, fz = 0, vx = 0, t = 96 }
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.fade = 2, 0 end
  elseif a.ai == 2 then
    if band(game.frame or 0, 15) == 0 then
      a.fade = a.fade + 1
      if a.fade >= 31 then a.ai = 3 end
    end
  elseif a.ai == 3 then
    a.dead = true
    game.fluteBoyHold = nil
    game.fluteBoyGone = (game.fluteBoyGone or 0) + 1
  end
end

-- ------------------------------------------------------------ 5. the dug-up flute
function M.dugUpFlute(game)
  game.dugFlute = { x = 0x490, y = 0xA8A, z = 0, zf = 0, zv = 24, fx = 0, vx = game.link.facing == 4 and -8 or 8,
                    step = 0, world = "lw" }
  game.fluteDug = (game.fluteDug or 0) + 1
end

local function dugFluteFrame(game)
  local f = game.dugFlute
  if not f then return end
  if game.link.world ~= f.world or game.state ~= "play" then return end
  if f.step ~= 3 then
    f.zv = f.zv - 2
    local px = f.x * 16 + f.fx + f.vx
    f.x, f.fx = math.floor(px / 16), px % 16
    local z = f.z * 16 + f.zf + f.zv
    f.z, f.zf = math.floor(z / 16), z % 16
    if f.z < 0 or f.z >= 0xF0 then
      f.step = f.step + 1
      f.zv = BOUNCE_ZV[f.step] or 0
      f.z, f.zf = 0, 0
    end
  else
    local lk = game.link
    if not game.textBox and not game.holdItem and lk.x + 16 > f.x and lk.x < f.x + 16 and lk.y + 16 > f.y - 8 and lk.y + 8 < f.y + 16 then
      game.dugFlute = nil
      require("src.zelda.alttp.Sprites31").give(game, 0x14)
      game.fluteTaken = (game.fluteTaken or 0) + 1
    end
  end
end

-- ------------------------------------------------------------ drawing
function M.drawOw(game, spr, cx, cy)
  local tb = T(game)
  local f = game.dugFlute
  if f and game.link.world == f.world and game.view and game.data.menus then
    -- the flute's menu icon (grid slot 15, value 2: the GBA's flute byte 0x2E)
    local R = require("src.zelda.alttp.RomMap")
    local t = game.data.menus
    local ad = R.menu.gridTab[15] + 2 * 8
    local words = { t:u16(ad), t:u16(ad + 2), t:u16(ad + 4), t:u16(ad + 6) }
    local Hud = require("src.zelda.alttp.Hud")
    game.hudPal = game.hudPal or Hud.palette(game.data, 0)
    if not game.receiptPal then
      game.receiptPal = {}
      for k, v in pairs(game.hudPal) do if v ~= 0 then game.receiptPal[k] = v end end
    end
    love.graphics.draw(game.view:hudImage(words, 2, 2, game.receiptPal, t:get("itemLang")), f.x - cx, f.y - cy - f.z)
  end
  local sb = game.superBomb
  if sb and spr then M.drawBomb(game, spr, sb.x - cx, sb.y - cy, sb.count <= 1) end
end

-- the super bomb (OURS: drawn as Bomb_Draw's unlit bomb -- follower 13's
-- own sheet (SNES 0x58) is not traced on the GBA); it flashes at count 1
function M.drawBomb(game, spr, x, y, flash)
  local T2 = game.data.roomIdx and game.data.roomIdx.items
  if not (T2 and T2.bombDrawTab0) then return end
  local frame = T2.bombDrawTab0[1] * 6
  local n = T2.bombDrawTab2[1]
  local r11 = flash and band(game.frame or 0, 0xE) or 4
  for idx = 0, n - 1 do
    local f = frame + idx
    local ch = T2.explCF[f * 2 + 1]
    if ch ~= 0xFF then
      local fl = bor(band(T2.explCF[f * 2 + 2], bit.bnot(0x3E)), r11)
      spr:oam(x + 8 + T2.explXY[f * 2 + 2], y + 12 + T2.explXY[f * 2 + 1], ch, fl, T2.explExt[f + 1])
    end
  end
end

-- ------------------------------------------------------------ install
function M.install(G)
  require("src.zelda.alttp.Barrier29").TYPES[0x65] = true   -- the host: Sprite_NullifyHookshotDrag on contact
  local A = require("src.zelda.alttp.Actors")
  local up0 = A.update
  function A:update()
    local game = self.game
    local tb = game and T(game)
    if tb and self.inside and not game.textBox then
      if self.room == M.GALLERY then
        local h = host(self)
        if h then
          if not h.g31 then M.galleryPrep(self, h) end
          hostFrame(self, h)
          for _, a in ipairs(self.list) do if a.target and not a.dead then targetFrame(self, a, h) end end
        end
      end
      -- the brothers' door: dung_door_opened & 0xFF00 in the odd room
      local inside = self.inside
      if inside.mem and band(self.room or 0, 1) == 1 then
        for _, a in ipairs(self.list) do
          if a.type == 0x32 then
            for k, v in pairs(inside.mem.doors or {}) do
              if v and type(k) == "number" and k >= 8 then inside.mem.quarrelOpen = true end
            end
            break
          end
        end
      end
    end
    if tb and self.room == -1 then
      for _, a in ipairs(self.list) do if a.fluteBoy and not a.dead then fluteBoyFrame(game, a) end end
    end
    return up0(self)
  end
  local N = require("src.zelda.alttp.Npc")
  local spawn0 = N.spawnArea
  function N.spawnArea(game, oa)
    spawn0(game, oa)
    M.spawnFluteBoy(game, oa)
  end
  -- the archery bow rules
  local add0 = G.addArrow
  if add0 then
    function G:addArrow(...)
      local acts = self.actors
      if T(self) and self.interior and acts and acts.room == M.GALLERY and host(acts) then
        if (self.archeryLeft or 0) > 0 then
          self.archeryLeft = self.archeryLeft - 1
        else
          self.archeryBlocked = (self.archeryBlocked or 0) + 1
          return nil
        end
      end
      return add0(self, ...)
    end
  end
  local af0 = G.arrowFrame
  if af0 then
    -- (the targets before the walls, as Ancilla_CheckSpriteCollision runs first)
    local function check(self, a)
      local IT = self.data.roomIdx.items
      local k = (a.dir or 0) + 4
      local hx, hy = a.x + (IT and IT.hbX[k + 1] or 0), a.y + (IT and IT.hbY[k + 1] or 0)
      local s = M.arrowAt(self, hx, hy, a.lower)
      if s then
        a.kind, a.itl, a.aux, a.on = "stuck", 0, 1, s
        a.ox, a.oy = a.x - s.x, a.y - s.y
        return true
      end
    end
    function G:arrowFrame(a)
      local here = T(self) and self.actors and self.actors.room == M.GALLERY and self.interior
      if here and a.kind == "arrow" and (a.itl or 0) < 4 and check(self, a) then return end
      local r = af0(self, a)
      if here and a.kind == "arrow" then check(self, a)
      elseif here and a.kind == "stuck" and not a.on and not a.g31 then
        a.g31 = true
        self.archeryStreak = 0   -- a wall: byte_7E0B88 = 0
      end
      return r
    end
  end
  -- the super bomb's blasts: no damage, the crack under the centre
  local bf0 = G.bombFrame
  if bf0 then
    function G:bombFrame(a)
      if not a.superFx then return bf0(self, a) end
      local IT = self.data.roomIdx and self.data.roomIdx.items
      a.t = a.t - 1
      if a.t <= 0 then
        a.itl = a.itl + 1
        if a.itl == 11 then a.gone = true return end
        a.t = IT and IT.bombTab0 and IT.bombTab0[a.itl + 1] or 4
      end
      if a.center and a.itl == 3 and a.t == 1 and self.bombDestroy then
        self.g31SuperBlast = true
        self:bombDestroy(a)
        self.g31SuperBlast = nil
      end
    end
  end
  -- only the super bomb opens the pyramid's crack (screen 0x5B)
  local bt0 = G.bombTile
  if bt0 then
    function G:bombTile(x, y)
      if not self.g31SuperBlast and T(self) and self.link.world == "dw" then
        local O = require("src.zelda.alttp.Overworld")
        local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
        local screen = O.screenAt(self.link.world, tx, ty)
        local area = screen and self.ow:area(screen)
        if area and area.parent == M.PYRAMID then
          local pos = math.floor((ty - area.y) / 16) * 128 + math.floor((tx - area.x) / 16) * 2
          for _, sc in ipairs(self.data.roomIdx.owSecrets and self.data.roomIdx.owSecrets[area.parent + 1] or {}) do
            if sc.pos == pos and sc.type == 0x86 then self.pyramidRefused = (self.pyramidRefused or 0) + 1 return end
          end
        end
      end
      return bt0(self, x, y)
    end
  end
  -- frames: the super bomb, the dug-up flute
  local upd0 = G.update
  function G:update(dt)
    local r = upd0(self, dt)
    if T(self) and (self.state == "play" or self.state == "room") and not self.roomScroll and not self.scroll and not self.textBox then
      if (self.progress.follower or 0) == M.SUPER_BOMB and not self.superBomb then trailFrame(self) end
      if self.state == "play" then superBombFrame(self); dugFluteFrame(self) end
    end
    return r
  end
  -- R: the gallery host, the super bomb ware; outdoors the bomb set down
  local act0 = G.escapeAct
  function G:escapeAct()
    if T(self) and self.actors and self.interior and not self.textBox then
      for _, a in ipairs(self.actors.list) do
        if not a.dead and facingNear(self, a) then
          if a.type == 0x65 and a.g31 and not a.target then return M.galleryTalk(self, a) end
          if a.type == 0xB5 and a.ware == 2 then return M.buySuperBomb(self, a) end
        end
      end
    end
    return act0(self)
  end
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if (self.fluteBoyHold) and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y" }) do inp[k] = false end
    end
    if inp and inp.a and T(self) and not self.textBox and (self.progress.follower or 0) == M.SUPER_BOMB
       and not self.superBomb and self.sbTrail then
      local p = self.sbTrail.t[self.sbTrail.v2]
      self.superBomb = { x = p[1], y = p[2], count = 3, tick = 0xBB, reacquire = 64 }
      self.superBombDrops = (self.superBombDrops or 0) + 1
      inp.a = false
    end
    return owFrame(self, inp)
  end
  -- drawing: the gallery host's pose and targets, the arrows left, the flute boy
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    local tb = self.data.t and self.data.t.games31
    if tb and a.type == 0x65 and a.target then
      local info = self.info
      local ch = info.single2[(info.single1[0x65 + 1] or 0) + (a.tg or 0) + 1]
      local j = (a.ta2 or 0) ~= 0 and a.ta2 or rshift(a.sub2 or 0, 3)
      local fl = a.target == 1 and bor(13, band(j, 4) * 16) or 13
      if ch then self:oam(x, y + (a.target == 1 and -3 or 3), ch, fl, 2) end
      return true
    end
    if tb and a.type == 0x65 and a.g31 and not a.target then
      local g0 = a.gfx
      a.gfx = a.g31gfx or 3
      local r = da0(self, a, x, y, frame, room)
      a.gfx = g0
      if a.ai == 2 then
        local i = (a.ha1 or 0) > 0 and (tb.numSpr[rshift(a.ha1, 3) + 1] or 0) or (M.game and M.game.archeryLeft or 0)
        for j = i * 2 + 7, 0, -1 do
          self:oam(x - 20 + tb.arX[j + 1] + 1, y - 48 + tb.arY[j + 1] + 1, tb.arChar[j + 1], tb.arFlags[j + 1], 0)
        end
      end
      return r
    end
    if tb and a.fluteBoy then
      if (a.fade or 0) >= 16 and band(frame or 0, 1) == 1 then return true end   -- (OURS: the fade)
      self:drawDmd(a, tb.fluteBoy, (a.D or 0) * 8 + (a.gfx or 0) * 4, 4, x, y, band(self.info.flags3[0x2E + 1] or 0, 0x0F))
      local info = self.info
      for _, q in ipairs(a.quavers or {}) do
        local ch = info.single2[(info.single1[0x2E + 1] or 0) + 1]
        if ch then self:oam(x + q.x + math.floor(q.fx / 16), y + q.y - math.floor(q.fz / 16), ch, band(self.info.flags3[0x2E + 1] or 0, 0x0F), 0) end
      end
      return true
    end
    return da0(self, a, x, y, frame, room)
  end
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    M.game = self
    if lk == self.link and not tint and T(self) then
      local spr
      if (self.progress.follower or 0) == M.SUPER_BOMB and self.sbTrail and not self.superBomb then
        spr = self:shadowSprites()
        local tr = self.sbTrail
        local p = tr.t[tr.v2]
        if spr then M.drawBomb(self, spr, p[1] - self.cam.x, p[2] - self.cam.y, false) end
      end
    end
    return dl0(self, lk, tint)
  end
  -- the bomb set down and the dug-up flute, with the overworld's sprites
  local dd0 = G.drawDrops
  function G:drawDrops(cx, cy, spr)
    local r = dd0(self, cx, cy, spr)
    if self.state == "play" and T(self) and (self.superBomb or self.dugFlute) then M.drawOw(self, spr, cx, cy) end
    return r
  end
end

return M
