package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local F = dofile("tests/trainer_ai_metadata/fixtures.lua")
local rows, e = F.gen2("gen2")
T.same(F.normalized(rows), {
  {
    index = 1,
    attributes = { 13, 13, 8, 170, 187, 1, 2 },
    items = { "ITEM_013", "ITEM_013" },
    baseMoney = 8,
  },
  { index = 2, attributes = { 0, 19, 12, 204, 221, 4, 0 }, items = { "ITEM_019" }, baseMoney = 12 },
}, "native trainer extraction retains exact seven-byte records and stocked slots")
local attrs, items = e:gen2TrainerAttributes(1)
attrs[1], items[1] = 99, "EXTERNAL"
local again, stock = e:gen2TrainerAttributes(1)
T.eq(again[1], 13, "attribute reads are detached from ROM and other views")
T.eq(stock[1], "ITEM_013", "stock reads are detached")
for _, group in ipairs({ 0, -1, 1.5, 256 }) do
  T.eq(e:gen2TrainerAttributes(group), nil, "invalid class row refused")
end
e.symbol = function()
  return nil
end
T.eq(e:gen2TrainerAttributes(1), nil, "missing attributes do not fabricate native flags")
for _, row in ipairs({
  { 1, 2, 3, 4, 5, 6 },
  { 1, 2, 3, 4, 5, 6, -1 },
  { 1, 2, 3, 4, 5, 6, 256 },
  {
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
  },
}) do
  local invalid = setmetatable({
    symbol = function()
      return { bank = 1, address = 0x4000 }
    end,
    rom = {
      bytes = function()
        return row
      end,
    },
  }, { __index = require("src.import.RomExtractorGen2") })
  T.eq(invalid:gen2TrainerAttributes(1), nil, "incomplete or invalid attribute row refused")
end
local G = require("src.import.RomExtractorGen3")
for _, sym in ipairs({
  { bank = 1, address = 0x7FFF },
  { bank = 0, address = 0x3FFF },
  { bank = 1, address = false },
  { bank = -1, address = 0x4000 },
}) do
  local reads = 0
  local invalid = setmetatable({
    symbol = function()
      return sym
    end,
    rom = {
      bytes = function()
        reads = reads + 1
        return { 0, 0, 0, 0, 0, 0, 0 }
      end,
    },
  }, { __index = require("src.import.RomExtractorGen2") })
  T.eq(invalid:gen2TrainerAttributes(1), nil, "invalid or bank-crossing optional attribute symbols refused")
  T.eq(reads, 0, "invalid optional symbol is refused before reading cartridge bytes")
end
local R = require("src.import.RomGba")
local r = R.new(string.char(1, 2, 3, 4, 4, 0, 255))
T.same(G.itemEffectBytes(r, 0), { 1, 2, 3, 4, 4, 0, 255 }, "raw heal sentinel and battle bits survive")
T.raises(function()
  G.itemEffectBytes(r, -1)
end, "invalid item effect offset", "negative effect offset refused")
T.raises(function()
  G.itemEffectBytes(r, 0.5)
end, "invalid item effect offset", "fractional effect offset refused")
T.raises(function()
  G.itemEffectBytes(R.new(string.char(0, 0, 0, 0, 4, 0)), 0)
end, "past the end", "truncated argument refused")
T.raises(function()
  G.itemEffectBytes(R.new(string.char(0, 0, 0)), 0)
end, "past the end", "truncated header refused")
local source = string.char(9, 8, 7, 6, 24, 0, 123, 77)
T.same(
  G.itemEffectBytes(R.new(source), 0),
  { 9, 8, 7, 6, 24, 0, 123 },
  "two PP bits consume one shared byte without reading the next record"
)
local emitted
local effect = { 1, 0, 0, 0, 4, 224, 20, 255, 2, 3 }
local blob = {}
for i, v in ipairs(effect) do
  blob[i] = string.char(v)
end
local real = R.new(table.concat(blob))
local extractor = setmetatable({
  rom = {
    u8 = function(_, at)
      return real:u8(at - 100)
    end,
    pointer = function(_, at)
      if at == G.ITEM_EFFECTS.TABLE then
        return 100
      end
    end,
  },
  _constants = { itemOrder = { [13] = "ITEM_013" } },
  beginStage = function() end,
  write = function(_, name, value)
    if name == "constants" then
      emitted = value
    end
  end,
}, { __index = G })
extractor:extractItemEffects()
local native = assert(extractor._constants.gen3ItemEffects.ITEM_013)
T.same(native.bytes, effect, "actual item-effects stage publishes raw bytes alongside parsed medicine")
T.eq(native.heal, true, "existing parsed medicine is preserved")
T.eq(native.amount, 20, "existing parsed amount is preserved")
T.same(native.friendship, { -1, 2, 3 }, "signed friendship parser remains intact")
T.eq(emitted, extractor._constants, "the actual stage emits the extended constants record")
local saved = assert(loadstring(require("src.import.LuaWriter").encode(emitted)))()
T.same(saved.gen3ItemEffects.ITEM_013.bytes, effect, "raw bytes survive native cache serialization")
T.finish("native trainer AI import metadata")
