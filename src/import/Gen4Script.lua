-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) script decoding: bytes to instructions.
--
-- Gen4ScriptOps says how wide every command is.  This walks a real script
-- file with that table and produces instructions -- opcode, name, operand
-- values, and for a jump the absolute target rather than the relative offset
-- the cartridge stores.  Lowering to engine commands comes after this and
-- needs it; nothing here decides what a command MEANS.
--
-- A MEMBER IS NOT A SCRIPT.  /fielddata/script/scr_seq.narc's 1,124 members
-- each hold SEVERAL scripts behind a header of u32 offsets, and the offsets
-- are RELATIVE -- to the position after the offset word, not to the start of
-- the file.  The header ends either at the halfword 0xFD13 or, more often,
-- simply where the first script begins: there is no count.  So the walk stops
-- when the cursor reaches the lowest target it has seen, which is the only
-- rule that works for both shapes.  Reading a count that is not there takes
-- the first script's opcodes as more offsets.
--
-- JUMPS ARE SIGNED AND RELATIVE TO THE END OF THE INSTRUCTION.  `goto` and
-- `call` store a four-byte offset measured from the byte AFTER it -- so the
-- target is (position of the operand) + 4 + offset, and the offset is
-- negative for every backward jump, which is most loops.  Reading it unsigned
-- sends a loop several gigabytes forward and the decode simply stops, which
-- looks like a short script rather than a misread operand.
--
-- WHAT THIS REFUSES TO DO.  Nine commands have no fixed width (see
-- Gen4ScriptOps.VARIABLE_LENGTH).  Reaching one ends the walk with
-- `stopped = "variable"` rather than a guessed skip: a guessed width here is
-- the Sootopolis bug Gen3ScriptOps' header describes, where a two-byte slip
-- lands on a plausible opcode and the decode sails on producing valid-looking
-- nonsense.  Eight scripts in the cartridge end this way.
--
-- HOW THE JUMP FORMULA WAS CHECKED, since a decoder that reads its own output
-- can agree with itself all day.  Starting at every entry point and following
-- every `goto` and `call` TRANSITIVELY reaches 8,567 basic blocks and 78,093
-- instructions -- twice what a linear walk from the entry points alone sees --
-- and of the 15,002 jump operands in them, ZERO point outside their own
-- member.  8,549 of those blocks then decode to a clean `end`.
--
-- That tests two things at once.  A wrong sign or a wrong base would scatter
-- targets to negative numbers and gigabyte offsets, and a wrong operand width
-- anywhere earlier in an instruction would shift the jump operand itself and
-- produce the same mess.  Neither happens.  Four blocks of the 8,567 stop on
-- something unexpected -- two run off the end and two reach an opcode not in
-- the table -- which is 0.05% and is recorded rather than smoothed over.
--
-- MEASURED COVERAGE, which is what makes lowering plannable: 4,079 scripts,
-- 50,835 instructions, 381 distinct opcodes.  The commonest 20 opcodes are
-- 87% of all instructions and fully cover 58% of scripts; the commonest 80
-- are 98.3% and fully cover 89%.  The top of that list is the shape of a
-- conversation -- lockall, faceplayer, message, closemessage, releaseall --
-- so a lowering that starts there gets NPCs talking before it gets anything
-- else working.

local Gen4Script = {}

local Ops = require("src.import.Gen4ScriptOps")
Gen4Script.Ops = Ops

-- The halfword that ends an entry-point header when one is present.
Gen4Script.HEADER_END = 0xFD13

-- Commands whose four-byte operand is a jump, so the decoder can resolve it.
Gen4Script.JUMPS = {
  [0x016] = "goto",
  [0x01A] = "call",
  [0x01C] = "gotoif",
  [0x01D] = "callif",
}

local floor = math.floor

local function u16(s, at)
  local a, b = s:byte(at, at + 1)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = s:byte(at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function i32(s, at)
  local v = u32(s, at)
  if not v then return nil end
  return v < 2147483648 and v or v - 4294967296
end

-- Entry points in a scr_seq member, as 1-based positions into `data`.
function Gen4Script.entries(data)
  if type(data) ~= "string" or #data < 6 then return {} end
  local out, at, lowest = {}, 1, math.huge
  while at + 3 <= #data do
    if u16(data, at) == Gen4Script.HEADER_END then break end
    local rel = i32(data, at)
    if not rel then break end
    local target = at + 4 + rel
    if target < 1 or target > #data then break end
    out[#out + 1] = target
    if target < lowest then lowest = target end
    at = at + 4
    -- The header ends where the first script begins.  There is no count.
    if at >= lowest then break end
  end
  return out
end

-- Decode one script from `at` (1-based).  Returns the instruction list and a
-- reason the walk stopped: "end", "variable", "unknown" or "overrun".
function Gen4Script.decode(data, at)
  if type(data) ~= "string" or type(at) ~= "number" then return nil, "bad arguments" end
  local out, pc = {}, at
  local stopped = "overrun"
  while pc + 1 <= #data do
    local op = u16(data, pc)
    local entry = Ops.COMMANDS[op]
    if not entry then stopped = "unknown"; break end
    -- `sizeAt` rather than `size`: a `*` command whose rule is known resolves
    -- here from its own operand bytes instead of stopping the walk.  Three do
    -- (the field-move flag commands); the other six still stop, and stopping
    -- is still the right answer for them -- see the paragraph in
    -- `Gen4ScriptOps` for what a guessed width costs.
    local spec = Ops.specAt(op, data, pc)
    local size = spec and (Ops.OPCODE_BYTES + Ops.specWidth(spec))
    if not size then
      out[#out + 1] = { at = pc, op = op, name = Ops.name(op), variable = true }
      stopped = "variable"
      break
    end
    local args, o = {}, pc + Ops.OPCODE_BYTES
    for i = 1, #spec do
      local c = spec:sub(i, i)
      if c == "b" then args[#args + 1] = data:byte(o); o = o + 1
      elseif c == "w" then args[#args + 1] = u16(data, o); o = o + 2
      elseif c == "d" then args[#args + 1] = u32(data, o); o = o + 4 end
    end

    local instruction = { at = pc, op = op, name = Ops.name(op), args = args }

    -- A jump's operand is the LAST one, signed, and measured from the byte
    -- after it -- which is pc + size, since the operand ends the instruction.
    local jump = Gen4Script.JUMPS[op]
    if jump then
      local rel = i32(data, pc + size - 4)
      if rel then instruction.target = pc + size + rel end
    end

    out[#out + 1] = instruction
    pc = pc + size
    if Ops.TERMINATORS[op] then stopped = "end"; break end
  end
  return out, stopped
end

-- Every script in one member, keyed by entry-point position.
function Gen4Script.decodeAll(data)
  local out = {}
  for _, at in ipairs(Gen4Script.entries(data)) do
    local instructions, stopped = Gen4Script.decode(data, at)
    out[#out + 1] = { at = at, instructions = instructions, stopped = stopped }
  end
  return out
end

-- A script as readable text, for logs and for looking at one by hand.
function Gen4Script.render(instructions)
  local lines = {}
  for _, ins in ipairs(instructions or {}) do
    local parts = { ("%04X  %s"):format(ins.at, ins.name) }
    if ins.variable then
      parts[#parts + 1] = "<variable length; not decoded>"
    else
      for i, a in ipairs(ins.args or {}) do
        -- Show a jump's resolved target instead of the raw offset.
        if ins.target and i == #ins.args then
          parts[#parts + 1] = ("-> %04X"):format(ins.target)
        else
          parts[#parts + 1] = tostring(a)
        end
      end
    end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  return table.concat(lines, "\n")
end

return Gen4Script
