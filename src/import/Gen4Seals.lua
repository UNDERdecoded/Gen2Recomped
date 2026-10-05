-- PLATINUM'S BALL SEALS (pokeplatinum src/ball_seal_info.c,
-- src/applications/capsule_menu/main.c, include/data/mart_items.h).
--
-- Two ARM9 tables, found by content:
--
--   sealTypeValues[80]  10 bytes each: u16 memberIdx, u8 nameIndex, u8 unused,
--                       u8 particleIndex, u8 isAlphabetSeal, u16 price,
--                       u8 nonAlphabetIndex, pad. Row 0 is SEAL_DUMMY (0xB8,
--                       price 999), row 1 Heart Seal A (0xB9, price 50).
--   SunyshoreMarketDailyStocks[7]  pointers to seven seal-id lists ended by
--                       0xFFFF, Monday first (MART_SEAL_ID_SUNYSHORE_MONDAY);
--                       Monday opens Heart Seal A (1), Star Seal B (8).
--
-- Seal ids are 1-based (SEAL_DUMMY is 0); the table is indexed by id.
-- Names come from bank 12 (TEXT_BANK_BALL_SEAL_NAMES) and its plural bank 13,
-- entry = nameIndex.
--
-- Runtime: save.gen4Seals = { [id] = count }, the case's loose seals. No
-- capsules are modelled, so "in use" is always zero and
-- SealCase_CountSealOccurrenceAnywhere is the case count. A type caps at 99
-- (MAX_SEALS_PER_TYPE).

local Gen4Seals = {}

Gen4Seals.COUNT = 80
Gen4Seals.STRIDE = 10
Gen4Seals.MAX_PER_TYPE = 99
Gen4Seals.NAME_BANK = 12
Gen4Seals.PLURAL_BANK = 13
Gen4Seals.TABLE_SIGNATURE = string.char(0xB8, 0, 0, 0x25, 0x25, 0, 0xE7, 3, 0, 0, 0xB9, 0, 1)

local function u16(s, at) local a, b = s:byte(at, at + 1) return a and b and a + b * 256 end
local function u32(s, at)
  local a, b = u16(s, at), u16(s, at + 2)
  return a and b and a + b * 65536
end

function Gen4Seals.parseTable(arm9)
  local at = arm9:find(Gen4Seals.TABLE_SIGNATURE, 1, true)
  if not at then return nil, "sealTypeValues not found" end
  local rows = {}
  for i = 0, Gen4Seals.COUNT - 1 do
    local o = at + i * Gen4Seals.STRIDE
    rows[i] = {
      nameIndex = arm9:byte(o + 2),
      alphabet = arm9:byte(o + 5) == 1,
      price = u16(arm9, o + 6),
    }
  end
  return rows
end

function Gen4Seals.parseStocks(arm9, ramBase)
  ramBase = ramBase or 0x02000000
  local function list(p)
    if not p then return nil end
    local at = p - ramBase + 1
    if at < 1 or at > #arm9 then return nil end
    local out = {}
    for i = 0, 15 do
      local v = u16(arm9, at + i * 2)
      if v == 0xFFFF then return #out > 0 and out or nil end
      if not v or v < 1 or v >= Gen4Seals.COUNT then return nil end
      out[#out + 1] = v
    end
  end
  local found, hits
  hits = 0
  for at = 1, #arm9 - 28, 4 do
    local first = list(u32(arm9, at))
    if first and first[1] == 1 and first[2] == 8 then
      local days, ok = { first }, true
      for d = 1, 6 do
        days[d + 1] = list(u32(arm9, at + d * 4))
        if not days[d + 1] then ok = false break end
      end
      if ok then found, hits = days, hits + 1 end
    end
  end
  if hits == 1 then return found end
  return nil, "daily seal stock matches: " .. hits
end

function Gen4Seals.extract(rom)
  local arm9 = rom and rom:arm9()
  if type(arm9) ~= "string" then return nil, "no arm9" end
  local rows, e1 = Gen4Seals.parseTable(arm9)
  local stocks, e2 = Gen4Seals.parseStocks(arm9, rom:header().arm9.ram)
  if not (rows and stocks) then return nil, e1 or e2 end
  return { seals = rows, stocks = stocks }
end

-- -------------------------------------------------------------- runtime --

function Gen4Seals.count(save, id)
  return tonumber(save and save.gen4Seals and save.gen4Seals[tonumber(id)]) or 0
end

-- SealCase_CheckSealCount
function Gen4Seals.canChange(save, id, quantity)
  local have = Gen4Seals.count(save, id)
  if quantity < 0 then return have + quantity >= 0 end
  return have + quantity <= Gen4Seals.MAX_PER_TYPE
end

-- GiveOrTakeSeal: refused (false) rather than clamped.
function Gen4Seals.change(save, id, quantity)
  id = tonumber(id)
  if not id or id < 1 or id >= Gen4Seals.COUNT then return false end
  if not Gen4Seals.canChange(save, id, quantity) then return false end
  save.gen4Seals = save.gen4Seals or {}
  save.gen4Seals[id] = Gen4Seals.count(save, id) + quantity
  return true
end

-- SealCase_CountUniqueSeals: ids 1..79 held at least once.
function Gen4Seals.unique(save)
  local n = 0
  for id = 1, Gen4Seals.COUNT - 1 do if Gen4Seals.count(save, id) > 0 then n = n + 1 end end
  return n
end

-- CalcTotalBallSeals (the Seal Case's bag message)
function Gen4Seals.total(save)
  local n = 0
  for id = 1, Gen4Seals.COUNT - 1 do n = n + Gen4Seals.count(save, id) end
  return n
end

function Gen4Seals.name(data, id, plural)
  local rec = data and data.gen4_seals
  local row = rec and rec.seals and rec.seals[tonumber(id)]
  if not row then return nil end
  local T = require("src.import.Gen4Text")
  return data.text and data.text[T.label(plural and Gen4Seals.PLURAL_BANK or Gen4Seals.NAME_BANK, row.nameIndex)]
end

function Gen4Seals.price(data, id)
  local rec = data and data.gen4_seals
  local row = rec and rec.seals and rec.seals[tonumber(id)]
  return row and row.price or 0
end

return Gen4Seals
