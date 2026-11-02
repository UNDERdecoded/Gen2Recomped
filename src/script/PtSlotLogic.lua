-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SLOT MACHINE, THE GAME ITSELF (overlay 101; pokeplatinum
-- src/overlay101/ov101_021D1A28.c, ov101_021D59AC.c, ov101_021D94D8.c).
--
-- A frame-stepped port of the app's state machine and its SysTasks, with no
-- drawing and no LOVE: src/ui/PtSlotMachineApp.lua feeds it the pad and draws
-- what it leaves in the record, and a headless test can run it alone.
--
-- Every behaviour below is READ FROM CODE unless marked INFERRED. Names keep
-- the C struct's offsets in comments (UnkStruct_ov101_021D13C8.unk_xx).
--
-- WHAT THE GAME IS (all READ FROM CODE):
--   * three reels of 21 symbols (Unk_ov101_021D9688): 0 red 7, 1 Galactic 7,
--     2 replay, 3 cherry, 4 Pikachu, 5 the green one; five pay lines
--     (middle, top, bottom, the two diagonals); a cherry on the LEFT reel's
--     square of a line pays on its own.
--   * X bets 3 coins (state 1, ov101_021D1B40), down or X spins (state 2),
--     Y / B / A stop the left / middle / right reel (ov101_021D1CBC); START
--     quits (a bet already made is handed back, ov101_021D1B9C).
--   * the LOTTERY decides the outcome when the reels start (ov101_021D40A8):
--     a hit at all with Unk_ov101_021D9520[setting] % (25/25/30/30/35/35),
--     then the role from Unk_ov101_021D95C8 -- odd flag bits carry the
--     BONUS flag with a small role. The reels then SLIP (up to 4 symbols, 21
--     on an "assisted" spin) to line the flagged role up -- or to keep every
--     unflagged line off (ov101_021D3780 .. ov101_021D3FA0): what lines up is
--     the lottery's choice, the stop timing only where it lands.
--   * a bonus flag puts the machine in BONUS STANDBY (states 25..40): Clefairy
--     comes out, and each spin either lines up the 7s (with 100 - 25/30/35 %,
--     ov101_021D4394) or plays a small role. The 7s pay 100 and start the
--     BONUS ROUND (states 41..58): rounds of 15 one-coin games; each game
--     pays 15 (a replay line in the middle) when the reels are stopped in the
--     order Clefairy points (Unk_ov101_021D87A8), else nothing; after each
--     round the round goes on with the bonus type's chance (50 / 70 / 90 %,
--     Unk_ov101_021D9568), less 10 or 5 each round (Unk_ov101_021D9598).
--   * the session hands back the coins (max 50000) and the longest bonus
--     streak (unk_20), which PtSlotMachine.finish books.

local L = {}
L.__index = L

-- ---------------------------------------------------------------- tables --
-- ov101_021D94D8.c, READ FROM CODE

-- Unk_ov101_021D9688: the reel strips, top to bottom
L.STRIPS = {
  [0] = { [0] = 5, 3, 1, 0, 2, 4, 5, 3, 1, 2, 4, 5, 3, 1, 2, 4, 5, 2, 0, 2, 4 },
  [1] = { [0] = 3, 0, 1, 5, 4, 2, 3, 0, 5, 4, 2, 3, 0, 5, 4, 2, 3, 1, 5, 4, 2 },
  [2] = { [0] = 4, 2, 1, 0, 2, 5, 4, 2, 1, 3, 5, 4, 2, 1, 3, 5, 4, 2, 0, 3, 5 },
}
L.NONE = 6
L.PAY = { [0] = 100, 100, 0, 2, 10, 15 }            -- Unk_ov101_021D9550
L.PAY_BONUS = { [0] = 100, 100, 15, 2, 10, 15 }     -- Unk_ov101_021D94F0
L.HIT = { [0] = 25, 25, 30, 30, 35, 35 }            -- Unk_ov101_021D9520
-- Unk_ov101_021D95C8: { bit3, bit2, bit7, bit6, bit5, bit4, bit1 }
L.ROLES = {
  [0] = { 1, 4, 2, 13, 1, 39, 1 }, { 1, 4, 2, 13, 1, 39, 1 }, { 2, 3, 4, 11, 2, 38, 2 },
  { 3, 2, 4, 11, 2, 38, 2 }, { 4, 1, 6, 9, 3, 37, 3 }, { 4, 1, 6, 9, 3, 37, 3 },
}
L.HINT = { [0] = 80, 80, 80, 80, 80, 70 }           -- Unk_ov101_021D94D8
-- Unk_ov101_021D9934: { weight, bonus type (unk_50), clefairy table (unk_4C) }
local T934 = {
  { { 5, 3, 0 }, { 10, 1, 1 }, { 10, 5, 2 }, { 10, 2, 2 }, { 15, 4, 1 }, { 50, 0, 0 } },
  { { 5, 3, 0 }, { 15, 1, 1 }, { 10, 5, 2 }, { 15, 2, 2 }, { 15, 4, 1 }, { 40, 0, 0 } },
  { { 5, 3, 0 }, { 15, 1, 1 }, { 15, 5, 2 }, { 15, 2, 2 }, { 10, 4, 1 }, { 40, 0, 0 } },
  { { 5, 3, 0 }, { 20, 1, 1 }, { 15, 5, 2 }, { 20, 2, 2 }, { 10, 4, 1 }, { 30, 0, 0 } },
}
L.BONUS_TYPES = { [0] = T934[1], T934[1], T934[2], T934[3], T934[4], T934[4] }
L.CONTINUE = { [0] = 50, 70, 90, 50, 70, 90 }       -- Unk_ov101_021D9568
-- Unk_ov101_021D9784[setting][unk_4C]: { weight, clefairy look } (same for all)
L.CLEFAIRY = { [0] = { { 5, 2 }, { 20, 0 }, { 75, 1 } }, { { 20, 2 }, { 60, 0 }, { 20, 1 } },
               { { 75, 2 }, { 20, 0 }, { 5, 1 } } }
L.STANDBY_MISS = { [0] = 25, 25, 30, 30, 35, 35 }   -- Unk_ov101_021D9538
L.STANDBY_ROLES = { 5, 15, 30, 50 }                 -- Unk_ov101_021D9628 (every setting)
L.GUARANTEE = { [0] = 1, 1, 3, 3, 5, 5 }            -- Unk_ov101_021D9580
L.SPECIAL = { [0] = 3, 3, 5, 5, 7, 7 }              -- Unk_ov101_021D9508
L.DECAY = { [0] = { 25, 20 }, { 20, 15 }, { 15, 15 }, { 15, 15 }, { 10, 15 }, { 5, 10 } } -- 9598
-- Unk_ov101_021D9AE4 (every setting): { from chance, outcome 1 %, outcome 0 % }
L.OUTCOME = { { 75, 10, 10 }, { 65, 10, 30 }, { 55, 10, 40 }, { 45, 20, 50 }, { 35, 30, 50 },
              { 25, 50, 40 }, { 15, 60, 30 }, { 5, 80, 10 }, { 0, 90, 5 } }
-- Unk_ov101_021D87A8: the stop order Clefairy points, and her pose per step
L.ORDERS = { [0] = { { "y", "b", "a" }, { 6, 5, 7 } }, { { "y", "a", "b" }, { 6, 7, 5 } },
             { { "b", "y", "a" }, { 5, 6, 7 } }, { { "b", "a", "y" }, { 5, 7, 6 } },
             { { "a", "y", "b" }, { 7, 6, 5 } }, { { "a", "b", "y" }, { 7, 5, 6 } } }
L.LAMP_ROWS = { [0] = 2, 3, 12, 4, 11 }            -- Unk_ov101_021D9E60
L.BUTTON_RECTS = { [0] = { 7, 17 }, { 15, 17 }, { 22, 17 } } -- Unk_ov101_021D8740
L.MAX = 50000
local REEL_KEYS = { [0] = "y", "b", "a" }

-- Unk_ov101_021D8938: the idle lamp show { lines mask, from, to, step } or
-- { wait frames }
local LB = {}
do
  local function w(n) LB[#LB + 1] = { wait = n } end
  local function up(m) LB[#LB + 1] = { mask = m, from = 0, to = 14, step = 4 } end
  local function dn(m) LB[#LB + 1] = { mask = m, from = 14, to = 0, step = 4 } end
  local function pulse(m, gap, after) up(m); w(gap); dn(m); w(after) end
  w(30)
  pulse(1, 2, 8); pulse(6, 2, 8); pulse(24, 2, 16); pulse(24, 2, 8); pulse(6, 2, 8); pulse(1, 2, 16)
  pulse(2, 2, 8); pulse(16, 2, 8); pulse(4, 2, 8); pulse(8, 2, 8); pulse(1, 2, 16)
  pulse(8, 1, 2); pulse(2, 1, 2); pulse(1, 1, 2); pulse(4, 1, 2); pulse(16, 1, 8)
  pulse(4, 1, 2); pulse(1, 1, 2); pulse(2, 1, 2); pulse(8, 1, 16)
end
L.LAMP_SHOW = LB

local band = bit and bit.band or function(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end
local function has(v, mask) return band(v, mask) ~= 0 end

-- --------------------------------------------------------------- the RNG --
-- LCRNG_Next: seed * 0x41C64E6D + 0x6073, the top 16 bits
local function lcrng(self)
  local s = self.seed
  local lo, hi = s % 65536, math.floor(s / 65536)
  local v = lo * 0x4E6D + ((lo * 0x41C6 + hi * 0x4E6D) % 65536) * 65536 + 0x6073
  self.seed = v % 4294967296
  return math.floor(self.seed / 65536)
end
L.lcrng = lcrng
local function r100(self) return lcrng(self) % 100 end      -- ov101_021D405C

-- ov101_021D406C: take `w` off the roll; true when the roll fell inside it
local function take(w, box)
  local v = box[1]
  box[1] = v - w
  if box[1] < 0 then box[1] = 0 end
  return v < w
end

-- ------------------------------------------------------------ the record --

function L.new(opts)
  opts = opts or {}
  local self = setmetatable({}, L)
  self.seed = (tonumber(opts.seed) or os.time()) % 4294967296
  self.setting = math.max(0, math.min(5, math.floor(tonumber(opts.setting) or 0))) -- unk_88
  self.credit = math.floor(tonumber(opts.coins) or 0)        -- unk_60
  self.sound = opts.sound or function() end                  -- (kind, name)
  self.seqLen = opts.seqLen                                  -- (group, anim) -> frames
  self.state, self.next = 0, 0                               -- unk_00 / unk_04
  self.bonus = 0                                             -- unk_08
  self.games = 0                                             -- unk_0C (RECORD_UNK_014)
  self.left, self.won = 0, 0                                 -- unk_10 / unk_14
  self.cont = 0                                              -- unk_18
  self.round, self.best = 0, 0                               -- unk_1C / unk_20
  self.guaranteed, self.special, self.ending = 0, 0, 0       -- unk_24 / 28 / 2C
  self.assist, self.order = 0, 0                             -- unk_30 / unk_34
  self.sym, self.lines = L.NONE, 0                           -- unk_44 / unk_48
  self.clefTable, self.bonusType = 0, 0                      -- unk_4C / unk_50
  self.pressed = { [0] = false, false, false }               -- unk_54
  self.payout = 0                                            -- unk_64
  self.timer = 0                                             -- unk_6C
  self.bigSlip, self.flags = 0, 0                            -- unk_70 / unk_74
  self.reelState = { [0] = 0, 0, 0 }                         -- unk_7C
  self.speed = 16                                            -- unk_8C
  self.pos = { [0] = 0, 0, 0 }                               -- unk_90 (pixels)
  self.bounce = { [0] = 0, 0, 0 }                            -- unk_9C
  self.top = { [0] = 0, 0, 0 }                               -- unk_A8
  self.reels = {}
  for i = 0, 2 do self.reels[i] = { st = 0, busy = 0, amp = 0, n = 0, id = i, row = 0, slip = 0 } end
  self.stats = { paid = 0, bet = 0, spins = 0, normal = 0, standby = 0, bonusGames = 0, hits = 0,
                 bonusFlags = 0, roles = {}, msg = nil }
  -- what the screen shows (all READ FROM CODE unless marked)
  self.lamp = { [0] = 0, 0, 0, 0, 0 }      -- each line lamp's blend level 0..16
  self.buttons = { [0] = 5, 5, 5 }          -- the stop buttons' palette rows
  self.subPal = { from = "base", to = "bonus", level = 0 }   -- sub BG row 1
  self.message = nil                         -- text bank 544 entry on show
  self.music = { cur = 0, want = 3, step = 0, busy = 0 }      -- unk_424
  self.payTask = { st = 0, done = 0, t = 0, blink = {} }      -- unk_120
  self.anim = { seq = 0, step = 0, done = 0, hide = 0, t = 0, hint = 0, role = 0, look = 0 } -- unk_13C
  self.objs = {}                             -- live sprites, drawn by the app
  self.fades = {}                            -- the sub BG palette tasks
  self.keys, self.held = {}, {}
  -- ov101_021D1A68: each reel starts at a random symbol
  for i = 0, 2 do
    local v = lcrng(self) % 21
    self.top[i] = v
    self.pos[i] = (21 * 32 - v * 32) % (21 * 32)
  end
  return self
end

-- ---------------------------------------------------------- the symbols --

-- ov101_021D55A4
function L:symbolAt(reel, row)
  local v = (self.top[reel] + row) % 21
  if v < 0 then v = v + 21 end
  return L.STRIPS[reel][v]
end
-- ov101_021D55D4: a reel between symbols reads one higher
function L:symbol(reel, row)
  local d = (self.pos[reel] % 32 ~= 0) and -1 or 0
  return self:symbolAt(reel, row + d)
end

-- ov101_021D3FE8
local function advance(self, reel, d)
  self.pos[reel] = (self.pos[reel] + d) % (21 * 32)
  self.top[reel] = 21 - math.floor(self.pos[reel] / 32)
end
-- ov101_021D4024
local function align(self, reel, d)
  local v = self.pos[reel] % 32
  if v ~= 0 then
    if v < d then d = v end
    advance(self, reel, d)
    v = self.pos[reel] % 32
  end
  return v
end

-- ov101_021D5660 .. ov101_021D5740: one line, or NONE
local function lineOf(self, r0, r1, r2)
  local a, b, c = self:symbol(0, r0), self:symbol(1, r1), self:symbol(2, r2)
  if a == 3 or (a == b and a == c) then return a end
  return L.NONE
end
L.LINES = { [0] = { 2, 2, 2 }, { 1, 1, 1 }, { 3, 3, 3 }, { 1, 2, 3 }, { 3, 2, 1 } }
-- ov101_021D5778 (the check order: top, middle, bottom, \, /)
function L:judge()
  local sym, mask = L.NONE, 0
  for _, line in ipairs({ 1, 0, 2, 3, 4 }) do
    local r = L.LINES[line]
    local v = lineOf(self, r[1], r[2], r[3])
    if v ~= L.NONE then sym = v; mask = mask + 2 ^ line end
  end
  return sym, mask
end
-- ov101_021D57EC: the bonus game counts the middle line only
function L:judgeBonus()
  local v = lineOf(self, 2, 2, 2)
  return v, (v ~= L.NONE) and 1 or 0
end

-- ov101_021D5618: the symbol a role flag lines up
local function roleSymbol(f)
  if has(f, 3) then return 2 end
  if has(f, 12) then return 3 end
  if has(f, 48) then return 4 end
  if has(f, 192) then return 5 end
  if has(f, 256) then return 1 end
  if has(f, 512) then return 0 end
  return L.NONE
end
L.roleSymbol = roleSymbol
-- ov101_021D5814: the hint ball's look for a role
local function ballFor(f)
  if has(f, 3) then return 1 end
  if has(f, 12) then return 0 end
  if has(f, 48) then return 2 end
  if has(f, 192) then return 3 end
  return 4
end

-- ------------------------------------------------------------ the lottery

-- ov101_021D40A8
function L:lottery()
  self.flags = 0
  if not (L.HIT[self.setting] > r100(self)) then return 0 end
  local box, t = { r100(self) }, L.ROLES[self.setting]
  self.stats.hits = self.stats.hits + 1
  local bits = { 8, 4, 128, 64, 32, 16, 2 }
  for i = 1, 7 do
    if take(t[i], box) then self.flags = bits[i]; return 1 end
  end
  self.flags = 1
  return 1
end

-- ov101_021D4210: the bonus type and Clefairy's table
function L:bonusDraw()
  local box, t = { r100(self) }, L.BONUS_TYPES[self.setting]
  for i = 1, 6 do
    if take(t[i][1], box) then
      self.bonusType, self.clefTable = t[i][2], t[i][3]
      self.cont = L.CONTINUE[self.bonusType]
      return
    end
  end
  self.bonusType, self.clefTable = t[6][2], t[6][3]          -- GF_ASSERT(FALSE)
  self.cont = L.CONTINUE[self.bonusType]
end
-- ov101_021D42D0
function L:lookDraw()
  local box, t = { r100(self) }, L.CLEFAIRY[self.clefTable]
  for i = 1, 3 do
    if take(t[i][1], box) then self.anim.look = t[i][2]; return end
  end
  self.anim.look = 1
end
-- ov101_021D4394: a spin in bonus standby
function L:standbyLottery()
  local box = { r100(self) }
  self.flags = 0
  if not (r100(self) < L.STANDBY_MISS[self.setting]) then  -- ov101_021D4370 == 0
    if self.bonusType <= 2 then self.flags = 512 else self.flags = 256 end
    return
  end
  local t = L.STANDBY_ROLES
  if take(t[1], box) then self.flags = 4; return end
  if take(t[2], box) then self.flags = 64; return end
  -- the cartridge tests v1[1] twice (READ FROM CODE)
  if take(t[2], box) then self.flags = 16; return end
  self.flags = 1
end
-- ov101_021D44FC: the round's continue chance decays
function L:decay()
  local v, box, t = self.cont, { r100(self) }, L.DECAY[self.setting]
  if self.special == 2 then v = v - 10
  elseif take(t[1], box) then v = v - 10
  elseif take(t[2], box) then v = v - 5 end
  if v < 0 then v = 0 end
  self.cont = v
end
-- ov101_021D4550: Clefairy's show between rounds (0 cry, 1 back into the
-- ball and out, 2 the burst)
function L:outcome()
  local v, box = self.cont, { r100(self) }
  for _, row in ipairs(L.OUTCOME) do
    if v >= row[1] then
      if take(row[2], box) then return 1 end
      if take(row[3], box) then return 0 end
      return 2
    end
  end
  return 0
end

-- -------------------------------------------------------- the reel stops

local function stoppedCount(self)                             -- ov101_021D38E4
  local n = 0
  for i = 0, 2 do if self.reelState[i] ~= 1 then n = n + 1 end end
  return n
end
local function firstToStop(self, id)                          -- ov101_021D38FC
  for i = 0, 2 do
    if i ~= id and self.reelState[i] ~= 1 then return false end
  end
  return true
end
-- ov101_021D3AF0 / ov101_021D3B34: a cherry in reel 0's window after slip k
local function cherryAt(self, k)
  for r = 1, 3 do if self:symbol(0, r - k) == 3 then return true end end
  return false
end
local function cherryOk(self, k, sym)
  return sym == 3 or not cherryAt(self, k)
end
-- ov101_021D394C: the rows the stopped reels leave open for this one
local function openRows(self, id)
  local s0, s1, s2 = self.reelState[0], self.reelState[1], self.reelState[2]
  local v6, v7, v8 = self.reels[0].row, self.reels[1].row, self.reels[2].row
  if id == 0 then
    if s1 ~= 1 and s2 ~= 1 then
      if v7 == v8 then return v7, 0, 0 end
      if v8 == 1 then return 3, 0, 0 end
      return 1, 0, 0
    end
    if s1 ~= 1 then
      if v7 == 2 then return 1, 2, 3 end
      return v7, 0, 0
    end
    if v8 == 2 then return v8, 0, 0 end
    return 1, 3, 0
  elseif id == 1 then
    if s0 ~= 1 and s2 ~= 1 then
      if v6 == v8 then return v6, 0, 0 end
      return 2, 0, 0
    end
    if s0 ~= 1 then
      if v6 == 2 then return 2, 0, 0 end
      if v6 == 1 then return 1, 2, 0 end
      return 2, 3, 0
    end
    if v8 == 2 then return 2, 0, 0 end
    if v8 == 1 then return 1, 2, 0 end
    return 2, 3, 0
  else
    if s0 ~= 1 and s1 ~= 1 then
      if v6 == v7 then return v6, 0, 0 end
      if v6 == 1 then return 3, 0, 0 end
      return 1, 0, 0
    end
    if s0 ~= 1 then
      if v6 == 2 then return 2, 0, 0 end
      return 1, 3, 0
    end
    if v7 == 2 then return 1, 2, 3 end
    return v7, 0, 0
  end
end

local function reach(self) return self.bigSlip == 1 and 21 or 4 end

-- ov101_021D2E94: the left reel, stopped first, lining a role up
local function leftFirst(self, r, sym)
  local id = r.id
  for v0 = 1, 3 do
    if self:symbol(id, v0) == sym then
      local v1 = 0
      while v0 + v1 <= 3 do
        if cherryOk(self, v1, sym) then r.row, r.slip = v0 + v1, v1; return true end
        v1 = v1 + 1
      end
    end
  end
  local v4 = self.top[0]
  for v0 = 1, reach(self) do
    if self:symbol(id, 1 - v0) == sym then
      for v1 = 0, 2 do
        if cherryOk(self, v0 + v1, sym) then
          if v1 == 0 then
            if v4 % 4 == 0 and cherryOk(self, v0 + 2, sym) then r.row, r.slip = 3, v0 + 2; return true end
          elseif v1 == 1 then
            if v4 % 6 < 2 and cherryOk(self, v0 + 2, sym) then r.row, r.slip = 3, v0 + 2; return true end
          end
          r.row, r.slip = 1 + v1, v0 + v1
          return true
        end
      end
    end
  end
  return false
end

-- ov101_021D2FAC: the left reel, stopped after another
local function leftAfter(self, r, sym)
  local id = r.id
  local v2, v3, v4 = openRows(self, id)
  if cherryOk(self, 0, sym) then
    if self:symbol(id, v2) == sym then r.row, r.slip = v2, 0; return true end
    if v3 ~= 0 and self:symbol(id, v3) == sym then r.row, r.slip = v3, 0; return true end
    if v4 ~= 0 and self:symbol(id, v4) == sym then r.row, r.slip = v4, 0; return true end
  end
  local n = reach(self)
  local function try(row, v0)
    if self:symbol(id, row - v0) == sym and cherryOk(self, v0, sym) then r.row, r.slip = row, v0; return true end
  end
  if v3 == 0 then
    for v0 = 1, n do if try(v2, v0) then return true end end
    return false
  end
  if v4 == 0 then
    for v0 = 1, n do
      if v0 % 2 == 1 then
        if try(v2, v0) or try(v3, v0) then return true end
      else
        if try(v3, v0) or try(v2, v0) then return true end
      end
    end
    return false
  end
  for v0 = 1, n do
    local m = v0 % 4
    if m == 0 then
      if try(v2, v0) or try(v3, v0) or try(v4, v0) then return true end
    elseif m == 1 then
      if try(v3, v0) or try(v2, v0) then return true end
    else
      if try(v4, v0) or try(v2, v0) or try(v3, v0) then return true end
    end
  end
  return false
end

-- ov101_021D32EC: the middle / right reel, stopped first
local function otherFirst(self, r, sym)
  local id = r.id
  for v0 = 1, 3 do
    if self:symbol(id, v0) == sym then r.row, r.slip = v0, 0; return true end
  end
  for v0 = 1, reach(self) do
    if self:symbol(id, 1 - v0) == sym then
      local v1 = v0 % 4
      if v1 == 1 then r.row, r.slip = 3, v0 + 2; return true end
      if v1 == 2 or v1 == 3 then r.row, r.slip = 2, v0 + 1; return true end
      r.row, r.slip = 1, v0
      return true
    end
  end
  return false
end

-- ov101_021D3394: the middle / right reel, stopped after another
local function otherAfter(self, r, sym)
  local id = r.id
  local v3, v4, v5 = openRows(self, id)
  if self:symbol(id, v3) == sym then r.row, r.slip = v3, 0; return true end
  if v4 ~= 0 and self:symbol(id, v4) == sym then r.row, r.slip = v4, 0; return true end
  if v5 ~= 0 and self:symbol(id, v5) == sym then r.row, r.slip = v5, 0; return true end
  local n = reach(self)
  local function scan(row)
    for v0 = 1, n do
      if self:symbol(id, row - v0) == sym then r.row, r.slip = row, v0; return true end
    end
  end
  if v4 == 0 then return scan(v3) or false end
  local v2 = self.top[id]
  if v5 == 0 then
    if v2 % 2 == 1 then return scan(v3) or scan(v4) or false end
    return scan(v4) or scan(v3) or false
  end
  v2 = v2 % 3
  if v2 == 0 then return scan(v3) or scan(v4) or scan(v5) or false end
  if v2 == 1 then return scan(v4) or scan(v5) or scan(v3) or false end
  return scan(v5) or scan(v3) or scan(v4) or false
end

-- ov101_021D3738: the bonus game's replay, middle row
local function bonusLine(self, r, sym)
  for v0 = 0, reach(self) do
    if self:symbol(r.id, 2 - v0) == sym then r.row, r.slip = 2, v0; return true end
  end
  return false
end

-- ov101_021D2D88 / ov101_021D2DC0
local function control(self, r)
  if self.flags == 0 then return false end
  local sym = roleSymbol(self.flags)
  if self.bonus ~= 0 then return bonusLine(self, r, sym) end
  if sym == L.NONE then return false end
  if r.id == 0 then
    if firstToStop(self, r.id) then return leftFirst(self, r, sym) end
    return leftAfter(self, r, sym)
  end
  if firstToStop(self, r.id) then return otherFirst(self, r, sym) end
  return otherAfter(self, r, sym)
end

-- the miss checks: would slip k leave a winning line (or a left cherry)?
local function anyLine(self, s0, s1, s2, cherry)
  local A, B, C = self.reels[0].slip, self.reels[1].slip, self.reels[2].slip
  if s0 then A = s0 elseif s1 then B = s1 else C = s2 end
  for line = 0, 4 do
    local rr = L.LINES[line]
    local a, b, c = self:symbol(0, rr[1] - A), self:symbol(1, rr[2] - B), self:symbol(2, rr[3] - C)
    if (cherry and a == 3) or (a == b and a == c) then return true end
  end
  return false
end
local function middleLine(self, s0, s1, s2, cherry)
  local A, B, C = self.reels[0].slip, self.reels[1].slip, self.reels[2].slip
  if s0 then A = s0 elseif s1 then B = s1 else C = s2 end
  local a, b, c = self:symbol(0, 2 - A), self:symbol(1, 2 - B), self:symbol(2, 2 - C)
  return (cherry and a == 3) or (a == b and a == c)
end

-- ov101_021D3780: no role (or the role is out of reach) -- keep it a miss
local function miss(self, r)
  local n = stoppedCount(self)
  if r.id ~= 0 and n < 2 then return end
  if r.id == 0 and n < 2 then
    for v0 = 0, 21 do
      if not cherryAt(self, v0) then r.slip = v0; return end
    end
    return
  end
  for v0 = 1, 21 do
    local hit
    if r.id == 0 then hit = anyLine(self, v0, nil, nil, true)
    elseif r.id == 1 then hit = anyLine(self, nil, v0, nil, false)
    else hit = anyLine(self, nil, nil, v0, false) end
    if not hit then r.slip = v0; return end
  end
end
-- ov101_021D3830: the bonus game's miss (middle line only)
local function missBonus(self, r)
  local n = stoppedCount(self)
  if r.id ~= 0 and n < 2 then return end
  if r.id == 0 and n < 2 then
    for v0 = 0, 20 do
      if self:symbol(0, 2 - v0) ~= 3 then r.slip = v0; return end
    end
  end
  local last = (r.id == 0) and 20 or 21
  for v0 = 0, last do
    local hit
    if r.id == 0 then hit = middleLine(self, v0, nil, nil, true)
    elseif r.id == 1 then hit = middleLine(self, nil, v0, nil, false)
    else hit = middleLine(self, nil, nil, v0, false) end
    if not hit then r.slip = v0; return end
  end
end

-- the reel task (ov101_021D2C10 with Unk_ov101_021D86C4)
local BOUNCE = { [0] = 4, 8, 8, 8, 16 }
function L:reelTask(r)
  while true do
    local st = r.st
    if st == 0 then return
    elseif st == 1 then advance(self, r.id, self.speed); return
    elseif st == 2 then                                        -- ov101_021D2C4C
      r.st, r.row, r.slip = 3, 0, 0
      if self.assist == 1 then
        if not control(self, r) then
          if self.bonus == 0 then miss(self, r) else missBonus(self, r) end
          self.assist = 0
        end
      elseif self.bonus == 0 then miss(self, r)
      else missBonus(self, r) end
    elseif st == 3 then                                        -- ov101_021D2CA8
      local moved = false
      local v0 = self.pos[r.id] % 32
      if v0 ~= 0 then
        moved = true
        local d = self.speed
        if v0 < d then d = v0 end
        v0 = align(self, r.id, d)
      elseif r.slip > 0 then
        moved = true
        r.slip = r.slip - 1
        advance(self, r.id, self.speed)
        v0 = self.pos[r.id] % 32
      end
      if v0 == 0 and r.slip == 0 then
        r.amp = BOUNCE[math.min(r.slip, 4)]
        r.n, r.st = 0, 4
        if not moved then goto continue end
      end
      return
    elseif st == 4 then                                        -- ov101_021D2D50
      self.bounce[r.id] = r.amp
      r.amp = -r.amp
      r.n = r.n + 1
      if r.n % 2 == 0 then
        -- `>>= 2` on a negative fx32 is an arithmetic shift (floor)
        r.amp = math.floor(r.amp * 4096 / 4) / 4096
      end
      if math.abs(r.amp) < 1 / 4096 then
        r.st, r.busy, self.bounce[r.id] = 0, 0, 0
      end
      return
    end
    ::continue::
  end
end
-- NOTE the cartridge's `v5 = param0->unk_18` after the slip is spent is 0,
-- so every stop bounces 4 px (READ FROM CODE: unk_18 is 0 by then).

local function startReel(self, i) self.reels[i].st, self.reels[i].busy = 1, 1 end   -- 2BDC
local function stopReel(self, i) self.reels[i].st = 2 end                             -- 2BF4
local function reelBusy(self, i) return self.reels[i].busy == 1 end                  -- 2C04

-- ----------------------------------------------------- the screen helpers

function L:play(kind, name) self.sound(kind, name) end

-- the lamps (ov101_021D4F58 / 4F78 / 4FB8 / 4FF8 / 5010)
local function lampsOff(self) for i = 0, 4 do self.lamp[i] = 0 end end
local function lampsBet(self) for i = 0, 4 do self.lamp[i] = 10 end end
-- the stop buttons (ov101_021D5938 / 58F4)
local function buttonUp(self, i) self.buttons[i] = 5 end
local function buttonDown(self, i) self.buttons[i] = 6 end

-- the idle lamp show (ov101_021D5200 / 5244, Unk_ov101_021D8700)
local function showStart(self) self.show = { at = 1, first = true, levels = {}, wait = 0 } end
local function showStop(self)
  self.show = nil
  lampsOff(self)
end
local function showTick(self)
  local sh = self.show
  if not sh then return end
  local e = LB[sh.at]
  local doneStep = true
  if e.mask then
    for line = 0, 4 do
      if has(e.mask, 2 ^ line) then
        local lv
        if sh.first then lv = e.from; doneStep = false
        else
          lv = sh.levels[line] or e.from
          if e.from < e.to then
            lv = lv + e.step
            if lv >= e.to then lv = e.to else doneStep = false end
          else
            lv = lv - e.step
            if lv <= e.to then lv = e.to else doneStep = false end
          end
        end
        sh.levels[line] = lv
        self.lamp[line] = math.floor(lv)
      end
    end
  else
    sh.wait = sh.wait + 1
    if sh.wait >= e.wait then sh.wait = 0 else doneStep = false end
  end
  sh.first = false
  if doneStep then
    sh.first = true
    sh.at = sh.at + 1
    if sh.at > #LB then sh.at = 1 end      -- the (1 << 6) entry: back to 0
  end
end

-- the music task (ov101_021D1894 / ov101_021D18F4): 0 field, 1 ATARI,
-- 2 OOATARI, 3 none
function L:musicTo(m)
  local mu = self.music
  if mu.cur == m or mu.want == m then return end
  mu.want, mu.step, mu.busy = m, 1, 1
end
local function musicTask(self)
  local mu = self.music
  if mu.step == 1 then
    self:play("bgm_stop", mu.cur)
    mu.step = 2
  elseif mu.step == 2 then
    self:play("bgm_start", mu.want)
    mu.cur, mu.want, mu.busy, mu.step = mu.want, 3, 0, 0
  end
end

-- the sub BG row 1 fades (ov101_021D53B0 / 53D4 / 53F8)
local function fade(self, kind, which)
  local f = { kind = kind, which = which, level = (kind == "flash") and 8 or 0, phase = 0 }
  self.fades[#self.fades + 1] = f
  if kind == "flash" then self:play("se", "SEQ_SE_DP_025") end
end
local function fadeTasks(self)
  local keep = {}
  for _, f in ipairs(self.fades) do
    local alive = true
    if self.state == 63 then alive = false
    elseif f.kind == "in" or f.kind == "out" then
      f.level = f.level + 0.5
      local v = math.min(16, math.floor(f.level))
      if f.kind == "in" then self.subPal = { from = "base", to = "bonus", level = v }
      else self.subPal = { from = "bonus", to = "base", level = v } end
      if v == 16 then alive = false end
    else
      local to = (f.which == 0) and "flashA" or "flashB"
      if f.phase == 0 then
        f.level = f.level + 1
        local v = math.floor(f.level)
        if v > 16 then v = 16; f.phase = 1 end
        self.subPal = { from = "bonus", to = to, level = v }
      else
        f.level = f.level - 0.25
        local v = math.floor(f.level)
        if v < 0 then v = 0 end
        self.subPal = { from = "bonus", to = to, level = v }
        if v == 0 then alive = false end
      end
    end
    if alive then keep[#keep + 1] = f end
  end
  self.fades = keep
end

-- --------------------------------------------------------- the sprites --
-- Each object is { kind, ... } with x / y in the DS's two-screen space (sub
-- screen y = 192 + local y), scale, anim (sequence) and tick, visible.

local function newObj(self, o)
  o.tick, o.visible, o.scale, o.rot = 0, true, o.scale or 1, 0
  o.ready = false
  self.objs[#self.objs + 1] = o
  return o
end
local function finish(self, o)
  if not o then return end
  for i, v in ipairs(self.objs) do if v == o then table.remove(self.objs, i); return end end
end
local function setAnim(o, a, speed)
  o.anim, o.tick, o.animOn, o.speed = a, 0, true, speed or 1
end

-- the hint ball (ov101_021D5D58, Unk_ov101_021D9218)
local function ball(self, role)
  return newObj(self, { kind = "ball", group = "ball" .. role, mode = 0, step = 0, done = 0, t = 0,
                        x = 0, y = 400, anim = 0, animOn = true, load = 0 })
end
local function ballMode(o, m) o.mode, o.step, o.done, o.t = m, 0, 0, 0 end
local function ballTick(self, o)
  local m, s = o.mode, o.step
  if m == 0 then
    if s == 0 then o.step = 1
    elseif s == 1 then o.step = 2                      -- the VBlank transfer
    elseif s == 2 then o.x, o.y, o.ready, o.done, o.step = 0, 192 + 224, true, 1, 3 end
  elseif m == 1 then
    if s == 0 then
      o.scale, o.rot, o.x, o.y = 2, 0, 128, 384
      setAnim(o, 0); o.animOn = true
      self:play("se", "SEQ_SE_DP_UG_020")
      o.step = 1
    elseif s == 1 then
      o.y = o.y - 4
      o.scale = o.scale - 0x1c7 / 4096
      o.t = o.t + 1
      if o.t >= 9 then o.y, o.scale, o.t, o.step = 352, 1, 0, 2 end
    elseif s == 2 then
      o.t = o.t + 1
      if o.t >= 3 then o.t, o.done, o.step = 0, 1, 3 end
    end
  elseif m == 2 then
    if s == 0 then setAnim(o, 1); self:play("se", "SEQ_SE_DP_SLOT01"); o.step = 1
    elseif s == 1 then
      o.t = o.t + 1
      if o.t >= 4 then o.t, o.done, o.step = 0, 1, 2 end
    end
  elseif m == 3 then
    if s == 0 then
      o.x, o.y, o.scale, o.rot = 128, 352, 1, 0
      o.baseY = 352
      setAnim(o, 3)
      o.step = 1
      return ballTick(self, o)
    elseif s == 1 then
      local d = { [0] = -8, 0, -6, 0, -4, 0, -2, 0 }
      o.y = o.baseY + d[math.floor(o.t / 2)]
      o.t = o.t + 1
      if o.t >= 16 then o.t, o.done, o.step = 0, 1, 2 end
    end
  elseif m == 4 then
    if s == 0 then
      o.x, o.y, o.scale, o.rot = 128, 352, 1, 0
      setAnim(o, 4)
      o.step = 1
      return ballTick(self, o)
    elseif s == 1 then
      o.y = o.y + 4
      o.scale = o.scale + 0x1c7 / 4096
      o.t = o.t + 1
      if o.t >= 10 then o.y, o.scale, o.t, o.done, o.step = 192 + 256, 1, 0, 1, 2 end
    end
  elseif m == 5 then
    if s == 0 then
      o.x, o.y, o.scale, o.rot = 128, 352, 1, 0
      o.t, o.k, o.done = 0, 0, 1
      setAnim(o, 2)
      o.step = 1
      return ballTick(self, o)
    elseif s == 1 then
      local dr = { [0] = -16, 0, 16, 0, 16, 0, -16, 0 }
      local dx = { [0] = -2, 0, 2, 0, 2, 0, -2, 0 }
      local len = { [0] = 4, 1, 4, 8, 4, 1, 4, 8 }
      o.rot = o.rot + dr[o.k]
      o.x = o.x + dx[o.k]
      o.t = o.t + 1
      if o.t >= len[o.k] then o.k = (o.k + 1) % 8; o.t = 0 end
    end
  elseif m == 6 then
    if s == 0 then
      o.x, o.y, o.scale, o.rot, o.done = 128, 352, 1, 0, 1
      setAnim(o, 2)
      o.step = 1
    end
  end
end

-- the sparkle (ov101_021D6484)
local function sparkle(self)
  return newObj(self, { kind = "sparkle", group = "sparkle", x = 128, y = 192 + 144, st = 0, t = 0,
                        anim = 0, animOn = true, load = 0 })
end
local function sparkleTick(self, o)
  if o.st == 0 then
    o.load = o.load + 1
    if o.load >= 2 then o.ready = true; o.st = 1 end
    return
  end
  if o.st == 1 then
    o.t = o.t + 1
    if o.t >= 15 then o.st, o.gone = 2, true end
  elseif o.st == 2 then
    o.ready = false
    o.st = 3
  end
end

-- Clefairy (ov101_021D6764, Unk_ov101_021D9164)
local function clefairy(self, look)
  return newObj(self, { kind = "clefairy", group = "clefairy" .. look, mode = 0, step = 0, done = 0,
                        t = 0, load = 0, x = 128, y = 192 + 256, anim = 0, animOn = true })
end
local function clefMode(o, m) o.mode, o.step, o.done, o.t = m, 0, 0, 0 end
local function clefTick(self, o)
  local m, s = o.mode, o.step
  local home = 192 + 128
  if m == 0 then
    if s == 0 then
      o.load = o.load + 1
      if o.load >= 2 then o.x, o.y, o.ready, o.done, o.step = 128, 192 + 256, true, 1, 1 end
    end
  elseif m == 1 then
    if s == 0 then
      o.scale, o.x, o.y = 0x400 / 4096, 128, home
      setAnim(o, 1); o.animOn = false
      o.step = 1
    elseif s == 1 then
      o.scale = o.scale + 0xc0 / 4096
      o.t = o.t + 1
      if o.t >= 16 then
        o.y, o.scale, o.t, o.step = home, 1, 0, 2
        self:play("cry", 35)
      end
    elseif s == 2 then
      o.tick = o.tick + 1
      o.t = o.t + 1
      if o.t >= 9 then o.t, o.step, o.done = 0, 3, 1 end
    end
  elseif m == 2 then
    if s == 0 then
      o.scale, o.x, o.y = 1, 128, home
      setAnim(o, 1); o.animOn = false
      self:play("se", "SEQ_SE_DP_SLOT02")
      o.step = 1
    elseif s == 1 then
      o.scale = o.scale - 0x180 / 4096
      o.t = o.t + 1
      if o.t >= 8 then o.y, o.scale, o.t, o.step, o.done = 192 + 272, 1, 0, 2, 1 end
    end
  elseif s == 0 then
    o.scale, o.x, o.y = 1, 128, home
    if m == 3 then setAnim(o, 0); o.animOn = false
    elseif m == 4 then
      if o.anim ~= 2 then setAnim(o, 2, 0.5) else o.animOn, o.speed = true, 0.5 end
    elseif m == 5 then setAnim(o, 5)
    elseif m == 6 then setAnim(o, 4)
    elseif m == 7 then setAnim(o, 3)
    elseif m == 8 then setAnim(o, 5); o.animOn = false; o.manual = true; o.wait = 0 end
    o.manual = (m == 8)
    o.done, o.step = 1, 1
  elseif m == 8 and s == 1 then
    -- ov101_021D6CE0: step the pose; 8 frames' rest between plays
    o.tick = o.tick + 1
    o.seqLen = o.seqLen or (self.seqLen and self.seqLen(o.group, o.anim))
    if o.seqLen and o.tick >= o.seqLen then
      o.wait = (o.wait or 0) + 1
      o.tick = o.seqLen
      if o.wait >= 8 then o.wait, o.tick = 0, 0 end
    end
  end
end

-- the burst (ov101_021D6DF0)
local function burst(self)
  return newObj(self, { kind = "burst", group = "burst", st = 0, t = 0, n = 0, px = 0, py = 0, load = 0,
                        done = 0, anim = 0, animOn = true, x = -999, y = -999, x2 = -999, y2 = -999 })
end
local function burstTick(self, o)
  local function place()
    o.x, o.y = -32 + o.px, 192 + 228 - o.py
    o.x2, o.y2 = 288 - o.px, 192 + 228 - o.py
  end
  local function nudge(dx, dy, which)
    o.px, o.py = o.px + dx, o.py + dy
    if which == 0 then o.x, o.y = -32 + o.px, 192 + 228 - o.py
    else o.x2, o.y2 = 288 - o.px, 192 + 228 - o.py end
  end
  local st = o.st
  if st == 0 then
    o.load = o.load + 1
    if o.load < 2 then return end
    o.ready = true
    o.st = 1
    st = 1
  end
  if st == 1 then
    o.px, o.py = o.px + 8, o.py + 8
    local n = 0
    if o.px >= 64 then o.px = 64; n = n + 1 end
    if o.py >= 56 then o.py = 64; n = n + 1 end
    place()
    if n == 2 then o.st = 2 end
  elseif st == 2 or st == 7 then
    o.t = o.t + 1
    if o.t < 8 then return end
    o.t, o.st = 0, st + 1
    return burstTick(self, o)
  elseif st >= 3 and st <= 6 then
    local which = (st <= 4) and 0 or 1
    local s = (st % 2 == 1) and -1 or 1
    nudge(2 * s * (which == 0 and 1 or 1), 4 * s, which)
    o.t = o.t + 1
    if o.t >= 4 then
      o.t = 0
      if st == 6 then
        o.n = o.n + 1
        if o.n < 2 then o.st = 3 else o.n, o.st = 0, 7 end
      else o.st = st + 1 end
    end
  elseif st == 8 or st == 9 then
    local s = (st == 8) and -1 or 1
    nudge(2 * s, 4 * s, 0)
    o.x2, o.y2 = 288 - o.px, 192 + 228 - o.py
    o.t = o.t + 1
    if o.t >= 4 then
      o.t = 0
      if st == 9 then
        o.n = o.n + 1
        if o.n < 2 then o.st = 8 else o.n, o.st = 0, 10 end
      else o.st = 9 end
    end
  elseif st == 10 then
    nudge(-8, -8, 0)
    o.x2, o.y2 = 288 - o.px, 192 + 228 - o.py
    o.st, o.done = 11, 1
  end
end

-- the bonus counters (ov101_021D47B4): label, "GET" label, games left,
-- coins won -- hidden while anim.hide is 1
local function counters(self)
  local c = {}
  c[1] = newObj(self, { kind = "counter", group = "bonusLabel", x = 24, y = 192 + 8, anim = 0 })
  c[2] = newObj(self, { kind = "counter", group = "gamesLabel", x = 200, y = 192 + 184, anim = 0 })
  c[3] = newObj(self, { kind = "gamesLeft" })
  c[4] = newObj(self, { kind = "wonDigits" })
  for _, o in ipairs(c) do o.ready = true end
  return c
end
-- the round number (ov101_021D79BC): 60 frames
local function roundDigits(self, n)
  return newObj(self, { kind = "round", value = math.min(999, n), life = 60, ready = true })
end
-- the end-of-bonus totals (ov101_021D72D4 / 7460 / 77E4): 45 frames
local function totals(self)
  newObj(self, { kind = "label2x", group = "bonusLabel", x = 128 - 44, y = 192 + 112, life = 45, scale = 2 }).ready = true
  newObj(self, { kind = "label2x", group = "gamesLabel", x = 128 - 60, y = 192 + 80, life = 45, scale = 2 }).ready = true
  newObj(self, { kind = "total", value = math.min(999, self.round), y = 192 + 112, life = 45 }).ready = true
  newObj(self, { kind = "total", value = math.min(99999, self.won), y = 192 + 80, life = 45 }).ready = true
end
-- the lined-up 7s falling to the bottom screen (ov101_021D7B08)
local DROP = { [0] = { 2, 2, 2 }, { 1, 1, 1 }, { 3, 3, 3 }, { 1, 2, 3 }, { 3, 2, 1 } }
local function drop(self)
  local line = 0
  while line < 5 and not has(self.lines, 2 ^ line) do line = line + 1 end
  if line >= 5 then line = 0 end
  local o = newObj(self, { kind = "drop", group = (self.sym == 0) and "line7" or "lineOther", st = 0, t = 0,
                           n = 0, load = 0, ys = {} })
  for i = 0, 2 do o.ys[i] = 16 + 32 * DROP[line][i + 1] end
  return o
end
local function dropTick(self, o)
  if o.st == 0 then
    o.load = o.load + 1
    if o.load >= 2 then o.ready, o.st = true, 1 end
  elseif o.st == 1 then
    local moving = false
    for i = 0, 2 do
      o.ys[i] = o.ys[i] + 4
      if o.ys[i] >= 192 + 48 then o.ys[i] = 192 + 48 else moving = true end
    end
    if not moving then o.st = 2 end
  elseif o.st == 2 or o.st == 4 then
    o.t = o.t + 1
    if o.t >= 30 then o.t, o.st = 0, o.st + 1 end
  elseif o.st == 3 then
    o.t = o.t + 1
    o.visible = o.t >= 12
    if o.t >= 30 then
      o.t, o.n = 0, o.n + 1
      if o.n >= 3 then o.n, o.st = 0, 4 end
    end
  elseif o.st == 5 then
    o.ready, o.st = false, 6
  end
end

local function objTick(self, o)
  if o.kind == "ball" then ballTick(self, o)
  elseif o.kind == "sparkle" then sparkleTick(self, o)
  elseif o.kind == "clefairy" then clefTick(self, o)
  elseif o.kind == "burst" then burstTick(self, o)
  elseif o.kind == "drop" then dropTick(self, o)
  elseif o.life then
    o.life = o.life - 1
    if o.life <= 0 then finish(self, o) end
  end
  -- the OAM animation runs on every sprite with its animate flag set
  -- (Sprite_SetAnimateFlag); the app reads o.anim / o.tick
  if o.ready and o.animOn and not o.manual then o.tick = o.tick + (o.speed or 1) end
end

-- ------------------------------------------------- the payout task (120)

-- ov101_021D5028 / Unk_ov101_021D86B0: a pay line's lamp blinking
local function blink(self, line, pay)
  return { line = line, pay = pay, st = 0, level = 0, n = 0, done = 0 }
end
local function blinkTick(self, b)
  local st = b.st
  if st == 0 or st == 2 then
    b.level = math.min(16, b.level + ((st == 0) and 4 or 8))
    if b.level == 16 then b.st = st + 1 end
  elseif st == 1 or st == 3 then
    b.level = math.max(0, b.level - ((st == 1) and 4 or 8))
    if b.level == 0 then
      if st == 1 then
        b.n = b.n + 1
        if b.n >= 4 then
          b.done = 1
          b.st = (b.pay ~= 0) and 2 or 4
        else b.st = 0 end
      else b.st = 2 end
    end
  end
  if st ~= 4 then self.lamp[b.line] = b.level end
end

local function payStart(self)                                 -- ov101_021D45F8
  local p = self.payTask
  p.done, p.t, p.st = 0, 0, 1
end
local function payTask(self)                                  -- ov101_021D4614
  local p = self.payTask
  if p.st == 0 then return end
  if p.st == 1 then
    p.blink = {}
    local m = self.lines
    for line = 0, 4 do
      if has(m, 2 ^ line) and #p.blink < 2 then p.blink[#p.blink + 1] = blink(self, line, self.payout) end
    end
    p.st = 2
    return
  end
  if p.st == 2 then
    for _, b in ipairs(p.blink) do if b.done ~= 1 then return end end
    p.st = 3
  end
  if self.keys.x or self.payout == 0 then
    self:play("se", "SEQ_SE_DP_DENSI16")
    self.credit = math.min(L.MAX, self.credit + self.payout)
    if self.bonus == 1 then self.won = self.won + self.payout end
    self.payout = 0
    for _, b in ipairs(p.blink) do self.lamp[b.line] = 0 end   -- ov101_021D508C on Finish
    p.blink = {}
    p.done, p.st = 1, 0
    return
  end
  local mask = 3
  if self.held.a or self.held.b or self.held.x or self.held.y then mask = 1 end
  p.t = p.t + 1
  if p.t % (mask + 1) == 0 then
    self.payout = self.payout - 1
    self.credit = math.min(L.MAX, self.credit + 1)
    self:play("se", "SEQ_SE_DP_DENSI16")
    if self.bonus == 1 then self.won = self.won + 1 end
  end
end
local function payDone(self) return self.payTask.done == 1 end

-- --------------------------------------------- the animation task (13C)

local function animSet(self, seq)                             -- ov101_021D4798
  local a = self.anim
  a.seq, a.step, a.done, a.t = seq, 0, 0, 0
end
L.animSet = animSet
local function animDone(self) return self.anim.done == 1 end -- ov101_021D47AC

local SEQS = {}
SEQS[0] = { function() return 0 end }
SEQS[1] = {
  function(self, a) a.ball = ball(self, a.role); a.step = a.step + 1; return 0 end,
  function(self, a) if a.ball.done == 0 then return 0 end ballMode(a.ball, 1); a.step = a.step + 1; return 0 end,
  function(self, a) if a.ball.done == 0 then return 0 end ballMode(a.ball, 5); a.done = 1; a.step = a.step + 1; return 0 end,
  function() return 0 end,
}
SEQS[2] = {
  function(self, a) ballMode(a.ball, 4); a.step = a.step + 1; return 0 end,
  function(self, a)
    if a.ball.done == 1 then finish(self, a.ball); a.ball = nil; a.done = 1; a.step = a.step + 1 end
    return 0
  end,
  function() return 0 end,
}
SEQS[3] = {
  function(self, a) ballMode(a.ball, 2); a.step = a.step + 1; return 0 end,
  function(self, a)
    if a.ball.done == 1 then
      a.sparkle = sparkle(self); a.clef = clefairy(self, a.look); a.step = a.step + 1
    end
    return 0
  end,
  function(self, a)
    if a.clef.done == 1 then clefMode(a.clef, 1); a.ball.visible = false; a.step = a.step + 1 end
    return 0
  end,
  function(self, a)
    if a.clef.done == 1 then finish(self, a.sparkle); a.sparkle = nil; a.done = 1; a.step = a.step + 1 end
    return 0
  end,
  function() return 0 end,
}
SEQS[4] = {
  function(self, a) a.sparkle = sparkle(self); clefMode(a.clef, 2); a.step = a.step + 1; return 0 end,
  function(self, a)
    if a.clef.done == 1 then
      finish(self, a.clef); finish(self, a.sparkle); a.clef, a.sparkle = nil, nil
      a.ball.visible = true; ballMode(a.ball, 3); a.step = a.step + 1
    end
    return 0
  end,
  function(self, a) if a.ball.done == 1 then ballMode(a.ball, 4); a.step = a.step + 1 end return 0 end,
  function(self, a)
    if a.ball.done == 1 then finish(self, a.ball); a.ball = nil; a.done = 1; a.step = a.step + 1 end
    return 0
  end,
  function() return 0 end,
}
SEQS[5] = {
  function(self, a) clefMode(a.clef, 3); a.burst = burst(self); a.t = 0; a.step = a.step + 1; return 0 end,
  function(self, a)
    a.t = a.t + 1
    if a.t >= 48 then a.t = 0; a.step = a.step + 1; self:play("cry", 35); clefMode(a.clef, 4) end
    return 0
  end,
  function(self, a)
    if a.burst.done == 1 then
      clefMode(a.clef, 3); finish(self, a.burst); a.burst = nil
      a.step, a.t, a.done = a.step + 1, 0, 1
    end
    return 0
  end,
  function() return 0 end,
}
SEQS[6] = {
  function(self, a)
    a.step, a.hint = a.step + 1, 0
    clefMode(a.clef, L.ORDERS[self.order][2][1])
    return 0
  end,
  function(self, a)
    local n = stoppedCount(self)
    if a.hint < 2 and a.hint ~= n then
      a.hint = n
      clefMode(a.clef, L.ORDERS[self.order][2][a.hint + 1])
    end
    return 0
  end,
  function() return 0 end,
}
SEQS[7] = { function(self, a) clefMode(a.clef, 3); a.step = a.step + 1; return 0 end, function() return 0 end }
SEQS[8] = {
  function(self, a)
    a.hide = 1
    for _, o in ipairs(a.counters or {}) do finish(self, o) end
    a.counters = nil
    a.sparkle = sparkle(self); clefMode(a.clef, 2); a.step = a.step + 1
    return 0
  end,
  function(self, a)
    if a.clef.done == 1 then
      finish(self, a.clef); finish(self, a.sparkle); a.clef, a.sparkle = nil, nil
      a.ball.visible = true; ballMode(a.ball, 3); a.step = a.step + 1
    end
    return 0
  end,
  function(self, a) if a.ball.done == 1 then totals(self); a.step = a.step + 1 end return 0 end,
  function(self, a)
    a.t = a.t + 1
    if a.t >= 45 then a.t = 0; ballMode(a.ball, 4); a.step = a.step + 1 end
    return 0
  end,
  function(self, a)
    if a.ball.done == 1 then finish(self, a.ball); a.ball = nil; a.done = 1; a.step = a.step + 1 end
    return 0
  end,
  function() return 0 end,
}
SEQS[9] = { function(self, a) clefMode(a.clef, 4); a.done = 1; a.step = a.step + 1; return 0 end, function() return 0 end }
SEQS[10] = { function(self, a) clefMode(a.clef, 8); a.done = 1; a.step = a.step + 1; return 0 end, function() return 0 end }
SEQS[11] = { function(self, a) ballMode(a.ball, 6); a.step = a.step + 1; a.done = 1; return 0 end, function() return 0 end }
SEQS[12] = {
  function(self, a) a.sparkle = sparkle(self); clefMode(a.clef, 2); a.hide = 1; a.step = a.step + 1; return 0 end,
  function(self, a)
    if a.clef.done == 1 then
      finish(self, a.sparkle); finish(self, a.clef); a.sparkle, a.clef = nil, nil
      a.ball.visible = true; ballMode(a.ball, 3); a.t = 0; a.step = a.step + 1
    end
    return 0
  end,
  function(self, a)
    a.t = a.t + 1
    if a.t >= 30 then a.t = 0; a.step = a.step + 1; ballMode(a.ball, 2) end
    return 0
  end,
  function(self, a)
    if a.ball.done == 1 then
      a.sparkle = sparkle(self); a.clef = clefairy(self, a.look); a.hide = 0; a.step = a.step + 1
    end
    return 0
  end,
  function(self, a)
    if a.clef.done == 1 then clefMode(a.clef, 1); a.ball.visible = false; a.step = a.step + 1 end
    return 0
  end,
  function(self, a)
    if a.clef.done == 1 then finish(self, a.sparkle); a.sparkle = nil; a.done = 1; a.step = a.step + 1 end
    return 0
  end,
  function() return 0 end,
}

local function animTask(self)                                 -- ov101_021D4824
  local a = self.anim
  repeat
    local fn = SEQS[a.seq][a.step + 1]
    if not fn then return end
  until fn(self, a) ~= 1
end

-- ---------------------------------------------------- the state machine

local function message(self, n)                               -- ov101_021D148C
  self.message = n
  self.stats.msg = n
end

local function newGame(self, standby)                         -- 1AD0 / 212C
  self.payout, self.unk68 = 0, 0
  self.flags = 0
  for i = 0, 2 do buttonUp(self, i) end
  lampsOff(self)
  showStart(self)
end
local function coinsCheck(self, low, back, min)
  if self.credit == 0 then self.state, self.next = 60, 63
  elseif self.credit < min then self.state, self.next = low, 63
  elseif self.credit >= L.MAX then self.state, self.next = 61, back end
end

local function spin(self)                                     -- the common tail of 1BD0 / 2228 / 2738
  for i = 0, 2 do buttonUp(self, i) end
  for i = 0, 2 do startReel(self, i) end
  for i = 0, 2 do self.pressed[i] = false end
  for i = 0, 2 do self.reelState[i] = 1 end
  self.timer = 0
  self:play("se", "SEQ_SE_DP_OPEN2")
end
-- ov101_021D5880 / 58C0: are the stops in the wanted order so far?
local function inOrder(self, order)
  for i = 0, 2 do
    if self.pressed[i] and self.pressed[i] ~= order[i + 1] then return false end
  end
  return true
end
local function stops(self, se, order, bonusRule)
  local k = self.keys
  for i = 0, 2 do
    local key = REEL_KEYS[i]
    if self.reelState[i] == 1 and k[key] then
      self.reelState[i] = 2
      for j = 0, 2 do if not self.pressed[j] then self.pressed[j] = key; break end end
      if not inOrder(self, order) then
        self.bigSlip = 0
        if bonusRule then self.assist = 0 end
      end
      buttonDown(self, i)
      stopReel(self, i)
      self:play("se", se)
      break
    end
  end
end

local ST = {}
ST[0] = function(self)                                        -- 1AD0
  newGame(self)
  self.speed, self.flags, self.bonus = 16, 0, 0
  self.state = 1
  coinsCheck(self, 59, 1, 3)
  return 1
end
ST[1] = function(self)                                        -- 1B40
  if self.keys.start then showStop(self); self.state = 63; return 0 end
  if self.keys.x then
    self.credit = self.credit - 3
    self.stats.bet = self.stats.bet + 3
    self.state = 2
    self:play("se", "SEQ_SE_DP_ZUKAN02")
    showStop(self); lampsBet(self)
  end
  return 0
end
ST[2] = function(self)                                        -- 1B9C
  if self.keys.start then self.credit = self.credit + 3; self.stats.bet = self.stats.bet - 3; self.state = 63; return 0 end
  if self.keys.down or self.keys.x then self.state = 3; return 1 end
  return 0
end
ST[3] = function(self)                                        -- 1BD0
  self:lottery()
  self.stats.spins = self.stats.spins + 1
  self.stats.normal = self.stats.normal + 1
  self.bigSlip = has(self.flags, 1 + 2 + 16 + 32) and 1 or 0
  self.assist = 0
  if self.flags ~= 0 then
    self.stats.roles[self.flags] = (self.stats.roles[self.flags] or 0) + 1
    if not (r100(self) < L.HINT[self.setting]) then self.anim.role = 4
    else self.anim.role = ballFor(self.flags) end
    self.assist = 1
    animSet(self, 1)
  end
  for i = 0, 2 do buttonUp(self, i) end
  lampsBet(self)
  spin(self)
  self.state = 4
  return 1
end
ST[4] = function(self)                                        -- 1C9C
  self.timer = self.timer + 1
  if self.timer >= 8 then self.timer, self.state = 0, 5; return 1 end
  return 0
end
ST[5] = function(self)                                        -- 1CBC
  stops(self, "SEQ_SE_DP_UG_022", { "y", "b", "a" }, false)
  if self.reelState[0] == 2 and self.reelState[1] == 2 and self.reelState[2] == 2 then self.state = 6 end
  return 0
end
ST[6] = function(self)                                        -- 1DB4
  for i = 0, 2 do if reelBusy(self, i) then return 0 end end
  lampsOff(self)
  self.state = 7
  return 1
end
ST[7] = function(self)                                        -- 1DEC
  local v, m = self:judge()
  self.sym, self.lines = v, m
  local bonusFlag = has(self.flags, 2 + 8 + 32 + 128)
  if v == L.NONE then
    if bonusFlag then self.state = 16
    elseif self.flags ~= 0 then self.state = 10
    else self.state = 8 end
    return 1
  end
  if bonusFlag then self.state = has(self.flags, 2) and 21 or 19; return 1 end
  if v == 2 then self.state = 14; return 1 end
  self.state = 12
  return 1
end
ST[8] = function(self) lampsOff(self); self.timer, self.state = 0, 9; return 1 end
ST[9] = function(self)
  self.timer = self.timer + 1
  if self.timer >= 8 then self.timer, self.state = 0, 0 end
  return 0
end
ST[10] = function(self) lampsOff(self); animSet(self, 2); self.state = 11; return 0 end
ST[11] = function(self)
  if animDone(self) then animSet(self, 0); self.state = 0; return 1 end
  return 0
end
ST[12] = function(self)                                       -- 1EBC: a paid role
  self.payout = self:pay()
  self.stats.paid = self.stats.paid + self.payout
  self.timer, self.state = 0, 13
  payStart(self); animSet(self, 11)
  return 0
end
ST[13] = function(self)
  self.timer = self.timer + 1
  if self.timer == 30 then animSet(self, 2)
  elseif self.timer > 30 and payDone(self) and animDone(self) then
    animSet(self, 0); self.timer, self.state = 0, 0; return 1
  end
  return 0
end
ST[14] = function(self)                                       -- 1F34: a replay
  self.payout, self.timer, self.state = 0, 0, 15
  payStart(self); animSet(self, 11)
  return 0
end
ST[15] = function(self)
  self.timer = self.timer + 1
  if self.timer == 15 then animSet(self, 2)
  elseif self.timer > 15 and payDone(self) and animDone(self) then
    animSet(self, 0); self.timer, self.state = 0, 3; return 1
  end
  return 0
end
ST[16] = function(self)                                       -- 1FA0: bonus, no win
  lampsOff(self); self:bonusDraw(); self:lookDraw(); animSet(self, 11)
  self.stats.bonusFlags = self.stats.bonusFlags + 1
  self.timer, self.state = 0, 17
  return 0
end
ST[17] = function(self)
  self.timer = self.timer + 1
  if self.timer >= 8 then animSet(self, 3); self:musicTo(1); self.state = 18 end
  return 0
end
ST[18] = function(self) if animDone(self) then self.state = 23; return 1 end return 0 end
ST[19] = function(self)                                       -- 200C: bonus with a paid role
  self.payout = self:pay()
  self.stats.paid = self.stats.paid + self.payout
  self.timer, self.state = 0, 20
  payStart(self); self:bonusDraw(); self:lookDraw(); animSet(self, 11)
  self.stats.bonusFlags = self.stats.bonusFlags + 1
  return 0
end
ST[20] = function(self)
  self.timer = self.timer + 1
  if self.timer == 30 then self:musicTo(1); animSet(self, 3)
  elseif self.timer >= 30 and payDone(self) and animDone(self) then self.timer, self.state = 0, 23; return 1 end
  return 0
end
ST[21] = function(self)                                       -- 2088: bonus with a replay
  self.timer, self.state = 0, 22
  payStart(self); animSet(self, 11); self:bonusDraw(); self:lookDraw()
  self.stats.bonusFlags = self.stats.bonusFlags + 1
  return 0
end
ST[22] = function(self)
  self.timer = self.timer + 1
  if self.timer == 8 then animSet(self, 3); self:musicTo(1)
  elseif self.timer >= 8 and payDone(self) and animDone(self) then self.timer, self.state = 0, 24; return 1 end
  return 0
end
ST[23] = function(self) self.state = 25; return 1 end         -- 20FC
ST[24] = function(self) self.state = 28; return 1 end         -- 2114 (the replay's free spin)
ST[25] = function(self)                                       -- 212C: standby bet
  newGame(self)
  self.flags = 0
  self.state = 26
  animSet(self, 7)
  coinsCheck(self, 59, 26, 3)
  return 1
end
ST[26] = function(self)
  if self.keys.start then self.state = 63; showStop(self); return 0 end
  if self.keys.x then
    self.credit = self.credit - 3
    self.stats.bet = self.stats.bet + 3
    self.state = 27
    self:play("se", "SEQ_SE_DP_ZUKAN02")
    showStop(self); lampsBet(self)
  end
  return 0
end
ST[27] = function(self)
  if self.keys.start then self.credit = self.credit + 3; self.stats.bet = self.stats.bet - 3; self.state = 63; return 0 end
  if self.keys.down or self.keys.x then self.state = 28; return 1 end
  return 0
end
ST[28] = function(self)                                       -- 2228
  self:standbyLottery()
  self.stats.spins = self.stats.spins + 1
  self.stats.standby = self.stats.standby + 1
  self.stats.roles[self.flags] = (self.stats.roles[self.flags] or 0) + 1
  self.bigSlip = has(self.flags, 1 + 2 + 16 + 32) and 1 or 0
  self.assist = (self.flags ~= 0) and 1 or 0
  lampsBet(self)
  spin(self)
  animSet(self, 9)
  self.state = 29
  return 1
end
ST[29] = function(self)
  self.timer = self.timer + 1
  if self.timer >= 8 then self.timer, self.state = 0, 30; return 1 end
  return 0
end
ST[30] = function(self)
  stops(self, "SEQ_SE_DP_UG_022", { "y", "b", "a" }, false)
  if self.reelState[0] == 2 and self.reelState[1] == 2 and self.reelState[2] == 2 then self.state = 31 end
  return 0
end
ST[31] = function(self)
  for i = 0, 2 do if reelBusy(self, i) then return 0 end end
  lampsOff(self)
  self.state = 32
  return 1
end
ST[32] = function(self)                                       -- 2420
  local v, m = self:judge()
  self.sym, self.lines = v, m
  if v == L.NONE then self.state = 33; return 1 end
  if has(self.flags, 256 + 512) then self.state = 39; return 1 end
  if v == 2 then self.state = 37; return 1 end
  self.state = 35
  return 1
end
ST[33] = function(self) lampsOff(self); animSet(self, 7); self.timer, self.state = 0, 34; return 1 end
ST[34] = function(self)
  self.timer = self.timer + 1
  if self.timer >= 8 then self.timer, self.state = 0, 25; return 1 end
  return 0
end
ST[35] = function(self)
  self.payout = self:pay()
  self.stats.paid = self.stats.paid + self.payout
  self.timer, self.state = 0, 36
  payStart(self); animSet(self, 10)
  return 0
end
ST[36] = function(self)
  if payDone(self) then animSet(self, 7); self.state = 25; return 1 end
  return 0
end
ST[37] = function(self)
  self.payout, self.timer, self.state = 0, 0, 38
  payStart(self); animSet(self, 10)
  return 0
end
ST[38] = function(self)
  self.timer = self.timer + 1
  if self.timer > 15 and payDone(self) then
    animSet(self, 7); lampsOff(self); self.timer, self.state = 0, 28; return 1
  end
  return 0
end
ST[39] = function(self)                                       -- 254C: the 7s
  self.payout = self:pay()
  self.stats.paid = self.stats.paid + self.payout
  self.timer, self.state = 0, 40
  payStart(self); animSet(self, 10)
  fade(self, "in")
  self:musicTo(2)
  self.dropObj = drop(self)
  return 0
end
ST[40] = function(self)
  if payDone(self) then
    finish(self, self.dropObj); self.dropObj = nil
    animSet(self, 7)
    self.state = 41
    return 1
  end
  return 0
end
ST[41] = function(self)                                       -- 25C4: the bonus round
  self.anim.hide = 0
  self.anim.counters = counters(self)
  self.round, self.won, self.bonus = 0, 0, 1
  self.state = 42
  return 1
end
ST[42] = function(self)                                       -- 25DC: a new round of 15
  self.games = self.games + 1
  self.round = math.min(999, self.round + 1)
  roundDigits(self, self.round)
  self.left, self.bonus = 16, 1
  self.guaranteed, self.special, self.ending = 0, 0, 0
  if not (r100(self) < self.cont) then self.ending = 1 end   -- ov101_021D44E8 == 0
  self.state = 43
  return 1
end
ST[43] = function(self)                                       -- 2628
  self.left = self.left - 1
  for i = 0, 2 do buttonUp(self, i) end
  lampsOff(self)
  showStart(self)
  animSet(self, 7)
  self.state = 44
  if self.credit < 1 then self.state, self.next = 60, 63
  elseif self.credit >= L.MAX then self.state, self.next = 61, 44 end
  return 1
end
ST[44] = function(self)
  if self.keys.start then self.state = 63; return 0 end
  if self.keys.x then
    self.credit = self.credit - 1
    self.won = math.max(0, self.won - 1)
    self.stats.bet = self.stats.bet + 1
    self.state = 45
    self:play("se", "SEQ_SE_DP_ZUKAN02")
    showStop(self)
    self.lamp[0] = 12                                         -- ov101_021D4FB8(line 0)
  end
  return 0
end
ST[45] = function(self)
  if self.keys.start then self.credit = self.credit + 1; self.stats.bet = self.stats.bet - 1; self.state = 63; return 0 end
  if self.keys.down or self.keys.x then self.state = 46; return 1 end
  return 0
end
ST[46] = function(self)                                       -- 2738
  self.stats.spins = self.stats.spins + 1
  self.stats.bonusGames = self.stats.bonusGames + 1
  self.flags, self.assist, self.bigSlip = 1, 1, 1
  for i = 0, 2 do buttonUp(self, i) end
  self.lamp[0] = 12
  for i = 0, 2 do startReel(self, i) end
  for i = 0, 2 do self.pressed[i] = false end
  self.order = lcrng(self) % 6                                -- ov101_021D45B0
  for i = 0, 2 do self.reelState[i] = 1 end
  self.timer = 0
  self.state = 47
  self:play("se", "SEQ_SE_DP_OPEN2")
  if self.guaranteed == 0 and self.special == 0 then
    if r100(self) < L.SPECIAL[self.setting] then self.special = 1 end
    if self.special == 1 then fade(self, "flash", 1) end
  end
  if self.guaranteed == 0 and self.special == 0 then
    if r100(self) < L.GUARANTEE[self.setting] then self.guaranteed = 1 end
    if self.guaranteed == 1 then fade(self, "flash", 0) end
  end
  return 1
end
ST[47] = function(self)
  self.timer = self.timer + 1
  if self.timer >= 8 then self.timer, self.state = 0, 48; animSet(self, 6); return 1 end
  return 0
end
ST[48] = function(self)
  -- SE_CONFIRM_sseq_6: the seventh seqInfo entry on SE_CONFIRM.sseq,
  -- SEQ_SE_DP_SELECT_SLOT (INFERRED from pl_sound_data.json's order)
  stops(self, "SEQ_SE_DP_SELECT_SLOT", L.ORDERS[self.order][1], true)
  if self.reelState[0] == 2 and self.reelState[1] == 2 and self.reelState[2] == 2 then self.state = 49 end
  return 0
end
ST[49] = function(self)
  for i = 0, 2 do if reelBusy(self, i) then return 0 end end
  lampsOff(self)
  self.state = 50
  return 1
end
ST[50] = function(self)                                       -- 2988
  local v, m = self:judgeBonus()
  self.sym, self.lines = v, m
  if v == L.NONE then
    if self.special == 1 then self.special = 3 end
    self.state = 51
    return 1
  end
  if self.special == 1 then self.special = 2 end
  self.state = 52
  return 1
end
ST[51] = function(self)
  lampsOff(self); animSet(self, 7)
  self.state = (self.left <= 1) and 54 or 43
  return 0
end
ST[52] = function(self)
  self.payout = L.PAY_BONUS[self.sym]
  self.stats.paid = self.stats.paid + self.payout
  payStart(self); animSet(self, 10)
  self.timer, self.state = 0, 53
  return 0
end
ST[53] = function(self)
  if not payDone(self) then return 0 end
  animSet(self, 7)
  self.state = (self.left <= 1) and 54 or 43
  return 1
end
ST[54] = function(self)                                       -- 2A44: the round is over
  self.left = self.left - 1
  if self.ending == 1 and self.guaranteed == 0 then animSet(self, 8); self.state = 58; return 0 end
  self.state = 55
  return 1
end
ST[55] = function(self)                                       -- 2A78
  self:decay()
  local v = self:outcome()
  if self.guaranteed == 1 then v = 2 end
  self.lastOutcome = v
  if v == 2 then animSet(self, 5); self.state = 56; return 0 end
  if v == 1 then animSet(self, 12); self.state = 57; return 0 end
  self:play("cry", 35)
  self.state = 42
  return 0
end
ST[56] = function(self) if animDone(self) then self.state = 42; return 1 end return 0 end
ST[57] = ST[56]
ST[58] = function(self)                                       -- 2AF8: the bonus is over
  if not animDone(self) then return 0 end
  if self.round > self.best then self.best = self.round end
  self:musicTo(0)
  fade(self, "out")
  self.bonus = 0
  self.state = 0
  return 1
end
ST[59] = function(self) message(self, 0); self.state = 62; return 0 end
ST[60] = function(self) message(self, 2); self.state = 62; return 0 end
ST[61] = function(self) message(self, 1); self.state = 62; return 0 end
ST[62] = function(self)
  if self.keys.a or self.keys.b then self.message = nil; self.state = self.next end
  return 0
end
ST[63] = function(self) showStop(self); return 2 end
L.STATES = ST

-- ov101_021D597C: the payout of the lines just judged
function L:pay()
  local n, m = 0, self.lines
  for line = 0, 4 do if has(m, 2 ^ line) then n = n + L.PAY[self.sym] end end
  return n
end

-- ----------------------------------------------------------- one frame --
-- keys: what was pressed this frame ({ a = true, ... }); held: what is down.
-- Returns true when the app is finished (state 63 ran).
function L:step(keys, held)
  self.keys, self.held = keys or {}, held or {}
  -- the app (ov101_021D1AAC); once it has said 2 only the tasks run on
  -- (ov101_021D0E40 waits for the fade and the music task)
  if not self.finished then
    local r
    repeat
      local fn = (self.hook and self.hook[self.state]) or ST[self.state]   -- a test's tap
      r = fn(self)
    until r ~= 1
    if r == 2 then
      self.finished = true
      self:musicTo(0)                                         -- ov101_021D1894(00)
    end
  end
  -- the SysTasks, in priority order
  for i = 0, 2 do self:reelTask(self.reels[i]) end            -- 129..131
  animTask(self)                                              -- 132
  local list = {}
  for i, o in ipairs(self.objs) do list[i] = o end
  for _, o in ipairs(list) do objTick(self, o) end            -- 134..142
  payTask(self)                                               -- 138
  for _, b in ipairs(self.payTask.blink) do blinkTick(self, b) end -- 143
  showTick(self)                                              -- 143
  fadeTasks(self)                                             -- 143
  musicTask(self)                                             -- 144
  return self.finished == true
end

-- ov101_021D18B4: the music task still switching
function L:musicBusy() return self.music.busy == 1 end

-- what the session books (ov101_021D0F3C)
function L:result()
  return { coins = math.min(L.MAX, self.credit), bonusWins = self.best, games = self.games }
end

return L
