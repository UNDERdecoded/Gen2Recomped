-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PASSERBY ANALYTICS' TABLES (overlay 10) -> constants.gen5Passerby.
--
-- READ FROM CODE (Black, ov10):
--   0x214's handler (0x0216B720) names two tables with its first two pc
--   literals: 0x0217219C, one u8 per survey QUESTION -- how many answers it
--   has (30 questions: 2,2,...,17,11) -- and 0x021721BC, 17 u8 answer ids per
--   question (the ids are system bank 0's lines: 1 "Black", 2 "White" ...)
--   right behind them (word aligned) the REQUEST table 0x021723BC, 7 bytes a
--   request (0x0216BB70 .. 0x0216BBC4 read it):
--     [0] kind  1: a timed survey (count passersby within the time limit),
--               0: a total (enough answers to each question, ever)
--     [1] how many questions, [2..4] the questions (0xFF none)
--     [5] the target (kind 0: answers per question; kind 1: 1)
--     [6] the time limit in hours (kind 1)
--   47 requests in Black (0 is an empty placeholder).
-- Found through the command table so White's copy is found the same way.

local M = {}

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

local function segments(rom)
  local segs = {}
  for o = 0, 240 do
    local ok, b, info = pcall(function() return rom:overlay(o) end)
    if ok and b and info then segs[#segs + 1] = { b = b, ram = info.ram, name = "ov" .. o } end
  end
  return segs
end

-- the first `count` pc-relative literals of op's handler
function M.literals(rom, derived, op, count)
  if not (derived and derived.table) then return nil end
  local segs = segments(rom)
  local tseg
  for _, s in ipairs(segs) do if s.name == derived.table.segment then tseg = s end end
  if not tseg then return nil end
  local h = u32(tseg.b, derived.table.at + (op + (derived.offset or 0)) * 4)
  if not h or h == 0 then return nil end
  local addr = h - 1
  local order = { tseg }
  for _, s in ipairs(segs) do if s ~= tseg then order[#order + 1] = s end end
  for _, s in ipairs(order) do
    local a = addr - s.ram
    if a >= 0 and a + 160 <= #s.b and math.floor(u16(s.b, a) / 256) == 0xB5 then
      local out = {}
      for i = 0, 70 do
        local ins = u16(s.b, a + i * 2)
        if math.floor(ins / 2048) == 0x09 then
          local pc = addr + i * 2
          local lit = (math.floor((pc + 4) / 4) * 4) + (ins % 256) * 4
          out[#out + 1] = u32(s.b, lit - s.ram)
          if #out >= count then return out, s end
        end
      end
    end
  end
  return nil
end

function M.build(x, derived)
  local rom = x and x.rom
  if not (rom and derived) then return nil, "no rom" end
  local lits, seg = M.literals(rom, derived, 0x214, 2)
  if not lits then return nil, "no 0x214 handler" end
  local counts, answers = lits[1] - seg.ram, lits[2] - seg.ram
  local b = seg.b
  if counts < 0 or answers < 0 or answers + 17 * 30 > #b then return nil, "tables out of range" end
  local out = { questions = {}, requests = {} }
  local nq = 0
  for q = 0, 31 do
    local n = b:byte(counts + q + 1) or 0
    if n == 0 or n > 17 then break end
    local ids = {}
    for k = 0, n - 1 do ids[k + 1] = b:byte(answers + q * 17 + k + 1) end
    out.questions[q] = ids
    nq = q + 1
  end
  local req = answers + nq * 17
  req = req + (4 - req % 4) % 4
  for id = 0, 255 do
    local at = req + id * 7
    if at + 7 > #b then break end
    local kind, n = b:byte(at + 1), b:byte(at + 2)
    local q = { b:byte(at + 3), b:byte(at + 4), b:byte(at + 5) }
    local good = kind <= 1 and n <= 3
    for k = 1, 3 do if not (q[k] == 255 or q[k] < nq) then good = false end end
    for k = 1, n do if q[k] == 255 then good = false end end
    if not good then break end
    out.requests[id] = { kind = kind, n = n, q = q, target = b:byte(at + 6), hours = b:byte(at + 7) }
  end
  return out
end

return M
