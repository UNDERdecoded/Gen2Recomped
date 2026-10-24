local F = {}
function F.gen2(backend)
  local Extractor = require("src.import.RomExtractorGen2")
  local Rom = require("src.import.Rom")
  local bytes = {}
  for i = 1, 0xC000 do
    bytes[i] = 255
  end
  local function put(bank, at, values)
    local first = Rom.offset(bank, at) + 1
    for i, value in ipairs(values) do
      bytes[first + i - 1] = value
    end
  end
  put(1, 0x4000, { 0x00, 0x41, 0x05, 0x41 })
  put(1, 0x4100, { 0x50, 0, 5, 4, 255, 0x50, 0, 6, 4, 255 })
  put(1, 0x4200, { 0x80, 0x50, 0x81, 0x50 })
  put(1, 0x4300, { 0, 0, 0 })
  put(2, 0x5000, { 13, 13, 8, 170, 187, 1, 2, 0, 19, 12, 204, 221, 4, 0 })
  local chunks = {}
  for i, value in ipairs(bytes) do
    chunks[i] = string.char(value)
  end
  local symbols = {
    TrainerGroups = { bank = 1, address = 0x4000 },
    Trainers = { bank = 1, address = 0x4100 },
    TrainerClassNames = { bank = 1, address = 0x4200 },
    TrainerEncounterMusic = { bank = 1, address = 0x4300 },
    TrainerClassAttributes = { bank = 2, address = 0x5000 },
  }
  local manifest = {
    constants = {
      trainerClassOrder = { "NONE", "ALPHA", "BETA" },
      trainerClassMembers = { ALPHA = { "ONE" }, BETA = { "ONE" } },
      trainerTypeOrder = { "NORMAL" },
      itemOrder = { [13] = "ITEM_013", [19] = "ITEM_019" },
      moveOrder = {},
      speciesOrder = { "NONE", "A", "B", "C", "CHARMANDER" },
    },
    charmap = { ["128"] = "A", ["129"] = "B" },
  }
  local e = setmetatable(
    { rom = Rom.new(table.concat(chunks)), manifest = manifest, symbols = {} },
    { __index = Extractor }
  )
  e.symbol = function(_, name)
    return symbols[name]
  end
  e.beginStage = function() end
  e.tick = function() end
  e.write = function() end
  e.readBattleTowerRoster = function()
    return nil
  end
  -- Both extractors use their real group/party/attribute readers. Only the
  -- manifest and symbol-table IO are synthetic, not the new field producer.
  if backend == "gen1" then
    return e:extractTrainers().classes, e
  end
  e.constants = function()
    return manifest.constants
  end
  return e:gen2Trainers().byClass, e
end
function F.normalized(rows)
  local out = {}
  for _, row in pairs(rows) do
    out[#out + 1] =
      { index = row.index, attributes = row.attributes, items = row.items, baseMoney = row.baseMoney }
  end
  table.sort(out, function(a, b)
    return a.index < b.index
  end)
  return out
end
function F.effects()
  local out, seen = {}, {}
  local function add(e4, e5)
    local key = e4 .. ":" .. e5
    if seen[key] then
      return
    end
    seen[key] = true
    local bytes = { 3, 0xA2, 0x91, 0xFF, e4, e5 }
    for i = 1, 11 do
      bytes[#bytes + 1] = i * 17
    end
    out[#out + 1] = bytes
  end
  for n = 0, 255 do
    add(n, 0)
    add(0, n)
  end
  for _, e4 in ipairs({ 3, 7, 8, 16, 24, 31, 64, 128, 255 }) do
    for _, e5 in ipairs({ 1, 15, 16, 32, 64, 128, 224, 255 }) do
      add(e4, e5)
    end
  end
  return out
end
return F
