-- Player macros (src/code_0805EC04.c InitPlayerMacro / UpdatePlayerInput,
-- src/script.c SetPlayerMacro / WaitForPlayerMacro): cutscene scripts
-- drive Link with a list of PlayerMacroEntry {u16 flags, u16 keys}.
--   flags >> 14 = 1  JUMPTO: (s16) keys bytes on from this entry
--                 3  END: macro off, no keys
--                 2  IGNORE: skip
--   otherwise    hold `keys` (the GBA key bits) for `flags` frames
-- (playerMacroWaiting counts the low bits down, one frame each).
--
-- The importer (`extract`, Layout.R5_EXTRACT) finds every macro a script
-- passes to SetPlayerMacro (CallWithArg $0807F29D, arg) and copies its
-- entries into manifest.playerMacros[address] = {flags, keys, ...}.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.SET, M.WAIT = 0x0807F29C, 0x0807F2A8
local KEYS = { a = 0x1, b = 0x2, select = 0x4, start = 0x8, right = 0x10, left = 0x20,
               up = 0x40, down = 0x80, r = 0x100, l = 0x200 }

-- ---------------------------------------------------------------------------
-- importer (runs in the import worker)
-- ---------------------------------------------------------------------------
function M.extract(rom, store, manifest)
  local Layout = require("src.zelda.tmc.Layout")
  local out = {}
  local lo, hi = Layout.SCRIPT_LO, Layout.SCRIPT_HI
  local bytes = rom:str(lo, hi - lo)
  -- CallWithArg's function pointer, then its argument
  local pat = string.char(0x9D, 0xF2, 0x07, 0x08)
  local at = 1
  while true do
    local i = bytes:find(pat, at, true)
    if not i then break end
    at = i + 4
    local b1, b2, b3, b4 = bytes:byte(i + 4, i + 7)
    if b4 then
      local ptr = b1 + 256 * b2 + 65536 * b3 + 16777216 * b4
      if ptr >= 0x08000000 and ptr < 0x09000000 and not out[ptr] then
        local list, p = {}, ptr
        for _ = 1, 128 do
          local fl, k = rom:u16(p), rom:u16(p + 2)
          list[#list + 1] = fl; list[#list + 1] = k
          local kind = rshift(fl, 14)
          if kind == 3 then break end
          if kind == 1 then break end -- a jump: the copy keeps its offset (see `step`)
          p = p + 4
        end
        out[ptr] = list
      end
    end
  end
  manifest.playerMacros = out
end

-- ---------------------------------------------------------------------------
-- runtime
-- ---------------------------------------------------------------------------
-- InitPlayerMacro(ptr) (0 = off)
function M.init(field, ptr)
  if not ptr or ptr == 0 then field.playerMacro = nil return end
  local list = field.assets.manifest.playerMacros and field.assets.manifest.playerMacros[ptr]
  if not list then field.playerMacro = nil return end
  field.playerMacro = { list = list, i = 0, waiting = 0, held = 0, prev = 0, base = ptr }
end

-- UpdatePlayerInput's macro branch: the keys held this frame
function M.step(field)
  local m = field.playerMacro
  if not m then return nil end
  if m.waiting == 0 then
    while true do
      local fl, k = m.list[m.i * 2 + 1], m.list[m.i * 2 + 2]
      if not fl then field.playerMacro = nil; return 0 end
      local kind = rshift(fl, 14)
      if kind == 1 then
        local off = k >= 0x8000 and k - 0x10000 or k
        m.i = m.i + math.floor(off / 4)
      elseif kind == 3 then
        field.playerMacro = nil
        return 0
      else
        if kind ~= 2 then m.waiting, m.held = band(fl, 0xFFFF), k end
        m.i = m.i + 1
        break
      end
    end
  end
  m.waiting = band(m.waiting - 1, 0xFFFF)
  return m.held
end

-- an input object (Game.wrapInput's shape) for the held key mask
function M.input(mask, prev)
  return {
    down = function(b) return band(mask, KEYS[b] or 0) ~= 0 end,
    pressed = function(b) local k = KEYS[b] or 0 return band(mask, k) ~= 0 and band(prev or 0, k) == 0 end,
  }
end

-- once a frame from Field:update: returns the input to use (the macro's
-- while one runs, else `input`)
function M.frame(field, input)
  local m = field.playerMacro
  if not m then return input, false end
  local prev = m.prev
  local mask = M.step(field) or 0
  if field.playerMacro then field.playerMacro.prev = mask end
  return M.input(mask, prev), true
end

return M
