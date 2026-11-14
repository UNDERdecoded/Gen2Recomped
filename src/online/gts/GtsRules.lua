-- The GTS's cartridge rules (docs/online-design.md 2.7a, workstream WS7).
--
--   * A seek names a species, a gender and a level band, as the D/P/Pt
--     GTS's SEEK POKéMON menu does.  You can only SEEK or ASK FOR a species
--     your Pokédex has seen.
--   * Level bands are the cartridge's: ANY, LV 1-10, 11-20 ... 91-100.
--   * An offer must meet every one of the depositor's wants (species, gender,
--     band); the host then trades at once -- there is no "the depositor
--     approves" step on the cartridge.
--   * You cannot deposit an EGG, a mon holding MAIL, your last able party
--     mon, or (HG/SS) the Spiky-eared PICHU.
--
-- Species cross the wire by NATIONAL DEX number (`dex`), never by this
-- engine's species key, so Emerald (names) and FireRed (names) and Platinum
-- (numbers) all agree on what was asked for.  Every screen renders names
-- from its own ROM data.
--
-- Pure apart from `data`/`save` tables handed in.

local GtsRules = {}

GtsRules.BANDS = {
  [0] = { lo = 1, hi = 100, label = "ANY LEVEL" },
}
for i = 1, 10 do
  GtsRules.BANDS[i] = { lo = (i - 1) * 10 + 1, hi = i * 10,
                        label = ("LV %d-%d"):format((i - 1) * 10 + 1, i * 10) }
end
GtsRules.MAX_BAND = 10

GtsRules.GENDERS = { "any", "male", "female" }
GtsRules.GENDER_LABEL = { any = "EITHER", male = "MALE", female = "FEMALE" }
GtsRules.GENDER_MARK = { male = "M", female = "F", none = "", any = "" }

function GtsRules.band(i)
  return GtsRules.BANDS[tonumber(i) or 0] or GtsRules.BANDS[0]
end

function GtsRules.inBand(level, band)
  local b = GtsRules.band(band)
  level = tonumber(level)
  return level ~= nil and level >= b.lo and level <= b.hi
end

local function isInt(v, lo, hi)
  return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end
GtsRules.isInt = isInt

-- ------------------------------------------------------------ species <-> dex

function GtsRules.dexOf(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  if type(def) == "table" and tonumber(def.dex) then return tonumber(def.dex) end
  if type(species) == "number" then return species end
  local n = tonumber(species)
  if n then return n end
  return nil
end

local reverse = setmetatable({}, { __mode = "k" })

-- this data set's species key for a national dex number (forms aside: the
-- base record, the lowest key that carries the number)
function GtsRules.speciesOf(data, dex)
  if type(data) ~= "table" or type(data.pokemon) ~= "table" then return nil end
  local map = reverse[data.pokemon]
  if not map then
    map = {}
    for k, def in pairs(data.pokemon) do
      if type(def) == "table" then
        local d = GtsRules.dexOf(data, k)
        if d and d >= 1 then
          local cur = map[d]
          -- prefer the key equal to the dex, else the first name-keyed one
          if cur == nil or k == d
             or (cur ~= d and type(k) == type(cur) and tostring(k) < tostring(cur)) then
            map[d] = k
          end
        end
      end
    end
    reverse[data.pokemon] = map
  end
  return map[tonumber(dex)]
end

function GtsRules.speciesName(data, dex)
  local key = GtsRules.speciesOf(data, dex)
  local def = key ~= nil and data.pokemon[key]
  if type(def) == "table" and type(def.name) == "string" then return def.name end
  return ("#%03d"):format(tonumber(dex) or 0)
end

-- which genders a species can be: { "any", "male", "female" } trimmed by its
-- ratio (0 = always male, 254 = always female, 255 = genderless) and by
-- generation (Gen 1 has no gender)
function GtsRules.genderOptions(data, dex, gen)
  if (tonumber(gen) or 2) <= 1 then return { "any" } end
  local key = GtsRules.speciesOf(data, dex)
  local def = key ~= nil and data.pokemon[key] or nil
  local r = def and tonumber(def.genderRatio)
  if r == 255 then return { "any" } end
  if r == 0 then return { "any", "male" } end
  if r == 254 then return { "any", "female" } end
  return { "any", "male", "female" }
end

-- ------------------------------------------------------------ the Pokédex

local function seenSet(save)
  local dex = type(save) == "table" and save.pokedex
  return type(dex) == "table" and type(dex.seen) == "table" and dex.seen or {}
end

function GtsRules.hasSeen(save, data, dex)
  local key = GtsRules.speciesOf(data, dex)
  if key == nil then return false end
  local seen = seenSet(save)
  return seen[key] == true or seen[tostring(key)] == true
end

-- every dex number this save has seen and this data set knows, sorted;
-- maxDex trims a pool to its cartridges' species
function GtsRules.seenList(save, data, maxDex)
  local out, have = {}, {}
  for k, v in pairs(seenSet(save)) do
    if v then
      local key = k
      if data.pokemon[key] == nil and tonumber(k) then key = tonumber(k) end
      local d = data.pokemon[key] ~= nil and GtsRules.dexOf(data, key) or nil
      if d and d >= 1 and (not maxDex or d <= maxDex) and not have[d] then
        have[d] = true
        out[#out + 1] = d
      end
    end
  end
  table.sort(out)
  return out
end

-- ------------------------------------------------------------ wants

-- a want / a query as it crosses the wire: { dex, gender, band }
function GtsRules.checkWant(want, maxDex)
  if type(want) ~= "table" then return false, "no request" end
  if not isInt(want.dex, 1, maxDex or 1023) then return false, "bad species" end
  local g = want.gender or "any"
  if g ~= "any" and g ~= "male" and g ~= "female" then return false, "bad gender" end
  if want.band ~= nil and not isInt(want.band, 0, GtsRules.MAX_BAND) then
    return false, "bad level band"
  end
  return true
end

function GtsRules.normalizeWant(want)
  return { dex = want.dex, gender = want.gender or "any", band = want.band or 0 }
end

-- info: { dex, level, gender }: does this mon meet `want`?
function GtsRules.matches(info, want)
  if type(info) ~= "table" or type(want) ~= "table" then return false end
  if tonumber(info.dex) ~= tonumber(want.dex) then return false end
  local g = want.gender or "any"
  if g ~= "any" and info.gender ~= g then return false end
  return GtsRules.inBand(info.level, want.band or 0)
end

function GtsRules.describeWant(data, want, short)
  if type(want) ~= "table" then return "?" end
  local name = GtsRules.speciesName(data, want.dex)
  local g = GtsRules.GENDER_MARK[want.gender or "any"] or ""
  local b = (want.band or 0) == 0 and (short and "" or " ANY LV") or (" " .. GtsRules.band(want.band).label)
  return name .. (g ~= "" and (" " .. g) or "") .. b
end

-- ------------------------------------------------------------ mons

-- the summary a listing shows, from a mon this engine built
function GtsRules.infoOf(data, mon)
  local Pokemon = require("src.pokemon.Pokemon")
  local okG, g = pcall(Pokemon.genderOf, data, mon)
  local okS, shiny = pcall(Pokemon.isShiny, mon)
  return {
    dex = GtsRules.dexOf(data, mon.species),
    level = mon.level,
    gender = okG and (g == "male" or g == "female") and g or "none",
    shiny = okS and shiny == true or false,
    nickname = type(mon.nickname) == "string" and mon.nickname or nil,
    ot = type(mon.ot) == "string" and mon.ot or nil,
  }
end

local function itemName(data, item)
  local def = item ~= nil and data and data.items and data.items[item]
  return type(def) == "table" and type(def.name) == "string" and def.name or ""
end

-- why `mon` (party slot `index`, or nil for a box mon) cannot go into the
-- GTS, or nil when it can
function GtsRules.depositBlocker(save, data, mon, index)
  if type(mon) ~= "table" then return "Nothing there." end
  if mon.isEgg then return "An EGG can't be traded." end
  -- RUN MODES: dead Nuzlocke mons / Soul Link pairs stay home
  local runBlock = require("src.runmodes.RunModes").tradeBlock(mon, save)
  if runBlock then return require("src.runmodes.RunModes").BLOCK_TEXT[runBlock] end
  local held = mon.item or mon.heldItem
  -- the item's own pocket first (Gen 4: "MAIL"), the name only where a cache
  -- has no pocket -- a German cache's mail is "...brief"
  local heldDef = data and data.items and data.items[held]
  if held ~= nil and ((type(heldDef) == "table" and heldDef.pocket == "MAIL")
                      or itemName(data, held):upper():find("MAIL")) then
    return "Remove the MAIL first."
  end
  local CompatRules = require("src.online.CompatRules")
  local GameVersion = require("src.core.GameVersion")
  local fam = CompatRules.familyOf(GameVersion.get())
  if fam == "hgss" and tonumber(mon.species) == 172 and tonumber(mon.form) == 1 then
    return "This POKéMON can't be traded."
  end
  if index then
    local others = 0
    for i, m in ipairs((save and save.party) or {}) do
      if i ~= index and not m.isEgg then others = others + 1 end
    end
    if others == 0 then return "That's your last POKéMON!" end
  end
  return nil
end

return GtsRules
