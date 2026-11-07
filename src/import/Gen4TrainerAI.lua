-- THE TRAINER AI'S SCRIPT, read out of the cartridge (Platinum and
-- HeartGold / SoulSilver).
--
-- WHAT IT IS.  Every Sinnoh / Johto trainer carries an `aiMask` in its trdata
-- record, and each set bit names one program in a table of 32 entry points:
-- Basic, EvalAttack, Expert, SetupFirstTurn, Risky, PrioritizeExtremes,
-- BatonPass, TagStrategy, CheckHP, Weather, Harrassment, 18 unused ones that
-- all point at the same Terminate, then RoamingPokemon, Safari and
-- CatchTutorial.  The programs are a flat array of 32-bit words: opcode,
-- operands, and jumps stored as word offsets relative to the word after the
-- jump (pokeplatinum asm/macros/aicmd.inc: `(\jump-.) / 4 - 1`).
--
-- WHERE IT IS.  NOT in tr_ai_seq.narc as the file name suggests: the table is
-- `gTrainerAITable`, linked straight into the trainer AI overlay after its
-- code (pokeplatinum platinum.us/main.lsf.in, `Overlay trainer_ai`: trainer_ai.c
-- then trainer_ai_script.o).  READ FROM THE ROMS:
--   Platinum (US rev 1)   overlay 14, byte 0x4C84, RAM 0x0221FC20 + 0x4C84
--   HeartGold (US)        overlay 10, byte 0x4C8C, RAM 0x0221BE20 + 0x4C8C
-- and the 10,607 words from the table to Terminate's last word are the SAME
-- in both games (compared word by word; they diverge only at word 10626, past
-- the script, in the overlay's next table).
--
-- HOW IT IS FOUND.  By the table's own shape rather than a fixed address, so a
-- different revision still reads: word 0 is 32 (Basic starts right after the
-- table), and entries 11..28 are one shared value (Terminate).  The script runs
-- to Terminate's PopOrEnd, which is the last word the table names plus the
-- 4..word tail of CatchTutorial; the reader keeps every word up to the highest
-- entry point plus a margin and lets the interpreter stop where the program
-- does.

local Gen4TrainerAI = {}

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function signed(v)
  if v >= 2147483648 then return v - 4294967296 end
  return v
end

-- the 32-entry flag table at byte `at`, or nil
local function tableAt(s, at)
  if u32(s, at) ~= 32 then return nil end
  local t = {}
  for i = 0, 31 do
    local v = u32(s, at + i * 4)
    if not v or v == 0 or v > 0x10000 then return nil end
    t[i] = v
  end
  for i = 12, 28 do
    if t[i] ~= t[11] then return nil end
  end
  return t
end

-- Scan one overlay's bytes for the table; returns the byte offset.
function Gen4TrainerAI.find(bytes)
  if type(bytes) ~= "string" then return nil end
  for at = 0, #bytes - 128, 4 do
    if bytes:byte(at + 1) == 32 and bytes:byte(at + 2) == 0 and tableAt(bytes, at) then
      return at
    end
  end
  return nil
end

-- The program from an overlay's bytes: { words = { [1] = word 0, ... } } with
-- every word signed (jumps go backwards; masks with bit 31 stay bit-exact
-- under LuaJIT's `bit`, which works on signed 32-bit integers anyway).
function Gen4TrainerAI.parse(bytes, at)
  local t = tableAt(bytes, at)
  if not t then return nil end
  local last = 0
  for i = 0, 31 do if t[i] > last then last = t[i] end end
  -- the last program (CatchTutorial) is a handful of words; 64 more is room
  -- for any of them and still well inside the overlay
  local count = math.min(last + 64, math.floor((#bytes - at) / 4))
  local words = {}
  for i = 0, count - 1 do
    words[i + 1] = signed(u32(bytes, at + i * 4))
  end
  local entries = {}
  for i = 0, 31 do entries[i] = t[i] end
  return { words = words, entries = entries, count = count }
end

-- Every overlay of the ROM, first match wins (Platinum 14, HGSS 10).
function Gen4TrainerAI.extract(rom)
  if not (rom and rom.overlay) then return nil end
  for _, first in ipairs({ 14, 10 }) do
    local ok, bytes = pcall(rom.overlay, rom, first)
    local at = ok and Gen4TrainerAI.find(bytes)
    if at then
      local p = Gen4TrainerAI.parse(bytes, at)
      if p then p.overlay, p.offset = first, at return p end
    end
  end
  for id = 0, 160 do
    local ok, bytes = pcall(rom.overlay, rom, id)
    if not ok or not bytes then
      if id > 20 then break end
    else
      local at = Gen4TrainerAI.find(bytes)
      if at then
        local p = Gen4TrainerAI.parse(bytes, at)
        if p then p.overlay, p.offset = id, at return p end
      end
    end
  end
  return nil
end

return Gen4TrainerAI
