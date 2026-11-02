-- HEARTGOLD / SOULSILVER'S POKEGEAR PHONE CALLS, out of the ROM.
--
-- What src/ui/HgssPhoneCall.lua needs to play a call the way overlay 101 does
-- (pokeheartgold src/application/pokegear/phone/*), all read, none typed in:
--
--   book       `tel/pmtel_book.dat` (phonebook_dat.c AllocAndReadPhoneBook):
--              a u32 count, then 20-byte PhoneBookEntry rows -- id, call
--              TYPE (which handler picks the script), trainer class, trainer,
--              home map, gift, local script, GREETING row (unkC, 0xFF none)
--   scripts    gPhoneCallScriptDef (phone_script_defs.c, overlay 101): 456
--              six-byte rows, msgIds[2] (Ethan / Lyra), u16 kind:4 param0:12,
--              u16 param1. Found by its first four rows (the empty one and
--              Elm's 001..003), which must occur exactly once
--   elmMapScripts  sPhoneCallData_ProfElm_MapScripts (phone_scripts_prof_elm.c):
--              five {scriptType, script} pairs a scripted Elm call indexes
--              with its third operand. Found by its bytes 0,2,0,3,..0,6
--   greetings  sGreetingMsgIDs (phone_generic_headers.c): 8 rows of 12
--              bank-640 entries (time of day x2 + incoming x6, Ethan/Lyra)
--   ink        the call windows' text colours per skin: sub-BG palette slot 1
--              (ov101_021F0388 loads pgphone_gra 4+skin at PLTTBUF_SUB_BG,
--              and both call windows use palette 1, MAKE_TEXT_COLOR(1, 2, 0))
--   texts      bank 271's no-signal "......" (30-32), hang-up "Click!" (33-35)
--              and the Mom savings menu rows (8, 9)
--
-- `build(x)` is the RomExtractorGen4 stage shape (x.rom, x:string); `read(rom,
-- str)` is the same without an extractor, which is what a harness uses.

local N = require("src.import.NarcArchive")
local G = require("src.import.Gen4Graphics")

local P = {}
P.BOOK = "/tel/pmtel_book.dat"
P.OVERLAY = 101
P.SCRIPT_COUNT = 456

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

function P.book(bytes)
  local n = u32(bytes, 0)
  local out = { count = n }
  for i = 0, n - 1 do
    local o = 4 + i * 20
    if o + 20 > #bytes then break end
    out[i] = {
      id = bytes:byte(o + 1), type = bytes:byte(o + 2), trainerClass = bytes:byte(o + 4),
      trainerId = u16(bytes, o + 4), mapId = u16(bytes, o + 6), gift = u16(bytes, o + 8),
      localScript = u16(bytes, o + 10), greeting = bytes:byte(o + 13),
      rematchWeekday = bytes:byte(o + 14), rematchTimeOfDay = bytes:byte(o + 15),
      -- unkF: the random-call group (ov02_02251FDC picks 0 / 1 / 2 at 50 / 30 / 20 %)
      callGroup = bytes:byte(o + 16),
    }
  end
  return out
end

local function unique(hay, needle, what)
  local at = hay:find(needle, 1, true)
  assert(at and not hay:find(needle, at + 1, true), what .. " is not unique in overlay 101")
  return at - 1
end

function P.scripts(ov)
  local anchor = string.rep("\0", 6) .. "\1\2\0\0\0\0" .. "\33\34\0\0\0\0" .. "\35\36\0\0\0\0"
  local at = unique(ov, anchor, "gPhoneCallScriptDef")
  local out = {}
  for i = 0, P.SCRIPT_COUNT - 1 do
    local o = at + i * 6
    local w = u16(ov, o + 2)
    out[i] = { ov:byte(o + 1), ov:byte(o + 2), kind = w % 16, param0 = math.floor(w / 16),
               param1 = u16(ov, o + 4) }
  end
  return out
end

function P.elmMapScripts(ov)
  local at = unique(ov, string.char(0, 2, 0, 3, 0, 4, 0, 5, 0, 6), "Elm's map-script table")
  local out = {}
  for i = 0, 4 do out[i] = { scriptType = ov:byte(at + i * 2 + 1), script = ov:byte(at + i * 2 + 2) } end
  return out
end

function P.greetings(ov)
  local anchor = {}
  for i = 0, 23 do anchor[#anchor + 1] = string.char(i) end
  local at = unique(ov, table.concat(anchor) .. string.char(72, 72, 73, 73), "sGreetingMsgIDs")
  local out = {}
  for row = 0, 7 do
    out[row] = {}
    for k = 0, 11 do out[row][k] = ov:byte(at + row * 12 + k + 1) end
  end
  return out
end

function P.ink(rom)
  local arc = N.parse(assert(rom:read("/a/1/4/6")))
  local out = {}
  for skin = 0, 5 do
    local raw = arc:get(4 + skin)
    if raw and G.isCompressed(raw) then raw = G.decompress(raw) end
    local pal = raw and G.palette(raw)
    if pal then
      -- slot 1: colour 1 the letters, 2 their shadow
      out[skin] = { text = pal[16 + 2], shadow = pal[16 + 3] }
    end
  end
  return out
end

function P.read(rom, str)
  local ov = assert(rom:overlay(P.OVERLAY), "no overlay 101")
  local out = {
    book = P.book(assert(rom:read(P.BOOK), "no " .. P.BOOK)),
    scripts = P.scripts(ov),
    elmMapScripts = P.elmMapScripts(ov),
    greetings = P.greetings(ov),
    ink = P.ink(rom),
    texts = {},
  }
  if str then
    for _, i in ipairs({ 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 30, 31, 32, 33, 34, 35, 37 }) do out.texts[i] = str(271, i) end
  end
  return out
end

function P.build(x)
  return P.read(x.rom, function(bank, i) return x:string(bank, i) end)
end

return P
