-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S POKE MART STOCK, out of overlay 21 (scrcmd_shop.c).
--
-- Script command 0x149 <var shop, var result> opens a counter's BUY list. Its
-- handler (Black ov21 0x021B38E0) reads three tables:
--
--   * a pointer table of 43 lists, the last thing before the "scrcmd_shop.c"
--     assert name; the handler indexes it from entry 17 (&ptr[17])
--   * a byte table of those lists' lengths, entries 17..42
--   * for shop 255, the regular counter: a byte table badges -> tier
--     (0, 1, 1, 2, 2, 3, 3, 4, 5), and the list is 17 + tier
--
-- Any other shop id is a Center's second clerk: list 17 + 6 + id (special
-- Poke Balls and Mail). Entries 0..16 are the shop code's other records,
-- not stock.
--
-- build(x) -> { tiers = { [badges] = tier }, regular = { [tier] = { items } },
--               specialty = { [id] = { items } }, source = "..." } or nil, why

local M = {}

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

M.FIRST = 17          -- the handler's &ptr[17]
M.SPECIALTY = 6       -- a specialty id is list FIRST + 6 + id
-- what Black reads, should the tables not be found by shape
M.FALLBACK_TIERS = { [0] = 0, 1, 1, 2, 2, 3, 3, 4, 5 }

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local ok, b, info = pcall(function() return rom:overlay(21) end)
  if not (ok and b and info) then return nil, "no overlay 21" end
  local base = info.ram
  local function inOv(v) return v >= base and v < base + #b end

  -- the pointer table: the run of overlay pointers ending at the assert name
  local name = b:find("scrcmd_shop.c", 1, true)
  if not name then return nil, "no scrcmd_shop.c" end
  local endAt = name - 1                 -- 0-based offset of the name
  while endAt % 4 ~= 0 do endAt = endAt - 1 end
  local ptrs, at = {}, endAt - 4
  while at >= 0 and inOv(u32(b, at)) do
    table.insert(ptrs, 1, u32(b, at) - base)
    at = at - 4
  end
  if #ptrs < M.FIRST + 6 then return nil, ("pointer table too short (%d)"):format(#ptrs) end

  -- the lengths: unambiguous for lists FIRST..FIRST+4 from the gap to the
  -- next list start; the byte table is where those five sit in a row
  local starts = {}
  for _, p in ipairs(ptrs) do starts[#starts + 1] = p end
  table.sort(starts)
  local function gap(p)
    for _, s in ipairs(starts) do if s > p then return (s - p) / 2 end end
  end
  local probe = {}
  for i = 0, 4 do
    local g = gap(ptrs[M.FIRST + i + 1])
    if not g or g ~= math.floor(g) or g > 255 then return nil, "list lengths" end
    probe[#probe + 1] = string.char(g)
  end
  local countsAt = b:find(table.concat(probe), 1, true)
  if not countsAt then return nil, "no counts table" end
  countsAt = countsAt - 1
  local function count(index) return b:byte(countsAt + (index - M.FIRST) + 1) end

  local function list(index)
    local p, n = ptrs[index + 1], count(index)
    if not (p and n) then return nil end
    local items = {}
    for k = 0, n - 1 do items[#items + 1] = u16(b, p + k * 2) end
    return items
  end

  -- badges -> tier, by shape: nine bytes 0,1,1,2,2,3,3,4,5
  local tiers = {}
  local tierAt = b:find(string.char(0, 1, 1, 2, 2, 3, 3, 4, 5), 1, true)
  for badges = 0, 8 do
    tiers[badges] = tierAt and b:byte(tierAt + badges) or M.FALLBACK_TIERS[badges]
  end

  local regular, specialty = {}, {}
  for tier = 0, 5 do regular[tier] = list(M.FIRST + tier) end
  for id = 0, #ptrs - 1 - (M.FIRST + M.SPECIALTY) do
    specialty[id] = list(M.FIRST + M.SPECIALTY + id)
  end
  -- the BP counters (shop 0xFE / 0xFD): lists 0 / 1 of the same table, but
  -- 8-byte entries { u16 item, u16 0, u32 BP }, their lengths a byte table
  -- of their own; 0x021B39C4's literal pool holds the two side by side
  -- (table address, then the lengths' address)
  local bp = {}
  local tableAddr = base + endAt - #ptrs * 4
  local lens
  for o = 0, #b - 8, 4 do
    if u32(b, o) == tableAddr and inOv(u32(b, o + 4)) then lens = u32(b, o + 4) - base break end
  end
  for k, shop in pairs(M.BP_LIST) do
    local p, n = ptrs[k + 1], lens and b:byte(lens + k + 1)
    if p and n and n > 0 and n < 128 then
      local items = {}
      for i = 0, n - 1 do items[#items + 1] = { item = u16(b, p + i * 8), price = u32(b, p + i * 8 + 4) } end
      bp[shop] = items
    end
  end
  return {
    tiers = tiers, regular = regular, specialty = specialty, buyers = M.buyers(rom), bp = bp,
    source = ("ROM:ov21 ptr table @%X (%d lists), counts @%X%s"):format(
      endAt - #ptrs * 4, #ptrs, countsAt, tierAt and (", tiers @%X"):format(tierAt - 1) or ", tiers fallback"),
  }
end

-- THE SPECIAL BUYERS (0x14E mode 1 and 0x20E): /a/2/0/8, one member per
-- buyer, entries { u16 item, u16 0, u32 price } -- the price the buyer pays
-- outright. The kind a script names picks the member through ov21's byte
-- table at 0x021D99D0 (kind 0 -> 0, 1 -> 3, 2 -> 2, 3 -> 1): the gourmet
-- maid's foods and Berries, the Rare Bone, the relics and Flutes, the
-- treasures, stones and Gems. Returns { [kind] = { { item, price }... } }
M.BUYER_MEMBER = { [0] = 0, 3, 2, 1 }
function M.buyers(rom)
  local okA, bytes = pcall(function() return rom:read("/a/2/0/8") end)
  if not (okA and bytes) then return nil end
  local okN, arc = pcall(require("src.import.NarcArchive").parse, bytes)
  if not (okN and arc) then return nil end
  local out = {}
  for kind, member in pairs(M.BUYER_MEMBER) do
    local d = member < arc.count and arc:get(member)
    local list = {}
    for o = 0, (d and #d or 0) - 8, 8 do
      list[#list + 1] = { item = u16(d, o), price = u32(d, o + 4) }
    end
    out[kind] = list
  end
  return out
end

-- THE EXCHANGE SERVICE CORNER (the Battle Subway platforms' clerks, scripts
-- 0x8000 = 0xFE / 0xFD into shared script 871, bank 424 #8): 0x149's handler
-- (ov21 0x021B2FD8) does not open the Poke Mart for these two; the shop task
-- (0x021B3258) hands 0xFE to 0x021B39C4 with list 0 and 0xFD with list 1 of
-- the table at 0x021DE164 (counts 0x021D9430), entries { u16 item, u16 0,
-- u32 BP }. READ from Black; caches imported before gen5-marts-bp-v1 have
-- no `bp`, so the same lists are kept here
M.BP_LIST = { [0] = 0xFE, [1] = 0xFD }
local function bpRows(t)
  local out = {}
  for i = 1, #t, 2 do out[#out + 1] = { item = t[i], price = t[i + 1] } end
  return out
end
M.BP_FALLBACK = {
  [0xFE] = bpRows({ 46, 1, 49, 1, 47, 1, 52, 1, 48, 1, 45, 1,
    289, 16, 290, 16, 291, 16, 292, 16, 293, 16, 294, 16, 272, 16, 273, 16,
    214, 32, 271, 32, 545, 32, 546, 32, 542, 32, 547, 32,
    267, 48, 297, 48, 232, 48, 276, 48, 265, 48, 266, 48, 230, 48, 220, 48, 287, 48,
    275, 48, 326, 48, 327, 48, 213, 48, 270, 48, 278, 48, 541, 48, 544, 48, 50, 48 }),
  [0xFD] = bpRows({ 350, 36, 375, 36, 414, 36, 415, 36,
    361, 48, 378, 48, 386, 48, 387, 48, 391, 48, 404, 48 }),
}
function M.bpStock(marts, shop)
  shop = tonumber(shop)
  local t = type(marts) == "table" and type(marts.bp) == "table" and marts.bp[shop]
  return t or M.BP_FALLBACK[shop]
end

-- The stock for one 0x149 call: shop 255 is the regular counter by badges.
function M.stock(marts, shop, badges)
  if type(marts) ~= "table" then return nil end
  shop = tonumber(shop) or 255
  if shop == 255 then
    local tier = (marts.tiers or {})[math.max(0, math.min(8, tonumber(badges) or 0))] or 0
    return (marts.regular or {})[tier]
  end
  return (marts.specialty or {})[shop]
end

return M
