-- PLATINUM'S SUPER CONTEST DATA (pokeplatinum /contest/data/contest_data.narc,
-- read by src/unk_02094EDC.c and overlay017).
--
--   member 0   the NPC contestants, 48 bytes each (UnkStruct_ov6_02248BE8):
--              u32 x2 (acting / dance parameters, kept raw), u16 object
--              graphic, u16, u16 moves[4], u16 species, u16 nickname and OT
--              name (bank 205 entries), u8 cool..sheen, a u16 bitfield --
--              rank (3 bits), the five type flags, "official competition"
--              (single-round contests), "practice", a 2-bit postgame tag (1
--              before the National Dex + game clear only, 2 and 3 after;
--              3 is the special guest), gender (2), and 2 more -- then the
--              dress-up set for each of the 12 visual themes and the fame.
--   member 1   the judges, 8 bytes: u16 name (bank 207), u16 pad, a u16 of
--              five 2-bit type marks (1 a regular, 2 the head judge) and a
--              2-bit rank.
--   member 2   the NPC dress-ups, 84 bytes: 20 x { accessory, x, y, layer }
--              then u8 count, s8 a, s8 b.
--   members 3..14  one 100-byte table per visual theme: each accessory's
--              worth to the dress-up score (ov17_02252A70).
--
-- Written to the cache module `gen4_contest`.

local Gen4ContestData = {}

Gen4ContestData.PATH = "/contest/data/contest_data.narc"

local function u16(s, at) local a, b = s:byte(at, at + 1) return a + b * 256 end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 65536 end
local function s8(v) return v >= 128 and v - 256 or v end
local function bits(v, from, n) return math.floor(v / 2 ^ from) % 2 ^ n end

function Gen4ContestData.parseOpponents(bytes)
  local out = {}
  for i = 0, math.floor(#bytes / 48) - 1 do
    local o = i * 48 + 1
    local flags = u16(bytes, o + 0x20)
    local dress = {}
    for t = 0, 11 do dress[t] = bytes:byte(o + 0x22 + t) end
    out[i] = {
      param0 = u32(bytes, o), param1 = u32(bytes, o + 4),
      gfx = u16(bytes, o + 8), unk0A = u16(bytes, o + 10),
      moves = { u16(bytes, o + 12), u16(bytes, o + 14), u16(bytes, o + 16), u16(bytes, o + 18) },
      species = u16(bytes, o + 20), nameId = u16(bytes, o + 22), otNameId = u16(bytes, o + 24),
      cool = bytes:byte(o + 26), beauty = bytes:byte(o + 27), cute = bytes:byte(o + 28),
      smart = bytes:byte(o + 29), tough = bytes:byte(o + 30), sheen = bytes:byte(o + 31),
      rank = bits(flags, 0, 3),
      types = { bits(flags, 3, 1) == 1, bits(flags, 4, 1) == 1, bits(flags, 5, 1) == 1,
                bits(flags, 6, 1) == 1, bits(flags, 7, 1) == 1 },
      official = bits(flags, 8, 1), practice = bits(flags, 9, 1),
      postgame = bits(flags, 10, 2), gender = bits(flags, 12, 2), unk14 = bits(flags, 14, 2),
      dress = dress, fame = bytes:byte(o + 0x2E),
    }
  end
  return out
end

function Gen4ContestData.parseJudges(bytes)
  local out = {}
  for i = 0, math.floor(#bytes / 8) - 1 do
    local o = i * 8 + 1
    local f = u16(bytes, o + 4)
    out[i] = { nameId = u16(bytes, o),
      types = { bits(f, 0, 2), bits(f, 2, 2), bits(f, 4, 2), bits(f, 6, 2), bits(f, 8, 2) },
      rank = bits(f, 10, 2) }
  end
  return out
end

function Gen4ContestData.parseDressups(bytes)
  local out = {}
  for i = 0, math.floor(#bytes / 84) - 1 do
    local o = i * 84 + 1
    local items = {}
    local count = bytes:byte(o + 80)
    for k = 0, count - 1 do
      local p = o + k * 4
      items[#items + 1] = { accessory = bytes:byte(p), x = bytes:byte(p + 1), y = bytes:byte(p + 2),
                            layer = s8(bytes:byte(p + 3)) }
    end
    out[i] = { items = items, a = s8(bytes:byte(o + 81)), b = s8(bytes:byte(o + 82)) }
  end
  return out
end

function Gen4ContestData.parse(arc)
  if not (arc and arc.count and arc.count >= 15) then return nil, "contest_data.narc missing" end
  local themes = {}
  for t = 0, 11 do
    local b = arc:get(3 + t)
    local row = {}
    for k = 0, #b - 1 do row[k] = b:byte(k + 1) end
    themes[t] = row
  end
  return {
    opponents = Gen4ContestData.parseOpponents(arc:get(0)),
    judges = Gen4ContestData.parseJudges(arc:get(1)),
    dressups = Gen4ContestData.parseDressups(arc:get(2)),
    themes = themes,
  }
end

-- THE ACTING COMPETITION'S TWO TABLES, found by content.
--
--   effects  ARM9 Unk_020F568C (src/unk_02094EDC.c), 24 x 26 bytes, one per
--            contest effect: u16 the move menu's two description lines (bank
--            210), s8 the base appeal (x10; sub_02095734), then five
--            { u16 message (bank 211), u8 its argument count } -- the result
--            lines ov17_02245F14 picks by "variant" (sub_02095790). 0xFFFF is
--            "no line".
--   ai       overlay 17 Unk_ov17_02253C30 (ov17_02246ECC.c), 165 x 12 bytes:
--            u8 the performance position + 1 the row applies to, u8 the
--            condition (one of 28 functions), u8 the moves it weights (240
--            the contest's type, 241 base appeal >= 2 hearts, else an effect
--            id), s8 how the condition's judge marks are used (0 none, 1 as
--            is, 2/3 inverted), s16 x4 the weight by the NPC's AI level.
Gen4ContestData.EFFECTS = 24
Gen4ContestData.EFFECT_SIGNATURE = string.char(0, 0, 1, 0, 0x14, 0, 0, 0, 2, 0, 1, 0, 7, 0, 0xFF, 0xFF, 0, 0)
Gen4ContestData.AI_ROWS = 165
Gen4ContestData.AI_SIGNATURE = string.char(1, 0x14, 0xF0, 1, 0x46, 0, 0x14, 0, 0x14, 0, 0xEC, 0xFF,
                                           1, 0x14, 0x16, 1, 0x64, 0, 0x14, 0, 0x14, 0, 0xEC, 0xFF)

local function s16(s, at) local v = u16(s, at) return v >= 32768 and v - 65536 or v end

function Gen4ContestData.parseEffects(arm9)
  if type(arm9) ~= "string" then return nil end
  local at = arm9:find(Gen4ContestData.EFFECT_SIGNATURE, 1, true)
  if not at then return nil end
  at = at - 26                                  -- CONTEST_EFFECT_NONE is all zero, before it
  local out = {}
  for e = 0, Gen4ContestData.EFFECTS - 1 do
    local o = at + e * 26
    local msgs, args = {}, {}
    for v = 0, 4 do
      msgs[v] = u16(arm9, o + 6 + v * 4)
      args[v] = arm9:byte(o + 8 + v * 4)
    end
    out[e] = { line1 = u16(arm9, o), line2 = u16(arm9, o + 2), appeal = s8(arm9:byte(o + 4)),
               msgs = msgs, args = args }
  end
  return out
end

function Gen4ContestData.parseActingAI(ov)
  if type(ov) ~= "string" then return nil end
  local at = ov:find(Gen4ContestData.AI_SIGNATURE, 1, true)
  if not at then return nil end
  local out = {}
  for r = 0, Gen4ContestData.AI_ROWS - 1 do
    local o = at + r * 12
    out[r + 1] = { position = ov:byte(o), cond = ov:byte(o + 1), target = ov:byte(o + 2),
                   mode = s8(ov:byte(o + 3)),
                   weights = { [0] = s16(ov, o + 4), s16(ov, o + 6), s16(ov, o + 8), s16(ov, o + 10) } }
  end
  return out
end

function Gen4ContestData.extract(rom)
  local bytes = rom and rom:read(Gen4ContestData.PATH)
  if not bytes then return nil, "no contest_data.narc" end
  local out, err = Gen4ContestData.parse(require("src.import.NarcArchive").parse(bytes))
  if out then
    out.effects = Gen4ContestData.parseEffects(rom.arm9 and rom:arm9())
    out.actingAI = Gen4ContestData.parseActingAI(rom.overlay and rom:overlay(17))
  end
  return out, err
end

return Gen4ContestData
