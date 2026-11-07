-- A POKEMON FROM ONE GAME, IN ANOTHER GAME'S SHAPE: Pal Park (Gen III -> Gen
-- IV, src/world/Gen4PalPark.lua), Poke Transfer (Gen IV -> Black / White,
-- src/world/Gen5PokeTransfer.lua), and the Monster Walker's catches into
-- either.
--
-- The destination's own records decide everything they can: the species is
-- the National Dex number (WalkerLink.dexOf reads the source's numbering), a
-- move / item / ball is matched by NAME against the destination's tables (a
-- Gen III move by its index, which Gen IV and V kept), and the stats, nature
-- and ability come off the Pokemon's own personality and IVs through
-- Pokemon.applySeed -- so it is the same individual, measured the way the new
-- game measures.

local CG = {}

local function norm(s) return (tostring(s or ""):upper():gsub("[^%w]", "")) end
CG.norm = norm

-- a source game's records, off its own cache (WalkerDelivery's way)
function CG.sourceData(version)
  local Art = require("src.pokewalker.WalkerArt")
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  local out = {}
  for _, name in ipairs({ "pokemon", "items", "moves" }) do
    local src = Art._read(prefix, "data/generated/" .. name .. ".lua")
    local chunk = src and (loadstring or load)(src, "=" .. version .. "/" .. name)
    local ok, rec = false, nil
    if chunk then ok, rec = pcall(chunk) end
    if ok and type(rec) == "table" then out[name] = rec end
  end
  return out
end

-- normalised name -> numeric id, over a number-keyed table
local cacheByName = setmetatable({}, { __mode = "k" })
function CG.byName(tbl)
  if type(tbl) ~= "table" then return {} end
  local hit = cacheByName[tbl]
  if hit then return hit end
  local out = {}
  for id, def in pairs(tbl) do
    if type(id) == "number" and type(def) == "table" and def.name then
      local k = norm(def.name)
      if out[k] == nil or id < out[k] then out[k] = id end
    end
  end
  cacheByName[tbl] = out
  return out
end

-- a source move reference -> its NAME (or the shared numeric id)
function CG.moveRef(src, id)
  local def = src and src.moves and src.moves[id]
  if type(id) == "number" then return id, def and def.name end
  if def and tonumber(def.index) then return tonumber(def.index), def.name end
  local n = tonumber(tostring(id):match("^MOVE_(%d+)$"))
  if n then return n, nil end
  return nil, tostring(id):gsub("^MOVE_", ""):gsub("_", " ")
end

-- the destination's move id for a source move
function CG.moveId(data, src, id)
  local n, name = CG.moveRef(src, id)
  local moves = data.moves or {}
  if name then
    local byName = CG.byName(moves)
    local hit = byName[norm(name)]
    if hit then return hit end
  end
  if n and moves[n] then return n end
  return nil
end

-- the destination's item id for a source item key (number, KEY or name)
function CG.itemId(data, src, key)
  if key == nil or key == 0 then return nil end
  local d = src and src.items and src.items[key]
  local name = (d and d.name) or (type(key) == "string" and key:gsub("^ITEM_", ""):gsub("_", " ")) or nil
  if name then
    local hit = CG.byName(data.items)[norm(name)]
    if hit then return hit end
  end
  if type(key) == "number" and src == nil and data.items and data.items[key] then return key end
  return nil
end

-- the destination's spelling of a source Pokemon's nature: its own name
-- matched without regard to case (the caches spell them LONELY / Lonely), a
-- cartridge number, or the personality's (Gen IV's nature IS personality % 25)
function CG.natureFor(data, raw)
  local order = data and data.constants and data.constants.natureOrder
  if type(order) ~= "table" then return nil end
  if type(raw.nature) == "string" then
    local want = norm(raw.nature)
    for _, n in ipairs(order) do if norm(n) == want then return n end end
  end
  local n = tonumber(raw.nature) or tonumber(raw.ndsNature)
  if n and n >= 0 and n <= 24 then return order[math.floor(n) + 1] end
  if tonumber(raw.personality) then return order[(tonumber(raw.personality) % 25) + 1] end
  return nil
end

local function finish(data, mon, raw)
  local Pokemon = require("src.pokemon.Pokemon")
  local seed = { personality = raw.personality, ivs = raw.ivs }
  if (data.constants or {}).gen == 5 then
    -- POKE TRANSFER KEEPS THE NATURE AND THE ABILITY.  Black / White store
    -- both apart from the personality, and Pokemon.new above already rolled
    -- a B/W nature and ability slot that applySeed would keep
    -- (Pokemon.natureIsOwnField) -- re-rolling 37 of 40 natures in a
    -- Platinum -> Black check.  The Gen IV nature and slot are put back;
    -- applySeed then recomputes the stats from them.
    seed.nature = CG.natureFor(data, raw)
    local slot = tonumber(raw.abilitySlot)
    if slot ~= 1 and slot ~= 2 then
      local def = require("src.pokemon.Gen4Forms").definition(data, mon)
      local list = def and (def.abilityIds or def.abilities)
      local two = type(list) == "table" and list[2] ~= nil and list[2] ~= 0
      slot = (two and tonumber(raw.personality)) and (tonumber(raw.personality) % 2) + 1 or 1
    end
    mon.abilitySlot = slot
  end
  if raw.personality or raw.ivs or seed.nature then
    Pokemon.applySeed(data, mon, seed)
  end
  mon.hp = mon.stats and mon.stats.hp or mon.hp
  return mon
end

-- convert(game, version, src, raw) -> a destination Pokemon, or nil + why.
-- `game` needs `.data` (the destination's records).
function CG.convert(game, version, src, raw)
  local data = game.data
  local Link = require("src.pokewalker.WalkerLink")
  local dex = Link.dexOf(version, raw.species)
  local def = dex and data.pokemon and data.pokemon[dex]
  if not def then return nil, "species" end
  local Growth = require("src.pokemon.Growth")
  local level = tonumber(raw.level)
  if not level and raw.exp then level = Growth.levelForExp(def.growthRate, raw.exp) end
  level = math.max(1, math.min(100, level or 5))
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(data, dex, level)
  if tonumber(raw.exp) then mon.exp = tonumber(raw.exp) end
  mon.evs = raw.evs or mon.evs
  mon.otId, mon.secretId = raw.otId or mon.otId, raw.secretId
  mon.ot = raw.ot or raw.gen3OtName
  mon.nickname = raw.nickname
  mon.happiness = tonumber(raw.happiness or raw.friendship) or mon.happiness
  mon.contest = raw.contest or mon.contest
  mon.pokerus = raw.pokerus or raw.gen3Pokerus
  mon.markings = raw.markings or raw.gen3Markings
  mon.ribbons = raw.ribbons
  mon.form = raw.form or mon.form
  mon.origin = raw.origin or version
  mon.metLevel = level
  mon.item = CG.itemId(data, src, raw.item)
  mon.ball = CG.itemId(data, src, raw.ball) or CG.byName(data.items)[norm("POKE BALL")]
  local moves = {}
  for _, m in ipairs(raw.moves or {}) do
    local id = CG.moveId(data, src, m.id)
    local mdef = id and data.moves[id]
    if mdef then moves[#moves + 1] = { id = id, pp = tonumber(m.pp) or mdef.pp or 0, ppUps = m.ppUps } end
  end
  if #moves > 0 then mon.moves = moves end
  mon.shiny = raw.shiny or nil
  if not mon.shiny and raw.personality and raw.otId and raw.secretId then
    mon.shiny = require("src.pokemon.Stats").isShinyGen3(raw.personality, raw.otId + raw.secretId * 65536) or nil
  end
  return finish(data, mon, raw)
end

-- a Monster Walker catch ({ species = dex, level, gender, moves = names, shiny })
function CG.fromWalker(game, entry)
  local data = game.data
  local dex = tonumber(entry.species)
  if not (dex and data.pokemon and data.pokemon[dex]) then return nil, "species" end
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(data, dex, math.max(1, math.min(100, tonumber(entry.level) or 5)))
  local moves = {}
  for _, name in ipairs(entry.moves or {}) do
    local id = CG.byName(data.moves)[norm(type(name) == "table" and name.name or name)]
    if id then moves[#moves + 1] = { id = id, pp = data.moves[id].pp or 0 } end
  end
  if #moves > 0 then mon.moves = moves end
  if entry.shiny then Pokemon.forceShiny(data, mon) end
  mon.origin = "walker"
  mon.ball = CG.byName(data.items)[norm("POKE BALL")]
  return mon
end

-- withDest(version, fn) -> fn(data)'s answers, with no game running: the
-- destination's records loaded off its cache and the engine pointed at that
-- game for the duration (WalkerDelivery.apply's wrappers), so Pokemon.new,
-- the growth curves and the natures are that game's
function CG.withDest(version, fn)
  local Delivery = require("src.pokewalker.WalkerDelivery")
  local data, why = Delivery.dataset(version)
  if not data then return nil, why end
  local GV = require("src.core.GameVersion")
  local previous = GV.get()
  GV.set(version)
  local ok, a, b = pcall(function()
    return require("src.pokemon.Boxes").withData(data, function()
      return require("src.pokemon.Growth").withTables(data.constants and data.constants.experienceTables, function()
        return require("src.pokemon.Stats").withNatures(data.constants and data.constants.natures, function()
          return fn(data)
        end)
      end)
    end)
  end)
  GV.set(previous)
  if not ok then return nil, tostring(a) end
  return a, b
end

-- read / write a save slot off disk (the launcher's side; WalkerLink's way)
function CG.readSlot(version, slot)
  local SaveData = require("src.core.SaveData")
  local okO, open = pcall(SaveData.slotOpenElsewhere, version, slot)
  if okO and open then return nil, "that save is open in a running game -- save and quit it first" end
  local path = SaveData.slotDiskPath(version, slot)
  local f = path and io.open(path, "rb")
  if not f then return nil, "no save in that slot" end
  local bytes = f:read("*a"); f:close()
  local ok, t = pcall(require("src.core.SaveSerializer").decode, bytes)
  if not (ok and type(t) == "table") then return nil, "the save does not read" end
  return t, bytes
end

function CG.backup(dir, version, slot, bytes)
  if not (bytes and love and love.filesystem) then return end
  local d = ("%s/%s"):format(dir, version)
  love.filesystem.createDirectory(d)
  love.filesystem.write(("%s/%s_%s.lua"):format(d, slot, os.date("%Y%m%d_%H%M%S")), bytes)
end

-- ---------------------------------------------------------------------------
-- the Monster Walker as a source
-- ---------------------------------------------------------------------------

-- its catches, as picker entries
function CG.walkerEntries(game, maxDex)
  local okW, W = pcall(require, "src.pokewalker.Walker")
  if not okW then return {} end
  local okS, st = pcall(W.load)
  if not (okS and st) then return {} end
  local out = {}
  for i, c in ipairs(st.caught or {}) do
    if type(c) == "table" and tonumber(c.species) and (not maxDex or tonumber(c.species) <= maxDex) then
      local def = game.data.pokemon and game.data.pokemon[tonumber(c.species)]
      out[#out + 1] = { walker = i, entry = c, label = (def and def.name) or c.name or "?",
                        level = tonumber(c.level) or 5, species = tonumber(c.species) }
    end
  end
  return out
end

-- take the picked catches off the Walker (highest index first)
function CG.takeWalker(indexes)
  if #indexes == 0 then return true end
  local W = require("src.pokewalker.Walker")
  local st = W.load()
  table.sort(indexes, function(a, b) return a > b end)
  for _, i in ipairs(indexes) do table.remove(st.caught, i) end
  W.save(st)
  return true
end

return CG
