-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Round 35: the small cartridge tables the runtime modules used to carry as
-- literals, now read from the player's ROM at import (data.t.rt35) and
-- poured into the modules' live tables when the cache loads (RT.bind from
-- Data.load). A module asks for a table by name (RT.get) at load time and
-- gets an empty table that the bind fills in place, so its code keeps
-- indexing it as before.
--
-- A spec is { name, addr, count, kind, base, opts }:
--   addr   GBA ROM offset (or a list of offsets: one column each, rows {a, b..})
--   kind   "u8" / "s8" / "u16" / "s16" / "u32"
--   base   0: values at [0]..[n-1]; 1: at [1]..[n]
--   opts   w = n values a row (rows are 1-based lists), lo / hi = the range
--          every value must be in (the import fails loudly otherwise),
--          scale = multiply each value (a table the port keeps in other units),
--          keys = the index each value goes to (a list of keys, in order),
--          invert = true: the table maps each value to its index (skip = a
--          value left out), add = a constant added after the scale
-- Round 36, values the cartridge keeps in its code (count = #addr):
--   kind "imm"  addr = GBA addresses (0x08xxxxxx) of Thumb `movs / cmp /
--               adds / subs rN, #imm8` (a `movs` followed by `lsls rN, rN,
--               #s`, s < 16, is the value << s) or `ldr rN, [pc, #]` (the
--               literal); opts.op = the forms allowed (default: any)
--   kind "msg"  addr = GBA addresses of `bl` calls of the message routines
--               (RT.MSG_CALLS: 0x080C9164 / 0x080C9564 / 0x080C94F4 /
--               0x080E1058 with the number in r1, 0x080C95C0 / 0x080AF4FC
--               in r0); the value is that register as the code before the
--               call sets it, minus 3 (GBA message numbers are the SNES
--               ones + 3; the port uses the SNES numbers)
-- Round 37: opts.ref = { {site, delta} }: a table's user -- the code at site
-- must load the table's address (+ delta) from its literal pool.
-- A site that is not of its form fails the import.
-- Only offsets and shapes live here; the values come from the cartridge.

local RT = {}

local live = {}      -- name -> the table handed out by RT.get

RT.SPEC = {}
local function S(name, addr, n, kind, base, opts)
  RT.SPEC[#RT.SPEC + 1] = { name = name, addr = addr, n = n, kind = kind, base = base or 0, opts = opts or {} }
end
RT.S = S

local function read(rom, kind, a, n)
  local out = {}
  if kind == "u8" or kind == "s8" then
    out = rom:bytesU8(a, n)
    if kind == "s8" then for i = 1, n do if out[i] >= 128 then out[i] = out[i] - 256 end end end
  elseif kind == "u16" or kind == "s16" then
    out = rom:bytesU16(a, n)
    if kind == "s16" then for i = 1, n do if out[i] >= 32768 then out[i] = out[i] - 65536 end end end
  elseif kind == "u32" then
    for i = 1, n do out[i] = rom:u32(a + (i - 1) * 4) end
  else
    error("RomTables: kind " .. tostring(kind))
  end
  return out
end

-- r36: code immediates
local FORMS = { [4] = "movs", [5] = "cmp", [6] = "adds", [7] = "subs" }
local function codeImm(rom, at)
  local o = at - 0x08000000
  local h = rom:u16(o)
  local top = math.floor(h / 2048)
  local reg = math.floor(h / 256) % 8
  local v, form
  if FORMS[top] then
    v, form = h % 256, FORMS[top]
    local h2 = rom:u16(o + 2)
    local sh = math.floor(h2 / 64) % 32
    if form == "movs" and math.floor(h2 / 2048) == 0 and h2 % 8 == reg and math.floor(h2 / 8) % 8 == reg
       and sh > 0 and sh < 16 then
      v = v * 2 ^ sh
    end
  elseif top == 9 then
    local la = (at + 4) - (at + 4) % 4 + (h % 256) * 4
    v, form = rom:u32(la - 0x08000000), "ldr"
  end
  return v, form
end
RT.codeImm = codeImm

-- the message routines and the register that carries the message number
-- (r37: + 0x080C94F4 (r1), the room-sprite wrapper 0x080E1058 (r1), the
-- dialogue start 0x080C95C0 (r0) and the player's text 0x080AF4FC (r0))
RT.MSG_CALLS = { [0x080C9164] = 1, [0x080C9564] = 1, [0x080C94F4] = 1, [0x080E1058] = 1,
                 [0x080C95C0] = 0, [0x080AF4FC] = 0 }
local function blTarget(rom, at)
  local o = at - 0x08000000
  local h1, h2 = rom:u16(o), rom:u16(o + 2)
  if math.floor(h1 / 2048) ~= 0x1E or math.floor(h2 / 2048) ~= 0x1F then return nil end
  local off = (h1 % 2048) * 4096 + (h2 % 2048) * 2
  if off >= 0x400000 then off = off - 0x800000 end
  return at + 4 + off
end
RT.blTarget = blTarget

-- does Thumb instruction h write low register r? (r37: every format, so a
-- walk back never steps over a load / ALU op / call into r)
local function writes(h, r)
  local top5, top4, top3 = math.floor(h / 2048), math.floor(h / 4096), math.floor(h / 8192)
  local rd = h % 8
  local r8 = math.floor(h / 256) % 8
  local L = math.floor(h / 2048) % 2 == 1
  if top3 == 0 then return rd == r end                          -- shifts, add / sub (3 regs / imm3)
  if top3 == 1 then return top5 ~= 5 and r8 == r end            -- movs / adds / subs imm8 (not cmp)
  local top6 = math.floor(h / 1024)
  if top6 == 0x10 then                                          -- ALU: tst / cmp / cmn write nothing
    local op = math.floor(h / 64) % 16
    return op ~= 8 and op ~= 10 and op ~= 11 and rd == r
  end
  if top6 == 0x11 then                                          -- hi-register add / mov
    local op = math.floor(h / 256) % 4
    local d = rd + (math.floor(h / 128) % 2) * 8
    return (op == 0 or op == 2) and d == r
  end
  if top5 == 9 then return r8 == r end                          -- ldr pc-relative
  if top4 == 5 then                                             -- ldr / str register offset
    local sbit = math.floor(h / 512) % 2 == 1
    if sbit then return (L or math.floor(h / 1024) % 2 == 1) and rd == r end   -- ldsb / ldrh / ldsh
    return L and rd == r
  end
  if top3 == 3 or top4 == 8 then return L and rd == r end       -- ldr / str immediate offset
  if top4 == 9 then return L and r8 == r end                    -- sp-relative
  if top4 == 0xA then return r8 == r end                        -- add rd, pc / sp
  if top4 == 0xB then                                           -- pop {list}
    return math.floor(h / 256) % 16 >= 0xC and math.floor(h / 2 ^ r) % 2 == 1
  end
  if top4 == 0xC then return L and math.floor(h / 2 ^ r) % 2 == 1 end   -- ldmia
  if top5 == 0x1E or top5 == 0x1F then return r <= 3 end        -- bl: a call clobbers r0-r3
  return false
end
RT.writes = writes

-- the immediate register reg holds at address at: walk back to the
-- instruction that sets it (movs / ldr literal), through `lsls reg, reg, #s`
-- and `adds / subs reg, #n`; nil when it comes from anywhere else (another
-- register, a load, a call) or a branch lies in between
local function regAt(rom, at, reg)
  local shift, add = 0, 0
  for b = at - 2, at - 30, -2 do
    local h = rom:u16(b - 0x08000000)
    local top5 = math.floor(h / 2048)
    local r8 = math.floor(h / 256) % 8
    if top5 == 4 and r8 == reg then return (h % 256) * 2 ^ shift + add, b end
    if top5 == 9 and r8 == reg then
      local la = (b + 4) - (b + 4) % 4 + (h % 256) * 4
      return rom:u32(la - 0x08000000) * 2 ^ shift + add, b
    end
    if top5 == 0 and h % 8 == reg and math.floor(h / 8) % 8 == reg then
      shift = shift + math.floor(h / 64) % 32
    elseif top5 == 6 and r8 == reg then
      add = add + h % 256
    elseif top5 == 7 and r8 == reg then
      add = add - h % 256
    elseif math.floor(h / 4096) == 0xD or top5 == 0x1C or h == 0x4770 or writes(h, reg) then
      return nil   -- a branch, or reg comes from somewhere else
    end
  end
  return nil
end
RT.regAt = regAt

-- the message number a `bl` of a message routine passes (GBA number - 3)
local function msgAt(rom, at)
  local reg = RT.MSG_CALLS[blTarget(rom, at) or 0]
  if not reg then return nil end
  local v = regAt(rom, at, reg)
  return v and v - 3
end
RT.msgAt = msgAt

-- the flat values of one spec (rows flattened row by row)
local function values(rom, s)
  if s.kind == "imm" or s.kind == "msg" then
    local flat = {}
    for i, at in ipairs(s.addr) do
      local v, form
      if s.kind == "msg" then v, form = msgAt(rom, at), "msg" else v, form = codeImm(rom, at) end
      if v ~= nil and s.opts.op and not s.opts.op[form] then v = nil end
      flat[i] = v or false
    end
    return flat, 1
  end
  if type(s.addr) == "table" then
    local cols = {}
    for c, a in ipairs(s.addr) do cols[c] = read(rom, s.kind, a, s.n) end
    local flat = {}
    for i = 1, s.n do for c = 1, #cols do flat[#flat + 1] = cols[c][i] end end
    return flat, #cols
  end
  local w = s.opts.w or 1
  return read(rom, s.kind, s.addr, s.n * w), w
end

function RT.extract(rom, R, check)
  local t = {}
  for _, s in ipairs(RT.SPEC) do
    local flat, w = values(rom, s)
    check(#flat == s.n * w, "rom table %s: %d values", s.name, #flat)
    for i, v in ipairs(flat) do
      check(v ~= false, "rom table %s: site %d (%08X) is not of its form", s.name, i, type(s.addr) == "table" and s.addr[i] or 0)
    end
    local lo, hi = s.opts.lo, s.opts.hi
    for i, v in ipairs(flat) do
      check((lo == nil or v >= lo) and (hi == nil or v <= hi),
            "rom table %s[%d] = %d is outside %s..%s", s.name, i - 1, v, tostring(lo), tostring(hi))
    end
    if s.opts.check then check(s.opts.check(flat), "rom table %s fails its shape check", s.name) end
    -- r37: ref = { {site, delta}, .. }: the code at site loads this table's
    -- address (+ delta) with `ldr rN, [pc]` (ties a table to the code using it)
    for _, r in ipairs(s.opts.ref or {}) do
      local v, form = codeImm(rom, r[1])
      check(form == "ldr" and v == 0x08000000 + s.addr + (r[2] or 0),
            "rom table %s: the code at %08X does not load it", s.name, r[1])
    end
    t[s.name] = { v = flat, w = w }
  end
  return t
end

local function fill(dst, s, rec)
  for k in pairs(dst) do dst[k] = nil end
  local w, v = rec.w, rec.v
  local scale = s.opts.scale or 1
  local add = s.opts.add or 0
  if s.opts.invert then   -- value -> its index (entries equal to opts.skip left out)
    for i = 1, s.n do
      if v[i] ~= s.opts.skip then dst[v[i]] = i - 1 + s.base end
    end
    return
  end
  for i = 1, s.n do
    local key = s.opts.keys and s.opts.keys[i] or (i - 1 + s.base)
    if w == 1 then
      dst[key] = v[i] * scale + add
    else
      local row = {}
      for c = 1, w do row[c] = v[(i - 1) * w + c] * scale + add end
      dst[key] = row
    end
  end
end

-- the live table for name (empty until a cache is bound)
function RT.get(name)
  local t = live[name]
  if not t then t = {}; live[name] = t end
  return t
end

-- fn(t) runs after every bind with the whole imported data.t (modules that
-- build their tables from another module's import, e.g. Menu.RECEIPT_SLOT)
local hooks = {}
function RT.onBind(fn)
  hooks[#hooks + 1] = fn
  if RT.all then fn(RT.all) end   -- a cache already bound
end

-- pour an imported data.t.rt35 into the live tables; a cache without one is
-- an older import (the cacheVersion bump makes the launcher import again)
function RT.bind(rt, all)
  assert(type(rt) == "table", "ALttP cache has no ROM tables (rt35) -- import the ROM again")
  for _, s in ipairs(RT.SPEC) do
    local rec = rt[s.name]
    assert(rec, "ALttP cache is missing ROM table " .. s.name .. " -- import the ROM again")
    fill(RT.get(s.name), s, rec)
  end
  RT.bound, RT.all = rt, all or {}
  for _, fn in ipairs(hooks) do fn(RT.all) end
end

-- the specs (offsets only) live in RomTablesSpec.lua
require("src.zelda.alttp.RomTablesSpec")(S)

return RT
