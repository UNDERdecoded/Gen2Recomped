-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE FRONT END'S SPRITE LAYOUTS, BUILT BY THE CARTRIDGE (round 36).
--
-- Where the GBA takes them from: the front end's pictures are objects of
-- the shared ALttP / Four Swords object system (type 6, kind 0x3B: the file
-- panels, their name plates, the hearts, the cursor fairy, the buttons, the
-- game cards...). Each frame the object loop (ARM, 0x0800023C) runs every
-- object's code, which places it relative to its parent object (+0x54) with
-- its own offsets and animates its frame (+0x21); then the sprite builder
-- 0x08000CFC writes its OAM from the frame lists (table 0x0862F52C [set
-- +0x1B] -> frame [+0x21] -> a count and 5-byte pieces {x, y, shape/size/
-- flips/tile high, tile, palette}) plus the object's position, tile base,
-- palette and priority. So the layouts are computed by code from many small
-- code immediates spread over the front-end tasks (8: 0x0800F809, 6:
-- 0x0803074D) and their objects.
--
-- Instead of shipping a copy (round 13 read the OAM off a scratch
-- interpreter run), the import runs that code: a small Thumb interpreter
-- boots the cartridge from AgbMain, presses the buttons a player would
-- (START, A on the empty file, a letter, END, A on the file), and takes the
-- OAM and the display registers at four frames -- CHOOSE A FILE (empty),
-- ENTER A NAME, CHOOSE A FILE (used), CHOOSE A GAME. The frames and the
-- presses are ours (they pick an animation phase); every number in the
-- layouts is the cartridge's.
--
-- What is not the GBA's (stand-ins that the interpreter needs): the BIOS
-- calls (LZ77 to WRAM / VRAM, CpuSet, CpuFastSet, Div; waits are no-ops),
-- DMA (done at once when enabled), VCOUNT (a counter that steps on every
-- read), the VBlank interrupt (its handler 0x0800B701 is run at the main
-- loop's wait 0x0800B550), the EEPROM (blank, through the cartridge's read
-- / write routines 0x08135DC4 / 0x08135E74), and the two ARM routines the
-- object system copies to IWRAM (the object loop and an object's overlap
-- list), written here in Lua from their ARM code.

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, arshift = bit.lshift, bit.rshift, bit.arshift
local floor, byte = math.floor, string.byte

local M = {}

local TWO32 = 4294967296
local TWO31 = 2147483648
local SENT = 0x0BFFFFF0

-- cartridge addresses (logic, not data)
M.A = {
  agbMain = 0x0800B084, loopTop = 0x0800B120, vblWait = 0x0800B550, vblank = 0x0800B701,
  vblFlag = 0x0300050C, task = 0x03006D10, eepRead = 0x08135DC4, eepWrite = 0x08135E74,
  objHeads = 0x03005958, objHeadsEnd = 0x030059A0, objTypes = 0x08000218,
  objList = 0x02016D50, overlapMasks = 0x08137B10,
  armObjLoop = { 0x08137B00, 0x0800023C, 0x03006740 }, armOverlap = { 0x03005AE0, 0x080008A8 },
}

local function u32(x) return x % TWO32 end

-- 32 x 32 -> low 32 bits, exact in doubles
local function mul32(a, b)
  local al, ah = a % 65536, floor(a / 65536)
  local bl, bh = b % 65536, floor(b / 65536)
  return ((al * bh + ah * bl) % 65536 * 65536 + al * bl) % TWO32
end

local function zeros(n)
  local t = {}
  for i = 0, n - 1 do t[i] = 0 end
  return t
end

-- a machine over the ROM string
function M.new(rom)
  local A = M.A
  local ew, iw, io, pal, vram, oam = zeros(0x40000), zeros(0x8000), zeros(0x400), zeros(0x400), zeros(0x18000), zeros(0x400)
  local romLen = #rom
  local vcount = 0
  local S = { r = {}, n = false, z = false, c = false, v = false, steps = 0, hooks = {},
              ew = ew, iw = iw, io = io, pal = pal, vram = vram, oam = oam }
  local r = S.r
  for i = 0, 15 do r[i] = 0 end
  r[13] = 0x03007E00

  -- region -> buffer, offset (nil = unmapped)
  local function reg(a)
    local hi = floor(a / 0x1000000)
    if hi == 2 then return ew, a % 0x40000
    elseif hi == 3 then return iw, a % 0x8000
    elseif hi == 4 then return io, a % 0x400
    elseif hi == 5 then return pal, a % 0x400
    elseif hi == 6 then
      local o = a % 0x20000
      if o >= 0x18000 then o = o - 0x8000 end
      return vram, o
    elseif hi == 7 then return oam, a % 0x400 end
    return nil, 0
  end
  local function romByte(o) return byte(rom, o + 1) or 0 end

  local function r8(a)
    if a == 0x04000006 then vcount = (vcount + 1) % 228; return vcount end
    local hi = floor(a / 0x1000000)
    if hi == 2 then return ew[a % 0x40000] end
    if hi == 3 then return iw[a % 0x8000] end
    if hi >= 8 and hi <= 0xD then return romByte(a % 0x2000000) end
    local b, o = reg(a)
    if not b then return 0 end
    return b[o] or 0
  end
  local function r16(a)
    a = a - a % 2
    if a == 0x04000006 then vcount = (vcount + 1) % 228; return vcount end
    local hi = floor(a / 0x1000000)
    if hi == 2 then local o = a % 0x40000; return ew[o] + ew[o + 1] * 256 end
    if hi == 3 then local o = a % 0x8000; return iw[o] + iw[o + 1] * 256 end
    if hi == 0xD then return 1 end
    if hi >= 8 and hi < 0xD then
      local o = a % 0x2000000
      if o + 2 > romLen then return 0 end
      local b0, b1 = byte(rom, o + 1, o + 2)
      return b0 + b1 * 256
    end
    local b, o = reg(a)
    if not b or b[o + 1] == nil then return 0 end
    return b[o] + b[o + 1] * 256
  end
  local function r32(a)
    a = a - a % 4
    local hi = floor(a / 0x1000000)
    if hi == 2 then local o = a % 0x40000; return ew[o] + ew[o + 1] * 256 + ew[o + 2] * 65536 + ew[o + 3] * 16777216 end
    if hi == 3 then local o = a % 0x8000; return iw[o] + iw[o + 1] * 256 + iw[o + 2] * 65536 + iw[o + 3] * 16777216 end
    if hi >= 8 and hi <= 0xD then
      local o = a % 0x2000000
      if o + 4 > romLen then return 0 end
      local b0, b1, b2, b3 = byte(rom, o + 1, o + 4)
      return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
    end
    local b, o = reg(a)
    if not b or b[o + 3] == nil then return 0 end
    return b[o] + b[o + 1] * 256 + b[o + 2] * 65536 + b[o + 3] * 16777216
  end

  local w16, w32
  -- DMA: done at once when a channel's control word is written enabled
  local function ioWrite(o)
    for ch = 0, 3 do
      local base = 0xB0 + ch * 12
      if o == base + 10 then
        local cnt = io[o] + io[o + 1] * 256
        if cnt >= 0x8000 then
          local src = io[base] + io[base + 1] * 256 + io[base + 2] * 65536 + io[base + 3] * 16777216
          local dst = io[base + 4] + io[base + 5] * 256 + io[base + 6] * 65536 + io[base + 7] * 16777216
          local n = io[base + 8] + io[base + 9] * 256
          if n == 0 then n = 0x4000 end
          local wide = band(cnt, 0x400) ~= 0
          local sm, dm = band(rshift(cnt, 7), 3), band(rshift(cnt, 5), 3)
          local st = wide and 4 or 2
          for _ = 1, n do
            if wide then w32(dst, r32(src)) else w16(dst, r16(src)) end
            if sm == 0 then src = src + st elseif sm == 1 then src = src - st end
            if dm == 0 or dm == 3 then dst = dst + st elseif dm == 1 then dst = dst - st end
          end
          io[o + 1] = band(io[o + 1], 0x7F)
        end
      end
    end
  end
  local function w8(a, v)
    local b, o = reg(a)
    if not b then return end
    v = v % 256
    local hi = floor(a / 0x1000000)
    if hi >= 5 and hi <= 7 then o = o - o % 2; b[o] = v; b[o + 1] = v; return end
    b[o] = v
  end
  w16 = function(a, v)
    a = a - a % 2
    local b, o = reg(a)
    if not b then return end
    v = v % 65536
    b[o] = v % 256; b[o + 1] = floor(v / 256)
    if b == io then ioWrite(o) end
  end
  w32 = function(a, v)
    a = a - a % 4
    local b, o = reg(a)
    if not b then return end
    v = v % TWO32
    b[o] = v % 256; b[o + 1] = floor(v / 256) % 256; b[o + 2] = floor(v / 65536) % 256; b[o + 3] = floor(v / 16777216)
    if b == io then ioWrite(o); ioWrite(o + 2) end
  end
  S.r8, S.r16, S.r32, S.w8, S.w16, S.w32 = r8, r16, r32, w8, w16, w32

  -- BIOS LZ77 (0x11 WRAM / 0x12 VRAM: halfword writes)
  local function lz77(src, dst)
    local n = floor(r32(src) / 256)
    src = src + 4
    local out, len = {}, 0
    while len < n do
      local flags = r8(src); src = src + 1
      for k = 0, 7 do
        if len >= n then break end
        if band(flags, rshift(0x80, k)) ~= 0 then
          local b1, b2 = r8(src), r8(src + 1); src = src + 2
          local ln, disp = rshift(b1, 4) + 3, band(b1, 15) * 256 + b2 + 1
          for _ = 1, ln do len = len + 1; out[len] = out[len - disp] end
        else
          len = len + 1; out[len] = r8(src); src = src + 1
        end
      end
    end
    local i = 1
    while i + 1 <= n do w16(dst + i - 1, out[i] + out[i + 1] * 256); i = i + 2 end
    if n % 2 == 1 then w8(dst + n - 1, out[n]) end
  end

  local function setnz(v) S.n = v >= TWO31; S.z = v == 0; return v end
  local function add(a, b, c)
    local x = a + b + (c or 0)
    S.c = x >= TWO32
    x = x % TWO32
    S.v = band(bxor(a, x), bxor(b, x)) < 0
    return setnz(x)
  end
  local function sub(a, b, c)
    if c == nil then c = 1 end
    return add(a, u32(bnot(b)), c)
  end
  local function cond(cc)
    local n, z, c, v = S.n, S.z, S.c, S.v
    if cc == 0 then return z elseif cc == 1 then return not z
    elseif cc == 2 then return c elseif cc == 3 then return not c
    elseif cc == 4 then return n elseif cc == 5 then return not n
    elseif cc == 6 then return v elseif cc == 7 then return not v
    elseif cc == 8 then return c and not z elseif cc == 9 then return (not c) or z
    elseif cc == 10 then return n == v elseif cc == 11 then return n ~= v
    elseif cc == 12 then return (not z) and n == v elseif cc == 13 then return z or n ~= v end
    return true
  end

  local function swi(k)
    if k == 0x11 or k == 0x12 then lz77(r[0], r[1])
    elseif k == 0x06 then
      local a = r[0] >= TWO31 and r[0] - TWO32 or r[0]
      local b = r[1] >= TWO31 and r[1] - TWO32 or r[1]
      local q = 0
      if b ~= 0 then q = a / b; q = q >= 0 and floor(q) or -floor(-q) end
      local rr = a - q * b
      r[0] = u32(q); r[1] = u32(rr); r[3] = u32(math.abs(q))
    elseif k == 0x0B or k == 0x0C then
      local src, dst, cnt = r[0], r[1], r[2]
      local n = cnt % 0x200000
      local fill = band(rshift(cnt, 24), 1) == 1
      local wide = k == 0x0C or band(rshift(cnt, 26), 1) == 1
      if k == 0x0C then n = band(n + 7, bnot(7)) end
      local st = wide and 4 or 2
      local v0 = wide and r32(src) or r16(src)
      for i = 0, n - 1 do
        local v = fill and v0 or (wide and r32(src + i * st) or r16(src + i * st))
        if wide then w32(dst + i * st, v) else w16(dst + i * st, v) end
      end
    elseif k == 0x05 or k == 0x04 or k == 0x02 then
      -- waits
    else
      error(("FrontRun: swi %X at %08X"):format(k, r[15]))
    end
  end

  local ARM = {}
  S.ARM = ARM
  local function bx(v)
    if v % 2 == 1 then r[15] = v - 1; return end
    local f = ARM[v]
    if f then
      local rv = f(S)
      r[0] = u32(rv or 0)
      r[15] = r[14] - r[14] % 2
      return
    end
    error(("FrontRun: ARM bx to %08X"):format(v))
  end

  local function ldm(list, a, b, load)
    for i = 0, 7 do
      if band(list, lshift(1, i)) ~= 0 then
        if load then r[i] = r32(a) else w32(a, r[i]) end
        a = a + 4
      end
    end
    return a
  end

  local hooks = S.hooks
  local function run(maxsteps)
    while true do
      local pc = r[15]
      if pc == SENT then return r[0] end
      local h = hooks[pc]
      if not (h and h(S)) then
        local steps = S.steps + 1
        S.steps = steps
        if steps > maxsteps then error(("FrontRun: too many steps at %08X"):format(pc)) end
        local op = r16(pc)
        r[15] = pc + 2
        local top = rshift(op, 13)
        if top == 0 then
          if band(rshift(op, 11), 3) == 3 then
            local rd, rs, rn = band(op, 7), band(rshift(op, 3), 7), band(rshift(op, 6), 7)
            local val = band(op, 0x400) ~= 0 and rn or r[rn]
            if band(op, 0x200) ~= 0 then r[rd] = sub(r[rs], val) else r[rd] = add(r[rs], val) end
          else
            local kind, imm, rs, rd = band(rshift(op, 11), 3), band(rshift(op, 6), 31), r[band(rshift(op, 3), 7)], band(op, 7)
            if kind == 0 then
              if imm ~= 0 then S.c = band(rshift(rs, 32 - imm), 1) == 1; rs = u32(lshift(rs, imm)) end
            elseif kind == 1 then
              if imm == 0 then imm = 32 end
              S.c = (imm == 32 and rs >= TWO31) or (imm < 32 and band(rshift(rs, imm - 1), 1) == 1)
              rs = imm < 32 and u32(rshift(rs, imm)) or 0
            else
              if imm == 0 then imm = 32 end
              if imm < 32 then S.c = band(rshift(rs, imm - 1), 1) == 1 else S.c = rs >= TWO31 end
              rs = u32(arshift(rs, math.min(imm, 31)))
            end
            r[rd] = setnz(rs)
          end
        elseif top == 1 then
          local k, rd, imm = band(rshift(op, 11), 3), band(rshift(op, 8), 7), band(op, 0xFF)
          if k == 0 then r[rd] = setnz(imm)
          elseif k == 1 then sub(r[rd], imm)
          elseif k == 2 then r[rd] = add(r[rd], imm)
          else r[rd] = sub(r[rd], imm) end
        elseif top == 2 then
          local o10 = rshift(op, 10)
          if o10 == 0x10 then
            local k, a = band(rshift(op, 6), 15), band(op, 7)
            local b, x = r[band(rshift(op, 3), 7)], r[a]
            if k == 0 then r[a] = setnz(u32(band(x, b)))
            elseif k == 1 then r[a] = setnz(u32(bxor(x, b)))
            elseif k == 2 then
              b = b % 256
              if b ~= 0 then
                if b <= 32 then S.c = band(rshift(x, 32 - b), 1) == 1 else S.c = false end
                if b == 32 then S.c = x % 2 == 1 end
                x = b < 32 and u32(lshift(x, b)) or 0
              end
              r[a] = setnz(x)
            elseif k == 3 then
              b = b % 256
              if b ~= 0 then
                if b <= 32 then S.c = (b == 32 and x >= TWO31) or (b < 32 and band(rshift(x, b - 1), 1) == 1) else S.c = false end
                x = b < 32 and u32(rshift(x, b)) or 0
              end
              r[a] = setnz(x)
            elseif k == 4 then
              b = b % 256
              if b ~= 0 then
                local sb = math.min(b, 32)
                if sb == 32 then S.c = x >= TWO31 else S.c = band(rshift(x, sb - 1), 1) == 1 end
                x = u32(arshift(x, math.min(b, 31)))
              end
              r[a] = setnz(x)
            elseif k == 5 then r[a] = add(x, b, S.c and 1 or 0)
            elseif k == 6 then r[a] = sub(x, b, S.c and 1 or 0)
            elseif k == 7 then
              b = b % 256
              if b ~= 0 then
                b = b % 32
                if b ~= 0 then x = u32(bor(rshift(x, b), lshift(x, 32 - b))) end
                S.c = x >= TWO31
              end
              r[a] = setnz(x)
            elseif k == 8 then setnz(u32(band(x, b)))
            elseif k == 9 then r[a] = sub(0, b)
            elseif k == 10 then sub(x, b)
            elseif k == 11 then add(x, b)
            elseif k == 12 then r[a] = setnz(u32(bor(x, b)))
            elseif k == 13 then r[a] = setnz(mul32(x, b))
            elseif k == 14 then r[a] = setnz(u32(band(x, bnot(b))))
            else r[a] = setnz(u32(bnot(b))) end
          elseif o10 == 0x11 then
            local k = band(rshift(op, 8), 3)
            local a = bor(band(op, 7), band(rshift(op, 4), 8))
            local b = band(rshift(op, 3), 15)
            local rb = b == 15 and (r[15] + 2) % TWO32 or r[b]
            if k == 0 then
              local ra = a == 15 and (r[15] + 2) % TWO32 or r[a]
              local v = (ra + rb) % TWO32
              if a == 15 then r[15] = v - v % 2 else r[a] = v end
            elseif k == 1 then
              local ra = a == 15 and (r[15] + 2) % TWO32 or r[a]
              sub(ra, rb)
            elseif k == 2 then
              if a == 15 then r[15] = rb - rb % 2 else r[a] = rb end
            else bx(rb) end
          elseif rshift(op, 11) == 9 then
            local a = (pc + 4) - (pc + 4) % 4 + band(op, 0xFF) * 4
            r[band(rshift(op, 8), 7)] = r32(a)
          else
            local k = band(rshift(op, 9), 7)
            local a = (r[band(rshift(op, 3), 7)] + r[band(rshift(op, 6), 7)]) % TWO32
            local t = band(op, 7)
            if k == 0 then w32(a, r[t])
            elseif k == 1 then w16(a, r[t])
            elseif k == 2 then w8(a, r[t])
            elseif k == 3 then local v = r8(a); r[t] = v >= 128 and v - 256 + TWO32 or v
            elseif k == 4 then r[t] = r32(a)
            elseif k == 5 then r[t] = r16(a)
            elseif k == 6 then r[t] = r8(a)
            else local v = r16(a); r[t] = v >= 32768 and v - 65536 + TWO32 or v end
          end
        elseif top == 3 then
          local k, imm, b, t = band(rshift(op, 11), 3), band(rshift(op, 6), 31), r[band(rshift(op, 3), 7)], band(op, 7)
          if k == 0 then w32(b + imm * 4, r[t])
          elseif k == 1 then r[t] = r32(b + imm * 4)
          elseif k == 2 then w8(b + imm, r[t])
          else r[t] = r8(b + imm) end
        elseif top == 4 then
          if rshift(op, 12) == 8 then
            local imm, b, t = band(rshift(op, 6), 31) * 2, r[band(rshift(op, 3), 7)], band(op, 7)
            if band(op, 0x800) ~= 0 then r[t] = r16(b + imm) else w16(b + imm, r[t]) end
          else
            local imm, t = band(op, 0xFF) * 4, band(rshift(op, 8), 7)
            if band(op, 0x800) ~= 0 then r[t] = r32(r[13] + imm) else w32(r[13] + imm, r[t]) end
          end
        elseif top == 5 then
          if rshift(op, 12) == 0xA then
            local imm, t = band(op, 0xFF) * 4, band(rshift(op, 8), 7)
            if band(op, 0x800) ~= 0 then r[t] = (r[13] + imm) % TWO32 else r[t] = (pc + 4) - (pc + 4) % 4 + imm end
          elseif rshift(op, 8) == 0xB0 then
            local imm = band(op, 0x7F) * 4
            if band(op, 0x80) ~= 0 then r[13] = (r[13] - imm) % TWO32 else r[13] = (r[13] + imm) % TWO32 end
          elseif band(rshift(op, 9), 3) == 2 then
            if band(op, 0x800) ~= 0 then
              local sp = ldm(op, r[13], 13, true)
              if band(op, 0x100) ~= 0 then local v = r32(sp); r[15] = v - v % 2; sp = sp + 4 end
              r[13] = sp
            else
              local cnt = 0
              for i = 0, 7 do if band(op, lshift(1, i)) ~= 0 then cnt = cnt + 1 end end
              local lr = band(op, 0x100) ~= 0
              if lr then cnt = cnt + 1 end
              local sp = r[13] - 4 * cnt
              r[13] = sp
              sp = ldm(op, sp, 13, false)
              if lr then w32(sp, r[14]) end
            end
          else
            error(("FrontRun: op %04X at %08X"):format(op, pc))
          end
        elseif top == 6 then
          if rshift(op, 12) == 0xC then
            local b = band(rshift(op, 8), 7)
            local load = band(op, 0x800) ~= 0
            local a = ldm(op, r[b], b, load)
            if not (load and band(op, lshift(1, b)) ~= 0) then r[b] = a % TWO32 end
          else
            local cc = band(rshift(op, 8), 15)
            if cc == 15 then swi(band(op, 0xFF))
            elseif cc == 14 then error(("FrontRun: undefined at %08X"):format(pc))
            elseif cond(cc) then
              local off = band(op, 0xFF)
              if off >= 0x80 then off = off - 256 end
              r[15] = (pc + 4 + off * 2) % TWO32
            end
          end
        else
          local o11 = rshift(op, 11)
          if o11 == 0x1C then
            local off = band(op, 0x7FF)
            if off >= 0x400 then off = off - 0x800 end
            r[15] = (pc + 4 + off * 2) % TWO32
          elseif o11 == 0x1E then
            local off = band(op, 0x7FF)
            if off >= 0x400 then off = off - 0x800 end
            r[14] = (pc + 4 + off * 4096) % TWO32
          elseif o11 == 0x1F then
            local t = (r[14] + band(op, 0x7FF) * 2) % TWO32
            r[14] = pc + 2 + 1
            r[15] = t
          else
            error(("FrontRun: op %04X at %08X"):format(op, pc))
          end
        end
      end
    end
  end

  function S.call(addr, maxsteps, ...)
    local args = { ... }
    for i = 1, #args do r[i - 1] = u32(args[i]) end
    r[14] = SENT + 1
    r[15] = addr - addr % 2
    return run(maxsteps or 5000000)
  end

  -- a nested call that keeps the caller's registers and flags
  function S.ncall(addr, ...)
    local saved = {}
    for i = 0, 15 do saved[i] = r[i] end
    local fl = { S.n, S.z, S.c, S.v }
    local ok, rv = pcall(S.call, addr, S.steps + 20000000, ...)
    for i = 0, 15 do r[i] = saved[i] end
    S.n, S.z, S.c, S.v = fl[1], fl[2], fl[3], fl[4]
    if not ok then error(rv, 0) end
    return rv
  end

  function S.callany(fn, ...)
    if fn % 2 == 0 and ARM[fn] then
      local saved = {}
      for i = 0, 15 do saved[i] = r[i] end
      local args = { ... }
      for i = 1, #args do r[i - 1] = u32(args[i]) end
      local rv = ARM[fn](S)
      for i = 0, 15 do r[i] = saved[i] end
      return rv
    end
    return S.ncall(fn, ...)
  end
  return S
end

-- the two ARM routines, as their ARM code does them
local function objLoop(S)
  local A = M.A
  local r8, r16, r32, w8, w16, w32 = S.r8, S.r16, S.r32, S.w8, S.w16, S.w32
  w16(0x0300020A, r16(0x03000208)); w16(0x03000208, 0)
  local r4 = A.objHeads
  while true do
    r4 = r4 + 8
    if r4 >= A.objHeadsEnd then break end
    local fp = r32(r4 + 4)
    while true do
      w32(0x0300044C, fp)
      if r4 == fp then break end
      local fn = r32(A.objTypes + r8(fp + 8) * 4)
      S.callany(fn, fp)
      local r0 = r32(0x0300044C)
      if r0 == fp then S.callany(0x03005AE0, r0) end
      fp = r32(r0 + 4)
    end
    if r4 == 0x03005968 then S.callany(0x0803E115) end
  end
  S.callany(0x080126CD)
  w16(0x0300020A, 0)
  return 0
end

local function overlap(S)
  local A = M.A
  local r8, r16, r32, w8, w32 = S.r8, S.r16, S.r32, S.w8, S.w32
  local r0 = S.r[0]
  local r2 = 0
  if r8(r0 + 0x3C) >= 0x80 then
    local r4 = r16(r0 + 0x5C)
    local r1 = r32(A.objList)
    local head = r1
    local r5 = (r16(r0 + 0x32) + 0x38) % TWO32
    local r6 = (r16(r0 + 0x36) + 0x38) % TWO32
    local r7 = r16(r0 + 0x50)
    local sb = 0
    while true do
      local r3 = r32(r1 + 8)
      local ok = r3 ~= 0
      local r8v
      if ok then r8v = r8(r3 + 0x3C); ok = r8v >= 0x80 end
      if ok then ok = band(r32(A.overlapMasks + band(r8v, 15) * 4), r4) ~= 0 end
      if ok then ok = (r5 - r16(r3 + 0x32)) % TWO32 < 0x71 end
      if ok then ok = (r6 - r16(r3 + 0x36)) % TWO32 < 0x71 end
      if ok then ok = rshift(band(r7, r16(r3 + 0x50)), 14) ~= 0 end
      if ok and r3 ~= r0 then
        sb = sb + 1
        local n = r8(r1 + 0xC)
        if n < 0x20 then w8(r1 + 0xC, n + 1); w32(r1 + 0x10 + n * 4, r0) end
      end
      r1 = r32(r1 + 4)
      if r1 == head then break end
    end
    r2 = sb
  end
  if r8(r0 + 8) == 3 then w8(r0 + 0x6B, r2) end
  return r2
end

-- OAM -> the drawn OBJs: {x, y, shape, size, tile, palette, hflip, vflip, prio}
-- (hidden, affine and off-screen entries left out)
function M.oamRows(S)
  local out = {}
  local o = S.oam
  for k = 0, 127 do
    local a0 = o[k * 8] + o[k * 8 + 1] * 256
    local a1 = o[k * 8 + 2] + o[k * 8 + 3] * 256
    local a2 = o[k * 8 + 4] + o[k * 8 + 5] * 256
    local mode = band(rshift(a0, 8), 3)
    local y, x = band(a0, 255), band(a1, 511)
    if mode ~= 2 and not (y >= 160 and y < 240) and not (x >= 240 and x < 512 - 64) and mode % 2 == 0 then
      out[#out + 1] = { x < 256 and x or x - 512, y < 160 and y or y - 256, rshift(a0, 14), rshift(a1, 14),
                        band(a2, 0x3FF), rshift(a2, 12), band(rshift(a1, 12), 1), band(rshift(a1, 13), 1),
                        band(rshift(a2, 10), 3) }
    end
  end
  return out
end

-- the display registers a screen leaves: BGxCNT, scroll, BLDCNT / BLDALPHA
function M.ioRegs(S)
  local io = S.io
  local function h(o) return io[o] + io[o + 1] * 256 end
  local t = { disp = h(0), bld = h(0x50), alpha = h(0x52), bgs = {} }
  for i = 0, 3 do
    t.bgs[i] = { cnt = h(8 + 2 * i), x = h(0x10 + 4 * i) % 512, y = h(0x12 + 4 * i) % 512 }
  end
  return t
end

-- boot the cartridge and take snapshots.
-- plan = { keys = { [frame] = mask }, shots = { [frame] = name }, last = frame }
-- returns { [name] = { task = id, oam = rows, io = regs } }
function M.boot(rom, plan, tick)
  local A = M.A
  local S = M.new(rom)
  for _, a in ipairs(A.armObjLoop) do S.ARM[a] = objLoop end
  for _, a in ipairs(A.armOverlap) do S.ARM[a] = overlap end
  local r = S.r
  local eep = {}
  S.hooks[A.eepRead] = function()
    local blk, dst = r[0] % 65536, r[1]
    local e = eep[blk]
    for i = 0, 7 do S.w8(dst + i, e and e[i] or 0xFF) end
    r[0] = 0; r[15] = r[14] - r[14] % 2
    return true
  end
  S.hooks[A.eepWrite] = function()
    local blk, src = r[0] % 65536, r[1]
    local e = {}
    for i = 0, 7 do e[i] = S.r8(src + i) end
    eep[blk] = e
    r[0] = 0; r[15] = r[14] - r[14] % 2
    return true
  end
  local frame = 0
  local shots = {}
  local STOP = {}
  S.hooks[A.loopTop] = function()
    local f = frame
    S.w16(0x04000130, bxor(0x3FF, plan.keys[f] or 0))
    local name = plan.shots[f]
    if name then
      shots[name] = { task = S.r8(A.task), oam = M.oamRows(S), io = M.ioRegs(S), frame = f }
    end
    frame = frame + 1
    S.steps = 0
    if tick and f % 64 == 0 then tick(f, plan.last) end
    if frame > plan.last then error(STOP, 0) end
    return false
  end
  S.hooks[A.vblWait] = function()
    if S.r8(A.vblFlag) == 0 then return false end
    local saved = {}
    for i = 0, 15 do saved[i] = r[i] end
    local fl = { S.n, S.z, S.c, S.v }
    S.w16(0x04000006, 160)
    local ok, err = pcall(S.call, A.vblank, S.steps + 5000000)
    for i = 0, 15 do r[i] = saved[i] end
    S.n, S.z, S.c, S.v = fl[1], fl[2], fl[3], fl[4]
    if not ok then error(err, 0) end
    S.w8(A.vblFlag, 0)
    return false
  end
  S.w16(0x04000130, 0x3FF)
  r[13] = 0x03007F00
  local ok, err = pcall(S.call, A.agbMain, 400000000)
  if not ok and err ~= STOP then error(err, 0) end
  return shots, frame
end

-- round 36: THE ITEM STRIP's layout, from the cartridge's own loader.
-- LoadItemGFXIntoWRAM4BPPBuffer (GBA 0x0812E554) decompresses sprite sheets
-- (LZ77 0x08135B90, the sheet pointers of table 0x0822B324) into a buffer
-- (0x02032000, 16 tiles a row) and copies runs of tiles (CpuFastSet
-- 0x08135B78, words) to the strip (RAM 0x02008800 + the SNES offsets that
-- kLinkDmaSources6 / 7 hold). Run here with both helpers recorded and
-- skipped: the result is strip tile -> { sheet, tile }.
M.STRIP = { loader = 0x0812E554, lz = 0x08135B90, fastSet = 0x08135B78, sheets = 0x0822B324,
            buffer = 0x02032000, base = 0x02008800, size = 0x1000 }

function M.itemStrip(rom)
  local P = M.STRIP
  local S = M.new(rom)
  local r = S.r
  local sheetOf = {}
  for i = 0, 255 do
    local o = P.sheets - 0x08000000 + i * 4
    local b0, b1, b2, b3 = byte(rom, o + 1, o + 4)
    local p = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
    if sheetOf[p] == nil then sheetOf[p] = i end
  end
  local sheet
  local map, copies = {}, 0
  local function ret() r[15] = r[14] - r[14] % 2; return true end
  S.hooks[P.lz] = function()
    sheet = (r[1] == P.buffer) and sheetOf[r[0]] or nil
    return ret()
  end
  S.hooks[P.fastSet] = function()
    local src, dst, n = r[0], r[1], r[2] % 0x200000
    if dst >= P.base and dst < P.base + P.size and sheet and src >= P.buffer and src < P.buffer + 0x1000 then
      copies = copies + 1
      local t0, s0 = (dst - P.base) / 32, (src - P.buffer) / 32
      for k = 0, n / 8 - 1 do map[t0 + k] = { sheet, s0 + k } end
    end
    return ret()
  end
  -- the loader's tail (0x0812FDEC, the travel bird's sheet) and anything
  -- else it calls run as they are; only the strip's copies are kept
  S.hooks[0x08135B8C] = ret   -- LZ77 to VRAM
  r[13] = 0x03007E00
  S.call(P.loader, 2000000)
  return map, copies
end

-- for the import (Extract: data.t.strip36); fails loudly on a wrong ROM
function M.stripTable(rom, check)
  local ok, map, copies = pcall(M.itemStrip, rom.data)
  check(ok, "the item strip loader did not run: %s", tostring(map))
  check(copies >= 20 and map[0] ~= nil, "the item strip loader made %d copies", copies or 0)
  for k, e in pairs(map) do
    check(k >= 0 and k < 128 and e[1] >= 0 and e[1] < 256 and e[2] >= 0 and e[2] < 128, "item strip tile %s", tostring(k))
  end
  return map
end

return M
